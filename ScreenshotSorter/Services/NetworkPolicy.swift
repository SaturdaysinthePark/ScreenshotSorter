import Foundation
import Network
import os

/// Whether analysis may download iCloud originals right now.
///
/// With "Optimize iPhone Storage" most screenshots only exist in iCloud, so downloads decide how
/// much of a library can be sorted. They happen on unmetered networks only: never on cellular or a
/// Personal Hotspot (`isExpensive`), never in Low Data Mode (`isConstrained`).
final class NetworkPolicy: @unchecked Sendable {
    static let shared = NetworkPolicy()

    private static let logger = Logger(subsystem: "sabtain.ScreenshotSorter", category: "Network")

    private let monitor = NWPathMonitor()
    private let lock = OSAllocatedUnfairLock(initialState: State())
    private let queue = DispatchQueue(label: "analysis.network-policy", qos: .utility)

    private struct State {
        var allowsDownloads = false
        var listeners: [UUID: @Sendable (Bool) -> Void] = [:]
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.update(path)
        }
        monitor.start(queue: queue)
    }

    var allowsICloudDownloads: Bool {
        lock.withLock { $0.allowsDownloads }
    }

    /// Called on every change of `allowsICloudDownloads` (on a background queue).
    @discardableResult
    func observe(_ handler: @escaping @Sendable (Bool) -> Void) -> UUID {
        let id = UUID()
        lock.withLock { $0.listeners[id] = handler }
        return id
    }

    private func update(_ path: NWPath) {
        let allowed = path.status == .satisfied && !path.isExpensive && !path.isConstrained
        let (changed, listeners) = lock.withLock { state -> (Bool, [@Sendable (Bool) -> Void]) in
            let changed = state.allowsDownloads != allowed
            state.allowsDownloads = allowed
            return (changed, Array(state.listeners.values))
        }
        guard changed else { return }
        NetworkPolicy.logger.notice("iCloud downloads \(allowed ? "allowed" : "paused", privacy: .public) (status \(String(describing: path.status), privacy: .public), expensive \(path.isExpensive), constrained \(path.isConstrained))")
        for listener in listeners { listener(allowed) }
    }
}
