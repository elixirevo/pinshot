@testable import PinShotApp
import Cocoa
import MacAppCore
import MacAppSettings
import MacAppOnboarding

@MainActor
func finishAsync(_ work: @escaping @MainActor () async -> Void) {
    var done = false
    Task { await work(); done = true }
    let deadline = Date().addingTimeInterval(5)
    while !done && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    expect(done, "Async settings operation must finish")
}

@MainActor
func testPermissionSettings() {
    var allowed: Set<String> = []
    var requests: [String] = []
    var opened: [String] = []
    var confirmation = NSApplication.ModalResponse.alertSecondButtonReturn
    let permissions = PermissionSettingsModel(["screenRecording", "accessibility"].map { id in
        SettingsPermission(id: id, title: id, detail: "Test permission",
            readStatus: { allowed.contains(id) ? .granted : .notGranted },
            request: { requests.append(id) }, openSystemSettings: { opened.append(id) })
    }, presentRequest: { _ in confirmation })
    finishAsync { await permissions.refresh() }
    expect(requests.isEmpty && opened.isEmpty, "Status queries must not request OS access")
    finishAsync { await permissions.requestAccess(id: "screenRecording") }
    expect(requests.isEmpty, "Declining shared permission guidance must not call the OS")
    confirmation = .alertFirstButtonReturn
    finishAsync { await permissions.requestAccess(id: "screenRecording") }
    expect(requests == ["screenRecording"] && permissions.statuses["screenRecording"] == .notGranted,
           "Only the selected permission is requested; successful request does not imply approval")
    allowed.insert("screenRecording")
    finishAsync { await permissions.refresh() }
    expect(permissions.statuses["screenRecording"] == .granted && permissions.statuses["accessibility"] == .notGranted,
           "Shared model must reflect independent external grants")
    permissions.openSystemSettings(id: "screenRecording")
    expect(opened == ["screenRecording"], "Settings navigation must remain scoped")
    allowed.removeAll()
    finishAsync { await permissions.refresh() }
    expect(permissions.statuses["screenRecording"] == .notGranted, "Permission revocation must refresh")
    print("PASS: shared permission reads, confirmation, denied requests, scoped settings, grants and revocation")
}

@MainActor
func testEssentialsIntegration() throws {
    let suite = "PinShot.EssentialsTests.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let en = try LegalDocuments(language: "en")
    let ko = try LegalDocuments(language: "ko")
    expect(en.terms.contains("13. Disputes") && ko.terms.contains("13. 분쟁"), "Both complete terms translations must be bundled")
    expect(en.privacy.contains("10. Children") && ko.privacy.contains("10. 아동"), "Both complete privacy translations must be bundled")
    let identity = SettingsIdentity(name: "PinShot", version: "Test")
    var started = 0
    var quit = 0
    let flow = try OnboardingCoordinator(identity: identity, documents: en, permissions: PermissionSettingsModel(),
        defaults: defaults, onReady: { started += 1 }, onQuit: { quit += 1 })
    expect(!flow.agreement.allowsAppUse && started == 0, "First-run construction cannot start app services")
    expect(flow.showIfNeeded(), "First run must present onboarding")
    expect(!flow.window.window!.styleMask.contains(.resizable), "Onboarding keeps the shared fixed size")
    flow.window.window!.performClose(nil)
    expect(quit == 1 && started == 0 && defaults.object(forKey: OnboardingCoordinator.completionKey) == nil,
           "Closing before acceptance requests quit without completion or services")
    expect(!flow.agreement.accept(), "Checkbox is required before explicit agreement")
    flow.agreement.isAcknowledged = true
    expect(flow.agreement.accept() && flow.agreement.allowsAppUse, "Explicit agreement must persist before app use")
    let receipt = defaults.data(forKey: OnboardingCoordinator.acceptanceKey)
    let preferences = CapturePreferences(defaults: defaults)
    preferences.pinHistoryRetention = .ten
    preferences.restoreDefaults()
    expect(preferences.pinHistoryRetention == .thirty && defaults.data(forKey: OnboardingCoordinator.acceptanceKey) == receipt,
           "Capture reset restores its scope while preserving acceptance")
    let koreanAgreement = TermsAgreementModel(document: try ko.termsDocument(), store: .init(defaults: defaults, key: OnboardingCoordinator.acceptanceKey))
    expect(koreanAgreement.allowsAppUse, "Changing display language alone must not require renewed agreement")
    let changed = try TermsDocument(id: "pinshot.terms", version: "next", language: "en", changes: "Changed", fullText: en.terms)
    let changedAgreement = TermsAgreementModel(document: changed, store: .init(defaults: defaults, key: OnboardingCoordinator.acceptanceKey))
    expect(!changedAgreement.allowsAppUse, "Changed terms must gate app use")
    let review = try flow.model.makeReviewModel()
    expect(review.currentIndex == 0 && review.shouldPresent && defaults.data(forKey: OnboardingCoordinator.acceptanceKey) == receipt,
           "Review starts at the beginning without clearing agreement")
    defaults.set(Data("broken".utf8), forKey: OnboardingCoordinator.acceptanceKey)
    koreanAgreement.reload()
    expect(!koreanAgreement.allowsAppUse && koreanAgreement.hasReadError, "Corrupt receipts must fail closed")
    let shortcut = try HotkeyShortcut.parse("command+option+shift+a")
    expect(HotkeyShortcut(shortcut.settingsShortcut) == shortcut, "Shortcut adapters preserve physical key and all modifiers")
    print("PASS: bundled legal translations, first-run gate, explicit acceptance, reset scope, language, version changes, review and corrupt receipts")
}

