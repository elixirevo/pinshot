import Cocoa

/// Shared by Settings and the screenshot editor's Frame popover.
final class ScreenshotAppearanceView: NSView, NSTextFieldDelegate {
    var onChange: ((ScreenshotStyle) -> Void)?
    var previewImage: NSImage? { didSet { updatePreview() } }
    private var style = CapturePreferences.shared.screenshotStyle
    private let enabled = NSButton(checkboxWithTitle: "Add padding and rounded corners", target: nil, action: nil)
    private let transparent = NSButton(checkboxWithTitle: "Transparent background", target: nil, action: nil)
    private let colorWell = NSColorWell()
    private let preview = NSImageView()
    private var fields: [NSTextField] = []

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 370, height: 386))
        enabled.frame = NSRect(x: 16, y: 348, width: 340, height: 24)
        enabled.target = self
        enabled.action = #selector(changed)
        addSubview(enabled)
        let labels = ["Top", "Bottom", "Left", "Right", "Corner radius"]
        for (index, label) in labels.enumerated() {
            let x: CGFloat = index < 4 ? 16 + CGFloat(index % 2) * 176 : 16
            let y: CGFloat = index < 4 ? 308 - CGFloat(index / 2) * 34 : 240
            let title = NSTextField(labelWithString: label)
            title.frame = NSRect(x: x, y: y + 3, width: 88, height: 20)
            addSubview(title)
            let field = NSTextField(frame: NSRect(x: x + 90, y: y, width: 66, height: 24))
            let formatter = NumberFormatter()
            formatter.minimum = 0
            formatter.maximum = 500
            formatter.allowsFloats = false
            field.formatter = formatter
            field.delegate = self
            field.setAccessibilityLabel("\(label) in pixels")
            fields.append(field)
            addSubview(field)
        }
        let units = NSTextField(labelWithString: "Output pixels · 0–500")
        units.font = .systemFont(ofSize: 11)
        units.textColor = .secondaryLabelColor
        units.frame = NSRect(x: 192, y: 243, width: 162, height: 20)
        addSubview(units)
        transparent.frame = NSRect(x: 16, y: 206, width: 270, height: 24)
        transparent.target = self
        transparent.action = #selector(changed)
        addSubview(transparent)
        colorWell.frame = NSRect(x: 302, y: 204, width: 50, height: 28)
        colorWell.target = self
        colorWell.action = #selector(changed)
        colorWell.setAccessibilityLabel("Padding background color")
        addSubview(colorWell)
        preview.frame = NSRect(x: 16, y: 30, width: 338, height: 158)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.18).cgColor
        preview.layer?.cornerRadius = 8
        preview.setAccessibilityLabel("Screenshot frame preview")
        addSubview(preview)
        let hint = NSTextField(labelWithString: "Applied when copying, saving, or pinning with the editor.")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 16, y: 7, width: 340, height: 17)
        addSubview(hint)
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: 370, height: 386) }

    func reload() {
        style = CapturePreferences.shared.screenshotStyle
        enabled.state = style.enabled ? .on : .off
        transparent.state = style.transparent ? .on : .off
        colorWell.color = NSColor(srgbRed: style.red, green: style.green, blue: style.blue, alpha: 1)
        for (field, value) in zip(fields, [style.top, style.bottom, style.left, style.right, style.cornerRadius]) {
            field.integerValue = Int(value)
        }
        updatePreview()
    }

    func controlTextDidChange(_ notification: Notification) { changed() }
    func controlTextDidEndEditing(_ notification: Notification) { changed() }

    @objc private func changed() {
        style.enabled = enabled.state == .on
        style.transparent = transparent.state == .on
        style.top = fields[0].doubleValue
        style.bottom = fields[1].doubleValue
        style.left = fields[2].doubleValue
        style.right = fields[3].doubleValue
        style.cornerRadius = fields[4].doubleValue
        if let color = colorWell.color.usingColorSpace(.sRGB) {
            style.red = color.redComponent
            style.green = color.greenComponent
            style.blue = color.blueComponent
        }
        style = style.normalized
        CapturePreferences.shared.screenshotStyle = style
        updatePreview()
        onChange?(style)
    }

    private func updatePreview() {
        fields.forEach { $0.isEnabled = style.enabled }
        transparent.isEnabled = style.enabled
        colorWell.isEnabled = style.enabled && !style.transparent
        let sample = previewImage ?? NSImage(size: NSSize(width: 480, height: 240), flipped: false) { rect in
            NSColor(srgbRed: 0.15, green: 0.38, blue: 0.52, alpha: 1).setFill()
            rect.fill()
            ("PinShot" as NSString).draw(at: NSPoint(x: 36, y: 106), withAttributes: [
                .font: NSFont.systemFont(ofSize: 34, weight: .semibold), .foregroundColor: NSColor.white
            ])
            return true
        }
        preview.image = ScreenshotStyler.apply(style, to: sample)
    }
}
