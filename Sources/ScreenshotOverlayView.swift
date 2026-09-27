import Cocoa
import Carbon

/// A frozen-screen editor. Coordinates stay in display points until the final pixel export.
final class ScreenshotOverlayView: CaptureOverlayView, NSTextFieldDelegate {
    override var drawsSelectionBorder: Bool { selection == nil }
    var sourceImage: CGImage?
    var screenshotPreferences = CapturePreferences.shared {
        didSet { screenshotStyle = screenshotPreferences.screenshotStyle }
    }
    var onActivate: (() -> Void)?
    var onSelectionCommitted: (() -> Void)?
    var onFinish: ((NSImage, NSRect, ScreenshotOutput) -> Void)?
    var screenshotStyle = ScreenshotStyle() {
        didSet { needsDisplay = true }
    }
    private var framePanel: ScreenshotChromeView?

    private(set) var selection: NSRect?
    private(set) var isSelectionLocked = false
    private var tool: ScreenshotTool = .select
    private var color = NSColor.systemRed
    private var strokeWidth: CGFloat = 3
    private var annotations: [ScreenshotAnnotation] = []
    private var redoAnnotations: [ScreenshotAnnotation] = []
    private var pendingAnnotation: ScreenshotAnnotation?
    private var dragOrigin: NSPoint?
    private var isSelecting = false
    private var textField: NSTextField?
    private var textOrigin: NSPoint?
    private let toolbar = ScreenshotChromeView()
    private var toolButtons: [NSButton] = []
    private var colorButtons: [NSButton] = []
    private var undoButton: NSButton!
    private var redoButton: NSButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        enableMagnifier = true
        screenshotStyle = screenshotPreferences.screenshotStyle
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
            drawStyledSelection(selection)

            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.setStrokeColor(CaptureOverlayAppearance.borderColor.cgColor)
                context.setLineWidth(1.5)
                context.addPath(selectionOutline(in: selection))
                context.strokePath()
                context.restoreGState()
            }
            let pixels = sourceImage.map { ScreenshotGeometry.pixelRect(selection, in: bounds.size, image: $0) }
            let width = Int(pixels?.width ?? selection.width)
            let height = Int(pixels?.height ?? selection.height)
            let label = "\(width) × \(height) px"
            drawBadge(label, at: NSPoint(x: selection.minX, y: min(selection.maxY + 8, bounds.maxY - 30)))
        }
        if selection == nil && !isSelectionLocked {
            drawBadge("Drag an area or click a window  ·  Esc to cancel", at: NSPoint(x: 20, y: 24))
        }
    }

    override func mouseMoved(with event: NSEvent) {
        cursorPoint = convert(event.locationInWindow, from: nil)
        if selection == nil && !isSelectionLocked {
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
        if dismissFramePanelIfNeeded() { return }
        // Other displays remain frozen once a capture has been selected.
        if selection == nil && isSelectionLocked { onActivate?(); return }
        commitText()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        let point = ScreenshotGeometry.clamped(convert(event.locationInWindow, from: nil), to: bounds)
        cursorPoint = point
        if let selection {
            guard selection.contains(point) else { return }
            if tool == .select {
                if event.clickCount == 2 { finish(.copy) }
                return
            }
            if tool == .text { beginText(at: point); return }
            dragOrigin = point
            pendingAnnotation = ScreenshotAnnotation(tool: tool, points: [point], color: color, lineWidth: strokeWidth)
        } else {
            onActivate?()
            beginSelection(at: point)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let origin = dragOrigin else { return }
        let point = ScreenshotGeometry.clamped(convert(event.locationInWindow, from: nil), to: bounds)
        cursorPoint = point
        if isSelecting {
            selection = ScreenshotGeometry.rect(from: origin, to: point)
            enableMagnifier = false
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
        if isSelecting && selection != nil { commitSelection() }
        pendingAnnotation = nil
        dragOrigin = nil
        isSelecting = false
        highlightedWindow = nil
        enableMagnifier = selection == nil && !isSelectionLocked
        refreshToolbar()
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        if dismissFramePanelIfNeeded() { return }
        if !isSelectionLocked { onCancel?() }
    }

    override func keyDown(with event: NSEvent) {
        if handleKey(event) { return }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Let the field editor own normal text editing shortcuts while entering a label.
        if event.keyCode == UInt16(kVK_Escape), dismissFramePanelIfNeeded() { return true }
        if let fieldEditor = window?.firstResponder as? NSTextView, fieldEditor.isFieldEditor {
            // This menu-bar app has no Edit menu to supply these native text shortcuts.
            if event.modifierFlags.contains(.command), event.modifierFlags.intersection([.option, .control]).isEmpty {
                switch event.keyCode {
                case UInt16(kVK_ANSI_A): fieldEditor.selectAll(nil)
                case UInt16(kVK_ANSI_C): fieldEditor.copy(nil)
                case UInt16(kVK_ANSI_X): fieldEditor.cut(nil)
                case UInt16(kVK_ANSI_V): fieldEditor.paste(nil)
                case UInt16(kVK_ANSI_Z):
                    if event.modifierFlags.contains(.shift) { fieldEditor.undoManager?.redo() }
                    else { fieldEditor.undoManager?.undo() }
                default: return false
                }
                return true
            }
            return false
        }
        if textField != nil || framePanel != nil || isFrameControlFocused { return super.performKeyEquivalent(with: event) }
        return handleKey(event) || super.performKeyEquivalent(with: event)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == UInt16(kVK_Escape) {
            if !dismissFramePanelIfNeeded() { onCancel?() }
            return true
        }
        if framePanel != nil || isFrameControlFocused { return false }
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
                guard !isSelectionLocked else { return true }
                commitText()
                onActivate?()
                selection = bounds
                commitSelection()
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
        if selection != nil {
            if [kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow].contains(Int(event.keyCode)) { return true }
            let keys: [String: ScreenshotTool] = ["v": .select, "r": .rectangle, "o": .ellipse,
                "a": .arrow, "p": .pen, "t": .text, "m": .mosaic]
            guard let selectedTool = keys[key] else { return false }
            selectTool(selectedTool)
            return true
        }
        return false
    }

    func resetSelection() {
        guard !isSelectionLocked else { return }
        closeFramePanel()
        textField?.removeFromSuperview()
        textField = nil
        textOrigin = nil
        selection = nil
        annotations.removeAll()
        redoAnnotations.removeAll()
        pendingAnnotation = nil
        dragOrigin = nil
        isSelecting = false
        highlightedWindow = nil
        startPoint = nil
        currentPoint = nil
        tool = .select
        enableMagnifier = true
        toolbar.isHidden = true
        needsDisplay = true
    }

    private func beginSelection(at point: NSPoint) {
        guard !isSelectionLocked else { return }
        resetSelection()
        dragOrigin = point
        isSelecting = true
    }

    func lockSelection() {
        isSelectionLocked = true
        isSelecting = false
        dragOrigin = nil
        highlightedWindow = nil
        enableMagnifier = false
        needsDisplay = true
    }

    private func commitSelection() {
        guard selection != nil, !isSelectionLocked else { return }
        lockSelection()
        onSelectionCommitted?()
    }

    private func updateCursor(at point: NSPoint) {
        if (!toolbar.isHidden && toolbar.frame.contains(point)) || framePanel?.frame.contains(point) == true {
            NSCursor.arrow.set(); return
        }
        if isSelectionLocked && (tool == .select || selection?.contains(point) != true) { NSCursor.arrow.set() }
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
        if framePanel != nil { closeFramePanel(); return }
        commitText()
        let appearance = ScreenshotAppearanceView(preferences: screenshotPreferences)
        appearance.configure(screenshotStyle)
        if let selection, let sourceImage {
            appearance.previewImage = ScreenshotRenderer.render(source: sourceImage, size: bounds.size,
                selection: selection, annotations: annotations)
        }
        appearance.onChange = { [weak self] style in self?.screenshotStyle = style }
        let panel = ScreenshotChromeView(frame: NSRect(x: 0, y: 0, width: 370, height: 420))
        configureChrome(panel)
        let title = NSTextField(labelWithString: "Screenshot Frame")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.frame = NSRect(x: 16, y: 391, width: 280, height: 20)
        panel.addSubview(title)
        let close = NSButton(image: NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close frame controls")!, target: self, action: #selector(closeFramePanel))
        close.bezelStyle = .circular
        close.frame = NSRect(x: 332, y: 388, width: 26, height: 26)
        close.setAccessibilityLabel("Close frame controls")
        panel.addSubview(close)
        appearance.frame.origin = .zero
        panel.addSubview(appearance)
        framePanel = panel
        addSubview(panel)
        positionFramePanel()
    }

    private var isFrameControlFocused: Bool {
        guard let responder = window?.firstResponder else { return false }
        let input = (responder as? NSTextView)?.delegate as? NSView
        guard let view = input ?? responder as? NSView else { return false }
        return framePanel.map { view.isDescendant(of: $0) } == true
    }

    /// Used by the capture session's Escape monitor before it cancels the capture.
    @discardableResult func dismissFramePanelIfNeeded() -> Bool {
        if framePanel != nil { closeFramePanel(); return true }
        if isFrameControlFocused { window?.makeFirstResponder(self); return true }
        return false
    }

    @objc private func closeFramePanel() {
        if framePanel != nil { window?.makeFirstResponder(self) }
        framePanel?.removeFromSuperview()
        framePanel = nil
    }

    private func configureChrome(_ view: NSVisualEffectView) {
        view.material = .hudWindow
        view.blendingMode = .withinWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
    }

    private func positionFramePanel() {
        guard let panel = framePanel else { return }
        let aboveToolbar = toolbar.frame.maxY + 8
        let y = aboveToolbar + panel.frame.height <= bounds.maxY - 8
            ? aboveToolbar : toolbar.frame.minY - panel.frame.height - 8
        panel.setFrameOrigin(NSPoint(
            x: min(max(toolbar.frame.maxX - panel.frame.width, 8), max(8, bounds.width - panel.frame.width - 8)),
            y: min(max(y, 8), max(8, bounds.height - panel.frame.height - 8))))
    }

    private func selectionOutline(in selection: NSRect) -> CGPath {
        let scale = CGFloat(sourceImage?.width ?? Int(bounds.width)) / max(bounds.width, 1)
        return ScreenshotStyler.roundedPath(in: selection, style: screenshotStyle, pixelScale: scale)
    }

    private func drawStyledSelection(_ selection: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        // Re-dim the original rectangular hole, then reveal only the rounded image.
        NSColor.black.withAlphaComponent(0.3).setFill()
        selection.fill()
        // Padding belongs to the Frame preview and exported image, never the selection overlay.
        if let context = NSGraphicsContext.current?.cgContext {
            context.addPath(selectionOutline(in: selection))
            context.clip()
        }
        if let backgroundImage {
            backgroundImage.draw(in: bounds, from: NSRect(origin: .zero, size: backgroundImage.size), operation: .copy, fraction: 1)
        }
        for annotation in annotations { annotation.draw() }
        pendingAnnotation?.draw()
        NSGraphicsContext.restoreGraphicsState()
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
        _ = makeButton("스크린샷을 클립보드에 복사하고 닫기 (Enter / ⌘C)", symbol: "doc.on.doc", action: #selector(copyClicked), x: x)
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
        frameButton.setAccessibilityLabel("Screenshot padding, corners, and background")
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
        positionFramePanel()
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

/// Empty toolbar space must not start a new screenshot selection.
private final class ScreenshotChromeView: NSVisualEffectView {
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
}
