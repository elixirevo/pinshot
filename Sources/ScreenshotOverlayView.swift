import Cocoa
import Carbon

/// A frozen-screen editor. Coordinates stay in display points until the final pixel export.
final class ScreenshotOverlayView: CaptureOverlayView, NSTextFieldDelegate {
    var sourceImage: CGImage?
    var onActivate: (() -> Void)?
    var onFinish: ((NSImage, NSRect, ScreenshotOutput) -> Void)?
    var screenshotStyle = ScreenshotStyle()
    private var appearancePopover: NSPopover?

    private(set) var selection: NSRect?
    private var tool: ScreenshotTool = .select
    private var color = NSColor.systemRed
    private var strokeWidth: CGFloat = 3
    private var annotations: [ScreenshotAnnotation] = []
    private var redoAnnotations: [ScreenshotAnnotation] = []
    private var pendingAnnotation: ScreenshotAnnotation?
    private var dragOrigin: NSPoint?
    private var originalSelection: NSRect?
    private var resizeHandle: Int?
    private var isSelecting = false
    private var isMoving = false
    private var textField: NSTextField?
    private var textOrigin: NSPoint?
    private let toolbar = NSVisualEffectView()
    private var toolButtons: [NSButton] = []
    private var colorButtons: [NSButton] = []
    private var undoButton: NSButton!
    private var redoButton: NSButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        enableMagnifier = true
        setupToolbar()
        setAccessibilityLabel("Screenshot selection and annotation editor")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        // Reuse the capture overlay's dimming and magnifier without including them in exports.
        startPoint = selection?.origin
        currentPoint = selection.map { NSPoint(x: $0.maxX, y: $0.maxY) }
        if enableMagnifier { currentPoint = nil; startPoint = nil }
        super.draw(dirtyRect)

        if let selection {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: selection).addClip()
            for annotation in annotations { annotation.draw() }
            pendingAnnotation?.draw()
            NSGraphicsContext.restoreGraphicsState()

