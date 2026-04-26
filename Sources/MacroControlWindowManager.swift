import Cocoa
import Carbon

final class MacroControlWindowManager: NSObject, NSWindowDelegate {
    static let shared = MacroControlWindowManager()

    var onPlayRequested: ((String, TimeInterval, Int, TimeInterval) -> Void)?
    var onStopRequested: (() -> Void)?

    private var window: NSPanel?
    private var afterShortcutField: NSTextField?
    private var postDelayField: NSTextField?
    private var restLoopIntervalField: NSTextField?
    private var restDurationField: NSTextField?
    private var playButton: NSButton?
    private var stopButton: NSButton?
    private var readKeyButton: NSButton?
    private var statusLabel: NSTextField?
    private let defaults = UserDefaults.standard
    private let windowOriginXDefaultsKey = "macro.windowOrigin.x"
    private let windowOriginYDefaultsKey = "macro.windowOrigin.y"
    private var hasUserPinnedPosition = false
    private var isProgrammaticMoveInProgress = false
    private var isReadingKey = false
    private var localReadKeyMonitor: Any?
    private var globalReadKeyMonitor: Any?
    private var lastPlaybackIsRunning = false
    private var lastPlaybackIteration = 0

    private override init() {
        super.init()
    }

    func configure(
        afterShortcutText: String,
        postDelaySeconds: TimeInterval,
        restLoopInterval: Int,
        restDurationSeconds: TimeInterval
    ) {
        DispatchQueue.main.async {
            self.ensureWindow()
            self.afterShortcutField?.stringValue = afterShortcutText
            self.postDelayField?.stringValue = String(format: "%.2f", postDelaySeconds)
            self.restLoopIntervalField?.stringValue = "\(restLoopInterval)"
            self.restDurationField?.stringValue = String(format: "%.2f", restDurationSeconds)
        }
    }

    func show(below region: NSRect) {
        DispatchQueue.main.async {
            self.ensureWindow()
            if !self.hasUserPinnedPosition {
                self.reposition(below: region)
            }
            self.window?.orderFrontRegardless()
        }
    }

    func hide() {
        DispatchQueue.main.async {
            self.stopReadingShortcutCapture(updateStatus: false)
            self.window?.orderOut(nil)
        }
    }

    func updatePlaybackState(isRunning: Bool, iteration: Int) {
        DispatchQueue.main.async {
            self.lastPlaybackIsRunning = isRunning
            self.lastPlaybackIteration = iteration
            self.playButton?.isEnabled = !isRunning && !self.isReadingKey
            self.stopButton?.isEnabled = isRunning
            self.readKeyButton?.isEnabled = !isRunning || self.isReadingKey
            if !self.isReadingKey {
                self.refreshStatusText()
            }
        }
    }

    private func reposition(below region: NSRect) {
        guard let window else { return }
        guard let screen = screenContaining(region: region) else { return }

        let visible = screen.visibleFrame
        let size = window.frame.size
        let margin: CGFloat = 8

        var x = region.midX - (size.width / 2)
        x = min(max(x, visible.minX + margin), visible.maxX - size.width - margin)

        var y = region.minY - size.height - 10
        if y < visible.minY + margin {
            y = region.maxY + 10
        }
        y = min(max(y, visible.minY + margin), visible.maxY - size.height - margin)

        setWindowOrigin(window, NSPoint(x: x, y: y))
    }

    @objc private func playClicked() {
        guard let postDelayField, let restLoopIntervalField, let restDurationField else { return }
        let afterShortcutText = afterShortcutField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let delayText = postDelayField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let restLoopIntervalText = restLoopIntervalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let restDurationText = restDurationField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let delay = TimeInterval(delayText), delay.isFinite, delay >= 0 else {
            showValidationError("Post delay must be a number >= 0.")
            return
        }
        guard let restLoopInterval = Int(restLoopIntervalText), restLoopInterval > 0 else {
            showValidationError("Rest loop interval must be an integer >= 1.")
            return
        }
        guard let restDuration = TimeInterval(restDurationText), restDuration.isFinite, restDuration >= 0 else {
            showValidationError("Rest duration must be a number >= 0.")
            return
        }
        onPlayRequested?(afterShortcutText, delay, restLoopInterval, restDuration)
    }

    @objc private func stopClicked() {
        onStopRequested?()
    }

    @objc private func readKeyClicked() {
        if isReadingKey {
            stopReadingShortcutCapture(updateStatus: true)
            return
        }
        startReadingShortcutCapture()
    }

