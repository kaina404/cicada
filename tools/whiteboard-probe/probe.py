"""P0 probe: DeepSeek reading of real whiteboard frames, change judgment on frame pairs, latency.

Frames come from AndroidEngineerMockInterview.mp4 (candidate's own Chrome: Excalidraw + floating Meet tile).
Writes out/*.json. Usage: python3 -I probe.py read|pairs|latency
"""
import json, os, statistics, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ds

HERE = os.path.dirname(os.path.abspath(__file__))
V = os.environ.get("PROBE_FRAMES", os.path.join(HERE, "video"))
OUT = os.environ.get("PROBE_OUT", os.path.join(HERE, "out"))

READ_SYSTEM = """You read a screenshot of a technical interview. The shared whiteboard (Excalidraw, code or
diagram) is the subject; ignore browser chrome, the floating video-call tile and cursor name tags.
Return JSON only: {"texts": [exact visible whiteboard text lines], "boxes": [labels of drawn boxes],
"arrows": [["from label","to label"]], "occluded": [what is hidden or cut off], "unreadable": [...]}.
Copy text exactly as written, including typos. Never complete words hidden behind the video tile or the
screen edge: write the visible part followed by "…" and list it under occluded."""

PAIR_SYSTEM = """Two screenshots of the same interview whiteboard, BEFORE then AFTER (about 20 seconds apart).
Decide what changed on the board itself. Ignore browser chrome, the floating video-call tile, the mouse
cursor and collaborator name tags. Panning or zooming moves content without changing it; content that
moved out of view is NOT removed. Text partly hidden by the video tile or the screen edge is not a change.
Return JSON only: {"view": "none|pan|zoom|pan+zoom", "added": [...], "removed": [...], "edited": [...],
"in_progress": [content still being typed or drawn], "uncertain": [...]}. Only list what you can see."""

FRAMES = [180, 540, 900, 1260, 1620, 1980, 2400, 2760, 3000, 3120]
PAIRS = [300, 700, 1100, 1250, 1500, 1800, 2200, 2600]


def run_read():
    results = {}
    for t in FRAMES:
        r = ds.chat(READ_SYSTEM, [ds.image_part(f"{V}/t{t}.jpg"), {"type": "text", "text": "Read this frame."}], max_tokens=1500)
        results[t] = r
        print(t, r.get("first_token_s"), r.get("total_s"), (r.get("usage") or {}).get("prompt_tokens"), r.get("error", ""))
    json.dump(results, open(f"{OUT}/read.json", "w"), indent=1, ensure_ascii=False)


def run_pairs():
    results = {}
    for t in PAIRS:
        parts = [{"type": "text", "text": "BEFORE:"}, ds.image_part(f"{V}/pairs/p{t}.jpg"),
                 {"type": "text", "text": "AFTER:"}, ds.image_part(f"{V}/pairs/p{t + 20}.jpg")]
        r = ds.chat(PAIR_SYSTEM, parts, max_tokens=800)
        results[t] = r
        print(t, r.get("first_token_s"), r.get("total_s"), r.get("error", ""))
    json.dump(results, open(f"{OUT}/pairs.json", "w"), indent=1, ensure_ascii=False)


def transcript(minutes=90):
    """Synthetic but realistic-length two-sided transcript (~150 wpm candidate, sparse interviewer)."""
    topics = ["requirements for the news feed", "cursor pagination for the feed API", "offline viewing and sync",
              "the repository layer and single source of truth", "an in-memory cache in front of Room",
              "optimistic likes with a pending queue", "exponential backoff for failed writes",
              "image loading through a CDN", "push notifications with FCM", "Compose UI state for loading and errors"]
    lines, sec = [], 0
    while sec < minutes * 60:
        topic = topics[(sec // 540) % len(topics)]
        if sec % 120 == 0:
            lines.append(f"[{sec // 60:02d}:{sec % 60:02d}] interviewer#{len(lines)}: Can you go a bit deeper on {topic}? What trade-offs do you see?")
        lines.append(f"[{sec // 60:02d}:{sec % 60:02d}] candidate#{len(lines)}: So for {topic}, I'd keep the screen state in the ViewModel and "
                     f"expose it as a StateFlow. The repository decides whether data comes from the local store or the network, "
                     f"and the UI only observes. When the network fails we keep showing cached items and mark the request as pending.")
        sec += 15
    return "\n".join(lines)


def run_latency():
    rules = open(os.environ.get("PROBE_PREFIX", os.path.join(HERE, "excalidraw-truth.md"))).read()  # stand-in for fixed rules + knowledge prefix
    prefix = ("You coach a candidate in a live Android system design interview. Reply with the next card:\n"
              "<<<CICADA_CARD>>>\nSAY:\n<two or three short spoken English sentences>\nTHEN: <one line>\n\n"
              "Reference board notes:\n" + rules)
    full = transcript(90)
    cases = {"text_full_transcript": None, "image_full_transcript": f"{V}/t2760.jpg"}
    results = {}
    for name, img in cases.items():
        runs = []
        for i in range(6):
            # Same prefix and transcript every time: the tail question changes, as in a live interview.
            parts = []
            if img:
                parts.append(ds.image_part(img))
            parts.append({"type": "text", "text": "Full transcript so far:\n" + full +
                          f"\n[90:{i:02d}] interviewer: Quick one ({i}) — how would you prefetch the next page?"})
            r = ds.chat(prefix, parts, max_tokens=200)
            u = r.get("usage") or {}
            runs.append({"first": r.get("first_token_s"), "total": r.get("total_s"), "prompt": u.get("prompt_tokens"),
                         "cached": u.get("prompt_cache_hit_tokens"), "error": r.get("error")})
            print(name, i, runs[-1])
        firsts = [x["first"] for x in runs if x["first"]]
        results[name] = {"runs": runs, "median_first": statistics.median(firsts), "max_first": max(firsts),
                         "median_first_warm": statistics.median(firsts[1:])}
    json.dump(results, open(f"{OUT}/latency.json", "w"), indent=1)


if __name__ == "__main__":
    {"read": run_read, "pairs": run_pairs, "latency": run_latency}[sys.argv[1]]()
