# ScreenshotSorter

iOS 26-only SwiftUI app that sorts screenshots into categories with on-device AI, makes their
text searchable and helps users clean up. Product name ("What the Screen?") is **not final** —
all user-facing copy and the name live in `ScreenshotSorter/Utilities/DesignSystem/Brand*.swift`.

## Build & test
- Xcode 26, scheme `ScreenshotSorter` (shared). New files under `ScreenshotSorter/` are picked up
  automatically (synchronized folders) — don't edit `project.pbxproj` to add files.
- Unit tests (Swift Testing, no Vision dependency → fine on the simulator):
  `xcodebuild test -project ScreenshotSorter.xcodeproj -scheme ScreenshotSorter -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ScreenshotSorterTests`
- **Vision image classification does not work in the iOS 26 simulator** — measure classification
  speed/accuracy on a physical device. UI work is fine on the simulator.
- Device profiling without Xcode UI: `xcrun xctrace record --device <udid> --template Logging
  --instrument 'Activity Monitor' --all-processes --time-limit 60s` (Release builds can't be attached
  to), then `xctrace export --xpath …os-log / OSSignpostIntervals`. Pipeline signposts: fastPass,
  fastLoad, fastVision, deepPass, languageModel, embed. Check the `Budget` log line first — a warm
  phone (`thermal=2`) runs one item at a time by design.
- Swift 5 language mode; no third-party packages.

## Architecture
- `Stores/AppModel.swift` — `@MainActor @Observable` app model injected via `.environment`. Owns
  every service; views call it for actions (corrections, delete, search, smart collections).
- `Stores/LibraryStore.swift` — in-memory library (`Screenshot` by id, category membership sets).
  Updates are incremental; never rebuild everything.
- `Persistence/AnalysisStore.swift` — SQLite (built-in `SQLite3`) with FTS5 full-text search,
  embeddings, feature prints, corrections, smart collections. Categories persist by stable
  `ScreenshotCategory.key`, never by display name.
- `Analysis/` — the pipeline:
  - `AnalysisScheduler` (actor): sliding-window concurrency, urgent → fast → deep → model lanes,
    budgets from `ResourceGovernor` (thermal / Low Power / background). The language model runs one
    at a time and only after deep work is done (~2–3 s per request on device, serialised system-wide).
  - `AnalysisPipeline`: fast pass (1280px, one Vision handler: classifier + fast OCR + barcodes +
    faces) → deep pass (2048px, accurate OCR + feature print, entities, embedding; decides if the
    model is worth it) → model pass (Foundation Models from stored features) → `rescore` (rules/fusion
    from stored features, no pixels).
  - iCloud-only originals ("Optimize iPhone Storage" — often >90% of a real library) download only when
    `Services/NetworkPolicy` allows (not cellular/hotspot, not Low Data Mode). Otherwise the fast pass
    uses the on-device preview and items are parked (`waitingForNetwork`) until Wi-Fi returns.
  - `ScreenshotClassifier` (pure): `TextNormalizer` (token-boundary matching, screen zones),
    `RuleEngine` + `CategoryRules`, `AppDetector` + `AppSignatures`, `VisionLabelMap`,
    `EntityExtractor`, `SignalFusion` (noisy-OR with per-source reliabilities, user overrides).
  - `FoundationModels/`: guided generation constrained to `CategoryKey` (must mirror
    `ScreenshotCategory`; enforced by `CategoryKeySyncTests`). Optional — everything works without it.
  - `SmartCollections/`: conservative clustering → suggestions (≥8 members, ≤3 visible, Keep required).
- `Learning/UserFeedbackLearner.swift` — corrections override; kNN propagation needs ≥2 agreeing
  neighbours; per-category calibration.
- `Search/` — `QueryParser` (dates/apps/categories/entities), `SearchService` (BM25 + typo
  tolerance + trigram + sentence embeddings, reciprocal rank fusion), `VectorIndex`.
- `Background/BackgroundAnalysisManager.swift` — `BGContinuedProcessingTask` + overnight
  `BGProcessingTask` (identifiers in `Config/Info.plist`, merged with the generated plist).
- `Utilities/DesignSystem/` — Brand/copy, Palette (per-`CategoryGroup` hues), Typography, Space/Radius,
  Motion (always Reduce-Motion aware), buttons, cards, components. Use these; don't hard-code
  colors, fonts or animations.

## Changing classification
0. Measure first: `Tools/eval/` runs real Vision + the app's rules on a ~290-image labelled corpus on macOS
   (see `Tools/eval/README.md`); `failures.py` explains every miss. Check the held-out set before calling a win.
1. Edit rules in `Analysis/Rules/` (or fusion weights in `FusionConfig`).
2. Add/adjust cases in `ScreenshotSorterTests/Fixtures/golden_features.json` (export real ones from
   the DEBUG "Evaluation" screen in the home ⋯ menu, scrub personal text).
3. Run `GoldenSetTests` and `CorpusRegressionTests`; keep macro-F1 ≥ the floors and every category reachable.
4. Bump `PipelineVersion.rules` so existing libraries re-score from stored features (no re-OCR).
   Bump `.vision` only when image extraction changes.

## Conventions
- Animations go through `Motion` / `.dsAnimation`; test with Reduce Motion, dark mode, largest
  Dynamic Type and iPad. See `docs/qa/animation-review.md` for the QA checklist.
- Haptics via `HapticManager` (not disabled by Reduce Motion).
- Libraries of 2k–25k screenshots are normal. Main-actor work per frame or per analysis batch must not be
  O(library): use `LibraryStore.preview(for:)` for cards/shelves, keep counters incremental. `ScaleTests`
  enforces budgets at 25k.
- Logs: subsystem `sabtain.ScreenshotSorter` — `Scheduler` (throughput every 10 s, budget changes),
  `Pipeline` (failures; per-screenshot decisions at debug level), `Vision` (unavailable requests, once each).
- UI walkthrough for `docs/qa/animation-review.md`: `QAWalkthroughTests` via `docs/qa/walkthrough.sh`.
