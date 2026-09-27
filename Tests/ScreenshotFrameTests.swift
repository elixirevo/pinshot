import Cocoa

private func frameDescendants<T: NSView>(_ type: T.Type, in view: NSView) -> [T] {
    (view as? T).map { [$0] } ?? [] + view.subviews.flatMap { frameDescendants(type, in: $0) }
}

func testScreenshotFrames() throws {
    let legacy = Data("""
        {"enabled":true,"top":11,"bottom":23,"left":7,"right":19,"cornerRadius":31,
         "transparent":true,"red":0.25,"green":0.5,"blue":0.75}
        """.utf8)
    let migrated = try JSONDecoder().decode(ScreenshotStyle.self, from: legacy)
    expect(migrated.paddingEnabled && migrated.cornersEnabled && migrated.radii == [31, 31, 31, 31],
           "Existing frame preferences must preserve enabled state and all corner radii")
    expect(migrated.top == 11 && migrated.right == 19 && migrated.transparent,
           "Migrating corner settings must preserve padding and background")
    var style = ScreenshotStyle()
    style.cornersEnabled = true
    style.cornerRadius = 0
    let image = NSImage(cgImage: fixture(width: 128, height: 96), size: NSSize(width: 64, height: 48))
    let pixels = [(2, 2), (125, 2), (2, 93), (125, 93)]
    for corner in ScreenshotCorner.allCases {
        style.cornerRadius = 0
        style.setRadius(24, for: corner)
        let result = bitmap(ScreenshotStyler.apply(style, to: image)!)
        expect(result.pixelsWide == 128 && result.pixelsHigh == 96, "Rounding alone must not add padding")
        for (index, point) in pixels.enumerated() {
            expect((result.colorAt(x: point.0, y: point.1)!.alphaComponent < 0.1) == (index == corner.rawValue),
                   "Each corner must round independently without rotating or rounding another corner")
        }
        expect(matches(result.colorAt(x: 64, y: 48)!, bitmap(image).colorAt(x: 64, y: 48)!),
               "Rounding must preserve interior source pixels")
    }
    style.cornersEnabled = false
    style.paddingEnabled = true
    style.top = 11; style.bottom = 23; style.left = 7; style.right = 19
    let padded = bitmap(ScreenshotStyler.apply(style, to: image)!)
    expect(padded.pixelsWide == 154 && padded.pixelsHigh == 130, "Independent padding must preserve each edge in output pixels")
    expect(matches(padded.colorAt(x: 9, y: 13)!, bitmap(image).colorAt(x: 2, y: 2)!),
           "Disabling corners must restore square image corners while keeping padding")
    expect(matches(padded.colorAt(x: 0, y: 0)!, .white), "Opaque padding must use its background color")
    style.cornersEnabled = true
    style.topLeftRadius = 200
    style.topRightRadius = 12
    style.bottomLeftRadius = 0
    style.bottomRightRadius = 30
    style.transparent = true
    let combined = bitmap(ScreenshotStyler.apply(style, to: image)!)
    expect(combined.colorAt(x: 7, y: 11)!.alphaComponent < 0.1, "Oversized radii must safely clamp to the image size")
    let decoded = try JSONDecoder().decode(ScreenshotStyle.self, from: JSONEncoder().encode(style))
    expect(decoded == style, "Independent toggles, radii, and padding must survive persistence")
    let livePath = ScreenshotStyler.roundedPath(in: NSRect(x: 0, y: 0, width: 64, height: 48), style: style, pixelScale: 2)
    let exportPath = ScreenshotStyler.roundedPath(in: NSRect(x: 0, y: 0, width: 128, height: 96), style: style)
    for point in [CGPoint(x: 2, y: 2), CGPoint(x: 3, y: 45), CGPoint(x: 60, y: 45), CGPoint(x: 32, y: 24)] {
        expect(livePath.contains(point) == exportPath.contains(CGPoint(x: point.x * 2, y: point.y * 2)),
               "Retina preview and export must use identical corner geometry")
    }

    let suite = "PinShot.FrameTests.\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = CapturePreferences(defaults: defaults)
    let window = CaptureOverlayWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), screenshotEditor: true)
    let editor = window.contentView as! ScreenshotOverlayView
    editor.screenshotPreferences = preferences
    editor.sourceImage = fixture(width: 1600, height: 1200)
    editor.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 150, y: 150)))
    editor.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 650, y: 450)))
    editor.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 650, y: 450)))
    let selected = editor.selection
    expect(frameDescendants(ScreenshotCornerControlsView.self, in: editor).isEmpty,
           "Corner controls must stay inside Frame, not above the selected range")
    let frameButton = frameDescendants(NSButton.self, in: editor).first { $0.title == "Frame…" }!
    frameButton.performClick(nil)
    let appearance = frameDescendants(ScreenshotAppearanceView.self, in: editor).first!
    let cornerControls = frameDescendants(ScreenshotCornerControlsView.self, in: appearance).first!
    let roundButton = frameDescendants(NSButton.self, in: cornerControls).first { $0.title == "Rounded corners" }!
    roundButton.performClick(nil)
    let segment = frameDescendants(NSSegmentedControl.self, in: cornerControls).first!
    segment.selectedSegment = 2 // Top right.
    segment.sendAction(segment.action, to: segment.target)
    let radiusSlider = frameDescendants(NSSlider.self, in: cornerControls).first!
    radiusSlider.doubleValue = 72
    radiusSlider.sendAction(radiusSlider.action, to: radiusSlider.target)
    expect(editor.screenshotStyle.topRightRadius == 72 && editor.screenshotStyle.topLeftRadius == 12,
           "The Frame slider must update only the selected corner")
    expect(editor.screenshotStyle.cornersEnabled && !editor.screenshotStyle.paddingEnabled,
           "Enabling rounded corners in Frame must not enable padding")
    let padding = frameDescendants(NSButton.self, in: appearance).first { $0.title == "Padding" }!
    padding.performClick(nil)
    let colorButton = frameDescendants(NSButton.self, in: appearance).first { $0.title == "Color…" }!
    colorButton.performClick(nil)
    let picker = frameDescendants(ScreenshotColorPickerView.self, in: appearance).first!
    expect(!picker.isHidden && picker.window === window && window.level == .screenSaver,
           "Color controls must appear inside the active top-level capture window")
    let red = frameDescendants(NSSlider.self, in: picker).first!
    red.doubleValue = 0
    red.sendAction(red.action, to: red.target)
    expect(editor.screenshotStyle.red == 0 && editor.screenshotStyle.green == 1,
           "Color changes must immediately reach the selected screenshot style")
    expect(editor.screenshotStyle.topRightRadius == 72, "Padding and color changes must preserve corner radii")
    var exported = false
    editor.onFinish = { _, _, _ in exported = true }
    editor.keyDown(with: key(36, "\r"))
    expect(!exported && editor.selection == selected, "Return inside the Frame panel must not finish or reset the capture")
    let hex = frameDescendants(NSTextField.self, in: picker).first { $0.isEditable }!
    window.makeFirstResponder(hex)
    let fieldEditor = window.firstResponder as! NSTextView
    _ = window.performKeyEquivalent(with: key(0, "a", modifiers: .command))
    expect(fieldEditor.selectedRange().length == fieldEditor.string.utf16.count && editor.selection == selected,
           "Command-A inside color inputs must select text without selecting the entire screen")
    expect(picker.control(hex, textView: fieldEditor, doCommandBy: #selector(NSResponder.insertNewline(_:))),
           "Return in a color field must be consumed as an edit, not an export")
    expect(editor.dismissFramePanelIfNeeded() && editor.selection == selected,
           "Escape must close Frame controls while retaining the selected region")
    editor.keyDown(with: key(36, "\r"))
    expect(exported, "Return must export again once Frame controls are dismissed")
    expect(preferences.screenshotStyle.topRightRadius == 72 && preferences.screenshotStyle.red == 0,
           "Frame controls must persist independent values")
    expect(frameDescendants(ScreenshotCornerControlsView.self, in: editor).isEmpty,
           "Closing Frame must remove the corner controls from the selection screen")

    editor.backgroundImage = NSImage(cgImage: editor.sourceImage!, size: editor.bounds.size)
    func drawSelection() -> NSBitmapImageRep {
        let result = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 800, pixelsHigh: 600,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: result)
        editor.draw(editor.bounds)
        NSGraphicsContext.restoreGraphicsState()
        return result
    }
    let withPadding = drawSelection()
    let savedStyle = editor.screenshotStyle
    editor.screenshotStyle.paddingEnabled = false
    let withoutPadding = drawSelection()
    for point in [(145, 300), (655, 300), (400, 145), (400, 455), (180, 280)] {
        expect(matches(withPadding.colorAt(x: point.0, y: point.1)!, withoutPadding.colorAt(x: point.0, y: point.1)!),
               "Padding and its background must not be drawn inside or around the selected range")
    }
    editor.screenshotStyle = savedStyle

    // Render the actual overlay on black so any stale rectangular border is visible.
    let savedBackground = editor.backgroundImage
    let savedSource = editor.sourceImage
    editor.backgroundImage = NSImage(size: editor.bounds.size, flipped: false) { rect in
        NSColor.black.setFill()
        rect.fill()
        return true
    }
    let squareCorners = [NSPoint(x: 150, y: 450), NSPoint(x: 650, y: 450),
                         NSPoint(x: 150, y: 150), NSPoint(x: 650, y: 150)]
    let roundedCorners = [NSPoint(x: 173, y: 427), NSPoint(x: 627, y: 427),
                          NSPoint(x: 173, y: 173), NSPoint(x: 627, y: 173)]
    func hasOutline(_ rendered: NSBitmapImageRep, near point: NSPoint) -> Bool {
        for x in (Int(point.x) - 2)...(Int(point.x) + 2) {
            for y in (Int(point.y) - 2)...(Int(point.y) + 2) {
                let color = rendered.colorAt(x: x, y: 599 - y)!.usingColorSpace(.deviceRGB)!
                if max(color.redComponent, color.greenComponent, color.blueComponent) > 0.1 { return true }
            }
        }
        return false
    }
    for scale in [1, 2] {
        editor.sourceImage = fixture(width: 800 * scale, height: 600 * scale)
        for corner in ScreenshotCorner.allCases {
            var outlineStyle = ScreenshotStyle()
            outlineStyle.cornersEnabled = true
            outlineStyle.cornerRadius = 0
            outlineStyle.setRadius(Double(80 * scale), for: corner)
            editor.screenshotStyle = outlineStyle
            let rounded = drawSelection()
            for index in squareCorners.indices {
                expect(hasOutline(rounded, near: squareCorners[index]) == (index != corner.rawValue),
                       "Only the adjusted corner must lose its square border, including the inherited capture outline")
            }
            expect(hasOutline(rounded, near: roundedCorners[corner.rawValue]),
                   "The visible outline must follow the adjusted corner curve at both 1× and 2×")
            editor.screenshotStyle.cornersEnabled = false
            let square = drawSelection()
            expect(hasOutline(square, near: squareCorners[corner.rawValue]) &&
                   !hasOutline(square, near: roundedCorners[corner.rawValue]),
                   "Disabling rounding must restore the square border and remove the curved outline")
        }
    }
    editor.backgroundImage = savedBackground
    editor.sourceImage = savedSource
    editor.screenshotStyle = savedStyle

    // A new capture reloads the persisted values, even through a fresh preferences instance.
    let nextEditor = ScreenshotOverlayView(frame: editor.bounds)
    nextEditor.screenshotPreferences = CapturePreferences(defaults: UserDefaults(suiteName: suite)!)
    nextEditor.sourceImage = editor.sourceImage
    expect(nextEditor.screenshotStyle == savedStyle && !nextEditor.isSelectionLocked,
           "The next capture must remember every frame setting while allowing its first range selection")
    nextEditor.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 150, y: 150)))
    nextEditor.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 650, y: 450)))
    nextEditor.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 650, y: 450)))
    var nextImage: NSImage?
    nextEditor.onFinish = { image, _, _ in nextImage = image }
    nextEditor.keyDown(with: key(36, "\r"))
    let nextPixels = bitmap(nextImage!)
    expect(nextPixels.pixelsWide == 1048 && nextPixels.pixelsHigh == 648,
           "Remembered padding must still be included in export despite being hidden during selection")
    expect(matches(nextPixels.colorAt(x: 0, y: 0)!, .cyan), "The next capture must export the remembered background color")
    window.orderOut(nil)
    print("PASS: frame migration, independent corners in Frame, live rounded outlines at 1×/2×, hidden selection padding, Retina export, embedded color inputs, Return/Escape, remembered settings across captures")
}
