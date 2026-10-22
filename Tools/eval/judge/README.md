# Judge eval: your own screenshots, judged blind

The corpus in `Tools/eval` is clean and public. This one measures what matters, a real library, with labels
judged by looking at each screenshot without seeing what the app said.

Everything here holds the owner's own screenshots and text. It lives in `build/` (git-ignored): never commit it,
and never send it anywhere.

## 1. Export from the phone (Debug build only)

```sh
# Install a Debug build, then launch it with the export flag (sorting paused so it runs fast)
xcrun devicectl device process launch --terminate-existing --device <id> sabtain.ScreenshotSorter -- \
  -QAExportScreenshots 0 -QAPauseAnalysis YES
# ~3 min for 2k screenshots, then copy the archive and a database snapshot
xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
  --domain-identifier sabtain.ScreenshotSorter --source Documents/qa-export.tar --destination build/phone/qa-export.tar
(cd build/phone && tar -xf qa-export.tar)          # img/*.jpg (1024 px previews) + export.json
for f in analysis.sqlite analysis.sqlite-wal analysis.sqlite-shm; do xcrun devicectl device copy from --device <id> \
  --domain-type appDataContainer --domain-identifier sabtain.ScreenshotSorter \
  --source "Library/Application Support/ScreenshotSorter/$f" --destination build/phone/db/$f; done
```

`Services/QAExport.swift` is compiled into Debug builds only, and only uses on-device previews, so nothing is
downloaded.

## 2. Sample and judge

```sh
python3 Tools/eval/judge/sample.py build/phone/db/analysis.sqlite build/phone build/phone/judge 4 40
python3 Tools/eval/judge/sheets.py build/phone/judge        # numbered contact sheets, no labels
```

The sample is stratified: up to N per category the app assigned, so rare labels get judged, plus M at random, so
precision isn't only measured where the app already said something.

Write `build/phone/judge/labels.txt`, one line per tile: `<n> expected,keys | acceptable,keys`. Use the category
keys from `ScreenshotCategory`. An empty left side means only "Other" fits. The right side lists labels that are
fine but not required, for example `people` on a fashion post.

Rubric:
- Expected = what someone would file it under. That's the app it came from (tiktok, instagram, reddit…) plus
  what it is about.
- A person merely appearing isn't `people`.
- A shop's product page is `stores` plus the product type.
- Ads are judged on what they sell.

```sh
python3 Tools/eval/judge/truth.py build/phone/judge
```

## 3. Score

```sh
# What the phone currently shows
python3 Tools/eval/judge/score.py build/phone/judge/truth.json build/phone/db/analysis.sqlite --manifest build/phone
# Current code on the phone's own stored features (full-resolution OCR from the phone): the faithful number
Tools/eval/run.sh --db build/phone/db/analysis.sqlite --out build/phone/rescore.jsonl
# Current code end to end on the 1024 px previews (lower: preview OCR), optionally with the model
Tools/eval/run.sh --corpus build/phone --pass deep [--model]
```

## 4. Collections

```sh
Tools/eval/run.sh --db build/phone/db/analysis.sqlite --collections "books,coffee,matcha,cars" --out build/phone/collections.json
python3 Tools/eval/judge/collection_sheets.py build/phone/collections.json build/phone build/phone/judge/collections
```

Judge precision of the top 12 per name, the way a New Collection fills itself (`SearchScope.whatItShows`).

## Results, October 2026 (iPhone 17 Pro, 1,938 screenshots, 229 judged)

| | precision | recall | macro-F1 | exactly right |
|---|---|---|---|---|
| Phone's labels before this pass | 0.72 | 0.58 | 0.582 | 75 |
| Same stored features, current rules | 0.81 | 0.69 | 0.638 | 99 |

Collections, right in the top 12, before → after: cars 3 → 6, japan trip 6 → 10; matcha 12, coffee 11,
watches 12, anime 10.

The sentence embedding scores a one-word name against a whole screenshot near zero, and *lower* for screenshots
containing the word than for unrelated ones. So collections match on titles and tags, plus words repeated on screen,
not on embedding similarity.
