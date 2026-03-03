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
    
    var windowCandidates: [WindowCandidate] = []
    var highlightedWindow: WindowCandidate?
    
    var startPoint: NSPoint?
    var currentPoint: NSPoint?
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
    }
    override func mouseMoved(with event: NSEvent) {
        let point = event.locationInWindow
        
        let oldHighlightRect = highlightedWindow?.viewRect
        highlightedWindow = nil
        
        for candidate in windowCandidates {
            if candidate.viewRect.contains(point) {
                highlightedWindow = candidate
                break
            }
        }
        
        if oldHighlightRect != highlightedWindow?.viewRect {
            needsDisplay = true
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        startPoint = event.locationInWindow
        currentPoint = startPoint
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        currentPoint = event.locationInWindow
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
    }
    
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onCancel?()
        }
    }
}
