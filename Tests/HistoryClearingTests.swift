@testable import PinShotApp
import Cocoa

func testHistoryClearing() throws {
    let files = FileManager.default
    let root = files.temporaryDirectory.appendingPathComponent("PinShotClearTests-\(UUID())")
    let suite = "PinShot.ClearTests.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    let preferences = CapturePreferences(defaults: defaults)
    preferences.pinHistoryRetention = .unlimited
    defer {
        try? files.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }
    let image = NSImage(cgImage: fixture(width: 32, height: 24), size: NSSize(width: 32, height: 24))
    let frame = NSRect(origin: .zero, size: image.size)
    let indexFolder = root.appendingPathComponent("History")
    let indexURL = indexFolder.appendingPathComponent("index.json")
    let store = PinHistoryStore(preferences: preferences, indexDirectory: indexFolder)
    func capture() throws -> PinHistoryEntry { try store.record(image: image, frame: frame)! }
    func exists(_ entry: PinHistoryEntry) -> Bool { files.fileExists(atPath: entry.imagePath) }
    func persistedIDs() -> [UUID] {
        PinHistoryStore(preferences: preferences, indexDirectory: indexFolder).entries.map(\.id)
    }

    try store.clearHistory() // Empty history must work even before a directory exists.
    preferences.setDirectory(root.appendingPathComponent("Original"), for: .pin)
    let first = try capture()
    let manualCopy = root.appendingPathComponent("Original/ManualCopy.png")
    try files.copyItem(at: first.imageURL, to: manualCopy)
    preferences.setDirectory(root.appendingPathComponent("New"), for: .pin)
    let second = try capture()
    let missing = try capture()
    try files.removeItem(at: missing.imageURL)
    preferences.pinHistoryEnabled = false
    var notifications = 0
    let observer = NotificationCenter.default.addObserver(forName: .pinHistoryChanged, object: nil, queue: nil) { notification in
        if notification.object as? PinHistoryStore === store { notifications += 1 }
    }
    defer { NotificationCenter.default.removeObserver(observer) }
    try store.clearHistory()
    expect(store.entries.isEmpty && persistedIDs().isEmpty, "Clearing must persist an empty history while saving is disabled")
    expect(!exists(first) && !exists(second), "Clearing must remove indexed PNGs from current and previous folders")
    expect(files.fileExists(atPath: manualCopy.path), "Clearing must preserve independently saved copies")
    expect(notifications == 1, "Clearing must notify the history shelf after persistence")
    try store.update(id: first.id, image: image)
    expect(!exists(first), "Editing an open pin must not recreate cleared history")
    try store.clearHistory()
    expect(notifications == 1, "Repeated clearing of empty history must be harmless")

    preferences.pinHistoryEnabled = true
    let blocked = try capture()
    let removable = try capture()
    try files.removeItem(at: blocked.imageURL)
    try files.createDirectory(at: blocked.imageURL, withIntermediateDirectories: true)
    let sentinel = blocked.imageURL.appendingPathComponent("keep.txt")
    try Data("keep".utf8).write(to: sentinel)
    do {
        try store.clearHistory()
        fatalError("A directory replacing a PNG must report a deletion failure")
    } catch {}
    expect(!exists(removable) && files.fileExists(atPath: sentinel.path), "Partial cleanup must delete safe PNGs without recursively deleting directories")
    expect(store.entries.map(\.id) == [blocked.id] && persistedIDs() == [blocked.id], "Failed deletions must remain indexed for retry")
    try files.removeItem(at: blocked.imageURL)
    try store.clearHistory()
    expect(store.entries.isEmpty && persistedIDs().isEmpty, "Retry must clear repaired or missing files")

    let indexFailure = try capture()
    let backup = indexFolder.appendingPathComponent("index.backup")
    try files.moveItem(at: indexURL, to: backup)
    try files.createDirectory(at: indexURL, withIntermediateDirectories: false)
    do {
        try store.clearHistory()
        fatalError("Index write failure must be reported")
    } catch {}
    expect(!exists(indexFailure) && store.entries.map(\.id) == [indexFailure.id], "Failed index writes must keep the old in-memory index for retry")
    try files.removeItem(at: indexURL)
    try files.moveItem(at: backup, to: indexURL)
    try store.clearHistory()
    expect(store.entries.isEmpty && persistedIDs().isEmpty, "Retry must reconcile files removed before an index write failure")

    let protected = PinHistoryEntry(id: UUID(), date: Date(), imagePath: manualCopy.path, frame: frame, pixelWidth: 32, pixelHeight: 24)
    try JSONEncoder().encode([protected]).write(to: indexURL, options: .atomic)
    let unexpected = PinHistoryStore(preferences: preferences, indexDirectory: indexFolder)
    do {
        try unexpected.clearHistory()
        fatalError("Unexpected filenames must not be deleted")
    } catch {}
    expect(files.fileExists(atPath: manualCopy.path) && persistedIDs() == [protected.id], "Unexpected files must be preserved with their index entry")

    let corruptData = Data("invalid history index".utf8)
    try corruptData.write(to: indexURL, options: .atomic)
    let corrupt = PinHistoryStore(preferences: preferences, indexDirectory: indexFolder)
    do {
        try corrupt.clearHistory()
        fatalError("A corrupt index must report an error instead of pretending to clear history")
    } catch {}
    let unchanged = try Data(contentsOf: indexURL)
    expect(unchanged == corruptData && files.fileExists(atPath: manualCopy.path), "Clearing must preserve a corrupt index and untracked files")
    print("History clearing tests passed")
}
