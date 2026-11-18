"""Qwen3-ASR 1.7B 8bit (streaming) + Hy-MT2 1.8B 8bit, both on MLX, for the meeting's other side.

JSON lines on stdin:  {"audio": <base64 float32 16 kHz mono>} | {"reset": lang} | {"cut": true}
                      | {"translate": text, "id": n, "sentence": bool}
JSON lines on stdout: {"ready": true} | {"draft"|"final": text, "start": s, "end": s}
                      | {"id": n, "zh": text|null}
Only these pipes carry meeting text; nothing is logged. Hy-MT2 runs in its own process so a
translation never holds back the next chunk's decode (measured 2026-11-17: both keep real time).
"""
import base64, json, multiprocessing as mp, os, queue, sys, threading

import numpy as np

MODELS = os.path.expanduser("~/.cicada-mlx/models")
ASR = os.path.join(MODELS, "qwen3-asr-1.7b-8bit")
MT = os.path.join(MODELS, "hy-mt2-1.8b-8bit")
RATE = 16000
# Trailing quiet that ends a line by itself (the app also cuts long lines with "cut").
QUIET_RMS, QUIET_SECONDS = 0.004, 0.7
LANGS = {"en": "English", "zh": "Chinese", "ja": "Japanese", "ko": "Korean"}

out_lock = threading.Lock()


def emit(value):
    with out_lock:
        sys.stdout.write(json.dumps(value, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def translator(requests, answers):
    import mlx.core as mx
    from mlx_lm import load, stream_generate
    from mlx_lm.sample_utils import make_sampler, make_logits_processors
    model, tok = load(MT)
    mx.eval(model.parameters())
    # Greedy: the same English gives the same Chinese, so a draft's translation doesn't flicker.
    sampler = make_sampler(temp=0.0)
    processors = make_logits_processors(repetition_penalty=1.05)

    def run(text):
        prompt = tok.apply_chat_template(
            [{"role": "user", "content": "将以下文本翻译为中文，注意只需要输出翻译后的结果，不要额外解释：\n\n" + text}],
            tokenize=False, add_generation_prompt=True)
        limit = max(64, len(text) * 2)
        return "".join(r.text for r in stream_generate(model, tok, prompt, max_tokens=limit, sampler=sampler,
                                                        logits_processors=processors)).strip()
    run("Hello.")
    answers.put(("ready", None))
    while True:
        item = requests.get()
        if item is None:
            return
        rid, text = item
        try:
            answers.put((rid, run(text)))
        except Exception:
            answers.put((rid, None))


class Translations:
    """Sentences first, in order; of drafts only the latest waits. One in flight at a time."""

    def __init__(self):
        ctx = mp.get_context("spawn")
        self.requests, self.answers = ctx.Queue(), ctx.Queue()
        self.child = ctx.Process(target=translator, args=(self.requests, self.answers), daemon=True)
        self.child.start()
        self.lock = threading.Condition()
        self.sentences, self.draft = [], None

    def wait_ready(self):
        while True:
            rid, _ = self.answers.get()
            if rid == "ready":
                return

    def ask(self, rid, text, sentence):
        with self.lock:
            if sentence:
                self.sentences.append((rid, text))
            else:
                if self.draft:
                    emit({"id": self.draft[0], "zh": None})
                self.draft = (rid, text)
            self.lock.notify()

    def serve(self):
        while True:
            with self.lock:
                while not self.sentences and not self.draft:
                    self.lock.wait()
                if self.sentences:
                    item = self.sentences.pop(0)
                else:
                    item, self.draft = self.draft, None
            self.requests.put(item)
            rid, zh = self.answers.get()
            emit({"id": rid, "zh": zh})


def main():
    import mlx.core as mx
    from mlx_qwen3_asr import Session

    commands = queue.Queue()

    def read():
        for line in sys.stdin:
            try:
                commands.put(json.loads(line))
            except ValueError:
                pass
        commands.put(None)
    threading.Thread(target=read, daemon=True).start()

    mt = Translations()
    session = Session(model=ASR)
    mx.eval(session.model.parameters())
    warm = session.init_streaming(language="English", chunk_size_sec=1.0)
    session.feed_audio(np.zeros(RATE, dtype=np.float32), warm)
    mt.wait_ready()
    threading.Thread(target=mt.serve, daemon=True).start()
    emit({"ready": True})

    lang = "English"
    clock = 0.0          # seconds of audio received
    line_start = None    # when the line in progress began
    quiet = 0.0
    shown = ""

    def fresh():
        return session.init_streaming(language=lang, chunk_size_sec=1.0, max_context_sec=30.0)
    state = fresh()

    def end_line():
        nonlocal state, line_start, shown, quiet
        if line_start is not None or state.text:
            session.finish_streaming(state)
            text = state.text.strip()
            if text:
                emit({"final": text, "start": line_start or clock, "end": clock - min(quiet, QUIET_SECONDS)})
        state, line_start, shown, quiet = fresh(), None, "", 0.0

    while True:
        cmd = commands.get()
        if cmd is None:
            break
        if "translate" in cmd:
            mt.ask(cmd.get("id"), cmd["translate"], bool(cmd.get("sentence")))
        elif "reset" in cmd:
            lang = LANGS.get(str(cmd["reset"]).split("-")[0])
            state, line_start, shown, quiet, clock = fresh(), None, "", 0.0, 0.0
        elif cmd.get("cut"):
            end_line()
        elif "audio" in cmd:
            pcm = np.frombuffer(base64.b64decode(cmd["audio"]), dtype=np.float32).copy()
            if pcm.size == 0:
                continue
            seconds = pcm.size / RATE
            clock += seconds
            loud = float(np.sqrt(np.mean(pcm * pcm))) >= QUIET_RMS
            quiet = 0.0 if loud else quiet + seconds
            if line_start is None:
                if not loud:
                    continue  # no line yet: silence isn't decoded
                line_start = clock - seconds
            session.feed_audio(pcm, state)
            text = state.text.strip()
            if text and text != shown:
                shown = text
                emit({"draft": text, "start": line_start, "end": clock})
            if quiet >= QUIET_SECONDS:
                end_line()
    end_line()
    mt.requests.put(None)


if __name__ == "__main__":
    main()
