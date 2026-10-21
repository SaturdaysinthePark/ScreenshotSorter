# Animation & UX QA checklist

Run on the linked Mac (Xcode 26 + Simulator via XcodeBuildMCP, see
`.agents/skills/ios-debugger-agent/SKILL.md`) and on a physical device for performance.
For every row: record the interaction (`xcrun simctl io booted recordVideo out.mov`), scrub
frame-by-frame, then repeat in **dark mode**, **Reduce Motion**, **largest Dynamic Type**,
**iPad**, and with **0 / 10 / 5,000** screenshots. Profile device runs with Instruments
(SwiftUI + Animation Hitches + Hangs + Points of Interest for pipeline signposts).

| # | Interaction | Expectation | Light | Dark | Reduce Motion | AX5 | iPad | Notes |
|---|---|---|---|---|---|---|---|---|
| 1 | Launch → splash → home | Splash ≤ 0.65s when cached, no flash of empty home | ✅ | ✅ | — | ✅ | ✅ | Fixed: onboarding faded in over the fading splash, so home showed through mid-crossfade. Now inserted opaque under the splash. |
| 2 | Photo access prompt → grant | Card stack illustration animates, home fades in | ✅ | — | — | — | — | |
| 3 | Onboarding pages 1–3 | Pile → stacks demo, flingable card, no clipped glass | ✅ | ✅ | — | ✅ | ✅ | Fixed (AX5): demo took the screen and titles started below the fold; demo now shrinks at accessibility sizes, wordmark capped. |
| 4 | Home: analysis card appears/disappears | Slides from top, collapses smoothly when idle | ✅ | ✅ | — | ✅ | ✅ | Fixed (AX5): text wrapped mid-word beside icon + pause button; stacks vertically at accessibility sizes. |
| 5 | Home: stats counters while sorting | numericText transitions, no layout jumps | ✅ | ✅ | — | ✅ | ✅ | |
| 6 | Home: shelf horizontal scroll | scrollTransition scale/opacity, 120Hz, snapping | ✅ | ✅ | — | ✅ | ✅ | |
| 7 | Category card → gallery | Zoom transition from card, back gesture zooms home | ✅ | ✅ | — | ✅ | ✅ | |
| 8 | Gallery: items arrive while analyzing | Gentle insertions, no scroll jump | ✅ | — | — | — | ✅ | Checked with 50 screenshots arriving; no scroll jumps seen. |
| 9 | Gallery thumbnail → detail | Zoom from thumbnail; after paging, dismiss returns to current thumbnail | ✅ | ✅ | — | — | ✅ | Fixed: pager could not page at all (zero frames recorded during swipes). The dismiss DragGesture claimed every pan; now a UIKit pan that only begins for vertical drags. |
| 10 | Detail: pinch / double-tap / drag-dismiss | Rubber-banding, background fade, no stutter | ✅ | — | — | — | ✅ | Pinch-in from zoom settles at fit (does not close), pinch-in at fit closes, like Photos. |
| 11 | Detail: insight sheet | Detents smooth, chips tappable, text selectable | ✅ | ✅ | — | — | ✅ | |
| 12 | Edit labels → move category | Haptic, card leaves gallery, undo toast restores | ✅ | — | — | — | ✅ | Fixed: undo left the "Add N similar" card up for the move it reversed; suggestions now carry their correction group. |
| 13 | Propagation card ("Add N similar") | Bouncy appear, accept files items | ✅ | — | — | — | ✅ | |
| 14 | Search typing | Results update ≤150ms debounce, no keyboard lag | ✅ | ✅ | — | ✅ | — | |
| 15 | Search result → detail | Zoom from row thumbnail | ✅ | ✅ | — | ✅ | — | |
| 16 | Review deck fling / undo / sort-into | Velocity-aware, stack promotes, threshold haptic once | ✅ | ✅ | — | ⚠️ | ✅ | AX5: "Start swiping" banner is below the fold on home; reachable by scrolling. |
| 17 | Review completion | Confetti, count-up, space freed figure | ✅ | — | — | — | ✅ | Only "kept everything" path exercised (no tosses → no space-freed figure). |
| 18 | Smart suggestion Keep / dismiss | Card animates into "Your collections" shelf | — | — | — | — | — | Not exercised: suggestions need ≥8 similar items; seed library too small. |
| 19 | Pause / resume sorting | Symbol replace transition, progress freezes/resumes | ✅ | ✅ | — | ✅ | — | |

Last run: 2026-10-20, iPhone 17 Pro + iPad Pro 11" (M5) simulators, iOS 26, 50 seeded screenshots,
driven by `QAWalkthroughTests` via `docs/qa/walkthrough.sh` (✅ looked right, ⚠️ minor, — not checked).
Reduce Motion ran combined with dark + AX5 but only stills were reviewed, so motion under it is unverified; 0 / 5,000-screenshot libraries not yet run.
Simulator note: Vision's classifier, face, barcode and feature-print requests have no inference
context in the iOS 26 simulator; extraction now continues with OCR only (logged once per request type).

## Performance targets (device, 500+ screenshots, fresh install, plugged in)
- Fast pass ≥ 15 screenshots/s; whole library categorized in < 1 min per 1,000.
- Deep pass 3–6/s (without language model); language model 0.5–1/s.
- No main-thread hangs > 100ms; zero animation hitches > 1 frame in gallery scroll and zoom.
- Search < 50 ms at 10k screenshots.
