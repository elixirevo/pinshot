import Cocoa
import VisionKit

class PinWindow: NSPanel, NSWindowDelegate {
    private(set) var image: NSImage
    let destination: CaptureDestination
    var onImageChanged: ((NSImage) -> Void)?
    private let drawingView = PinDrawingView()
    private var drawingToolbar: PinDrawingToolbar?
    private var isDrawing = false
    
    private let imageView = NSImageView()
    private let overlayView = PinOverlayView()
    private var textAnalysisTask: Task<Void, Never>?
    private var textSelectionContext: AnyObject?
    private var localKeyMonitor: Any?
    
    init(image: NSImage, frame: NSRect, destination: CaptureDestination = .pin) {
        self.image = image
        self.destination = destination
        
        let styleMask: NSWindow.StyleMask = [
            .titled,
            .fullSizeContentView,
            .resizable
        ]
        
        super.init(contentRect: frame, styleMask: styleMask, backing: .buffered, defer: false)
        
        self.titlebarAppearsTransparent = true
        self.title = "Pinned Screenshot"
        self.titleVisibility = .hidden
        self.standardWindowButton(.closeButton)?.isHidden = true
        self.standardWindowButton(.miniaturizeButton)?.isHidden = true
        self.standardWindowButton(.zoomButton)?.isHidden = true
        self.showsToolbarButton = false
        
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = false
        self.hidesOnDeactivate = false
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        let minContentSize = NSSize(width: 176, height: 96)
        self.contentMinSize = minContentSize
        self.minSize = self.frameRect(forContentRect: NSRect(origin: .zero, size: minContentSize)).size
        
        self.delegate = self
        if frame.width < minContentSize.width || frame.height < minContentSize.height {
            setContentSize(NSSize(width: max(frame.width, minContentSize.width), height: max(frame.height, minContentSize.height)))
        }
        setupViews()
        installLocalCopyShortcutMonitor()
    }
    
    private func setupViews() {
        let containerView = NSView(frame: self.contentRect(forFrameRect: self.frame))
        self.contentView = containerView
        
        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.frame = containerView.bounds
        imageView.autoresizingMask = [.width, .height]
        containerView.addSubview(imageView)

        if #available(macOS 13.0, *) {
            let context = TextSelectionContext()
            context.overlay.frame = imageView.bounds
            context.overlay.autoresizingMask = [.width, .height]
            context.overlay.trackingImageView = imageView
            context.overlay.preferredInteractionTypes = .textSelection
            containerView.addSubview(context.overlay)
            textSelectionContext = context
        }
        
        drawingView.configure(image: image)
        drawingView.frame = containerView.bounds
        drawingView.autoresizingMask = [.width, .height]
        drawingView.isHidden = true
        drawingView.onChange = { [weak self] in self?.drawingToolbar?.refresh() }
        containerView.addSubview(drawingView)

        overlayView.frame = containerView.bounds
        overlayView.autoresizingMask = [.width, .height]
        containerView.addSubview(overlayView)
        
        overlayView.onClose = { [weak self] in
            self?.close()
        }
        
        overlayView.onCopy = { [weak self] in self?.copyImage() }
        overlayView.onSave = { [weak self] in self?.saveImage() }
        overlayView.onDraw = { [weak self] in self?.toggleDrawing() }
        overlayView.onHistory = { PinHistoryWindowController.shared.showHistory() }

