import Cocoa
import ImageIO

final class PinHistoryWindowController: NSWindowController, NSCollectionViewDataSource, NSWindowDelegate {
    static let shared = PinHistoryWindowController()
    private let store: PinHistoryStore
    private let preferences: CapturePreferences
    private let collection = HistoryCollectionView()
    private let scroll = HistoryScrollView()
    private let summary = NSTextField(labelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private let hint = NSTextField(labelWithString: "")
    private let revealButton = NSButton(title: "Show in Finder", target: nil, action: nil)
    private var previousButton: PinControlButton!
    private var nextButton: PinControlButton!
    private var observers: [NSObjectProtocol] = []
    private var outsideClickMonitor: Any?
    private var entries: [PinHistoryEntry] = []
    private var selectedIndex = 0
    private let thumbnails = NSCache<NSUUID, NSImage>()
    private let thumbnailQueue = DispatchQueue(label: "PinShot.history-thumbnails", qos: .userInitiated)
    private var thumbnailGeneration = UUID()
    private static let itemIdentifier = NSUserInterfaceItemIdentifier("HistoryThumbnail")
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    init(store: PinHistoryStore = .shared, preferences: CapturePreferences = .shared) {
        self.store = store
        self.preferences = preferences
        let panel = HistoryPanel(contentRect: NSRect(x: 0, y: 0, width: 1080, height: 254),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "PinShot History"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isMovable = false
        super.init(window: panel)
        panel.delegate = self
        panel.onKey = { [weak self] event in self?.handleKey(event) ?? false }
        collection.onKey = panel.onKey
        thumbnails.countLimit = 100
        buildContent()
        observers.append(NotificationCenter.default.addObserver(forName: .pinHistoryChanged, object: store, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.thumbnails.removeAllObjects()
            self.thumbnailGeneration = UUID()
            if self.window?.isVisible == true { self.reload() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
            object: scroll.contentView, queue: .main) { [weak self] _ in self?.updateNavigation() })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.dismiss() })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    }

    func showHistory(on screen: NSScreen? = nil) {
        guard let window, let screen = screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main else { return }
        window.setFrame(Self.panelFrame(in: screen.visibleFrame), display: false)
        window.contentView?.layoutSubtreeIfNeeded()
        reload()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(collection)
        if outsideClickMonitor == nil {
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
                self?.dismiss()
            }
        }
    }

    static func panelFrame(in visibleFrame: NSRect) -> NSRect {
        let width = min(1120, max(0, visibleFrame.width - 32))
        return NSRect(x: visibleFrame.midX - width / 2, y: visibleFrame.maxY - 266, width: width, height: 254)
    }

