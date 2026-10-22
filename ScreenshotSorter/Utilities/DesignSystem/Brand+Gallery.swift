import Foundation

// Gallery, photo detail and label-editing copy. Kept next to `Brand` so tone and name stay in one place.
extension Brand.Copy {

    // MARK: Gallery (collection grid)
    enum Gallery {
        static let select: String = "Select"
        static let done: String = "Done"
        static let selectAll: String = "Select all"
        static let deselectAll: String = "Deselect all"
        static let sort: String = "Sort"
        static let sortHint: String = "Changes the order of screenshots"
        static func stillSorting(_ count: Int) -> String { "\(count.formatted()) still sorting" }
        static func newThisWeek(_ count: Int) -> String { "\(count.formatted()) this week" }
        static let today: String = "Today"
        static let yesterday: String = "Yesterday"
        static let thisWeek: String = "This week"
        static func selectedCount(_ count: Int) -> String {
            count == 0 ? "Tap screenshots to select" : "\(count) selected"
        }
        static let share: String = "Share"
        static let move: String = "Move"
        static let moveTo: String = "Move to…"
        static let moveSubtitle: String = "Pick a new stack. We'll learn from it."
        static let remove: String = "Remove"
        static let delete: String = "Delete"
        static func removeHint(_ name: String) -> String { "Removes the selection from \(name)" }
        static func deleteTitle(_ count: Int) -> String { "Delete \(Brand.screenshots(count))?" }
        static func moved(_ count: Int, to name: String) -> String { "Moved \(Brand.screenshots(count)) to \(name)" }
        static func removed(_ count: Int, from name: String) -> String { "Removed \(Brand.screenshots(count)) from \(name)" }
        static func deleted(_ count: Int) -> String { "Deleted \(Brand.screenshots(count))" }
        static func added(_ count: Int, to name: String) -> String { "Added \(Brand.screenshots(count)) to \(name)" }
        static let notSortedYet: String = "Not sorted yet"
        static let openHint: String = "Opens full screen"
        static let selectHint: String = "Toggles selection"
        static let selected: String = "Selected"
        static let preparingShare: String = "Getting them ready…"
        static let shareFailed: String = "Couldn't get those ready to share."
        static func cellAccessibility(title: String?, date: String) -> String {
            if let title, !title.isEmpty {
                return "\(title), \(date)"
            }
            return "Screenshot, \(date)"
        }
        static func propagationTitle(_ count: Int, _ category: String) -> String {
            "Add \(count) similar \(count == 1 ? "screenshot" : "screenshots") to \(category)?"
        }
        static let propagationBody: String = "They look a lot like the ones you just sorted."
        static let propagationAdd: String = "Add them"
        static let propagationNotNow: String = "Not now"
        static let allEyebrow: String = "Everything"
        static let smartEyebrow: String = "Smart collection"
    }

    // MARK: Photo detail
    enum Detail {
        static let close: String = "Close"
        static let share: String = "Share"
        static let more: String = "More options"
        static let editLabels: String = "Edit labels"
        static let delete: String = "Delete"
        static let deleteTitle: String = "Delete this screenshot?"
        static func position(_ index: Int, _ total: Int) -> String { "\(index) of \(total)" }
        static let insightsHint: String = "Drag up or tap for details"
        static let expand: String = "Show details"
        static let collapse: String = "Hide details"
        static let fallbackTitle: String = "Screenshot"
        static func fromApp(_ app: String) -> String { "From \(app)" }
        static let categories: String = "Stacks"
        static let tags: String = "Tags"
        static let text: String = "Text we found"
        static let copy: String = "Copy"
        static let copyText: String = "Copy text"
        static let copied: String = "Copied"
        // Quick actions (one per screenshot, chosen from what it's about)
        static func copyCode(_ code: String) -> String { "Copy code \(code)" }
        static let copyTracking: String = "Copy tracking number"
        static let openInMaps: String = "Open in Maps"
        static func openSite(_ site: String) -> String { "Open \(site)" }
        static let call: String = "Call"
        static let textCopied: String = "Text copied"
        static let showMore: String = "Show more"
        static let showLess: String = "Show less"
        static let actions: String = "Quick actions"
        static let similar: String = "Looks similar"
        static let edit: String = "Edit"
        static let noTags: String = "No tags yet"
        static let notSorted: String = "Not sorted yet — hang tight."
        static let reading: String = "Still reading this one…"
        static let photoHint: String = "Double-tap to zoom. Swipe down to close."
        static func zoomLevel(_ percent: Int) -> String { "Zoomed to \(percent) percent" }
        static let zoomIn: String = "Zoom in"
        static let zoomOut: String = "Zoom out"
        static let openHint: String = "Opens in another app"
        static let copyHint: String = "Copies to the clipboard"
        static let similarHint: String = "Jumps to this screenshot"
    }

    // MARK: Edit labels sheet
    enum Labels {
        static let title: String = "Edit labels"
        static let done: String = "Done"
        static let learns: String = "We'll sort similar screenshots this way too."
        static let current: String = "In these stacks"
        static let noneYet: String = "No stacks yet. Pick one below."
        static let tags: String = "Tags"
        static let addTagPlaceholder: String = "Add a tag"
        static let addTag: String = "Add tag"
        static let allStacks: String = "Add to a stack"
        static let searchPrompt: String = "Search stacks"
        static let noMatches: String = "No stacks match that."
        static func editing(_ count: Int) -> String { "Editing \(Brand.screenshots(count))" }
        static func removeCategory(_ name: String) -> String { "Remove from \(name)" }
        static func addCategory(_ name: String) -> String { "Add to \(name)" }
        static func removeTag(_ tag: String) -> String { "Remove tag \(tag)" }
    }
}
