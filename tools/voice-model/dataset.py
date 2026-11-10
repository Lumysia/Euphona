"""The extracted examples, split by speaker, with a few whole languages held out."""

import hashlib
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from extract import OUT

# Never trained on: shows how the models do on a language they have not heard.
HELD_OUT_LANGUAGES = ("ka", "sw", "uk", "yue", "eu")


@dataclass
class Examples:
    language: np.ndarray
    speaker: np.ndarray
    gender: np.ndarray
    kind: np.ndarray
    timbre: np.ndarray
    windows: list[np.ndarray]  # per example, (n, 192) float32
    split: np.ndarray  # train, val, test (held-out speakers), unseen (held-out languages), fleurs

    def subset(self, mask: np.ndarray) -> "Examples":
        index = np.flatnonzero(mask)
        return Examples(*(getattr(self, f)[index] for f in
                          ("language", "speaker", "gender", "kind", "timbre")),
                        [self.windows[i] for i in index], self.split[index])


def speaker_split(speaker: str) -> str:
    bucket = int(hashlib.sha1(speaker.encode()).hexdigest(), 16) % 10
    return "val" if bucket == 0 else "test" if bucket == 1 else "train"


def load(directory: Path = OUT) -> Examples:
    parts = {k: [] for k in ("language", "speaker", "gender", "kind", "timbre")}
    windows, split = [], []
    for path in sorted(directory.glob("*.npz")):
        d = np.load(path)
        language = str(d["language"])
        n = len(d["kind"])
        parts["language"].append(np.full(n, language))
        for key in ("speaker", "gender", "kind", "timbre"):
            parts[key].append(d[key])
        e, o = d["embeddings"].astype(np.float32), d["offsets"]
        windows += [e[o[i]:o[i + 1]] for i in range(n)]
        if path.name.startswith("fleurs-"):
            split += ["fleurs"] * n
        else:
            split += ["unseen" if language in HELD_OUT_LANGUAGES else speaker_split(s) for s in d["speaker"]]
    joined = {k: np.concatenate(v) for k, v in parts.items()}
    return Examples(**joined, windows=windows, split=np.array(split))