    @objc func dismiss() {
        window?.orderOut(nil)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor); self.outsideClickMonitor = nil }
    }

    func windowDidResignKey(_ notification: Notification) { dismiss() }

    private func buildContent() {
        let content = NSVisualEffectView()
        content.material = .popover
        content.blendingMode = .behindWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 20
        content.layer?.masksToBounds = true
        window?.contentView = content

        let title = NSTextField(labelWithString: "Screenshot History")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .secondaryLabelColor
        summary.lineBreakMode = .byTruncatingTail
        summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        previousButton = PinControlButton(symbol: "chevron.left", label: "Scroll to newer screenshots", target: self, action: #selector(scrollPrevious))
        nextButton = PinControlButton(symbol: "chevron.right", label: "Scroll to older screenshots", target: self, action: #selector(scrollNext))
        let close = PinControlButton(symbol: "xmark", label: "Close history (Esc)", target: self, action: #selector(dismiss))
        let controls = NSStackView(views: [previousButton, nextButton, close])
        controls.spacing = 6
        for button in [previousButton!, nextButton!, close] {
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.itemSize = NSSize(width: 200, height: 152)
        layout.minimumLineSpacing = 12
        layout.minimumInteritemSpacing = 12
        layout.sectionInset = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        collection.collectionViewLayout = layout
        collection.backgroundColors = [.clear]
        collection.dataSource = self
        collection.isSelectable = true
        collection.allowsMultipleSelection = false
        collection.register(HistoryThumbnailItem.self, forItemWithIdentifier: Self.itemIdentifier)
        collection.setAccessibilityLabel("Screenshot history, newest first")
        scroll.documentView = collection
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        scroll.contentView.postsBoundsChangedNotifications = true
        message.alignment = .center
        message.textColor = .secondaryLabelColor
        message.font = .systemFont(ofSize: 13)
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        revealButton.target = self
        revealButton.action = #selector(revealSelected)
        revealButton.bezelStyle = .rounded
        revealButton.controlSize = .small
        for view in [title, summary, controls, scroll, message, hint, revealButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 18),
            summary.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 12),
            summary.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            summary.trailingAnchor.constraint(lessThanOrEqualTo: controls.leadingAnchor, constant: -12),
            controls.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            controls.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 52),
            scroll.heightAnchor.constraint(equalToConstant: 164),
            message.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
            message.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 24),
            message.trailingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: -24),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            hint.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -15),
            hint.trailingAnchor.constraint(lessThanOrEqualTo: revealButton.leadingAnchor, constant: -12),
            revealButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            revealButton.centerYAnchor.constraint(equalTo: hint.centerYAnchor)
        ])
    }

    private var selectedEntry: PinHistoryEntry? { entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil }

    private func reload() {
        let previousID = selectedEntry?.id
        entries = store.entries
        selectedIndex = entries.firstIndex { $0.id == previousID } ?? 0
        summary.stringValue = "\(entries.count) \(entries.count == 1 ? "capture" : "captures")" + (preferences.pinHistoryEnabled ? "" : " · History off")
        if let error = store.loadError {
            message.stringValue = "Could not read history: \(error.localizedDescription)"
        } else if entries.isEmpty {
            message.stringValue = preferences.pinHistoryEnabled
                ? "No screenshots yet. Use Capture & Pin to save your first capture."
                : "History is off. Enable it in Settings to save new captures."
        }
        message.isHidden = !entries.isEmpty && store.loadError == nil
        scroll.isHidden = entries.isEmpty
        collection.reloadData()
        collection.layoutSubtreeIfNeeded()
        selectItem(at: selectedIndex)
        updateNavigation()
    }

    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { entries.count }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: Self.itemIdentifier, for: indexPath) as! HistoryThumbnailItem
        let entry = entries[indexPath.item]
        item.configure(entry: entry, date: dateFormatter.string(from: entry.date))
        item.onOpen = { [weak self] in self?.openItem(at: indexPath.item) }
        if let image = thumbnails.object(forKey: entry.id as NSUUID) {
            item.setThumbnail(image, for: entry.id)
        } else {
            let generation = thumbnailGeneration
            thumbnailQueue.async { [weak self, weak item] in
                // Only visible collection items are decoded, at thumbnail resolution.
                let cgImage = CGImageSourceCreateWithURL(entry.imageURL as CFURL, nil).flatMap {
                    CGImageSourceCreateThumbnailAtIndex($0, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 400,
                        kCGImageSourceCreateThumbnailWithTransform: true
                    ] as CFDictionary)
                }
                DispatchQueue.main.async {
                    guard let self, self.thumbnailGeneration == generation else { return }
                    let image = cgImage.map { NSImage(cgImage: $0, size: .zero) }
                    if let image { self.thumbnails.setObject(image, forKey: entry.id as NSUUID) }
                    item?.setThumbnail(image, for: entry.id)
                }
            }
        }
        return item
    }

    private func selectItem(at index: Int) {
        guard entries.indices.contains(index) else {
            revealButton.isEnabled = false
            hint.stringValue = "Esc to close"
            return
        }
        selectedIndex = index
        let path = IndexPath(item: index, section: 0)
        collection.selectionIndexPaths = [path]
        collection.scrollToItems(at: [path], scrollPosition: .nearestHorizontalEdge)
        revealButton.isEnabled = FileManager.default.fileExists(atPath: entries[index].imagePath)
        hint.stringValue = "Scroll to browse · Click to pin · ← → to select · Return to open"
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        switch event.keyCode {
        case 53: dismiss()
        case 123: selectItem(at: max(0, selectedIndex - 1))
        case 124: selectItem(at: min(entries.count - 1, selectedIndex + 1))
        case 36, 76, 49: openItem(at: selectedIndex)
        default: return false
        }
        return true
    }

    private func updateNavigation() {
        let visible = scroll.documentVisibleRect
        previousButton.isEnabled = !entries.isEmpty && visible.minX > 1
        nextButton.isEnabled = !entries.isEmpty && visible.maxX < collection.bounds.width - 1
    }

    @objc private func scrollPrevious() { scroll.page(by: -1) }
    @objc private func scrollNext() { scroll.page(by: 1) }

    private func openItem(at index: Int) {
        selectItem(at: index)
        guard let entry = selectedEntry else { return }
        guard let image = store.image(for: entry) else {
            hint.stringValue = "This screenshot was moved or deleted."
            revealButton.isEnabled = false
            return
        }
        var frame = entry.frame
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? window?.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let scale = min(1, visible.width / max(frame.width, 1), visible.height / max(frame.height, 1))
            frame.size = NSSize(width: frame.width * scale, height: frame.height * scale)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        dismiss()
        PinManager.shared.pin(image: image, at: frame, historyEntry: entry)
    }

    @objc private func revealSelected() {
        guard let entry = selectedEntry else { return }
        dismiss()
        NSWorkspace.shared.activateFileViewerSelecting([entry.imageURL])
    }
}

