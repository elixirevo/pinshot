import Cocoa

class CaptureManager {
    static let shared = CaptureManager()
    
    private var overlayWindows: [CaptureOverlayWindow] = []
    private var localEventMonitor: Any?
    private var isCapturing = false

    private enum SelectionMode {
        case regionOrWindow
        case regionOnly
    }
    
    func startCapture(completion: @escaping ((NSImage, NSRect)?) -> Void) {
        PermissionGuideManager.shared.ensureScreenRecordingReady { [weak self] isReady in
            guard let self else {
                completion(nil)
                return
            }
            guard isReady else {
                PermissionGuideManager.shared.handleAuthorizedButUnavailableScreenCapture()
                completion(nil)
                return
            }
            self.startCapture(selectionMode: .regionOrWindow, completion: completion)
        }
    }

    func startRegionCapture(completion: @escaping ((NSImage, NSRect)?) -> Void) {
        PermissionGuideManager.shared.ensureScreenRecordingReady { [weak self] isReady in
            guard let self else {
                completion(nil)
                return
            }
            guard isReady else {
                PermissionGuideManager.shared.handleAuthorizedButUnavailableScreenCapture()
                completion(nil)
                return
            }
            self.startCapture(selectionMode: .regionOnly, completion: completion)
        }
    }

    func captureImage(in screenRect: NSRect) -> NSImage? {
        guard screenRect.width > 5, screenRect.height > 5 else { return nil }
        guard let screen = screenContaining(rect: screenRect),
              let cgImage = getScreenCGImage(screen) else { return nil }

        let localRect = NSRect(
            x: screenRect.origin.x - screen.frame.origin.x,
            y: screenRect.origin.y - screen.frame.origin.y,
            width: screenRect.width,
            height: screenRect.height
        )
        return cropCGImage(cgImage, sourceFrame: screen.frame, cropRectInWindow: localRect)
    }

