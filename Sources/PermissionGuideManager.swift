import Cocoa

final class PermissionGuideManager {
    static let shared = PermissionGuideManager()

    private init() {}

    func checkAndGuidePermissionsIfNeeded() {
        let missing = missingPermissions()
        guard missing.isEmpty == false else { return }

        showPermissionGuide(for: missing)
    }

    private func missingPermissions() -> [String] {
        if CGPreflightScreenCaptureAccess() == false {
            return ["Screen Recording"]
        }
        return []
    }

    private func showPermissionGuide(for missing: [String]) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "PinShot Permission Setup"
        alert.informativeText = """
        PinShot needs permissions to work correctly.

        Missing:
        \(missing.map { "- \($0)" }.joined(separator: "\n"))

        Click "Open Settings" and enable permissions for PinShot.
        """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        if missing.contains("Screen Recording") {
            openPrivacyPane(anchor: "Privacy_ScreenCapture")
            _ = CGRequestScreenCaptureAccess()
        }
    }

    private func openPrivacyPane(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