private final class HistoryPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        onKey?(event) == true || super.performKeyEquivalent(with: event)
    }
}

private final class HistoryCollectionView: NSCollectionView {
    var onKey: ((NSEvent) -> Bool)?
    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }
}

final class HistoryScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        // A regular mouse wheel should browse the same horizontal strip as a trackpad.
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            let delta = event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 1 : 24)
            scrollHorizontally(to: contentView.bounds.minX - delta)
        } else {
            super.scrollWheel(with: event)
        }
    }

    func page(by direction: CGFloat) {
        scrollHorizontally(to: contentView.bounds.minX + direction * contentView.bounds.width * 0.85)
    }

    private func scrollHorizontally(to x: CGFloat) {
        let maximum = max(0, (documentView?.bounds.width ?? 0) - contentView.bounds.width)
        contentView.scroll(to: NSPoint(x: min(max(0, x), maximum), y: 0))
        reflectScrolledClipView(contentView)
    }
}

private final class HistoryThumbnailItem: NSCollectionViewItem {
    private let button = NSButton()
    private let thumbnail = NSImageView()
    private let dateLabel = NSTextField(labelWithString: "")
    private let dimensions = NSTextField(labelWithString: "")
    private var entryID: UUID?
    var onOpen: (() -> Void)?

    override func loadView() {
        view = HistoryThumbnailBackground(frame: NSRect(x: 0, y: 0, width: 200, height: 152))
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.wantsLayer = true
        thumbnail.layer?.cornerRadius = 8
        thumbnail.layer?.masksToBounds = true
        dateLabel.font = .systemFont(ofSize: 11, weight: .medium)
        dateLabel.lineBreakMode = .byTruncatingTail
        dimensions.font = .systemFont(ofSize: 10)
        dimensions.textColor = .secondaryLabelColor
        button.title = ""
        button.isBordered = false
        button.target = self
        button.action = #selector(open)
        for child in [thumbnail, dateLabel, dimensions, button] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        NSLayoutConstraint.activate([
            thumbnail.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            thumbnail.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            thumbnail.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            thumbnail.heightAnchor.constraint(equalToConstant: 100),
            dateLabel.leadingAnchor.constraint(equalTo: thumbnail.leadingAnchor),
            dateLabel.trailingAnchor.constraint(equalTo: thumbnail.trailingAnchor),
            dateLabel.topAnchor.constraint(equalTo: thumbnail.bottomAnchor, constant: 7),
            dimensions.leadingAnchor.constraint(equalTo: dateLabel.leadingAnchor),
            dimensions.topAnchor.constraint(equalTo: dateLabel.bottomAnchor, constant: 2),
            button.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            button.topAnchor.constraint(equalTo: view.topAnchor),
            button.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        updateSelection()
    }

    func configure(entry: PinHistoryEntry, date: String) {
        _ = view
        entryID = entry.id
        dateLabel.stringValue = date
        dimensions.stringValue = "\(entry.pixelWidth) × \(entry.pixelHeight) px"
        thumbnail.image = nil
        button.toolTip = "Open as Pin · \(date) · \(dimensions.stringValue)"
        button.setAccessibilityLabel("Open screenshot from \(date), \(dimensions.stringValue)")
        updateSelection()
    }

    func setThumbnail(_ image: NSImage?, for id: UUID) {
        guard entryID == id else { return }
        thumbnail.image = image ?? NSImage(systemSymbolName: "photo.badge.exclamationmark", accessibilityDescription: "Screenshot unavailable")
        if image == nil { dimensions.stringValue = "File unavailable" }
    }

    override var isSelected: Bool { didSet { updateSelection() } }
    private func updateSelection() {
        guard isViewLoaded else { return }
        (view as? HistoryThumbnailBackground)?.selected = isSelected
    }

    @objc private func open() { onOpen?() }
}

private final class HistoryThumbnailBackground: NSView {
    var selected = false { didSet { needsDisplay = true } }
    override var wantsUpdateLayer: Bool { true }
    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
        layer?.borderWidth = selected ? 2 : 0
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
    }
    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }
}
