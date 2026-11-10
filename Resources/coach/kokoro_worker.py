"""Private, persistent Kokoro CPU worker. JSON lines over pipes; no audio/text files or listener."""
import base64
import contextlib
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys

MODEL_REVISION = "f3ff3571791e39611d31c381e3a41a3af07b4987755"
VOICE = "af_heart"


def runtime():
    root = Path.home() / ".cicada-kokoro"
    python = root / "bin/python"
    marker = root / "cicada-kokoro-0.9.4-ready"
    if Path(sys.prefix) != root:
        # Multiple dev/release instances may prepare at once. Never let pip mutate the same venv concurrently.
        with (Path.home() / ".cicada-kokoro-install.lock").open("w") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            # All setup runs in this child, never on the app's main thread. Existing MLX packages stay intact.
            if not python.exists():
                subprocess.run([sys.executable, "-m", "venv", str(root)], check=True, stdout=sys.stderr)
            if not marker.exists():
                subprocess.run([str(python), "-m", "pip", "install", "--disable-pip-version-check",
                                "kokoro==0.9.4", "torch==2.8.0", "numpy<3",
                                "https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl"],
                               check=True, stdout=sys.stderr)
                marker.touch()
        os.execv(str(python), [str(python), "-u", str(Path(__file__).resolve())])


def main():
    runtime()
    # Third-party progress/output must never corrupt the JSON-lines channel.
    with contextlib.redirect_stdout(sys.stderr):
        import numpy as np
        import torch
        from huggingface_hub import hf_hub_download
        from kokoro import KModel, KPipeline
        torch.set_num_threads(4)
        def fetch(name):
            try:
                return hf_hub_download("hexgrad/Kokoro-82M", name, revision=MODEL_REVISION, local_files_only=True)
            except FileNotFoundError:
                return hf_hub_download("hexgrad/Kokoro-82M", name, revision=MODEL_REVISION)
        model = KModel(repo_id="hexgrad/Kokoro-82M", config=fetch("config.json"), model=fetch("kokoro-v1_0.pth")).to("cpu").eval()
        pipeline = KPipeline(lang_code="a", model=model, repo_id="hexgrad/Kokoro-82M")
        voice = torch.load(fetch("voices/af_heart.pt"), map_location="cpu", weights_only=True)
        def synthesize(text):
            with torch.inference_mode():
                chunks, words, offset = [], [], 0.0
                for result in pipeline(text, voice=voice, speed=0.95):
                    audio = result.audio.numpy()
                    for token in result.tokens or []:
                        if token.start_ts is not None and token.end_ts is not None:
                            words.append({"text": token.text, "start": offset + token.start_ts,
                                          "end": offset + token.end_ts})
                    chunks.append(audio)
                    offset += len(audio) / 24000
            return (np.concatenate(chunks).astype("<f4") if chunks else np.array([], dtype="<f4")), words
        synthesize("Ready.")  # Warm kernels and G2P without playing any sound.
    print(json.dumps({"ready": True, "model": "Kokoro-82M", "voice": VOICE}), flush=True)
    for line in sys.stdin:
        request = json.loads(line)
        try:
            text = request["text"]
            if not isinstance(text, str) or len(text) > 4000:
                raise ValueError("invalid text")
            with contextlib.redirect_stdout(sys.stderr):
                pcm, words = synthesize(text)
            reply = {"id": request["id"], "pcm": base64.b64encode(pcm.tobytes()).decode(), "rate": 24000, "words": words}
        except Exception:
            reply = {"id": request.get("id"), "error": "synthesis_failed"}
        print(json.dumps(reply), flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception:
        # Do not log assistant text or exception bodies containing it.
        print(json.dumps({"error": "kokoro_start_failed"}), flush=True)
        sys.exit(1)
