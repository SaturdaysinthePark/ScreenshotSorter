"""Writes ScreenshotSorterTests/Fixtures/corpus_features.json from a harness export.

Keeps only cases whose text is safe to commit: mock screens (our own text) and full-screen photo
captures (clock + URL). Web-page captures stay in the local corpus because their OCR is third-party text.

    Tools/eval/run.sh --corpus build/corpus --pass deep --export build/corpus/export.json
    python3 Tools/eval/export_fixture.py build/corpus
"""
import json, pathlib, sys

root = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "build/corpus")
cases = json.loads((root / "export.json").read_text())
entries = {}
for name in ("mock_manifest.json", "web_manifest.json"):
    path = root / name
    if path.exists():
        entries.update({e["file"]: e for e in json.loads(path.read_text())})
keep = []
for case in cases:
    entry = entries.get(case["name"])
    if not entry or not (entry.get("source") == "mock" or str(entry.get("source", "")).startswith("wiki:")):
        continue
    if entry.get("allow"):
        case["allow"] = entry["allow"]
    keep.append(case)
out = pathlib.Path("ScreenshotSorterTests/Fixtures/corpus_features.json")
out.write_text(json.dumps(keep, indent=0, sort_keys=True, ensure_ascii=False))
print(f"wrote {len(keep)} of {len(cases)} cases to {out}")
