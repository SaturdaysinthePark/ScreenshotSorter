import Foundation

// Home, search and smart-collection copy. Kept next to `Brand` so tone and name stay in one place.
extension Brand.Copy {
    enum Home {
        static let title: String = "Your stacks"
        static func greeting(for date: Date = Date()) -> String {
            let hour = Calendar.current.component(.hour, from: date)
            switch hour {
            case 5..<12: return "Good morning"
            case 12..<17: return "Good afternoon"
            case 17..<22: return "Good evening"
            default: return "Up late?"
            }
        }
        static let totalLabel: String = "Screenshots"
        static let sortedLabel: String = "% sorted"
        static let stacksLabel: String = "Stacks"
        static let allScreenshots: String = "All Screenshots"
        static let allScreenshotsSubtitle: String = "Every single one, newest first"
        static let yourCollections: String = "Your collections"
        static let sortMenu: String = "Sort stacks"
        static let moreMenu: String = "More"
        static let reanalyze: String = "Re-sort everything"
        static let reanalyzeConfirmTitle: String = "Re-sort every screenshot?"
        static let reanalyzeConfirmBody: String = "We'll take a fresh look at your whole library. Your manual edits are kept."
        static let pause: String = "Pause sorting"
        static let resume: String = "Resume sorting"
    }

    enum Analysis {
        static func sorting(_ done: Int, _ total: Int) -> String {
            "Sorting \(done.formatted()) of \(total.formatted())"
        }
        static func reading(_ remaining: Int) -> String {
            "Reading the fine print · \(remaining.formatted()) left"
        }
        static func polishing(_ remaining: Int) -> String {
            "Polishing titles · \(remaining.formatted()) left"
        }
        static func waitingForWiFi(_ count: Int) -> String {
            "\(count.formatted()) waiting for Wi-Fi"
        }
        static let waitingDetail: String = "They're in iCloud. We'll fetch them on Wi-Fi."
        static let paused: String = "Paused. Your screenshots will wait."
        static let lowPowerHint: String = "Taking it easy to save battery"
        static func speed(_ perSecond: Double) -> String {
            perSecond >= 1 ? "\(Int(perSecond.rounded()))/sec" : ""
        }
        static let doneTitle: String = "All sorted"
        static let pauseLabel: String = "Pause"
        static let resumeLabel: String = "Resume"
    }

    enum Search {
        static let prompt: String = "Search text, apps, “receipts last week”…"
        static let understoodAs: String = "Looking for"
        static func resultCount(_ count: Int) -> String {
            count == 1 ? "1 match" : "\(count.formatted()) matches"
        }
        static let searching: String = "Digging…"
        static let tipsTitle: String = "Try searching for"
        static let tips: [String] = ["wifi password", "receipts last month", "tweets with links", "flight", "\"order number\""]
    }

    enum Smart {
        static let sectionTitle: String = "Suggested for you"
        static let sectionSubtitle: String = "We spotted some patterns. Keep the ones you like."
        static let keep: String = "Keep"
        static let dismiss: String = "Not for me"
        static func count(_ value: Int) -> String { Brand.screenshots(value) }
        static let rename: String = "Rename"
        static let delete: String = "Remove collection"
        static let renamePrompt: String = "Collection name"
    }

    enum Propagation {
        static func title(_ count: Int, _ category: String) -> String {
            "Add \(Brand.screenshots(count)) that look similar to \(category)?"
        }
        static let accept: String = "Add them"
        static let decline: String = "Not now"
    }
}
