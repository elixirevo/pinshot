import Cocoa
import SwiftUI
import MacAppCore
import MacAppSettings
import MacAppOnboarding

struct LegalDocuments {
    static let version = "2026-10-05"
    let language: String
    let terms: String
    let privacy: String

    init(language: String = AppLocalizer.current.languageCode, bundle: Bundle = .module) throws {
        self.language = language
        func read(_ name: String) throws -> String {
            guard let url = bundle.url(forResource: name, withExtension: "txt", subdirectory: nil, localization: language) else {
                throw CocoaError(.fileNoSuchFile)
            }
            let text = try String(contentsOf: url, encoding: .utf8)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !text.contains("{{") else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return text
        }
        terms = try read("terms")
        privacy = try read("privacy")
    }

    func termsDocument() throws -> TermsDocument {
        try TermsDocument(id: "pinshot.terms", version: Self.version, language: language,
            changes: appText("These terms describe PinShot’s free local screenshot tools, your content rights, updates and support. Screenshot files stay on your Mac. Read the separate Privacy Policy for update, support and optional crash-report data."),
            fullText: terms)
    }
}

struct LegalDocumentsSection: View {
    let documents: LegalDocuments
    @State private var selection: LegalSelection?
    var body: some View {
        SettingsSection(appText("Legal Documents")) {
            SettingsRow(appText("Terms of Use")) {
                Button(appText("Read…")) { selection = .terms }
            }
            SettingsRow(appText("Privacy Policy")) {
                Button(appText("Read…")) { selection = .privacy }
            }
        }.sheet(item: $selection) { item in
            LegalDocumentView(title: appText(item == .terms ? "Terms of Use" : "Privacy Policy"),
                              text: item == .terms ? documents.terms : documents.privacy)
        }
    }
}

private enum LegalSelection: String, Identifiable {
    case terms, privacy
    var id: String { rawValue }
}

struct LegalDocumentView: View {
    let title: String
    let text: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.title2.bold())
            ScrollView { Text(text).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                Button(appText("Copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
                Spacer()
                Button(appText("Done")) { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 550, height: 480)
    }
}

struct OnboardingPrivacyView: View {
    let documents: LegalDocuments
    @State private var showing = false
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield").font(.system(size: 48)).foregroundStyle(.secondary)
            Text(appText("Your screenshots stay on your Mac")).font(.title2.bold())
            Text(appText("PinShot has no account, cloud screenshot upload or advertising. Optional crash reports go to Sentry only when you enable them and restart the app. Update checks contact GitHub. Support messages are sent only when you submit them."))
                .multilineTextAlignment(.center)
            Button(appText("Read Privacy Policy…")) { showing = true }
        }.padding(20).sheet(isPresented: $showing) {
            LegalDocumentView(title: appText("Privacy Policy"), text: documents.privacy)
        }
    }
}
