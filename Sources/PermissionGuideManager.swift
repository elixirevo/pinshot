import Cocoa
import ApplicationServices

final class PermissionGuideManager {
    static let shared = PermissionGuideManager()

    private var isShowingGuide = false
    private var isShowingSyncAlert = false

    private init() {}

    func checkAndGuidePermissionsIfNeeded(forceImmediate: Bool = false) {
        runPermissionCheck()
    }

    func ensureScreenRecordingReady(
        timeout: TimeInterval = 20.0,
        interval: TimeInterval = 0.35,
        completion: @escaping (Bool) -> Void
    ) {
        let deadline = Date().addingTimeInterval(max(timeout, 0))

        func poll() {
            if isScreenRecordingReadyNow() {
                completion(true)
                return
            }
            if Date() >= deadline {
                completion(false)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + max(interval, 0.1)) {
                poll()
            }
        }

        DispatchQueue.main.async {
            poll()
        }
    }

    func hasScreenRecordingAuthorization() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func handleAuthorizedButUnavailableScreenCapture() {
        guard hasScreenRecordingAuthorization() else {
            checkAndGuidePermissionsIfNeeded(forceImmediate: true)
            return
        }
        showScreenRecordingSyncAlert()
    }

    private func runPermissionCheck() {
        let missing = missingPermissions()
        guard missing.isEmpty == false else { return }
        showPermissionGuide(for: missing)
    }

    private func missingPermissions() -> [String] {
        var missing: [String] = []
        if hasScreenRecordingAuthorization() == false {
            missing.append("Screen Recording")
        }
        if AXIsProcessTrusted() == false {
            missing.append("Accessibility")
        }
        return missing
    }

    private func isScreenRecordingReadyNow() -> Bool {
        guard CGPreflightScreenCaptureAccess() else { return false }
        return canCaptureAnyDisplayImage()
    }

    private func canCaptureAnyDisplayImage() -> Bool {
        if let image = CGDisplayCreateImage(CGMainDisplayID()) {
            return image.width > 0 && image.height > 0
        }

        let maxDisplayCount: UInt32 = 16
        var activeDisplayCount: UInt32 = 0
        var activeDisplays = Array(repeating: CGDirectDisplayID(), count: Int(maxDisplayCount))
        let status = CGGetActiveDisplayList(maxDisplayCount, &activeDisplays, &activeDisplayCount)
        guard status == .success else { return false }

        for index in 0..<Int(activeDisplayCount) {
            if CGDisplayCreateImage(activeDisplays[index]) != nil {
                return true
            }
        }
        return false
    }

    private func showScreenRecordingSyncAlert() {
        guard isShowingSyncAlert == false else { return }
        isShowingSyncAlert = true

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Applying Screen Recording Permission"
        alert.informativeText = """
        Screen Recording permission is already granted, but macOS has not fully applied it to this process yet.

        Restarting PinShot once usually resolves this immediately.
        """
        alert.addButton(withTitle: "Restart PinShot")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        isShowingSyncAlert = false
        guard response == .alertFirstButtonReturn else { return }
        restartApplication()
    }

    private func restartApplication() {
        let appURL = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            NSApp.terminate(nil)
        }
    }

    private func showPermissionGuide(for missing: [String]) {
        guard isShowingGuide == false else { return }
        isShowingGuide = true

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
        isShowingGuide = false
        guard response == .alertFirstButtonReturn else { return }

        if missing.contains("Screen Recording") {
            openPrivacyPane(anchor: "Privacy_ScreenCapture")
            _ = CGRequestScreenCaptureAccess()
        }
        if missing.contains("Accessibility") {
            openPrivacyPane(anchor: "Privacy_Accessibility")
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }

    private func openPrivacyPane(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
