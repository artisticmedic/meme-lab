import CoreGraphics
import Foundation

public enum Layout: String, CaseIterable, Codable, Sendable {
    case single, side, stack, sequence
}

public struct MakeRequest: Sendable {
    public var ids: [String]
    public var captions: [String]
    public var labels: [String]
    public var style: CaptionStyle?
    public var layout: Layout
    public var trims: [String]
    public var width: Int?
    public var fps: Int?
    public var maxMB: Double?
    public var maxSeconds: Double?

    public init(
        ids: [String], captions: [String] = [], labels: [String] = [], style: CaptionStyle? = nil,
        layout: Layout? = nil, trims: [String] = [], width: Int? = nil, fps: Int? = nil,
        maxMB: Double? = nil, maxSeconds: Double? = nil
    ) {
        self.ids = ids
        self.captions = captions
        self.labels = labels
        self.style = style
        self.layout = layout ?? (ids.count > 1 ? .side : .single)
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

struct Plan: Equatable {
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

    static func plan(layout: Layout, inputs: [RenderInput], width: Int, maxSeconds: Double, barText: String?) -> Plan {
        let (rects, height) = panels(layout: layout, sizes: inputs.map(\.size), width: width)
        let canvasWidth = rects.map(\.maxX).max() ?? CGFloat(width)
        let bar = barText.map { CaptionRenderer.barHeight($0, width: canvasWidth) } ?? 0
        let lengths = inputs.map { $0.length(cap: maxSeconds) }
        if layout == .sequence {
            let segments = lengths.map { $0 > 0 ? $0 : 1.5 }
            return Plan(width: canvasWidth, contentHeight: height, bar: bar, panels: rects, segments: segments, duration: segments.reduce(0, +))
        }
        return Plan(width: canvasWidth, contentHeight: height, bar: bar, panels: rects, segments: [], duration: lengths.max() ?? 0)
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

enum FFmpegGraph {
    struct Outputs {
        var frames: URL?
        var mp4: URL?
        var png: URL?
    }

    static func arguments(plan: Plan, layout: Layout, inputs: [RenderInput], panelOverlays: [URL?],
                          globalOverlay: URL?, fps: Int, outputs: Outputs) -> [String] {
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
        var overlayIndex: [Int: Int] = [:]
        for (i, overlay) in panelOverlays.enumerated() {
            guard let overlay else { continue }
            args += ["-i", overlay.path]
            overlayIndex[i] = nextInput
            nextInput += 1
        }
        let globalIndex: Int? = globalOverlay.map { overlay in
            args += ["-i", overlay.path]
            return nextInput
        }

        var chains: [String] = []
        for (i, input) in inputs.enumerated() {
            let panel = plan.panels[i]
            let pw = Int(panel.width)
            let ph = Int(panel.height)
            // The fps filter can swallow the only frame of a still, so stills skip it.
            var chain = plan.animated ? "[\(i):v]fps=\(fps)," : "[\(i):v]"
            if layout == .sequence {
                chain += "scale=\(pw):\(ph):force_original_aspect_ratio=decrease:flags=lanczos,pad=\(pw):\(ph):(ow-iw)/2:(oh-ih)/2:color=black,"
            } else {
                chain += "scale=\(pw):\(ph):flags=lanczos,"
            }
            chain += "setsar=1,format=rgb24"
            let length = input.length(cap: plan.duration)
            if layout != .sequence, input.info.animated, length + 0.01 < plan.duration {
                let frames = Int((length * f).rounded(.up)) + 1
                chain += ",loop=loop=-1:size=\(frames):start=0,trim=duration=\(seconds(plan.duration)),setpts=N/(\(fps)*TB)"
            }
            if let o = overlayIndex[i] {
                chains.append(chain + "[p\(i)]")
                chains.append("[p\(i)][\(o):v]overlay=0:0:format=rgb[q\(i)]")
            } else {
                chains.append(chain + "[q\(i)]")
            }
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
        if let g = globalIndex {
            chains.append("[\(last)][\(g):v]overlay=0:0:format=rgb[captioned]")
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

    static func seconds(_ value: Double) -> String { String(format: "%.3f", value) }
}

public enum Trim {
    /// "0.4-2.9", "1.5-" (to the end) or "-2" (the first two seconds).
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
    public func make(_ request: MakeRequest) async throws -> MakeResult {
        let started = Date()
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

        let width = request.width ?? (request.layout == .side ? config.width * 3 / 2 : config.width)
        let fps = request.fps ?? config.fps
        let maxBytes = Int((request.maxMB ?? config.maxMB) * 1_000_000)
        let maxSeconds = request.maxSeconds ?? config.maxSeconds
        let hasText = request.captions.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let barText = style == .bar && hasText ? request.captions.joined(separator: "\n") : nil

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
            let plan = Planner.plan(layout: request.layout, inputs: inputs, width: Int(Double(width) * step.scale),
                                    maxSeconds: maxSeconds, barText: barText)
            let overlays = try renderOverlays(plan: plan, inputs: inputs, style: style, request: request,
                                              templated: templated, hasText: hasText, work: work)
            if !plan.animated {
                let png = made.appending(path: "\(id).png")
                try Shell.run("ffmpeg", FFmpegGraph.arguments(
                    plan: plan, layout: request.layout, inputs: inputs, panelOverlays: overlays.panels,
                    globalOverlay: overlays.global, fps: 1, outputs: .init(png: png)
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
                globalOverlay: overlays.global, fps: step.fps, outputs: .init(frames: frames, mp4: mp4)
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
                inputs: request.ids, captions: request.captions, labels: request.labels, style: style.rawValue,
                layout: request.layout.rawValue, gif: outcome.plan.animated ? relative : nil,
                mp4: outcome.mp4.map { "Made/\($0.lastPathComponent)" }, png: outcome.plan.animated ? nil : relative,
                bytes: outcome.bytes, fps: outcome.fps, width: Int(outcome.plan.width), overLimit: outcome.bytes > maxBytes
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

    private func renderOverlays(plan: Plan, inputs: [RenderInput], style: CaptionStyle, request: MakeRequest,
                                templated: Int?, hasText: Bool, work: URL) throws -> (panels: [URL?], global: URL?) {
        var panels: [URL?] = Array(repeating: nil, count: inputs.count)
        for i in inputs.indices {
            let size = plan.panels[i].size
            var blocks: [TextBlock] = []
            if style == .template, i == templated, hasText {
                blocks += try Captions.templateBlocks(boxes: inputs[i].item.boxes, captions: request.captions, panel: size)
            }
            if i < request.labels.count, !request.labels[i].isEmpty {
                blocks.append(Captions.labelBlock(request.labels[i], panel: size))
            }
            guard !blocks.isEmpty else { continue }
            let url = work.appending(path: "panel\(i)-\(Int(size.width)).png")
            try CaptionRenderer.render(size: size, blocks: blocks, to: url)
            panels[i] = url
        }
        guard style != .template, hasText else { return (panels, nil) }
        let url = work.appending(path: "global-\(Int(plan.width)).png")
        try CaptionRenderer.render(
            size: CGSize(width: plan.width, height: plan.height), bar: plan.bar,
            blocks: try Captions.blocks(style: style, captions: request.captions, plan: plan), to: url
        )
        return (panels, url)
    }

    private func fileSize(_ url: URL) throws -> Int {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    }
}
