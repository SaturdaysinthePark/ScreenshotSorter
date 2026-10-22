import Foundation

// MARK: - Brand
/// Single source of truth for the app's name, voice and user-facing copy.
/// The product name is NOT final — never hard-code it anywhere else.
/// Rename the app by changing `appName` (and `tagline`) below.

enum Brand {
    static let appName: String = "What the Screen?"
    static let tagline: String = "Screenshots, sorted. Finally."

    /// "1 screenshot" / "3 screenshots"
    static func count(_ value: Int, _ singular: String, _ plural: String? = nil) -> String {
        let word: String = value == 1 ? singular : (plural ?? singular + "s")
        return "\(value) \(word)"
    }

    static func screenshots(_ value: Int) -> String {
        count(value, "screenshot")
    }

    // MARK: - Copy

    enum Copy {

        // MARK: Splash
        enum Splash {
            static let loading: String = "Shuffling your screenshots…"
            static var accessibilityLabel: String { "\(Brand.appName). Loading." }
        }

        // MARK: Photo access
        /// The system's progress UI (Live Activity) while sorting continues in the background
        enum Background {
            static let sortingTitle: String = "Sorting screenshots"
            static func progress(percent: Int, left: Int) -> String { "\(percent)% · \(left.formatted()) left" }
            static let doneTitle: String = "Screenshots sorted"
            static let doneSubtitle: String = "Finishing touches happen in the app"
        }

        enum Access {
            static let eyebrow: String = "Hey there 👋"
            static let title: String = "Let's tame that camera roll."
            static var body: String {
                "\(Brand.appName) sorts your screenshots into tidy stacks — receipts, memes, directions, the lot — so you can find things and toss the junk."
            }
            static let privacy: String = "Everything stays on your iPhone."
            static let privacyDetail: String = "Sorting happens on-device. Nothing is uploaded. Ever."
            static let cta: String = "Allow Photo Access"
            static let ctaHint: String = "Opens the system prompt to allow access to your photo library"
            static let footnote: String = "You can change this anytime in Settings."
            static let deniedTitle: String = "We can't see your screenshots"
            static let deniedBody: String = "Photo access is off. Turn it on in Settings and we'll get sorting."
            static let openSettings: String = "Open Settings"
        }

        // MARK: Onboarding
        enum Onboarding {
            static let skip: String = "Skip"
            static let next: String = "Next"
            static let getStarted: String = "Let's go"

            static let page1Eyebrow: String = "Step 1"
            static let page1Title: String = "Chaos in.\nOrder out."
            static let page1Body: String = "We read every screenshot and drop it in the right stack. 50+ categories, zero effort."

            static let page2Eyebrow: String = "Step 2"
            static let page2Title: String = "Swipe. Done."
            static let page2Body: String = "Swipe right to keep, left to toss. Go on — try it on the card above."
            static let page2Try: String = "Give it a fling"

            static let page3Eyebrow: String = "Step 3"
            static let page3Title: String = "Private by design."
            static let page3Body: String = "All the smarts run on your iPhone. Your screenshots never leave it."
            static let privacyPoint1: String = "On-device sorting"
            static let privacyPoint2: String = "No uploads, no accounts"
            static let privacyPoint3: String = "Search what's inside your screenshots"
            static let searchTeaser: String = "that wifi password"

            static func pageAccessibility(_ page: Int, of total: Int) -> String {
                "Page \(page) of \(total)"
            }
        }

        // MARK: Empty states
        enum Empty {
            static let noScreenshotsTitle: String = "Nothing to see here"
            static let noScreenshotsBody: String = "Take a screenshot and it'll show up here, already sorted."
            static let nothingToReviewTitle: String = "All caught up"
            static let nothingToReviewBody: String = "No screenshots waiting for a verdict. Go touch grass."
            static let noResultsTitle: String = "No matches"
            static let noResultsBody: String = "Try a different word — we search the text inside screenshots too."
            static let emptyCollectionTitle: String = "This stack is empty"
            static let emptyCollectionBody: String = "Screenshots you sort here will show up in this spot."
        }

