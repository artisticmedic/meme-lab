import CoreGraphics
import Foundation

public enum Layout: String, CaseIterable, Codable, Sendable {
    case single, side, stack, sequence
}

public enum Motion: String, CaseIterable, Codable, Sendable {
    case none, reveal, zoom, shake

    static let revealLead = 0.7
    static let revealGap = 1.0
    static let revealHold = 2.0

    static func revealStart(_ step: Int) -> Double { revealLead + Double(step) * revealGap }

    func duration(steps: Int) -> Double? {
        switch self {
        case .none: nil
        case .reveal: Self.revealStart(max(steps, 1) - 1) + Self.revealHold
        case .zoom: 3
        case .shake: 2
        }
    }
}

public struct MakeRequest: Sendable {
    public var ids: [String]
    public var captions: [String]
    public var labels: [String]
    public var style: CaptionStyle?
    public var layout: Layout
    public var motion: Motion
    public var trims: [String]
    public var width: Int?
    public var fps: Int?
    public var maxMB: Double?
    public var maxSeconds: Double?

    public init(
        ids: [String], captions: [String] = [], labels: [String] = [], style: CaptionStyle? = nil,
        layout: Layout? = nil, motion: Motion = .none, trims: [String] = [], width: Int? = nil, fps: Int? = nil,
        maxMB: Double? = nil, maxSeconds: Double? = nil
    ) {
        self.ids = ids
        self.captions = captions
        self.labels = labels
        self.style = style
        self.layout = layout ?? (ids.count > 1 ? .side : .single)
        self.motion = motion
        self.trims = trims
        self.width = width
        self.fps = fps
        self.maxMB = maxMB
        self.maxSeconds = maxSeconds
    }
}

public struct MakeResult: Codable, Sendable {
    public let id: String
    public let file: String
    public let mp4: String?
    public let bytes: Int
    public let width: Int
    public let height: Int
    public let fps: Int?
    public let seconds: Double
    public let overLimit: Bool
    public let rights: String
    public let attribution: String?
}

/// `overlay` holds only the captions, on a transparent canvas; the caller lays each item's media under it at `panels`.
public struct MakePreview: Sendable {
    public let canvas: CGSize
    public let bar: CGFloat
    public let panels: [CGRect]
    public let overlay: URL
}

struct RenderInput {
    let item: Item
    let file: URL
    let info: MediaInfo
    let trim: ClosedRange<Double>?

    var size: CGSize { CGSize(width: info.width, height: info.height) }

    func length(cap: Double) -> Double {
        guard info.animated else { return 0 }
        let span = trim.map { min($0.upperBound, info.duration) - $0.lowerBound } ?? info.duration
        return min(max(span, 0.1), cap)
    }
}

struct Plan {
    var width: CGFloat
    var contentHeight: CGFloat
    var bar: CGFloat
    var panels: [CGRect]
    var segments: [Double]
    var duration: Double

    var height: CGFloat { contentHeight + bar }
    var animated: Bool { duration > 0 }
}

enum Planner {
    static func panels(layout: Layout, sizes: [CGSize], width: Int) -> (panels: [CGRect], height: CGFloat) {
        let w = even(CGFloat(width))
        let aspects = sizes.map { $0.width / max($0.height, 1) }
        switch layout {
        case .single, .sequence:
            let h = even(w / aspects[0])
            return (sizes.map { _ in CGRect(x: 0, y: 0, width: w, height: h) }, h)
        case .side:
            let h = even(w / aspects.reduce(0, +))
            var x: CGFloat = 0
            let rects = aspects.map { aspect -> CGRect in
                let rect = CGRect(x: x, y: 0, width: even(aspect * h), height: h)
                x += rect.width
                return rect
            }
            return (rects, h)
        case .stack:
            var y: CGFloat = 0
            let rects = aspects.map { aspect -> CGRect in
                let rect = CGRect(x: 0, y: y, width: w, height: even(w / aspect))
                y += rect.height
                return rect
            }
            return (rects, y)
        }
    }

