"""Turn judged labels into truth.json.

    python3 Tools/eval/judge/truth.py <out dir>

labels.txt, one line per numbered tile:  "<n> expected,keys | acceptable,keys"
(empty expected = only "Other" fits; the right side lists labels that are fine but not required).
"""
import json, os, sys
out = sys.argv[1]
sample = {s["n"]: s for s in json.load(open(os.path.join(out, "sample.json")))}
truth = []
for line in open(os.path.join(out, "labels.txt")):
    if not line.strip():
        continue
    head, _, allow = line.partition("|")
    n, _, expect = head.strip().partition(" ")
    item = dict(sample[int(n)])
    item["expect"] = [k for k in expect.replace(" ", "").split(",") if k]
    item["allow"] = [k for k in allow.strip().replace(" ", "").split(",") if k]
    truth.append(item)
missing = sorted(set(sample) - {t["n"] for t in truth})
json.dump(truth, open(os.path.join(out, "truth.json"), "w"), indent=1)
print(f"{len(truth)} judged → {out}/truth.json" + (f" · not judged: {missing}" if missing else ""))
