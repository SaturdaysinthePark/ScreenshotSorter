# Sorting strategy (October 2026)

What we learned from a real 1,938-screenshot library, Pool (pool.day) and its reviews, ~10 other
screenshot apps, and Apple's iOS 26/27 on-device ML. Numbers marked *measured* come from
`Tools/eval/` (corpus 286 images, held-out 48, `--db` re-score of a real library); everything else is
cited research or an estimate.

## Where we stand against Pool

Pool ("the screenshot app", Random Access Memories, free, iOS 18+, launched Mar 2026) is the closest
competitor and it is **cloud-first**: it uploads the whole library, sends content to Google, OpenAI and
Anthropic, needs an account (Apple, phone or email) and talks publicly about screenshots as commercial
intent data. Its 96 written App Store reviews average 3.2★ (4.6★ since August):

- Loved: design and motion (~20), auto pools that fill themselves (~4), "search anything" (~3), links back
  to the source (~3), cleanup (2).
- Hated: invite/account gates (~27), crashes/heat/lag (~15), discovering the cloud upload (~9), shipping
  without automatic sorting (8), 700 MB+ app size, 32 GB of cellular data in a month.
- Top request (also across Captr, Screenshot Manager): keep screenshots after deleting them from Photos.

Across the category, users with 10k–25k backlogs want automatic sorting **with** control (rename, accept or
deny, switch off), and punish surprise paywalls and weekly plans.

**Our position:** everything Pool does, on the phone. No account, no upload, works in airplane mode, Data
Not Collected. Pixel Screenshots moved to cloud AI in June 2026, so this is now rare. It only wins if the
app also feels as good as Pool (design is what earns Pool its 5★ reviews).

## Classification: what the data says

*Measured on the real library before this round:* about 3 in 4 primary labels right. The errors were systematic:

| Problem | Cause | Fix (shipped in `f9aaae0`) |
|---|---|---|
| Tags like "bonus bet tokens" | Name tagger on garbled OCR | Names stay searchable, not shown as tags (8,182 → 2,256 tags) |
| 14 "memes", all wrong | All-caps caption pattern fired on ads and menus | No prices, codes or links; sparse screens only (→ 1) |
| News on every "New York" screen | "news" stemmed to "new" | Unstemmed word list (71 → 28) |
| Maps place cards as Directions | Maps app mapped to Directions | Maps → Places; routes need route cues (Directions 79 → 30) |
| Documents as a catch-all | Vision says "document" about 96% of screenshots | Not evidence any more (93 → 31) |
| People on 1 in 5 screenshots | Someone visible in any post | Face-less People needs more evidence inside apps (370 → 296) |
| Model's guesses (events, memes, reading…) | Text-only model, ~0.9 confidence on everything | Model corroborates, can't label alone |

Library-wide, "Other" rose from 151 to 264: a wrong shelf is worse than Unsorted. Corpus macro-F1 went
from 0.861 to 0.864; held-out from 0.793 to 0.824.

### The language model

*Measured* (text only, macOS 26, same model family as iOS 26):

Topic accuracy counts screenshots that have a topic to find; app-only cases don't count, since the model never picks apps.

| Prompt and schema | Topic right | Extra picks right | Fused macro-F1 vs rules only | p50 |
|---|---|---|---|---|
| v1: 70 bare keys, 0–100 confidence, apps allowed | 59% | 26% | 0.856 vs 0.868 (hurts) | 1.69 s |
| v2: + 16 lines of category definitions, "other" last | ~47% on a partial run (stopped) | | | |
| C: summary first, topics only, "other" first, sure/likely/unsure, short prompt | 73% | 17% | 0.865 vs 0.866 | 1.45 s |
| E: C + plain topic names (`qrCode`, `paymentReceipt`, `code`) + merged categories | 75% | 10% | 0.885 vs 0.877 (helps) | 1.43 s |
| **F: E, not asked about screenshots with <3 text lines; a "sure" topic fills gaps inside apps** | **82% when asked** (84% held-out) | 10% | **0.880 vs 0.874; held-out 0.847 vs 0.836** | 1.44 s, **~30% fewer calls** |

What moved the numbers:
- The model defaults to the first enum case when unsure. "Events" first meant boarding passes became events; "other" first makes doubt safe.
- Case names are read literally. `codes` (QR codes) collected code screenshots, and `receipts` took every price tag.
- Long definitions hurt this small model; one-line instructions do better.
- Describing before choosing helps.
- Without the image, the model answers "receipts" or "events" for almost every photo, so photos aren't sent to a
  text-only model. Inside a TikTok/Reddit post with no other topic, its "sure" answers were right about 3 in 4
  times. On stand-alone ads it was about a coin flip, so filling the gap is limited to app posts.
- The extra picks field helps the main pick when present, even though its own picks are mostly wrong. It is kept in the schema, but text-only fusion ignores it.

On iOS 26 the model only reads OCR text, and on a TikTok or Instagram post the text is mostly chrome
("Following · For You · 12.4K"). **iOS 27 lets the model see the image** (`Attachment`,
`capabilities.contains(.vision)`). The app now sends a 768px copy when the model can see. Image-backed "sure"
answers may label on their own, while text-only answers still need agreement. This is the single biggest
expected accuracy gain for feed screenshots. It is **not yet measured**: macOS 26 can't run it, so measure it
on an iOS 27 phone first.

Research notes that shape how we use it:
- There are no log-probabilities, and stated confidence is overconfident (Xiong et al. 2024), so calibration
  has to come from agreement between sources and the eval corpus, not from the model.
