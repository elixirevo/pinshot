import Cocoa

private final class TestPermissions: PermissionManaging {
    var allowed: Set<AppPermission> = []
    var requests: [AppPermission] = []
    var openedSettings: [AppPermission] = []
    var allowOnRequest = false

    func isAuthorized(for permission: AppPermission) -> Bool { allowed.contains(permission) }
    func request(_ permission: AppPermission) {
        requests.append(permission)
        if allowOnRequest { allowed.insert(permission) }
    }
    func openSettings(for permission: AppPermission) { openedSettings.append(permission) }
}

private func permissionView<T: NSView>(_ type: T.Type, in view: NSView, id: String? = nil) -> T? {
    if let result = view as? T, id == nil || result.identifier?.rawValue == id { return result }
    return view.subviews.lazy.compactMap { permissionView(type, in: $0, id: id) }.first
}

func testPermissionSettings() {
    let permissions = TestPermissions()
    let controller = SettingsWindowController(permissions: permissions)
    controller.showSettings()
    defer { controller.close() }
    let window = controller.window!
    let content = window.contentView!
    let tabs = permissionView(NSTabView.self, in: content)!
    tabs.selectTabViewItem(withIdentifier: "Permissions")
    let pane = tabs.selectedTabViewItem!.view!
    func status(_ permission: AppPermission) -> String {
        permissionView(NSTextField.self, in: pane, id: "permission.\(permission.rawValue).status")!.stringValue
    }
    func button(_ permission: AppPermission) -> NSButton {
        permissionView(NSButton.self, in: pane, id: "permission.\(permission.rawValue).action")!
    }
    let summary = permissionView(NSTextField.self, in: pane, id: "permission.summary")!
    let refresh = permissionView(NSButton.self, in: pane, id: "permission.refresh")!
    expect(permissions.requests.isEmpty && permissions.openedSettings.isEmpty,
           "Opening Settings must read permission status without prompting or opening System Settings")
    expect(AppPermission.allCases.allSatisfy { status($0) == "Not Allowed" } && summary.stringValue == "0 of 2 permissions allowed",
           "Missing permissions must be displayed individually and in the summary")
    button(.screenRecording).performClick(nil)
    expect(permissions.requests == [.screenRecording] && status(.screenRecording) == "Not Allowed",
           "Requesting screen access must not request other permissions or show an unapproved request as granted")

    // macOS changes outside PinShot must appear without recreating the window.
    permissions.allowed.insert(.screenRecording)
    controller.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
    expect(status(.screenRecording) == "Allowed" && status(.accessibility) == "Not Allowed" &&
           button(.screenRecording).title == "Open Settings…" && summary.stringValue == "1 of 2 permissions allowed",
           "Returning from System Settings must refresh only the changed permission and its action")
    button(.screenRecording).performClick(nil)
    expect(permissions.openedSettings == [.screenRecording] && permissions.requests == [.screenRecording],
           "An authorized permission must open its own settings instead of requesting access again")
    permissions.allowOnRequest = true
    button(.accessibility).performClick(nil)
    expect(permissions.requests == [.screenRecording, .accessibility] && status(.accessibility) == "Allowed" &&
           summary.stringValue == "2 of 2 permissions allowed",
           "Accessibility requests must refresh from the actual authorization result")
    permissions.allowed.remove(.screenRecording)
    refresh.performClick(nil)
    expect(status(.screenRecording) == "Not Allowed" && button(.screenRecording).title == "Request Access…",
           "Manual refresh must detect revoked permissions and restore the request button")
    permissions.allowed.remove(.accessibility)
    controller.close()
    controller.showSettings()
    expect(status(.accessibility) == "Not Allowed" && summary.stringValue == "0 of 2 permissions allowed",
           "Reopening Settings must discard stale authorization status")
    print("PASS: permission status, prompt-free checks, scoped requests, denied requests, grants, revocation, refresh, settings reopen")
}

// Simulated permissions keep UI verification from prompting for or changing real macOS access.
func previewPermissionSettings() {
    let permissions = TestPermissions()
    permissions.allowOnRequest = true
    let controller = SettingsWindowController(permissions: permissions)
    NSApp.setActivationPolicy(.regular)
    controller.showSettings()
    let tabs = permissionView(NSTabView.self, in: controller.window!.contentView!)!
    tabs.selectTabViewItem(withIdentifier: "Permissions")
    NSApp.run()
    withExtendedLifetime(controller) {}
}
