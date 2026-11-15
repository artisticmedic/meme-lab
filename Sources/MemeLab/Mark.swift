import AppKit

@MainActor
enum Mark {
    /// The flask's glass, open at the neck, on an 18 pt canvas with y up. The lip across the neck is drawn separately.
    private static func glass(scale s: CGFloat) -> NSBezierPath {
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
        let glass = NSBezierPath()
        glass.move(to: p(7.3, 16))
        glass.line(to: p(7.3, 11.4))
        glass.line(to: p(3.2, 4.6))
        glass.curve(to: p(4.6, 2.2), controlPoint1: p(2.6, 3.6), controlPoint2: p(3.3, 2.2))
        glass.line(to: p(13.4, 2.2))
        glass.curve(to: p(14.8, 4.6), controlPoint1: p(14.7, 2.2), controlPoint2: p(15.4, 3.6))
        glass.line(to: p(10.7, 11.4))
        glass.line(to: p(10.7, 16))
        glass.move(to: p(6.2, 16))
        glass.line(to: p(11.8, 16))
        return glass
    }

    private static func strokes(scale s: CGFloat, waiting: Bool) -> (outline: NSBezierPath, liquid: NSBezierPath, details: NSBezierPath) {
        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
        let outline = glass(scale: s)

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
            func hex(_ v: Int, _ a: CGFloat = 1) -> NSColor {
                NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
            }
            let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
            NSGradient(starting: hex(0x0E0F12), ending: hex(0x2A2D33))?.draw(in: tile, angle: 90)

            let s: CGFloat = 30
            func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s, y: y * s) }
            func bubble(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: NSColor) {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: (x - r) * s, y: (y - r) * s, width: 2 * r * s, height: 2 * r * s)).fill()
            }
            NSGraphicsContext.current?.cgContext.translateBy(x: 512 - 9 * s, y: 512 - 9 * s - 40)

            let outline = glass(scale: s)
            outline.lineWidth = 1.5 * s
            outline.lineCapStyle = .round
            outline.lineJoinStyle = .round

            let liquid = NSBezierPath()
            liquid.move(to: p(2, 7.6))
            liquid.curve(to: p(9, 7.6), controlPoint1: p(4.5, 8.7), controlPoint2: p(6.5, 6.5))
            liquid.curve(to: p(16, 7.6), controlPoint1: p(11.5, 8.7), controlPoint2: p(13.5, 6.5))
            liquid.line(to: p(16, 0))
            liquid.line(to: p(2, 0))
            liquid.close()

            let green = hex(0xB6FF5C)
            NSGraphicsContext.saveGraphicsState()
            // Clipping fills the glass: the lip's stray segment encloses no area, and the open neck closes itself.
            outline.addClip()
            NSGradient(starting: green, ending: hex(0x22C55E))?.draw(in: liquid, angle: -90)
            bubble(7.2, 5.0, 0.75, hex(0xFFFFFF, 0.55))
            bubble(10.4, 3.9, 0.5, hex(0xFFFFFF, 0.45))
            bubble(9.3, 9.4, 0.42, green)
            NSGraphicsContext.restoreGraphicsState()
            bubble(9.6, 18.0, 0.62, green)
            bubble(11.6, 20.0, 0.9, green)
            bubble(8.4, 21.2, 0.45, green)

            NSColor.white.setStroke()
            outline.stroke()
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
