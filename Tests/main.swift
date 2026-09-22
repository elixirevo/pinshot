import Cocoa

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { fatalError(message) }
}

func fixture(width: Int = 800, height: Int = 600) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let offset = (y * width + x) * 4
            bytes[offset] = UInt8(x * 200 / width)
            bytes[offset + 1] = UInt8(y * 200 / height)
            bytes[offset + 2] = 130
        }
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                   bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
}

func bitmap(_ image: NSImage) -> NSBitmapImageRep { NSBitmapImageRep(data: image.tiffRepresentation!)! }
func matches(_ a: NSColor, _ b: NSColor) -> Bool {
    let a = a.colorSpace.colorSpaceModel == .rgb ? a : a.usingColorSpace(.deviceRGB)!
    let b = b.colorSpace.colorSpaceModel == .rgb ? b : b.usingColorSpace(.deviceRGB)!
    return abs(a.redComponent - b.redComponent) < 0.02 &&
        abs(a.greenComponent - b.greenComponent) < 0.02 && abs(a.blueComponent - b.blueComponent) < 0.02
}

let app = NSApplication.shared
let source = fixture()
let size = NSSize(width: 400, height: 300)
let selection = NSRect(x: 40, y: 60, width: 200, height: 120)
let sourceBitmap = NSBitmapImageRep(cgImage: source)
expect(ScreenshotGeometry.rect(from: NSPoint(x: 50, y: 60), to: NSPoint(x: 10, y: 20)) ==
       NSRect(x: 10, y: 20, width: 40, height: 40), "Reverse drag must normalize the selection")
expect(ScreenshotGeometry.pixelRect(selection, in: size, image: source) ==
       CGRect(x: 80, y: 240, width: 400, height: 240), "Retina crop must flip Y relative to the display")
expect(ScreenshotGeometry.moved(selection, by: NSSize(width: -200, height: 500),
                                within: NSRect(origin: .zero, size: size)) ==
       NSRect(x: 0, y: 180, width: 200, height: 120), "Moving a selection must clamp to display bounds")
expect(ScreenshotRenderer.render(source: source, size: size, selection: .zero, annotations: []) == nil,
       "Empty selections must not export")
let crop = ScreenshotRenderer.render(source: source, size: size, selection: selection, annotations: [])!
let cropped = bitmap(crop)
expect(cropped.pixelsWide == 400 && cropped.pixelsHigh == 240, "Unedited output must preserve Retina pixels")
expect(matches(cropped.colorAt(x: 20, y: 30)!, sourceBitmap.colorAt(x: 100, y: 270)!),
       "Crop must contain the expected original display pixels")
let annotation = ScreenshotAnnotation(tool: .rectangle,
    points: [NSPoint(x: 60, y: 80), NSPoint(x: 100, y: 110)], color: .red, lineWidth: 4)
let edited = bitmap(ScreenshotRenderer.render(source: source, size: size, selection: selection, annotations: [annotation])!)
expect(edited.pixelsWide == 400 && edited.pixelsHigh == 240, "Edited output must preserve Retina pixels")
expect(matches(edited.colorAt(x: 40, y: 170)!, .red), "Annotations must export at the same position as the preview")
expect(matches(edited.colorAt(x: 20, y: 30)!, cropped.colorAt(x: 20, y: 30)!),
       "Rendering annotations must not flip or modify the background")
var mosaic = ScreenshotAnnotation(tool: .mosaic,
    points: [NSPoint(x: 60, y: 80), NSPoint(x: 180, y: 140)], color: .red, lineWidth: 4)
mosaic.prepareMosaic(source: source, size: size)
expect(mosaic.mosaicImage?.width == 10 && mosaic.mosaicImage?.height == 5,
       "Mosaic must contain reduced-resolution pixels, not just a UI overlay")
let redacted = bitmap(ScreenshotRenderer.render(source: source, size: size, selection: selection, annotations: [mosaic])!)
expect(matches(redacted.colorAt(x: 45, y: 90)!, redacted.colorAt(x: 50, y: 90)!),
       "Mosaic pixels must be included in the exported image")
