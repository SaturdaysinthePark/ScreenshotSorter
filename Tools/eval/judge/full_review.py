"""Score a full-library review (every screenshot judged on contact sheets, see judge/README.md §6).

    python3 Tools/eval/judge/full_review.py <review dir> <notes.jsonl> [<rescore.jsonl>]

review dir: r*.jsonl with one verdict per screenshot ({"n", "id", "cats_wrong", "cats_missing", "title", "tags_noise",
"button", "details_noise", "details_missing", …}). notes.jsonl: what the app showed when it was judged.
With a newer re-score (Tools/eval/run.sh --db … --out x.jsonl), also says how a change moved against the verdicts:
expected collections = shown − wrong + missing.
"""
import glob, json, sys
from collections import Counter

verdicts = {}
for path in sorted(glob.glob(sys.argv[1] + "/r*.jsonl")):
    for line in open(path):
        line = line.strip()
        if line:
            try:
                v = json.loads(line)
                verdicts[v["id"][:8]] = v
            except (json.JSONDecodeError, KeyError):
                pass
notes = {json.loads(l)["id"]: json.loads(l) for l in open(sys.argv[2])}
n = len(verdicts)
print(f"{n} screenshots judged (of {len(notes)})")

wrong, missing = Counter(), Counter()
for v in verdicts.values():
    wrong.update(v.get("cats_wrong") or []); missing.update(v.get("cats_missing") or [])
shown = Counter(c for i in verdicts for c in notes.get(i, {}).get("collections", []) if c != "other")
anywrong = sum(1 for v in verdicts.values() if v.get("cats_wrong"))
anymissing = sum(1 for v in verdicts.values() if v.get("cats_missing"))
allright = sum(1 for v in verdicts.values() if not v.get("cats_wrong") and not v.get("cats_missing"))
print(f"\ncollections: all right {allright} ({100*allright/max(1,n):.0f}%) · some wrong {anywrong} · some missing {anymissing}")
print(f"labels shown {sum(shown.values())}, wrong {sum(wrong.values())} ({100*sum(wrong.values())/max(1,sum(shown.values())):.0f}%), missing {sum(missing.values())}")
print("\n  category       shown  wrong  missing")
for c in sorted(set(shown) | set(missing), key=lambda c: -(wrong[c] + missing[c])):
    if wrong[c] + missing[c]:
        print(f"  {c:14s} {shown[c]:5d} {wrong[c]:6d} {missing[c]:8d}")

titles = Counter(v.get("title") for v in verdicts.values())
buttons = Counter(v.get("button") for v in verdicts.values())
print(f"\ntitles: {dict(titles)}")
print(f"buttons: {dict(buttons)}")
tags = Counter(t.lower() for v in verdicts.values() for t in (v.get("tags_noise") or []))
print(f"noise tags: {sum(tags.values())} on {sum(1 for v in verdicts.values() if v.get('tags_noise'))} screenshots; top {tags.most_common(25)}")
dn = sum(len(v.get("details_noise") or []) for v in verdicts.values())
dm = sum(len(v.get("details_missing") or []) for v in verdicts.values())
print(f"details: noise rows {dn}, missing {dm}")

if len(sys.argv) > 3:
    now = {}
    for line in open(sys.argv[3]):
        r = json.loads(line)
        now[r["id"]] = {a.split("=")[0] for a in r["after"]} - {"other"}
    fixed = broke = added = lost = 0
    for i, v in verdicts.items():
        before = set(notes[i]["collections"]) - {"other"}
        bad, need = set(v.get("cats_wrong") or []), set(v.get("cats_missing") or [])
        right = before - bad
        after = now.get(i, before)
        fixed += len(bad - after); added += len(need & after)
        lost += len(right - after); broke += len((after - before) - need)
    print(f"\nagainst the verdicts: wrong removed {fixed}/{sum(wrong.values())} · missing added {added}/{sum(missing.values())}"
          f" · right ones lost {lost} · new unjudged labels {broke}")
