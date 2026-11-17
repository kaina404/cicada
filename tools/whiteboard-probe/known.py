"""P0: re-run pan pairs with 'known board content' from earlier frames (what a board log would hold)."""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ds, probe
read = json.load(open(os.path.join(probe.OUT, "read.json")))
def known(t):
    try: return "\n".join(json.loads(read[str(t)]["text"])["texts"])
    except Exception: return read[str(t)]["text"]
out = {}
for pair, earlier in [(1100, 900), (2600, 2400), (2200, 1980)]:
    parts = [{"type": "text", "text": "Board content already seen earlier in this interview (log):\n" + known(earlier) +
              "\nContent that is in this log and merely comes into view is NOT added."},
             {"type": "text", "text": "BEFORE:"}, ds.image_part(f"{probe.V}/pairs/p{pair}.jpg"),
             {"type": "text", "text": "AFTER:"}, ds.image_part(f"{probe.V}/pairs/p{pair + 20}.jpg")]
    r = ds.chat(probe.PAIR_SYSTEM, parts, max_tokens=800)
    out[pair] = r; print("==", pair, r.get("text", r.get("error"))[:700].replace("\n", " "))
json.dump(out, open(os.path.join(probe.OUT, "pairs-known.json"), "w"), indent=1, ensure_ascii=False)
