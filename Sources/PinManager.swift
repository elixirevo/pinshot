import Cocoa

class PinManager {
    static let shared = PinManager()
    
    private var activePins: [PinWindow] = []
    
    func pin(image: NSImage, at rect: NSRect, destination: CaptureDestination = .pin,
             recordHistory: Bool = false, historyEntry: PinHistoryEntry? = nil) {
        let pinWindow = PinWindow(image: image, frame: rect, destination: destination)
        
        // When closing, we remove from array
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: pinWindow)
        
        activePins.append(pinWindow)
        pinWindow.makeKeyAndOrderFront(nil)

        do {
            let entry = try recordHistory ? PinHistoryStore.shared.record(image: image, frame: rect) : historyEntry
            if let entry {
                pinWindow.onImageChanged = { image in
                    do { try PinHistoryStore.shared.update(id: entry.id, image: image) }
                    catch { Self.showHistoryError(error) }
                }
                if recordHistory, let error = PinHistoryStore.shared.lastRetentionError {
                    Self.showHistoryError(error, title: "Could Not Remove Old Screenshot History")
                }
            }
        } catch { Self.showHistoryError(error) }
    }
    
    func closeAll() {
        for pin in activePins {
            pin.close()
        }
        activePins.removeAll()
    }

    func finishEditing() {
        for pin in activePins { pin.finishDrawing() }
    }
    
    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? PinWindow else { return }
        NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        activePins.removeAll(where: { $0 === window })
    }

    private static func showHistoryError(_ error: Error, title: String = "Could Not Save Screenshot History") {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.runModal()
    }
}
