import Cocoa
import SwiftUI
import MacAppCore
import MacAppSettings
import MacAppOnboarding

@MainActor
final class OnboardingCoordinator {
    static let completionKey = "PinShot.onboarding.completedVersion"
    static let acceptanceKey = "PinShot.terms.acceptance"
    let agreement: TermsAgreementModel
    let model: OnboardingModel
    let window: OnboardingWindowController
    let termsWindow: TermsAgreementWindowController

    init(identity: SettingsIdentity, documents: LegalDocuments, permissions: PermissionSettingsModel,
         diagnostics: CrashReportingPreference? = nil,
         defaults: UserDefaults = .standard, onReady: @escaping () -> Void,
         onQuit: @escaping @MainActor () -> Void = { NSApp.terminate(nil) }) throws {
        agreement = TermsAgreementModel(document: try documents.termsDocument(),
            store: TermsAcceptanceStore(defaults: defaults, key: Self.acceptanceKey))
        func illustration(_ name: String, _ description: String) -> OnboardingIllustration? {
            guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
                  let image = NSImage(contentsOf: url) else { return nil }
            return OnboardingIllustration(Image(nsImage: image), accessibilityLabel: appText(description))
        }
        var steps: [OnboardingStep] = [
            .welcome(message: appText("Capture, annotate and keep what matters in view. PinShot lives in the menu bar; click the pin icon to get started.")),
            .guide(id: "capture", title: appText("Capture and annotate"),
                message: appText("Press Option+A, then drag a region or click a window. Add arrows, text or mosaic. Return copies, Command+S saves, and the pin button keeps the image on top. These are the default shortcuts; customize them in Settings."),
                illustration: illustration("onboarding-editor", "PinShot’s screenshot editor with a selected region and annotation toolbar")),
            .guide(id: "pins", title: appText("Keep references close"),
                message: appText("Option+1 captures a floating pin. Drag it beside your work, draw on it, or reopen a capture from History. Option+2 saves a remembered region; Option+3 selects a new one."),
                illustration: illustration("onboarding-pins", "A PinShot floating screenshot with copy, save, draw and history controls")),
            .custom(id: "privacy", title: appText("Privacy")) { OnboardingPrivacyView(documents: documents) },
            .terms(agreement),
            .permissions(permissions)
        ]
        if let diagnostics {
            steps.append(.diagnostics(diagnostics, explanation: appText("Optional crash reports include app and macOS versions, device details, exceptions and technical call stacks. They are sent to Sentry to diagnose crashes. Screenshots are not attached. Changes apply after restarting PinShot. See the Privacy Policy in Help & Support for retention and international processing.")))
        }
        model = try OnboardingModel(steps: steps, version: 1, store: OnboardingStore(defaults: defaults, key: Self.completionKey))
        window = OnboardingWindowController(identity: identity, model: model,
            autosaveName: "PinShot.Onboarding", onFinish: onReady, onDismiss: onReady, onQuit: onQuit)
        termsWindow = TermsAgreementWindowController(identity: identity, model: agreement,
            autosaveName: "PinShot.Terms", onAccepted: onReady, onQuit: onQuit)
    }

    @discardableResult func showIfNeeded() -> Bool {
        if model.completedVersion >= model.version, !agreement.allowsAppUse {
            return termsWindow.showIfNeeded()
        }
        return window.showIfNeeded()
    }

    func review() {
        do { try window.showForReview() }
        catch { NSApp.presentError(error) }
    }
}
