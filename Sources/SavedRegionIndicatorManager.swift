import Cocoa
import Carbon

final class SavedRegionIndicatorManager {
    static let shared = SavedRegionIndicatorManager()

    private var overlayWindows: [SavedRegionBorderStripWindow] = []
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var escPollingTimer: Timer?
    private var wasEscPressed = false

    private init() {}

    func show(region screenRect: NSRect) {
        if Thread.isMainThread {
            showOnMain(region: screenRect)
        } else {
            DispatchQueue.main.async {
                self.showOnMain(region: screenRect)
            }
        }
    }

    func hide() {
        if Thread.isMainThread {
            hideOnMain()
        } else {
            DispatchQueue.main.async {
                self.hideOnMain()
            }
        }
    }

    func hideAndWaitForCompositor(completion: @escaping () -> Void) {
        let execute = {
            self.hideOnMain()
            // Give WindowServer a short frame to commit the overlay removal before taking a screenshot.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                completion()
            }
        }

        if Thread.isMainThread {
            execute()
        } else {
            DispatchQueue.main.async {
                execute()
            }
        }
    }

    private func showOnMain(region screenRect: NSRect) {
        hideOnMain()
        guard screenRect.width > 5, screenRect.height > 5 else { return }
        let thickness: CGFloat = 3.0
        let r = screenRect
        let stripRects: [NSRect] = [
            // Top
            NSRect(
                x: r.minX - thickness,
                y: r.maxY,
                width: r.width + (thickness * 2),
                height: thickness
            ),
            // Bottom
            NSRect(
                x: r.minX - thickness,
                y: r.minY - thickness,
                width: r.width + (thickness * 2),
                height: thickness
            ),
            // Left
            NSRect(
                x: r.minX - thickness,
                y: r.minY,
                width: thickness,
                height: r.height
            ),
            // Right
            NSRect(
                x: r.maxX,
                y: r.minY,
                width: thickness,
                height: r.height
            )
        ]

        overlayWindows = stripRects.map { SavedRegionBorderStripWindow(contentRect: $0) }
        overlayWindows.forEach { $0.orderFrontRegardless() }
        installEscMonitors()
        startEscPollingFallback()
    }

    private func hideOnMain() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }
        escPollingTimer?.invalidate()
        escPollingTimer = nil
        wasEscPressed = false
        overlayWindows.forEach {
            $0.orderOut(nil)
            $0.close()
        }
        overlayWindows.removeAll()
    }

    private func installEscMonitors() {
        guard localKeyMonitor == nil else { return }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                ScreenshotMacroManager.shared.handleOverlayDismissedByUser()
                self?.hide()
                return nil
            }
            return event
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                ScreenshotMacroManager.shared.handleOverlayDismissedByUser()
                self?.hide()
            }
        }
    }

    private func startEscPollingFallback() {
        escPollingTimer?.invalidate()
        escPollingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let isEscPressed = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Escape))
            if isEscPressed, !self.wasEscPressed {
                ScreenshotMacroManager.shared.handleOverlayDismissedByUser()
                self.hide()
            }
            self.wasEscPressed = isEscPressed
        }
        RunLoop.main.add(escPollingTimer!, forMode: .common)
    }
}

private final class SavedRegionBorderStripWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .screenSaver
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        contentView = SavedRegionBorderStripView(frame: NSRect(origin: .zero, size: contentRect.size))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class SavedRegionBorderStripView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemYellow.withAlphaComponent(0.95).setFill()
        NSBezierPath(rect: bounds).fill()
    }
}
