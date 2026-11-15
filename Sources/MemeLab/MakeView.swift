import AppKit
import MemeCore
import SwiftUI

struct MakeView: View {
    @EnvironmentObject var model: AppModel
    let ids: [String]
    let close: () -> Void

    @State private var captions: [String]
    @State private var style: CaptionStyle
    @State private var motion: Motion
    @State private var layout: MemeCore.Layout
    @State private var preview: MakePreview?
    @State private var overlay: NSImage?
    @State private var previewProblem: String?
    @State private var makeProblem: String?
    @State private var making = false
    @State private var result: MakeResult?
    @FocusState private var focusedCaption: Int?

    /// Read once, so the caption fields keep their count if the library reloads while the sheet is open.
    private let boxes: [String]
    private let canTemplate: Bool

    init(ids: [String], items: [Item], captions: [String] = [], close: @escaping () -> Void) {
        self.ids = ids
        self.close = close
        let templated = items.first { !$0.boxes.isEmpty }
        canTemplate = templated != nil
        boxes = templated.map { item in item.boxes.indices.map { $0 < item.example.count ? item.example[$0] : "" } } ?? []
        let slots = max(2, boxes.count, captions.count)
        _captions = State(initialValue: captions + Array(repeating: "", count: slots - captions.count))
        let still = items.allSatisfy { !$0.animated }
        _style = State(initialValue: items.contains { !$0.boxes.isEmpty } ? .template : (still ? .classic : .bar))
        _motion = State(initialValue: still ? .reveal : .none)
        _layout = State(initialValue: ids.count > 1 ? .side : .single)
    }

    private var items: [Item] { ids.compactMap(model.item) }
    private var allStill: Bool { items.allSatisfy { !$0.animated } }
    private var canMove: Bool { allStill && layout != .sequence }

    private var fields: [(title: String, prompt: String)] {
        switch style {
        case .template:
            return boxes.enumerated().map { i, example in ("Caption \(i + 1)", example) }
        case .classic: return [("Top", ""), ("Bottom", "")]
        case .bar, .subtitle: return [("Caption", "")]
        }
    }

    private var request: MakeRequest {
        let used = Array(captions.prefix(fields.count))
        return MakeRequest(ids: ids, captions: used, style: style, layout: layout, motion: canMove ? motion : .none)
    }

    private var requestKey: String {
        "\(ids)|\(captions.prefix(fields.count))|\(style)|\(layout)"
    }

