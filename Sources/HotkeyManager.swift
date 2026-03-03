import Cocoa
import Carbon

enum HotkeyAction {
    case capture
    case closeAll
}

enum HotkeyError: LocalizedError {
    case invalidFormat
    case unknownKey
    case missingModifier
    case duplicateShortcut
    case registerFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Use format like command+option+1 or option+w."
        case .unknownKey:
            return "Unsupported key. Use A-Z, 0-9, or F1-F12."
        case .missingModifier:
            return "At least one modifier is required (command/option/control/shift)."
        case .duplicateShortcut:
            return "That shortcut is already used by another action."
        case .registerFailed(let status):
            return "Failed to register shortcut (OSStatus: \(status))."
        }
    }
}

struct HotkeyShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    var displayString: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        result += Self.displayKey(for: keyCode)
        return result
    }

    var editableString: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("control") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("option") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("shift") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("command") }
        parts.append(Self.tokenForKey(keyCode))
        return parts.joined(separator: "+")
    }

    static func parse(_ text: String) throws -> HotkeyShortcut {
        let tokens = text
            .split(separator: "+")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard tokens.count >= 2 else { throw HotkeyError.invalidFormat }
        guard let keyToken = tokens.last else { throw HotkeyError.invalidFormat }

        var modifiers: UInt32 = 0
        for modifierToken in tokens.dropLast() {
            switch modifierToken {
            case "cmd", "command":
                modifiers |= UInt32(cmdKey)
            case "opt", "option", "alt":
                modifiers |= UInt32(optionKey)
            case "ctrl", "control":
                modifiers |= UInt32(controlKey)
            case "shift":
                modifiers |= UInt32(shiftKey)
            default:
                throw HotkeyError.invalidFormat
            }
        }

        guard modifiers != 0 else { throw HotkeyError.missingModifier }
        guard let keyCode = Self.keyCodeMap[keyToken] else { throw HotkeyError.unknownKey }

        return HotkeyShortcut(keyCode: keyCode, modifiers: normalizeModifiers(modifiers))
    }

    static func from(event: NSEvent) throws -> HotkeyShortcut {
        let modifiers = modifierMask(from: event.modifierFlags)
        guard modifiers != 0 else { throw HotkeyError.missingModifier }

        let keyCode = UInt32(event.keyCode)
        guard supports(keyCode: keyCode) else { throw HotkeyError.unknownKey }

        return HotkeyShortcut(keyCode: keyCode, modifiers: modifiers)
    }

    private static func displayKey(for keyCode: UInt32) -> String {
        switch keyCode {
        case UInt32(kVK_Return): return "↩"
        case UInt32(kVK_Escape): return "⎋"
        case UInt32(kVK_Space): return "Space"
        default:
            return reverseKeyCodeMap[keyCode] ?? "?"
        }
    }

    private static func tokenForKey(_ keyCode: UInt32) -> String {
        switch keyCode {
        case UInt32(kVK_Return): return "return"
        case UInt32(kVK_Escape): return "escape"
        case UInt32(kVK_Space): return "space"
        default:
            return (reverseKeyCodeMap[keyCode] ?? "?").lowercased()
        }
    }

    private static let keyCodeMap: [String: UInt32] = {
        var map: [String: UInt32] = [
            "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C),
            "d": UInt32(kVK_ANSI_D), "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F),
            "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H), "i": UInt32(kVK_ANSI_I),
            "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
            "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O),
            "p": UInt32(kVK_ANSI_P), "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R),
            "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T), "u": UInt32(kVK_ANSI_U),
            "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
            "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
            "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
            "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
            "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
            "9": UInt32(kVK_ANSI_9),
            "return": UInt32(kVK_Return), "enter": UInt32(kVK_Return),
            "escape": UInt32(kVK_Escape), "esc": UInt32(kVK_Escape),
            "space": UInt32(kVK_Space)
        ]

        let functionKeys: [(String, Int)] = [
            ("f1", kVK_F1), ("f2", kVK_F2), ("f3", kVK_F3), ("f4", kVK_F4),
            ("f5", kVK_F5), ("f6", kVK_F6), ("f7", kVK_F7), ("f8", kVK_F8),
            ("f9", kVK_F9), ("f10", kVK_F10), ("f11", kVK_F11), ("f12", kVK_F12)
        ]
        for (token, code) in functionKeys {
            map[token] = UInt32(code)
        }
        return map
    }()

    private static let reverseKeyCodeMap: [UInt32: String] = {
        var reverse: [UInt32: String] = [:]
        for (key, value) in keyCodeMap {
            if reverse[value] == nil {
                reverse[value] = key.uppercased()
            }
        }
        return reverse
    }()

    private static func supports(keyCode: UInt32) -> Bool {
        reverseKeyCodeMap[keyCode] != nil
    }
}

class HotkeyManager {
    static let shared = HotkeyManager()

    var onCaptureShortcut: (() -> Void)?
    var onCloseAllShortcut: (() -> Void)?

    var captureShortcutDisplay: String { captureShortcut.displayString }
    var closeAllShortcutDisplay: String { closeAllShortcut.displayString }
    var captureShortcutEditable: String { captureShortcut.editableString }
    var closeAllShortcutEditable: String { closeAllShortcut.editableString }

    private var captureHotKeyRef: EventHotKeyRef?
    private var closeAllHotKeyRef: EventHotKeyRef?

    private var captureShortcut: HotkeyShortcut
    private var closeAllShortcut: HotkeyShortcut

