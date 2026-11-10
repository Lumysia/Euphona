"""Scores recordings with Euphona's trained timbre head, flow and ease, through the app's own path.

    uv run python score.py recording.m4a [more files...]
"""

import sys

import numpy as np
import onnxruntime as ort

import flow
from features import Embedder, embedding_statistics, load_audio
from prosody import Prosody
from train import OUT

embedder, prosody = Embedder(), Prosody()
timbre = ort.InferenceSession(str(OUT / "Timbre.onnx"), providers=["CPUExecutionProvider"])
ease = ort.InferenceSession(str(OUT / "Ease.onnx"), providers=["CPUExecutionProvider"])

for path in sys.argv[1:]:
    samples = load_audio(path)
    segments = embedder.speech_segments(samples)
    if not segments:
        print(path, "no speech found")
        continue
    e = embedder.embed(samples, embedder.windows(segments))
    rate, pauses = flow.measures(samples, segments, prosody)
    stats = embedding_statistics(e)[None].astype(np.float32)
    print(f"{path}\n  timbre  {100 * float(timbre.run(None, {'embeddings': e})[0].mean()):5.1f}"
          f"\n  flow    {flow.flow(rate, pauses):5.1f}  ({rate:.2f} syllables/s, pauses {pauses:.0%})"
          f"\n  ease    {float(ease.run(None, {'features': stats})[0].squeeze()):5.1f}")
