import AppKit

@MainActor
enum Mark {
    /// Drawn on an 18 pt canvas, y up.
    private static func strokes(scale s: CGFloat, waiting: Bool) -> (outline: NSBezierPath, liquid: NSBezierPath, details: NSBezierPath) {
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
        let outline = NSBezierPath()
        outline.move(to: p(6.2, 16))
        outline.line(to: p(11.8, 16))
        outline.move(to: p(7.3, 16))
        outline.line(to: p(7.3, 11.4))
        outline.line(to: p(3.2, 4.6))
        outline.curve(to: p(4.6, 2.2), controlPoint1: p(2.6, 3.6), controlPoint2: p(3.3, 2.2))
        outline.line(to: p(13.4, 2.2))
        outline.curve(to: p(14.8, 4.6), controlPoint1: p(14.7, 2.2), controlPoint2: p(15.4, 3.6))
        outline.line(to: p(10.7, 11.4))
        outline.line(to: p(10.7, 16))

        let liquid = NSBezierPath()
        liquid.move(to: p(4.9, 7.4))
        liquid.curve(to: p(9, 7.4), controlPoint1: p(6.2, 8.4), controlPoint2: p(7.7, 6.4))
        liquid.curve(to: p(13.1, 7.4), controlPoint1: p(10.3, 8.4), controlPoint2: p(11.8, 6.4))

        let details = NSBezierPath()
        details.move(to: p(7.4, 5.0))
        details.curve(to: p(10.6, 5.0), controlPoint1: p(8.2, 3.9), controlPoint2: p(9.8, 3.9))
        if !waiting { details.appendOval(in: NSRect(x: 12.6 * s, y: 12.4 * s, width: 1.8 * s, height: 1.8 * s)) }
        for path in [outline, liquid, details] {
            path.lineWidth = 1.5 * s
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
        }
        return (outline, liquid, details)
    }

    static func menuBarIcon(waiting: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let (outline, liquid, details) = strokes(scale: 1, waiting: waiting)
            NSColor.black.set()
            [outline, liquid, details].forEach { $0.stroke() }
            if waiting { NSBezierPath(ovalIn: NSRect(x: 12.8, y: 12.8, width: 4.8, height: 4.8)).fill() }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = waiting ? "Meme Lab: an agent is waiting for your pick" : "Meme Lab"
        return image
    }

    static func header(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let (outline, liquid, details) = strokes(scale: size / 18, waiting: false)
            NSColor.labelColor.set()
            [outline, liquid, details].forEach { $0.stroke() }
            return true
        }
        return image
    }

    static func appIcon() -> NSImage {
        NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { _ in
            let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
            let shape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
            NSGradient(starting: NSColor(white: 0.22, alpha: 1), ending: NSColor(white: 0.07, alpha: 1))?.draw(in: shape, angle: -90)
            let scale: CGFloat = 30
            let size = 18 * scale
            NSGraphicsContext.current?.cgContext.translateBy(x: 512 - size / 2, y: 512 - size / 2 - 10)
            let (outline, liquid, details) = strokes(scale: scale, waiting: false)
            let fill = NSBezierPath()
            fill.append(liquid)
            fill.line(to: NSPoint(x: 14.2 * scale, y: 5.2 * scale))
            fill.line(to: NSPoint(x: 13.4 * scale, y: 2.2 * scale))
            fill.line(to: NSPoint(x: 4.6 * scale, y: 2.2 * scale))
            fill.line(to: NSPoint(x: 3.8 * scale, y: 5.2 * scale))
            fill.close()
            NSGraphicsContext.saveGraphicsState()
            outline.addClip()
            NSColor(white: 1, alpha: 0.22).set()
            fill.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.set()
            [outline, liquid, details].forEach { $0.stroke() }
            return true
        }
    }

    static func writeAppIcon(to url: URL) -> Int32 {
        let image = appIcon()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]), (try? png.write(to: url)) != nil
        else { return 1 }
        return 0
    }
}
