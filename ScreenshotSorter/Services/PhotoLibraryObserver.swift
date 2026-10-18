import Photos

/// Changes to the set of screenshots in the photo library.
struct LibraryDelta: Sendable {
    var inserted: [String] = []
    var removed: [String] = []
    /// Edited (e.g. cropped/markup) — need re-analysis
    var changed: [String] = []

    var isEmpty: Bool { inserted.isEmpty && removed.isEmpty && changed.isEmpty }

    static let reconcileMarker = "*reconcile*"
    var needsFullReconcile: Bool { inserted.contains(LibraryDelta.reconcileMarker) }
}

/// Watches PhotoKit for new / deleted / edited screenshots (replaces the old count comparison).
final class PhotoLibraryObserver: NSObject, PHPhotoLibraryChangeObserver, @unchecked Sendable {
    private let lock = NSLock()
    private var fetchResult: PHFetchResult<PHAsset>
    private var continuation: AsyncStream<LibraryDelta>.Continuation?
    private var isRegistered = false

    let deltas: AsyncStream<LibraryDelta>

    override init() {
        fetchResult = PhotoLibraryService.shared.fetchScreenshotResult()
        var continuation: AsyncStream<LibraryDelta>.Continuation?
        deltas = AsyncStream { continuation = $0 }
        super.init()
        self.continuation = continuation
    }

    deinit {
        if isRegistered { PHPhotoLibrary.shared().unregisterChangeObserver(self) }
        continuation?.finish()
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !isRegistered else { return }
        fetchResult = PhotoLibraryService.shared.fetchScreenshotResult()
        PHPhotoLibrary.shared().register(self)
        isRegistered = true
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        lock.lock()
        guard let details = changeInstance.changeDetails(for: fetchResult) else {
            lock.unlock()
            return
        }
        fetchResult = details.fetchResultAfterChanges
        lock.unlock()

        guard details.hasIncrementalChanges else {
            // Non-incremental change: ask the coordinator to reconcile the whole library
            continuation?.yield(LibraryDelta(inserted: [LibraryDelta.reconcileMarker]))
            return
        }
        var delta = LibraryDelta()
        delta.inserted = details.insertedObjects.map(\.localIdentifier)
        delta.removed = details.removedObjects.map(\.localIdentifier)
        delta.changed = details.changedObjects.filter(\.hasAdjustments).map(\.localIdentifier)
        if !delta.isEmpty { continuation?.yield(delta) }
    }
}
