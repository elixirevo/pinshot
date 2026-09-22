import Cocoa

enum CaptureDestination: String, CaseIterable {
    case screenshot, pin, macro

    var title: String {
        switch self {
        case .screenshot: return "Screenshot Editor"
        case .pin: return "Pinned Screenshots"
        case .macro: return "Macro Screenshots"
        }
    }

    var folderName: String {
        switch self {
        case .screenshot: return "Screenshots"
        case .pin: return "Pins"
        case .macro: return "Macro"
        }
    }
}

enum PinHistoryRetention: Int, CaseIterable {
    case ten = 10
    case thirty = 30
    case fifty = 50
    case hundred = 100
    case unlimited = 0

    var maximumCount: Int? { self == .unlimited ? nil : rawValue }
    var title: String { self == .unlimited ? "Never Delete" : "\(rawValue) captures" }
}

struct ScreenshotStyle: Codable, Equatable {
    var enabled = false
    var top: Double = 24
    var bottom: Double = 24
    var left: Double = 24
    var right: Double = 24
    var cornerRadius: Double = 12
    var transparent = false
    var red: Double = 1
    var green: Double = 1
    var blue: Double = 1

    var backgroundColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: transparent ? 0 : 1)
    }

    var normalized: ScreenshotStyle {
        var result = self
        func limit(_ value: Double, to maximum: Double) -> Double {
            value.isFinite ? min(max(value, 0), maximum) : 0
        }
        result.top = limit(top, to: 500).rounded()
        result.bottom = limit(bottom, to: 500).rounded()
        result.left = limit(left, to: 500).rounded()
        result.right = limit(right, to: 500).rounded()
        result.cornerRadius = limit(cornerRadius, to: 500).rounded()
        result.red = limit(red, to: 1)
        result.green = limit(green, to: 1)
        result.blue = limit(blue, to: 1)
        return result
    }
}

final class CapturePreferences {
    static let shared = CapturePreferences()
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var screenshotStyle: ScreenshotStyle {
        get {
            guard let data = defaults.data(forKey: "screenshot.style.v1"),
                  let style = try? JSONDecoder().decode(ScreenshotStyle.self, from: data) else { return ScreenshotStyle() }
            return style.normalized
        }
        set { defaults.set(try? JSONEncoder().encode(newValue.normalized), forKey: "screenshot.style.v1") }
    }

    var pinHistoryEnabled: Bool {
        get { defaults.object(forKey: "pins.history.enabled") == nil || defaults.bool(forKey: "pins.history.enabled") }
        set { defaults.set(newValue, forKey: "pins.history.enabled") }
    }

    var pinHistoryRetention: PinHistoryRetention {
        get {
            guard defaults.object(forKey: "pins.history.limit") != nil else { return .thirty }
            return PinHistoryRetention(rawValue: defaults.integer(forKey: "pins.history.limit")) ?? .thirty
        }
        set { defaults.set(newValue.rawValue, forKey: "pins.history.limit") }
    }

    func directory(for destination: CaptureDestination) -> URL {
        if let path = defaults.string(forKey: directoryKey(destination)), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        let pictures = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return pictures.appendingPathComponent("PinShotCaptures", isDirectory: true)
            .appendingPathComponent(destination.folderName, isDirectory: true)
    }

    func setDirectory(_ url: URL, for destination: CaptureDestination) {
        defaults.set(url.standardizedFileURL.path, forKey: directoryKey(destination))
    }

    private func directoryKey(_ destination: CaptureDestination) -> String { "save.directory.\(destination.rawValue)" }
}

enum ScreenshotStyler {
    /// Insets and radius are output pixels, independent of Retina scale.
    static func apply(_ style: ScreenshotStyle, to image: NSImage) -> NSImage? {
        let style = style.normalized
        guard style.enabled else { return image }
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let width = source.width + Int(style.left + style.right)
        let height = source.height + Int(style.top + style.bottom)
        let colorSpace = source.colorSpace?.model == .rgb ? source.colorSpace! : CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if !style.transparent {
            context.setFillColor(style.backgroundColor.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let imageRect = CGRect(x: style.left, y: style.bottom, width: Double(source.width), height: Double(source.height))
        let radius = min(style.cornerRadius, Double(min(source.width, source.height)) / 2)
        context.addPath(CGPath(roundedRect: imageRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.draw(source, in: imageRect)
        guard let result = context.makeImage() else { return nil }
        let scaleX = CGFloat(source.width) / max(image.size.width, 1)
        let scaleY = CGFloat(source.height) / max(image.size.height, 1)
        return NSImage(cgImage: result, size: NSSize(width: CGFloat(width) / scaleX, height: CGFloat(height) / scaleY))
    }
}