            NSColor.systemTeal.setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 1.5
            border.stroke()
            for point in handles(for: selection) {
                let handle = NSBezierPath(ovalIn: NSRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
                NSColor.white.setFill()
                handle.fill()
                NSColor.systemTeal.setStroke()
                handle.stroke()
            }
            let pixels = sourceImage.map { ScreenshotGeometry.pixelRect(selection, in: bounds.size, image: $0) }
            let label = "\(Int(pixels?.width ?? selection.width)) × \(Int(pixels?.height ?? selection.height)) px"
            drawBadge(label, at: NSPoint(x: selection.minX, y: min(selection.maxY + 8, bounds.maxY - 30)))
        }
        if selection == nil {
            drawBadge("Drag an area or click a window  ·  Esc to cancel", at: NSPoint(x: 20, y: 24))
        }
    }

    override func mouseMoved(with event: NSEvent) {
        cursorPoint = convert(event.locationInWindow, from: nil)
        if selection == nil {
            highlightedWindow = windowCandidates.first { $0.viewRect.contains(cursorPoint!) }
            enableMagnifier = true
        }
        updateCursor(at: cursorPoint!)
        needsDisplay = true
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDown(with event: NSEvent) {
        commitText()
        onActivate?()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        let point = ScreenshotGeometry.clamped(convert(event.locationInWindow, from: nil), to: bounds)
        dragOrigin = point
        originalSelection = selection
        cursorPoint = point
        if let selection {
            if event.clickCount == 2, tool == .select, selection.contains(point) {
                finish(.copy)
                return
            }
            if let index = handles(for: selection).firstIndex(where: { hypot($0.x - point.x, $0.y - point.y) <= 8 }) {
                resizeHandle = index
            } else if selection.contains(point) {
                if tool == .select {
                    isMoving = true
                } else if tool == .text {
                    beginText(at: point)
                    return
                } else {
                    pendingAnnotation = ScreenshotAnnotation(tool: tool, points: [point], color: color, lineWidth: strokeWidth)
                }
            } else {
                // Start another region only in selection mode; annotation clicks outside are ignored.
                guard tool == .select else { return }
                beginSelection(at: point)
            }
        } else {
            beginSelection(at: point)
        }
        toolbar.isHidden = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let point = ScreenshotGeometry.clamped(convert(event.locationInWindow, from: nil), to: bounds)
        cursorPoint = point
        if isSelecting {
            selection = ScreenshotGeometry.rect(from: origin, to: point)
            enableMagnifier = false
        } else if isMoving, let originalSelection {
            selection = ScreenshotGeometry.moved(originalSelection,
                by: NSSize(width: point.x - origin.x, height: point.y - origin.y), within: bounds)
        } else if let handle = resizeHandle, let originalSelection {
            selection = resized(originalSelection, handle: handle, point: point)
        } else if var annotation = pendingAnnotation, let selection {
            let endpoint = ScreenshotGeometry.clamped(point, to: selection)
            if annotation.tool == .pen {
                annotation.points.append(endpoint)
            } else {
                annotation.points = [origin, endpoint]
            }
            if let sourceImage { annotation.prepareMosaic(source: sourceImage, size: bounds.size) }
            pendingAnnotation = annotation
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isSelecting, let origin = dragOrigin {
            let point = ScreenshotGeometry.clamped(convert(event.locationInWindow, from: nil), to: bounds)
            let rect = ScreenshotGeometry.rect(from: origin, to: point)
            if rect.width > 5, rect.height > 5 {
                selection = rect
            } else {
                selection = windowCandidates.first { $0.viewRect.contains(point) }?.viewRect.intersection(bounds)
                if let selected = selection, selected.width <= 5 || selected.height <= 5 { selection = nil }
            }
        }
        if let annotation = pendingAnnotation {
            if annotation.tool == .pen || annotation.rect.width > 2 || annotation.rect.height > 2 {
                annotations.append(annotation)
                redoAnnotations.removeAll()
            }
        }
        pendingAnnotation = nil
        dragOrigin = nil
        originalSelection = nil
        resizeHandle = nil
        isSelecting = false
        isMoving = false
        highlightedWindow = nil
        enableMagnifier = selection == nil
        refreshToolbar()
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        if selection != nil { resetSelection() } else { onCancel?() }
    }

    override func keyDown(with event: NSEvent) {
        if handleKey(event) { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Let the field editor own normal text editing shortcuts while entering a label.
        if textField != nil { return super.performKeyEquivalent(with: event) }
        return handleKey(event) || super.performKeyEquivalent(with: event)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == UInt16(kVK_Escape) { onCancel?(); return true }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Use hardware keys so editor shortcuts also work with Korean and other IMEs.
        let keysByCode: [UInt16: String] = [
            UInt16(kVK_ANSI_C): "c", UInt16(kVK_ANSI_S): "s", UInt16(kVK_ANSI_Z): "z",
            UInt16(kVK_ANSI_A): "a", UInt16(kVK_ANSI_V): "v", UInt16(kVK_ANSI_R): "r",
            UInt16(kVK_ANSI_O): "o", UInt16(kVK_ANSI_P): "p", UInt16(kVK_ANSI_T): "t", UInt16(kVK_ANSI_M): "m"
        ]
        let key = keysByCode[event.keyCode] ?? event.charactersIgnoringModifiers?.lowercased() ?? ""
        if flags.contains(.command) {
            switch key {
            case "c": finish(.copy)
            case "s": finish(.save)
            case "z": flags.contains(.shift) ? redo() : undo()
            case "a":
                commitText()
                onActivate?()
                selection = bounds
                highlightedWindow = nil
                enableMagnifier = false
                refreshToolbar()
                needsDisplay = true
            default: return false
            }
            return true
        }
        guard !flags.contains(.option), !flags.contains(.control) else { return false }
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            finish(.copy)
            return true
        }
        if let selection {
            let step: CGFloat = flags.contains(.shift) ? 10 : 1
            let delta: NSSize
            switch Int(event.keyCode) {
            case kVK_LeftArrow: delta = NSSize(width: -step, height: 0)
            case kVK_RightArrow: delta = NSSize(width: step, height: 0)
            case kVK_UpArrow: delta = NSSize(width: 0, height: step)
            case kVK_DownArrow: delta = NSSize(width: 0, height: -step)
            default:
                let keys: [String: ScreenshotTool] = ["v": .select, "r": .rectangle, "o": .ellipse,
                    "a": .arrow, "p": .pen, "t": .text, "m": .mosaic]
                guard let selectedTool = keys[key] else { return false }
                selectTool(selectedTool)
                return true
            }
            self.selection = ScreenshotGeometry.moved(selection, by: delta, within: bounds)
            refreshToolbar()
            needsDisplay = true
            return true
        }
        return false
    }

    func resetSelection() {
        textField?.removeFromSuperview()
        textField = nil
        textOrigin = nil
        selection = nil
        annotations.removeAll()
        redoAnnotations.removeAll()
        pendingAnnotation = nil
        highlightedWindow = nil
        startPoint = nil
        currentPoint = nil
        tool = .select
        enableMagnifier = true
        toolbar.isHidden = true
        needsDisplay = true
    }

    private func beginSelection(at point: NSPoint) {
        resetSelection()
        dragOrigin = point
        isSelecting = true
    }

    private func handles(for rect: NSRect) -> [NSPoint] {
        [NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.midX, y: rect.minY),
         NSPoint(x: rect.maxX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.midY),
         NSPoint(x: rect.maxX, y: rect.maxY), NSPoint(x: rect.midX, y: rect.maxY),
         NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.minX, y: rect.midY)]
    }

    private func resized(_ rect: NSRect, handle: Int, point: NSPoint) -> NSRect {
        var left = rect.minX, right = rect.maxX, bottom = rect.minY, top = rect.maxY
        if [0, 6, 7].contains(handle) { left = min(point.x, right - 6) }
        if [2, 3, 4].contains(handle) { right = max(point.x, left + 6) }
        if [0, 1, 2].contains(handle) { bottom = min(point.y, top - 6) }
        if [4, 5, 6].contains(handle) { top = max(point.y, bottom + 6) }
        return NSRect(x: left, y: bottom, width: right - left, height: top - bottom).intersection(bounds)
    }

    private func updateCursor(at point: NSPoint) {
        if !toolbar.isHidden, toolbar.frame.contains(point) { NSCursor.arrow.set(); return }
        if tool == .select, selection?.contains(point) == true { NSCursor.openHand.set() }
        else if tool == .text, selection?.contains(point) == true { NSCursor.iBeam.set() }
        else { NSCursor.crosshair.set() }
    }

    private func beginText(at point: NSPoint) {
        guard let selection else { return }
        let font = NSFont.systemFont(ofSize: max(18, strokeWidth * 6), weight: .semibold)
        let origin = NSPoint(x: min(point.x, max(selection.minX, selection.maxX - 120)),
                             y: min(point.y, max(selection.minY, selection.maxY - 30)))
        let field = NSTextField(frame: NSRect(x: origin.x, y: origin.y,
                                               width: min(320, selection.maxX - origin.x), height: 30))
        field.font = font
        field.textColor = color
        field.backgroundColor = NSColor.black.withAlphaComponent(0.75)
        field.isBordered = false
        field.focusRingType = .none
        field.placeholderString = "Text"
        field.delegate = self
        field.setAccessibilityLabel("Annotation text")
        textOrigin = origin
        textField = field
        addSubview(field)
        window?.makeFirstResponder(field)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            commitText()
            window?.makeFirstResponder(self)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            textField?.removeFromSuperview()
            textField = nil
            textOrigin = nil
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }

    private func commitText() {
        guard let field = textField, let origin = textOrigin else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        textField = nil
        textOrigin = nil
        field.removeFromSuperview()
        if !text.isEmpty {
            annotations.append(ScreenshotAnnotation(tool: .text, points: [origin], color: color,
                                                    lineWidth: strokeWidth, text: text))
            redoAnnotations.removeAll()
        }
        refreshToolbar()
        needsDisplay = true
    }

    private func finish(_ output: ScreenshotOutput) {
        commitText()
        guard let selection, let sourceImage,
              let rawImage = ScreenshotRenderer.render(source: sourceImage, size: bounds.size,
                                                     selection: selection, annotations: annotations),
              let image = ScreenshotStyler.apply(screenshotStyle, to: rawImage) else {
            NSSound.beep()
            return
        }
        onFinish?(image, selection, output)
    }

    private func selectTool(_ newTool: ScreenshotTool) {
        commitText()
        tool = newTool
        window?.makeFirstResponder(self)
        refreshToolbar()
    }

    @objc private func toolClicked(_ sender: NSButton) { selectTool(ScreenshotTool(rawValue: sender.tag) ?? .select) }
    @objc private func copyClicked() { finish(.copy) }
    @objc private func saveClicked() { finish(.save) }
    @objc private func pinClicked() { finish(.pin) }
    @objc private func cancelClicked() { onCancel?() }
    @objc private func frameClicked(_ sender: NSButton) {
        commitText()
        let appearance = ScreenshotAppearanceView()
        if let selection, let sourceImage {
            appearance.previewImage = ScreenshotRenderer.render(source: sourceImage, size: bounds.size,
                selection: selection, annotations: annotations)
        }
        appearance.onChange = { [weak self] style in self?.screenshotStyle = style }
        let controller = NSViewController()
        controller.view = appearance
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        appearancePopover = popover
        popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .maxY)
    }
    @objc private func undo() {
        commitText()
        if let annotation = annotations.popLast() { redoAnnotations.append(annotation) }
        refreshToolbar()
        needsDisplay = true
    }
    @objc private func redo() {
        if let annotation = redoAnnotations.popLast() { annotations.append(annotation) }
        refreshToolbar()
        needsDisplay = true
    }
    @objc private func colorClicked(_ sender: NSButton) {
        commitText()
        color = Self.colors[sender.tag]
        refreshToolbar()
        window?.makeFirstResponder(self)
    }
    @objc private func widthChanged(_ sender: NSSegmentedControl) {
        commitText()
        strokeWidth = [CGFloat(2), 3, 6][sender.selectedSegment]
        window?.makeFirstResponder(self)
    }

    private static let colors: [NSColor] = [.systemRed, .systemOrange, .systemYellow, .systemGreen, .systemBlue, .white, .black]

    private func setupToolbar() {
        toolbar.material = .hudWindow
        toolbar.blendingMode = .withinWindow
        toolbar.state = .active
        toolbar.appearance = NSAppearance(named: .darkAqua)
        toolbar.wantsLayer = true
        toolbar.layer?.cornerRadius = 10
        toolbar.layer?.borderWidth = 1
        toolbar.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        toolbar.frame.size = NSSize(width: 548, height: 80)
        toolbar.isHidden = true
        addSubview(toolbar)

        var x: CGFloat = 8
        for tool in ScreenshotTool.allCases {
            let button = makeButton(tool.title, symbol: tool.symbol, action: #selector(toolClicked(_:)), x: x)
            button.tag = tool.rawValue
            button.setButtonType(.toggle)
            toolButtons.append(button)
            x += 36
        }
        x += 8
        undoButton = makeButton("Undo (⌘Z)", symbol: "arrow.uturn.backward", action: #selector(undo), x: x)
        x += 36
        redoButton = makeButton("Redo (⇧⌘Z)", symbol: "arrow.uturn.forward", action: #selector(redo), x: x)
        x += 44
        _ = makeButton("Pin screenshot", symbol: "pin", action: #selector(pinClicked), x: x)
        x += 36
        _ = makeButton("Save PNG to the screenshot folder (⌘S)", symbol: "square.and.arrow.down", action: #selector(saveClicked), x: x)
        x += 36
        _ = makeButton("Copy screenshot (Return / ⌘C)", symbol: "checkmark", action: #selector(copyClicked), x: x)
        x += 36
        _ = makeButton("Cancel (Esc)", symbol: "xmark", action: #selector(cancelClicked), x: x)

        for (index, color) in Self.colors.enumerated() {
            let button = NSButton(frame: NSRect(x: 12 + CGFloat(index) * 26, y: 10, width: 22, height: 22))
            button.title = "●"
            button.font = .systemFont(ofSize: 20)
            button.contentTintColor = color
            button.isBordered = false
            button.tag = index
            button.target = self
            button.action = #selector(colorClicked(_:))
            button.toolTip = ["Red", "Orange", "Yellow", "Green", "Blue", "White", "Black"][index]
            button.setAccessibilityLabel(button.toolTip)
            button.wantsLayer = true
            button.layer?.cornerRadius = 11
            toolbar.addSubview(button)
            colorButtons.append(button)
        }
        let widths = NSSegmentedControl(labels: ["Thin", "Medium", "Thick"], trackingMode: .selectOne,
                                        target: self, action: #selector(widthChanged(_:)))
        widths.frame = NSRect(x: 208, y: 9, width: 184, height: 24)
        widths.selectedSegment = 1
        widths.setAccessibilityLabel("Annotation stroke width")
        toolbar.addSubview(widths)
        let frameButton = NSButton(title: "Frame…", target: self, action: #selector(frameClicked(_:)))
        frameButton.bezelStyle = .rounded
        frameButton.frame = NSRect(x: 414, y: 7, width: 122, height: 28)
        frameButton.setAccessibilityLabel("Screenshot padding and corners")
        toolbar.addSubview(frameButton)
    }

    private func makeButton(_ title: String, symbol: String, action: Selector, x: CGFloat) -> NSButton {
        let button = NSButton(frame: NSRect(x: x, y: 42, width: 32, height: 30))
        button.bezelStyle = .texturedRounded
        button.isBordered = false
        button.title = ""
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        button.image?.isTemplate = true
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = .white
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.target = self
        button.action = action
        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        toolbar.addSubview(button)
        return button
    }

    private func refreshToolbar() {
        guard let selection else { toolbar.isHidden = true; return }
        toolbar.isHidden = false
        let x = min(max(selection.maxX - toolbar.frame.width, 8), max(8, bounds.maxX - toolbar.frame.width - 8))
        var y = selection.minY - toolbar.frame.height - 10
        if y < 8 { y = selection.maxY + 10 }
        if y + toolbar.frame.height > bounds.maxY - 8 { y = max(8, selection.minY + 10) }
        toolbar.setFrameOrigin(NSPoint(x: x, y: y))
        for button in toolButtons {
            button.state = button.tag == tool.rawValue ? .on : .off
            button.layer?.backgroundColor = button.state == .on
                ? NSColor.controlAccentColor.withAlphaComponent(0.5).cgColor : NSColor.clear.cgColor
        }
        for button in colorButtons {
            button.layer?.borderWidth = Self.colors[button.tag] == color ? 2 : 0
            button.layer?.borderColor = NSColor.white.cgColor
        }
        undoButton.isEnabled = !annotations.isEmpty
        redoButton.isEnabled = !redoAnnotations.isEmpty
    }

    private func drawBadge(_ text: String, at point: NSPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let rect = NSRect(x: min(point.x, bounds.maxX - size.width - 16), y: point.y,
                          width: size.width + 12, height: size.height + 8)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        (text as NSString).draw(at: NSPoint(x: rect.minX + 6, y: rect.minY + 4), withAttributes: attributes)
    }
}
