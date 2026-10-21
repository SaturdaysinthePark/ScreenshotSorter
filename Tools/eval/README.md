# Classification eval

Measures categories end to end — real Vision extraction (classifier + OCR) and the app's own rules and
fusion — on a labelled corpus of iPhone-sized screenshots. Vision's image classifier doesn't run in the
iOS 26 simulator, so the harness runs on macOS by compiling the app's analysis sources directly.

## Build the corpus (≈30 min, writes `build/corpus`, git-ignored)

```sh
python3 Tools/corpus/mocks.py build/corpus             # ~130 mock app screens (chats, feeds, receipts, passes…)
xcrun swift Tools/corpus/barcodes.swift build/corpus/assets   # real QR / Aztec / PDF417 codes used by the mocks
xcrun simctl privacy <udid> grant location com.apple.Maps
python3 Tools/corpus/capture.py build/corpus --device <udid>          # ~155 real captures (Safari, Maps, photos)
python3 Tools/corpus/capture.py build/holdout --sources holdout --device <udid>   # held-out set: score, never tune
```
Merge manifests: `build/corpus/manifest.json` = `mock_manifest.json` + `web_manifest.json`.
Check captures by eye (contact sheets) — consent walls, location prompts and logo-only lead images
have to be removed or relabelled; record such decisions in `sources.py`.

Labels: `expect` = what a person would file it under (all required); `allow` = acceptable extras
(neither rewarded nor counted as false positives); `forbid` = must not appear.

## Run

```sh
Tools/eval/run.sh --corpus build/corpus                 # fast + deep pass → report.md, results.jsonl
Tools/eval/run.sh --corpus build/corpus --filter web/   # only real captures
python3 Tools/eval/failures.py build/corpus deep        # every miss with rule hits, Vision labels and OCR text
```

## Lock in improvements

```sh
Tools/eval/run.sh --corpus build/corpus --pass deep --export build/corpus/export.json
python3 Tools/eval/export_fixture.py build/corpus       # → ScreenshotSorterTests/Fixtures/corpus_features.json
```
`CorpusRegressionTests` holds macro-F1 over those cases to a floor; raise it when accuracy improves.
Bump `PipelineVersion.rules` so existing libraries re-score from stored features.
