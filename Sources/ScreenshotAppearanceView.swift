import Cocoa

/// Native corner controls shared by the Frame panel and Settings.
final class ScreenshotCornerControlsView: NSView, NSTextFieldDelegate {
    var onChange: ((ScreenshotStyle) -> Void)?
    private var style = ScreenshotStyle()
    private let enabled = NSButton(checkboxWithTitle: "Rounded corners", target: nil, action: nil)
    private let corners = NSSegmentedControl(labels: ["All", "", "", "", ""], trackingMode: .selectOne, target: nil, action: nil)
    private let label = NSTextField(labelWithString: "All corners")
    private let slider = NSSlider(value: 12, minValue: 0, maxValue: 500, target: nil, action: nil)
    private let value = NSTextField()

    override init(frame: NSRect) {
        super.init(frame: frame)
        enabled.target = self
        enabled.action = #selector(toggleEnabled)
        corners.target = self
        corners.action = #selector(selectCorner)
        corners.selectedSegment = 0
        corners.setWidth(38, forSegment: 0)
        corners.setToolTip("Adjust all four corners together", forSegment: 0)
        for corner in ScreenshotCorner.allCases {
            let index = corner.rawValue + 1
            corners.setImage(Self.cornerIcon(corner), forSegment: index)
            corners.setWidth(27, forSegment: index)
            corners.setToolTip(corner.title, forSegment: index)
        }
        corners.setAccessibilityLabel("Corner to adjust: all, top left, top right, bottom left, bottom right")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.setAccessibilityLabel("Corner radius in pixels")
        value.formatter = pixelFormatter()
        value.delegate = self
        value.alignment = .right
        value.setAccessibilityLabel("Corner radius value in pixels")
        let units = NSTextField(labelWithString: "px")
        units.font = .systemFont(ofSize: 11)
        units.textColor = .secondaryLabelColor
        for child in [enabled, corners, label, slider, value, units] {
            child.translatesAutoresizingMaskIntoConstraints = false
            addSubview(child)
        }
        NSLayoutConstraint.activate([
            enabled.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            enabled.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            corners.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            corners.centerYAnchor.constraint(equalTo: enabled.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: enabled.leadingAnchor),
            label.topAnchor.constraint(equalTo: enabled.bottomAnchor, constant: 14),
            label.widthAnchor.constraint(equalToConstant: 72),
            slider.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 6),
            slider.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            slider.trailingAnchor.constraint(equalTo: value.leadingAnchor, constant: -8),
            value.widthAnchor.constraint(equalToConstant: 50),
            value.centerYAnchor.constraint(equalTo: label.centerYAnchor),
            units.leadingAnchor.constraint(equalTo: value.trailingAnchor, constant: 5),
            units.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            units.centerYAnchor.constraint(equalTo: value.centerYAnchor)
        ])
        configure(style)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ style: ScreenshotStyle) {
        self.style = style
        enabled.state = style.cornersEnabled ? .on : .off
        let selected = ScreenshotCorner(rawValue: corners.selectedSegment - 1)
        label.stringValue = selected?.title ?? "All corners"
        let radius = selected.map { style.radius(for: $0) } ?? style.topLeftRadius
        slider.doubleValue = radius
        if value.currentEditor() == nil {
            if selected == nil && Set(style.radii).count > 1 { value.stringValue = ""; value.placeholderString = "Mixed" }
            else { value.integerValue = Int(radius); value.placeholderString = nil }
        }
        slider.isEnabled = style.cornersEnabled
        value.isEnabled = style.cornersEnabled
    }

    @objc private func toggleEnabled() {
        style.cornersEnabled = enabled.state == .on
        configure(style)
        onChange?(style)
    }
    @objc private func selectCorner() { configure(style) }
    @objc private func sliderChanged() { setRadius(slider.doubleValue.rounded()) }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        finishFrameFieldEditing(control, command: command)
    }
    func controlTextDidChange(_ notification: Notification) {
        guard !value.stringValue.isEmpty else { return }
        setRadius(value.doubleValue, updateField: false)
    }
    func controlTextDidEndEditing(_ notification: Notification) { configure(style) }

    private func setRadius(_ radius: Double, updateField: Bool = true) {
        if let corner = ScreenshotCorner(rawValue: corners.selectedSegment - 1) { style.setRadius(radius, for: corner) }
        else { style.cornerRadius = radius }
        style = style.normalized
        slider.doubleValue = radius
        if updateField { configure(style) }
        onChange?(style)
    }

    private static func cornerIcon(_ corner: ScreenshotCorner) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let path = NSBezierPath()
            let transform = NSAffineTransform()
            transform.translateX(by: 9, yBy: 9)
            transform.scaleX(by: [.topRight, .bottomRight].contains(corner) ? -1 : 1,
                             yBy: [.bottomLeft, .bottomRight].contains(corner) ? -1 : 1)
            transform.concat()
            path.move(to: NSPoint(x: -5, y: -6))
            path.line(to: NSPoint(x: -5, y: 0))
            path.curve(to: NSPoint(x: 0, y: 5), controlPoint1: NSPoint(x: -5, y: 3), controlPoint2: NSPoint(x: -3, y: 5))
            path.line(to: NSPoint(x: 6, y: 5))
            path.lineWidth = 2
            path.lineCapStyle = .round
            NSColor.labelColor.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Embedded in the capture overlay, so a system color panel cannot appear behind it.
