import Cocoa

func testHistoryRetention() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("PinShotRetentionTests-\(UUID())")
    let suite = "PinShot.RetentionTests.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    let preferences = CapturePreferences(defaults: defaults)
    let files = FileManager.default
    defer {
        try? files.removeItem(at: root)
        defaults.removePersistentDomain(forName: suite)
    }
    let image = NSImage(cgImage: fixture(width: 32, height: 24), size: NSSize(width: 32, height: 24))
    let frame = NSRect(origin: .zero, size: image.size)
    func exists(_ entry: PinHistoryEntry) -> Bool { files.fileExists(atPath: entry.imagePath) }

    expect(preferences.pinHistoryRetention == .thirty, "History must default to keeping 30 captures")
    defaults.set(999, forKey: "pins.history.limit")
    expect(preferences.pinHistoryRetention == .thirty, "Invalid saved limits must fall back to 30")
    defaults.removeObject(forKey: "pins.history.limit")

    for retention in [PinHistoryRetention.ten, .thirty, .fifty, .hundred] {
        let limit = retention.maximumCount!
        // Exercise the unset default for 30 as well as each explicitly selected limit.
        if retention == .thirty { defaults.removeObject(forKey: "pins.history.limit") }
        else { preferences.pinHistoryRetention = retention }
        expect(CapturePreferences(defaults: defaults).pinHistoryRetention == retention, "Retention selection must persist")
        let folder = root.appendingPathComponent("Limit-\(limit)")
        preferences.setDirectory(folder.appendingPathComponent("Images"), for: .pin)
        let store = PinHistoryStore(preferences: preferences, indexDirectory: folder)
        var captured: [PinHistoryEntry] = []
        for _ in 0..<limit { captured.append(try store.record(image: image, frame: frame)!) }
        expect(store.entries.count == limit && captured.allSatisfy(exists), "Reaching the limit must not delete a capture early")
        captured.append(try store.record(image: image, frame: frame)!)
        expect(!exists(captured[0]) && exists(captured[1]), "The first overflow must remove only the oldest PNG")
        captured.append(try store.record(image: image, frame: frame)!)
        let expected = Array(captured.suffix(limit).reversed().map(\.id))
        expect(store.entries.map(\.id) == expected, "Every overflow must evict the oldest entry in FIFO order")
        expect(!exists(captured[1]) && captured.suffix(limit).allSatisfy(exists), "Retained PNG files must match the history index")
        let reloaded = PinHistoryStore(preferences: preferences, indexDirectory: folder)
        expect(reloaded.entries.map(\.id) == expected, "Pruned history must persist across app restarts")
        try reloaded.update(id: captured[0].id, image: image)
        expect(!exists(captured[0]), "Editing an old open pin must not recreate an evicted history file")
    }

    preferences.pinHistoryRetention = .unlimited
    expect(CapturePreferences(defaults: defaults).pinHistoryRetention == .unlimited, "Never Delete must persist separately from the default")
    let folder = root.appendingPathComponent("Unlimited")
    preferences.setDirectory(folder.appendingPathComponent("OriginalImages"), for: .pin)
    let store = PinHistoryStore(preferences: preferences, indexDirectory: folder)
    var captured: [PinHistoryEntry] = []
    for _ in 0..<103 { captured.append(try store.record(image: image, frame: frame)!) }
    expect(store.entries.count == 103 && captured.allSatisfy(exists), "Never Delete must preserve history beyond the largest finite limit")

    preferences.pinHistoryRetention = .ten
    preferences.pinHistoryEnabled = false
    let disabledResult = try store.record(image: image, frame: frame)
    expect(disabledResult == nil && captured.allSatisfy(exists), "Changing the limit while history is off must not delete existing captures")
    let beforeTrim = PinHistoryStore(preferences: preferences, indexDirectory: folder)
    expect(beforeTrim.entries.count == 103, "Changing the setting or opening history must not prune immediately")
    let manualSave = captured[0].imageURL.deletingLastPathComponent().appendingPathComponent("ManualScreenshot.png")
    try Data("keep this independent file".utf8).write(to: manualSave)
    preferences.setDirectory(folder.appendingPathComponent("NewImages"), for: .pin)
    preferences.pinHistoryEnabled = true
    captured.append(try beforeTrim.record(image: image, frame: frame)!)
    expect(beforeTrim.entries.count == 10, "The next successful capture must trim all excess entries after lowering the limit")
    expect(captured.dropLast(10).allSatisfy { !exists($0) } && captured.suffix(10).allSatisfy(exists),
           "Cleanup must delete old history PNGs from their original folder after the save folder changes")
    expect(files.fileExists(atPath: manualSave.path), "Retention must not delete manually saved or unrelated files")
    preferences.pinHistoryRetention = .unlimited
    for _ in 0..<3 { _ = try beforeTrim.record(image: image, frame: frame) }
    expect(beforeTrim.entries.count == 13, "Switching back to Never Delete must stop eviction")

    // Persisted insertion order, rather than wall-clock timestamps, defines FIFO.
    let clockFolder = root.appendingPathComponent("ClockChange")
    preferences.pinHistoryRetention = .ten
    preferences.setDirectory(clockFolder.appendingPathComponent("Images"), for: .pin)
    let clockStore = PinHistoryStore(preferences: preferences, indexDirectory: clockFolder)
    for _ in 0..<10 { _ = try clockStore.record(image: image, frame: frame) }
    let reversedDates = clockStore.entries.enumerated().map { index, entry in
        PinHistoryEntry(id: entry.id, date: Date(timeIntervalSince1970: Double(index)), imagePath: entry.imagePath,
                        frame: entry.frame, pixelWidth: entry.pixelWidth, pixelHeight: entry.pixelHeight)
    }
    try JSONEncoder().encode(reversedDates).write(to: clockFolder.appendingPathComponent("index.json"))
    let afterClockChange = PinHistoryStore(preferences: preferences, indexDirectory: clockFolder)
    let newest = try afterClockChange.record(image: image, frame: frame)!
    expect(afterClockChange.entries.map(\.id) == [newest.id] + reversedDates.dropLast().map(\.id),
           "Clock changes must not change FIFO order after restarting")

    // A failed new save must never evict existing history.
    let safeEntries = afterClockChange.entries
    let indexURL = clockFolder.appendingPathComponent("index.json")
    let backupURL = clockFolder.appendingPathComponent("index.backup")
    try files.moveItem(at: indexURL, to: backupURL)
    try files.createDirectory(at: indexURL, withIntermediateDirectories: false)
    do {
        _ = try afterClockChange.record(image: image, frame: frame)
        fatalError("Saving an index onto a directory must fail")
    } catch {}
    expect(afterClockChange.entries.map(\.id) == safeEntries.map(\.id) && safeEntries.allSatisfy(exists),
           "An index write failure must preserve all existing history and its PNGs")
    try files.removeItem(at: indexURL)
    try files.moveItem(at: backupURL, to: indexURL)

    // Failed cleanup remains indexed for retry and cannot recursively remove directories.
    let oldest = safeEntries.last!
    let oldPNG = try Data(contentsOf: oldest.imageURL)
    try files.removeItem(at: oldest.imageURL)
    try files.createDirectory(at: oldest.imageURL, withIntermediateDirectories: false)
    let sentinel = oldest.imageURL.appendingPathComponent("keep.txt")
    try Data("keep".utf8).write(to: sentinel)
    let savedDespiteCleanupFailure = try afterClockChange.record(image: image, frame: frame)!
    expect(afterClockChange.lastRetentionError != nil && afterClockChange.entries.count == 11,
           "A cleanup error must be reported while keeping the new capture and failed old entry indexed")
    expect(exists(savedDespiteCleanupFailure) && files.fileExists(atPath: sentinel.path),
           "Failed cleanup must preserve the new image and must not delete a directory's contents")
    try files.removeItem(at: oldest.imageURL)
    try oldPNG.write(to: oldest.imageURL)
    _ = try afterClockChange.record(image: image, frame: frame)
    expect(afterClockChange.lastRetentionError == nil && afterClockChange.entries.count == 10 && !exists(oldest),
           "The next capture must retry failed cleanup and restore the chosen limit")

    let missing = afterClockChange.entries.last!
    try files.removeItem(at: missing.imageURL)
    _ = try afterClockChange.record(image: image, frame: frame)
    expect(afterClockChange.lastRetentionError == nil && afterClockChange.entries.count == 10,
           "A PNG already deleted by the user must not block retention")
    print("PASS: default 30, 10/30/50/100 FIFO limits, Never Delete, persistence, history off, folder changes, save/cleanup failures, retry, missing files, clock changes")
}