@MainActor
func previewPermissionSettings() {
    let documents = try! LegalDocuments()
    let permissions = PermissionSettingsModel([
        SettingsPermission(id: "screenRecording", title: appText("Screen Recording"), detail: appText("Capture screenshots and pin images from your screen. Images are processed on your Mac."), readStatus: { .granted }),
        SettingsPermission(id: "accessibility", title: appText("Accessibility"), detail: appText("Optional: run macro keyboard actions and use Escape to dismiss overlays while another app is active."), readStatus: { .notGranted })
    ])
    let suite = "PinShot.OnboardingPreview.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let identity = SettingsIdentity(name: "PinShot", version: "1.2.0", build: "1200", icon: NSApp.applicationIconImage)
    let diagnostics = CrashReportingPreference(activeEnabled: false, save: { _ in })
    let onboarding = try! OnboardingCoordinator(identity: identity, documents: documents, permissions: permissions,
        diagnostics: diagnostics, defaults: defaults, onReady: {}, onQuit: { NSApp.stop(nil) })
    let controller = try! PinShotSettings(identity: identity, permissions: permissions,
        updates: UpdateSettingsModel(unavailableReason: "Preview — no update requests"), legal: documents,
        diagnostics: diagnostics,
        reviewOnboarding: { onboarding.review() }, setRegion: {}, preview: true)
    NSApp.setActivationPolicy(.regular)
    let previewAppearance = Bundle.main.object(forInfoDictionaryKey: "PinShotPreviewAppearance") as? String
    if CommandLine.arguments.contains("--dark") || previewAppearance == "dark" { NSApp.appearance = NSAppearance(named: .darkAqua) }
    if CommandLine.arguments.contains("--light") || previewAppearance == "light" { NSApp.appearance = NSAppearance(named: .aqua) }
    if CommandLine.arguments.contains("--preview-onboarding") || Bundle.main.object(forInfoDictionaryKey: "PinShotPreviewOnboarding") as? Bool == true { onboarding.showIfNeeded() }
    else {
        controller.show(.builtIn(.permissions))
        if CommandLine.arguments.contains("--compact") || Bundle.main.object(forInfoDictionaryKey: "PinShotPreviewCompact") as? Bool == true { controller.window.window?.setContentSize(NSSize(width: 740, height: 500)) }
    }
    NSApp.run()
    withExtendedLifetime((controller, onboarding)) {}
}