    static func plan(layout: Layout, inputs: [RenderInput], width: Int, maxSeconds: Double, barText: String?, hold: Double? = nil) -> Plan {
        let (rects, height) = panels(layout: layout, sizes: inputs.map(\.size), width: width)
        let canvasWidth = rects.map(\.maxX).max() ?? CGFloat(width)
        let bar = barText.map { CaptionRenderer.barHeight($0, width: canvasWidth) } ?? 0
        let lengths = inputs.map { $0.length(cap: maxSeconds) }
        if layout == .sequence {
            let segments = lengths.map { $0 > 0 ? $0 : 1.5 }
            return Plan(width: canvasWidth, contentHeight: height, bar: bar, panels: rects, segments: segments, duration: segments.reduce(0, +))
        }
        return Plan(width: canvasWidth, contentHeight: height, bar: bar, panels: rects, segments: [], duration: hold ?? lengths.max() ?? 0)
    }
}

enum Captions {
    static func blocks(style: CaptionStyle, captions: [String], plan: Plan) throws -> [TextBlock] {
        let w = plan.width
        let h = plan.contentHeight
        let top = plan.bar
        switch style {
        case .classic:
            guard captions.count <= 2 else { throw MemeError("Classic style takes a top and a bottom caption at most; got \(captions.count).") }
            let boxes = [
                CGRect(x: w * 0.04, y: top + h * 0.02, width: w * 0.92, height: h * 0.22),
                CGRect(x: w * 0.04, y: top + h * 0.76, width: w * 0.92, height: h * 0.22),
            ]
            return zip(captions, boxes).map { text, box in
                TextBlock(text: text.uppercased(), font: Fonts.classic, box: box, fill: Colors.white, outline: Colors.black)
            }
        case .subtitle:
            let text = captions.joined(separator: "\n")
            return [TextBlock(
                text: text, font: Fonts.subtitle, box: CGRect(x: w * 0.05, y: top + h * 0.7, width: w * 0.9, height: h * 0.26),
                fill: Colors.white, outline: Colors.black, maxSize: max(14, h * 0.085)
            )]
        case .bar:
            let text = captions.joined(separator: "\n")
            return [TextBlock(
                text: text, font: Fonts.bar, box: CGRect(x: w * 0.05, y: 0, width: w * 0.9, height: plan.bar),
                fill: Colors.black, outline: nil, maxSize: CaptionRenderer.barFontSize(text, width: w)
            )]
        case .template:
            return []
        }
    }

    static func templateBlocks(boxes: [TextBox], captions: [String], panel: CGSize) throws -> [TextBlock] {
        guard captions.count <= boxes.count else {
            throw MemeError("This template has \(boxes.count) text boxes; got \(captions.count) captions.")
        }
        return zip(captions, boxes).map { text, box in
            let fill = Colors.named(box.color)
            let cased = switch box.style {
            case "upper": text.uppercased()
            case "lower": text.lowercased()
            case "mock": text.enumerated().map { $0.offset % 2 == 0 ? $0.element.lowercased() : $0.element.uppercased() }.joined()
            default: text
            }
            return TextBlock(
                text: cased, font: Fonts.memegen(box.font),
                box: CGRect(x: box.anchorX * panel.width, y: box.anchorY * panel.height,
                            width: box.scaleX * panel.width, height: box.scaleY * panel.height),
                fill: fill, outline: Colors.outline(for: fill), angle: box.angle
            )
        }
    }

    static func labelBlock(_ label: String, panel: CGSize) -> TextBlock {
        TextBlock(
            text: label.uppercased(), font: Fonts.classic,
            box: CGRect(x: panel.width * 0.04, y: panel.height * 0.03, width: panel.width * 0.92, height: panel.height * 0.16),
            fill: Colors.white, outline: Colors.black
        )
    }
}