        // MARK: Review (swipe deck)
        enum Review {
            static let keepStamp: String = "KEEP"
            static let tossStamp: String = "TOSS"
            static let sortStamp: String = "SORT"
            static let keep: String = "Keep"
            static let toss: String = "Toss"
            static let sortInto: String = "Sort into…"
            static let sortIntoSubtitle: String = "Pick a stack. We'll file it there."
            static let suggested: String = "Our best guesses"
            static let allCategories: String = "Everything else"
            static let close: String = "Close"
            static let closeHint: String = "Saves your progress and closes review"
            static let saveAndExit: String = "Save & exit"
            static let more: String = "More options"
            static let undo: String = "Undo"
            static let kept: String = "Kept it"
            static let tossed: String = "Tossed it"
            static let sorted: String = "Sorted"
            static let hint: String = "Swipe right to keep, left to toss"
            static let hintWithSort: String = "Right keeps, left tosses, up sorts"
            static let cardHint: String = "Swipe right to keep, left to toss. Use the actions rotor for more."

            static func progress(_ current: Int, _ total: Int) -> String {
                "\(current) of \(total)"
            }

            static func cardAccessibility(index: Int, total: Int, categories: String) -> String {
                if categories.isEmpty {
                    return "Screenshot \(index) of \(total)"
                }
                return "Screenshot \(index) of \(total). Looks like: \(categories)"
            }

            // Loading / resume
            static let loadingTitle: String = "Dealing your cards…"
            static let loadingBody: String = "Grabbing the first few screenshots."
            static let resumeTitle: String = "Pick up where you left off?"
            static func resumeBody(reviewed: Int, total: Int) -> String {
                "You'd sorted \(reviewed) of \(total). No pressure."
            }
            static let resume: String = "Resume"
            static let startOver: String = "Start over"
        }

        // MARK: Completion
        enum Completion {
            static let title: String = "Deck cleared!"
            static func subtitle(reviewed: Int) -> String {
                "You just judged \(Brand.screenshots(reviewed)). Iconic."
            }
            static let keptLabel: String = "Kept"
            static let tossedLabel: String = "Tossed"
            static let spaceLabel: String = "Space to free up"
            static let spaceCalculating: String = "Measuring…"
            static func confirmDelete(_ count: Int) -> String {
                "Toss \(Brand.screenshots(count))"
            }
            static let deleteWarning: String = "They'll move to Recently Deleted for 30 days."
            static let done: String = "Done"
            static let notNow: String = "Not now"
            static let goBack: String = "Wait, go back"
            static let deleteCancelled: String = "No worries — nothing was deleted."
            static let nothingTossed: String = "Kept everything? Respect."
        }

        // MARK: Banners
        enum Banners {
            static func reviewTitle(_ count: Int) -> String {
                "\(count.formatted()) to review"
            }
            static let reviewSubtitle: String = "Keep or toss — takes seconds."
            static let reviewSubtitleProcessing: String = "Still sorting. More may pop in."
            static let reviewCTA: String = "Review"
            static func unprocessedTitle(_ count: Int) -> String {
                "\(Brand.screenshots(count)) still unsorted"
            }
            static let unprocessedSubtitle: String = "Give us a sec and we'll stack them."
            static let unprocessedCTA: String = "Sort them now"
            static let later: String = "Later"
            static let dismiss: String = "Dismiss"
        }

        // MARK: Toasts
        enum Toast {
            static func undoAccessibility(_ message: String, seconds: Int) -> String {
                "\(message). \(seconds) seconds to undo."
            }
            static let undoHint: String = "Restores the last screenshot"
        }

        // MARK: Errors
        enum Errors {
            static let genericTitle: String = "Well, that's awkward"
            static let genericBody: String = "Something went sideways. Give it another go."
            static let deleteFailed: String = "Couldn't delete those. Nothing was lost."
            static let imageFailed: String = "Couldn't load this one"
            static let tryAgain: String = "Try again"
        }
    }
}
