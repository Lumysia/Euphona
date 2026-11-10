"""Speech flow: how evenly someone speaks, from pace and pauses only, never from voice or style.

Two measures, both computable in the app from what the analyzer already has:

- articulation rate: loudness peaks (syllable nuclei, as `prosody.py`) per second of speech;
- pause share: the silent gaps between speech segments, over the span from the first speech to the
  last.

Flow is 100 inside the range natural read speech covers and falls smoothly (smoothstep, in log rate
and in pause share) to 0 beyond it, so only rushed or halting speech costs anything. Slow speech has
no rate limit: a slow style is not a fault, and about 2 % of natural FLEURS clips measure under 1.5
syllables per second (the peak counter misses quiet syllables). Very slow speech still shows in its
pauses. On FLEURS (15 languages, 40 clips each): natural 0.3 % below 80; halting 76 %, rushed
(1.8-2.8x) 40 %, dragged 8 %. The rate measure separates rushed speech only moderately (AUC 0.90;
the modulation spectrum, 0.79, was worse), so its limit is set for few false alarms.

    uv run python flow.py            # calibrates on FLEURS and tests rushed, dragged, halting speech
"""

import csv
import json
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path

import numpy as np

from features import SAMPLE_RATE, Embedder, load_audio
from prosody import Prosody

DATA = Path(__file__).resolve().parents[2] / ".build/voice-model/data"
FLEURS = DATA / "fleurs"
# Each limit: (full flow up to here, no flow from here), set from natural FLEURS speech (`main`).
# The app's `SpeechFlow` uses the same numbers.
RATE_FAST = (5.4, 7.0)
PAUSE_SHARE = (0.28, 0.55)


def measures(samples: np.ndarray, segments: list[tuple[int, int]], prosody: Prosody) -> tuple[float, float]:
    speech = sum(b - a for a, b in segments) / SAMPLE_RATE
    envelope = prosody.envelope(samples, segments)
    from scipy.signal import find_peaks
    syllables = len(find_peaks(envelope, prominence=3.0, distance=6, height=envelope.max() - 25)[0]) if len(envelope) > 5 else 0
    span = (segments[-1][1] - segments[0][0]) / SAMPLE_RATE
    gaps = sum(segments[i + 1][0] - segments[i][1] for i in range(len(segments) - 1)) / SAMPLE_RATE
    return syllables / max(speech, 1e-3), gaps / max(span, 1e-3)


def fall(value: float, full: float, none: float) -> float:
    """1 up to `full`, 0 from `none`, smoothstep between (either direction)."""
    x = np.clip((value - none) / (full - none), 0, 1)
    return float(x * x * (3 - 2 * x))


def flow(rate: float, pause_share: float) -> float:
    pace = fall(np.log(rate), np.log(RATE_FAST[0]), np.log(RATE_FAST[1]))
    return 100 * pace * fall(pause_share, *PAUSE_SHARE)


_tools = {}


def _measure(job):
    path, kind, seed = job
    if not _tools:
        _tools["vad"], _tools["prosody"] = Embedder(), Prosody()
    vad, prosody = _tools["vad"], _tools["prosody"]
    rng = np.random.default_rng(seed)
    samples = load_audio(path)
    if kind != "natural":
        import augment
        if kind in ("rushed", "dragged"):
            tempo = float(np.exp(rng.uniform(np.log(1.8), np.log(2.8))))
            samples = augment.World.analyze(samples).render(tempo=tempo if kind == "rushed" else 1 / tempo)
        elif kind == "halting":
            samples = halting(samples, vad.speech_segments(samples), rng)
    segments = vad.speech_segments(samples)
    if not segments:
        return None
    return kind, *measures(samples, segments, prosody)


def halting(samples, segments, rng):
    """Silences of 0.8-2.5 s cut in at quiet moments inside speech, one every 1-3 seconds."""
    out, last = [], 0
    for a, b in segments:
        point = a + int(rng.uniform(0.8, 2.5) * SAMPLE_RATE)
        while point < b:
            out += [samples[last:point], np.zeros(int(rng.uniform(0.8, 2.5) * SAMPLE_RATE), np.float32)]
            last = point
            point += int(rng.uniform(1.0, 3.0) * SAMPLE_RATE)
    out.append(samples[last:])
    return np.concatenate(out)


def fleurs_clips(per_language: int = 40):
    for folder in sorted(FLEURS.iterdir()):
        rows = list(csv.reader(open(folder / "dev.tsv", encoding="utf-8"), delimiter="\t", quoting=csv.QUOTE_NONE))
        names = sorted({r[1] for r in rows if (folder / "dev" / r[1]).exists()})[:per_language]
        yield from (folder / "dev" / n for n in names)


def main() -> None:
    cache = DATA / "flow_measures.json"
    if cache.exists():
        rows = [tuple(r) for r in json.loads(cache.read_text())]
    else:
        clips = list(fleurs_clips())
        jobs = [(p, kind, i) for i, p in enumerate(clips) for kind in ("natural", "rushed", "dragged", "halting")]
        with ProcessPoolExecutor(8) as pool:
            rows = [r for r in pool.map(_measure, jobs, chunksize=4) if r]
        cache.write_text(json.dumps(rows))
    report = {}
    for kind in ("natural", "rushed", "dragged", "halting"):
        r = np.array([(rate, share) for k, rate, share in rows if k == kind])
        scores = np.array([flow(*x) for x in r])
        report[kind] = {"n": len(r), "rate_p1_5_50_95_99": np.percentile(r[:, 0], [1, 5, 50, 95, 99]).round(2).tolist(),
                        "pause_p50_95_99": np.percentile(r[:, 1], [50, 95, 99]).round(3).tolist(),
                        "flow_p5_50_95": np.percentile(scores, [5, 50, 95]).round(1).tolist(),
                        "flow_below_80": float((scores < 80).mean())}
        print(kind, json.dumps(report[kind]))
    (DATA / "trained" / "flow_report.json").write_text(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