/// Shown from `from` seconds on; nil shows it throughout.
struct Overlay {
    let url: URL
    var from: Double? = nil
}

enum FFmpegGraph {
    struct Outputs {
        var frames: URL?
        var mp4: URL?
        var png: URL?
    }

    static func arguments(plan: Plan, layout: Layout, inputs: [RenderInput], panelOverlays: [[Overlay]],
                          globalOverlays: [Overlay], motion: Motion = .none, fps: Int, outputs: Outputs) -> [String] {
        var args = ["-v", "error", "-y"]
        let f = Double(fps)
        for (i, input) in inputs.enumerated() {
            let hold = layout == .sequence ? plan.segments[i] : plan.duration
            if input.info.animated {
                if let start = input.trim?.lowerBound, start > 0 { args += ["-ss", seconds(start)] }
                args += ["-t", seconds(layout == .sequence ? hold : input.length(cap: plan.duration))]
            } else if plan.animated {
                args += ["-loop", "1", "-t", seconds(hold)]
            }
            args += ["-i", input.file.path]
        }
        var nextInput = inputs.count
        func addInputs(_ overlays: [Overlay]) -> [Int] {
            overlays.map { overlay in
                args += ["-i", overlay.url.path]
                nextInput += 1
                return nextInput - 1
            }
        }
        let panelIndexes = panelOverlays.map(addInputs)
        let globalIndexes = addInputs(globalOverlays)

        var chains: [String] = []
        func layer(_ base: String, _ overlays: [Overlay], _ indexes: [Int], into result: String) {
            guard !overlays.isEmpty else {
                chains.append("[\(base)]null[\(result)]")
                return
            }
            var current = base
            for (n, overlay) in overlays.enumerated() {
                let next = n == overlays.count - 1 ? result : "\(result)_\(n)"
                let enable = overlay.from.map { ":enable='gte(t,\(seconds($0)))'" } ?? ""
                chains.append("[\(current)][\(indexes[n]):v]overlay=0:0:format=rgb\(enable)[\(next)]")
                current = next
            }
        }

        for (i, input) in inputs.enumerated() {
            let panel = plan.panels[i]
            let pw = Int(panel.width)
            let ph = Int(panel.height)
            // The fps filter can swallow the only frame of a still, so stills skip it.
            var chain = plan.animated ? "[\(i):v]fps=\(fps)," : "[\(i):v]"
            if layout == .sequence {
                chain += "scale=\(pw):\(ph):force_original_aspect_ratio=decrease:flags=lanczos,pad=\(pw):\(ph):(ow-iw)/2:(oh-ih)/2:color=black,"
            } else if !input.info.animated, plan.animated {
                chain += movement(motion, width: pw, height: ph, fps: fps, duration: plan.duration)
            } else {
                chain += "scale=\(pw):\(ph):flags=lanczos,"
            }
            chain += "setsar=1,format=rgb24"
            let length = input.length(cap: plan.duration)
            if layout != .sequence, input.info.animated, length + 0.01 < plan.duration {
                let frames = Int((length * f).rounded(.up)) + 1
                chain += ",loop=loop=-1:size=\(frames):start=0,trim=duration=\(seconds(plan.duration)),setpts=N/(\(fps)*TB)"
            }
            chains.append(chain + "[p\(i)]")
            layer("p\(i)", panelOverlays[i], panelIndexes[i], into: "q\(i)")
        }
        let streams = inputs.indices.map { "[q\($0)]" }.joined()
        switch layout {
        case .single: chains.append("[q0]null[base]")
        case .side: chains.append("\(streams)hstack=inputs=\(inputs.count)[base]")
        case .stack: chains.append("\(streams)vstack=inputs=\(inputs.count)[base]")
        case .sequence: chains.append("\(streams)concat=n=\(inputs.count):v=1:a=0[base]")
        }
        var last = "base"
        if plan.bar > 0 {
            chains.append("[\(last)]pad=\(Int(plan.width)):\(Int(plan.height)):0:\(Int(plan.bar)):color=white[padded]")
            last = "padded"
        }
        if !globalOverlays.isEmpty {
            layer(last, globalOverlays, globalIndexes, into: "captioned")
            last = "captioned"
        }

        if plan.animated {
            chains.append("[\(last)]split=2[forgif][formp4]")
            args += ["-filter_complex", chains.joined(separator: ";")]
            if let frames = outputs.frames {
                args += ["-map", "[forgif]", "-t", seconds(plan.duration), "-pix_fmt", "rgb24", "-f", "image2",
                         frames.appending(path: "f%05d.png").path]
            }
            if let mp4 = outputs.mp4 {
                args += ["-map", "[formp4]", "-t", seconds(plan.duration), "-c:v", "libx264", "-preset", "veryfast",
                         "-crf", "23", "-pix_fmt", "yuv420p", "-movflags", "+faststart", mp4.path]
            }
        } else {
            args += ["-filter_complex", chains.joined(separator: ";")]
            if let png = outputs.png { args += ["-map", "[\(last)]", "-frames:v", "1", png.path] }
        }
        return args
    }

