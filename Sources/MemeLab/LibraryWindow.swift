import AppKit
import MemeCore
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LibraryState: ObservableObject {
    @Published var shelf: Shelf = .all
    @Published var query = ""
    /// In click order; the last one fills the detail pane.
    @Published var selection: [String] = []
    @Published var removing: [String]?
    @Published var making: [String]?
    @Published var naming = false
    @Published var newCollection = ""
    @Published var dropTargeted = false
    /// Set by Edit › Find, possibly before the window exists; the view clears it once the field has focus.
    @Published var wantsSearchFocus = false
    private var anchor: String?

    /// Command toggles one item, Shift selects the run from the last plain click, and a plain click selects one.
    func click(_ id: String, in order: [String]) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.command) {
            if let index = selection.firstIndex(of: id) { selection.remove(at: index) } else { selection.append(id) }
            anchor = id
        } else if modifiers.contains(.shift), let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) {
            selection = from <= to ? Array(order[from...to]) : Array(order[to...from].reversed())
        } else {
            selection = [id]
            anchor = id
        }
    }
}

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var state: LibraryState
    @FocusState private var searchFocused: Bool
    @FocusState private var gridFocused: Bool
    @State private var copiedPrompt = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 220).background(SidebarBackground())
            Divider()
            if state.shelf == .settings {
                SettingsView()
            } else {
                main
                if !state.selection.isEmpty {
                    Divider()
                    DetailPane(state: state).frame(width: 340).transition(.move(edge: .trailing))
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: state.selection.isEmpty)
        .onAppear(perform: focusSearchIfAsked)
        .onChange(of: state.wantsSearchFocus) { focusSearchIfAsked() }
        .onChange(of: model.status.picks) {
            if state.shelf == .picked { state.selection.removeAll { !model.status.picks.contains($0) } }
        }
        .onChange(of: model.items) { state.selection.removeAll { model.item($0) == nil } }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 900, minHeight: 600)
        .background(Surface.page)
        .sheet(isPresented: Binding(get: { state.making != nil }, set: { if !$0 { state.making = nil } })) {
            let ids = state.making ?? []
            MakeView(ids: ids, items: ids.compactMap(model.item)) { state.making = nil }.environmentObject(model)
        }
        .onDrop(of: [.fileURL], isTargeted: $state.dropTargeted) { providers in
            Task { model.add(await Self.fileURLs(providers), recording: false) }
            return true
        }
        .overlay {
            if state.dropTargeted {
                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [6, 4])).padding(6)
            }
        }
        .alert("Remove \(state.removing?.count ?? 0 == 1 ? "this meme" : "\(state.removing?.count ?? 0) memes")?", isPresented: Binding(
            get: { state.removing != nil }, set: { if !$0 { state.removing = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let ids = state.removing { model.remove(ids); state.selection.removeAll { ids.contains($0) } }
                state.removing = nil
            }
            Button("Cancel", role: .cancel) { state.removing = nil }
        } message: {
            Text("Saved and made files go to the Trash. Templates are hidden, and a refresh does not bring them back.")
        }
        .alert("New Collection", isPresented: $state.naming) {
            TextField("Name", text: $state.newCollection)
            Button("Create") {
                let name = state.newCollection.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty {
                    model.update(state.selection) { if !$0.collections.contains(name) { $0.collections.append(name) } }
                    state.shelf = .collection(name)
                }
                state.newCollection = ""
            }
            Button("Cancel", role: .cancel) { state.newCollection = "" }
        } message: {
            Text("The selected memes go into it.")
        }
    }

    private func focusSearchIfAsked() {
        guard state.wantsSearchFocus else { return }
        DispatchQueue.main.async {
            searchFocused = true
            state.wantsSearchFocus = false
        }
    }

    static func fileURLs(_ providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            let loaded = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
            if let url = loaded as? URL { urls.append(url) }
            else if let data = loaded as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) { urls.append(url) }
        }
        return urls
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear.frame(height: topBarHeight).background(WindowDragArea()).padding(.horizontal, -8)
            sectionLabel("Library")
            ForEach(Shelf.library, id: \.self) { shelf in sidebarRow(shelf, title: shelf.title) }
            sectionLabel("Collections").padding(.top, 12)
            ForEach(model.collections, id: \.self) { name in
                sidebarRow(.collection(name), title: name)
                    .contextMenu {
                        Button("Delete Collection") {
                            model.update(model.items.filter { $0.collections.contains(name) }.map(\.id)) { $0.collections.removeAll { $0 == name } }
                            if state.shelf == .collection(name) { state.shelf = .all }
                        }
                    }
            }
            Button {
                state.naming = true
            } label: {
                Label("New Collection…", systemImage: "plus").font(.system(size: 13)).foregroundStyle(.secondary)
                    .padding(.horizontal, 10).frame(height: 30, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(state.selection.isEmpty)
            .help(state.selection.isEmpty ? "Select memes first; they go into the new collection." : "Make a collection from the selected memes.")
            Spacer()
            if let notice = model.notice {
                Text(notice).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 10).padding(.bottom, 6)
            }
            sidebarRow(.settings, title: "Settings")
                .padding(.bottom, 10)
        }
        .padding(.horizontal, 8)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.bottom, 2)
    }

    private func sidebarRow(_ shelf: Shelf, title: String) -> some View {
        Button {
            state.shelf = shelf
            state.selection = []
        } label: {
            HStack(spacing: 9) {
                Image(systemName: shelf.symbol).font(.system(size: 14)).foregroundStyle(.secondary).frame(width: 20)
                Text(title).font(.system(size: 13)).lineLimit(1)
                Spacer()
                if shelf != .settings { Text("\(model.count(shelf))").font(.system(size: 12).monospacedDigit()).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 10).frame(height: 32)
            .contentShape(Rectangle())
            .background {
                if state.shelf == shelf { RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.09)) }
            }
        }
        .buttonStyle(.plain)
    }

    private var main: some View {
        let items = model.items(state.shelf, matching: state.query)
        return VStack(spacing: 0) {
            TopBar {
                SearchField(text: $state.query, prompt: model.count(state.shelf) > 1 ? "Search \(model.count(state.shelf)) memes by name or feeling" : "Search by name or feeling", focus: $searchFocused)
                Menu {
                    Button("Add Files…") { addFiles(recording: false) }
                    Button("Add My Own Recordings…") { addFiles(recording: true) }
                } label: {
                    Text("Add")
                }
                .menuStyle(.button)
                .buttonStyle(PillButtonStyle())
                .fixedSize()
                if [.made, .clips].contains(state.shelf), !items.isEmpty {
                    Button("Remove All…") { state.removing = items.map(\.id) }.buttonStyle(PillButtonStyle())
                }
            }
            if let error = model.error {
                HStack(alignment: .top) {
                    Text(error).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    IconButton(symbol: "xmark", label: "Dismiss") { model.error = nil }
                }
                .padding(.leading, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.07)))
                .padding(.horizontal, 16).padding(.bottom, 8)
            }
            if state.shelf == .popular, state.query.isEmpty, !items.isEmpty {
                Text("Imgflip's 100 most used memes, most used first. New marks memes added to the library or the list in the last two weeks.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.bottom, 8)
            }
            GeometryReader { viewport in
                ScrollView {
                    VStack(spacing: 0) {
                        if items.isEmpty { emptyState }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 168, maximum: 260), spacing: 10, alignment: .top)], spacing: 10) {
                            ForEach(items) { item in
                                Tile(item: item, picked: model.status.picks.contains(item.id), selected: state.selection.contains(item.id),
                                     height: 128, onTogglePick: { model.togglePick(item.id) })
                                    .onTapGesture {
                                        gridFocused = true
                                        if (NSApp.currentEvent?.clickCount ?? 1) >= 2, canMake([item.id]) {
                                            state.making = [item.id]
                                        } else {
                                            state.click(item.id, in: items.map(\.id))
                                        }
                                    }
                                    .contextMenu {
                                        if canMake(targets(item.id)) {
                                            Button("Make GIF…") { state.making = targets(item.id) }
                                        }
                                        Button(model.status.picks.contains(item.id) ? "Unpick" : "Pick") { model.togglePick(item.id) }
                                        Button("Copy") { Task { await model.copy(targets(item.id).compactMap(model.item)) } }
                                        Divider()
                                        Button(item.kind == .template ? "Hide…" : "Remove…") { state.removing = targets(item.id) }
                                    }
                            }
                        }
                        .padding(.horizontal, 16).padding(.bottom, 16)
                    }
                    .frame(minHeight: viewport.size.height, alignment: .top)
                    .contentShape(Rectangle())
                    .onTapGesture { state.selection = [] }
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($gridFocused)
            .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                guard !state.selection.isEmpty else { return .ignored }
                state.removing = state.selection
                return .handled
            }
            .onKeyPress(.escape) {
                guard !state.selection.isEmpty else { return .ignored }
                state.selection = []
                return .handled
            }
            if !model.status.picks.isEmpty { picksBar }
        }
        .frame(maxWidth: .infinity)
    }

    private var picksBar: some View {
        let picks = model.status.picks.compactMap(model.item)
        let ids = picks.map(\.id)
        return VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Text("\(picks.count) picked").font(.system(size: 13, weight: .semibold)).padding(.trailing, 4)
                ForEach(picks) { item in
                    MediaPreview(item: item, playing: false, maxPixel: 120)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button { model.togglePick(item.id) } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 15)).symbolRenderingMode(.palette)
                                    .foregroundStyle(Color.white, Color.black.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            .offset(x: 5, y: -5)
                            .accessibilityLabel("Unpick \(item.title)")
                        }
                        .help(item.title)
                }
                Spacer(minLength: 12)
                if canMake(ids) {
                    Button("Make GIF") { state.making = ids }.buttonStyle(PillButtonStyle(prominent: true))
                }
                Button(copiedPrompt ? "Copied" : "Copy Prompt") {
                    model.copyPrompt(idea: "")
                    copiedPrompt = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copiedPrompt = false }
                }
                .buttonStyle(PillButtonStyle())
                .help("Copies a prompt that tells your agent to make a meme from these picks.")
                if !model.config.agentCommand.isEmpty {
                    Button("Ask Agent") { model.askAgent(idea: "") }.buttonStyle(PillButtonStyle())
                }
                Button("Clear") { model.clearPicks() }.buttonStyle(PillButtonStyle())
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .background(Surface.card)
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 10) {
            if !state.query.isEmpty {
                emptyText("Nothing matches “\(state.query)”.", nil)
                if state.shelf != .all {
                    Button("Search All Memes") { state.shelf = .all }.buttonStyle(PillButtonStyle())
                }
            } else {
                switch state.shelf {
                case .clips:
                    emptyText("No clips yet", "Clips are GIFs and videos of your own, like reactions you saved or screen recordings. Drop them here or add them.")
                    HStack(spacing: 8) {
                        Button("Add Files…") { addFiles(recording: false) }.buttonStyle(PillButtonStyle(prominent: true))
                        Button("Add My Own Recordings…") { addFiles(recording: true) }.buttonStyle(PillButtonStyle())
                    }
                case .made:
                    emptyText("Nothing made yet", "GIFs you make land here, whether you make them in this window or an agent makes them with the meme command.")
                    Button("Browse Templates") { state.shelf = .templates }.buttonStyle(PillButtonStyle(prominent: true))
                case .picked:
                    emptyText("Nothing picked", "Picks are the memes you hand to an agent, up to four. Click the circle on a tile to pick it.")
                    Button("Browse Templates") { state.shelf = .templates }.buttonStyle(PillButtonStyle(prominent: true))
                case .popular:
                    emptyText("Not loaded yet", "Imgflip's 100 most used memes show here once the templates refresh.")
                    Button(model.syncing ? "Refreshing…" : "Refresh Now") { model.sync() }.buttonStyle(PillButtonStyle(prominent: true)).disabled(model.syncing)
                case .all, .templates:
                    emptyText("The library is empty", "Load about 270 templates from memegen and Imgflip.")
                    Button(model.syncing ? "Refreshing…" : "Refresh Now") { model.sync() }.buttonStyle(PillButtonStyle(prominent: true)).disabled(model.syncing)
                case .collection, .settings:
                    emptyText("This collection is empty.", nil)
                }
            }
        }
        .frame(maxWidth: 400).padding(.top, 80)
    }

    private func emptyText(_ title: String, _ detail: String?) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 17, weight: .semibold))
            if let detail { Text(detail).font(.system(size: 14)).foregroundStyle(.secondary) }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func targets(_ id: String) -> [String] { state.selection.contains(id) ? state.selection : [id] }

    private func canMake(_ ids: [String]) -> Bool { DetailPane.canMake(ids, model: model) }

    private func addFiles(recording: Bool) {
        guard let files = Self.chooseMedia() else { return }
        model.add(files, recording: recording)
    }

    static func chooseMedia() -> [URL]? {
        let open = NSOpenPanel()
        open.allowsMultipleSelection = true
        open.canChooseDirectories = false
        open.allowedContentTypes = [.gif, .image, .movie]
        open.prompt = "Add"
        return open.runModal() == .OK ? open.urls : nil
    }
}

