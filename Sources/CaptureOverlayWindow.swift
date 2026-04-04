import Cocoa

struct WindowCandidate {
    let windowID: CGWindowID
    let viewRect: NSRect
}

class CaptureOverlayWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        
        self.isFloatingPanel = true
        self.level = .screenSaver
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let overlayView = CaptureOverlayView(frame: contentRect)
        self.contentView = overlayView
    }
    
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

class CaptureOverlayView: NSView {
    var backgroundImage: NSImage?
    var enableMagnifier = false
    
    var windowCandidates: [WindowCandidate] = []
    var highlightedWindow: WindowCandidate?
    
    var startPoint: NSPoint?
    var currentPoint: NSPoint?
    var cursorPoint: NSPoint?
    var onCaptureRegion: ((NSRect) -> Void)?
    var onCaptureWindow: ((WindowCandidate) -> Void)?
    var onCancel: (() -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        // Setup tracking area for cursor change
        let trackingArea = NSTrackingArea(rect: self.bounds, options: [.activeAlways, .mouseMoved, .cursorUpdate], owner: self, userInfo: nil)
        self.addTrackingArea(trackingArea)
    }
    override var acceptsFirstResponder: Bool {
        return true
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if enableMagnifier, let window {
            cursorPoint = convert(window.mouseLocationOutsideOfEventStream, from: nil)
            needsDisplay = true
        }
    }
    
    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override func draw(_ dirtyRect: NSRect) {
        // Draw the frozen background image first
        if let bgImage = backgroundImage {
            bgImage.draw(in: self.bounds, from: NSRect(origin: .zero, size: bgImage.size), operation: .copy, fraction: 1.0)
        }
        
        // Create path for the darkening overlay with a hole for the selection
        let path = NSBezierPath(rect: self.bounds)
        var selectionRect: NSRect? = nil
        
        // Calculate selection
        if let start = startPoint, let current = currentPoint {
            let x = min(start.x, current.x)
            let y = min(start.y, current.y)
            let w = abs(start.x - current.x)
            let h = abs(start.y - current.y)
            
            if w > 5 && h > 5 {
                let rect = NSRect(x: x, y: y, width: w, height: h)
                selectionRect = rect
                
                // Add the hole using evenOdd winding rule
                path.append(NSBezierPath(rect: rect))
                path.windingRule = .evenOdd
            }
        }
        
        // If not dragging, try to highlight window
        if selectionRect == nil, let hwRect = highlightedWindow?.viewRect {
            selectionRect = hwRect
            path.append(NSBezierPath(rect: hwRect))
            path.windingRule = .evenOdd
        }
        
        // Fill background with semi-transparent dark color
        NSColor(white: 0.0, alpha: 0.3).set()
        path.fill()
        
        // Draw selection border
        if let rect = selectionRect {
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.white.setStroke()
            let borderPath = NSBezierPath(rect: rect)
            borderPath.lineWidth = 2.0
            borderPath.stroke()
        }

        if enableMagnifier {
            drawMagnifier()
        }
    }
    override func mouseMoved(with event: NSEvent) {
        let point = event.locationInWindow
        cursorPoint = point
        
        let oldHighlightRect = highlightedWindow?.viewRect
        highlightedWindow = nil
        
        for candidate in windowCandidates {
            if candidate.viewRect.contains(point) {
                highlightedWindow = candidate
                break
            }
        }
        
        if enableMagnifier || oldHighlightRect != highlightedWindow?.viewRect {
            needsDisplay = true
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        currentPoint = startPoint
        cursorPoint = startPoint
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        currentPoint = event.locationInWindow
        cursorPoint = currentPoint
        needsDisplay = true
    }
    
    override func mouseUp(with event: NSEvent) {
        let upPoint = event.locationInWindow
        if let start = startPoint {
            let w = abs(start.x - upPoint.x)
            let h = abs(start.y - upPoint.y)
            
            if w > 5 && h > 5 {
                let rect = NSRect(x: min(start.x, upPoint.x), y: min(start.y, upPoint.y), width: w, height: h)
                onCaptureRegion?(rect)
            } else if let highlightedWindow {
                onCaptureWindow?(highlightedWindow)
            } else {
                onCancel?()
            }
        } else {
            onCancel?()
        }
        
        startPoint = nil
        currentPoint = nil
        cursorPoint = nil
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onCancel?()
        }
    }

