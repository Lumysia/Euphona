"""Voice Quality: predicts the CAPE-V overall severity listeners gave in the Perceptual Voice Qualities
Database (PVQD, CC BY 4.0; 296 speakers, 3-4 raters twice each) from voice quality measures.

    uv run --with openpyxl --with pandas python train_quality.py
"""

import json
import re
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
import torch

import voice_quality
from extract import OUT as EXAMPLES
from features import Embedder, load_audio

DATA = EXAMPLES.parent / "pvqd"
TRAINED = EXAMPLES.parent / "trained"
# Measures that describe the voice itself, not who is speaking or how loud the microphone is.
USED = ("hnr_db", "cpps_db", "jitter_local", "jitter_rap", "jitter_ppq5", "shimmer_local", "shimmer_apq3",
        "shimmer_apq5", "f0_cv", "voiced_fraction", "intensity_iqr")
COLUMNS = [voice_quality.NAMES.index(n) for n in USED]
# Above this predicted severity a recording is flagged; CAPE-V's mild-to-moderate boundary.
SEVERITY_LINE = 35.0

_tools = {}


def measure(path: Path):
    if not _tools:
        from prosody import Prosody
        _tools["vad"], _tools["f0"] = Embedder(), Prosody()
    samples = load_audio(path)
    segments = _tools["vad"].speech_segments(samples)
    if not segments:
        return path.stem, None
    hz, confidence = (x[0] for x in _tools["f0"].f0.run(None, {"input_audio": samples[None, :]}))
    return path.stem, voice_quality.measures(samples, segments, hz, confidence)


def ratings() -> dict[str, float]:
    import pandas as pd
    sheet = pd.read_excel(DATA / "Ratings Spreadsheets" / "cape_v_severity_only.xlsx")
    return {key(str(r["File"])): float(r["Average Values"]) for _, r in sheet.iterrows()}


def key(name: str) -> str:
    """The participant id at the start of a file name or rating row, such as PT023 or SJ30006."""
    match = re.match(r"\s*([A-Za-z]+\d+)", name)
    return match.group(1).upper() if match else name.strip().upper()


class Health(torch.nn.Module):
    def __init__(self, mean, std, weights, bias):
        super().__init__()
        self.register_buffer("mean", torch.tensor(mean, dtype=torch.float32))
        self.register_buffer("std", torch.tensor(std, dtype=torch.float32))
        self.register_buffer("w", torch.tensor(weights, dtype=torch.float32))
        self.register_buffer("b", torch.tensor(bias, dtype=torch.float32))

    def forward(self, features):
        z = torch.clamp((features - self.mean) / self.std, -6, 6)
        return torch.clamp(z @ self.w + self.b, 0, 100).unsqueeze(-1)


def ridge(x, y, alpha):
    a = np.c_[x, np.ones(len(x))]
    penalty = alpha * np.eye(a.shape[1]); penalty[-1, -1] = 0
    return np.linalg.solve(a.T @ a + penalty, a.T @ y)


def main():
    files = sorted((DATA / "Audio Files").glob("*.wav"))
    cache = DATA / "measures.npz"
    if cache.exists():
        d = np.load(cache)
        stems, values = list(d["stems"]), d["values"]
    else:
        with ProcessPoolExecutor(6) as pool:
            done = [(s, v) for s, v in pool.map(measure, files) if v is not None]
        stems, values = [s for s, _ in done], np.stack([v for _, v in done])
        np.savez(cache, stems=stems, values=values)
    severity = ratings()
    keep = [i for i, s in enumerate(stems) if key(s) in severity and np.all(np.isfinite(values[i, COLUMNS]))]
    x = values[keep][:, COLUMNS].astype(np.float64)
    y = np.array([severity[key(stems[i])] for i in keep])
    print(f"{len(keep)} of {len(stems)} recordings with ratings and finite measures; severity mean {y.mean():.1f}")

    # Robust standardization; clip so one odd measure cannot dominate.
    mean, std = np.median(x, 0), np.percentile(x, 75, 0) - np.percentile(x, 25, 0) + 1e-9
    z = np.clip((x - mean) / std, -6, 6)
    rng = np.random.default_rng(0)
    folds = rng.permutation(len(y)) % 5
    best = None
    for alpha in (0.3, 1, 3, 10, 30, 100):
        pred = np.zeros(len(y))
        for f in range(5):
            w = ridge(z[folds != f], y[folds != f], alpha)
            pred[folds == f] = np.c_[z[folds == f], np.ones((folds == f).sum())] @ w
        pred = np.clip(pred, 0, 100)
        r = np.corrcoef(pred, y)[0, 1]
        mae = np.abs(pred - y).mean()
        flagged, actual = pred >= SEVERITY_LINE, y >= SEVERITY_LINE
        print(f"  alpha {alpha:5}: r {r:.3f}, MAE {mae:.1f}, flags {flagged.mean():.2f} (sensitivity "
              f"{(flagged & actual).sum() / max(actual.sum(), 1):.2f}, specificity {(~flagged & ~actual).sum() / max((~actual).sum(), 1):.2f})")
        if best is None or r > best[0]:
            best = (r, alpha, mae)
    r, alpha, mae = best
    w = ridge(z, y, alpha)
    print("weights", dict(zip(USED, np.round(w[:-1], 2))), "bias", round(w[-1], 1))
    model = Health(mean, std, w[:-1], w[-1]).eval()
    TRAINED.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(model, (torch.zeros(1, len(USED)),), str(TRAINED / "VoiceQuality.onnx"),
                      input_names=["features"], output_names=["severity"],
                      dynamic_axes={"features": {0: "batch"}, "severity": {0: "batch"}}, opset_version=17, dynamo=False)
    (TRAINED / "quality_report.json").write_text(json.dumps(
        {"recordings": len(y), "cv_r": r, "cv_mae": mae, "alpha": alpha, "features": USED,
         "severity_line": SEVERITY_LINE}, indent=1))


if __name__ == "__main__":
    main()
