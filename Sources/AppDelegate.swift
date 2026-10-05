import Cocoa
import MacAppCore
import MacAppSettings
import MacAppMenuBar
import MacAppMainMenu
import MacAppLifecycle
import MacAppUpdatesSparkle

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBar: MenuBarController?
    private var mainMenu: MainMenuController?
    private var onboarding: OnboardingCoordinator?
    private var settings: PinShotSettings?
    private var diagnostics: AppDiagnostics?
    private var servicesStarted = false
    private let updates = SparkleUpdates()
    private lazy var lifecycle = AppLifecycleController(mode: .accessory,
        reopen: .custom { [weak self] _ in self?.reopen() })
    private let permissions = PermissionSettingsModel([
        .screenRecording(detail: appText("Capture screenshots and pin images from your screen. Images are processed on your Mac.")),
        .accessibility(detail: appText("Optional: run macro keyboard actions and use Escape to dismiss overlays while another app is active."))
    ])

    public override init() { super.init() }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            try lifecycle.start()
            AppearanceSettings.apply()
            let identity = SettingsIdentity(bundle: .main, icon: NSApp.applicationIconImage,
                website: URL(string: "https://github.com/elixirevo/pinshot"))
            let documents = try LegalDocuments()
            let diagnostics = try AppDiagnostics()
            self.diagnostics = diagnostics
            onboarding = try OnboardingCoordinator(identity: identity, documents: documents,
                permissions: permissions, diagnostics: diagnostics.settingsPreference,
                onReady: { [weak self] in self?.startServices() })
            settings = try PinShotSettings(identity: identity, permissions: permissions,
                updates: updates.settings, legal: documents, diagnostics: diagnostics.settingsPreference,
                reviewOnboarding: { [weak self] in self?.onboarding?.review() },
                setRegion: { [weak self] in
                    self?.perform {
                        self?.settings?.window.close()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            ScreenshotSaveManager.shared.selectRegionAndCaptureAndSave()
                        }
                    }
                })
            PermissionGuideManager.shared.showPermissions = { [weak self] in
                self?.perform { self?.settings?.show(.builtIn(.permissions)) }
            }
            try installMenus()
            if onboarding?.showIfNeeded() == false { startServices() }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = appText("PinShot could not start")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    private func startServices() {
        guard onboarding?.agreement.allowsAppUse == true, !servicesStarted else { return }
        servicesStarted = true
        do { try diagnostics?.start() }
        catch { NSApp.presentError(error) }
        let hotkeys = HotkeyManager.shared
        hotkeys.onScreenshotShortcut = { [weak self] in self?.perform { CaptureManager.shared.startScreenshot() } }
        hotkeys.onCaptureShortcut = { [weak self] in self?.perform { self?.capture() } }
        hotkeys.onSaveScreenshotShortcut = { [weak self] in self?.perform { ScreenshotSaveManager.shared.captureUsingSavedRegionOrPromptSelection() } }
        hotkeys.onSetScreenshotRegionShortcut = { [weak self] in self?.perform { ScreenshotSaveManager.shared.selectRegionAndCaptureAndSave() } }
        hotkeys.onCloseAllShortcut = { [weak self] in self?.perform { PinManager.shared.closeAll() } }
        hotkeys.start()
        do { try updates.start() }
        catch { NSApp.presentError(error) }
        menuBar?.refresh()
    }

    private func perform(_ action: () -> Void) {
        guard servicesStarted, onboarding?.agreement.allowsAppUse == true else {
            onboarding?.showIfNeeded()
            return
        }
        action()
    }

    private func capture() {
        CaptureManager.shared.startCapture { result in
            guard let result else { return }
            PinManager.shared.pin(image: result.0, at: result.1, recordHistory: true)
        }
    }

    private func installMenus() throws {
        func captureCommand(_ action: HotkeyAction, _ title: String, run: @escaping () -> Void) -> MenuBarItem {
            .command(.init(id: title, title: appText(title), state: { [weak self] in
                let error = HotkeyManager.shared.registrationErrors[action]
                return .init(isEnabled: self?.servicesStarted == true,
                    title: appText(title) + " (" + HotkeyManager.shared.shortcut(for: action).displayString + ")" +
                        (error == nil ? "" : " — " + appText("Shortcut Unavailable")), toolTip: error)
            }, action: { [weak self] in self?.perform(run) }))
        }
        var items: [MenuBarItem] = [
            captureCommand(.screenshot, "Take Screenshot", run: { CaptureManager.shared.startScreenshot() }),
            captureCommand(.capture, "Capture & Pin", run: { [weak self] in self?.capture() }),
            captureCommand(.saveScreenshot, "Capture & Save Screenshot", run: { ScreenshotSaveManager.shared.captureUsingSavedRegionOrPromptSelection() }),
            captureCommand(.setScreenshotRegion, "Set Screenshot Region", run: { ScreenshotSaveManager.shared.selectRegionAndCaptureAndSave() }),
            captureCommand(.closeAll, "Close All Pins", run: { PinManager.shared.closeAll() }),
            .command(.init(id: "history", title: appText("Screenshot History…"), state: { [weak self] in
                .init(isEnabled: self?.servicesStarted == true)
            }, action: { [weak self] in self?.perform { PinHistoryWindowController.shared.showHistory() } })),
            .separator,
            .command(.settings { [weak self] in self?.reopen() })
        ]
        items += MenuBarCommand.updateItems(distribution: .direct,
            manualState: { [weak self] in .init(isEnabled: self?.servicesStarted == true && self?.updates.settings.canCheckForUpdates == true) },
            check: { [weak self] in self?.perform { Task { await self?.updates.settings.checkForUpdates() } } },
            automaticState: { [weak self] in
                .init(isEnabled: self?.servicesStarted == true && self?.updates.settings.canChangeAutomaticChecks == true,
                      checkState: self?.updates.settings.automaticChecksEnabled == true ? .on : .off)
            }, toggleAutomatic: { [weak self] in self?.perform { self?.updates.settings.toggleAutomaticChecks() } })
        items += [.separator, .command(.quit(appName: "PinShot") { NSApp.terminate(nil) })]
        menuBar = try MenuBarController(configuration: .init(id: "PinShot.StatusItem", accessibilityLabel: "PinShot",
            toolTip: "PinShot", icon: .systemSymbol("pin.fill"), items: items))
        menuBar?.install()
        mainMenu = try MainMenuController(configuration: .init(appName: "PinShot",
            settings: { [weak self] in self?.reopen() },
            about: { [weak self] in self?.perform { self?.settings?.show(.builtIn(.about)) } },
            help: { [weak self] in self?.perform { self?.settings?.show(.support) } },
            sidebar: .init(id: "sidebar", title: appText("Toggle Sidebar"),
                shortcut: .init("s", modifiers: [.command, .control]),
                state: { [weak self] in .init(isEnabled: self?.settings?.window.window?.isKeyWindow == true) },
                action: .perform { [weak self] in self?.settings?.navigation.toggleSidebar() })))
        mainMenu?.install()
    }

    private func reopen() {
        if onboarding?.showIfNeeded() == true { return }
        perform { settings?.show() }
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        lifecycle.handleReopen(hasVisibleWindows: flag)
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        lifecycle.shouldTerminateAfterLastWindowClosed
    }

    public func applicationWillTerminate(_ notification: Notification) {
        if servicesStarted { PinManager.shared.finishEditing() }
        menuBar?.remove()
        mainMenu?.uninstall()
    }
}