let clipped = ScreenshotRenderer.render(source: source, size: size,
    selection: NSRect(x: -10, y: -10, width: 60, height: 60), annotations: [annotation])!
expect(bitmap(clipped).pixelsWide == 100 && bitmap(clipped).pixelsHigh == 100,
       "Out-of-bounds regions must safely clip to display bounds")
let plainSource = fixture(width: 400, height: 300)
let plain = bitmap(ScreenshotRenderer.render(source: plainSource, size: size, selection: selection, annotations: [annotation])!)
expect(plain.pixelsWide == 200 && plain.pixelsHigh == 120, "1× displays must retain their native pixel dimensions")

// Native view tests exercise region selection without sending events to other apps.
let view = ScreenshotOverlayView(frame: NSRect(origin: .zero, size: size))
view.sourceImage = source
func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
    NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                      windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
}
view.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 240, y: 180)))
view.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 40, y: 60)))
view.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 40, y: 60)))
expect(view.selection == selection, "Dragging must enter the editor without immediately exporting")
var result: NSImage?
view.onFinish = { image, _, _ in result = image }
let enter = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
    windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36)!
view.keyDown(with: enter)
expect(result != nil && bitmap(result!).pixelsWide == 400, "Return must export the selected screenshot")
func key(_ code: UInt16, _ text: String, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
        windowNumber: 0, context: nil, characters: text, charactersIgnoringModifiers: text,
        isARepeat: false, keyCode: code)!
}
view.keyDown(with: key(15, "ㄱ")) // R with the Korean input source.
view.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 60, y: 80)))
view.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 100, y: 110)))
view.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 100, y: 110)))
view.keyDown(with: enter)
let annotatedPixel = bitmap(result!).colorAt(x: 40, y: 170)!
expect(!matches(annotatedPixel, cropped.colorAt(x: 40, y: 170)!), "Tool shortcuts must work with Korean input")
expect(view.performKeyEquivalent(with: key(6, "ㅋ", modifiers: .command)), "Command-Z must be handled with Korean input")
view.keyDown(with: enter)
expect(matches(bitmap(result!).colorAt(x: 40, y: 170)!, cropped.colorAt(x: 40, y: 170)!),
       "Undo must remove the annotation from the exported image")
expect(view.performKeyEquivalent(with: key(6, "ㅋ", modifiers: [.command, .shift])), "Shift-Command-Z must be handled")
view.keyDown(with: enter)
expect(matches(bitmap(result!).colorAt(x: 40, y: 170)!, annotatedPixel), "Redo must restore the annotation")
view.keyDown(with: key(9, "ㅍ")) // Select tool.
view.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 240, y: 180)))
view.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 280, y: 210)))
view.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 280, y: 210)))
expect(view.selection == NSRect(x: 40, y: 60, width: 240, height: 150), "Corner handles must resize the selection")
var cancelled = false
view.onCancel = { cancelled = true }
view.keyDown(with: key(53, ""))
expect(cancelled, "Escape must cancel the editor session")
view.resetSelection()
expect(view.selection == nil, "Reselecting must discard the previous selection")
view.windowCandidates = [WindowCandidate(windowID: 1, viewRect: NSRect(x: -20, y: 20, width: 100, height: 100))]
view.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 30, y: 40)))
view.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 30, y: 40)))
expect(view.selection == NSRect(x: 0, y: 20, width: 80, height: 100),
       "Window selection must clip windows crossing the display edge")
print("PASS: screenshot geometry, 1×/2× pixel export, annotation alignment, mosaic, region/window selection, resize, Korean shortcuts, undo/redo, Return, Escape, reset")

