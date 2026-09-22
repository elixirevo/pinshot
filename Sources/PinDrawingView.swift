import Cocoa

final class PinDrawingView: NSView {
    var tool: ScreenshotTool = .pen
    var color: NSColor = .systemRed
    var strokeWidth: CGFloat = 3
    var onChange: (() -> Void)?
    private var source: CGImage?
    private var sourceSize: NSSize = .zero
    private var annotations: [ScreenshotAnnotation] = []
    private var undone: [ScreenshotAnnotation] = []
    private var pending: ScreenshotAnnotation?

    var canUndo: Bool { !annotations.isEmpty }
    var canRedo: Bool { !undone.isEmpty }
    var hasEdits: Bool { !annotations.isEmpty }
    override var acceptsFirstResponder: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func configure(image: NSImage) {
        source = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        sourceSize = image.size
        annotations.removeAll()
        undone.removeAll()
        pending = nil
        needsDisplay = true
    }

    func renderedImage() -> NSImage? {
        guard let source else { return nil }
        return ScreenshotRenderer.render(source: source, size: sourceSize,
            selection: NSRect(origin: .zero, size: sourceSize), annotations: annotations)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.scaleX(by: bounds.width / sourceSize.width, yBy: bounds.height / sourceSize.height)
        transform.concat()
        for annotation in annotations { annotation.draw() }
        pending?.draw()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func point(for event: NSEvent) -> NSPoint {
        let point = convert(event.locationInWindow, from: nil)
        return ScreenshotGeometry.clamped(NSPoint(x: point.x * sourceSize.width / max(bounds.width, 1),
                                                  y: point.y * sourceSize.height / max(bounds.height, 1)),
                                          to: NSRect(origin: .zero, size: sourceSize))
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        pending = ScreenshotAnnotation(tool: tool, points: [point(for: event)], color: color, lineWidth: strokeWidth)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard var annotation = pending else { return }
        let endpoint = point(for: event)
        if annotation.tool == .pen { annotation.points.append(endpoint) }
        else { annotation.points = [annotation.points[0], endpoint] }
        if let source { annotation.prepareMosaic(source: source, size: sourceSize) }
        pending = annotation
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let pending, pending.tool == .pen || pending.rect.width > 2 || pending.rect.height > 2 {
            annotations.append(pending)
            undone.removeAll()
        }
        pending = nil
        needsDisplay = true
        onChange?()
    }

    func undoStroke() {
        if let last = annotations.popLast() { undone.append(last) }
        needsDisplay = true
        onChange?()
    }

    func redoStroke() {
        if let last = undone.popLast() { annotations.append(last) }
        needsDisplay = true
        onChange?()
    }
}

/// Explicit colors keep controls legible over both light and dark screenshots.
final class PinControlButton: NSButton {
    init(symbol: String, label: String, target: AnyObject?, action: Selector?) {
        super.init(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
        title = ""
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        toolTip = label
        setAccessibilityLabel(label)
        self.target = target
        self.action = action
        isBordered = false
        focusRingType = .none
        appearance = NSAppearance(named: .aqua)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1.5, dy: 1.5)
        let shape = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        (state == .on || isHighlighted ? NSColor(white: 0.80, alpha: 1) : NSColor(white: 0.98, alpha: 1)).setFill()
        shape.fill()
        NSColor.black.setStroke()
        shape.lineWidth = 2
        shape.stroke()
        if let image {
            image.draw(in: NSRect(x: (bounds.width - 16) / 2, y: (bounds.height - 16) / 2, width: 16, height: 16),
                       from: .zero, operation: .sourceOver, fraction: isEnabled ? 1 : 0.3, respectFlipped: true, hints: nil)
        }
    }
}

final class PinDrawingToolbar: NSPanel {
    var onDone: (() -> Void)?
    private weak var canvas: PinDrawingView?
    private var buttons: [PinControlButton] = []
    private var undoButton: PinControlButton!
    private var redoButton: PinControlButton!

    init(canvas: PinDrawingView) {
        self.canvas = canvas
        super.init(contentRect: NSRect(x: 0, y: 0, width: 348, height: 84),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 348, height: 84))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor
        content.layer?.borderWidth = 1
        content.layer?.borderColor = NSColor.white.cgColor
        content.layer?.cornerRadius = 10
        contentView = content
        for (index, tool) in [ScreenshotTool.pen, .rectangle, .ellipse, .arrow, .mosaic].enumerated() {
            let button = PinControlButton(symbol: tool.symbol, label: tool.title, target: self, action: #selector(selectTool(_:)))
            button.tag = tool.rawValue
            button.frame.origin = NSPoint(x: 10 + index * 34, y: 46)
            content.addSubview(button)
            buttons.append(button)
        }
        undoButton = PinControlButton(symbol: "arrow.uturn.backward", label: "Undo (⌘Z)", target: self, action: #selector(undoStroke))
        undoButton.frame.origin = NSPoint(x: 188, y: 46)
        content.addSubview(undoButton)
        redoButton = PinControlButton(symbol: "arrow.uturn.forward", label: "Redo (⇧⌘Z)", target: self, action: #selector(redoStroke))
        redoButton.frame.origin = NSPoint(x: 222, y: 46)
        content.addSubview(redoButton)
        let done = NSButton(title: "Done", target: self, action: #selector(doneClicked))
        done.bezelStyle = .rounded
        done.appearance = NSAppearance(named: .aqua)
        done.frame = NSRect(x: 264, y: 45, width: 74, height: 30)
        content.addSubview(done)
        for (index, color) in Self.colors.enumerated() {
            let button = NSButton(frame: NSRect(x: 12 + index * 26, y: 11, width: 22, height: 24))
            button.title = "●"
            button.font = .systemFont(ofSize: 20)
            button.isBordered = false
            button.contentTintColor = color
            button.tag = index
            button.target = self
            button.action = #selector(selectColor(_:))
            button.setAccessibilityLabel(["Red", "Orange", "Green", "Blue", "White", "Black"][index])
            content.addSubview(button)
        }
        let width = NSSegmentedControl(labels: ["2", "4", "8"], trackingMode: .selectOne,
                                       target: self, action: #selector(selectWidth(_:)))
        width.frame = NSRect(x: 202, y: 10, width: 132, height: 26)
        width.selectedSegment = 1
        width.setAccessibilityLabel("Drawing stroke width")
        content.addSubview(width)
        canvas.strokeWidth = 4
        refresh()
    }

    private static let colors: [NSColor] = [.systemRed, .systemOrange, .systemGreen, .systemBlue, .white, .black]

    func refresh() {
        for button in buttons { button.state = button.tag == canvas?.tool.rawValue ? .on : .off; button.needsDisplay = true }
        undoButton.isEnabled = canvas?.canUndo == true
        redoButton.isEnabled = canvas?.canRedo == true
    }

    @objc private func selectTool(_ sender: NSButton) {
        canvas?.tool = ScreenshotTool(rawValue: sender.tag) ?? .pen
        refresh()
        canvas?.window?.makeFirstResponder(canvas)
    }
    @objc private func selectColor(_ sender: NSButton) { canvas?.color = Self.colors[sender.tag] }
    @objc private func selectWidth(_ sender: NSSegmentedControl) { canvas?.strokeWidth = [2, 4, 8][sender.selectedSegment] }
    @objc private func undoStroke() { canvas?.undoStroke() }
    @objc private func redoStroke() { canvas?.redoStroke() }
    @objc private func doneClicked() { onDone?() }
}
