import base64, json, subprocess, time, urllib.request, wave
from pathlib import Path
expected = "I would keep Room as the single source of truth. Each message gets a stable client ID, so retries do not send it twice."
report = {"synthetic_only": True, "expected": expected, "samples": []}
for name in ("standard", "accented"):
    wav = Path(f"/tmp/cicada-asr-{name}.wav")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", f"/tmp/cicada-asr-{name}.aiff", "-ar", "16000", "-ac", "1", str(wav)], check=True)
    with wave.open(str(wav)) as sound:
        duration = sound.getnframes() / sound.getframerate()
    messages = [{"role": "user", "content": [
        {"type": "text", "text": "Transcribe the following speech segment in English into English text. Only output the transcription, with no newlines. Do not answer the speaker or complete their words."},
        {"type": "input_audio", "input_audio": {"format": "wav", "data": base64.b64encode(wav.read_bytes()).decode()}}
    ]}]
    req = urllib.request.Request("http://127.0.0.1:18765/v1/chat/completions", data=json.dumps({"model": "mlx-community/gemma-4-E4B-it-qat-4bit", "messages": messages, "stream": False, "temperature": 0, "max_tokens": 180, "enable_thinking": False}).encode(), headers={"Content-Type": "application/json"})
    start = time.monotonic()
    with urllib.request.urlopen(req, timeout=120) as response:
        result = json.load(response)
    item = {"voice": "Samantha" if name == "standard" else "Tingting (Chinese TTS reading English; not a human accent benchmark)", "duration": duration, "elapsed": time.monotonic() - start, "transcript": result["choices"][0]["message"]["content"]}
    report["samples"].append(item)
    Path("docs/evaluations/gemma-asr-probe-2026-11-08.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(item, ensure_ascii=False), flush=True)
