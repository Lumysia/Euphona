"""Variants of a recording made with the WORLD vocoder, plus channel variety.

Timbre learns a smooth scale from gender morphs: pitch and resonance move together from a speaker's
own voice toward the other end, and the label moves with them. Natural examples are vocoded too, so
the vocoder's own sound is not a cue. `flow.py` uses `World` to make rushed and dragged speech for
testing flow.
"""

from dataclasses import dataclass

import numpy as np
import pyworld as pw
from scipy.signal import butter, sosfilt

from features import SAMPLE_RATE

FRAME_PERIOD = 5.0
# Typical feminine voices sit about this far from typical masculine ones: pitch ratio and the
# resonance (formant) ratio, from adult speaking norms (about 120 vs 210 Hz; vocal tracts ~17%
# shorter).
PITCH_RATIO = 1.75
FORMANT_RATIO = 1.17
# Timbre labels for typical voices; morphs interpolate between them.
TIMBRE_LOW, TIMBRE_HIGH = 0.12, 0.88


@dataclass
class World:
    f0: np.ndarray
    sp: np.ndarray
    ap: np.ndarray

    @classmethod
    def analyze(cls, samples: np.ndarray) -> "World":
        x = samples.astype(np.float64)
        f0, t = pw.dio(x, SAMPLE_RATE, frame_period=FRAME_PERIOD)
        f0 = pw.stonemask(x, f0, t, SAMPLE_RATE)
        return cls(f0, pw.cheaptrick(x, f0, t, SAMPLE_RATE), pw.d4c(x, f0, t, SAMPLE_RATE))

    def render(self, pitch=1.0, formant=1.0, tempo=1.0, intonation=1.0) -> np.ndarray:
        """pitch scales F0, formant stretches the spectral envelope, tempo speeds up speech without
        changing pitch, intonation scales the pitch contour around its median (0 = monotone)."""
        f0 = self.f0.copy()
        voiced = f0 > 0
        if voiced.any():
            median = np.median(f0[voiced])
            st = 12 * np.log2(f0[voiced] / median)
            f0[voiced] = median * pitch * 2 ** (intonation * st / 12)
        sp = self.sp if formant == 1.0 else warp(self.sp, formant)
        y = pw.synthesize(f0, np.ascontiguousarray(sp), self.ap, SAMPLE_RATE, FRAME_PERIOD / tempo)
        peak = np.max(np.abs(y)) or 1.0
        return (y / peak * min(peak, 0.95)).astype(np.float32)


def warp(sp: np.ndarray, ratio: float) -> np.ndarray:
    """Moves every formant by `ratio` (above 1 = shorter vocal tract)."""
    bins = np.arange(sp.shape[1], dtype=np.float64)
    source = np.clip(bins / ratio, 0, sp.shape[1] - 1)
    return np.stack([np.interp(source, bins, frame) for frame in sp])


def channel(samples: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    """A different microphone and room: band limits, a little noise, another level."""
    y = samples.astype(np.float64)
    low = rng.uniform(60, 250)
    high = rng.uniform(3400, 7600)
    y = sosfilt(butter(2, [low, high], btype="band", fs=SAMPLE_RATE, output="sos"), y)
    snr = rng.uniform(15, 40)
    rms = np.sqrt(np.mean(y ** 2)) or 1e-4
    y = y + rng.normal(0, rms / 10 ** (snr / 20), len(y))
    y *= 10 ** (rng.uniform(-12, 3) / 20)
    return np.clip(np.round(y * 32767), -32768, 32767).astype(np.float32) / 32768.0


def natural(world: World, rng: np.random.Generator) -> np.ndarray:
    """Within the range of ordinary speech."""
    return world.render(pitch=rng.uniform(0.93, 1.07), tempo=rng.uniform(0.85, 1.2),
                        intonation=rng.uniform(0.8, 1.25))


def morph(world: World, is_feminine: bool, rng: np.random.Generator) -> tuple[np.ndarray, float]:
    """A voice part of the way to the other end of the scale, and its timbre label."""
    t = rng.uniform(0.1, 1.0)
    direction = -1 if is_feminine else 1
    audio = world.render(pitch=PITCH_RATIO ** (direction * t), formant=FORMANT_RATIO ** (direction * t))
    position = 1 - t if is_feminine else t
    return audio, TIMBRE_LOW + (TIMBRE_HIGH - TIMBRE_LOW) * position
