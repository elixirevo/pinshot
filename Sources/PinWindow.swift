import Cocoa
import VisionKit

class PinWindow: NSPanel {
    let image: NSImage
    
    private let imageView = NSImageView()
    private let overlayView = PinOverlayView()
    private var textAnalysisTask: Task<Void, Never>?
    private var textSelectionContext: AnyObject?
    private var localKeyMonitor: Any?
    
    init(image: NSImage, frame: NSRect) {
        self.image = image
        
        let styleMask: NSWindow.StyleMask = [
            .titled,
            .fullSizeContentView,
            .resizable
        ]
        
        super.init(contentRect: frame, styleMask: styleMask, backing: .buffered, defer: false)
        
        self.titlebarAppearsTransparent = true
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
        let minContentSize = NSSize(width: 120, height: 80)
        self.contentMinSize = minContentSize
        self.minSize = self.frameRect(forContentRect: NSRect(origin: .zero, size: minContentSize)).size
        
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
        
        overlayView.frame = containerView.bounds
        overlayView.autoresizingMask = [.width, .height]
        containerView.addSubview(overlayView)
        
        overlayView.onClose = { [weak self] in
            self?.close()
        }
        
        overlayView.onCopy = { [weak self] in
            guard let self = self else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([self.image])
        }

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
            if #available(macOS 13.0, *),
               let context = textSelectionContext as? TextSelectionContext {
                makeFirstResponder(context.overlay)
            }
        default:
            break
        }
        super.sendEvent(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if isCopyShortcut(event) {
            if copySelectedTextFromOverlay() {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if isCopyShortcut(event), copySelectedTextFromOverlay() {
            return
        }
        super.keyDown(with: event)
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
            guard let self = self, self.isKeyWindow else { return event }
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

class PinOverlayView: NSView {
    var onClose: (() -> Void)?
    var onCopy: (() -> Void)?
    
    private let closeBtn = NSButton()
    private let copyBtn = NSButton()
    
    private var trackingArea: NSTrackingArea?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupButtons()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupButtons() {
        closeBtn.title = "X"
        closeBtn.bezelStyle = .circular
        closeBtn.target = self
        closeBtn.action = #selector(closeClicked)
        closeBtn.translatesAutoresizingMaskIntoConstraints = false
        closeBtn.alphaValue = 0.0
        
        copyBtn.title = "Copy"
        copyBtn.bezelStyle = .roundRect
        copyBtn.target = self
        copyBtn.action = #selector(copyClicked)
        copyBtn.translatesAutoresizingMaskIntoConstraints = false
        copyBtn.alphaValue = 0.0
        
        addSubview(closeBtn)
        addSubview(copyBtn)
        
        NSLayoutConstraint.activate([
            closeBtn.topAnchor.constraint(equalTo: self.topAnchor, constant: 4),
            closeBtn.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 4),
            closeBtn.widthAnchor.constraint(equalToConstant: 24),
            closeBtn.heightAnchor.constraint(equalToConstant: 24),
            
            copyBtn.topAnchor.constraint(equalTo: self.topAnchor, constant: 4),
            copyBtn.leadingAnchor.constraint(equalTo: closeBtn.trailingAnchor, constant: 4),
            copyBtn.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    @objc private func closeClicked() {
        onClose?()
    }
    
    @objc private func copyClicked() {
        onCopy?()
        
        // Visual feedback
        let originalTitle = "Copy"
        copyBtn.title = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.copyBtn.title = originalTitle
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        if let ta = trackingArea {
            addTrackingArea(ta)
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            closeBtn.animator().alphaValue = 1.0
            copyBtn.animator().alphaValue = 1.0
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            closeBtn.animator().alphaValue = 0.0
            copyBtn.animator().alphaValue = 0.0
        }
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        if view == self {
            return nil // Pass through to window background for dragging
        }
        return view
    }
}
