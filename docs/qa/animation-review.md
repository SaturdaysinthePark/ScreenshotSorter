# Animation & UX QA checklist

Run on the linked Mac (Xcode 26 + Simulator via XcodeBuildMCP, see
`.agents/skills/ios-debugger-agent/SKILL.md`) and on a physical device for performance.
For every row: record the interaction (`xcrun simctl io booted recordVideo out.mov`), scrub
frame-by-frame, then repeat in **dark mode**, **Reduce Motion**, **largest Dynamic Type**,
**iPad**, and with **0 / 10 / 5,000** screenshots. Profile device runs with Instruments
(SwiftUI + Animation Hitches + Hangs + Points of Interest for pipeline signposts).

| # | Interaction | Expectation | Light | Dark | Reduce Motion | AX5 | iPad | Notes |
|---|---|---|---|---|---|---|---|---|
| 1 | Launch → splash → home | Splash ≤ 0.65s when cached, no flash of empty home | | | | | | |
| 2 | Photo access prompt → grant | Card stack illustration animates, home fades in | | | | | | |
| 3 | Onboarding pages 1–3 | Pile → stacks demo, flingable card, no clipped glass | | | | | | |
| 4 | Home: analysis card appears/disappears | Slides from top, collapses smoothly when idle | | | | | | |
| 5 | Home: stats counters while sorting | numericText transitions, no layout jumps | | | | | | |
| 6 | Home: shelf horizontal scroll | scrollTransition scale/opacity, 120Hz, snapping | | | | | | |
| 7 | Category card → gallery | Zoom transition from card, back gesture zooms home | | | | | | |
| 8 | Gallery: items arrive while analyzing | Gentle insertions, no scroll jump | | | | | | |
| 9 | Gallery thumbnail → detail | Zoom from thumbnail; after paging, dismiss returns to current thumbnail | | | | | | |
| 10 | Detail: pinch / double-tap / drag-dismiss | Rubber-banding, background fade, no stutter | | | | | | |
| 11 | Detail: insight sheet | Detents smooth, chips tappable, text selectable | | | | | | |
| 12 | Edit labels → move category | Haptic, card leaves gallery, undo toast restores | | | | | | |
| 13 | Propagation card ("Add N similar") | Bouncy appear, accept files items | | | | | | |
| 14 | Search typing | Results update ≤150ms debounce, no keyboard lag | | | | | | |
| 15 | Search result → detail | Zoom from row thumbnail | | | | | | |
| 16 | Review deck fling / undo / sort-into | Velocity-aware, stack promotes, threshold haptic once | | | | | | |
| 17 | Review completion | Confetti, count-up, space freed figure | | | | | | |
| 18 | Smart suggestion Keep / dismiss | Card animates into "Your collections" shelf | | | | | | |
| 19 | Pause / resume sorting | Symbol replace transition, progress freezes/resumes | | | | | | |

## Performance targets (device, 500+ screenshots, fresh install, plugged in)
- Fast pass ≥ 15 screenshots/s; whole library categorized in < 1 min per 1,000.
- Deep pass 3–6/s (without language model); language model 0.5–1/s.
- No main-thread hangs > 100ms; zero animation hitches > 1 frame in gallery scroll and zoom.
- Search < 50 ms at 10k screenshots.
