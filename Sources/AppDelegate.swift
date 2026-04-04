import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    private var launchAtLoginMenuItem: NSMenuItem?
    private var captureMenuItem: NSMenuItem?
    private var saveScreenshotMenuItem: NSMenuItem?
    private var setScreenshotRegionMenuItem: NSMenuItem?
    private var closeAllMenuItem: NSMenuItem?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupStatusBar()
        setupHotkeys()
        PermissionGuideManager.shared.checkAndGuidePermissionsIfNeeded()
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = makeStableStatusBarIcon()

            button.image = image
            button.title = ""
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleNone
        }
        
        let menu = NSMenu()
        let captureItem = NSMenuItem(title: "Capture & Pin", action: #selector(captureClicked), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)
        captureMenuItem = captureItem

        let saveScreenshotItem = NSMenuItem(
            title: "Capture & Save Screenshot",
            action: #selector(saveScreenshotClicked),
            keyEquivalent: ""
        )
        saveScreenshotItem.target = self
        menu.addItem(saveScreenshotItem)
        saveScreenshotMenuItem = saveScreenshotItem

        let closeItem = NSMenuItem(title: "Close All Pins", action: #selector(closeAllClicked), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)
        closeAllMenuItem = closeItem

        let changeCaptureItem = NSMenuItem(title: "Change Capture Shortcut…", action: #selector(changeCaptureShortcut), keyEquivalent: "")
        changeCaptureItem.target = self
        menu.addItem(changeCaptureItem)

        let changeSaveScreenshotItem = NSMenuItem(
            title: "Change Save-Screenshot Shortcut…",
            action: #selector(changeSaveScreenshotShortcut),
            keyEquivalent: ""
        )
        changeSaveScreenshotItem.target = self
        menu.addItem(changeSaveScreenshotItem)

        let setScreenshotRegionItem = NSMenuItem(
            title: "Set Screenshot Region…",
            action: #selector(setScreenshotRegionClicked),
            keyEquivalent: ""
        )
        setScreenshotRegionItem.target = self
        menu.addItem(setScreenshotRegionItem)
        setScreenshotRegionMenuItem = setScreenshotRegionItem

        let changeSetScreenshotRegionItem = NSMenuItem(
            title: "Change Set-Region Shortcut…",
            action: #selector(changeSetScreenshotRegionShortcut),
            keyEquivalent: ""
        )
        changeSetScreenshotRegionItem.target = self
        menu.addItem(changeSetScreenshotRegionItem)

        let changeCloseAllItem = NSMenuItem(title: "Change Close-All Shortcut…", action: #selector(changeCloseAllShortcut), keyEquivalent: "")
        changeCloseAllItem.target = self
        menu.addItem(changeCloseAllItem)

        let resetShortcutsItem = NSMenuItem(title: "Reset Shortcuts to Default", action: #selector(resetShortcutsToDefault), keyEquivalent: "")
        resetShortcutsItem.target = self
        menu.addItem(resetShortcutsItem)

        menu.addItem(NSMenuItem.separator())
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        menu.addItem(launchItem)
        launchAtLoginMenuItem = launchItem
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit PinShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        
        statusItem.menu = menu
        updateHotkeyMenuItems()
        updateLaunchAtLoginMenuItem()
    }

    private func makeStableStatusBarIcon() -> NSImage? {
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold, scale: .small)
        guard let symbol = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "PinShot")?.withSymbolConfiguration(symbolConfig) else {
            return nil
        }

        // Draw the symbol into a fixed canvas so third-party menubar managers do not reflow variable symbol bounds.
        let canvasSize = NSSize(width: 18, height: 18)
        let icon = NSImage(size: canvasSize)
        icon.lockFocus()
        symbol.draw(
            in: NSRect(x: 1.0, y: 0.8, width: 16, height: 16),
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )
        icon.unlockFocus()
        icon.isTemplate = true
        return icon
    }
    
    private func setupHotkeys() {
        // Initialize the shared hotkey manager
        let _ = HotkeyManager.shared
        
        HotkeyManager.shared.onCaptureShortcut = { [weak self] in
            self?.captureClicked()
        }

        HotkeyManager.shared.onSaveScreenshotShortcut = { [weak self] in
            self?.saveScreenshotClicked()
        }

        HotkeyManager.shared.onSetScreenshotRegionShortcut = { [weak self] in
            self?.setScreenshotRegionClicked()
        }
        
        HotkeyManager.shared.onCloseAllShortcut = { [weak self] in
            self?.closeAllClicked()
        }
    }
    
    @objc private func captureClicked() {
        CaptureManager.shared.startCapture { result in
            guard let result = result else { return }
            PinManager.shared.pin(image: result.0, at: result.1)
        }
    }

    @objc private func saveScreenshotClicked() {
        ScreenshotSaveManager.shared.captureUsingSavedRegionOrPromptSelection()
    }

    @objc private func setScreenshotRegionClicked() {
        ScreenshotSaveManager.shared.selectRegionAndCaptureAndSave()
    }

    @objc private func closeAllClicked() {
        PinManager.shared.closeAll()
    }

    @objc private func toggleLaunchAtLogin() {
        let manager = LoginLaunchManager.shared
        let nextEnabled = !manager.isEnabled

        do {
            try manager.setEnabled(nextEnabled)
        } catch {
            showLaunchAtLoginError(error)
        }

        updateLaunchAtLoginMenuItem()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateHotkeyMenuItems()
        updateLaunchAtLoginMenuItem()
    }

    private func updateHotkeyMenuItems() {
        captureMenuItem?.title = "Capture & Pin (\(HotkeyManager.shared.captureShortcutDisplay))"
        saveScreenshotMenuItem?.title = "Capture & Save Screenshot (\(HotkeyManager.shared.saveScreenshotShortcutDisplay))"
        setScreenshotRegionMenuItem?.title = "Set Screenshot Region… (\(HotkeyManager.shared.setScreenshotRegionShortcutDisplay))"
        closeAllMenuItem?.title = "Close All Pins (\(HotkeyManager.shared.closeAllShortcutDisplay))"
    }

    @objc private func changeCaptureShortcut() {
        promptForShortcutChange(
            action: .capture,
            title: "Change Capture Shortcut"
        )
    }

    @objc private func changeSaveScreenshotShortcut() {
        promptForShortcutChange(
            action: .saveScreenshot,
            title: "Change Save-Screenshot Shortcut"
        )
    }

    @objc private func changeSetScreenshotRegionShortcut() {
        promptForShortcutChange(
            action: .setScreenshotRegion,
            title: "Change Set-Region Shortcut"
        )
    }

    @objc private func changeCloseAllShortcut() {
        promptForShortcutChange(
            action: .closeAll,
            title: "Change Close-All Shortcut"
        )
    }

    @objc private func resetShortcutsToDefault() {
        do {
            try HotkeyManager.shared.resetShortcut(action: .capture)
            try HotkeyManager.shared.resetShortcut(action: .saveScreenshot)
            try HotkeyManager.shared.resetShortcut(action: .setScreenshotRegion)
            try HotkeyManager.shared.resetShortcut(action: .closeAll)
            updateHotkeyMenuItems()
        } catch {
            showHotkeyError(error)
        }
    }

    private func promptForShortcutChange(action: HotkeyAction, title: String) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = title
        alert.informativeText = "Press the shortcut keys now. Modifier keys are optional."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let currentShortcut = HotkeyManager.shared.shortcut(for: action)
        let recorderView = HotkeyRecorderView(frame: NSRect(x: 0, y: 0, width: 320, height: 42), initialShortcut: currentShortcut)
        alert.accessoryView = recorderView

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        guard let shortcut = recorderView.recordedShortcut else {
            showHotkeyError(HotkeyError.invalidFormat)
            return
        }

        do {
            try HotkeyManager.shared.updateShortcut(action: action, shortcut: shortcut)
            updateHotkeyMenuItems()
        } catch {
            showHotkeyError(error)
        }
    }

    private func updateLaunchAtLoginMenuItem() {
        guard let item = launchAtLoginMenuItem else { return }

        let manager = LoginLaunchManager.shared
        if manager.isSupported {
            item.title = "Launch at Login"
            item.isEnabled = true
            item.state = manager.isEnabled ? .on : .off
        } else {
            item.title = "Launch at Login (macOS 13+)"
            item.isEnabled = false
            item.state = .off
        }
    }

    private func showLaunchAtLoginError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could Not Update Login Setting"
        alert.informativeText = "Please check login item permission in System Settings and try again."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showHotkeyError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could Not Update Shortcut"
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? "Please try another shortcut."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private final class HotkeyRecorderView: NSView {
    private let valueLabel = NSTextField(labelWithString: "")
    private(set) var recordedShortcut: HotkeyShortcut?

    init(frame frameRect: NSRect, initialShortcut: HotkeyShortcut) {
        self.recordedShortcut = initialShortcut
        super.init(frame: frameRect)
        setupUI()
        valueLabel.stringValue = "Current: \(initialShortcut.displayString)"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        do {
            let shortcut = try HotkeyShortcut.from(event: event)
            recordedShortcut = shortcut
            valueLabel.stringValue = "Recorded: \(shortcut.displayString)"
        } catch {
            NSSound.beep()
        }
    }

    private func setupUI() {
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        valueLabel.alignment = .center
        valueLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(valueLabel)

        NSLayoutConstraint.activate([
            valueLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            valueLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}
