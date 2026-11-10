"""Window embeddings computed the way the app computes them, with the app's own models.

Audio goes in as 16 kHz mono PCM16, Silero VAD finds speech (Silero's own segmentation algorithm and
defaults, as SpeechDetector.swift), speech is cut into 1.515 s windows with a 0.1 s stride (shorter
segments keep their own length), and ECAPA turns each window into a 192-dimension embedding.
"""

import subprocess
from dataclasses import dataclass
from pathlib import Path

import numpy as np
import onnxruntime as ort

SAMPLE_RATE = 16000
PATCH_SAMPLES = 24240
STRIDE_SAMPLES = 1600
BATCH = 8
EMBEDDING_DIMS = 192

# The app's own models, so the tools measure exactly as the app does.
MODELS = Path(__file__).resolve().parents[2] / "Packages/EuphonaKit/Sources/Models"


def load_audio(path: str | Path) -> np.ndarray:
    """Any file ffmpeg reads, as float samples quantized to PCM16 like the app's input."""
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(SAMPLE_RATE), "-f", "s16le", "-"],
        check=True, capture_output=True,
    ).stdout
    return np.frombuffer(raw, dtype=np.int16).astype(np.float32) / 32768.0


def _session(name: str) -> ort.InferenceSession:
    options = ort.SessionOptions()
    options.log_severity_level = 3
    return ort.InferenceSession(str(MODELS / name), options, providers=["CPUExecutionProvider"])


@dataclass
class Windows:
    starts: np.ndarray
    lengths: np.ndarray


class Embedder:
    def __init__(self) -> None:
        self.vad = _session("EuphonaVAD.onnx")
        self.ecapa = _session("EuphonaECAPA.onnx")

    def speech_segments(self, samples: np.ndarray, start_p=0.5) -> list[tuple[int, int]]:
        end_p = max(start_p - 0.15, 0.01)
        window, context_size = 512, 64
        state = np.zeros((2, 1, 128), np.float32)
        context = np.zeros(context_size, np.float32)
        padded = np.pad(samples, (0, (-len(samples)) % window))
        probabilities = []
        for start in range(0, len(padded), window):
            chunk = np.concatenate([context, padded[start:start + window]])[None, :]
            out, state = self.vad.run(None, {"input": chunk, "state": state, "sr": np.array(SAMPLE_RATE, np.int64)})
            probabilities.append(float(out[0, 0]))
            context = chunk[0, -context_size:]
        min_speech, min_silence = SAMPLE_RATE * 250 // 1000, SAMPLE_RATE * 100 // 1000
        segments, triggered, current_start, temporary_end = [], False, 0, 0
        for index, p in enumerate(probabilities):
            sample = index * window
            if p >= start_p and temporary_end:
                temporary_end = 0
            if p >= start_p and not triggered:
                triggered, current_start = True, sample
                continue
            if p < end_p and triggered:
                temporary_end = temporary_end or sample
                if sample - temporary_end < min_silence:
                    continue
                if temporary_end - current_start > min_speech:
                    segments.append([current_start, temporary_end])
                triggered, current_start, temporary_end = False, 0, 0
        if triggered and len(samples) - current_start > min_speech:
            segments.append([current_start, len(samples)])
        pad = SAMPLE_RATE * 30 // 1000
        for i, segment in enumerate(segments):
            if i == 0:
                segment[0] = max(0, segment[0] - pad)
            if i + 1 < len(segments):
                gap = segments[i + 1][0] - segment[1]
                if gap < 2 * pad:
                    segment[1] += gap // 2
                    segments[i + 1][0] -= gap // 2
                else:
                    segment[1] = min(len(samples), segment[1] + pad)
                    segments[i + 1][0] = max(0, segments[i + 1][0] - pad)
            else:
                segment[1] = min(len(samples), segment[1] + pad)
        return [(a, b) for a, b in segments if b > a]

    @staticmethod
    def windows(segments: list[tuple[int, int]], stride: int = STRIDE_SAMPLES) -> Windows:
        starts, lengths = [], []
        for first, last in segments:
            length = last - first
            if length <= PATCH_SAMPLES:
                starts.append(first); lengths.append(length)
                continue
            maximum = length - PATCH_SAMPLES
            offsets = list(range(0, maximum + 1, stride))
            if offsets[-1] != maximum:
                offsets.append(maximum)
            starts += [first + o for o in offsets]; lengths += [PATCH_SAMPLES] * len(offsets)
        return Windows(np.array(starts, int), np.array(lengths, int))

    def embed(self, samples: np.ndarray, windows: Windows) -> np.ndarray:
        """One embedding per window; windows of equal length are batched together (raw waveforms in,
        the filterbank is inside the model, as `SpeakerEncoder` runs it)."""
        out = np.zeros((len(windows.starts), EMBEDDING_DIMS), np.float32)
        for length in np.unique(windows.lengths):
            indices = np.flatnonzero(windows.lengths == length)
            for b in range(0, len(indices), BATCH):
                chunk = indices[b:b + BATCH]
                batch = np.stack([samples[windows.starts[i]:windows.starts[i] + length] for i in chunk]).astype(np.float32)
                out[chunk] = self.ecapa.run(None, {"waveforms": batch})[0]
        return out

    def embed_file(self, path, stride: int = STRIDE_SAMPLES) -> np.ndarray:
        samples = load_audio(path)
        return self.embed(samples, self.windows(self.speech_segments(samples), stride))


def l2(x: np.ndarray) -> np.ndarray:
    return x / np.maximum(np.linalg.norm(x, axis=-1, keepdims=True), 1e-12)


def embedding_statistics(embeddings: np.ndarray) -> np.ndarray:
    """A recording's 384 statistics, as the app's `EmbeddingMath.statistics`: normalized mean of the
    normalized windows, then their std."""
    normalized = l2(embeddings)
    return np.concatenate([l2(normalized.mean(0)), normalized.std(0)])
