import AppKit
import Carbon.HIToolbox
import MemeCore
import SwiftUI

enum PanelAction { case library, quit }

@MainActor
final class PanelState: ObservableObject {
    @Published var query = ""
    @Published var shelf: Shelf = .all
    @Published var focus: Int?
    @Published var idea = ""
    @Published var note = ""
    @Published var chosen: [String] = []
    @Published var copied = false
    var requestID: String?
    var height: CGFloat = 680
    unowned let model: AppModel

    init(model: AppModel) { self.model = model }

    var request: AppRequest? { model.status.request }

    var list: [Item] {
        if let request {
            switch request.mode {
            case .propose: return request.items.compactMap(model.item)
            case .pick: return model.items(.all, matching: query, only: request.items)
            }
        }
        return model.items(shelf, matching: query)
    }

    /// Options keep the agent's numbering even if one cannot be shown.
    var numbers: [String: Int] {
        Dictionary((request?.items ?? []).enumerated().map { ($1, $0 + 1) }, uniquingKeysWith: { first, _ in first })
    }

    func sync(with request: AppRequest?) {
        guard request?.id != requestID else { return }
        requestID = request?.id
        chosen = []
        note = ""
        focus = nil
        query = ""
    }

    func move(_ delta: Int) {
        let count = list.count
        guard count > 0 else { return }
        focus = focus.map { min(max($0 + delta, 0), count - 1) } ?? 0
    }

    func activate(_ item: Item) {
        guard let request else {
            model.togglePick(item.id)
            return
        }
        switch request.mode {
        case .propose:
            chosen = chosen == [item.id] ? [] : [item.id]
        case .pick:
            if let index = chosen.firstIndex(of: item.id) { chosen.remove(at: index) }
            else if chosen.count < request.max { chosen.append(item.id) }
        }
    }

    func send() {
        guard let request else { return }
        model.answer(request, chosen: chosen, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

struct PanelView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var state: PanelState
    let onAction: (PanelAction) -> Void
    @FocusState private var searchFocused: Bool
    @State private var hoveredRow: PanelAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let request = model.status.request {
                requestBody(request)
            } else {
                browseBody
            }
            Divider().padding(.horizontal, 4)
            VStack(spacing: 0) {
                row(.library, title: "Open Library…", symbol: "square.grid.3x3", shortcut: "⌘,")
                row(.quit, title: "Quit Meme Lab", symbol: "power", shortcut: "⌘Q")
            }
        }
        .padding(10)
        .frame(width: 320, height: state.height, alignment: .top)
        .foregroundStyle(.primary)
        .onAppear { DispatchQueue.main.async { searchFocused = true } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(nsImage: Mark.header(size: 20))
                Text("Meme Lab").font(.system(size: 15, weight: .semibold))
            }
            Text(model.error ?? model.statusLine).font(.system(size: 12)).foregroundStyle(.secondary)
                .lineLimit(3).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 6).padding(.top, 4)
    }

    private var browseBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            SearchField(text: $state.query, focus: $searchFocused)
            HStack(spacing: 4) {
                ForEach(Shelf.panel, id: \.self) { shelf in
                    Button(shelf.title) { state.shelf = shelf; state.focus = nil }
                        .buttonStyle(PillButtonStyle(selected: state.shelf == shelf))
                }
            }
            grid(state.list, picked: Set(model.status.picks))
            tray
        }
    }

    private func grid(_ items: [Item], picked: Set<String>, numbers: [String: Int] = [:], captions: Bool = false) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                if items.isEmpty {
                    Text(state.query.isEmpty ? "Nothing here yet." : "Nothing matches “\(state.query)”.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).padding(.top, 40)
                }
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 4, alignment: .top), GridItem(.flexible(), spacing: 4, alignment: .top)], spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        Tile(item: item, number: numbers[item.id], picked: picked.contains(item.id),
                             selected: state.focus == index, height: 96, caption: captions ? caption(item) : nil)
                            .id(item.id)
                            .onTapGesture { state.focus = index; state.activate(item) }
                            .contextMenu {
                                Button("Copy") { Task { await model.copy([item]) } }
                            }
                    }
                }
            }
            .scrollIndicators(.automatic)
            .frame(maxHeight: .infinity)
            .onChange(of: state.focus) { _, focus in
                if let focus, focus < items.count { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(items[focus].id) } }
            }
        }
    }

    private func caption(_ item: Item) -> String {
        let captions = item.made?.captions.filter { !$0.isEmpty } ?? []
        return captions.isEmpty ? model.recipe(item) ?? item.title : captions.joined(separator: " / ")
    }

    private var tray: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Picked").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                if !model.status.picks.isEmpty {
                    Button("Clear") { model.clearPicks() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            if model.status.picks.isEmpty {
                Text("Click memes to pick up to four. Copy prompt hands them to any agent.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                FlowLayout {
                    ForEach(model.status.picks, id: \.self) { id in
                        Chip(text: model.item(id)?.title ?? id) { model.togglePick(id) }
                    }
                }
            }
            InputField(prompt: "Idea, like “me watching CI”", text: $state.idea)
            HStack(spacing: 8) {
                if !model.config.agentCommand.isEmpty {
                    Button("Ask agent") { model.askAgent(idea: state.idea) }
                        .buttonStyle(PillButtonStyle())
                        .disabled(model.status.picks.isEmpty)
                }
                Spacer()
                Button(state.copied ? "Copied" : "Copy prompt") {
                    model.copyPrompt(idea: state.idea)
                    state.copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { state.copied = false }
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .disabled(model.status.picks.isEmpty)
            }
        }
        .padding(.horizontal, 2)
    }

    @ViewBuilder
    private func requestBody(_ request: AppRequest) -> some View {
        let items = state.list
        VStack(alignment: .leading, spacing: 8) {
            if request.mode == .pick { SearchField(text: $state.query, focus: $searchFocused) }
            grid(items, picked: Set(state.chosen), numbers: request.mode == .propose ? state.numbers : [:], captions: request.mode == .propose)
            if request.mode == .propose {
                InputField(prompt: "What to change, like “2, shorter caption”", text: $state.note)
            }
            Text(request.mode == .propose ? "Return sends the selected option back." : "Return sends your picks back.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("None") {
                    state.chosen = []
                    state.send()
                }
                .buttonStyle(PillButtonStyle())
                Spacer()
                Button("Send back") { state.send() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(state.chosen.isEmpty && state.note.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func row(_ action: PanelAction, title: String, symbol: String, shortcut: String) -> some View {
        Button { onAction(action) } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 22)
                Text(title).font(.system(size: 13))
                Spacer(minLength: 8)
                Text(shortcut).font(.system(size: 12)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 40)
            .contentShape(Rectangle())
            .background {
                if hoveredRow == action { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.09)) }
            }
        }
        .buttonStyle(.plain)
        .onHover { inside in hoveredRow = inside ? action : (hoveredRow == action ? nil : hoveredRow) }
    }
}