// Frame rendering must preserve Retina pixels and independently honor every edge.
var style = ScreenshotStyle()
style.enabled = true
style.top = 11; style.bottom = 23; style.left = 7; style.right = 19
style.cornerRadius = 0
let framed = bitmap(ScreenshotStyler.apply(style, to: crop)!)
expect(framed.pixelsWide == 426 && framed.pixelsHigh == 274, "Padding must use output pixels, not display points")
expect(matches(framed.colorAt(x: 27, y: 41)!, cropped.colorAt(x: 20, y: 30)!), "Top and left padding must preserve source pixel alignment")
expect(matches(framed.colorAt(x: 0, y: 100)!, .white), "Padding must use the configured background")
style.transparent = true
style.cornerRadius = 40
let rounded = bitmap(ScreenshotStyler.apply(style, to: crop)!)
expect(rounded.colorAt(x: 0, y: 0)!.alphaComponent == 0, "Transparent padding must preserve alpha")
expect(rounded.colorAt(x: 7, y: 11)!.alphaComponent < 0.1, "Rounded source corners must be clipped")
expect(matches(rounded.colorAt(x: 100, y: 100)!, cropped.colorAt(x: 93, y: 89)!), "Rounding must not modify interior pixels")
style.enabled = false
expect(bitmap(ScreenshotStyler.apply(style, to: crop)!).pixelsWide == 400, "Disabling the frame must return the original crop")

// History uses isolated preferences and files; no user's screenshots or settings are touched.
let testRoot = FileManager.default.temporaryDirectory.appendingPathComponent("PinShotTests-\(UUID().uuidString)")
let suite = "PinShot.Tests.\(UUID().uuidString)"
let isolatedDefaults = UserDefaults(suiteName: suite)!
let preferences = CapturePreferences(defaults: isolatedDefaults)
let indexDirectory = testRoot.appendingPathComponent("History")
let pinDirectory = testRoot.appendingPathComponent("Pins")
preferences.setDirectory(pinDirectory, for: .pin)
preferences.setDirectory(testRoot.appendingPathComponent("Editor"), for: .screenshot)
preferences.setDirectory(testRoot.appendingPathComponent("Macro"), for: .macro)
expect(Set(CaptureDestination.allCases.map { preferences.directory(for: $0) }).count == 3, "Capture types need independent save destinations")
expect(CapturePreferences(defaults: isolatedDefaults).directory(for: .pin).path == pinDirectory.path, "Chosen directories must persist")
let history = PinHistoryStore(preferences: preferences, indexDirectory: indexDirectory)
let historyFrame = NSRect(x: 20, y: 40, width: 200, height: 120)
let historyEntry = try! history.record(image: crop, frame: historyFrame)!
expect(historyEntry.imageURL.deletingLastPathComponent().path == pinDirectory.path, "History PNGs must use the configured pin folder")
let reloaded = PinHistoryStore(preferences: preferences, indexDirectory: indexDirectory)
expect(reloaded.entries.count == 1 && reloaded.entries[0].id == historyEntry.id, "History must survive restarting the store")
expect(bitmap(reloaded.image(for: historyEntry)!).pixelsWide == 400, "History must retain Retina resolution")
preferences.pinHistoryEnabled = false
let skipped = try! history.record(image: crop, frame: historyFrame)
expect(skipped == nil && history.entries.count == 1, "Turning history off must stop new saves and preserve existing captures")
preferences.pinHistoryEnabled = true
preferences.setDirectory(testRoot.appendingPathComponent("NewPins"), for: .pin)
let newEntry = try! history.record(image: crop, frame: historyFrame)!
expect(newEntry.imageURL.deletingLastPathComponent().lastPathComponent == "NewPins", "New captures must honor a changed folder")
expect(history.image(for: historyEntry) != nil, "Changing folders must not break old history")
let saver = ScreenshotSaveManager(preferences: preferences)
for destination in CaptureDestination.allCases {
    let output = try! saver.saveScreenshot(image: crop, destination: destination)
    expect(output.deletingLastPathComponent().path == preferences.directory(for: destination).path,
           "Each saver must write to its selected destination")
    expect(bitmap(NSImage(contentsOf: output)!).pixelsWide == 400, "Saving must preserve image resolution")
}
let blockedDirectory = testRoot.appendingPathComponent("not-a-directory")
try! Data("file".utf8).write(to: blockedDirectory)
preferences.setDirectory(blockedDirectory.appendingPathComponent("Macro"), for: .macro)
do {
    _ = try saver.saveScreenshot(image: crop, destination: .macro)
    fatalError("An unusable save directory must report failure, not silently save elsewhere")
} catch {}
let updatedImage = NSImage(cgImage: fixture(width: 400, height: 240), size: historyFrame.size)
try! history.update(id: historyEntry.id, image: updatedImage)
expect(matches(bitmap(history.image(for: historyEntry)!).colorAt(x: 10, y: 10)!, bitmap(updatedImage).colorAt(x: 10, y: 10)!), "Edited history images must be saved to disk")
let badIndex = testRoot.appendingPathComponent("BadIndex")
try! FileManager.default.createDirectory(at: badIndex, withIntermediateDirectories: true)
try! Data("broken".utf8).write(to: badIndex.appendingPathComponent("index.json"))
let damaged = PinHistoryStore(preferences: preferences, indexDirectory: badIndex)
do {
    _ = try damaged.record(image: crop, frame: historyFrame)
    fatalError("A damaged history index must not be silently overwritten")
} catch {}
try! FileManager.default.removeItem(at: testRoot)
isolatedDefaults.removePersistentDomain(forName: suite)

