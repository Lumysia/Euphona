"""Trains the timbre head on the extracted examples, reports how it does on held-out speakers,
unseen languages and FLEURS, and exports it as ONNX. (Flow and ease have their own scripts: `flow.py`, `train_ease.py`.)

    uv run python train.py
"""

import json
from collections import defaultdict
from pathlib import Path

import numpy as np
import torch
from scipy.stats import spearmanr
from torch import nn

import dataset
from models import Timbre

OUT = dataset.OUT.parent / "trained"
torch.manual_seed(0)


def balanced_weights(ex: dataset.Examples) -> np.ndarray:
    """Every language counts the same, and within it every gender."""
    groups = defaultdict(int)
    keys = list(zip(ex.language, ex.gender))
    for k in keys:
        groups[k] += 1
    w = np.array([1.0 / groups[k] for k in keys])
    return w / w.mean()


def fit(model: nn.Module, x: np.ndarray, y: np.ndarray, w: np.ndarray, vx, vy, vw,
        epochs=60, lr=2e-3, decay=1e-3, batch=1024) -> nn.Module:
    x, y, w = (torch.tensor(a, dtype=torch.float32) for a in (x, y, w))
    vx, vy, vw = (torch.tensor(a, dtype=torch.float32) for a in (vx, vy, vw))
    optimizer = torch.optim.AdamW(model.parameters(), lr=lr, weight_decay=decay)
    loss = lambda logits, target, weight: (nn.functional.binary_cross_entropy_with_logits(
        logits, target, reduction="none") * weight).mean()
    best, best_state, patience = float("inf"), None, 0
    for epoch in range(epochs):
        model.train()
        for b in torch.randperm(len(x)).split(batch):
            optimizer.zero_grad()
            loss(model.logits(x[b]), y[b], w[b]).backward()
            optimizer.step()
        model.eval()
        with torch.no_grad():
            v = loss(model.logits(vx), vy, vw).item()
        if v < best - 1e-5:
            best, best_state, patience = v, {k: t.clone() for k, t in model.state_dict().items()}, 0
        else:
            patience += 1
            if patience >= 8:
                break
    model.load_state_dict(best_state)
    model.eval()
    print(f"  stopped after {epoch + 1} epochs, val loss {best:.4f}")
    return model


def window_rows(ex: dataset.Examples, weights: np.ndarray):
    x = np.concatenate(ex.windows)
    counts = np.array([len(w) for w in ex.windows])
    y = np.repeat(ex.timbre, counts)
    w = np.repeat(weights / counts, counts) * counts.mean()
    return x, y, w


def timbre_scores(model: Timbre, ex: dataset.Examples) -> np.ndarray:
    with torch.no_grad():
        return np.array([100 * model(torch.tensor(w)).mean().item() for w in ex.windows])


def auc(pos: np.ndarray, neg: np.ndarray) -> float:
    ranks = np.argsort(np.argsort(np.concatenate([pos, neg]))) + 1
    return float((ranks[:len(pos)].sum() - len(pos) * (len(pos) + 1) / 2) / (len(pos) * len(neg)))


def report_timbre(name: str, scores: np.ndarray, ex: dataset.Examples) -> dict:
    recorded = ex.kind == "recorded"
    fem, masc = recorded & (ex.gender == 1), recorded & (ex.gender == 0)
    morph = ex.kind == "morph"
    out = {
        "auc": auc(scores[fem], scores[masc]),
        "feminine_p10_50_90": np.percentile(scores[fem], [10, 50, 90]).round(1).tolist(),
        "masculine_p10_50_90": np.percentile(scores[masc], [10, 50, 90]).round(1).tolist(),
        "saturated_share": float(((scores[recorded] < 5) | (scores[recorded] > 95)).mean()),
        "morph_spearman": float(spearmanr(ex.timbre[morph], scores[morph]).statistic) if morph.any() else None,
    }
    other = recorded & (ex.gender == 2)
    if other.sum() >= 5:
        out["other_gender_p10_50_90"] = np.percentile(scores[other], [10, 50, 90]).round(1).tolist()
    per_language = {l: auc(scores[fem & (ex.language == l)], scores[masc & (ex.language == l)])
                    for l in np.unique(ex.language) if (fem & (ex.language == l)).any() and (masc & (ex.language == l)).any()}
    out["worst_languages"] = sorted(per_language.items(), key=lambda kv: kv[1])[:4]
    print(f"  {name}: " + json.dumps(out, default=lambda v: round(v, 3) if isinstance(v, float) else v))
    return out


def export(model: nn.Module, example: torch.Tensor, path: Path, inputs: str, outputs: str) -> None:
    torch.onnx.export(model, (example,), str(path), input_names=[inputs], output_names=[outputs],
                      dynamic_axes={inputs: {0: "batch"}, outputs: {0: "batch"}}, opset_version=17, dynamo=False)


def main() -> None:
    ex = dataset.load()
    print(f"{len(ex.kind)} examples, {len(np.unique(ex.speaker))} speakers, {len(np.unique(ex.language))} languages")
    weights = balanced_weights(ex)
    train, val = ex.split == "train", ex.split == "val"
    evaluation = {s: ex.subset(ex.split == s) for s in ("test", "unseen", "fleurs") if (ex.split == s).any()}
    OUT.mkdir(parents=True, exist_ok=True)
    report = {}

    print("timbre")
    has = ~np.isnan(ex.timbre) & (ex.gender != 2)
    tx, ty, tw = window_rows(ex.subset(train & has), weights[train & has])
    vx, vy, vw = window_rows(ex.subset(val & has), weights[val & has])
    # Hundreds of thousands of window rows: it needs more than the default epochs to settle.
    timbre = fit(Timbre(), tx, ty, tw, vx, vy, vw, epochs=300)
    for split, sub in evaluation.items():
        report[f"timbre_{split}"] = report_timbre(split, timbre_scores(timbre, sub), sub)

    export(timbre, torch.zeros(8, 192), OUT / "Timbre.onnx", "embeddings", "probabilities")
    (OUT / "report.json").write_text(json.dumps(report, indent=1, default=float))
    print("exported to", OUT)


if __name__ == "__main__":
    main()
