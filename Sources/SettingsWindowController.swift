import Cocoa
import SwiftUI
import Carbon
import MacAppCore
import MacAppSettings

func appText(_ key: String) -> String {
    AppLocalizer.current.string(key, bundle: .module)
}

@MainActor
final class PinShotSettings {
    let navigation = SettingsNavigation()
    let permissions: PermissionSettingsModel
    let shortcuts: ShortcutSettingsModel
    let preferences: FeaturePreferences
    let window: MacAppSettings.SettingsWindowController

    init(identity: SettingsIdentity, permissions: PermissionSettingsModel,
         updates: UpdateSettingsModel, legal: LegalDocuments,
         diagnostics: CrashReportingPreference? = nil,
         reviewOnboarding: @escaping () -> Void, setRegion: @escaping () -> Void,
         preview: Bool = false) throws {
        self.permissions = permissions
        let preferences = FeaturePreferences(preview: preview)
        self.preferences = preferences
        let shortcuts = ShortcutSettingsModel(HotkeyAction.settingsActions.map { action, title in
            SettingsShortcutAction(id: title, title: appText(title),
                read: { HotkeyManager.shared.shortcut(for: action).settingsShortcut },
                validate: { value in
                    guard value != nil else { throw SettingsAdapterError.shortcutRequired }
                }, write: { value in
                    guard let value else { throw SettingsAdapterError.shortcutRequired }
                    try HotkeyManager.shared.updateShortcut(action: action, shortcut: .init(value))
                })
        }, recordingChanged: { active in
            if active { HotkeyManager.shared.beginShortcutRecording() }
            else { HotkeyManager.shared.endShortcutRecording() }
        })
        self.shortcuts = shortcuts
        let reset = try SettingsResetModel(actions: [
            SettingsResetAction(id: "capture", title: appText("Capture Preferences"),
                detail: appText("Restore history saving, the 30-capture limit, save folders and screenshot frame. Existing files are kept; the history limit applies after the next saved capture.")) {
                preferences.restoreCaptureDefaults()
            },
            SettingsResetAction(id: "shortcuts", title: appText("Keyboard Shortcuts"),
                detail: appText("Restore Option+A, Option+1/2/3 and Command+Option+W. If registration fails, keep the previous shortcuts.")) {
                try HotkeyManager.shared.resetAllShortcuts()
                shortcuts.refresh()
            }
        ])
        let support = try SupportSettingsModel(diagnostics: .init(identity: identity), links: [
            try SupportLink(.help, url: URL(string: "https://github.com/elixirevo/pinshot#readme")!),
            try SupportLink(.contact, url: URL(string: "mailto:elixirevo@gmail.com")!),
            try SupportLink(.reportIssue, url: URL(string: "https://github.com/elixirevo/pinshot/issues")!)
        ], showOnboarding: reviewOnboarding)
        let pages = try SettingsPages([
            .builtIn(.general),
            .custom(id: "features", title: appText("Features"), symbol: "display",
                    color: Color(red: 0.30, green: 0.68, blue: 0.94)) {
                FeatureSettings(model: preferences, setRegion: setRegion, preview: preview)
            },
            .builtIn(.shortcuts), .builtIn(.permissions), .builtIn(.updates), .support, .builtIn(.about)
        ])
        let navigation = self.navigation
        navigation.configure(pages)
        let login = preview ? LaunchAtLoginModel(read: { .disabled }, write: { _ in }, openSettings: {}) : LaunchAtLoginModel()
        window = MacAppSettings.SettingsWindowController(title: "PinShot", autosaveName: "PinShot.SharedSettings",
            navigation: navigation, onClose: { shortcuts.stopRecording() }) {
            AppSettingsView(identity: identity, navigation: navigation, shortcuts: shortcuts,
                permissions: permissions, updates: updates, launchAtLogin: login, pages: pages,
                support: support, reset: reset,
                supportContent: { AnyView(LegalDocumentsSection(documents: legal)) },
                shortcutsContent: { AnyView(ShortcutRegistrationStatus()) }) {
                    AppearanceSettings(preview: preview)
                    if let diagnostics {
                        DiagnosticsSettingsSection(preference: diagnostics, explanation: appText("Optional crash reports include app and macOS versions, device details, exceptions and technical call stacks. They are sent to Sentry to diagnose crashes. Screenshots are not attached. Changes apply after restarting PinShot. See the Privacy Policy in Help & Support for retention and international processing."))
                    }
                }
        }
    }

