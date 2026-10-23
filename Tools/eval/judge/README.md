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

## 5. Every shelf

Spot checks find what you happen to open. To judge every collection, sample 12 random members per category from a
re-score, make one contact sheet per shelf (`collection_sheets.py` takes the same JSON shape), judge each tile
right / wrong / borderline into `build/phone/audit/verdicts.json` (`{category: {id8: verdict}}`), then:

```sh
python3 Tools/eval/judge/shelf_score.py build/phone/audit/verdicts.json build/phone/rescore.jsonl
```

Every shelf counts the same, the way someone browsing collections sees them. "lost" counts right members a change
dropped; check it next to `score.py`, which measures recall.

## 6. Every screenshot

The thorough pass: contact sheets of the whole library, 8 per sheet, each tile showing collections, title, tags,
the button and details as the viewer does. Reviewers write one JSON verdict per screenshot (wrong and missing
collections, title good/meh/bad, noise tags, button right/wrong/missing/none-ok, detail noise). Then:

```sh
python3 Tools/eval/judge/full_review.py build/phone2/review build/phone2/notes.jsonl [build/phone2/rescore.jsonl]
```

With a re-score it also says what a change did against the verdicts (expected = shown − wrong + missing). Because
every screenshot has a verdict, a rule can be tried in a few lines of Python on the OCR text before it's written in
Swift: count how many it adds right and wrong.

## Results, October 2026 (iPhone 17 Pro, 1,938 screenshots, 229 judged)

| | precision | recall | macro-F1 | exactly right |
|---|---|---|---|---|
| Phone's labels before this pass | 0.72 | 0.58 | 0.582 | 75 |
| Same stored features, current rules | 0.81 | 0.69 | 0.638 | 99 |
| Fresh first run on the phone (rules 6) | 0.83 | 0.68 | 0.631 | 96 |
| Same, rules 7 (below) | 0.93 | 0.65 | 0.656 | 107 |

On the 1024 px previews end to end (Mac, model text-only): rules 0.621 → with the model 0.654 macro-F1. The model's
topic was right 72% of the time on real posts, at p50 1.6 s. On iOS 27 it also sees the image, which is not
measurable on a Mac.

Collections, right in the top 12, before → after: cars 3 → 6, japan trip 6 → 10; matcha 12, coffee 11,
watches 12, anime 10.

The sentence embedding scores a one-word name against a whole screenshot near zero, and *lower* for screenshots
containing the word than for unrelated ones. So collections match on titles and tags, plus words repeated on screen,
not on embedding similarity.

Every shelf, 12 random members each (498 judged): 61% right on the phone's first run, 80% with rules 7. Single
evidence was the cause: a label backed by one source only (one word in a caption or an ad, an object in the
background, the model's lone guess) was right about half the time, a corroborated one ~9 in 10. A second topic from
one source was right 10 times in 45. So: weak words never label alone in most text categories (`minWeakHits: 99`),
a second topic needs two sources or 0.8, People inside an app needs a face and no other topic, product barcodes
aren't codes, and a rule's negative terms veto the model too. The tuning corpus moved 0.873 → 0.877 and the
held-out set 0.842 → 0.851 macro-F1.

Whole library, every screenshot judged (1,938): collections all right 850 → 905, label precision 0.868 → 0.885,
recall 0.685 → 0.705; noise tags 2,218 → 645; 29 wrong buttons removed, 14 changed to what reviewers suggested,
none lost. Titles: the language model's were bad 15% of the time, the text fallback's 54% — so titles mostly improve
as the model reaches every screenshot. A more specific title instruction brought the model's titles closer to the
reviewers' (similarity 0.41 → 0.46 on 116) with its topics unchanged within noise (69 → 67 right).
