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

enum ScreenshotCorner: Int, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var title: String { ["Top left", "Top right", "Bottom left", "Bottom right"][rawValue] }
}

struct ScreenshotStyle: Codable, Equatable {
    var paddingEnabled = false
    var cornersEnabled = false
    var top: Double = 24
    var bottom: Double = 24
    var left: Double = 24
    var right: Double = 24
    var topLeftRadius: Double = 12
    var topRightRadius: Double = 12
    var bottomLeftRadius: Double = 12
    var bottomRightRadius: Double = 12
    var transparent = false
    var red: Double = 1
    var green: Double = 1
    var blue: Double = 1

    // Compatibility for callers that apply one value to the entire frame.
    var enabled: Bool {
        get { paddingEnabled || cornersEnabled }
        set { paddingEnabled = newValue; cornersEnabled = newValue }
    }
    var cornerRadius: Double {
        get { topLeftRadius }
        set { for corner in ScreenshotCorner.allCases { setRadius(newValue, for: corner) } }
    }
    var radii: [Double] { [topLeftRadius, topRightRadius, bottomLeftRadius, bottomRightRadius] }

    func radius(for corner: ScreenshotCorner) -> Double { radii[corner.rawValue] }
    mutating func setRadius(_ value: Double, for corner: ScreenshotCorner) {
        switch corner {
        case .topLeft: topLeftRadius = value
        case .topRight: topRightRadius = value
        case .bottomLeft: bottomLeftRadius = value
        case .bottomRight: bottomRightRadius = value
        }
    }

    init() {}

    private enum CodingKeys: String, CodingKey {
        case paddingEnabled, cornersEnabled, top, bottom, left, right
        case topLeftRadius, topRightRadius, bottomLeftRadius, bottomRightRadius
        case transparent, red, green, blue
    }
    private enum LegacyKeys: String, CodingKey { case enabled, cornerRadius }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyKeys.self)
        let wasEnabled = try legacy.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        let radius = try legacy.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 12
        paddingEnabled = try values.decodeIfPresent(Bool.self, forKey: .paddingEnabled) ?? wasEnabled
        cornersEnabled = try values.decodeIfPresent(Bool.self, forKey: .cornersEnabled) ?? wasEnabled
        top = try values.decodeIfPresent(Double.self, forKey: .top) ?? 24
        bottom = try values.decodeIfPresent(Double.self, forKey: .bottom) ?? 24
        left = try values.decodeIfPresent(Double.self, forKey: .left) ?? 24
        right = try values.decodeIfPresent(Double.self, forKey: .right) ?? 24
        topLeftRadius = try values.decodeIfPresent(Double.self, forKey: .topLeftRadius) ?? radius
        topRightRadius = try values.decodeIfPresent(Double.self, forKey: .topRightRadius) ?? radius
        bottomLeftRadius = try values.decodeIfPresent(Double.self, forKey: .bottomLeftRadius) ?? radius
        bottomRightRadius = try values.decodeIfPresent(Double.self, forKey: .bottomRightRadius) ?? radius
        transparent = try values.decodeIfPresent(Bool.self, forKey: .transparent) ?? false
        red = try values.decodeIfPresent(Double.self, forKey: .red) ?? 1
        green = try values.decodeIfPresent(Double.self, forKey: .green) ?? 1
        blue = try values.decodeIfPresent(Double.self, forKey: .blue) ?? 1
    }

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
        for corner in ScreenshotCorner.allCases {
            result.setRadius(limit(radius(for: corner), to: 500).rounded(), for: corner)
        }
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

    func restoreDefaults() {
        for key in ["screenshot.style.v1", "pins.history.enabled", "pins.history.limit"] + CaptureDestination.allCases.map(directoryKey) {
            defaults.removeObject(forKey: key)
        }
    }
}

enum ScreenshotStyler {
    /// The same path drives the live selection preview and the pixel export.
    static func roundedPath(in rect: CGRect, style: ScreenshotStyle, pixelScale: CGFloat = 1) -> CGPath {
        let radii = style.cornersEnabled ? style.normalized.radii : [0, 0, 0, 0]
        let r = radii.map { min(CGFloat($0) / max(pixelScale, 1), min(rect.width, rect.height) / 2) }
        let tl = r[0], tr = r[1], bl = r[2], br = r[3]
        let k: CGFloat = 0.5522847498
        let x = rect.minX, y = rect.minY, right = rect.maxX, top = rect.maxY
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x + bl, y: y))
        path.addLine(to: CGPoint(x: right - br, y: y))
        path.addCurve(to: CGPoint(x: right, y: y + br), control1: CGPoint(x: right - br + br * k, y: y), control2: CGPoint(x: right, y: y + br - br * k))
        path.addLine(to: CGPoint(x: right, y: top - tr))
        path.addCurve(to: CGPoint(x: right - tr, y: top), control1: CGPoint(x: right, y: top - tr + tr * k), control2: CGPoint(x: right - tr + tr * k, y: top))
        path.addLine(to: CGPoint(x: x + tl, y: top))
        path.addCurve(to: CGPoint(x: x, y: top - tl), control1: CGPoint(x: x + tl - tl * k, y: top), control2: CGPoint(x: x, y: top - tl + tl * k))
        path.addLine(to: CGPoint(x: x, y: y + bl))
        path.addCurve(to: CGPoint(x: x + bl, y: y), control1: CGPoint(x: x, y: y + bl - bl * k), control2: CGPoint(x: x + bl - bl * k, y: y))
        path.closeSubpath()
        return path
    }

    /// Insets and radius are output pixels, independent of Retina scale.
    static func apply(_ style: ScreenshotStyle, to image: NSImage) -> NSImage? {
        let style = style.normalized
        guard style.enabled else { return image }
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let left = style.paddingEnabled ? style.left : 0
        let right = style.paddingEnabled ? style.right : 0
        let top = style.paddingEnabled ? style.top : 0
        let bottom = style.paddingEnabled ? style.bottom : 0
        let width = source.width + Int(left + right)
        let height = source.height + Int(top + bottom)
        let colorSpace = source.colorSpace?.model == .rgb ? source.colorSpace! : CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if style.paddingEnabled && !style.transparent {
            context.setFillColor(style.backgroundColor.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        let imageRect = CGRect(x: left, y: bottom, width: Double(source.width), height: Double(source.height))
        context.addPath(roundedPath(in: imageRect, style: style))
        context.clip()
        context.draw(source, in: imageRect)
        guard let result = context.makeImage() else { return nil }
        let scaleX = CGFloat(source.width) / max(image.size.width, 1)
        let scaleY = CGFloat(source.height) / max(image.size.height, 1)
        return NSImage(cgImage: result, size: NSSize(width: CGFloat(width) / scaleX, height: CGFloat(height) / scaleY))
    }
}