    func show(_ page: SettingsPageID = .builtIn(.general)) {
        preferences.reload()
        shortcuts.refresh()
        window.show(pageID: page)
    }
}

enum SettingsAdapterError: LocalizedError {
    case shortcutRequired
    var errorDescription: String? { appText("Choose a shortcut for this action.") }
}

extension HotkeyAction {
    static let settingsActions: [(HotkeyAction, String)] = [
        (.screenshot, "Take Screenshot"), (.capture, "Capture & Pin"),
        (.saveScreenshot, "Capture & Save Screenshot"), (.setScreenshotRegion, "Set Screenshot Region"),
        (.closeAll, "Close All Pins")
    ]
}

extension HotkeyShortcut {
    var settingsShortcut: SettingsShortcut {
        var flags: NSEvent.ModifierFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        let label = HotkeyShortcut(keyCode: keyCode, modifiers: 0).displayString
        return .init(keyCode: UInt16(keyCode), modifiers: flags, keyLabel: label)
    }

    init(_ shortcut: SettingsShortcut) {
        var mask: UInt32 = 0
        if shortcut.modifierFlags.contains(.command) { mask |= UInt32(cmdKey) }
        if shortcut.modifierFlags.contains(.option) { mask |= UInt32(optionKey) }
        if shortcut.modifierFlags.contains(.control) { mask |= UInt32(controlKey) }
        if shortcut.modifierFlags.contains(.shift) { mask |= UInt32(shiftKey) }
        self.init(keyCode: UInt32(shortcut.keyCode), modifiers: mask)
    }
}

private struct ShortcutRegistrationStatus: View {
    @ObservedObject private var hotkeys = HotkeyManager.shared
    var body: some View {
        ForEach(HotkeyAction.settingsActions, id: \.1) { action, title in
            if let error = hotkeys.registrationErrors[action] {
                SettingsSection(appText(title)) { Text(error).foregroundColor(.secondary) }
            }
        }
    }
}

@MainActor
final class FeaturePreferences: ObservableObject {
    let store: CapturePreferences
    @Published var revision = 0
    init(preview: Bool = false) {
        store = preview ? CapturePreferences(defaults: UserDefaults(suiteName: "PinShot.SettingsPreview")!) : .shared
    }
    func reload() { revision += 1 }
    func restoreCaptureDefaults() { store.restoreDefaults(); reload() }
}

private struct FeatureSettings: View {
    @ObservedObject var model: FeaturePreferences
    let setRegion: () -> Void
    let preview: Bool
    @State private var error: String?
    @State private var confirmHistoryClear = false
    @State private var historyError: String?
    @State private var historyCleared = false

