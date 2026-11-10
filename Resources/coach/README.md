# Local acoustic worker

The app launches `audio_worker.py` with its existing `~/.cicada-mlx/bin/python`.
Settings › AI Service › Interview Coach › Set up speech detection installs the
ONNX CPU runtime and fetches model weights. No meeting audio leaves this process.
Missing runtime or model failures leave the existing pause/text endpoint fallback
active; `assistantState` exposes whether acoustic detection is ready.

- Python 3.12, ONNX Runtime 1.24.1 (MIT), NumPy and Transformers from the existing MLX environment.
- [Silero VAD v6.2](https://github.com/snakers4/silero-vad/tree/v6.2), MIT. Model URL and SHA-256 are pinned in the worker.
- [Smart Turn v3.2](https://github.com/pipecat-ai/smart-turn), BSD-2-Clause. Weights `pipecat-ai/smart-turn-v3`, revision `f766f81d3cfdf7737ac64aad813d91bbfd56bf93`, CPU ONNX graph.
- [ONNX Runtime](https://github.com/microsoft/onnxruntime), MIT.

VAD runs in independent 512-sample windows for each channel, with 64 context
samples and separate recurrent state. Smart Turn processes the last 8 seconds,
with Whisper feature extraction, once per 320 ms pause. Sessions explicitly use
CPUExecutionProvider with bounded CPU thread counts. Swift sends at most four
queued packets and coalesces visual work behind the active MLX response.

The worker's JSON-lines transport accepts PCM16 mono at 16 kHz and returns VAD
and endpoint events. It never logs transcripts or stores audio. Stdout is reserved
for protocol events; startup errors go to stderr. Model downloads are separate
from inference. The acoustic worker has no HTTP listener.

## Private Kokoro worker

`kokoro_worker.py` is separate from acoustic recognition. It provisions an isolated
`~/.cicada-kokoro` runtime from the existing Python, loads pinned Kokoro-82M weights
and af_heart, warms with an unplayed phrase, then accepts JSON-lines text requests
and returns mono 24 kHz float32 PCM over private pipes. The process keeps the model
loaded. No cloud synthesis, audio files, or system TTS fallback. See
[assistant read along](../../docs/assistant-read-along.md) for versions, routing and validation.