    func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        return CGDirectDisplayID(screenNumber.uint32Value)
    }

    func screen(for displayIDValue: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { displayID(for: $0) == displayIDValue }
    }

    func screenRect(fromLocalRect localRect: NSRect, on displayID: CGDirectDisplayID) -> NSRect? {
        guard let screen = screen(for: displayID) else { return nil }
        let translatedRect = NSRect(
            x: screen.frame.origin.x + localRect.origin.x,
            y: screen.frame.origin.y + localRect.origin.y,
            width: localRect.width,
            height: localRect.height
        )
        let bounded = translatedRect.intersection(screen.frame)
        guard bounded.width > 5, bounded.height > 5 else { return nil }
        return bounded
    }
    
    private func cleanup() {
        isCapturing = false
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        for window in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
    }

    private func startCapture(
        selectionMode: SelectionMode,
        completion: @escaping ((NSImage, NSRect)?) -> Void
    ) {
        guard overlayWindows.isEmpty, !isCapturing else { return }
        isCapturing = true
        var preparedOverlay = false

        for screen in NSScreen.screens {
            // Capture the screen immediately for the frozen effect.
            guard let cgImage = getScreenCGImage(screen) else { continue }
            preparedOverlay = true
            let bgImage = NSImage(cgImage: cgImage, size: screen.frame.size)
            
            let window = CaptureOverlayWindow(contentRect: screen.frame)
            self.overlayWindows.append(window)
            
            if let view = window.contentView as? CaptureOverlayView {
                view.backgroundImage = bgImage
                view.enableMagnifier = (selectionMode == .regionOnly)
                view.windowCandidates = (selectionMode == .regionOrWindow) ? getVisibleWindowCandidates(for: screen, in: view) : []
                
                view.onCancel = { [weak self] in
                    self?.cleanup()
                }
                view.onCaptureRegion = { [weak self, weak window] rectInWindow in
                    guard let self = self, let win = window else { return }
                    let screenRect = win.convertToScreen(rectInWindow)
                    let finalImage = self.cropCGImage(cgImage, sourceFrame: screen.frame, cropRectInWindow: rectInWindow)
                    self.cleanup()
                    if let image = finalImage {
                        completion((image, screenRect))
                    } else {
                        completion(nil)
                    }
                }

                if selectionMode == .regionOrWindow {
                    view.onCaptureWindow = { [weak self, weak window] candidate in
                        guard let self = self, let win = window else { return }
                        let screenRect = win.convertToScreen(candidate.viewRect)
                        let finalImage = self.captureWindowCGImage(windowID: candidate.windowID, targetSize: screenRect.size)
                        self.cleanup()
                        if let image = finalImage {
                            completion((image, screenRect))
                        } else {
                            completion(nil)
                        }
                    }
                } else {
                    view.onCaptureWindow = nil
                }
            }
            
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(window.contentView)
        }

        guard preparedOverlay else {
            cleanup()
            completion(nil)
            return
        }
        
        NSApp.activate(ignoringOtherApps: true)
        
        if localEventMonitor == nil {
            localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 53 { // ESC
                    self?.cleanup()
                    return nil
                }
                return event
            }
        }
    }
    
    private func getVisibleWindowCandidates(for screen: NSScreen, in view: NSView) -> [WindowCandidate] {
        let desktopTopY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let currentPID = Int32(ProcessInfo.processInfo.processIdentifier)
        
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let windowInfoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        
        var candidates: [WindowCandidate] = []
        for info in windowInfoList {
            let layer = info[kCGWindowLayer as String] as? Int ?? -1
            // Standard windows are usually layer 0.
            if layer > 0 { continue }
            let isOnScreen = (info[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
            if !isOnScreen { continue }
            let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1.0
            if alpha < 0.05 { continue }
            let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1
            if ownerPID == currentPID { continue }

            guard let windowNumber = info[kCGWindowNumber as String] as? NSNumber else { continue }
            
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            
            // Skip tiny elements.
            if bounds.width < 50 || bounds.height < 50 { continue }

            // Convert CoreGraphics bounds to AppKit global coordinates.
            let appKitY = desktopTopY - bounds.origin.y - bounds.height
            let globalRect = NSRect(
                x: bounds.origin.x,
                y: appKitY,
                width: bounds.width,
                height: bounds.height
            )
            
            if globalRect.intersects(screen.frame) {
                if let window = view.window {
                    let windowRect = window.convertFromScreen(globalRect)
                    let viewRect = view.convert(windowRect, from: nil)
                    let candidate = WindowCandidate(
                        windowID: CGWindowID(windowNumber.uint32Value),
                        viewRect: viewRect
                    )
                    candidates.append(candidate)
                }
            }
        }
        return candidates
    }

    private func screenContaining(rect: NSRect) -> NSScreen? {
        if let exact = NSScreen.screens.first(where: { $0.frame.contains(rect) }) {
            return exact
        }
        let center = NSPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })
    }
    
    private func getScreenCGImage(_ screen: NSScreen) -> CGImage? {
        guard let displayID = displayID(for: screen) else { return nil }
        return CGDisplayCreateImage(displayID)
    }
    
    private func cropCGImage(_ cgImage: CGImage, sourceFrame: NSRect, cropRectInWindow: NSRect) -> NSImage? {
        // cropRectInWindow is in points from bottom-left of the window.
        // cgImage is in pixels from top-left.
        let scaleX = CGFloat(cgImage.width) / sourceFrame.width
        let scaleY = CGFloat(cgImage.height) / sourceFrame.height
        
        let cropX = cropRectInWindow.origin.x * scaleX
        // View coordinates are bottom-left, CGImage is top-left.
        let cropY = (sourceFrame.height - cropRectInWindow.origin.y - cropRectInWindow.height) * scaleY
        let cropW = cropRectInWindow.width * scaleX
        let cropH = cropRectInWindow.height * scaleY
        
        let cropCGRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
        
        guard let croppedCGImage = cgImage.cropping(to: cropCGRect) else { return nil }
        return NSImage(cgImage: croppedCGImage, size: cropRectInWindow.size)
    }

    private func captureWindowCGImage(windowID: CGWindowID, targetSize: NSSize) -> NSImage? {
        let options = CGWindowListOption.optionIncludingWindow
        let imageOptions: CGWindowImageOption = [.bestResolution, .boundsIgnoreFraming]
        guard let cgImage = CGWindowListCreateImage(.null, options, windowID, imageOptions) else { return nil }
        return NSImage(cgImage: cgImage, size: targetSize)
    }
}
