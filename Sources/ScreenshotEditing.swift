import Cocoa

enum ScreenshotTool: Int, CaseIterable {
    case select, rectangle, ellipse, arrow, pen, text, mosaic

    var title: String {
        ["Select (V)", "Rectangle (R)", "Ellipse (O)", "Arrow (A)",
         "Pen (P)", "Text (T)", "Mosaic (M)"][rawValue]
    }

    var symbol: String {
        ["cursorarrow", "rectangle", "oval", "arrow.up.right", "pencil.tip",
         "textformat", "square.grid.3x3.fill"][rawValue]
    }
}

enum ScreenshotOutput {
    case copy, save, pin
}

enum ScreenshotGeometry {
    static func rect(from start: NSPoint, to end: NSPoint) -> NSRect {
        NSRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    static func clamped(_ point: NSPoint, to bounds: NSRect) -> NSPoint {
        NSPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    static func moved(_ rect: NSRect, by delta: NSSize, within bounds: NSRect) -> NSRect {
        NSRect(x: min(max(rect.minX + delta.width, bounds.minX), bounds.maxX - rect.width),
               y: min(max(rect.minY + delta.height, bounds.minY), bounds.maxY - rect.height),
               width: rect.width, height: rect.height)
    }

    // AppKit uses a bottom-left origin; captured display pixels use a top-left origin.
    static func pixelRect(_ rect: NSRect, in size: NSSize, image: CGImage) -> CGRect {
        let scaleX = CGFloat(image.width) / size.width
        let scaleY = CGFloat(image.height) / size.height
        return CGRect(x: rect.minX * scaleX, y: (size.height - rect.maxY) * scaleY,
                      width: rect.width * scaleX, height: rect.height * scaleY)
            .integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
}

struct ScreenshotAnnotation {
    let tool: ScreenshotTool
    var points: [NSPoint]
    let color: NSColor
    let lineWidth: CGFloat
    var text = ""
    var mosaicImage: CGImage?

    var rect: NSRect {
        ScreenshotGeometry.rect(from: points.first ?? .zero, to: points.last ?? .zero)
    }

    func draw() {
        guard let start = points.first, let end = points.last else { return }
        color.setStroke()
        color.setFill()
        let path = NSBezierPath()
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        switch tool {
        case .select:
            return
        case .rectangle:
            path.appendRect(rect)
        case .ellipse:
            path.appendOval(in: rect)
        case .arrow:
            path.move(to: start)
            path.line(to: end)
            let angle = atan2(end.y - start.y, end.x - start.x)
            let length = min(max(lineWidth * 4, 12), hypot(end.x - start.x, end.y - start.y) * 0.5)
            for offset in [CGFloat.pi / 6, -CGFloat.pi / 6] {
                path.move(to: end)
                path.line(to: NSPoint(x: end.x - cos(angle + offset) * length,
                                      y: end.y - sin(angle + offset) * length))
            }
        case .pen:
            if points.count == 1 {
                NSBezierPath(ovalIn: NSRect(x: start.x - lineWidth / 2, y: start.y - lineWidth / 2,
                                            width: lineWidth, height: lineWidth)).fill()
                return
            }
            path.move(to: start)
            for point in points.dropFirst() { path.line(to: point) }
        case .text:
            (text as NSString).draw(at: start, withAttributes: [
                .font: NSFont.systemFont(ofSize: max(18, lineWidth * 6), weight: .semibold),
                .foregroundColor: color
            ])
            return
        case .mosaic:
            guard let mosaicImage else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.imageInterpolation = .none
            NSImage(cgImage: mosaicImage, size: rect.size).draw(in: rect)
            NSGraphicsContext.restoreGraphicsState()
            return
        }
        path.stroke()
    }

    mutating func prepareMosaic(source: CGImage, size: NSSize) {
        guard tool == .mosaic, rect.width > 0, rect.height > 0,
              let crop = source.cropping(to: ScreenshotGeometry.pixelRect(rect, in: size, image: source)) else { return }
        let width = max(1, Int(rect.width / 12))
        let height = max(1, Int(rect.height / 12))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        context.interpolationQuality = .low
        context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))
        mosaicImage = context.makeImage()
    }
}

enum ScreenshotRenderer {
    static func render(source: CGImage, size: NSSize, selection: NSRect,
                       annotations: [ScreenshotAnnotation]) -> NSImage? {
        let selection = selection.intersection(NSRect(origin: .zero, size: size))
        guard selection.width > 5, selection.height > 5,
              let cropped = source.cropping(to: ScreenshotGeometry.pixelRect(selection, in: size, image: source)) else { return nil }
        if annotations.isEmpty { return NSImage(cgImage: cropped, size: selection.size) }
        let colorSpace = source.colorSpace?.model == .rgb ? source.colorSpace! : CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: nil, width: cropped.width, height: cropped.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x: CGFloat(cropped.width) / selection.width, y: CGFloat(cropped.height) / selection.height)
        context.draw(cropped, in: CGRect(origin: .zero, size: selection.size))
        context.translateBy(x: -selection.minX, y: -selection.minY)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for annotation in annotations { annotation.draw() }
        NSGraphicsContext.restoreGraphicsState()
        guard let result = context.makeImage() else { return nil }
        return NSImage(cgImage: result, size: selection.size)
    }
}
