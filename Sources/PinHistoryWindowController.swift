import Cocoa
import ImageIO

final class PinHistoryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    static let shared = PinHistoryWindowController()
    private let table = NSTableView()
    private let preview = NSImageView()
    private let message = NSTextField(wrappingLabelWithString: "")
    private let openButton = NSButton(title: "Open as Pin", target: nil, action: nil)
    private let revealButton = NSButton(title: "Show in Finder", target: nil, action: nil)
    private let summary = NSTextField(labelWithString: "")
    private var observer: NSObjectProtocol?
    private var entries: [PinHistoryEntry] = []
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "PinShot History"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 700, height: 420)
        super.init(window: window)
        buildContent()
        window.center()
        window.setFrameAutosaveName("PinShotHistory")
        observer = NotificationCenter.default.addObserver(forName: .pinHistoryChanged, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }

    func showHistory() {
        reload()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("capture"))
        column.width = 270
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 76
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(openSelected)
        table.setAccessibilityLabel("Screenshot history")
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        preview.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        preview.setAccessibilityLabel("Selected screenshot preview")
        message.alignment = .center
        message.textColor = .secondaryLabelColor
        message.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        openButton.target = self
        openButton.action = #selector(openSelected)
        openButton.bezelStyle = .rounded
        revealButton.target = self
        revealButton.action = #selector(revealSelected)
        revealButton.bezelStyle = .rounded
        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .secondaryLabelColor
        for view in [scroll, preview, message, openButton, revealButton, summary] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -54),
            scroll.widthAnchor.constraint(equalToConstant: 292),
            preview.leadingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: 18),
            preview.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            preview.topAnchor.constraint(equalTo: scroll.topAnchor),
            preview.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -38),
            message.leadingAnchor.constraint(equalTo: preview.leadingAnchor),
            message.trailingAnchor.constraint(equalTo: preview.trailingAnchor),
            message.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 8),
            summary.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            summary.centerYAnchor.constraint(equalTo: openButton.centerYAnchor),
            openButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            openButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
            revealButton.trailingAnchor.constraint(equalTo: openButton.leadingAnchor, constant: -8),
            revealButton.centerYAnchor.constraint(equalTo: openButton.centerYAnchor)
        ])
    }

    private func reload() {
        let previousID = selectedEntry?.id
        entries = PinHistoryStore.shared.entries
        table.reloadData()
        summary.stringValue = "\(entries.count) \(entries.count == 1 ? "capture" : "captures") · " + (CapturePreferences.shared.pinHistoryEnabled ? "History on" : "History off")
        if !entries.isEmpty {
            let index = entries.firstIndex { $0.id == previousID } ?? 0
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        }
        updateSelection()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row]
        let cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 270, height: 76))
        let thumbnail = NSImageView(frame: NSRect(x: 6, y: 8, width: 74, height: 58))
        // ImageIO downsamples without loading every full-size capture into the list.
        if let source = CGImageSourceCreateWithURL(entry.imageURL as CFURL, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 148,
                kCGImageSourceCreateThumbnailWithTransform: true
           ] as CFDictionary) {
            thumbnail.image = NSImage(cgImage: image, size: .zero)
        }
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        cell.addSubview(thumbnail)
        let label = NSTextField(wrappingLabelWithString: "\(dateFormatter.string(from: entry.date))\n\(entry.pixelWidth) × \(entry.pixelHeight) px")
        label.font = .systemFont(ofSize: 11)
        label.frame = NSRect(x: 90, y: 12, width: 180, height: 52)
        cell.addSubview(label)
        cell.textField = label
        cell.imageView = thumbnail
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateSelection() }

    private var selectedEntry: PinHistoryEntry? {
        entries.indices.contains(table.selectedRow) ? entries[table.selectedRow] : nil
    }

    private func updateSelection() {
        preview.image = selectedEntry.flatMap { PinHistoryStore.shared.image(for: $0) }
        openButton.isEnabled = preview.image != nil
        revealButton.isEnabled = preview.image != nil
        if let error = PinHistoryStore.shared.loadError {
            message.stringValue = "Could not read history: \(error.localizedDescription)"
        } else if let entry = selectedEntry {
            message.stringValue = preview.image == nil ? "This screenshot was moved or deleted." : entry.imageURL.lastPathComponent
        } else {
            message.stringValue = "No captures yet. Enable history in Settings, then use Capture & Pin."
        }
    }

    @objc private func openSelected() {
        guard let entry = selectedEntry, let image = PinHistoryStore.shared.image(for: entry) else { return }
        var frame = entry.frame
        if let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(frame) }) ?? NSScreen.main {
            let visible = screen.visibleFrame
            let scale = min(1, visible.width / max(frame.width, 1), visible.height / max(frame.height, 1))
            frame.size = NSSize(width: frame.width * scale, height: frame.height * scale)
            frame.origin.x = min(max(frame.minX, visible.minX), visible.maxX - frame.width)
            frame.origin.y = min(max(frame.minY, visible.minY), visible.maxY - frame.height)
        }
        PinManager.shared.pin(image: image, at: frame, historyEntry: entry)
    }

    @objc private func revealSelected() {
        guard let entry = selectedEntry else { return }
        NSWorkspace.shared.activateFileViewerSelecting([entry.imageURL])
    }
}
