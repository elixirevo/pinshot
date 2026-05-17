import Cocoa
import Carbon

struct MacroPlaybackSettings {
    let afterShortcutText: String
    let postDelaySeconds: TimeInterval
    let macroTermMaxSeconds: TimeInterval
    let restLoopInterval: Int
    let restDurationSeconds: TimeInterval
    let maxLoopCount: Int
    let periodicShortcutEnabled: Bool
    let periodicShortcutText: String
    let periodicShortcutLoopInterval: Int
    let periodicShortcutDelaySeconds: TimeInterval
}

final class MacroControlWindowManager: NSObject, NSWindowDelegate {
    static let shared = MacroControlWindowManager()

    var onPlayRequested: ((MacroPlaybackSettings) -> Void)?
    var onStopRequested: (() -> Void)?

    private enum ShortcutCaptureTarget {
        case afterScreenshot
        case periodicShortcut
    }

    private var window: NSPanel?
    private var afterShortcutField: NSTextField?
    private var postDelayField: NSTextField?
    private var macroTermMaxField: NSTextField?
    private var restLoopIntervalField: NSTextField?
    private var restDurationField: NSTextField?
    private var maxLoopCountField: NSTextField?
    private var periodicShortcutEnabledCheckbox: NSButton?
    private var periodicShortcutLoopIntervalField: NSTextField?
    private var periodicShortcutField: NSTextField?
    private var periodicShortcutDelayField: NSTextField?
    private var playButton: NSButton?
    private var stopButton: NSButton?
    private var readKeyButton: NSButton?
    private var readPeriodicKeyButton: NSButton?
    private var statusLabel: NSTextField?
    private let defaults = UserDefaults.standard
    private let windowOriginXDefaultsKey = "macro.windowOrigin.x"
    private let windowOriginYDefaultsKey = "macro.windowOrigin.y"
    private var hasUserPinnedPosition = false
    private var isProgrammaticMoveInProgress = false
    private var readingShortcutTarget: ShortcutCaptureTarget?
    private var localReadKeyMonitor: Any?
    private var globalReadKeyMonitor: Any?
    private var lastPlaybackIsRunning = false
    private var lastPlaybackIteration = 0

    private var isReadingKey: Bool {
        readingShortcutTarget != nil
    }

    private override init() {
        super.init()
    }

