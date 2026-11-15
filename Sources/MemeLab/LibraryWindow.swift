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
    @Published var naming = false
    @Published var newCollection = ""
    @Published var dropTargeted = false
}

struct LibraryView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var state: LibraryState
    @FocusState private var searchFocused: Bool
    @FocusState private var gridFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 220).background(SidebarBackground())
            Divider()
            if state.shelf == .settings {
                SettingsView()
            } else {
                main
                Divider()
                DetailPane(state: state).frame(width: 330)
            }
        }
        .frame(minWidth: 1040, minHeight: 640)
        .background(Surface.page)
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

    static func fileURLs(_ providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL { urls.append(url) }
            else if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data,
                    let url = URL(dataRepresentation: data, relativeTo: nil) { urls.append(url) }
        }
        return urls
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                Image(nsImage: Mark.header(size: 26))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Meme Lab").font(.system(size: 15, weight: .semibold))
                    Text(model.statusLine).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(.horizontal, 10).padding(.top, 40).padding(.bottom, 14)
            sectionLabel("Library")
            ForEach(Shelf.main, id: \.self) { shelf in sidebarRow(shelf, title: shelf == .new ? "New and rising" : shelf.title) }
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
            HStack(spacing: 8) {
                SearchField(text: $state.query, focus: $searchFocused)
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
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)
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
            ScrollView {
                if items.isEmpty {
                    Text(emptyText).font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .frame(maxWidth: 360).padding(.top, 80)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 168, maximum: 260), spacing: 10)], spacing: 10) {
                    ForEach(items) { item in
                        Tile(item: item, picked: model.status.picks.contains(item.id), selected: state.selection.contains(item.id), height: 128)
                            .onTapGesture(count: 2) { model.togglePick(item.id) }
                            .simultaneousGesture(TapGesture().modifiers(.command).onEnded { toggleSelection(item.id) })
                            .onTapGesture { state.selection = [item.id]; gridFocused = true }
                            .contextMenu {
                                Button(model.status.picks.contains(item.id) ? "Unpick" : "Pick") { model.togglePick(item.id) }
                                Button("Copy") { Task { await model.copy(item) } }
                                Divider()
                                Button(item.kind == .template ? "Hide…" : "Remove…") { state.removing = targets(item.id) }
                            }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 16)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($gridFocused)
            .onKeyPress(keys: [.delete, .deleteForward]) { _ in
                guard !state.selection.isEmpty else { return .ignored }
                state.removing = state.selection
                return .handled
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyText: String {
        if !state.query.isEmpty { return "Nothing matches “\(state.query)”." }
        switch state.shelf {
        case .clips: return "No clips yet. Drop GIFs, images or videos here, or click Add."
        case .made: return "Nothing made yet. Ask an agent for a meme, and what it makes lands here."
        case .new: return "Nothing new in the last two weeks."
        case .all, .templates: return "The library is empty. Refresh templates in Settings."
        default: return "Nothing here."
        }
    }

    private func targets(_ id: String) -> [String] { state.selection.contains(id) ? state.selection : [id] }

    private func toggleSelection(_ id: String) {
        if let index = state.selection.firstIndex(of: id) { state.selection.remove(at: index) } else { state.selection.append(id) }
    }

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
        Group {
            if state.selection.count > 1 {
                several
            } else if let id = state.selection.last, let item = model.item(id) {
                detail(item)
            } else {
                Text("Select a meme to see how it is used.").font(.system(size: 15)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var several: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(state.selection.count) selected").font(.system(size: 15, weight: .semibold))
            HStack(spacing: 8) {
                Button("Pick") { model.pick(state.selection) }
                    .buttonStyle(PillButtonStyle(prominent: true))
                Button("Remove…") { state.removing = state.selection }.buttonStyle(PillButtonStyle())
            }
            Spacer()
        }
        .padding(18)
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
                HStack(spacing: 8) {
                    Button(picked ? "Unpick" : "Pick") { model.togglePick(item.id) }.buttonStyle(PillButtonStyle(prominent: !picked))
                    Button("Copy") { Task { await model.copy(item) } }.buttonStyle(PillButtonStyle())
                    if let file = model.localFile(item), item.kind != .template {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }.buttonStyle(PillButtonStyle())
                    }
                    Spacer()
                    IconButton(symbol: "trash", label: item.kind == .template ? "Hide" : "Remove") { state.removing = [item.id] }
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
            }
            .padding(18)
        }
        .id(item.id)
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