    private func ensureWindow() {
        guard window == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 285),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Screenshot Macro"
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self

        let content = NSView(frame: panel.contentRect(forFrameRect: panel.frame))

        let step1 = NSTextField(labelWithString: "1. Screenshot: capture saved Opt+2 region")
        let step2 = NSTextField(labelWithString: "2. After screenshot: trigger shortcut (optional)")
        let step3 = NSTextField(labelWithString: "3. After screenshot: wait N seconds")
        let step4 = NSTextField(labelWithString: "4. Rest every")
        let restLoopsLabel = NSTextField(labelWithString: "loops for")
        let restSecondsLabel = NSTextField(labelWithString: "seconds")
        let step5 = NSTextField(labelWithString: "5. Loop back to step 1")
        [step1, step2, step3, step4, restLoopsLabel, restSecondsLabel, step5].forEach {
            $0.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            $0.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview($0)
        }

        let shortcutField = NSTextField(string: "")
        shortcutField.placeholderString = "ex) option+right, left, a"
        shortcutField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        shortcutField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(shortcutField)
        afterShortcutField = shortcutField

        let readButton = NSButton(title: "Read Key", target: self, action: #selector(readKeyClicked))
        readButton.bezelStyle = .rounded
        readButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(readButton)
        readKeyButton = readButton

        let delayField = NSTextField(string: "1.00")
        delayField.placeholderString = "seconds"
        delayField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        delayField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(delayField)
        postDelayField = delayField

        let restIntervalField = NSTextField(string: "10")
        restIntervalField.placeholderString = "loops"
        restIntervalField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        restIntervalField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(restIntervalField)
        restLoopIntervalField = restIntervalField

        let restField = NSTextField(string: "10.00")
        restField.placeholderString = "seconds"
        restField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        restField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(restField)
        restDurationField = restField

        let play = NSButton(title: "Play Macro", target: self, action: #selector(playClicked))
        play.bezelStyle = .rounded
        play.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(play)
        playButton = play

        let stop = NSButton(title: "Stop Macro", target: self, action: #selector(stopClicked))
        stop.bezelStyle = .rounded
        stop.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stop)
        stopButton = stop

        let status = NSTextField(labelWithString: "Stopped (Last loop 0)")
        status.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        status.alignment = .center
        status.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(status)
        statusLabel = status

        NSLayoutConstraint.activate([
            step1.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            step1.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            step1.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            step2.topAnchor.constraint(equalTo: step1.bottomAnchor, constant: 10),
            step2.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            step2.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            shortcutField.topAnchor.constraint(equalTo: step2.bottomAnchor, constant: 6),
            shortcutField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            shortcutField.trailingAnchor.constraint(equalTo: readButton.leadingAnchor, constant: -8),

            readButton.centerYAnchor.constraint(equalTo: shortcutField.centerYAnchor),
            readButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            readButton.widthAnchor.constraint(equalToConstant: 92),

            step3.topAnchor.constraint(equalTo: shortcutField.bottomAnchor, constant: 10),
            step3.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            delayField.leadingAnchor.constraint(equalTo: step3.trailingAnchor, constant: 8),
            delayField.widthAnchor.constraint(equalToConstant: 80),
            delayField.centerYAnchor.constraint(equalTo: step3.centerYAnchor),

            step4.topAnchor.constraint(equalTo: step3.bottomAnchor, constant: 10),
            step4.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            restIntervalField.leadingAnchor.constraint(equalTo: step4.trailingAnchor, constant: 8),
            restIntervalField.widthAnchor.constraint(equalToConstant: 70),
            restIntervalField.centerYAnchor.constraint(equalTo: step4.centerYAnchor),

            restLoopsLabel.leadingAnchor.constraint(equalTo: restIntervalField.trailingAnchor, constant: 8),
            restLoopsLabel.centerYAnchor.constraint(equalTo: step4.centerYAnchor),

            restField.leadingAnchor.constraint(equalTo: restLoopsLabel.trailingAnchor, constant: 8),
            restField.widthAnchor.constraint(equalToConstant: 80),
            restField.centerYAnchor.constraint(equalTo: step4.centerYAnchor),

            restSecondsLabel.leadingAnchor.constraint(equalTo: restField.trailingAnchor, constant: 8),
            restSecondsLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
            restSecondsLabel.centerYAnchor.constraint(equalTo: step4.centerYAnchor),

            step5.topAnchor.constraint(equalTo: step4.bottomAnchor, constant: 10),
            step5.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            step5.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            play.topAnchor.constraint(equalTo: step5.bottomAnchor, constant: 12),
            play.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),

            stop.centerYAnchor.constraint(equalTo: play.centerYAnchor),
            stop.leadingAnchor.constraint(equalTo: play.trailingAnchor, constant: 8),

            status.centerYAnchor.constraint(equalTo: play.centerYAnchor),
            status.leadingAnchor.constraint(equalTo: stop.trailingAnchor, constant: 10),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12)
        ])

