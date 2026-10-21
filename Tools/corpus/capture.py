"""Captures Tools/corpus/sources.py in the booted iOS simulator.

    python3 Tools/corpus/capture.py build/corpus [--device UDID] [--only id-substring]

Writes <out>/web/<id>.png and <out>/web_manifest.json. Re-running skips ids already captured.
"""
import argparse, json, pathlib, subprocess, sys, time, urllib.parse, urllib.request

sys.path.insert(0, str(pathlib.Path(__file__).parent))
import importlib

ap = argparse.ArgumentParser()
ap.add_argument("out")
ap.add_argument("--device", default="booted")
ap.add_argument("--only")
ap.add_argument("--wait", type=float, default=6)
ap.add_argument("--sources", default="sources", help="module in Tools/corpus defining SOURCES (sources | holdout)")
args = ap.parse_args()
SOURCES = importlib.import_module(args.sources).SOURCES
out = pathlib.Path(args.out)
(out / "web").mkdir(parents=True, exist_ok=True)
manifest_path = out / "web_manifest.json"
manifest = {e["file"]: e for e in json.loads(manifest_path.read_text())} if manifest_path.exists() else {}


def sim(*cmd):
    return subprocess.run(["xcrun", "simctl", *cmd], capture_output=True, text=True)


def wiki_image(title):
    url = "https://en.wikipedia.org/api/rest_v1/page/summary/" + urllib.parse.quote(title.replace(" ", "_"))
    req = urllib.request.Request(url, headers={"User-Agent": "ScreenshotSorter-eval/1.0 (corpus capture)"})
    data = json.load(urllib.request.urlopen(req, timeout=20))
    thumb = data.get("thumbnail", {}).get("source")
    if thumb and "/thumb/" in thumb:
        # Wikimedia only serves standard thumbnail widths (…, 960, 1280, 1920)
        head, name = thumb.rsplit("/", 1)
        url = head + "/1280px-" + name.split("px-", 1)[1]
    else:
        url = data.get("originalimage", {}).get("source")
    if url:
        check = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "ScreenshotSorter-eval/1.0 (corpus capture)"})
        response = urllib.request.urlopen(check, timeout=20)
        if response.status != 200 or not response.headers.get("Content-Type", "").startswith("image/"):
            return None
    return url


for ident, target, expect, allow in SOURCES:
    if args.only and args.only not in ident:
        continue
    file = f"web/{ident}.png"
    if file in manifest and (out / file).exists():
        continue
    try:
        wait = args.wait
        if target.startswith("wiki:"):
            url = wiki_image(target[5:])
            if not url:
                print("no image:", ident); continue
            sim("openurl", args.device, url)
            wait = 4
        elif target == "home":
            sim("terminate", args.device, "com.apple.mobilesafari")
            sim("terminate", args.device, "com.apple.Maps")
            wait = 2
        else:
            if target.startswith("maps://"):
                sim("terminate", args.device, "com.apple.Maps")
            sim("openurl", args.device, target)
        time.sleep(wait)
        sim("io", args.device, "screenshot", "--type=png", str(out / file))
        manifest[file] = {"file": file, "expect": expect, "allow": allow, "source": target}
        manifest_path.write_text(json.dumps(list(manifest.values()), indent=1))
        print("ok", ident, flush=True)
    except Exception as e:  # keep going; a failed page is just skipped
        print("fail", ident, e, flush=True)
print("captured", len(manifest))