final class ScreenshotColorPickerView: NSView, NSTextFieldDelegate {
    var onChange: ((NSColor) -> Void)?
    private var sliders: [NSSlider] = []
    private let hex = NSTextField()
    private static let colors: [NSColor] = [.white, .black, .systemRed, .systemOrange, .systemGreen, .systemBlue, .systemPurple]

    override init(frame: NSRect) {
        super.init(frame: frame)
        for (index, color) in Self.colors.enumerated() {
            let button = NSButton(frame: NSRect(x: CGFloat(index) * 25, y: 99, width: 23, height: 26))
            button.title = ""
            button.image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
                let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
                color.setFill()
                circle.fill()
                NSColor.gray.setStroke()
                circle.lineWidth = 0.5
                circle.stroke()
                return true
            }
            button.imagePosition = .imageOnly
            button.bezelStyle = .circular
            button.tag = index
            button.target = self
            button.action = #selector(preset(_:))
            button.setAccessibilityLabel(["White", "Black", "Red", "Orange", "Green", "Blue", "Purple"][index] + " background")
            addSubview(button)
        }
        hex.frame = NSRect(x: 192, y: 100, width: 142, height: 24)
        hex.delegate = self
        hex.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        hex.setAccessibilityLabel("Background color hex code")
        addSubview(hex)
        for (index, channel) in ["Red", "Green", "Blue"].enumerated() {
            let y = 69 - CGFloat(index) * 29
            let label = NSTextField(labelWithString: channel)
            label.font = .systemFont(ofSize: 11)
            label.frame = NSRect(x: 2, y: y + 3, width: 44, height: 18)
            addSubview(label)
            let slider = NSSlider(value: 255, minValue: 0, maxValue: 255, target: self, action: #selector(rgbChanged))
            slider.frame = NSRect(x: 50, y: y, width: 284, height: 24)
            slider.isContinuous = true
            slider.setAccessibilityLabel("Background \(channel.lowercased()) channel")
            sliders.append(slider)
            addSubview(slider)
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ color: NSColor) {
        guard let color = color.usingColorSpace(.sRGB) else { return }
        for (slider, component) in zip(sliders, [color.redComponent, color.greenComponent, color.blueComponent]) {
            slider.doubleValue = Double(component * 255)
        }
        hex.stringValue = String(format: "#%02X%02X%02X", Int((color.redComponent * 255).rounded()),
                                 Int((color.greenComponent * 255).rounded()), Int((color.blueComponent * 255).rounded()))
    }
    @objc private func preset(_ sender: NSButton) {
        configure(Self.colors[sender.tag])
        rgbChanged()
    }
    @objc private func rgbChanged() {
        let color = NSColor(srgbRed: sliders[0].doubleValue / 255, green: sliders[1].doubleValue / 255,
                            blue: sliders[2].doubleValue / 255, alpha: 1)
        configure(color)
        onChange?(color)
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        finishFrameFieldEditing(control, command: command)
    }
    func controlTextDidEndEditing(_ notification: Notification) {
        configure(NSColor(srgbRed: sliders[0].doubleValue / 255, green: sliders[1].doubleValue / 255,
                          blue: sliders[2].doubleValue / 255, alpha: 1))
    }
    func controlTextDidChange(_ notification: Notification) {
        let string = hex.stringValue.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "#", with: "")
        guard string.count == 6, let number = UInt32(string, radix: 16) else { return }
        let color = NSColor(srgbRed: Double((number >> 16) & 255) / 255,
                            green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255, alpha: 1)
        for (slider, component) in zip(sliders, [color.redComponent, color.greenComponent, color.blueComponent]) {
            slider.doubleValue = Double(component * 255)
        }
        onChange?(color)
    }
}

