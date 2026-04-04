import Cocoa
import Carbon
import ApplicationServices

final class ScreenshotMacroManager {
    static let shared = ScreenshotMacroManager()

    private let defaults = UserDefaults.standard
    private let afterShortcutDefaultsKey = "macro.afterShortcut"
    private let legacyPreShortcutDefaultsKey = "macro.preShortcut"
    private let postDelayDefaultsKey = "macro.postDelaySeconds"

    private var afterShortcutText: String
    private var postDelaySeconds: TimeInterval
    private var currentLoop = 0
    private var isRunning = false
    private var runID = UUID()
    private var pendingWorkItem: DispatchWorkItem?
    private let selfBundleID = Bundle.main.bundleIdentifier ?? "com.elixirevo.PinShot"
    private let maxRandomAdditionalDelaySeconds: TimeInterval = 2.0

    private init() {
        afterShortcutText =
            defaults.string(forKey: afterShortcutDefaultsKey) ??
            defaults.string(forKey: legacyPreShortcutDefaultsKey) ??
            ""
        let storedDelay = defaults.object(forKey: postDelayDefaultsKey) as? Double ?? 1.0
        postDelaySeconds = Self.clampDelay(storedDelay)

        MacroControlWindowManager.shared.configure(
            afterShortcutText: afterShortcutText,
            postDelaySeconds: postDelaySeconds
        )
        MacroControlWindowManager.shared.onPlayRequested = { [weak self] afterShortcut, postDelay in
            self?.startPlayback(afterShortcutText: afterShortcut, postDelaySeconds: postDelay)
        }
        MacroControlWindowManager.shared.onStopRequested = { [weak self] in
            self?.stopPlayback(hideWindow: false)
        }
        MacroControlWindowManager.shared.updatePlaybackState(isRunning: false, iteration: currentLoop)
    }

    func showControlWindow(below region: NSRect) {
        MacroControlWindowManager.shared.configure(
            afterShortcutText: afterShortcutText,
            postDelaySeconds: postDelaySeconds
        )
        MacroControlWindowManager.shared.updatePlaybackState(isRunning: isRunning, iteration: currentLoop)
        MacroControlWindowManager.shared.show(below: region)
    }

    func hideControlWindow() {
        MacroControlWindowManager.shared.hide()
    }

    func handleOverlayDismissedByUser() {
        if Thread.isMainThread {
            stopPlayback(hideWindow: true)
        } else {
            DispatchQueue.main.async {
                self.stopPlayback(hideWindow: true)
            }
        }
    }

    private func startPlayback(afterShortcutText: String, postDelaySeconds: TimeInterval) {
        guard let validatedDelay = validateDelay(postDelaySeconds) else {
            showSettingsError("Post delay must be between 0 and 3600 seconds.")
            return
        }

        let trimmed = afterShortcutText.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedAfterShortcut: HotkeyShortcut?
        if trimmed.isEmpty {
            parsedAfterShortcut = nil
        } else {
            do {
                let parsed = try HotkeyShortcut.parse(trimmed)
                if parsed == HotkeyManager.shared.shortcut(for: .saveScreenshot) {
                    showSettingsError("After-screenshot shortcut cannot be the same as the screenshot shortcut.")
                    return
                }
                parsedAfterShortcut = parsed
            } catch {
                showSettingsError("Invalid after-screenshot shortcut. Example: option+right, left, a")
                return
            }
        }

        self.afterShortcutText = trimmed
        self.postDelaySeconds = validatedDelay
        defaults.set(trimmed, forKey: afterShortcutDefaultsKey)
        defaults.set(validatedDelay, forKey: postDelayDefaultsKey)

        guard !isRunning else { return }
        guard ScreenshotSaveManager.shared.savedRegionScreenRect() != nil else {
            showSettingsError("Set screenshot region first with Option + 3.")
            return
        }

        isRunning = true
        currentLoop = 0
        runID = UUID()
        MacroControlWindowManager.shared.updatePlaybackState(isRunning: true, iteration: currentLoop)
        runNextLoop(afterShortcut: parsedAfterShortcut, runID: runID)
    }

