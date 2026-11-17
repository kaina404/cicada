"""Minimal DeepSeek streaming client for the P0 probe (stdlib only).

Mirrors CoachDeepSeekTest.body: model deepseek-flash, thinking disabled, images as image_url parts.
The key is read from the app's 0600 key file and never printed.
"""
import base64, json, os, time, urllib.request, urllib.error

KEY_FILE = os.path.expanduser("~/Library/Application Support/LiveSubs Dev/ai-key-deepseek")
URL = "https://api.deepseek.com/chat/completions"


def key():
    with open(KEY_FILE) as f:
        return f.read().strip()


def image_part(path):
    with open(path, "rb") as f:
        data = base64.b64encode(f.read()).decode()
    return {"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + data}}


def chat(system, user_parts, max_tokens=1600, model="deepseek-flash"):
    """Returns dict: text, first_token_s, total_s, usage, error."""
    body = {"model": model, "stream": True, "temperature": 0, "max_tokens": max_tokens,
            "thinking": {"type": "disabled"}, "stream_options": {"include_usage": True},
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user_parts}]}
    req = urllib.request.Request(URL, data=json.dumps(body).encode(), method="POST",
                                 headers={"Authorization": "Bearer " + key(), "Content-Type": "application/json"})
    started = time.time(); first = None; text = ""; usage = None
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            for raw in resp:
                line = raw.decode("utf-8", "replace").strip()
                if not line.startswith("data:"):
                    continue
                value = line[5:].strip()
                if value == "[DONE]":
                    break
                obj = json.loads(value)
                if obj.get("usage"):
                    usage = obj["usage"]
                for choice in obj.get("choices", []):
                    delta = choice.get("delta", {}).get("content") or ""
                    if delta:
                        if first is None:
                            first = time.time() - started
                        text += delta
    except urllib.error.HTTPError as e:
        return {"error": f"HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:400]}"}
    return {"text": text, "first_token_s": first, "total_s": time.time() - started, "usage": usage}


if __name__ == "__main__":
    import sys
    r = chat("You read screenshots precisely.",
             [image_part(sys.argv[1]), {"type": "text", "text": "Transcribe the whiteboard text exactly, line by line. Ignore the video call tiles and browser chrome."}],
             max_tokens=800)
    print(json.dumps(r, indent=1, ensure_ascii=False))
