import AppKit
import MemeCore
import SwiftUI

@MainActor
enum Renderer {
    static func run(into folder: URL) -> Int32 {
        NSApplication.shared.setActivationPolicy(.prohibited)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("Could not create \(folder.path): \(error)\n".utf8))
            return 1
        }
        let model = AppModel()
        let made = model.items(.made, matching: "").prefix(4).map(\.id)
        let options = made.count >= 2 ? Array(made) : model.items(.all, matching: "").prefix(4).map(\.id)
        let panelHeight: CGFloat = 680

        func panel(_ status: Status) -> some View {
            let state = PanelState(model: model)
            state.height = panelHeight
            model.stage(status)
            state.sync(with: status.request)
            return PanelView(state: state, onAction: { _ in })
                .environmentObject(model)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        func library(_ shelf: Shelf, selecting: Bool = true) -> some View {
            model.stage(browse)
            let state = LibraryState()
            state.shelf = shelf
            state.selection = selecting ? model.items(.all, matching: "").prefix(1).map(\.id) : []
            return LibraryView(state: state).environmentObject(model)
        }

        func make() -> some View {
            let template = model.items(.templates, matching: "").first { $0.boxes.count == 2 && $0.example.count == 2 }
            return MakeView(ids: template.map { [$0.id] } ?? [], items: template.map { [$0] } ?? [], captions: template?.example ?? []) {}
                .environmentObject(model)
                .background(Color(nsColor: .windowBackgroundColor))
        }

        var browse = model.store.load()
        browse.request = nil
        browse.picks = browse.picks.isEmpty ? model.items(.templates, matching: "").prefix(2).map(\.id) : Array(browse.picks.prefix(2))
        var propose = browse
        propose.request = AppRequest(mode: .propose, items: options, max: 1, from: "Codex", pid: getpid())
        var pick = browse
        pick.request = AppRequest(mode: .pick, items: [], max: 2, from: "Claude", pid: getpid())

        let surfaces: [(String, NSSize, () -> AnyView)] = [
            ("panel", NSSize(width: 320, height: panelHeight), { AnyView(panel(browse)) }),
            ("panel-propose", NSSize(width: 320, height: panelHeight), { AnyView(panel(propose)) }),
            ("panel-pick", NSSize(width: 320, height: panelHeight), { AnyView(panel(pick)) }),
            ("library", NSSize(width: 1180, height: 760), { AnyView(library(.all)) }),
            ("library-browse", NSSize(width: 1180, height: 760), { AnyView(library(.all, selecting: false)) }),
            ("make", NSSize(width: 940, height: 620), { AnyView(make()) }),
            ("settings", NSSize(width: 1180, height: 1300), { AnyView(library(.settings)) }),
            ("library-clips", NSSize(width: 1180, height: 760), { AnyView(library(.clips, selecting: false)) }),
            ("library-popular", NSSize(width: 1180, height: 760), { AnyView(library(.popular, selecting: false)) }),
        ]
        var failed = false
        for (name, size, make) in surfaces {
            for (suffix, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let url = folder.appending(path: "\(name)-\(suffix).png")
                if write(make(), size: size, appearance: appearance, to: url) {
                    print(url.path)
                } else {
                    FileHandle.standardError.write(Data("Could not render \(name) (\(suffix)).\n".utf8))
                    failed = true
                }
            }
        }
        return failed ? 1 : 0
    }

    private static func write(_ view: AnyView, size: NSSize, appearance: NSAppearance.Name, to url: URL) -> Bool {
        let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: size.width, height: size.height),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = .windowBackgroundColor
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        // Thumbnails load in tasks on the main run loop.
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))
        hosting.layoutSubtreeIfNeeded()
        let scale: CGFloat = 2
        guard let layer = hosting.layer,
              let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        context.translateBy(x: 0, y: size.height * scale)
        context.scaleBy(x: scale, y: -scale)
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            context.setFillColor(NSColor.windowBackgroundColor.cgColor)
        }
        context.fill(CGRect(origin: .zero, size: size))
        layer.render(in: context)
        window.orderOut(nil)
        guard let image = context.makeImage() else { return false }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        return (try? png.write(to: url)) != nil
    }
}
