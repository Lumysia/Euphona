"""Turns Common Voice speakers into timbre training examples: window embeddings and labels.

Each speaker's clips are joined into one recording (about the length of a short reading). Every
recording yields three variants: as recorded, vocoded within natural range, and morphed along the
timbre scale. Speakers who gave another gender are kept as recorded, for evaluation only. Audio is never stored; one .npz per language holds everything training needs.

    uv run python extract.py [languages...]      # default: every language with 20+ speakers per gender
"""

import json
import random
import subprocess
import sys
from collections import defaultdict
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np
import torch

import augment
import common_voice
from features import PATCH_SAMPLES, SAMPLE_RATE, Embedder

SPEAKERS_PER_GENDER = 100
OTHER_SPEAKERS = 20
CLIPS_PER_SPEAKER = 3
MIN_SPEAKERS = 20
TRAIN_STRIDE = SAMPLE_RATE  # one window per second; neighbouring windows add little
OUT = common_voice.DATA.parent / "examples"

KINDS = ("recorded", "vocoded", "morph")


def decode(mp3: bytes) -> np.ndarray:
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", "pipe:0", "-ac", "1", "-ar", str(SAMPLE_RATE),
                          "-f", "s16le", "-"], input=mp3, check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0


def pcm16(x: np.ndarray) -> np.ndarray:
    return np.clip(np.round(x * 32767), -32768, 32767).astype(np.float32) / 32768.0


_worker = {}


def _vad() -> Embedder:
    if not _worker:
        _worker["vad"] = Embedder()
    return _worker["vad"]


def variant(audio: np.ndarray, kind: str, timbre: float):
    vad = _vad()
    audio = pcm16(audio)
    segments = vad.speech_segments(audio)
    if not segments:
        return None
    windows = vad.windows(segments, TRAIN_STRIDE)
    keep = windows.lengths >= SAMPLE_RATE // 2
    crops = [audio[s:s + n] for s, n in zip(windows.starts[keep], windows.lengths[keep])]
    if not crops:
        return None
    return dict(kind=kind, timbre=timbre, crops=crops)


def make_unit(job):
    speaker, gender, mp3s, seed = job
    rng = np.random.default_rng(seed)
    gap = np.zeros(int(0.3 * SAMPLE_RATE), np.float32)
    parts = []
    for mp3 in mp3s:
        parts += [decode(mp3), gap]
    audio = np.concatenate(parts)
    if gender not in (0, 1):
        v = variant(audio, "recorded", np.nan)
        return speaker, gender, [v] if v else []
    feminine = gender == 1
    base = augment.TIMBRE_HIGH if feminine else augment.TIMBRE_LOW
    maybe_channel = lambda x: augment.channel(x, rng) if rng.random() < 0.5 else x
    world = augment.World.analyze(audio)
    morphed, label = augment.morph(world, feminine, rng)
    variants = [
        variant(maybe_channel(audio), "recorded", base),
        variant(maybe_channel(augment.natural(world, rng)), "vocoded", base),
        variant(maybe_channel(morphed), "morph", label),
    ]
    return speaker, gender, [v for v in variants if v]


class Encoder:
    """SpeechBrain ECAPA on the GPU: the same weights as the app's ECAPA (cosine ~0.996)."""

    def __init__(self) -> None:
        from speechbrain.inference.speaker import EncoderClassifier
        self.device = "mps" if torch.backends.mps.is_available() else "cpu"
        self.model = EncoderClassifier.from_hparams(
            "speechbrain/spkrec-ecapa-voxceleb", savedir=str(OUT.parent / "speechbrain-ecapa"),
            run_opts={"device": self.device})

    def __call__(self, crops: list[np.ndarray]) -> np.ndarray:
        out = np.zeros((len(crops), 192), np.float32)
        by_length = defaultdict(list)
        for i, c in enumerate(crops):
            by_length[len(c)].append(i)
        with torch.no_grad():
            for length, indices in by_length.items():
                for b in range(0, len(indices), 128):
                    chunk = indices[b:b + 128]
                    batch = torch.from_numpy(np.stack([crops[i] for i in chunk])).to(self.device)
                    out[chunk] = self.model.encode_batch(batch).squeeze(1).cpu().numpy()
        return out


def choose(language: str, rng: random.Random):
    rows = defaultdict(list)
    for split in common_voice.SPLITS:
        for row in common_voice.metadata(language, split):
            rows[(row["client_id"], split)].append(row)
    by_gender = defaultdict(list)
    for (speaker, split), items in rows.items():
        gender = common_voice.GENDERS.get(items[0].get("gender"), 2 if items[0].get("gender") else None)
        if gender is not None:
            by_gender[gender].append((speaker, split, items))
    wanted = []
    for gender, speakers in by_gender.items():
        rng.shuffle(speakers)
        limit = SPEAKERS_PER_GENDER if gender in (0, 1) else OTHER_SPEAKERS
        for speaker, split, items in speakers[:limit]:
            rng.shuffle(items)
            wanted.append((speaker, split, gender, [r["path"] for r in items[:CLIPS_PER_SPEAKER]]))
    return wanted


def extract(language: str, encoder: Encoder, pool: ProcessPoolExecutor) -> None:
    target = OUT / f"cv-{language}.npz"
    if target.exists():
        return
    rng = random.Random(language)
    wanted = choose(language, rng)
    audio = {}
    for split in common_voice.SPLITS:
        names = {p for s, sp, g, paths in wanted if sp == split for p in paths}
        for name, data in common_voice.clips(language, split, names):
            audio[name] = data
    jobs = [(speaker, gender, [audio[p] for p in paths if p in audio], rng.randrange(1 << 30))
            for speaker, split, gender, paths in wanted]
    jobs = [j for j in jobs if j[2]]

    columns = defaultdict(list)
    embeddings, offsets = [], [0]
    for speaker, gender, variants in pool.map(make_unit, jobs, chunksize=2):
        for v in variants:
            vectors = encoder(v["crops"])
            embeddings.append(vectors.astype(np.float16))
            offsets.append(offsets[-1] + len(vectors))
            columns["speaker"].append(speaker)
            columns["gender"].append(gender)
            for key in ("kind", "timbre"):
                columns[key].append(v[key])
    OUT.mkdir(parents=True, exist_ok=True)
    np.savez_compressed(
        target, language=language, embeddings=np.concatenate(embeddings), offsets=np.array(offsets),
        speaker=np.array(columns["speaker"]), gender=np.array(columns["gender"]),
        kind=np.array(columns["kind"]), timbre=np.array(columns["timbre"], np.float32))
    counts = defaultdict(int)
    for g in columns["gender"]:
        counts[int(g)] += 1
    print(language, f"{len(jobs)} speakers", dict(counts), f"{offsets[-1]} windows", flush=True)


if __name__ == "__main__":
    languages = sys.argv[1:]
    if not languages:
        counts = json.loads((common_voice.DATA / "speaker_counts.json").read_text())
        languages = [l for l, (m, f) in sorted(counts.items(), key=lambda kv: -min(kv[1]))
                     if min(m, f) >= MIN_SPEAKERS]
    encoder = Encoder()
    with ProcessPoolExecutor(max_workers=8) as pool:
        for language in languages:
            for attempt in range(3):
                try:
                    extract(language, encoder, pool)
                    break
                except Exception as error:
                    print(language, f"failed (attempt {attempt + 1}):", repr(error), flush=True)