    var body: some View {
        HStack(spacing: 0) {
            stage.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24).background(Color.primary.opacity(0.04))
            Divider()
            ScrollView {
                if let result { finished(result) } else { editor }
            }
            .frame(width: 330)
        }
        .frame(width: 940, height: 620)
        .task(id: requestKey) { await refreshPreview() }
    }

    @ViewBuilder private var stage: some View {
        if let result {
            if let made = model.item(result.id) {
                MediaPreview(item: made, playing: true, fill: false, maxPixel: 900)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onDrag { model.dragProvider(made) }
            } else {
                ProgressView()
            }
        } else if let preview, items.count == ids.count {
            GeometryReader { geo in
                let scale = min(geo.size.width / preview.canvas.width, geo.size.height / preview.canvas.height)
                let panels = layout == .sequence ? Array(preview.panels.prefix(1)) : preview.panels
                ZStack(alignment: .topLeading) {
                    ForEach(Array(zip(panels.indices, items)), id: \.0) { i, item in
                        let rect = panels[i]
                        MediaPreview(item: item, playing: true, fill: false, maxPixel: 900)
                            .frame(width: rect.width * scale, height: rect.height * scale)
                            .offset(x: rect.minX * scale, y: rect.minY * scale)
                    }
                    if let overlay {
                        Image(nsImage: overlay).resizable()
                            .frame(width: preview.canvas.width * scale, height: preview.canvas.height * scale)
                    }
                }
                .frame(width: preview.canvas.width * scale, height: preview.canvas.height * scale, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .frame(width: geo.size.width, height: geo.size.height)
            }
        } else if previewProblem == nil {
            ProgressView()
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Make a GIF").font(.system(size: 17, weight: .semibold))
                Text(items.map(\.title).joined(separator: " + ")).font(.system(size: 13)).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(fields.enumerated()), id: \.offset) { i, field in
                    VStack(alignment: .leading, spacing: 4) {
                        label(field.title)
                        TextField(field.prompt, text: $captions[i], axis: .vertical)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .lineLimit(1...3)
                            .focused($focusedCaption, equals: i)
                            .padding(.horizontal, 9).padding(.vertical, 7)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(focusedCaption == i ? 0.08 : 0.05)))
                    }
                }
            }
            if items.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    label("Layout")
                    Tabs(options: [(MemeCore.Layout.side, "Side by side"), (.stack, "Stacked"), (.sequence, "One after another")], selection: $layout)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                label("Style")
                Tabs(options: styleOptions, selection: $style)
            }
            if canMove {
                VStack(alignment: .leading, spacing: 6) {
                    label("Motion")
                    Tabs(options: [(Motion.reveal, "Reveal"), (.zoom, "Zoom"), (.shake, "Shake"), (.none, "Still")], selection: $motion)
                    Text(motionCaption).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
            if let problem = makeProblem ?? previewProblem {
                Text(problem).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))
            }
            HStack(spacing: 8) {
                Button(making ? "Making…" : "Make") { Task { await make() } }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(making)
                Button("Cancel", action: close).buttonStyle(PillButtonStyle()).keyboardShortcut(.cancelAction)
                if making { ProgressView().controlSize(.small).padding(.leading, 4) }
            }
        }
        .padding(20)
        .onAppear { focusedCaption = 0 }
    }

    private var styleOptions: [(CaptionStyle, String)] {
        (canTemplate ? [(CaptionStyle.template, "Template")] : []) + [(.classic, "Top and bottom"), (.bar, "Bar"), (.subtitle, "Subtitle")]
    }

    private var motionCaption: String {
        switch motion {
        case .reveal: "Each caption appears in turn."
        case .zoom: "The picture slowly pushes in."
        case .shake: "The picture shakes."
        case .none: "A still picture, saved as a PNG."
        }
    }

    private func finished(_ result: MakeResult) -> some View {
        let made = model.item(result.id)
        let kind = result.file.hasSuffix(".gif") ? "GIF" : "PNG"
        let size = ByteCountFormatter.string(fromByteCount: Int64(result.bytes), countStyle: .file)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Made").font(.system(size: 17, weight: .semibold))
                Text("\(kind), \(size), \(result.width)×\(result.height). It is in Made.").font(.system(size: 13)).foregroundStyle(.secondary)
                if result.overLimit {
                    Text("Larger than your \(model.config.maxMB.formatted()) MB limit even at the smallest size.").font(.system(size: 13))
                }
            }
            HStack(spacing: 8) {
                Button("Copy") { if let made { Task { await model.copy(made) } } }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(made == nil)
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: result.file)]) }
                    .buttonStyle(PillButtonStyle())
            }
            Text("Or drag it from the preview into a chat.").font(.system(size: 13)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Change It") { self.result = nil }.buttonStyle(PillButtonStyle())
                Button("Done", action: close).buttonStyle(PillButtonStyle()).keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
    }

    private func refreshPreview() async {
        if preview != nil { try? await Task.sleep(for: .milliseconds(150)) }
        guard !Task.isCancelled else { return }
        do {
            let fresh = try await model.preview(request)
            guard !Task.isCancelled else { return }
            preview = fresh
            overlay = NSImage(contentsOf: fresh.overlay)
            previewProblem = nil
        } catch {
            if !Task.isCancelled { previewProblem = "\(error)" }
        }
    }

    private func make() async {
        making = true
        makeProblem = nil
        do {
            result = try await model.make(request)
        } catch {
            makeProblem = "\(error)"
        }
        making = false
    }
}
