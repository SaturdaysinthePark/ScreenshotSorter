"""Score a library's stored labels against judged truth.

    python3 Tools/eval/judge/score.py <truth.json> <analysis.sqlite> [--manifest <corpus dir>]

truth.json: [{"n", "id", "file", "expect": [...], "allow": [...]}] written by the judge (see README).
Prints per-category precision/recall/F1 of what the app assigned, the worst confusions, and every miss.
With --manifest, also writes <corpus dir>/manifest.json so `Tools/eval/run.sh --corpus <dir>` can run the
full pipeline on the same images on a Mac.
"""
import json, os, sqlite3, sys
from collections import Counter, defaultdict

truth_path, db_path = sys.argv[1], sys.argv[2]
truth = json.load(open(truth_path))
db = sqlite3.connect(db_path)
bits = {0: 'V', 1: 'R', 2: 'A', 3: 'B', 4: 'F', 5: 'L', 6: 'M'}
def sources(v): return ''.join(c for b, c in bits.items() if int(v) & (1 << b))

tp, fp, fn = Counter(), Counter(), Counter()
confusions, exact, misses = Counter(), 0, []
for item in truth:
    row = db.execute("SELECT categories, title, fm_version FROM assets WHERE id = ?", (item["id"],)).fetchone()
    if not row:
        continue
    predicted = {}
    for part in row[0].split(","):
        if part:
            key, score, src = part.split(":")
            predicted[key] = (float(score), sources(src))
    expect, allow = set(item["expect"]), set(item.get("allow", []))
    got = set(predicted) - {"other"} - (allow - expect)
    if got == expect:
        exact += 1
    for c in got:
        (tp if c in expect else fp)[c] += 1
    for c in expect - got:
        fn[c] += 1
        for wrong in got - expect:
            confusions[f"{c} → {wrong}"] += 1
        if not got - expect:
            confusions[f"{c} → (nothing)"] += 1
    wrong = sorted(got - expect)
    missing = sorted(expect - got)
    if wrong or missing:
        misses.append((item["n"], missing, [f"{w}={predicted[w][0]:.2f}[{predicted[w][1]}]" for w in wrong], row[2]))

cats = sorted(set(tp) | set(fp) | set(fn))
def f1(c):
    p = tp[c] / max(1, tp[c] + fp[c]); r = tp[c] / max(1, tp[c] + fn[c])
    return p, r, (2 * p * r / (p + r)) if p + r else 0.0
supported = [c for c in cats if tp[c] + fn[c] > 0]
macro = sum(f1(c)[2] for c in supported) / max(1, len(supported))
T, FP, FN = sum(tp.values()), sum(fp.values()), sum(fn.values())
micro_p, micro_r = T / max(1, T + FP), T / max(1, T + FN)
print(f"{len(truth)} judged · exact {exact}/{len(truth)} ({100 * exact / max(1, len(truth)):.0f}%) · "
      f"precision {micro_p:.2f} recall {micro_r:.2f} · macro-F1 {macro:.3f} over {len(supported)} categories")
print("\ncategory          P     R     F1   support  FP")
for c in sorted(cats, key=lambda c: f1(c)[2]):
    p, r, f = f1(c)
    print(f"{c:16s} {p:5.2f} {r:5.2f} {f:5.2f} {tp[c] + fn[c]:5d} {fp[c]:5d}")
print("\ntop confusions:", confusions.most_common(15))
print("\nmisses (n, missing, wrong, model version):")
for m in misses:
    print("  ", m)

if "--manifest" in sys.argv:
    root = sys.argv[sys.argv.index("--manifest") + 1]
    manifest = [{"file": os.path.relpath(item["file"], root), "expect": item["expect"], "allow": item.get("allow", []),
                 "source": "phone"} for item in truth]
    json.dump(manifest, open(os.path.join(root, "manifest.json"), "w"), indent=1)
    print(f"\nwrote {root}/manifest.json ({len(manifest)} cases)")
