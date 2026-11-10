# Models

The ONNX models Euphona's engine runs, all on the device.

| File | What it is | Source | Licence |
|---|---|---|---|
| `EuphonaVAD.onnx` | Silero VAD, speech detection | [snakers4/silero-vad](https://github.com/snakers4/silero-vad) | MIT |
| `EuphonaF0.onnx` | SwiftF0 0.1.2, pitch | [lars76/swift-f0](https://github.com/lars76/swift-f0) (PyPI `swift-f0==0.1.2`) | MIT |
| `EuphonaECAPA.onnx` | SpeechBrain ECAPA-TDNN speaker embeddings with its filterbank, exported by `tools/voice-model/export_ecapa.py` (weights stored as FP16) | [speechbrain/spkrec-ecapa-voxceleb](https://huggingface.co/speechbrain/spkrec-ecapa-voxceleb) | Apache 2.0 |
| `EuphonaTimbre.onnx` | Timbre head | trained by `tools/voice-model/train.py` | GPL-3.0, like the app |
| `EuphonaEase.onnx` | Ease (audible strain) from ECAPA statistics | trained by `tools/voice-model/train_ease.py` | GPL-3.0, like the app |
| `EuphonaVoiceQuality.onnx` | Voice Quality model | trained by `tools/voice-model/train_quality.py` | GPL-3.0, like the app |

Training data: Common Voice 19 (CC0), FLEURS (CC BY 4.0, test only) and the Perceptual Voice
Qualities Database (CC BY 4.0, Walden 2020).