    static func movement(_ motion: Motion, width: Int, height: Int, fps: Int, duration: Double) -> String {
        switch motion {
        case .zoom:
            // zoompan places its window on whole pixels, so it works on a 4x copy to keep the push smooth.
            let pushFrames = max(1, Int((duration * Double(fps) * 0.7).rounded()))
            return "scale=\(width * 4):\(height * 4):flags=lanczos,"
                + "zoompan=z='1+0.12*(1-pow(1-min(on/\(pushFrames),1),3))':x='iw/2-iw/zoom/2':y='ih/2-ih/zoom/2'"
                + ":d=1:s=\(width)x\(height):fps=\(fps),"
        case .shake:
            let w = Int(even(CGFloat(width) * 1.06))
            let h = Int(even(CGFloat(height) * 1.06))
            return "scale=\(w):\(h):flags=lanczos,"
                + "crop=\(width):\(height):'(iw-ow)/2+(random(1)-0.5)*(iw-ow)':'(ih-oh)/2+(random(2)-0.5)*(ih-oh)',"
        case .none, .reveal:
            return "scale=\(width):\(height):flags=lanczos,"
        }
    }

    static func seconds(_ value: Double) -> String { String(format: "%.3f", value) }
}

public enum Trim {
    public static func parse(_ text: String) throws -> ClosedRange<Double>? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2 else { throw MemeError("A trim looks like 0.4-2.9, 1.5- or -2; got \"\(text)\".") }
        let start = parts[0].isEmpty ? 0 : Double(parts[0])
        let end = parts[1].isEmpty ? Double.greatestFiniteMagnitude : Double(parts[1])
        guard let start, let end, start >= 0, end > start else {
            throw MemeError("A trim looks like 0.4-2.9, 1.5- or -2; got \"\(text)\".")
        }
        return start...end
    }
}

extension Library {
    private struct Prepared {
        let inputs: [RenderInput]
        let style: CaptionStyle
        let templated: Int?
        let hasText: Bool
        let barText: String?
        let width: Int
        let hold: Double?
    }

