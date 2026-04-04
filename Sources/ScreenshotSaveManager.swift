import Cocoa

final class ScreenshotSaveManager {
    static let shared = ScreenshotSaveManager()

    private struct SavedRegion {
        let displayID: CGDirectDisplayID
        let localRect: NSRect
    }

    private let defaults = UserDefaults.standard
    private let savedRegionDefaultsKey = "screenshot.savedRegion.v1"
    private let fileManager = FileManager.default

    private lazy var timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss_SSS"
        return formatter
    }()

    private init() {}

    func captureUsingSavedRegionOrPromptSelection() {
        captureUsingSavedRegion(showPersistentIndicator: true) { [weak self] success, _ in
            guard let self else { return }
            if success { return }
            self.selectRegionAndCaptureAndSave(showPersistentIndicator: true)
        }
    }

    func savedRegionScreenRect() -> NSRect? {
        guard let saved = loadSavedRegion() else { return nil }
        return CaptureManager.shared.screenRect(fromLocalRect: saved.localRect, on: saved.displayID)
    }

    func captureUsingSavedRegion(
        showPersistentIndicator: Bool,
        completion: @escaping (Bool, NSRect?) -> Void
    ) {
        PermissionGuideManager.shared.ensureScreenRecordingReady { [weak self] isReady in
            guard let self else {
                completion(false, nil)
                return
            }
            guard isReady else {
                PermissionGuideManager.shared.handleAuthorizedButUnavailableScreenCapture()
                completion(false, nil)
                return
            }

            SavedRegionIndicatorManager.shared.hideAndWaitForCompositor { [weak self] in
                guard let self else {
                    completion(false, nil)
                    return
                }
                guard let screenRect = self.savedRegionScreenRect(),
                      let image = CaptureManager.shared.captureImage(in: screenRect) else {
                    completion(false, nil)
                    return
                }

                self.save(image: image)
                if showPersistentIndicator {
                    SavedRegionIndicatorManager.shared.show(region: screenRect)
                    ScreenshotMacroManager.shared.showControlWindow(below: screenRect)
                } else {
                    ScreenshotMacroManager.shared.hideControlWindow()
                }
                completion(true, screenRect)
            }
        }
    }

    func selectRegionAndCaptureAndSave(showPersistentIndicator: Bool = false) {
        SavedRegionIndicatorManager.shared.hide()
        ScreenshotMacroManager.shared.hideControlWindow()

        CaptureManager.shared.startRegionCapture { [weak self] result in
            guard let self else { return }
            guard let (image, screenRect) = result else { return }
            self.persistRegion(from: screenRect)
            self.save(image: image)
            if showPersistentIndicator {
                SavedRegionIndicatorManager.shared.show(region: screenRect)
                ScreenshotMacroManager.shared.showControlWindow(below: screenRect)
            }
        }
    }

    func openSaveDirectory() {
        guard let directoryURL = try? ensureSaveDirectory() else { return }
        NSWorkspace.shared.open(directoryURL)
    }

    private func persistRegion(from screenRect: NSRect) {
        guard let screen = screenContaining(rect: screenRect),
              let displayID = CaptureManager.shared.displayID(for: screen) else { return }

        let localRect = NSRect(
            x: screenRect.origin.x - screen.frame.origin.x,
            y: screenRect.origin.y - screen.frame.origin.y,
            width: screenRect.width,
            height: screenRect.height
        )
        let payload: [String: Any] = [
            "displayID": Int(displayID),
            "x": localRect.origin.x,
            "y": localRect.origin.y,
            "width": localRect.width,
            "height": localRect.height
        ]
        defaults.set(payload, forKey: savedRegionDefaultsKey)
    }

    private func loadSavedRegion() -> SavedRegion? {
        guard let dict = defaults.dictionary(forKey: savedRegionDefaultsKey),
              let displayNumber = dict["displayID"] as? NSNumber,
              let xNumber = dict["x"] as? NSNumber,
              let yNumber = dict["y"] as? NSNumber,
              let widthNumber = dict["width"] as? NSNumber,
              let heightNumber = dict["height"] as? NSNumber else {
            return nil
        }

        let rect = NSRect(
            x: xNumber.doubleValue,
            y: yNumber.doubleValue,
            width: widthNumber.doubleValue,
            height: heightNumber.doubleValue
        )
        guard rect.width > 5, rect.height > 5 else { return nil }

        return SavedRegion(displayID: displayNumber.uint32Value, localRect: rect)
    }

    private func save(image: NSImage) {
        do {
            let directoryURL = try ensureSaveDirectory()
            let fileURL = nextOutputURL(in: directoryURL)
            try writePNG(image: image, to: fileURL)
        } catch {
            showSaveError(error)
        }
    }

    private func ensureSaveDirectory() throws -> URL {
        let picturesDirectory = fileManager.urls(for: .picturesDirectory, in: .userDomainMask).first
        let baseDirectory = picturesDirectory ?? fileManager.homeDirectoryForCurrentUser
        let targetDirectory = baseDirectory.appendingPathComponent("PinShotCaptures", isDirectory: true)
        try fileManager.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        return targetDirectory
    }

    private func nextOutputURL(in directoryURL: URL) -> URL {
        let timestamp = timestampFormatter.string(from: Date())
        var candidate = directoryURL.appendingPathComponent("PinShot_\(timestamp).png")
        var suffix = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directoryURL.appendingPathComponent("PinShot_\(timestamp)_\(suffix).png")
            suffix += 1
        }
        return candidate
    }

    private func writePNG(image: NSImage, to destinationURL: URL) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PinShot", code: 1001, userInfo: [
                NSLocalizedDescriptionKey: "Failed to encode screenshot as PNG."
            ])
        }
        try pngData.write(to: destinationURL, options: .atomic)
    }

    private func screenContaining(rect: NSRect) -> NSScreen? {
        if let exact = NSScreen.screens.first(where: { $0.frame.contains(rect) }) {
            return exact
        }
        let center = NSPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first(where: { $0.frame.contains(center) })
    }

    private func showSaveError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could Not Save Screenshot"
        alert.informativeText = (error as NSError).localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
