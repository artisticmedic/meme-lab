import AppKit
import MemeCore
import SwiftUI

enum Shelf: Hashable {
    case all, templates, clips, made, new
    case collection(String)
    case settings

    static let main: [Shelf] = [.all, .templates, .clips, .made, .new]

    var title: String {
        switch self {
        case .all: "All"
        case .templates: "Templates"
        case .clips: "Clips"
        case .made: "Made"
        case .new: "New"
        case .collection(let name): name
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .templates: "photo.on.rectangle"
        case .clips: "film"
        case .made: "wand.and.stars"
        case .new: "chart.line.uptrend.xyaxis"
        case .collection: "folder"
        case .settings: "gearshape"
        }
    }
}

/// The files stay the source of truth: every change is written straight back, and edits from `meme` or by hand are picked up as they land.
@MainActor
final class AppModel: ObservableObject {
    let paths: Paths
    let store: StatusStore
    @Published private(set) var items: [Item] = []
    @Published private(set) var status = Status()
    @Published private(set) var config = Config.defaults
    @Published private(set) var configProblem: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var syncing = false
    @Published var error: String?
    private var library: Library?
    private var watcher: FolderWatcher?
    private var stamps: [URL: Date] = [:]
    var onStatusChange: ((Status, Status) -> Void)?

    init(paths: Paths = .current()) {
        self.paths = paths
        self.store = StatusStore(url: paths.status)
        reloadConfig()
        reloadLibrary()
        reloadStatus()
    }

    func startWatching() {
        try? FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
        for file in [paths.config, paths.index, paths.status] { stamps[file] = Self.modified(file) }
        watcher = FolderWatcher(paths.support) { [weak self] in self?.filesChanged() }
    }