    var body: some View {
        SettingsSection(appText("Capture & Pin"), footer: appText("When a new capture exceeds the limit, the oldest history entries and their PNG files are deleted.")) {
            SettingsToggle(appText("Save Capture & Pin history automatically"),
                detail: appText("Turning history off keeps existing captures."),
                isOn: Binding(get: { model.store.pinHistoryEnabled }, set: { model.store.pinHistoryEnabled = $0; model.reload() }))
            SettingsPicker(appText("History Limit"), selection: Binding(get: { model.store.pinHistoryRetention }, set: { model.store.pinHistoryRetention = $0; model.reload() })) {
                ForEach(PinHistoryRetention.allCases, id: \.rawValue) { value in
                    Text(value == .unlimited ? appText("Never Delete") : String(format: appText("%d captures"), value.rawValue)).tag(value)
                }
            }
            SettingsRow(appText("Screenshot History")) {
                HStack {
                    Button(appText("Open History…")) { if !preview { PinHistoryWindowController.shared.showHistory() } }
                    Button(appText("Clear History…"), role: .destructive) { confirmHistoryClear = true }
                        .disabled(preview)
                }
            }
            if let historyError {
                Text(appText("Could not clear all screenshot history. Please try again.") + "\n" + historyError)
                    .foregroundColor(.red)
            } else if historyCleared {
                Text(appText("Screenshot history cleared.")).foregroundColor(.secondary)
            }
        }
        .alert(appText("Clear screenshot history?"), isPresented: $confirmHistoryClear) {
            Button(appText("Cancel"), role: .cancel) {}
            Button(appText("Clear History"), role: .destructive) { clearHistory() }
        } message: {
            Text(appText("All screenshot history and its automatically saved PNG files will be permanently deleted, including files in previous save folders. Manually saved copies and currently open pins will remain. This cannot be undone."))
        }
        .onReceive(NotificationCenter.default.publisher(for: .pinHistoryChanged)) { _ in
            historyCleared = false
        }
        SettingsSection(appText("Saved Screenshot Region")) {
            SettingsRow(appText("Select a region and save a screenshot immediately.")) {
                Button(appText("Set Region…"), action: setRegion)
            }
        }
        SettingsSection(appText("Save Locations"), footer: appText("Changing folders affects new saves. Existing files are not moved.")) {
            ForEach(CaptureDestination.allCases, id: \.rawValue) { destination in
                SettingsRow(appText(destination.title), detail: model.store.directory(for: destination).path) {
                    HStack {
                        Button(appText("Show")) { showFolder(destination) }
                        Button(appText("Choose…")) { chooseFolder(destination) }
                    }
                }
            }
            if let error { Text(error).foregroundColor(.red) }
        }
        SettingsSection(appText("Screenshot Frame")) {
            ScreenshotFrameSettings(preferences: model.store, revision: model.revision).frame(height: 390)
        }
    }

    private func clearHistory() {
        guard !preview else { return }
        historyError = nil
        historyCleared = false
        do {
            try PinHistoryStore.shared.clearHistory()
            historyCleared = true
        } catch { historyError = error.localizedDescription }
    }

    private func showFolder(_ destination: CaptureDestination) {
        do {
            let url = model.store.directory(for: destination)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            if !NSWorkspace.shared.open(url) { throw CocoaError(.fileReadUnknown) }
        } catch { self.error = error.localizedDescription }
    }

    private func chooseFolder(_ destination: CaptureDestination) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.store.directory(for: destination)
        if panel.runModal() == .OK, let url = panel.url {
            model.store.setDirectory(url, for: destination)
            model.reload()
        }
    }
}

// The frame editor is also used inside the capture overlay and remains app-specific.
private struct ScreenshotFrameSettings: NSViewRepresentable {
    let preferences: CapturePreferences
    let revision: Int
    func makeNSView(context: Context) -> ScreenshotAppearanceView { ScreenshotAppearanceView(preferences: preferences) }
    func updateNSView(_ view: ScreenshotAppearanceView, context: Context) { view.reload() }
}

struct AppearanceSettings: View {
    let preview: Bool
    @AppStorage("PinShot.appearance") private var appearance = "system"
    var body: some View {
        SettingsSection(appText("Appearance")) {
            SettingsPicker(appText("Appearance"), selection: $appearance) {
                Text(appText("System")).tag("system")
                Text(appText("Light")).tag("light")
                Text(appText("Dark")).tag("dark")
            }.onChange(of: appearance) { _ in if !preview { Self.apply() } }
        }
    }
    static func apply() {
        switch UserDefaults.standard.string(forKey: "PinShot.appearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}