    private func prepare(_ request: MakeRequest) async throws -> Prepared {
        guard !request.ids.isEmpty else { throw MemeError("Name at least one item to make a meme from.") }
        if request.layout == .single, request.ids.count > 1 {
            throw MemeError("The single layout takes one item; use side, stack or sequence for \(request.ids.count).")
        }
        if request.ids.count > 4 { throw MemeError("A meme combines four items at most.") }

        var inputs: [RenderInput] = []
        for (n, id) in request.ids.enumerated() {
            let item = try self.item(id)
            guard item.rights.caption else {
                throw MemeError("\(id) is \(item.rights.post.label.lowercased()) and cannot be captioned.")
            }
            let file = try await ensureMedia(item)
            let trim = n < request.trims.count ? try Trim.parse(request.trims[n]) : nil
            inputs.append(RenderInput(item: item, file: file, info: try Media.probe(file), trim: trim))
        }

        let templated = inputs.firstIndex { !$0.item.boxes.isEmpty }
        let style = request.style ?? (templated != nil ? .template : (inputs.contains { $0.info.animated } ? .bar : .classic))
        if style == .template, templated == nil {
            throw MemeError("Template style needs a memegen template with text boxes; use classic, bar or subtitle.")
        }
        if request.labels.count > inputs.count {
            throw MemeError("Got \(request.labels.count) labels for \(inputs.count) items.")
        }
        let hasText = request.captions.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        var hold: Double?
        if request.motion != .none {
            if let moving = inputs.first(where: { $0.info.animated }) {
                throw MemeError("\(moving.item.id) already moves; motion is for still pictures.")
            }
            if request.layout == .sequence { throw MemeError("Motion works with the single, side and stack layouts.") }
            if request.motion == .reveal, !hasText { throw MemeError("Reveal shows the captions one at a time; add a caption.") }
            hold = request.motion.duration(steps: Self.revealSteps(request.captions, style: style).count)
        }
        return Prepared(
            inputs: inputs, style: style, templated: templated, hasText: hasText,
            barText: style == .bar && hasText ? request.captions.joined(separator: "\n") : nil,
            width: request.width ?? (request.layout == .side ? config.width * 3 / 2 : config.width), hold: hold
        )
    }

    /// The order captions appear in when revealed, by caption index. Bar and subtitle draw every caption as one block, so they appear together.
    static func revealSteps(_ captions: [String], style: CaptionStyle) -> [Int: Int] {
        let shown = captions.indices.filter { !captions[$0].trimmingCharacters(in: .whitespaces).isEmpty }
        if style == .bar || style == .subtitle { return shown.isEmpty ? [:] : [0: 0] }
        return Dictionary(uniqueKeysWithValues: shown.enumerated().map { ($1, $0) })
    }

    /// Also saves the index and records the result in status.json as the last one made.
    public func makeAndSave(_ request: MakeRequest) async throws -> MakeResult {
        let result = try await make(request)
        try save()
        try StatusStore(url: paths.status).update { $0.lastMade = result.id }
        return result
    }

    public func make(_ request: MakeRequest) async throws -> MakeResult {
        let started = Date()
        let prepared = try await prepare(request)
        let inputs = prepared.inputs
        let fps = request.fps ?? config.fps
        let maxBytes = Int((request.maxMB ?? config.maxMB) * 1_000_000)
        let maxSeconds = request.maxSeconds ?? config.maxSeconds

        let id = uniqueID(prefix: "m-")
        let work = paths.work.appending(path: id)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        let made = root.appending(path: "Made")
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)