        configureTextSelectionIfAvailable()
    }
    
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            if NSApp.isActive == false {
                NSApp.activate(ignoringOtherApps: true)
            }
            makeKeyAndOrderFront(nil)
            if isDrawing {
                makeFirstResponder(drawingView)
            } else if #available(macOS 13.0, *),
               let context = textSelectionContext as? TextSelectionContext {
                makeFirstResponder(context.overlay)
            }
        default:
            break
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleDrawingKey(event) { return true }
        if isCopyShortcut(event) {
            if !isDrawing && copySelectedTextFromOverlay() { return true }
            copyImage()
            return true
        }
        if event.modifierFlags.contains(.command), event.keyCode == 1 {
            saveImage()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if handleDrawingKey(event) { return }
        super.keyDown(with: event)
    }

    private func handleDrawingKey(_ event: NSEvent) -> Bool {
        guard isDrawing else { return false }
        if event.keyCode == 53 { toggleDrawing(); return true }
        if event.modifierFlags.contains(.command), event.keyCode == 6 {
            event.modifierFlags.contains(.shift) ? drawingView.redoStroke() : drawingView.undoStroke()
            return true
        }
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return false }
        let tools: [UInt16: ScreenshotTool] = [35: .pen, 15: .rectangle, 31: .ellipse, 0: .arrow, 46: .mosaic]
        guard let tool = tools[event.keyCode] else { return false }
        drawingView.tool = tool
        drawingToolbar?.refresh()
        return true
    }

    private var currentImage: NSImage { isDrawing ? drawingView.renderedImage() ?? image : image }

    private func copyImage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([currentImage])
    }

    private func saveImage() {
        do {
            _ = try ScreenshotSaveManager.shared.saveScreenshot(image: currentImage, destination: destination)
        } catch { showError(error, title: "Could Not Save Screenshot") }
    }

    private func toggleDrawing() {
        if isDrawing {
            finishDrawing()
            return
        }
        isDrawing = true
        drawingView.configure(image: image)
        drawingView.isHidden = false
        if #available(macOS 13.0, *), let context = textSelectionContext as? TextSelectionContext {
            context.overlay.isHidden = true
        }
        let toolbar = drawingToolbar ?? PinDrawingToolbar(canvas: drawingView)
        toolbar.onDone = { [weak self] in self?.finishDrawing() }
        drawingToolbar = toolbar
        toolbar.refresh()
        addChildWindow(toolbar, ordered: .above)
        positionDrawingToolbar()
        toolbar.orderFront(nil)
        overlayView.setDrawing(true)
        makeFirstResponder(drawingView)
    }

    func finishDrawing() {
        guard isDrawing else { return }
        if drawingView.hasEdits, let edited = drawingView.renderedImage() {
            image = edited
            imageView.image = edited
            onImageChanged?(edited)
            configureTextSelectionIfAvailable()
        }
        isDrawing = false
        drawingView.isHidden = true
        if let drawingToolbar { removeChildWindow(drawingToolbar); drawingToolbar.orderOut(nil) }
        if #available(macOS 13.0, *), let context = textSelectionContext as? TextSelectionContext {
            context.overlay.isHidden = false
        }
        overlayView.setDrawing(false)
    }

    private func positionDrawingToolbar() {
        guard isDrawing, let toolbar = drawingToolbar, let visible = screen?.visibleFrame else { return }
        var origin = NSPoint(x: frame.midX - toolbar.frame.width / 2, y: frame.minY - toolbar.frame.height - 8)
        if origin.y < visible.minY { origin.y = min(frame.maxY + 8, visible.maxY - toolbar.frame.height) }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - toolbar.frame.width)
        toolbar.setFrameOrigin(origin)
    }

    func windowDidMove(_ notification: Notification) { positionDrawingToolbar() }
    func windowDidResize(_ notification: Notification) { positionDrawingToolbar() }

    override func close() {
        finishDrawing()
        super.close()
    }

    private func showError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.beginSheetModal(for: self)
    }

    deinit {
        if let monitor = localKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        textAnalysisTask?.cancel()
    }

    private func configureTextSelectionIfAvailable() {
        guard #available(macOS 13.0, *) else { return }
        guard let context = textSelectionContext as? TextSelectionContext else { return }

        textAnalysisTask?.cancel()
        textAnalysisTask = Task { [weak self] in
            guard let self = self else { return }
            let configuration = ImageAnalyzer.Configuration([.text])
            do {
                let analysis = try await context.analyzer.analyze(self.image, orientation: .up, configuration: configuration)
                if Task.isCancelled { return }
                await MainActor.run {
                    context.overlay.analysis = analysis
                    context.overlay.preferredInteractionTypes = .textSelection
                }
            } catch {
                // Ignore OCR analysis failures; image pinning still works.
            }
        }
    }

    private func copySelectedTextFromOverlay() -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        guard let context = textSelectionContext as? TextSelectionContext else { return false }

        if #available(macOS 14.0, *) {
            let selected = context.overlay.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if selected.isEmpty == false {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(selected, forType: .string)
                return true
            }
        }

        let copySelector = NSSelectorFromString("copy:")
        if context.overlay.tryToPerform(copySelector, with: self) {
            return true
        }
        if NSApp.sendAction(copySelector, to: context.overlay, from: self) {
            return true
        }
        return NSApp.sendAction(copySelector, to: nil, from: self)
    }

    private func installLocalCopyShortcutMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.isKeyWindow, !self.isDrawing else { return event }
            if self.isCopyShortcut(event) {
                return self.copySelectedTextFromOverlay() ? nil : event
            }
            return event
        }
    }

    private func isCopyShortcut(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        if event.keyCode == 8 { return true } // kVK_ANSI_C
        return event.charactersIgnoringModifiers?.lowercased() == "c"
    }
}

@available(macOS 13.0, *)
private final class TextSelectionContext: NSObject {
    let analyzer = ImageAnalyzer()
    let overlay = ImageAnalysisOverlayView()
}

final class PinOverlayView: NSView {
    var onClose: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onDraw: (() -> Void)?
    var onHistory: (() -> Void)?
    private var drawButton: PinControlButton!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let actions: [(String, String, Selector)] = [
            ("xmark", "Close pin", #selector(closeClicked)),
            ("doc.on.doc", "Copy screenshot (⌘C)", #selector(copyClicked)),
            ("square.and.arrow.down", "Save screenshot (⌘S)", #selector(saveClicked)),
            ("pencil.tip", "Draw on screenshot", #selector(drawClicked)),
            ("clock.arrow.circlepath", "Screenshot history", #selector(historyClicked))
        ]
        for (index, item) in actions.enumerated() {
            let button = PinControlButton(symbol: item.0, label: item.1, target: self, action: item.2)
            button.translatesAutoresizingMaskIntoConstraints = false
            addSubview(button)
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6 + CGFloat(index) * 32),
                button.topAnchor.constraint(equalTo: topAnchor, constant: 6),
                button.widthAnchor.constraint(equalToConstant: 28),
                button.heightAnchor.constraint(equalToConstant: 28)
            ])
            if index == 3 { drawButton = button }
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setDrawing(_ drawing: Bool) {
        drawButton.state = drawing ? .on : .off
        drawButton.needsDisplay = true
    }

    @objc private func closeClicked() { onClose?() }
    @objc private func copyClicked() { onCopy?() }
    @objc private func saveClicked() { onSave?() }
    @objc private func drawClicked() { onDraw?() }
    @objc private func historyClicked() { onHistory?() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        return view === self ? nil : view
    }
}