    private func drawMagnifier() {
        guard let backgroundImage else { return }
        guard let focusPoint = currentPoint ?? cursorPoint else { return }
        guard let context = NSGraphicsContext.current else { return }

        let lensSize: CGFloat = 160
        let zoom: CGFloat = 10
        let sourceSize = lensSize / zoom
        let sourceHalf = sourceSize / 2
        let margin: CGFloat = 16

        let maxSourceX = max(bounds.width - sourceSize, 0)
        let maxSourceY = max(bounds.height - sourceSize, 0)
        let sourceOriginX = min(max(focusPoint.x - sourceHalf, 0), maxSourceX)
        let sourceOriginY = min(max(focusPoint.y - sourceHalf, 0), maxSourceY)
        let sourceRect = NSRect(x: sourceOriginX, y: sourceOriginY, width: sourceSize, height: sourceSize)

        var lensOrigin = NSPoint(x: focusPoint.x + 28, y: focusPoint.y + 28)
        if lensOrigin.x + lensSize > bounds.maxX - margin {
            lensOrigin.x = max(focusPoint.x - lensSize - 28, margin)
        }
        if lensOrigin.y + lensSize > bounds.maxY - margin {
            lensOrigin.y = max(focusPoint.y - lensSize - 28, margin)
        }

        let lensRect = NSRect(origin: lensOrigin, size: NSSize(width: lensSize, height: lensSize))
        let borderRect = lensRect.insetBy(dx: -2, dy: -2)

        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: borderRect, xRadius: 10, yRadius: 10).fill()

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: lensRect, xRadius: 8, yRadius: 8).addClip()
        let previousInterpolation = context.imageInterpolation
        context.imageInterpolation = .none
        backgroundImage.draw(in: lensRect, from: sourceRect, operation: .copy, fraction: 1.0)
        context.imageInterpolation = previousInterpolation
        NSGraphicsContext.restoreGraphicsState()

        let centerX = lensRect.midX
        let centerY = lensRect.midY
        let crosshairPath = NSBezierPath()
        crosshairPath.move(to: NSPoint(x: centerX, y: lensRect.minY))
        crosshairPath.line(to: NSPoint(x: centerX, y: lensRect.maxY))
        crosshairPath.move(to: NSPoint(x: lensRect.minX, y: centerY))
        crosshairPath.line(to: NSPoint(x: lensRect.maxX, y: centerY))
        crosshairPath.lineWidth = 1
        NSColor.black.withAlphaComponent(0.95).setStroke()
        crosshairPath.stroke()

        if let pixelText = pixelCoordinateText(at: focusPoint) {
            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let textSize = pixelText.size(withAttributes: textAttributes)
            let textRect = NSRect(
                x: lensRect.minX,
                y: lensRect.minY - textSize.height - 10,
                width: textSize.width + 12,
                height: textSize.height + 4
            )
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: textRect, xRadius: 6, yRadius: 6).fill()
            pixelText.draw(
                in: NSRect(x: textRect.minX + 6, y: textRect.minY + 2, width: textSize.width, height: textSize.height),
                withAttributes: textAttributes
            )
        }

        let lensBorder = NSBezierPath(roundedRect: lensRect, xRadius: 8, yRadius: 8)
        lensBorder.lineWidth = 2
        NSColor.systemYellow.withAlphaComponent(0.95).setStroke()
        lensBorder.stroke()
    }

    private func pixelCoordinateText(at point: NSPoint) -> String? {
        guard let window = self.window else { return nil }
        let screenPoint = window.convertToScreen(NSRect(origin: point, size: .zero)).origin
        let scale = window.screen?.backingScaleFactor ?? 1
        let x = Int((screenPoint.x * scale).rounded())
        let y = Int((screenPoint.y * scale).rounded())
        return "x: \(x)px  y: \(y)px"
    }
}