private extension NSImage {
    static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

private final class PanelWindow: NSPanel {
    var onKey: ((NSEvent) -> Bool)?

    init() {
        super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView], backing: .buffered, defer: false)
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        // Without it SwiftUI's onHover never fires in this borderless panel.
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true { return }
        super.sendEvent(event)
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let panel = PanelWindow()
    private let model: AppModel
    let state: PanelState
    private let onAction: (PanelAction) -> Void
    private weak var button: NSStatusBarButton?
    private var outsideClick: Any?
    private(set) var isOpen = false

    init(model: AppModel, onAction: @escaping (PanelAction) -> Void) {
        self.model = model
        self.state = PanelState(model: model)
        self.onAction = onAction
        super.init()
        panel.delegate = self
        panel.onKey = { [weak self] in self?.key($0) ?? false }
    }

    static func surface<Content: View>(_ content: Content, size: NSSize) -> NSView {
        let bounds = NSRect(origin: .zero, size: size)
        let hosting = NSHostingView(rootView: content)
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        let surface = NSVisualEffectView(frame: bounds)
        surface.material = .popover
        surface.blendingMode = .behindWindow
        surface.state = .active
        surface.maskImage = .roundedMask(radius: 16)
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView(frame: bounds)
            glass.style = .regular
            glass.cornerRadius = 16
            glass.contentView = hosting
            glass.autoresizingMask = [.width, .height]
            surface.addSubview(glass)
        } else {
            surface.addSubview(hosting)
        }
        return surface
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if isOpen { close() } else { open(relativeTo: button) }
    }

    func open(relativeTo button: NSStatusBarButton) {
        guard !isOpen, let window = button.window else { return }
        self.button = button
        model.error = nil
        state.sync(with: model.status.request)
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? anchor
        state.height = min(680, screen.height - 16)
        let size = NSSize(width: 320, height: state.height)
        panel.contentView = Self.surface(PanelView(state: state, onAction: { [weak self] in self?.choose($0) }).environmentObject(model), size: size)
        let x = min(max(anchor.maxX - size.width + 12, screen.minX + 8), screen.maxX - size.width - 8)
        let y = max(screen.minY + 8, anchor.minY - size.height - 6)
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        isOpen = true
        button.highlight(true)
        panel.orderFrontRegardless()
        panel.makeKey()
        outsideClick = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        if let outsideClick { NSEvent.removeMonitor(outsideClick); self.outsideClick = nil }
        panel.orderOut(nil)
        button?.highlight(false)
        panel.contentView = nil
    }

    func windowDidResignKey(_ notification: Notification) { close() }

    private func choose(_ action: PanelAction) {
        close()
        onAction(action)
    }

    private var textFocused: Bool { panel.firstResponder is NSTextView }

    /// Arrow keys belong to a text field only once it has text to move through.
    private var editingText: Bool { (panel.firstResponder as? NSTextView)?.string.isEmpty == false }

    private func key(_ event: NSEvent) -> Bool {
        let request = state.request
        let ch = event.charactersIgnoringModifiers?.lowercased()
        if event.modifierFlags.contains(.command) {
            switch ch {
            case ",": choose(.library)
            case "q": choose(.quit)
            default: return false
            }
            return true
        }
        switch event.keyCode {
        case UInt16(kVK_Escape): close()
        case UInt16(kVK_UpArrow): state.move(-2)
        case UInt16(kVK_DownArrow): state.move(2)
        case UInt16(kVK_LeftArrow) where !editingText: state.move(-1)
        case UInt16(kVK_RightArrow) where !editingText: state.move(1)
        case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
            if let request, request.mode == .propose || !state.chosen.isEmpty {
                if state.chosen.isEmpty, let focus = state.focus, focus < state.list.count { state.activate(state.list[focus]) }
                if !state.chosen.isEmpty || !state.note.isEmpty { state.send() }
            } else if let focus = state.focus, focus < state.list.count {
                state.activate(state.list[focus])
            } else {
                return false
            }
        default:
            if let request, request.mode == .propose, !textFocused, let ch, let number = Int(ch), number >= 1, number <= request.items.count,
               let index = state.list.firstIndex(where: { $0.id == request.items[number - 1] }) {
                state.focus = index
                state.chosen = [request.items[number - 1]]
                return true
            }
            return false
        }
        return true
    }
}