        let ladder: [(fps: Int, scale: Double, quality: Int)] = [
            (fps, 1, 90), (min(fps, 12), 1, 88), (min(fps, 10), 1, 85),
            (min(fps, 10), 0.8, 80), (min(fps, 8), 0.66, 75), (min(fps, 8), 0.5, 70),
        ]
        var outcome: (plan: Plan, file: URL, mp4: URL?, bytes: Int, fps: Int?)?
        for step in ladder {
            let plan = Planner.plan(layout: request.layout, inputs: inputs, width: Int(Double(prepared.width) * step.scale),
                                    maxSeconds: maxSeconds, barText: prepared.barText, hold: prepared.hold)
            let overlays = try renderOverlays(plan: plan, prepared: prepared, request: request, work: work)
            if !plan.animated {
                let png = made.appending(path: "\(id).png")
                try Shell.run("ffmpeg", FFmpegGraph.arguments(
                    plan: plan, layout: request.layout, inputs: inputs, panelOverlays: overlays.panels,
                    globalOverlays: overlays.global, fps: 1, outputs: .init(png: png)
                ))
                guard FileManager.default.fileExists(atPath: png.path) else { throw MemeError("ffmpeg wrote no picture for \(id).") }
                outcome = (plan, png, nil, try fileSize(png), nil)
                break
            }
            let frames = work.appending(path: "frames")
            try? FileManager.default.removeItem(at: frames)
            try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
            let gif = made.appending(path: "\(id).gif")
            let mp4 = made.appending(path: "\(id).mp4")
            try Shell.run("ffmpeg", FFmpegGraph.arguments(
                plan: plan, layout: request.layout, inputs: inputs, panelOverlays: overlays.panels,
                globalOverlays: overlays.global, motion: request.motion, fps: step.fps, outputs: .init(frames: frames, mp4: mp4)
            ))
            let frameFiles = try FileManager.default.contentsOfDirectory(atPath: frames.path)
                .filter { $0.hasSuffix(".png") }.sorted().map { frames.appending(path: $0).path }
            guard !frameFiles.isEmpty else { throw MemeError("ffmpeg produced no frames for \(id).") }
            try Shell.run("gifski", ["--quiet", "--fps", String(step.fps), "--quality", String(step.quality), "-o", gif.path] + frameFiles)
            let bytes = try fileSize(gif)
            outcome = (plan, gif, mp4, bytes, step.fps)
            if bytes <= maxBytes { break }
        }
        guard let outcome else { throw MemeError("Nothing was rendered for \(id).") }