    func configure(settings: MacroPlaybackSettings) {
        DispatchQueue.main.async {
            self.ensureWindow()
            self.afterShortcutField?.stringValue = settings.afterShortcutText
            self.postDelayField?.stringValue = String(format: "%.2f", settings.postDelaySeconds)
            self.macroTermMaxField?.stringValue = String(format: "%.2f", settings.macroTermMaxSeconds)
            self.restLoopIntervalField?.stringValue = "\(settings.restLoopInterval)"
            self.restDurationField?.stringValue = String(format: "%.2f", settings.restDurationSeconds)
            self.maxLoopCountField?.stringValue = "\(settings.maxLoopCount)"
            self.periodicShortcutEnabledCheckbox?.state = settings.periodicShortcutEnabled ? .on : .off
            self.periodicShortcutLoopIntervalField?.stringValue = "\(settings.periodicShortcutLoopInterval)"
            self.periodicShortcutField?.stringValue = settings.periodicShortcutText
            self.periodicShortcutDelayField?.stringValue = String(format: "%.2f", settings.periodicShortcutDelaySeconds)
            self.refreshControlStates()
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
            self.refreshControlStates()
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
        guard let postDelayField, let macroTermMaxField, let restLoopIntervalField, let restDurationField, let maxLoopCountField else { return }
        guard let periodicShortcutEnabledCheckbox, let periodicShortcutLoopIntervalField, let periodicShortcutDelayField else { return }
        let afterShortcutText = afterShortcutField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let delayText = postDelayField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let macroTermMaxText = macroTermMaxField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let restLoopIntervalText = restLoopIntervalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let restDurationText = restDurationField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxLoopCountText = maxLoopCountField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let periodicEnabled = periodicShortcutEnabledCheckbox.state == .on
        let periodicShortcutText = periodicShortcutField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let periodicLoopIntervalText = periodicShortcutLoopIntervalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let periodicDelayText = periodicShortcutDelayField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let delay = TimeInterval(delayText), delay.isFinite, delay >= 0 else {
            showValidationError("Post delay must be a number >= 0.")
            return
        }
        guard let macroTermMax = TimeInterval(macroTermMaxText), macroTermMax.isFinite, macroTermMax >= 0 else {
            showValidationError("Macro term max must be a number >= 0.")
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
        guard let maxLoopCount = Int(maxLoopCountText), maxLoopCount >= 0 else {
            showValidationError("Maximum loops must be an integer >= 0. Use 0 for unlimited.")
            return
        }

        let periodicLoopInterval: Int
        let periodicDelay: TimeInterval
        if periodicEnabled {
            guard !periodicShortcutText.isEmpty else {
                showValidationError("Periodic shortcut is enabled, so enter a shortcut.")
                return
            }
            guard let parsedLoopInterval = Int(periodicLoopIntervalText), parsedLoopInterval > 0 else {
                showValidationError("Periodic shortcut loop interval must be an integer >= 1.")
                return
            }
            guard let parsedDelay = TimeInterval(periodicDelayText), parsedDelay.isFinite, parsedDelay >= 0 else {
                showValidationError("Periodic shortcut wait must be a number >= 0.")
                return
            }
            periodicLoopInterval = parsedLoopInterval
            periodicDelay = parsedDelay
        } else {
            periodicLoopInterval = Int(periodicLoopIntervalText) ?? 1
            periodicDelay = TimeInterval(periodicDelayText) ?? 0
        }

        onPlayRequested?(
            MacroPlaybackSettings(
                afterShortcutText: afterShortcutText,
                postDelaySeconds: delay,
                macroTermMaxSeconds: macroTermMax,
                restLoopInterval: restLoopInterval,
                restDurationSeconds: restDuration,
                maxLoopCount: maxLoopCount,
                periodicShortcutEnabled: periodicEnabled,
                periodicShortcutText: periodicShortcutText,
                periodicShortcutLoopInterval: periodicLoopInterval,
                periodicShortcutDelaySeconds: periodicDelay
            )
        )
    }

    @objc private func stopClicked() {
        onStopRequested?()
    }

    @objc private func readKeyClicked() {
        if readingShortcutTarget == .afterScreenshot {
            stopReadingShortcutCapture(updateStatus: true)
            return
        }
        startReadingShortcutCapture(target: .afterScreenshot)
    }

    @objc private func readPeriodicKeyClicked() {
        if readingShortcutTarget == .periodicShortcut {
            stopReadingShortcutCapture(updateStatus: true)
            return
        }
        startReadingShortcutCapture(target: .periodicShortcut)
    }

    @objc private func periodicEnabledChanged() {
        refreshControlStates()
    }

    private func ensureWindow() {
        guard window == nil else { return }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
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
        let step4 = NSTextField(labelWithString: "4. Macro term: random 0 to")
        let macroTermSecondsLabel = NSTextField(labelWithString: "seconds")
        let step5 = NSTextField(labelWithString: "5. Rest every")
        let restLoopsLabel = NSTextField(labelWithString: "loops for")
        let restSecondsLabel = NSTextField(labelWithString: "seconds")
        let step6 = NSTextField(labelWithString: "6. Periodic shortcut after rest")
        let periodicEveryLabel = NSTextField(labelWithString: "every")
        let periodicLoopsLabel = NSTextField(labelWithString: "loops")
        let periodicWaitLabel = NSTextField(labelWithString: "After shortcut: wait")
        let periodicWaitSecondsLabel = NSTextField(labelWithString: "seconds")
        let step7 = NSTextField(labelWithString: "7. Stop after")
        let maxLoopSuffixLabel = NSTextField(labelWithString: "loops (0 = unlimited)")
        let step8 = NSTextField(labelWithString: "8. Loop back to step 1")
        [
            step1, step2, step3, step4, macroTermSecondsLabel, step5, restLoopsLabel, restSecondsLabel,
            step6, periodicEveryLabel, periodicLoopsLabel, periodicWaitLabel, periodicWaitSecondsLabel,
            step7, maxLoopSuffixLabel, step8
        ].forEach {
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

        let macroTermField = NSTextField(string: "3.00")
        macroTermField.placeholderString = "seconds"
        macroTermField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        macroTermField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(macroTermField)
        macroTermMaxField = macroTermField

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

        let maxLoopField = NSTextField(string: "0")
        maxLoopField.placeholderString = "loops"
        maxLoopField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        maxLoopField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(maxLoopField)
        maxLoopCountField = maxLoopField

        let periodicEnabled = NSButton(checkboxWithTitle: "Enable", target: self, action: #selector(periodicEnabledChanged))
        periodicEnabled.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(periodicEnabled)
        periodicShortcutEnabledCheckbox = periodicEnabled

        let periodicIntervalField = NSTextField(string: "10")
        periodicIntervalField.placeholderString = "loops"
        periodicIntervalField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        periodicIntervalField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(periodicIntervalField)
        periodicShortcutLoopIntervalField = periodicIntervalField

        let periodicField = NSTextField(string: "")
        periodicField.placeholderString = "ex) command+r, option+right"
        periodicField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        periodicField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(periodicField)
        periodicShortcutField = periodicField

        let readPeriodicButton = NSButton(title: "Read Key", target: self, action: #selector(readPeriodicKeyClicked))
        readPeriodicButton.bezelStyle = .rounded
        readPeriodicButton.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(readPeriodicButton)
        readPeriodicKeyButton = readPeriodicButton

        let periodicDelayField = NSTextField(string: "1.00")
        periodicDelayField.placeholderString = "seconds"
        periodicDelayField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        periodicDelayField.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(periodicDelayField)
        periodicShortcutDelayField = periodicDelayField

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
            macroTermField.leadingAnchor.constraint(equalTo: step4.trailingAnchor, constant: 8),
            macroTermField.widthAnchor.constraint(equalToConstant: 80),
            macroTermField.centerYAnchor.constraint(equalTo: step4.centerYAnchor),

            macroTermSecondsLabel.leadingAnchor.constraint(equalTo: macroTermField.trailingAnchor, constant: 8),
            macroTermSecondsLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
            macroTermSecondsLabel.centerYAnchor.constraint(equalTo: step4.centerYAnchor),

            step5.topAnchor.constraint(equalTo: step4.bottomAnchor, constant: 10),
            step5.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            restIntervalField.leadingAnchor.constraint(equalTo: step5.trailingAnchor, constant: 8),
            restIntervalField.widthAnchor.constraint(equalToConstant: 70),
            restIntervalField.centerYAnchor.constraint(equalTo: step5.centerYAnchor),

            restLoopsLabel.leadingAnchor.constraint(equalTo: restIntervalField.trailingAnchor, constant: 8),
            restLoopsLabel.centerYAnchor.constraint(equalTo: step5.centerYAnchor),

            restField.leadingAnchor.constraint(equalTo: restLoopsLabel.trailingAnchor, constant: 8),
            restField.widthAnchor.constraint(equalToConstant: 80),
            restField.centerYAnchor.constraint(equalTo: step5.centerYAnchor),

            restSecondsLabel.leadingAnchor.constraint(equalTo: restField.trailingAnchor, constant: 8),
            restSecondsLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
            restSecondsLabel.centerYAnchor.constraint(equalTo: step5.centerYAnchor),

            step6.topAnchor.constraint(equalTo: step5.bottomAnchor, constant: 10),
            step6.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            step6.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            periodicEnabled.topAnchor.constraint(equalTo: step6.bottomAnchor, constant: 8),
            periodicEnabled.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),

            periodicEveryLabel.leadingAnchor.constraint(equalTo: periodicEnabled.trailingAnchor, constant: 12),
            periodicEveryLabel.centerYAnchor.constraint(equalTo: periodicEnabled.centerYAnchor),

            periodicIntervalField.leadingAnchor.constraint(equalTo: periodicEveryLabel.trailingAnchor, constant: 8),
            periodicIntervalField.widthAnchor.constraint(equalToConstant: 70),
            periodicIntervalField.centerYAnchor.constraint(equalTo: periodicEnabled.centerYAnchor),

            periodicLoopsLabel.leadingAnchor.constraint(equalTo: periodicIntervalField.trailingAnchor, constant: 8),
            periodicLoopsLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
            periodicLoopsLabel.centerYAnchor.constraint(equalTo: periodicEnabled.centerYAnchor),

            periodicField.topAnchor.constraint(equalTo: periodicEnabled.bottomAnchor, constant: 6),
            periodicField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            periodicField.trailingAnchor.constraint(equalTo: readPeriodicButton.leadingAnchor, constant: -8),

            readPeriodicButton.centerYAnchor.constraint(equalTo: periodicField.centerYAnchor),
            readPeriodicButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            readPeriodicButton.widthAnchor.constraint(equalToConstant: 92),

            periodicWaitLabel.topAnchor.constraint(equalTo: periodicField.bottomAnchor, constant: 8),
            periodicWaitLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),

            periodicDelayField.leadingAnchor.constraint(equalTo: periodicWaitLabel.trailingAnchor, constant: 8),
            periodicDelayField.widthAnchor.constraint(equalToConstant: 80),
            periodicDelayField.centerYAnchor.constraint(equalTo: periodicWaitLabel.centerYAnchor),

            periodicWaitSecondsLabel.leadingAnchor.constraint(equalTo: periodicDelayField.trailingAnchor, constant: 8),
            periodicWaitSecondsLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
            periodicWaitSecondsLabel.centerYAnchor.constraint(equalTo: periodicWaitLabel.centerYAnchor),

            step7.topAnchor.constraint(equalTo: periodicWaitLabel.bottomAnchor, constant: 10),
            step7.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),

            maxLoopField.leadingAnchor.constraint(equalTo: step7.trailingAnchor, constant: 8),
            maxLoopField.widthAnchor.constraint(equalToConstant: 70),
            maxLoopField.centerYAnchor.constraint(equalTo: step7.centerYAnchor),

            maxLoopSuffixLabel.leadingAnchor.constraint(equalTo: maxLoopField.trailingAnchor, constant: 8),
            maxLoopSuffixLabel.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -12),
            maxLoopSuffixLabel.centerYAnchor.constraint(equalTo: step7.centerYAnchor),

            step8.topAnchor.constraint(equalTo: step7.bottomAnchor, constant: 10),
            step8.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            step8.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            play.topAnchor.constraint(equalTo: step8.bottomAnchor, constant: 12),
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

    private func startReadingShortcutCapture(target: ShortcutCaptureTarget) {
        guard !lastPlaybackIsRunning else { return }

        if isReadingKey {
            stopReadingShortcutCapture(updateStatus: false)
        }

        readingShortcutTarget = target
        refreshControlStates()
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
        readingShortcutTarget = nil
        refreshControlStates()
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
                switch self.readingShortcutTarget {
                case .afterScreenshot:
                    self.afterShortcutField?.stringValue = shortcut.editableString
                case .periodicShortcut:
                    self.periodicShortcutField?.stringValue = shortcut.editableString
                case nil:
                    return
                }
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

    private func refreshControlStates() {
        let isReadingAfter = readingShortcutTarget == .afterScreenshot
        let isReadingPeriodic = readingShortcutTarget == .periodicShortcut
        let isPeriodicEnabled = periodicShortcutEnabledCheckbox?.state == .on

        playButton?.isEnabled = !lastPlaybackIsRunning && !isReadingKey
        stopButton?.isEnabled = lastPlaybackIsRunning

        periodicShortcutEnabledCheckbox?.isEnabled = !lastPlaybackIsRunning && !isReadingKey

        readKeyButton?.title = isReadingAfter ? "Cancel Read" : "Read Key"
        readKeyButton?.isEnabled = !lastPlaybackIsRunning && (!isReadingKey || isReadingAfter)

        readPeriodicKeyButton?.title = isReadingPeriodic ? "Cancel Read" : "Read Key"
        readPeriodicKeyButton?.isEnabled = !lastPlaybackIsRunning && isPeriodicEnabled && (!isReadingKey || isReadingPeriodic)

        periodicShortcutLoopIntervalField?.isEnabled = isPeriodicEnabled && !lastPlaybackIsRunning
        periodicShortcutField?.isEnabled = isPeriodicEnabled && !lastPlaybackIsRunning
        periodicShortcutDelayField?.isEnabled = isPeriodicEnabled && !lastPlaybackIsRunning
        maxLoopCountField?.isEnabled = !lastPlaybackIsRunning && !isReadingKey
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
