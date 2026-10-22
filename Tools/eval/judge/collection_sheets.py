"""Contact sheets for judging New Collection results: one sheet per query, top 12, numbered.

    python3 Tools/eval/judge/collection_sheets.py <collections.json> <export dir> <out dir> [mode]

mode: whatItShows (default, what a New Collection fills with) or everything (plain search).
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont
results, export_dir, out_dir = json.load(open(sys.argv[1])), sys.argv[2], sys.argv[3]
mode = sys.argv[4] if len(sys.argv) > 4 else "whatItShows"
files = {e["id"]: os.path.join(export_dir, e["file"]) for e in json.load(open(os.path.join(export_dir, "export.json")))}
os.makedirs(out_dir, exist_ok=True)
font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 30)
cols, rows, w = 4, 3, 300
h = int(w * 2.17)
for q, r in enumerate(results):
    ids = r[mode][:cols * rows]
    sheet = Image.new("RGB", (cols * (w + 8) + 8, rows * (h + 44) + 60), (40, 40, 40))
    d = ImageDraw.Draw(sheet)
    d.text((10, 10), f"\"{r['query']}\"  ({r[mode + 'Count']} matches)", fill=(255, 255, 255), font=font)
    for k, i in enumerate(ids):
        x, y = 8 + (k % cols) * (w + 8), 60 + (k // cols) * (h + 44)
        try:
            im = Image.open(files[i]).convert("RGB"); im.thumbnail((w, h)); sheet.paste(im, (x, y + 40))
        except (KeyError, OSError):
            pass
        d.text((x + 4, y + 4), f"{k + 1}", fill=(255, 220, 0), font=font)
    sheet.save(os.path.join(out_dir, f"q{q + 1:02d}_{r['query'].replace(' ', '_')}.jpg"), quality=78)
print(f"{len(results)} sheets → {out_dir}")
