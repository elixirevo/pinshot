import Cocoa

extension Notification.Name {
    static let pinHistoryChanged = Notification.Name("PinShot.pinHistoryChanged")
}

struct PinHistoryEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let imagePath: String
    let frame: CGRect
    var pixelWidth: Int
    var pixelHeight: Int

    var imageURL: URL { URL(fileURLWithPath: imagePath) }
}

final class PinHistoryStore {
    static let shared = PinHistoryStore()
    private let preferences: CapturePreferences
    private let indexURL: URL
    private(set) var entries: [PinHistoryEntry] = []
    private(set) var loadError: Error?
    private(set) var lastRetentionError: Error?

    init(preferences: CapturePreferences = .shared, indexDirectory: URL? = nil) {
        self.preferences = preferences
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        indexURL = (indexDirectory ?? support.appendingPathComponent("PinShot/History", isDirectory: true))
            .appendingPathComponent("index.json")
        if FileManager.default.fileExists(atPath: indexURL.path) {
            do {
                entries = try JSONDecoder().decode([PinHistoryEntry].self, from: Data(contentsOf: indexURL))
                // The index is newest-first. Keep insertion order even if the system clock changes.
            } catch { loadError = error }
        }
    }

    @discardableResult
    func record(image: NSImage, frame: NSRect) throws -> PinHistoryEntry? {
        lastRetentionError = nil
        guard preferences.pinHistoryEnabled else { return nil }
        // A damaged index must not be silently replaced by an empty history.
        if let loadError { throw loadError }
        let directory = preferences.directory(for: .pin)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = UUID()
        let url = directory.appendingPathComponent("PinShot_\(id.uuidString).png")
        let bitmap = try encodedImage(image)
        try bitmap.data.write(to: url, options: .atomic)
        let entry = PinHistoryEntry(id: id, date: Date(), imagePath: url.path, frame: frame,
                                    pixelWidth: bitmap.width, pixelHeight: bitmap.height)
        let updated = [entry] + entries
        do { try writeIndex(updated) }
        catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        entries = updated
        // Save the new capture and index before removing any older capture.
        enforceRetention()
        NotificationCenter.default.post(name: .pinHistoryChanged, object: self)
        return entry
    }

    private func enforceRetention() {
        guard let limit = preferences.pinHistoryRetention.maximumCount, entries.count > limit else { return }
        var retained = entries
        for entry in entries.suffix(entries.count - limit).reversed() {
            do {
                try removeHistoryImage(entry)
                retained.removeLast()
            } catch {
                // Keep failed removals indexed so a later capture can retry, in FIFO order.
                lastRetentionError = error
                break
            }
        }
        guard retained.count != entries.count else { return }
        do {
            try writeIndex(retained)
            entries = retained
        } catch {
            // The previously saved index still contains the new capture. Missing old PNGs
            // are safely removed from that index on the next successful cleanup.
            lastRetentionError = error
        }
    }

    private func removeHistoryImage(_ entry: PinHistoryEntry) throws {
        let url = entry.imageURL
        guard url.lastPathComponent == "PinShot_\(entry.id.uuidString).png" else {
            throw NSError(domain: "PinShot.History", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "The old history file has an unexpected name and was not deleted: \(url.path)"
            ])
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            // Never recursively delete a directory that replaced one of our PNGs.
            guard let type = attributes[.type] as? FileAttributeType, type == .typeRegular || type == .typeSymbolicLink else {
                throw NSError(domain: "PinShot.History", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "The old history path is no longer an image file and was not deleted: \(url.path)"
                ])
            }
            try FileManager.default.removeItem(at: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain &&
            (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
            // A PNG already moved or deleted by the user should not block retention.
        }
    }

    func image(for entry: PinHistoryEntry) -> NSImage? {
        guard let image = NSImage(contentsOf: entry.imageURL) else { return nil }
        image.size = entry.frame.size
        return image
    }

    func update(id: UUID, image: NSImage) throws {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let bitmap = try encodedImage(image)
        try bitmap.data.write(to: entries[index].imageURL, options: .atomic)
        var updated = entries
        updated[index].pixelWidth = bitmap.width
        updated[index].pixelHeight = bitmap.height
        try writeIndex(updated)
        entries = updated
        NotificationCenter.default.post(name: .pinHistoryChanged, object: self)
    }

    private func writeIndex(_ entries: [PinHistoryEntry]) throws {
        try FileManager.default.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(entries).write(to: indexURL, options: .atomic)
    }

    private func encodedImage(_ image: NSImage) throws -> (data: Data, width: Int, height: Int) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let data = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PinShot.History", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not encode the screenshot for history."])
        }
        return (data, cgImage.width, cgImage.height)
    }
}
