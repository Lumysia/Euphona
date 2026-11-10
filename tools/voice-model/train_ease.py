"""Ease: how little audible strain a voice has, learned from the CAPE-V strain listeners gave in the
Perceptual Voice Qualities Database (PVQD, CC BY 4.0), calibrated on healthy speech.

- Input: the recording's ECAPA embedding statistics (the mean of the normalized window embeddings,
  normalized, and their per-dimension spread), which the app already computes. Ridge regression,
  regularization chosen by 5-fold cross-validation. Voice measures alone (CPPS, HNR, jitter,
  shimmer, spectral balance) were tried first and reached r 0.49-0.63 against 0.74 for these.
- Calibration: PVQD is clinic recordings and ridge shrinks toward its mean, so raw predictions read
  healthy speakers around 19. Ease is therefore measured from healthy speech: predictions up to the
  95th percentile of healthy FLEURS speakers (15 languages, women and men) are ease 100, and the
  median PVQD voice rated 50+ for strain is ease 50. The 95th rather than the 90th: at the 90th,
  healthy women read below 80 four times as often as men (4 % against 1 %).
- Accepted only if healthy women and healthy men each fall below ease 80 (where the score starts to
  count it) at most `HEALTHY_SHARE` of the time, and their medians are within `BIAS_LIMIT`: a strain
  score working through pitch or gender would cost light, feminine voices points for their style.

    uv run --with openpyxl --with pandas python train_ease.py
"""

import json
from concurrent.futures import ProcessPoolExecutor

import numpy as np
import torch

import dataset
from features import Embedder, embedding_statistics, load_audio
from train_quality import DATA, TRAINED, key, ridge

HEALTHY_SHARE = 0.10
BIAS_LIMIT = 5.0
# Where the score starts to count ease (`Scoring.fluentLevel` in the app).
COUNTS_BELOW = 80.0
SEVERE = 50.0
HEALTHY_REFERENCE = 95
ALPHAS = (100, 300, 1000, 3000)

_embedder = {}


def statistics(path):
    if not _embedder:
        _embedder["e"] = Embedder()
    e = _embedder["e"]
    samples = load_audio(path)
    segments = e.speech_segments(samples)
    if not segments:
        return str(path), None
    return str(path), embedding_statistics(e.embed(samples, e.windows(segments)))


class Ease(torch.nn.Module):
    """Embedding statistics -> ease 0-100."""

    def __init__(self, mean, std, weights, bias, reference, gain):
        super().__init__()
        for name, value in (("mean", mean), ("std", std), ("w", weights)):
            self.register_buffer(name, torch.tensor(value, dtype=torch.float32))
        self.bias, self.reference, self.gain = float(bias), float(reference), float(gain)

    def forward(self, features):
        strain = (features - self.mean) / self.std @ self.w + self.bias
        return torch.clamp(100 - torch.clamp(strain - self.reference, min=0) * self.gain, 0, 100).unsqueeze(-1)


def strain_ratings():
    import pandas as pd
    sheet = pd.read_excel(DATA / "Ratings Spreadsheets" / "cape_v_strain_only.xlsx")
    return {key(str(r["File"])): float(r["Average Values"]) for _, r in sheet.iterrows()}


def main():
    cache = DATA / "strain_pvqd_statistics.npz"
    if cache.exists():
        d = np.load(cache)
        paths, x = list(d["paths"]), d["x"]
    else:
        with ProcessPoolExecutor(8) as pool:
            done = [(p, v) for p, v in pool.map(statistics, sorted((DATA / "Audio Files").glob("*.wav"))) if v is not None]
        paths, x = [p for p, _ in done], np.stack([v for _, v in done])
        np.savez(cache, paths=paths, x=x)
    ratings = strain_ratings()
    keep = [i for i, p in enumerate(paths) if key(p.split("/")[-1]) in ratings]
    x, y = x[keep].astype(np.float64), np.array([ratings[key(paths[i].split("/")[-1])] for i in keep])

    ex = dataset.load()
    healthy = (ex.split == "fleurs") & (ex.kind == "recorded") & (ex.gender != 2)
    hx = np.stack([embedding_statistics(ex.windows[i]) for i in np.flatnonzero(healthy)])
    women = ex.gender[healthy] == 1

    mean, std = x.mean(0), x.std(0) + 1e-6
    z, hz = (x - mean) / std, (hx - mean) / std
    folds = np.random.default_rng(0).permutation(len(y)) % 5
    cross = {}
    for alpha in ALPHAS:
        pred = np.zeros(len(y))
        for f in range(5):
            w = ridge(z[folds != f], y[folds != f], alpha)
            pred[folds == f] = np.c_[z[folds == f], np.ones((folds == f).sum())] @ w
        cross[alpha] = (float(np.corrcoef(pred, y)[0, 1]), pred)
    alpha = max(cross, key=lambda a: cross[a][0])
    r, pred = cross[alpha]
    w = ridge(z, y, alpha)
    healthy_strain = np.c_[hz, np.ones(len(hz))] @ w
    reference = float(np.percentile(healthy_strain, HEALTHY_REFERENCE))
    gain = 50 / max(float(np.median(pred[y >= SEVERE])) - reference, 1e-6)

    def ease(strain):
        return np.clip(100 - np.clip(strain - reference, 0, None) * gain, 0, 100)

    healthy_ease = ease(healthy_strain)
    report = {
        "recordings": len(y), "alpha": alpha, "cv_r": r, "reference": reference, "gain": gain,
        "pvqd_ease_by_rated_strain": {f"{lo}-{hi}": np.percentile(ease(pred[(y >= lo) & (y < hi)]), [10, 50, 90]).round(1).tolist()
                                      for lo, hi in ((0, 10), (10, 25), (25, 50), (50, 101))},
        "healthy_women_below_80": float((healthy_ease[women] < COUNTS_BELOW).mean()),
        "healthy_men_below_80": float((healthy_ease[~women] < COUNTS_BELOW).mean()),
        "healthy_strain_median_women_men": [float(np.median(healthy_strain[women])), float(np.median(healthy_strain[~women]))],
    }
    report["accepted"] = bool(max(report["healthy_women_below_80"], report["healthy_men_below_80"]) <= HEALTHY_SHARE
                              and abs(np.subtract(*report["healthy_strain_median_women_men"])) < BIAS_LIMIT)
    print(json.dumps(report, indent=1, default=float))
    (TRAINED / "ease_report.json").write_text(json.dumps(report, indent=1, default=float))
    if not report["accepted"]:
        raise SystemExit("ease failed the healthy-voice check; not exported")
    model = Ease(mean, std, w[:-1], w[-1], reference, gain).eval()
    torch.onnx.export(model, (torch.zeros(1, x.shape[1]),), str(TRAINED / "Ease.onnx"),
                      input_names=["features"], output_names=["ease"],
                      dynamic_axes={"features": {0: "batch"}, "ease": {0: "batch"}}, opset_version=17, dynamo=False)
    print("exported", TRAINED / "Ease.onnx")


if __name__ == "__main__":
    main()
