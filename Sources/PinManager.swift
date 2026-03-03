import Cocoa

class PinManager {
    static let shared = PinManager()
    
    private var activePins: [PinWindow] = []
    
    func pin(image: NSImage, at rect: NSRect) {
        let pinWindow = PinWindow(image: image, frame: rect)
        
        // When closing, we remove from array
        NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose(_:)), name: NSWindow.willCloseNotification, object: pinWindow)
        
        activePins.append(pinWindow)
        pinWindow.makeKeyAndOrderFront(nil)
    }
    
    func closeAll() {
        for pin in activePins {
            pin.close()
        }
        activePins.removeAll()
    }
    
    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? PinWindow else { return }
        activePins.removeAll(where: { $0 === window })
    }
}
