@testable import PinShotApp
import Cocoa
import MacAppCore
import MacAppDiagnosticsSentry
import MacAppSettings

@MainActor
func testDiagnostics() throws {
    let suite = "PinShot.DiagnosticsTests.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let resourceBundle = Bundle(for: AppDelegate.self).resourceURL!
    // SwiftPM's test executable has no app metadata; load the app's resource bundle explicitly.
    let candidates = [resourceBundle.appendingPathComponent("PinShot_PinShotApp.bundle"),
                      Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("PinShot_PinShotApp.bundle")]
    let bundle = candidates.compactMap { Bundle(url: $0) }.first!
    let resource = try Data(contentsOf: bundle.url(forResource: "SentryConfiguration", withExtension: "json")!)
    let configuration = try SentryDiagnosticsConfiguration(resourceData: resource,
        appIdentifier: "com.elixirevo.PinShot", version: "1.2.0", build: "1200")
    expect(configuration.release == "com.elixirevo.PinShot@1.2.0+1200", "Sentry release must track actual app version and build")
    expect(configuration.environment == "production", "The bundled project must use the intended environment")
    do {
        _ = try SentryDiagnosticsConfiguration(resourceData: resource, appIdentifier: "com.example.Other", version: "1", build: "1")
        fatalError("Another app must not use PinShot's Sentry configuration")
    } catch {}

    let diagnostics = AppDiagnostics(configuration: configuration, defaults: defaults)
    expect(diagnostics.settingsPreference === diagnostics.preference, "Settings and onboarding must share the process consent model")
    expect(!diagnostics.preference.selection && !diagnostics.preference.activeEnabled, "New installations must not opt into crash reports")
    try diagnostics.start()
    expect(diagnostics.service?.isRunning == false, "No consent means no SDK initialization")
    diagnostics.preference.select(true)
    try diagnostics.start()
    expect(diagnostics.preference.requiresRestart && diagnostics.service?.isRunning == false, "Selecting consent must not initialize the SDK during this launch")
    CapturePreferences(defaults: defaults).restoreDefaults()
    let nextLaunch = AppDiagnostics(configuration: configuration, defaults: defaults)
    expect(nextLaunch.preference.activeEnabled, "Consent must survive restart and capture-preference reset")
    nextLaunch.preference.select(false)
    expect(nextLaunch.preference.activeEnabled && nextLaunch.preference.requiresRestart, "Withdrawal must clearly require restart")
    let disabledLaunch = AppDiagnostics(configuration: configuration, defaults: defaults)
    try disabledLaunch.start()
    expect(disabledLaunch.service?.isRunning == false, "SDK must remain stopped after restarting with consent withdrawn")
    let unconfigured = AppDiagnostics(configuration: nil, defaults: defaults)
    expect(unconfigured.settingsPreference == nil, "Unconfigured builds must hide the diagnostics control")

    let identity = SettingsIdentity(name: "PinShot", version: "Test")
    let documents = try LegalDocuments(language: "en")
    let flow = try OnboardingCoordinator(identity: identity, documents: documents,
        permissions: PermissionSettingsModel(), diagnostics: diagnostics.preference,
        defaults: defaults, onReady: {}, onQuit: {})
    expect(flow.model.steps.last?.id == "diagnostics", "Configured onboarding must include optional crash-report consent")
    expect(!flow.agreement.allowsAppUse && !defaults.bool(forKey: CrashReportingPreference.defaultKey), "Constructing onboarding must not accept terms or opt into reports")
    expect(documents.privacy.contains("Sentry") && documents.privacy.contains("off by default"), "Bundled policy must disclose optional Sentry reporting")
    let koreanDocuments = try LegalDocuments(language: "ko")
    expect(koreanDocuments.privacy.contains("Sentry"), "Korean policy must describe the same service")
    print("PASS: Sentry resource, release metadata, consent gating, restart, reset preservation, withdrawal and onboarding; no crash events sent")
}
