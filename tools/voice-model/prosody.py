"""The loudness envelope and the pitch model, measured the way the app measures them.

The envelope (10 ms loudness over the speech segments, smoothed over 50 ms) gives the syllable peaks
of `flow.py`; the pitch model is the app's SwiftF0 export.
"""

import numpy as np

from features import SAMPLE_RATE, _session

ENVELOPE_HOP = 160


class Prosody:
    def __init__(self) -> None:
        self.f0 = _session("EuphonaF0.onnx")

    @staticmethod
    def envelope(samples: np.ndarray, segments: list[tuple[int, int]]) -> np.ndarray:
        """Loudness in dB per 10 ms over the speech segments joined, smoothed over 50 ms."""
        speech = np.concatenate([samples[a:b] for a, b in segments]) if segments else samples[:0]
        frames = len(speech) // ENVELOPE_HOP
        if frames == 0:
            return np.zeros(0, np.float32)
        power = (speech[:frames * ENVELOPE_HOP].reshape(frames, ENVELOPE_HOP) ** 2).mean(1)
        db = 10 * np.log10(power + 1e-10)
        return np.convolve(db, np.ones(5) / 5, mode="same")