    private let defaults = UserDefaults.standard
    private let captureDefaultsKey = "hotkey.capture"
    private let closeAllDefaultsKey = "hotkey.closeAll"

    init() {
        captureShortcut = Self.loadShortcut(
            from: UserDefaults.standard,
            key: "hotkey.capture",
            fallback: HotkeyShortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(optionKey))
        )
        closeAllShortcut = Self.loadShortcut(
            from: UserDefaults.standard,
            key: "hotkey.closeAll",
            fallback: HotkeyShortcut(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(cmdKey | optionKey))
        )
        setupHotkeyEventHandler()
        registerConfiguredHotkeys()
    }

    func updateShortcut(action: HotkeyAction, text: String) throws {
        let parsed = try HotkeyShortcut.parse(text)
        try setShortcut(action: action, shortcut: parsed, persist: true)
    }

    func updateShortcut(action: HotkeyAction, shortcut: HotkeyShortcut) throws {
        try setShortcut(action: action, shortcut: shortcut, persist: true)
    }

    func shortcut(for action: HotkeyAction) -> HotkeyShortcut {
        switch action {
        case .capture:
            return captureShortcut
        case .closeAll:
            return closeAllShortcut
        }
    }

    func resetShortcut(action: HotkeyAction) throws {
        let fallback: HotkeyShortcut
        switch action {
        case .capture:
            fallback = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_1), modifiers: UInt32(optionKey))
        case .closeAll:
            fallback = HotkeyShortcut(keyCode: UInt32(kVK_ANSI_W), modifiers: UInt32(cmdKey | optionKey))
        }
        try setShortcut(action: action, shortcut: fallback, persist: true)
    }

    private func setupHotkeyEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let ptr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(GetApplicationEventTarget(), { _, theEvent, userData in
            guard let event = theEvent, let userData = userData else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

            var hotkeyID = EventHotKeyID()
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotkeyID
            )

            if hotkeyID.id == 1 {
                DispatchQueue.main.async { manager.onCaptureShortcut?() }
            } else if hotkeyID.id == 2 {
                DispatchQueue.main.async { manager.onCloseAllShortcut?() }
            }
            return noErr
        }, 1, &eventType, ptr, nil)
    }

    private func registerConfiguredHotkeys() {
        do {
            try registerHotKey(captureShortcut, id: 1, ref: &captureHotKeyRef)
            try registerHotKey(closeAllShortcut, id: 2, ref: &closeAllHotKeyRef)
        } catch {
            // Keep app running even if global shortcut registration fails.
        }
    }

    private func setShortcut(action: HotkeyAction, shortcut: HotkeyShortcut, persist: Bool) throws {
        let otherShortcut = (action == .capture) ? closeAllShortcut : captureShortcut
        if shortcut == otherShortcut {
            throw HotkeyError.duplicateShortcut
        }

        var oldShortcut: HotkeyShortcut
        switch action {
        case .capture:
            oldShortcut = captureShortcut
            unregister(ref: &captureHotKeyRef)
            do {
                try registerHotKey(shortcut, id: 1, ref: &captureHotKeyRef)
                captureShortcut = shortcut
                if persist { saveShortcut(shortcut, key: captureDefaultsKey) }
            } catch {
                try? registerHotKey(oldShortcut, id: 1, ref: &captureHotKeyRef)
                throw error
            }
        case .closeAll:
            oldShortcut = closeAllShortcut
            unregister(ref: &closeAllHotKeyRef)
            do {
                try registerHotKey(shortcut, id: 2, ref: &closeAllHotKeyRef)
                closeAllShortcut = shortcut
                if persist { saveShortcut(shortcut, key: closeAllDefaultsKey) }
            } catch {
                try? registerHotKey(oldShortcut, id: 2, ref: &closeAllHotKeyRef)
                throw error
            }
        }
    }

    private func registerHotKey(_ shortcut: HotkeyShortcut, id: UInt32, ref: inout EventHotKeyRef?) throws {
        let hotKeyID = EventHotKeyID(signature: OSType(32), id: id)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr else { throw HotkeyError.registerFailed(status) }
    }

    private func unregister(ref: inout EventHotKeyRef?) {
        if let ref {
            UnregisterEventHotKey(ref)
        }
        ref = nil
    }

    private func saveShortcut(_ shortcut: HotkeyShortcut, key: String) {
        defaults.set(["keyCode": Int(shortcut.keyCode), "modifiers": Int(shortcut.modifiers)], forKey: key)
    }

    private static func loadShortcut(from defaults: UserDefaults, key: String, fallback: HotkeyShortcut) -> HotkeyShortcut {
        guard let dict = defaults.dictionary(forKey: key),
              let keyCode = dict["keyCode"] as? Int,
              let modifiers = dict["modifiers"] as? Int else {
            return fallback
        }
        return HotkeyShortcut(
            keyCode: UInt32(keyCode),
            modifiers: normalizeModifiers(UInt32(modifiers))
        )
    }
}

private func normalizeModifiers(_ raw: UInt32) -> UInt32 {
    raw & UInt32(cmdKey | optionKey | controlKey | shiftKey)
}

private func modifierMask(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var result: UInt32 = 0
    if flags.contains(.control) { result |= UInt32(controlKey) }
    if flags.contains(.option) { result |= UInt32(optionKey) }
    if flags.contains(.shift) { result |= UInt32(shiftKey) }
    if flags.contains(.command) { result |= UInt32(cmdKey) }
    return normalizeModifiers(result)
}
