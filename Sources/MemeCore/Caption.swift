import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum CaptionStyle: String, CaseIterable, Codable, Sendable {
    case classic
    case bar
    case subtitle
    case template
}

/// One block of text to draw, in canvas points with a top-left origin.
struct TextBlock {
    var text: String
    var font: String
    var box: CGRect
    var fill: CGColor
    var outline: CGColor?
    var angle: Double = 0
    var maxSize: CGFloat? = nil
}

enum Fonts {
    static let classic = "Impact"
    static let bar = "Futura-CondensedExtraBold"
    static let subtitle = "HelveticaNeue-Bold"

    static func memegen(_ name: String) -> String {
        switch name {
        case "thick", "impact": classic
        case "comic": "ComicSansMS"
        default: "HelveticaNeue-Medium"
        }
    }
}

enum Colors {
    static let white = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let black = CGColor(red: 0, green: 0, blue: 0, alpha: 1)

    /// The CSS names memegen's configs use, plus #RGB and #RRGGBB. Anything else draws white, the usual meme text.
    static func named(_ name: String) -> CGColor {
        let names: [String: UInt32] = ["white": 0xFFFFFF, "black": 0x000000, "khaki": 0xF0E68C, "maroon": 0x800000, "palegoldenrod": 0xEEE8AA]
        var hex = name.lowercased()
        if hex.hasPrefix("#") {
            hex.removeFirst()
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        }
        guard let value = names[name.lowercased()] ?? (hex.count == 6 ? UInt32(hex, radix: 16) : nil) else { return white }
        return CGColor(red: CGFloat(value >> 16 & 0xFF) / 255, green: CGFloat(value >> 8 & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    static func outline(for fill: CGColor) -> CGColor {
        let c = fill.components ?? [1, 1, 1]
        let luminance = 0.299 * c[0] + 0.587 * c[min(1, c.count - 1)] + 0.114 * c[min(2, c.count - 1)]
        return luminance > 0.5 ? black : white
    }
}

enum TextLayout {
    static func attributed(_ text: String, font: String, size: CGFloat, color: CGColor) -> NSAttributedString {
        let ctFont = CTFontCreateWithName(font as CFString, size, nil)
        var alignment = CTTextAlignment.center
        let paragraph = withUnsafeBytes(of: &alignment) { pointer in
            var setting = CTParagraphStyleSetting(
                spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer.baseAddress!
            )
            return CTParagraphStyleCreate(&setting, 1)
        }
        return NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
        ])
    }

    static func size(of text: String, font: String, size: CGFloat, width: CGFloat) -> CGSize {
        let setter = CTFramesetterCreateWithAttributedString(attributed(text, font: font, size: size, color: Colors.black))
        return CTFramesetterSuggestFrameSizeWithConstraints(
            setter, CFRange(location: 0, length: 0), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil
        )
    }

    static func widestWord(_ text: String, font: String, size: CGFloat) -> CGFloat {
        let ctFont = CTFontCreateWithName(font as CFString, size, nil)
        return text.split(whereSeparator: \.isWhitespace).map { word -> CGFloat in
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(word), attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): ctFont,
            ]))
            return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        }.max() ?? 0
    }

    /// The largest size at which the text wraps inside the box without breaking a word.
    static func fittingSize(_ text: String, font: String, box: CGSize, maxSize: CGFloat) -> CGFloat {
        var low: CGFloat = 4
        var high = max(low, maxSize)
        for _ in 0..<18 {
            let mid = (low + high) / 2
            let fits = size(of: text, font: font, size: mid, width: box.width).height <= box.height
                && widestWord(text, font: font, size: mid) <= box.width
            if fits { low = mid } else { high = mid }
        }
        return low
    }
}

public enum CaptionRenderer {
    static func render(size: CGSize, bar: CGFloat = 0, blocks: [TextBlock], to url: URL) throws {
        let width = Int(size.width)
        let height = Int(size.height)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw MemeError("Could not create a drawing surface of \(width)×\(height).") }

        if bar > 0 {
            context.setFillColor(Colors.white)
            context.fill(CGRect(x: 0, y: size.height - bar, width: size.width, height: bar))
        }
        for block in blocks where !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draw(block, in: context, canvasHeight: size.height)
        }
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw MemeError("Could not write \(url.lastPathComponent).") }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw MemeError("Could not write \(url.lastPathComponent).") }
    }

    static func draw(_ block: TextBlock, in context: CGContext, canvasHeight: CGFloat) {
        let box = block.box
        let fontSize = TextLayout.fittingSize(block.text, font: block.font, box: box.size, maxSize: block.maxSize ?? box.height)
        let textHeight = TextLayout.size(of: block.text, font: block.font, size: fontSize, width: box.width).height
        // Core Graphics puts the origin bottom-left; boxes are top-left.
        let flippedY = canvasHeight - box.maxY + (box.height - textHeight) / 2
        let frameRect = CGRect(x: box.minX, y: flippedY, width: box.width, height: ceil(textHeight) + 1)

        context.saveGState()
        if block.angle != 0 {
            context.translateBy(x: box.midX, y: canvasHeight - box.midY)
            context.rotate(by: CGFloat(block.angle * .pi / 180))
            context.translateBy(x: -box.midX, y: -(canvasHeight - box.midY))
        }
        if let outline = block.outline {
            context.setTextDrawingMode(.stroke)
            context.setLineWidth(max(2, fontSize / 7))
            context.setLineJoin(.round)
            context.setStrokeColor(outline)
            drawFrame(TextLayout.attributed(block.text, font: block.font, size: fontSize, color: outline), in: frameRect, context: context)
        }
        context.setTextDrawingMode(.fill)
        drawFrame(TextLayout.attributed(block.text, font: block.font, size: fontSize, color: block.fill), in: frameRect, context: context)
        context.restoreGState()
    }

    private static func drawFrame(_ text: NSAttributedString, in rect: CGRect, context: CGContext) {
        let setter = CTFramesetterCreateWithAttributedString(text)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), CGPath(rect: rect, transform: nil), nil)
        CTFrameDraw(frame, context)
    }

    static func barHeight(_ text: String, width: CGFloat) -> CGFloat {
        let size = barFontSize(text, width: width)
        let textHeight = TextLayout.size(of: text, font: Fonts.bar, size: size, width: width * 0.9).height
        return even(textHeight + size * 0.9)
    }

    static func barFontSize(_ text: String, width: CGFloat) -> CGFloat {
        var size = width / 10
        while size > width / 20 {
            let lines = TextLayout.size(of: text, font: Fonts.bar, size: size, width: width * 0.9).height / (size * 1.2)
            if lines <= 3.2, TextLayout.widestWord(text, font: Fonts.bar, size: size) <= width * 0.9 { break }
            size -= 1
        }
        return size
    }
}

func even(_ value: CGFloat) -> CGFloat { max(2, (value / 2).rounded() * 2) }
