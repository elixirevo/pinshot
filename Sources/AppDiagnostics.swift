import Foundation
import MacAppCore
import MacAppDiagnosticsSentry

/// Owns the shared crash-only SDK for this process. Consent changes apply on the next launch.
@MainActor
final class AppDiagnostics {
    let preference: CrashReportingPreference
    let service: SentryDiagnostics?

    convenience init() throws {
        try self.init(configuration: SentryDiagnosticsConfiguration.bundled(in: .module, appBundle: .main))
    }

    init(configuration: SentryDiagnosticsConfiguration?, defaults: UserDefaults = .standard) {
        preference = CrashReportingPreference(defaults: defaults)
        service = configuration.map { SentryDiagnostics(configuration: $0) }
    }

    var settingsPreference: CrashReportingPreference? { service == nil ? nil : preference }

    func start() throws { try service?.startIfConsented(preference) }
}
