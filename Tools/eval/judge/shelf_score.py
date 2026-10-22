"""Precision of every collection shelf, from judged samples (build/phone/audit/verdicts.json).

    python3 Tools/eval/judge/shelf_score.py <verdicts.json> <rescore.jsonl> [--diff <older rescore.jsonl>]

verdicts.json: {category: {id8: "right" | "wrong" | "borderline"}}, judged from contact sheets of a random sample per
shelf. A re-score keeps or drops each sampled screenshot from its shelf: precision = right kept / (right + wrong kept);
"lost" counts right ones that fell out (recall cost). Borderline ones count for neither.
"""
import json, sys

verdicts = json.load(open(sys.argv[1]))
def labels(path):
    out = {}
    for line in open(path):
        r = json.loads(line)
        out[r["id"]] = {a.split("=")[0] for a in r["after"]}
    return out
now = labels(sys.argv[2])
total = {"right": 0, "wrong": 0, "lost": 0, "dropped": 0}
rows = []
for category, judged in verdicts.items():
    right = sum(1 for i, v in judged.items() if v == "right" and category in now.get(i, ()))
    wrong = sum(1 for i, v in judged.items() if v == "wrong" and category in now.get(i, ()))
    lost = sum(1 for i, v in judged.items() if v == "right" and category not in now.get(i, ()))
    dropped = sum(1 for i, v in judged.items() if v == "wrong" and category not in now.get(i, ()))
    for key, value in (("right", right), ("wrong", wrong), ("lost", lost), ("dropped", dropped)):
        total[key] += value
    rows.append((right / max(1, right + wrong), category, right, wrong, lost, dropped))
for p, category, right, wrong, lost, dropped in sorted(rows):
    print(f"{category:15s} precision {p:4.2f}  right {right:2d} wrong {wrong:2d}  (lost {lost}, fixed {dropped})")
p = total["right"] / max(1, total["right"] + total["wrong"])
print(f"\nall shelves: precision {p:.3f} · right kept {total['right']} · wrong kept {total['wrong']} · "
      f"right lost {total['lost']} · wrong fixed {total['dropped']}")
