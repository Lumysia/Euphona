"""Exports SpeechBrain's ECAPA-TDNN speaker encoder (Apache 2.0), filterbank included, as the app's
EuphonaECAPA.onnx: raw 16 kHz waveforms [batch, samples] in, 192-dimension embeddings out.

The complex STFT does not export, so it is replaced by an equivalent real convolution; the attentive
pooling's mask is all ones because every window is used whole. Large weights are stored as FP16 and
cast back to FP32 when the model loads, halving the file; the output is checked against SpeechBrain.

    uv run python export_ecapa.py
"""

import math
from pathlib import Path

import numpy as np
import onnx
import onnxruntime as ort
import torch
from onnx import TensorProto, helper, numpy_helper
from speechbrain.inference.speaker import EncoderClassifier
from speechbrain.lobes.models import ECAPA_TDNN

ROOT = Path(__file__).resolve().parents[2]
TARGET = ROOT / "Packages/EuphonaKit/Sources/Models/EuphonaECAPA.onnx"
WORK = ROOT / ".build/voice-model"

enc = EncoderClassifier.from_hparams("speechbrain/spkrec-ecapa-voxceleb", savedir=str(WORK / "speechbrain-ecapa"),
                                     run_opts={"device": "cpu"})
fb = enc.mods.compute_features
stft = fb.compute_STFT
N, H = stft.n_fft, stft.hop_length
n = torch.arange(N, dtype=torch.float64); k = torch.arange(N // 2 + 1, dtype=torch.float64)
ang = 2 * math.pi * k[:, None] * n[None, :] / N
w = stft.window.double()
kernel = torch.cat([(torch.cos(ang) * w), (-torch.sin(ang) * w)]).float()[:, None, :]
def conv_stft(x):
    x = torch.nn.functional.pad(x[:, None, :], (N // 2, N // 2))
    y = torch.nn.functional.conv1d(x, kernel, stride=H)          # [B, 2F, T]
    F = N // 2 + 1
    return torch.stack([y[:, :F], y[:, F:]], -1).transpose(1, 2)  # [B, T, F, 2]
ref_stft = stft.forward
x = torch.randn(2, 24240) * 0.05
print("stft max diff", float((conv_stft(x) - ref_stft(x)).abs().max()))
stft.forward = conv_stft
def asp_forward(self, x, lengths=None):
    # Every window is used whole, so the mask is all ones; shaped from x so the batch stays dynamic.
    L = x.shape[-1]
    def stats(x, m, dim=2, eps=self.eps):
        mean = (m * x).sum(dim)
        return mean, torch.sqrt((m * (x - mean.unsqueeze(dim)).pow(2)).sum(dim).clamp(eps))
    if self.global_context:
        mean, std = stats(x, torch.ones_like(x[:, :1, :]) / L)
        attn = torch.cat([x, mean.unsqueeze(2).repeat(1, 1, L), std.unsqueeze(2).repeat(1, 1, L)], dim=1)
    else:
        attn = x
    attn = torch.nn.functional.softmax(self.conv(self.tanh(self.tdnn(attn))), dim=2)
    mean, std = stats(x, attn)
    return torch.cat((mean, std), dim=1).unsqueeze(2)
ECAPA_TDNN.AttentiveStatisticsPooling.forward = asp_forward
class M(torch.nn.Module):
    def __init__(s, e): super().__init__(); s.e = e
    def forward(s, w):
        f = s.e.mods.compute_features(w)
        f = f - f.mean(dim=1, keepdim=True)
        return s.e.mods.embedding_model(f).squeeze(1)
m = M(enc).eval()
torch.onnx.export(m, (torch.randn(3, 24240) * 0.05,), str(WORK / "ECAPA-fp32.onnx"), input_names=["waveforms"], output_names=["embeddings"], dynamic_axes={"waveforms": {0: "batch", 1: "samples"}, "embeddings": {0: "batch"}}, opset_version=17, dynamo=False)
stft.forward = ref_stft
s = ort.InferenceSession(str(WORK / "ECAPA-fp32.onnx"))
for b, L in [(4, 24240), (1, 9000), (8, 24240)]:
    x = torch.randn(b, L) * 0.05
    with torch.no_grad(): ref = enc.encode_batch(x).squeeze(1).numpy()
    out = s.run(None, {"waveforms": x.numpy()})[0]
    cos = (out * ref).sum(1) / np.linalg.norm(out, axis=1) / np.linalg.norm(ref, axis=1)
    print(b, L, "max abs diff", float(np.abs(out - ref).max()), "min cos", float(cos.min()))


# FP16 storage with casts back to FP32.
model = onnx.load(str(WORK / "ECAPA-fp32.onnx"))
graph = model.graph
initializers, casts = [], []
for init in graph.initializer:
    a = numpy_helper.to_array(init)
    if a.dtype == np.float32 and a.size >= 1024:
        half = numpy_helper.from_array(a.astype(np.float16), init.name + "_fp16")
        initializers.append(half)
        casts.append(helper.make_node("Cast", [half.name], [init.name], to=TensorProto.FLOAT))
    else:
        initializers.append(init)
del graph.initializer[:]
graph.initializer.extend(initializers)
nodes = list(graph.node)
del graph.node[:]
graph.node.extend(casts + nodes)
onnx.save(model, str(TARGET))
x = torch.randn(8, 24240) * 0.05
with torch.no_grad():
    ref = enc.encode_batch(x).squeeze(1).numpy()
out = ort.InferenceSession(str(TARGET)).run(None, {"waveforms": x.numpy()})[0]
cos = (out * ref).sum(1) / np.linalg.norm(out, axis=1) / np.linalg.norm(ref, axis=1)
print("FP16 weights: min cosine to SpeechBrain", float(cos.min()), "->", TARGET)