- Fields are generated in order, so describe first, then classify. Greedy decoding is only deterministic per
  OS model version, so store the model version with each result and re-run when it changes.
- The adapter (LoRA) toolkit does not work on OS 27, so fine-tuning is not an option.
- Apple's Private Cloud Compute model exists on iOS 27, but using it would break our "nothing is uploaded"
  promise, so it stays off.

## Categories (October 2026)

From 71 to 54. Merged where users don't browse them separately and the classifiers confuse them:
- Nature & Outdoors ← nature, landscapes, beaches, mountains, flowers, sunset
- Places ← places, storefronts, sites of interest
- Recipes ← recipes, cooking
- Health & Fitness ← health, exercise
- Books & Reading ← books, reading
- Messages ← iMessage, WhatsApp, Signal, Telegram, Discord, Slack (the app still shows on each screenshot and in search)
- Email ← email, Gmail

Renamed to what people call them: Stores → Shopping, Flights & Travel → Travel, Homes → Home & Interior, Art → Art & Design,
Programming → Code, Money & Finance → Money, Orders & Shipping → Orders & Deliveries.

Old keys resolve to the new categories (`ScreenshotCategory.mergedKeys`), so stored labels and corrections carry over.

On home, topic shelves come before app shelves (TikTok, Instagram…), and collections are one two-column grid.

Considered for later:
- **IDs & Cards** (passports, licences; iOS 27 Photos added Identity Documents). It's sensitive and needs careful rules.
- **Work** (meeting notes, docs, tickets). It overlaps with Documents and Notes today.

**Your own collections:** "+ New" on home. Name it ("Barcelona trip", "Gift ideas"), see what search already finds
(text, meaning, dates), then Create. The collection's centroid is the mean of its members, so new screenshots that
look like them join on their own (same rule as kept smart collections: similar to the centroid and to ≥5 members).

## Scale: 2,000–25,000 screenshots

| Stage | Rate on device (*measured*, iPhone 17 Pro, cool) | 10k library |
|---|---|---|
| Fast pass (preview, labels, fast OCR) | ~8/s | ~20 min |
| Deep pass (accurate OCR, entities, embedding) | 3.5–4.9/s | ~40 min |
| Language model, one at a time | ~0.4/s | ~7 h |

Already in place: newest first, iCloud originals only on Wi-Fi (preview otherwise), thermal/Low Power
budgets, the model in its own lane after text and search are done. This round:
- Screenshots with no topic yet (only an app, a face-less "People", or Other) go to the model first, where
  seeing the post helps most.
- Rule changes apply immediately even to screenshots still waiting for the model (before, about 947 on a
  real phone kept old labels until the model reached them).
- Home shelves keep their order while sorting runs, and topic shelves rank before app shelves.

**Risk to verify on device:** iOS 27 restricts background Neural Engine use unless the app has
`com.apple.developer.background-tasks.continued-processing.inference`. Whether Vision and Foundation Models
count is undocumented. Test the overnight `BGProcessingTask` and the continued-processing task on iOS 27
before relying on them.

## Experience: what to copy from Pool, and do better

Shipped this round:
- **One primary action per screenshot** in the viewer (Copy code, Open in Maps, Open the shop's site, Call,
  Copy tracking number), chosen on-device from the topic and what was read. Nothing is fetched until the
  user taps.
- **Topics before apps** on home (Pool shows "Recipes", "Shopping", "Interior", not "TikTok").
- **"+N new" on collection cards** since you last opened them (Pool), with the total once seen.
- **A calmer home:** one compact sorting line (hidden once only titles are being polished), at most one next-step
  card, a slim All Screenshots row, then a two-column collection grid with fanned-stack covers, "Show all", "+ New".
- **Collections you name** (see Categories).

Next, ranked by value / effort:
1. **First minute:** a usable grid, text search and the first shelves within ~60 s on a 10k library, with honest
   progress ("3,200 of 10,000 sorted"). Publish a measured claim. Nobody in the category does.
2. **Accept, rename, deny:** let users rename shelves and smart collections, approve or deny suggestions
   (Pixel's carousel), and switch auto-sorting off per collection.
3. **Add to a collection from the viewer**, and teach a collection with a few examples.
4. **Keep after deleting from Photos:** a compressed on-device archive, with very clear warnings. This is the
   number one request in the category. Medium–high effort. Make data-loss risks explicit.
5. **Feed-aware image signal:** crop the media region out of app chrome (saliency) before Vision
   classification and the model. Medium effort.
6. **Image–text embeddings** for zero-shot topics, "search anything" and learning from corrections (Tip-Adapter-style
   kNN). The license matters: MobileCLIP2 weights are research-only and SigLIP 2 is Apache-2.0. It adds a downloaded
   model (Background Assets). Medium–high effort.
7. **Pricing:** a generous free tier (sorting and search), a one-time unlock for power cleanup. No weekly plans.

Avoid: accounts, invite gates, any upload, server-side fetching of URLs seen in screenshots, cellular
downloads, surprise paywalls, a huge binary.

## How to measure

- `Tools/eval/run.sh --corpus build/corpus --pass deep [--model]`: rules, plus the language model (text only on macOS 26).
- `Tools/eval/run.sh --db <copy of analysis.sqlite> [--model --limit 120]`: a real library, before/after, with the
  model on a sample.
- On device: the `Budget` and `Sorting:` log lines, and signposts `fastPass`, `deepPass` and `languageModel` (see CLAUDE.md).
