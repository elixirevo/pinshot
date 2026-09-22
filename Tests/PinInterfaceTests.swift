import Cocoa

private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
    if let result = view as? T { return result }
    return view.subviews.lazy.compactMap { descendant(type, in: $0) }.first
}

func testPinInterface() throws {
    for visible in [NSRect(x: 0, y: 24, width: 1440, height: 876),
                    NSRect(x: -1920, y: -200, width: 1920, height: 1056),
                    NSRect(x: 1440, y: 100, width: 800, height: 700)] {
        let frame = PinHistoryWindowController.panelFrame(in: visible)
        expect(visible.contains(frame), "History must stay inside the invoking display")
        expect(frame.midX == visible.midX && visible.maxY - frame.maxY == 12,
               "History must be centered below the menu bar, including offset displays")
    }

    let scroll = HistoryScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 164))
    scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1800, height: 164))
    scroll.page(by: 1)
    expect(scroll.documentVisibleRect.minX > 0, "Next must scroll horizontally")
    scroll.page(by: 100)
    expect(scroll.documentVisibleRect.maxX <= 1800, "Scrolling must clamp at the last thumbnail")
    scroll.page(by: -100)
    expect(scroll.documentVisibleRect.minX == 0, "Previous must clamp at the first thumbnail")

    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PinShot-Interface-\(UUID())")
    let suite = "PinShot.Interface.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suite)
    }
    let preferences = CapturePreferences(defaults: defaults)
    preferences.setDirectory(directory.appendingPathComponent("Pins"), for: .pin)
    let store = PinHistoryStore(preferences: preferences, indexDirectory: directory)
    let controller = PinHistoryWindowController(store: store, preferences: preferences)
    controller.showHistory()
    defer { controller.dismiss() }
    let window = controller.window!
    let collection = descendant(NSCollectionView.self, in: window.contentView!)!
    expect(collection.numberOfItems(inSection: 0) == 0, "Empty history must open without a selection")
    expect(window.performKeyEquivalent(with: key(36, "\r")), "Return must safely handle empty history")
    let image = NSImage(cgImage: fixture(width: 80, height: 60), size: NSSize(width: 80, height: 60))
    for _ in 0..<12 { try store.record(image: image, frame: NSRect(x: 50, y: 50, width: 240, height: 180)) }
    expect(!window.styleMask.contains(.titled), "History must use a shelf without a document title bar")
    expect(collection.numberOfItems(inSection: 0) == 12, "The open strip must update when new captures arrive")
    let layout = collection.collectionViewLayout!
    let first = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame
    let last = layout.layoutAttributesForItem(at: IndexPath(item: 11, section: 0))!.frame
    expect(first.minY == last.minY && last.minX > first.maxX, "History must stay in one horizontal row")
    expect(collection.selectionIndexPaths == [IndexPath(item: 11, section: 0)], "Live updates must preserve the selected capture")
    for _ in 0..<20 { _ = window.performKeyEquivalent(with: key(123, "")) }
    expect(collection.selectionIndexPaths == [IndexPath(item: 0, section: 0)], "Left arrow must stop at the first capture")
    expect(window.performKeyEquivalent(with: key(124, "")), "Right arrow must navigate history")
    expect(collection.selectionIndexPaths == [IndexPath(item: 1, section: 0)], "Right arrow must select the next capture")
    for _ in 0..<20 { _ = window.performKeyEquivalent(with: key(124, "")) }
    expect(collection.selectionIndexPaths == [IndexPath(item: 11, section: 0)], "Keyboard navigation must stop at the last capture")
    try FileManager.default.removeItem(at: store.entries[11].imageURL)
    _ = window.performKeyEquivalent(with: key(36, "\r"))
    expect(window.isVisible, "A missing image must leave history open with an explanation")
    _ = window.performKeyEquivalent(with: key(53, ""))
    expect(!window.isVisible, "Escape must dismiss history")
    print("PASS: history shelf placement, empty state, live updates, single-row layout, horizontal paging, keyboard bounds, missing-file handling, Escape")
}

// A fixture-only preview: no Screen Recording permission or real history is needed.
func previewPinInterface() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PinShot-Preview-\(UUID())")
    let suite = "PinShot.Preview.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer {
        try? FileManager.default.removeItem(at: directory)
        defaults.removePersistentDomain(forName: suite)
    }
    let preferences = CapturePreferences(defaults: defaults)
    preferences.setDirectory(directory.appendingPathComponent("Pins"), for: .pin)
    let store = PinHistoryStore(preferences: preferences, indexDirectory: directory)
    let visible = NSScreen.main!.visibleFrame
    let frame = NSRect(x: visible.midX - 290, y: visible.midY - 220, width: 580, height: 340)
    var images: [NSImage] = []
    for index in 0..<12 {
        let image = NSImage(size: frame.size)
        image.lockFocus()
        let dark = index % 2 == 1
        (dark ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.96, alpha: 1)).setFill()
        NSRect(origin: .zero, size: frame.size).fill()
        let color = NSColor(calibratedHue: CGFloat(index) / 12, saturation: 0.55, brightness: 0.8, alpha: 1)
        color.setFill()
        NSBezierPath(roundedRect: NSRect(x: 36, y: 48, width: 508, height: 94), xRadius: 16, yRadius: 16).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 32, weight: .semibold),
            .foregroundColor: dark ? NSColor.white : NSColor.black
        ]
        "Screenshot \(index + 1)".draw(at: NSPoint(x: 36, y: 220), withAttributes: attributes)
        "Capture ideas. Keep them in view.".draw(at: NSPoint(x: 36, y: 175), withAttributes: [
            .font: NSFont.systemFont(ofSize: 19), .foregroundColor: dark ? NSColor.lightGray : NSColor.darkGray
        ])
        image.unlockFocus()
        images.append(image)
        try store.record(image: image, frame: frame)
    }
    let controller = PinHistoryWindowController(store: store, preferences: preferences)
    let pin = PinWindow(image: images[0], frame: frame)
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    pin.makeKeyAndOrderFront(nil)
    app.activate(ignoringOtherApps: true)
    controller.showHistory(on: NSScreen.main)
    withExtendedLifetime((controller, pin)) { app.run() }
}