    private static func modified(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    func filesChanged() {
        func changed(_ url: URL) -> Bool {
            let stamp = Self.modified(url)
            defer { stamps[url] = stamp }
            return stamps[url] != stamp
        }
        if changed(paths.config) { reloadConfig(); reloadLibrary() }
        if changed(paths.index) { reloadLibrary() }
        if changed(paths.status) { reloadStatus() }
    }

    func reloadConfig() {
        do {
            config = try ConfigStore(url: paths.config).load()
            configProblem = nil
        } catch {
            configProblem = "\(error)"
        }
    }

    func reloadLibrary() {
        do {
            let fresh = try Library(paths: paths, config: config)
            library = fresh
            items = fresh.visible
            lastSync = fresh.lastSync
        } catch {
            self.error = "\(error)"
        }
    }

    func reloadStatus() {
        let old = status
        status = store.load()
        if let request = status.request, !AppLink.isAlive(request.pid) {
            AppLink.withdraw(request.id, store: store)
            status = store.load()
        }
        if old != status { onStatusChange?(old, status) }
    }

    /// Shows a status without writing it, for `--render`.
    func stage(_ staged: Status) { status = staged }

    var collections: [String] { Array(Set(items.flatMap(\.collections))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }

    func count(_ shelf: Shelf) -> Int { pool(shelf).count }

    private func pool(_ shelf: Shelf) -> [Item] {
        switch shelf {
        case .all, .settings: items
        case .templates: items.filter { $0.kind == .template }
        case .clips: items.filter { $0.kind == .clip }
        case .made: items.filter { $0.kind == .made }
        case .new: items.filter { $0.risingSince != nil }
        case .collection(let name): items.filter { $0.collections.contains(name) }
        }
    }

    func items(_ shelf: Shelf, matching query: String, only ids: [String] = []) -> [Item] {
        var pool = pool(shelf)
        if !ids.isEmpty {
            let order = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            pool = pool.filter { order[$0.id] != nil }.sorted { order[$0.id]! < order[$1.id]! }
        }
        let words = query.trimmingCharacters(in: .whitespaces)
        if !words.isEmpty { return Search.run(SearchQuery(words: words, limit: pool.count), in: pool) }
        if !ids.isEmpty { return pool }
        switch shelf {
        case .clips, .made: return pool.sorted { $0.added > $1.added }
        default: return pool.sorted { ($0.popularity ?? 1000, $0.title) < ($1.popularity ?? 1000, $1.title) }
        }
    }

    func item(_ id: String) -> Item? { items.first { $0.id == id } }

    func mediaSource(_ item: Item) -> Library.MediaSource { library?.mediaSource(for: item) ?? .missing }

    func localFile(_ item: Item) -> URL? {
        guard case .local(let url) = mediaSource(item), FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    var statusLine: String {
        if let problem = configProblem { return problem }
        if let request = status.request {
            let who = request.from ?? "Your agent"
            switch request.mode {
            case .propose: return "\(who) has \(request.items.count) option\(request.items.count == 1 ? "" : "s"). Pick one."
            case .pick: return "\(who) wants up to \(request.max). Pick \(request.max == 1 ? "one" : "them")."
            }
        }
        if items.isEmpty { return "The library is empty. Refresh templates in Settings." }
        let picked = status.picks.count
        return "\(items.count) memes." + (picked > 0 ? " \(picked) picked." : "")
    }

    static let trayLimit = 4

    func togglePick(_ id: String) {
        perform {
            try store.update { status in
                if let index = status.picks.firstIndex(of: id) { status.picks.remove(at: index) }
                else if status.picks.count < Self.trayLimit { status.picks.append(id) }
            }
        }
        reloadStatus()
    }

    func clearPicks() {
        perform { try store.update { $0.picks = [] } }
        reloadStatus()
    }

    func answer(_ request: AppRequest, chosen: [String], note: String) {
        perform {
            if try !AppLink.answer(request.id, chosen: chosen, note: note, store: store) {
                error = "That request was already answered or withdrawn."
            }
        }
        reloadStatus()
    }

    func prompt(idea: String) -> String {
        let idea = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Use Meme Lab (the `meme` command). Run `meme picks` to see the memes I picked (\(status.picks.joined(separator: ", "))), "
            + "then make a meme that combines them\(idea.isEmpty ? "" : ": \(idea)"). Show me the options with `meme propose`."
    }

    func copyPrompt(idea: String) {
        perform { try Clipboard.copyText(prompt(idea: idea)) }
    }

    /// Runs the configured command in a login shell, so it sees the same PATH as a terminal.
    func askAgent(idea: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", config.agentCommand]
        process.environment = ProcessInfo.processInfo.environment.merging(["MEME_PROMPT": prompt(idea: idea)]) { _, new in new }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] done in
            guard done.terminationStatus != 0 else { return }
            let code = done.terminationStatus
            Task { @MainActor in self?.error = "The Ask agent command failed (exit \(code)). Check it in Settings." }
        }
        perform { try process.run() }
    }

    func copy(_ item: Item) async {
        guard let file = await MediaStore.shared.file(for: mediaSource(item)) else {
            error = "\(item.title) has no file to copy yet."
            return
        }
        perform { try Clipboard.copyFile(file) }
    }

    func add(_ files: [URL], recording: Bool) {
        mutate { library in
            var refused: [String] = []
            for file in files {
                do { _ = try library.add(file: file, recording: recording) } catch { refused.append("\(error)") }
            }
            if !refused.isEmpty { self.error = refused.joined(separator: " ") }
        }
    }

    func remove(_ ids: [String]) {
        mutate { library in
            for id in ids { _ = try library.remove(id) }
        }
        perform { try store.update { $0.picks.removeAll { ids.contains($0) } } }
        reloadStatus()
    }

    func update(_ id: String, _ change: @escaping (inout Item) -> Void) {
        mutate { library in _ = try library.update(id, change) }
    }

    func setting(_ key: String, _ value: String) {
        perform { config = try ConfigStore(url: paths.config).set(key, to: value) }
        reloadConfig()
        if key == "libraryDir" { reloadLibrary() }
    }

    func sync() {
        guard !syncing else { return }
        syncing = true
        let paths = paths, config = config
        Task {
            do {
                let fresh = try Library(paths: paths, config: config)
                _ = try await fresh.sync()
                try fresh.save()
            } catch {
                self.error = "\(error)"
            }
            syncing = false
            reloadLibrary()
        }
    }

    private func mutate(_ change: (Library) throws -> Void) {
        perform {
            let fresh = try Library(paths: paths, config: config)
            try change(fresh)
            try fresh.save()
        }
        reloadLibrary()
    }

    private func perform(_ work: () throws -> Void) {
        do { try work() } catch { self.error = "\(error)" }
    }
}

/// Atomic writes replace files, so watching the folder, not the files, catches every save.
final class FolderWatcher {
    private let source: DispatchSourceFileSystemObject

    init?(_ folder: URL, onChange: @escaping @MainActor () -> Void) {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { onChange() } }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    deinit { source.cancel() }
}
