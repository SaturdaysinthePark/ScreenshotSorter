"""Prints explained failures from results.jsonl:  python3 Tools/eval/failures.py build/corpus [deep|fast] [category]"""
import json, sys
root = sys.argv[1]; want_pass = sys.argv[2] if len(sys.argv) > 2 else "deep"; cat = sys.argv[3] if len(sys.argv) > 3 else None
for line in open(f"{root}/results.jsonl"):
    p = json.loads(line)
    if p["pass"] != want_pass: continue
    expected, allowed = set(p["expect"]), set(p["allow"])
    predicted = set(p["predicted"]) - (allowed - expected) - {"other"}
    missing, extra = expected - predicted, predicted - expected
    if not (missing or extra): continue
    if cat and cat not in expected and cat not in extra: continue
    print(f"== {p['file']}  expect={sorted(expected)} got={p['predicted']}")
    if missing: print("   missing:", sorted(missing))
    if extra: print("   wrong:", sorted(extra), {k: p['sources'].get(k) for k in extra})
    print("   rules:", {k: v[:6] for k, v in p["ruleHits"].items()})
    print("   vision:", dict(list(p["visionLabels"].items())[:5]), "app:", p.get("app"))
    print("   text:", p["text"][:260].replace("\n", " | "))