        let rights = inputs.map(\.item.rights.post).max() ?? .personal
        let attributions = inputs.compactMap(\.item.attribution)
        let relative = "Made/\(outcome.file.lastPathComponent)"
        var item = Item(
            id: id, kind: .made, title: request.captions.first { !$0.isEmpty } ?? inputs.map(\.item.title).joined(separator: " + "),
            source: "made", rights: Rights(caption: true, post: rights), file: relative, animated: outcome.plan.animated,
            width: Int(outcome.plan.width), height: Int(outcome.plan.height),
            tags: Array(Set(inputs.flatMap(\.item.tags))).sorted(),
            attribution: attributions.isEmpty ? nil : attributions.joined(separator: "; "),
            made: MadeInfo(
                inputs: request.ids, captions: request.captions, labels: request.labels, style: prepared.style.rawValue,
                layout: request.layout.rawValue, gif: outcome.plan.animated ? relative : nil,
                mp4: outcome.mp4.map { "Made/\($0.lastPathComponent)" }, png: outcome.plan.animated ? nil : relative,
                bytes: outcome.bytes, fps: outcome.fps, width: Int(outcome.plan.width), overLimit: outcome.bytes > maxBytes,
                motion: request.motion == .none ? nil : request.motion.rawValue
            )
        )
        item.vibe = inputs.compactMap(\.item.vibe).first
        upsert(item)
        for input in inputs {
            items[input.item.id]?.useCount += 1
            items[input.item.id]?.lastUsed = Date()
        }
        return MakeResult(
            id: id, file: outcome.file.path, mp4: outcome.mp4?.path, bytes: outcome.bytes,
            width: Int(outcome.plan.width), height: Int(outcome.plan.height), fps: outcome.fps,
            seconds: (Date().timeIntervalSince(started) * 100).rounded() / 100, overLimit: outcome.bytes > maxBytes,
            rights: rights.label, attribution: item.attribution
        )
    }

    /// Lays out the meme and draws its captions without running ffmpeg, fast enough to follow typing.
    public func preview(_ request: MakeRequest) async throws -> MakePreview {
        var still = request
        still.motion = .none
        let prepared = try await prepare(still)
        let plan = Planner.plan(layout: request.layout, inputs: prepared.inputs, width: prepared.width,
                                maxSeconds: request.maxSeconds ?? config.maxSeconds, barText: prepared.barText)
        let folder = paths.work.appending(path: "previews")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stale = Date().addingTimeInterval(-300)
        for old in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        where ((try? old.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast) < stale {
            try? FileManager.default.removeItem(at: old)
        }

        let panels = plan.panels.map { $0.offsetBy(dx: 0, dy: plan.bar) }
        var blocks: [TextBlock] = []
        // A sequence shows one item at a time in the same place, so the preview shows the first.
        for (i, panel) in panels.enumerated() where request.layout != .sequence || i == 0 {
            let drawn = try panelBlocks(i, size: panel.size, prepared: prepared, request: request)
            for block in drawn.captions + drawn.labels {
                var moved = block
                moved.box = block.box.offsetBy(dx: panel.minX, dy: panel.minY)
                blocks.append(moved)
            }
        }
        if prepared.style != .template, prepared.hasText {
            blocks += try Captions.blocks(style: prepared.style, captions: request.captions, plan: plan)
        }
        let url = folder.appending(path: "\(UUID().uuidString).png")
        let canvas = CGSize(width: plan.width, height: plan.height)
        try CaptionRenderer.render(size: canvas, bar: plan.bar, blocks: blocks, to: url)
        return MakePreview(canvas: canvas, bar: plan.bar, panels: panels, overlay: url)
    }

    private func panelBlocks(_ i: Int, size: CGSize, prepared: Prepared, request: MakeRequest) throws -> (captions: [TextBlock], labels: [TextBlock]) {
        let captions = prepared.style == .template && i == prepared.templated && prepared.hasText
            ? try Captions.templateBlocks(boxes: prepared.inputs[i].item.boxes, captions: request.captions, panel: size) : []
        let labels = i < request.labels.count && !request.labels[i].isEmpty ? [Captions.labelBlock(request.labels[i], panel: size)] : []
        return (captions, labels)
    }

    private func renderOverlays(plan: Plan, prepared: Prepared, request: MakeRequest, work: URL) throws -> (panels: [[Overlay]], global: [Overlay]) {
        let steps = request.motion == .reveal ? Self.revealSteps(request.captions, style: prepared.style) : nil
        func draw(_ blocks: [TextBlock], size: CGSize, bar: CGFloat = 0, name: String, from: Double? = nil) throws -> Overlay {
            let url = work.appending(path: "\(name)-\(Int(size.width)).png")
            try CaptionRenderer.render(size: size, bar: bar, blocks: blocks, to: url)
            return Overlay(url: url, from: from)
        }
        func layers(_ captionBlocks: [TextBlock], fixed: [TextBlock], size: CGSize, bar: CGFloat = 0, name: String) throws -> [Overlay] {
            guard let steps else {
                let all = fixed + captionBlocks
                return all.isEmpty ? [] : [try draw(all, size: size, bar: bar, name: name)]
            }
            var overlays = fixed.isEmpty ? [] : [try draw(fixed, size: size, bar: bar, name: name)]
            for (n, block) in captionBlocks.enumerated() {
                guard let step = steps[n] else { continue }
                overlays.append(try draw([block], size: size, bar: bar, name: "\(name)-r\(n)", from: Motion.revealStart(step)))
            }
            return overlays
        }

        var panels: [[Overlay]] = []
        for i in prepared.inputs.indices {
            let size = plan.panels[i].size
            let drawn = try panelBlocks(i, size: size, prepared: prepared, request: request)
            panels.append(try layers(drawn.captions, fixed: drawn.labels, size: size, name: "panel\(i)"))
        }
        guard prepared.style != .template, prepared.hasText else { return (panels, []) }
        let blocks = try Captions.blocks(style: prepared.style, captions: request.captions, plan: plan)
        let global = try layers(blocks, fixed: [], size: CGSize(width: plan.width, height: plan.height), bar: plan.bar, name: "global")
        return (panels, global)
    }
}
