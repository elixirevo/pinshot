import Cocoa
import ServiceManagement

enum LoginLaunchError: Error {
    case unsupportedOS
}

final class LoginLaunchManager {
    static let shared = LoginLaunchManager()

    private init() {}

    var isSupported: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw LoginLaunchError.unsupportedOS
        }

        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled {
                try service.register()
            }
        } else if service.status == .enabled {
            try service.unregister()
        }
    }
}
