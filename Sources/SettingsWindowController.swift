import Cocoa

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let launchAtLoginButton = NSButton(checkboxWithTitle: "Launch at Login", target: nil, action: nil)
    private let loginDescription = NSTextField(wrappingLabelWithString: "")
    private var shortcutButtons: [HotkeyAction: NSButton] = [:]
    private var shortcutWarnings: [HotkeyAction: NSTextField] = [:]
    private let historyEnabledButton = NSButton(checkboxWithTitle: "Save Capture & Pin history automatically", target: nil, action: nil)
    private let historyRetentionButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private var directoryLabels: [CaptureDestination: NSTextField] = [:]
    private let appearanceView = ScreenshotAppearanceView()
    private let shortcutRows: [(HotkeyAction, String)] = [
        (.screenshot, "Take Screenshot"),
        (.capture, "Capture & Pin"),
        (.saveScreenshot, "Capture & Save Screenshot"),
        (.setScreenshotRegion, "Set Screenshot Region"),
        (.closeAll, "Close All Pins")
    ]

    init() {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 580),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = "PinShot Settings"
        window.isReleasedWhenClosed = false
        window.collectionBehavior = .moveToActiveSpace
        super.init(window: window)
        window.delegate = self
        buildContent()
        window.center()
        window.setFrameAutosaveName("PinShotSettings")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showSettings() {
        refreshSettings()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        refreshSettings()
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }

        launchAtLoginButton.target = self
        launchAtLoginButton.action = #selector(toggleLaunchAtLogin)
        loginDescription.font = .systemFont(ofSize: 11)
        loginDescription.textColor = .secondaryLabelColor
        let login = verticalStack([launchAtLoginButton, loginDescription], spacing: 4)

        let regionButton = NSButton(title: "Set Region…", target: self, action: #selector(setScreenshotRegion))
        regionButton.bezelStyle = .rounded
        let region = row(
            title: "Saved Screenshot Region",
            detail: "Select a region and save a screenshot immediately.",
            control: regionButton
        )
        historyEnabledButton.target = self
        historyEnabledButton.action = #selector(togglePinHistory)
        let historyDescription = NSTextField(wrappingLabelWithString:
            "New pins are saved in the pinned screenshot folder. Turning history off keeps existing captures.")
        historyDescription.font = .systemFont(ofSize: 11)
        historyDescription.textColor = .secondaryLabelColor
        for retention in PinHistoryRetention.allCases {
            historyRetentionButton.addItem(withTitle: retention.title)
            historyRetentionButton.lastItem?.tag = retention.rawValue
        }
        historyRetentionButton.target = self
        historyRetentionButton.action = #selector(changeHistoryRetention)
        historyRetentionButton.setAccessibilityLabel("Screenshot history limit")
        let retentionRow = row(title: "History Limit", detail: nil, control: historyRetentionButton)
        let retentionDescription = NSTextField(wrappingLabelWithString:
            "When a new capture exceeds the limit, the oldest history entries and their PNG files are deleted.")
        retentionDescription.font = .systemFont(ofSize: 11)
        retentionDescription.textColor = .secondaryLabelColor
        let historyButton = NSButton(title: "Open History…", target: self, action: #selector(openHistory))
        historyButton.bezelStyle = .rounded
        let history = verticalStack([historyEnabledButton, historyDescription, retentionRow, retentionDescription,
            horizontalRow(label: NSView(), control: historyButton)], spacing: 6)
        let general = verticalStack([login, separator(), region, separator(), history], spacing: 16)

        var rows: [NSView] = []
        for (index, entry) in shortcutRows.enumerated() {
            let (action, title) = entry
            let button = NSButton(title: "", target: self, action: #selector(changeShortcut(_:)))
            button.tag = index
            button.bezelStyle = .rounded
            button.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
            button.widthAnchor.constraint(equalToConstant: 112).isActive = true
            button.setAccessibilityLabel("Change \(title) shortcut")
            shortcutButtons[action] = button

            let warning = NSTextField(labelWithString: "Shortcut unavailable")
            warning.font = .systemFont(ofSize: 11)
            warning.textColor = .secondaryLabelColor
            warning.isHidden = true
            shortcutWarnings[action] = warning
            let label = verticalStack([NSTextField(labelWithString: title), warning], spacing: 2)
            rows.append(horizontalRow(label: label, control: button))
            if index < shortcutRows.count - 1 { rows.append(separator()) }
        }

        let resetButton = NSButton(title: "Restore Defaults", target: self, action: #selector(resetShortcuts))
        resetButton.bezelStyle = .rounded
        let footer = row(title: "Click a shortcut to change it.", detail: nil, control: resetButton)
        let shortcuts = verticalStack(rows, spacing: 8)
        let tabs = NSTabView()
        tabs.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(tabs)
        NSLayoutConstraint.activate([
            tabs.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            tabs.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            tabs.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            tabs.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16)
        ])
        addTab("General", stack: verticalStack([section(title: "General", content: general)], spacing: 16), to: tabs)
        addTab("Save Locations", stack: savingContent(), to: tabs)
        let appearanceContainer = NSView()
        appearanceView.translatesAutoresizingMaskIntoConstraints = false
        appearanceContainer.addSubview(appearanceView)
        NSLayoutConstraint.activate([
            appearanceView.centerXAnchor.constraint(equalTo: appearanceContainer.centerXAnchor),
            appearanceView.topAnchor.constraint(equalTo: appearanceContainer.topAnchor, constant: 12),
            appearanceView.widthAnchor.constraint(equalToConstant: 370),
            appearanceView.heightAnchor.constraint(equalToConstant: 386),
            appearanceContainer.heightAnchor.constraint(equalToConstant: 410)
        ])
        addTab("Screenshot Frame", stack: verticalStack([appearanceContainer], spacing: 0), to: tabs)
        addTab("Shortcuts", stack: verticalStack([section(title: "Keyboard Shortcuts", content: shortcuts), footer], spacing: 16), to: tabs)
    }

    private func addTab(_ title: String, stack: NSStackView, to tabs: NSTabView) {
        let item = NSTabViewItem(identifier: title)
        item.label = title
        let container = NSView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20)
        ])
        item.view = container
        tabs.addTabViewItem(item)
    }

    private func savingContent() -> NSStackView {
        var rows: [NSView] = []
        for (index, destination) in CaptureDestination.allCases.enumerated() {
            let path = NSTextField(labelWithString: "")
            path.font = .systemFont(ofSize: 11)
            path.textColor = .secondaryLabelColor
            path.lineBreakMode = .byTruncatingMiddle
            path.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            path.isSelectable = true
            directoryLabels[destination] = path
            let choose = NSButton(title: "Choose…", target: self, action: #selector(chooseDirectory(_:)))
            choose.bezelStyle = .rounded
            choose.tag = index
            let open = NSButton(title: "Open", target: self, action: #selector(openDirectory(_:)))
            open.bezelStyle = .rounded
            open.tag = index
            let buttons = NSStackView(views: [choose, open])
            buttons.orientation = .horizontal
            buttons.spacing = 4
            let labels = verticalStack([NSTextField(labelWithString: destination.title), path], spacing: 6)
            rows.append(horizontalRow(label: labels, control: buttons))
            if index < CaptureDestination.allCases.count - 1 { rows.append(separator()) }
        }
        let note = NSTextField(wrappingLabelWithString:
            "Each capture type has its own folder. Changing a folder affects new saves; existing history stays available from its original location.")
        note.font = .systemFont(ofSize: 12)
        note.textColor = .secondaryLabelColor
        return verticalStack([section(title: "Save Locations", content: verticalStack(rows, spacing: 20)), note], spacing: 16)
    }

    @objc private func chooseDirectory(_ sender: NSButton) {
        guard let window else { return }
        let destination = CaptureDestination.allCases[sender.tag]
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Folder"
        panel.message = "Save \(destination.title.lowercased()) in:"
        panel.directoryURL = CapturePreferences.shared.directory(for: destination)
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            CapturePreferences.shared.setDirectory(url, for: destination)
            self?.refreshSettings()
        }
    }

    @objc private func openDirectory(_ sender: NSButton) {
        ScreenshotSaveManager.shared.openSaveDirectory(for: CaptureDestination.allCases[sender.tag])
    }

    @objc private func togglePinHistory() {
        CapturePreferences.shared.pinHistoryEnabled = historyEnabledButton.state == .on
        NotificationCenter.default.post(name: .pinHistoryChanged, object: nil)
    }

    @objc private func changeHistoryRetention() {
        guard let tag = historyRetentionButton.selectedItem?.tag,
              let retention = PinHistoryRetention(rawValue: tag) else { return }
        // Apply the new limit on the next saved capture, not while editing Settings.
        CapturePreferences.shared.pinHistoryRetention = retention
    }

    @objc private func openHistory() { PinHistoryWindowController.shared.showHistory() }

    private func section(title: String, content: NSStackView) -> NSView {
        let heading = NSTextField(labelWithString: title)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        let box = NSBox()
        box.titlePosition = .noTitle
        box.boxType = .primary
        content.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: box.topAnchor, constant: 14),
            content.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -14)
        ])
        return verticalStack([heading, box], spacing: 8)
    }

    private func row(title: String, detail: String?, control: NSView) -> NSView {
        var labels: [NSView] = [NSTextField(labelWithString: title)]
        if let detail {
            let description = NSTextField(wrappingLabelWithString: detail)
            description.font = .systemFont(ofSize: 11)
            description.textColor = .secondaryLabelColor
            labels.append(description)
        }
        return horizontalRow(label: verticalStack(labels, spacing: 4), control: control)
    }

    private func horizontalRow(label: NSView, control: NSView) -> NSView {
        let stack = NSStackView(views: [label, NSView(), control])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        return stack
    }

    private func verticalStack(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        for view in views {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        return stack
    }

    private func separator() -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    private func refreshSettings() {
        let loginManager = LoginLaunchManager.shared
        launchAtLoginButton.isEnabled = loginManager.isSupported
        launchAtLoginButton.state = loginManager.isEnabled ? .on : .off
        loginDescription.stringValue = loginManager.isSupported
            ? "Start PinShot automatically when you log in."
            : "Launch at Login requires macOS 13 or later."

        for (action, _) in shortcutRows {
            let error = HotkeyManager.shared.registrationErrors[action]
            shortcutButtons[action]?.title = HotkeyManager.shared.shortcut(for: action).displayString
            shortcutButtons[action]?.toolTip = error ?? "Click to record a new shortcut."
            shortcutWarnings[action]?.isHidden = error == nil
            shortcutWarnings[action]?.toolTip = error
        }
        historyEnabledButton.state = CapturePreferences.shared.pinHistoryEnabled ? .on : .off
        historyRetentionButton.selectItem(withTag: CapturePreferences.shared.pinHistoryRetention.rawValue)
        for (destination, label) in directoryLabels {
            let path = CapturePreferences.shared.directory(for: destination).path
            label.stringValue = path
            label.toolTip = path
        }
        appearanceView.reload()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginLaunchManager.shared.setEnabled(launchAtLoginButton.state == .on)
        } catch {
            showError(title: "Could Not Update Login Setting", message: "Please check login item permission in System Settings and try again.")
        }
        refreshSettings()
    }

    @objc private func setScreenshotRegion() {
        // Let the settings window leave the screen before freezing the capture.
        window?.orderOut(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            ScreenshotSaveManager.shared.selectRegionAndCaptureAndSave()
        }
    }

    @objc private func changeShortcut(_ sender: NSButton) {
        guard let window, window.attachedSheet == nil else { return }
        let (action, title) = shortcutRows[sender.tag]
        let alert = NSAlert()
        alert.messageText = "Change \(title) Shortcut"
        alert.informativeText = "Press the shortcut keys now. Modifier keys are optional. Press Return to save or Esc to cancel."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let recorder = HotkeyRecorderView(initialShortcut: HotkeyManager.shared.shortcut(for: action))
        alert.accessoryView = recorder

        HotkeyManager.shared.beginShortcutRecording()
        alert.beginSheetModal(for: window) { [weak self] response in
            HotkeyManager.shared.endShortcutRecording()
            guard let self else { return }
            if response == .alertFirstButtonReturn {
                do {
                    try HotkeyManager.shared.updateShortcut(action: action, shortcut: recorder.recordedShortcut)
                } catch {
                    self.showError(title: "Could Not Update Shortcut", message: error.localizedDescription)
                }
            }
            self.refreshSettings()
        }
        alert.window.makeFirstResponder(recorder)
    }

    @objc private func resetShortcuts() {
        do {
            try HotkeyManager.shared.resetAllShortcuts()
        } catch {
            showError(title: "Could Not Restore Shortcuts", message: error.localizedDescription)
        }
        refreshSettings()
    }

    private func showError(title: String, message: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }
}

private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if attachedSheet == nil, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.keyCode == 13 { // Command-W also works in this menu bar app without a main menu.
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private final class HotkeyRecorderView: NSView {
    private let valueLabel = NSTextField(labelWithString: "")
    private(set) var recordedShortcut: HotkeyShortcut

    init(initialShortcut: HotkeyShortcut) {
        recordedShortcut = initialShortcut
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 48))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        valueLabel.font = .monospacedSystemFont(ofSize: 17, weight: .medium)
        valueLabel.stringValue = initialShortcut.displayString
        valueLabel.alignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)
        NSLayoutConstraint.activate([
            valueLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityLabel("Shortcut recorder")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        return record(event)
    }

    override func keyDown(with event: NSEvent) {
        if !record(event) { super.keyDown(with: event) }
    }

    private func record(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        // Keep the standard sheet Save/Cancel keys available.
        if modifiers.isEmpty && (event.keyCode == 36 || event.keyCode == 53) { return false }
        do {
            recordedShortcut = try HotkeyShortcut.from(event: event)
            valueLabel.stringValue = recordedShortcut.displayString
        } catch {
            NSSound.beep()
        }
        return true
    }
}
