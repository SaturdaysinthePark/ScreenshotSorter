"""Pick a stratified sample of a real library for judging.

    python3 Tools/eval/judge/sample.py <analysis.sqlite> <export dir> <out dir> [per_category] [random]

Takes up to `per_category` screenshots for every top topic the app assigned (so rare labels get judged
too), plus `random` more at random (so precision isn't only measured where the app already said something),
and writes <out>/sample.json: [{"n", "file", "id"}]. Labels are NOT included: judging is blind.
"""
import json, os, random, sqlite3, sys

db_path, export_dir, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
per_category = int(sys.argv[4]) if len(sys.argv) > 4 else 5
extra = int(sys.argv[5]) if len(sys.argv) > 5 else 40
apps = {"tiktok", "instagram", "twitter", "facebook", "linkedin", "reddit", "youtube", "messages", "email"}

exported = {e["id"]: e["file"] for e in json.load(open(os.path.join(export_dir, "export.json")))}
db = sqlite3.connect(db_path)
by_topic = {}
for asset_id, categories in db.execute("SELECT id, categories FROM assets"):
    if asset_id not in exported:
        continue
    keys = [p.split(":")[0] for p in categories.split(",") if p]
    topic = next((k for k in keys if k not in apps), keys[0] if keys else "other")
    by_topic.setdefault(topic, []).append(asset_id)

rng = random.Random(7)
chosen = []
for topic in sorted(by_topic):
    ids = by_topic[topic][:]
    rng.shuffle(ids)
    chosen += ids[:per_category]
rest = [i for ids in by_topic.values() for i in ids if i not in set(chosen)]
rng.shuffle(rest)
chosen += rest[:extra]
rng.shuffle(chosen)

os.makedirs(out_dir, exist_ok=True)
sample = [{"n": n + 1, "file": os.path.join(export_dir, exported[i]), "id": i} for n, i in enumerate(chosen)]
json.dump(sample, open(os.path.join(out_dir, "sample.json"), "w"), indent=1)
print(f"{len(sample)} screenshots from {len(by_topic)} topics → {out_dir}/sample.json")
