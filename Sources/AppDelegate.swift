import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    private lazy var settingsWindowController = SettingsWindowController()
    private var captureMenuItem: NSMenuItem?
    private var screenshotMenuItem: NSMenuItem?
    private var saveScreenshotMenuItem: NSMenuItem?
    private var closeAllMenuItem: NSMenuItem?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupStatusBar()
        setupHotkeys()
        PermissionGuideManager.shared.checkAndGuidePermissionsIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        PinManager.shared.finishEditing()
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
        let screenshotItem = NSMenuItem(title: "Take Screenshot…", action: #selector(screenshotClicked), keyEquivalent: "")
        screenshotItem.target = self
        menu.addItem(screenshotItem)
        screenshotMenuItem = screenshotItem

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

        let historyItem = NSMenuItem(title: "Screenshot History…", action: #selector(openHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)

        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit PinShot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        
        statusItem.menu = menu
        updateHotkeyMenuItems()
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

        HotkeyManager.shared.onScreenshotShortcut = { [weak self] in
            self?.screenshotClicked()
        }
        
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
            PinManager.shared.pin(image: result.0, at: result.1, recordHistory: true)
        }
    }

    @objc private func screenshotClicked() {
        // A menu invocation should not freeze the status menu into the screenshot.
        DispatchQueue.main.async { CaptureManager.shared.startScreenshot() }
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

    @objc private func openSettings() {
        settingsWindowController.showSettings()
    }

    @objc private func openHistory() {
        DispatchQueue.main.async { PinHistoryWindowController.shared.showHistory() }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        updateHotkeyMenuItems()
    }

    private func updateHotkeyMenuItems() {
        let unavailable = HotkeyManager.shared.registrationErrors[.screenshot]
        screenshotMenuItem?.title = "Take Screenshot… (\(HotkeyManager.shared.screenshotShortcutDisplay))" + (unavailable == nil ? "" : " — Shortcut Unavailable")
        screenshotMenuItem?.toolTip = unavailable
        captureMenuItem?.title = "Capture & Pin (\(HotkeyManager.shared.captureShortcutDisplay))"
        saveScreenshotMenuItem?.title = "Capture & Save Screenshot (\(HotkeyManager.shared.saveScreenshotShortcutDisplay))"
        closeAllMenuItem?.title = "Close All Pins (\(HotkeyManager.shared.closeAllShortcutDisplay))"
    }
}