/// Shared by Settings and the editor's in-overlay Frame panel.
final class ScreenshotAppearanceView: NSView, NSTextFieldDelegate {
    var onChange: ((ScreenshotStyle) -> Void)?
    var previewImage: NSImage? { didSet { updatePreview() } }
    private var style: ScreenshotStyle
    private let preferences: CapturePreferences
    private let corners = ScreenshotCornerControlsView(frame: NSRect(x: 8, y: 280, width: 354, height: 96))
    private let enabled = NSButton(checkboxWithTitle: "Padding", target: nil, action: nil)
    private let transparent = NSButton(checkboxWithTitle: "Transparent background", target: nil, action: nil)
    private let colorButton = NSButton(title: "Color…", target: nil, action: nil)
    private let picker = ScreenshotColorPickerView(frame: NSRect(x: 16, y: 12, width: 338, height: 130))
    private let preview = NSImageView()
    private let hint = NSTextField(labelWithString: "Output pixels · Applied to copy, save, and pin")
    private var fields: [NSTextField] = []

    init(preferences: CapturePreferences = .shared) {
        self.preferences = preferences
        style = preferences.screenshotStyle
        super.init(frame: NSRect(x: 0, y: 0, width: 370, height: 386))
        addSubview(corners)
        corners.onChange = { [weak self] style in self?.style = style; self?.save() }
        enabled.frame = NSRect(x: 16, y: 250, width: 180, height: 24)
        enabled.target = self
        enabled.action = #selector(changed)
        addSubview(enabled)
        for (index, label) in ["Top", "Bottom", "Left", "Right"].enumerated() {
            let x = 16 + CGFloat(index % 2) * 176
            let y = 216 - CGFloat(index / 2) * 34
            let title = NSTextField(labelWithString: label)
            title.frame = NSRect(x: x, y: y + 3, width: 80, height: 20)
            addSubview(title)
            let field = NSTextField(frame: NSRect(x: x + 90, y: y, width: 66, height: 24))
            field.formatter = pixelFormatter()
            field.delegate = self
            field.setAccessibilityLabel("\(label) padding in pixels")
            fields.append(field)
            addSubview(field)
        }
        transparent.frame = NSRect(x: 16, y: 149, width: 250, height: 24)
        transparent.target = self
        transparent.action = #selector(changed)
        addSubview(transparent)
        colorButton.frame = NSRect(x: 266, y: 146, width: 90, height: 28)
        colorButton.bezelStyle = .rounded
        colorButton.target = self
        colorButton.action = #selector(toggleColorPicker)
        colorButton.setAccessibilityLabel("Padding background color")
        addSubview(colorButton)
        picker.isHidden = true
        picker.onChange = { [weak self] color in
            guard let self, let color = color.usingColorSpace(.sRGB) else { return }
            self.style.red = color.redComponent
            self.style.green = color.greenComponent
            self.style.blue = color.blueComponent
            self.save()
        }
        addSubview(picker)
        preview.frame = NSRect(x: 16, y: 30, width: 338, height: 110)
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.wantsLayer = true
        preview.layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.18).cgColor
        preview.layer?.cornerRadius = 8
        preview.setAccessibilityLabel("Screenshot frame preview")
        addSubview(preview)
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 16, y: 7, width: 340, height: 17)
        addSubview(hint)
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { NSSize(width: 370, height: 386) }

    func reload() { configure(preferences.screenshotStyle) }
    func configure(_ style: ScreenshotStyle) {
        self.style = style
        corners.configure(style)
        enabled.state = style.paddingEnabled ? .on : .off
        transparent.state = style.transparent ? .on : .off
        picker.configure(NSColor(srgbRed: style.red, green: style.green, blue: style.blue, alpha: 1))
        for (field, value) in zip(fields, [style.top, style.bottom, style.left, style.right]) { field.integerValue = Int(value) }
        updatePreview()
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        finishFrameFieldEditing(control, command: command)
    }
    func controlTextDidChange(_ notification: Notification) { changed() }
    func controlTextDidEndEditing(_ notification: Notification) { configure(style) }

    @objc private func changed() {
        style.paddingEnabled = enabled.state == .on
        style.transparent = transparent.state == .on
        style.top = fields[0].doubleValue
        style.bottom = fields[1].doubleValue
        style.left = fields[2].doubleValue
        style.right = fields[3].doubleValue
        save()
    }
    @objc private func toggleColorPicker() {
        picker.isHidden.toggle()
        picker.configure(NSColor(srgbRed: style.red, green: style.green, blue: style.blue, alpha: 1))
        updatePreview()
    }
    private func save() {
        style = style.normalized
        preferences.screenshotStyle = style
        // Keep the two editors synchronized without replacing an active field editor.
        corners.configure(style)
        updatePreview()
        onChange?(style)
    }
    private func updatePreview() {
        fields.forEach { $0.isEnabled = style.paddingEnabled }
        transparent.isEnabled = style.paddingEnabled
        colorButton.isEnabled = style.paddingEnabled && !style.transparent
        if !colorButton.isEnabled { picker.isHidden = true }
        preview.isHidden = !picker.isHidden
        hint.isHidden = !picker.isHidden
        colorButton.title = picker.isHidden ? "Color…" : "Done"
        colorButton.image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { [style] rect in
            NSColor(srgbRed: style.red, green: style.green, blue: style.blue, alpha: 1).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
        colorButton.imagePosition = .imageLeading
        let sample = previewImage ?? NSImage(size: NSSize(width: 480, height: 240), flipped: false) { rect in
            NSColor(srgbRed: 0.15, green: 0.38, blue: 0.52, alpha: 1).setFill()
            rect.fill()
            ("PinShot" as NSString).draw(at: NSPoint(x: 36, y: 106), withAttributes: [
                .font: NSFont.systemFont(ofSize: 34, weight: .semibold), .foregroundColor: NSColor.white
            ])
            return true
        }
        if picker.isHidden { preview.image = ScreenshotStyler.apply(style, to: sample) }
    }
}

private func pixelFormatter() -> NumberFormatter {
    let formatter = NumberFormatter()
    formatter.minimum = 0
    formatter.maximum = 500
    formatter.allowsFloats = false
    return formatter
}

private func finishFrameFieldEditing(_ control: NSControl, command: Selector) -> Bool {
    guard command == #selector(NSResponder.insertNewline(_:)) || command == #selector(NSResponder.cancelOperation(_:)) else { return false }
    control.window?.makeFirstResponder(nil)
    return true
}