let pinCanvas = PinDrawingView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
pinCanvas.configure(image: crop) // Displayed at 2× the image's logical point size.
pinCanvas.tool = .rectangle
pinCanvas.color = .red
pinCanvas.strokeWidth = 3
pinCanvas.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 40, y: 40)))
pinCanvas.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 120, y: 100)))
pinCanvas.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 120, y: 100)))
let pinEdited = bitmap(pinCanvas.renderedImage()!)
expect(pinEdited.pixelsWide == 400 && pinEdited.pixelsHigh == 240, "Pin drawing must retain source resolution after window resizing")
expect(matches(pinEdited.colorAt(x: 40, y: 170)!, .red), "Pin drawing must map resized window coordinates onto the source")
pinCanvas.undoStroke()
expect(matches(bitmap(pinCanvas.renderedImage()!).colorAt(x: 40, y: 170)!, cropped.colorAt(x: 40, y: 170)!), "Pin drawing undo must restore original pixels")
pinCanvas.redoStroke()
expect(matches(bitmap(pinCanvas.renderedImage()!).colorAt(x: 40, y: 170)!, .red), "Pin drawing redo must restore the annotation")
print("PASS: asymmetric padding, rounded alpha, Retina export, separate folders and save errors, persistent history, history opt-out, folder changes, edited history, corrupt-index protection, pin drawing/undo/redo")

try testHistoryRetention()

if CommandLine.arguments.contains("--preview") || Bundle.main.bundleIdentifier == "com.elixirevo.PinShot.EditorPreview" {
    app.setActivationPolicy(.regular)
    let frame = NSRect(x: 100, y: 100, width: 1050, height: 720)
    let window = CaptureOverlayWindow(contentRect: frame, screenshotEditor: true)
    window.styleMask = [.titled, .closable]
    window.level = .normal
    window.isFloatingPanel = false
    window.title = "PinShot Screenshot Editor Test"
    let editor = window.contentView as! ScreenshotOverlayView
    let image = fixture(width: 2100, height: 1440)
    editor.sourceImage = image
    editor.backgroundImage = NSImage(cgImage: image, size: frame.size)
    editor.windowCandidates = [WindowCandidate(windowID: 1, viewRect: NSRect(x: 180, y: 180, width: 620, height: 360))]
    editor.onCancel = { app.terminate(nil) }
    editor.onFinish = { image, _, output in
        let directory = Bundle.main.bundleIdentifier == "com.elixirevo.PinShot.EditorPreview"
            ? Bundle.main.bundleURL.deletingLastPathComponent()
            : URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".build")
        let url = directory.appendingPathComponent("editor-preview.png")
        try! bitmap(image).representation(using: .png, properties: [:])!.write(to: url)
        print("Exported \(output): \(url.path)")
        app.terminate(nil)
    }
    window.contentView = editor
    window.acceptsMouseMovedEvents = true
    window.makeKeyAndOrderFront(nil)
    window.makeFirstResponder(editor)
    app.activate(ignoringOtherApps: true)
    app.run()
}
