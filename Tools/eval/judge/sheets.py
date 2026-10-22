"""Contact sheets for judging: numbered tiles, no labels (blind).

    python3 Tools/eval/judge/sheets.py <out dir> [columns] [rows] [tile width]
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

out_dir = sys.argv[1]
cols = int(sys.argv[2]) if len(sys.argv) > 2 else 3
rows = int(sys.argv[3]) if len(sys.argv) > 3 else 2
tile_w = int(sys.argv[4]) if len(sys.argv) > 4 else 420
tile_h = int(tile_w * 2.17)
sample = json.load(open(os.path.join(out_dir, "sample.json")))
sheet_dir = os.path.join(out_dir, "sheets")
os.makedirs(sheet_dir, exist_ok=True)
try:
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 34)
except OSError:
    font = ImageFont.load_default()
per = cols * rows
for start in range(0, len(sample), per):
    sheet = Image.new("RGB", (cols * (tile_w + 10) + 10, rows * (tile_h + 50) + 10), (40, 40, 40))
    draw = ImageDraw.Draw(sheet)
    for k, item in enumerate(sample[start:start + per]):
        x, y = 10 + (k % cols) * (tile_w + 10), 10 + (k // cols) * (tile_h + 50)
        try:
            im = Image.open(item["file"]).convert("RGB")
            im.thumbnail((tile_w, tile_h))
            sheet.paste(im, (x, y + 44))
        except OSError:
            pass
        draw.text((x + 4, y + 2), f"#{item['n']}", fill=(255, 220, 0), font=font)
    sheet.save(os.path.join(sheet_dir, f"sheet_{start // per + 1:03d}.jpg"), quality=80)
print(f"{(len(sample) + per - 1) // per} sheets → {sheet_dir}")