        panel.contentView = content
        window = panel
        if let storedOrigin = loadStoredWindowOrigin() {
            hasUserPinnedPosition = true
            setWindowOrigin(panel, storedOrigin)
        }
        updatePlaybackState(isRunning: false, iteration: 0)
    }

    private func screenContaining(region: NSRect) -> NSScreen? {
        if let exact = NSScreen.screens.first(where: { $0.frame.intersects(region) }) {
            return exact
        }
        let center = NSPoint(x: region.midX, y: region.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })
    }

    private func showValidationError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Invalid Macro Value"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func startReadingShortcutCapture() {
        guard !isReadingKey else { return }
        guard !lastPlaybackIsRunning else { return }

        isReadingKey = true
        readKeyButton?.title = "Cancel Read"
        playButton?.isEnabled = false
        statusLabel?.stringValue = "Reading key... (Esc to cancel)"

        localReadKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.consumeReadKey(event: event)
            return nil
        }
        globalReadKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.consumeReadKey(event: event)
        }
    }

    private func stopReadingShortcutCapture(updateStatus: Bool) {
        if let localReadKeyMonitor {
            NSEvent.removeMonitor(localReadKeyMonitor)
            self.localReadKeyMonitor = nil
        }
        if let globalReadKeyMonitor {
            NSEvent.removeMonitor(globalReadKeyMonitor)
            self.globalReadKeyMonitor = nil
        }
        isReadingKey = false
        readKeyButton?.title = "Read Key"
        playButton?.isEnabled = !lastPlaybackIsRunning
        readKeyButton?.isEnabled = !lastPlaybackIsRunning
        if updateStatus {
            refreshStatusText()
        }
    }

    private func consumeReadKey(event: NSEvent) {
        DispatchQueue.main.async {
            guard self.isReadingKey else { return }

            if event.keyCode == UInt16(kVK_Escape) {
                self.stopReadingShortcutCapture(updateStatus: true)
                return
            }

            do {
                let shortcut = try HotkeyShortcut.from(event: event)
                self.afterShortcutField?.stringValue = shortcut.editableString
                self.stopReadingShortcutCapture(updateStatus: false)
                self.statusLabel?.stringValue = "Key set: \(shortcut.displayString)"
            } catch {
                self.statusLabel?.stringValue = "Unsupported key. Try A-Z, 0-9, arrow, F1-F12."
            }
        }
    }

    private func refreshStatusText() {
        if lastPlaybackIsRunning {
            statusLabel?.stringValue = "Running (Loop \(lastPlaybackIteration))"
        } else {
            statusLabel?.stringValue = "Stopped (Last loop \(lastPlaybackIteration))"
        }
    }

    func windowDidMove(_ notification: Notification) {
        guard let movedWindow = notification.object as? NSWindow,
              movedWindow == window else { return }
        guard !isProgrammaticMoveInProgress else { return }

        hasUserPinnedPosition = true
        defaults.set(movedWindow.frame.origin.x, forKey: windowOriginXDefaultsKey)
        defaults.set(movedWindow.frame.origin.y, forKey: windowOriginYDefaultsKey)
    }

    private func setWindowOrigin(_ window: NSWindow, _ origin: NSPoint) {
        isProgrammaticMoveInProgress = true
        window.setFrameOrigin(origin)
        DispatchQueue.main.async {
            self.isProgrammaticMoveInProgress = false
        }
    }

    private func loadStoredWindowOrigin() -> NSPoint? {
        guard defaults.object(forKey: windowOriginXDefaultsKey) != nil,
              defaults.object(forKey: windowOriginYDefaultsKey) != nil else {
            return nil
        }
        return NSPoint(
            x: defaults.double(forKey: windowOriginXDefaultsKey),
            y: defaults.double(forKey: windowOriginYDefaultsKey)
        )
    }

    func windowWillClose(_ notification: Notification) {
        stopReadingShortcutCapture(updateStatus: false)
    }
}