    private func runNextLoop(afterShortcut: HotkeyShortcut?, runID: UUID) {
        guard isRunning, self.runID == runID else { return }

        ScreenshotSaveManager.shared.captureUsingSavedRegion(showPersistentIndicator: true) { [weak self] success, _ in
            guard let self else { return }
            guard self.isRunning, self.runID == runID else { return }

            guard success else {
                self.stopPlayback(hideWindow: false)
                self.showSettingsError("Could not capture saved region. Please set region again with Option + 3.")
                return
            }

            if let shortcut = afterShortcut {
                self.postShortcut(shortcut)
            }

            self.currentLoop += 1
            MacroControlWindowManager.shared.updatePlaybackState(isRunning: true, iteration: self.currentLoop)

            let workItem = DispatchWorkItem { [weak self] in
                self?.runNextLoop(afterShortcut: afterShortcut, runID: runID)
            }
            self.pendingWorkItem?.cancel()
            self.pendingWorkItem = workItem
            let randomAdditionalDelay = Double.random(in: 0...self.maxRandomAdditionalDelaySeconds)
            let actualDelay = self.postDelaySeconds + randomAdditionalDelay
            DispatchQueue.main.asyncAfter(deadline: .now() + actualDelay, execute: workItem)
        }
    }

    private func stopPlayback(hideWindow: Bool) {
        pendingWorkItem?.cancel()
        pendingWorkItem = nil
        isRunning = false
        runID = UUID()
        MacroControlWindowManager.shared.updatePlaybackState(isRunning: false, iteration: currentLoop)
        if hideWindow {
            MacroControlWindowManager.shared.hide()
        }
    }

    private static func clampDelay(_ value: TimeInterval) -> TimeInterval {
        min(max(value, 0), 3600)
    }

    private func validateDelay(_ value: TimeInterval) -> TimeInterval? {
        guard value.isFinite else { return nil }
        let clamped = Self.clampDelay(value)
        guard abs(clamped - value) < 0.000_001 else { return nil }
        return clamped
    }

    private func postShortcut(_ shortcut: HotkeyShortcut) {
        let targetPIDs = preferredInjectionTargets()
        for pid in targetPIDs {
            _ = postShortcutToProcess(shortcut, pid: pid)
        }
        if !targetPIDs.isEmpty {
            return
        }

        _ = postShortcutToEventTap(shortcut, tap: .cghidEventTap)
    }

    private func cgEventFlags(from modifiers: UInt32) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers & UInt32(cmdKey) != 0 { flags.insert(.maskCommand) }
        if modifiers & UInt32(optionKey) != 0 { flags.insert(.maskAlternate) }
        if modifiers & UInt32(controlKey) != 0 { flags.insert(.maskControl) }
        if modifiers & UInt32(shiftKey) != 0 { flags.insert(.maskShift) }
        return flags
    }

    private func postShortcutToEventTap(_ shortcut: HotkeyShortcut, tap: CGEventTapLocation) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let flags = cgEventFlags(from: shortcut.modifiers)
        let keyCode = CGKeyCode(shortcut.keyCode)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: tap)
        keyUp.post(tap: tap)
        return true
    }

    private func postShortcutToProcess(_ shortcut: HotkeyShortcut, pid: pid_t) -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
        let flags = cgEventFlags(from: shortcut.modifiers)
        let keyCode = CGKeyCode(shortcut.keyCode)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
        return true
    }

    private func preferredInjectionTargets() -> [pid_t] {
        var pids: [pid_t] = []
        let selfPID = pid_t(ProcessInfo.processInfo.processIdentifier)

        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.processIdentifier != selfPID,
           (frontmost.bundleIdentifier ?? "") != selfBundleID {
            pids.append(frontmost.processIdentifier)
        }

        let remoteApps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.processIdentifier != selfPID &&
                isLikelyRemoteDesktopClient(app)
            }
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive && !rhs.isActive
                }
                return lhs.processIdentifier < rhs.processIdentifier
            }
        for app in remoteApps {
            pids.append(app.processIdentifier)
        }

        var seen = Set<pid_t>()
        return pids.filter { seen.insert($0).inserted }
    }

    private func isLikelyRemoteDesktopClient(_ app: NSRunningApplication) -> Bool {
        let bundleID = app.bundleIdentifier?.lowercased() ?? ""
        let appName = app.localizedName?.lowercased() ?? ""
        let combined = bundleID + " " + appName

        let tokens = [
            "rustdesk",
            "teamviewer",
            "anydesk",
            "parsec",
            "remote desktop",
            "remotedesktop",
            "splashtop",
            "vnc"
        ]
        return tokens.contains(where: { combined.contains($0) })
    }

    private func showSettingsError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Macro Configuration Error"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