struct DetailPane: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var state: LibraryState
    @State private var newTag = ""
    @State private var newCollection = ""

    var body: some View {
        VStack(spacing: 0) {
            TopBar {
                Spacer()
                IconButton(symbol: "xmark", label: "Close") { state.selection = [] }
                    .padding(.trailing, -8)
            }
            if state.selection.count > 1 {
                several
            } else if let id = state.selection.last, let item = model.item(id) {
                detail(item)
            }
            Spacer(minLength: 0)
        }
    }

    private var several: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(state.selection.count) selected").font(.system(size: 17, weight: .semibold))
            HStack(spacing: 8) {
                if Self.canMake(state.selection, model: model) {
                    Button("Make GIF") { state.making = state.selection }.buttonStyle(PillButtonStyle(prominent: true))
                }
                let allPicked = state.selection.allSatisfy(model.status.picks.contains)
                Button(allPicked ? "Unpick All" : "Pick All") { allPicked ? model.unpick(state.selection) : model.pick(state.selection) }
                    .buttonStyle(PillButtonStyle())
                Button("Remove…") { state.removing = state.selection }.buttonStyle(PillButtonStyle())
            }
            if state.selection.count > 4 {
                Text("Select up to four to make one GIF from them.").font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detail(_ item: Item) -> some View {
        let picked = model.status.picks.contains(item.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MediaPreview(item: item, playing: true, fill: false, maxPixel: 720)
                    .frame(height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.system(size: 17, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(origin(item)).font(.system(size: 13)).foregroundStyle(.secondary)
                }
                FlowLayout(spacing: 8) {
                    if Self.canMake([item.id], model: model) {
                        Button("Make GIF") { state.making = [item.id] }.buttonStyle(PillButtonStyle(prominent: true))
                    }
                    Button(picked ? "Unpick" : "Pick") { model.togglePick(item.id) }.buttonStyle(PillButtonStyle(selected: picked))
                    Button("Copy") { Task { await model.copy([item]) } }.buttonStyle(PillButtonStyle())
                    if let file = model.localFile(item), item.kind != .template {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }.buttonStyle(PillButtonStyle())
                    }
                }
                if let made = item.made {
                    field("Captions", made.captions.filter { !$0.isEmpty }.joined(separator: " / "))
                    field("Made as", model.recipe(item) ?? "")
                }
                EditableField(title: "Feeling", value: item.vibe ?? "", prompt: "Like “smug calm while everything burns”") { text in
                    model.update(item.id) { $0.vibe = text.isEmpty ? nil : text }
                }
                EditableField(title: "How it is used", value: item.howUsed ?? "", prompt: "One sentence on the format") { text in
                    model.update(item.id) { $0.howUsed = text.isEmpty ? nil : text }
                }
                if !item.example.isEmpty { field("Example", item.example.filter { !$0.isEmpty }.joined(separator: " / ")) }
                VStack(alignment: .leading, spacing: 6) {
                    label("Tags")
                    FlowLayout {
                        ForEach(item.tags, id: \.self) { tag in
                            Chip(text: tag) { model.update(item.id) { $0.tags.removeAll { $0 == tag } } }
                        }
                    }
                    InputField(prompt: "Add a tag", text: $newTag)
                        .onSubmit {
                            let tag = newTag.trimmingCharacters(in: .whitespaces).lowercased()
                            if !tag.isEmpty { model.update(item.id) { if !$0.tags.contains(tag) { $0.tags.append(tag); $0.tags.sort() } } }
                            newTag = ""
                        }
                }
                VStack(alignment: .leading, spacing: 6) {
                    label("Collections")
                    FlowLayout {
                        ForEach(item.collections, id: \.self) { name in
                            Chip(text: name) { model.update(item.id) { $0.collections.removeAll { $0 == name } } }
                        }
                    }
                    InputField(prompt: "Add to a collection", text: $newCollection)
                        .onSubmit {
                            let name = newCollection.trimmingCharacters(in: .whitespaces)
                            if !name.isEmpty { model.update(item.id) { if !$0.collections.contains(name) { $0.collections.append(name) } } }
                            newCollection = ""
                        }
                }
                VStack(alignment: .leading, spacing: 4) {
                    label("Use")
                    Text(item.rights.post.label).font(.system(size: 13))
                    if let licence = item.licence { Text(licence).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    if let attribution = item.attribution { Text(attribution).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    if let source = item.sourceURL.flatMap(URL.init(string:)) {
                        Link("Open the source", destination: source).font(.system(size: 13))
                    }
                }
                Button(item.kind == .template ? "Hide This Template…" : "Move to Trash…") { state.removing = [item.id] }
                    .buttonStyle(PillButtonStyle())
                    .padding(.top, 6)
            }
            .padding(.horizontal, 18).padding(.bottom, 18)
        }
        .id(item.id)
    }

    static func canMake(_ ids: [String], model: AppModel) -> Bool {
        (1...4).contains(ids.count) && ids.allSatisfy { model.item($0)?.rights.caption == true }
    }

    private func origin(_ item: Item) -> String {
        var parts: [String]
        switch item.kind {
        case .template: parts = ["Template from \(item.source)"]
        case .clip: parts = [item.source == "recording" ? "Your recording" : "Clip, \(item.source)"]
        case .made: parts = ["Made \(item.added.formatted(.relative(presentation: .named)))"]
        }
        if let rank = item.popularity { parts.append("Imgflip #\(rank)") }
        if item.risingSince != nil { parts.append("New and rising") }
        return parts.joined(separator: " · ")
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
    }

    private func field(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label(title)
            Text(value).font(.system(size: 13)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct EditableField: View {
    let title: String
    let value: String
    let prompt: String
    let save: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            TextField(prompt, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 9).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(focused ? 0.08 : 0.04)))
                .onSubmit(commit)
                .onChange(of: focused) { _, now in if !now { commit() } }
                .onDisappear(perform: commit)
        }
        .onAppear { text = value }
        .onChange(of: value) { _, fresh in if !focused { text = fresh } }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed != value { save(trimmed) }
    }
}
