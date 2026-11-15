import Foundation

public final class Library {
    public let paths: Paths
    public let config: Config
    public internal(set) var items: [String: Item] = [:]
    public var lastSync: Date?
    public var imgflipTop: [String] = []

    private struct IndexFile: Codable {
        var version: Int
        var lastSync: Date?
        var imgflipTop: [String]
        var items: [Item]
    }

    /// The state last read from or written to disk, so `save` writes only this instance's changes.
    private var loaded: [String: Item] = [:]
    private var loadedSync: Date?
    private var loadedTop: [String] = []

    public init(paths: Paths, config: Config) throws {
        self.paths = paths
        self.config = config
        try reload()
    }

    private static func read(_ url: URL) throws -> IndexFile? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            return try JSONFile.decoder().decode(IndexFile.self, from: Data(contentsOf: url))
        } catch {
            throw MemeError("\(url.path) does not parse (\(error)). Restore it or move it aside, then run `meme sync`.")
        }
    }

    private func adopt(_ file: IndexFile?) {
        items = Dictionary((file?.items ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        lastSync = file?.lastSync
        imgflipTop = file?.imgflipTop ?? []
        loaded = items
        loadedSync = lastSync
        loadedTop = imgflipTop
    }

    /// Re-reads the index, dropping unsaved changes.
    public func reload() throws {
        adopt(try Self.read(paths.index))
    }

    public static func open(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Library {
        let paths = Paths.current(environment: environment)
        return try Library(paths: paths, config: try ConfigStore(url: paths.config).load())
    }

    public var root: URL {
        guard let dir = config.libraryDir, !dir.isEmpty else { return paths.defaultLibrary }
        return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
    }

    /// Merges this instance's changes into the index on disk, so the app and a command saving at once both keep theirs.
    public func save() throws {
        try FileLock.holding(paths.index) {
            let disk = try Self.read(paths.index)
            var merged = Dictionary((disk?.items ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            for (id, item) in items where loaded[id] != item { merged[id] = item }
            for id in loaded.keys where items[id] == nil { merged[id] = nil }
            let file = IndexFile(
                version: 1,
                lastSync: lastSync != loadedSync ? lastSync : disk?.lastSync,
                imgflipTop: imgflipTop != loadedTop ? imgflipTop : disk?.imgflipTop ?? [],
                items: merged.values.sorted { $0.id < $1.id }
            )
            try JSONFile.write(file, to: paths.index)
            adopt(file)
        }
    }

    public var visible: [Item] { items.values.filter { !$0.hidden } }

    public func item(_ id: String) throws -> Item {
        guard let item = items[id], !item.hidden else {
            throw MemeError("There is no item called \(id). Run `meme search <words>` to find ids.")
        }
        return item
    }

    public func upsert(_ item: Item) { items[item.id] = item }

    public func update(_ id: String, _ change: (inout Item) throws -> Void) throws -> Item {
        var item = try self.item(id)
        try change(&item)
        items[id] = item
        return item
    }

    public func localFile(for item: Item) -> URL? {
        if let file = item.file { return root.appending(path: file) }
        if let cached = cachedTemplate(item), FileManager.default.fileExists(atPath: cached.path) { return cached }
        return nil
    }

    func cachedTemplate(_ item: Item) -> URL? {
        guard let remote = item.mediaURL.flatMap(URL.init(string:)) else { return nil }
        let ext = remote.pathExtension.isEmpty ? "jpg" : remote.pathExtension.lowercased()
        return paths.templates.appending(path: "\(item.id).\(ext)")
    }

    public enum MediaSource: Sendable, Equatable {
        case local(URL)
        case remote(URL, cache: URL)
        case missing
    }

    public func mediaSource(for item: Item) -> MediaSource {
        if let local = localFile(for: item) { return .local(local) }
        if let remote = item.mediaURL.flatMap(URL.init(string:)), let target = cachedTemplate(item) { return .remote(remote, cache: target) }
        return .missing
    }

    public func ensureMedia(_ item: Item) async throws -> URL {
        switch mediaSource(for: item) {
        case .local(let local):
            guard FileManager.default.fileExists(atPath: local.path) else {
                throw MemeError("\(item.id)'s file is missing: \(local.path).")
            }
            return local
        case .remote(let remote, let target):
            try await Self.download(remote, to: target)
            return target
        case .missing:
            throw MemeError("\(item.id) has no media.")
        }
    }

    public static func download(_ remote: URL, to target: URL) async throws {
        try Blocklist.check(remote)
        let data = try await HTTP.get(remote)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
    }

    public func uniqueID(prefix: String) -> String {
        let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
        while true {
            let id = prefix + String((0..<5).map { _ in alphabet.randomElement()! })
            if items[id] == nil { return id }
        }
    }

    /// Templates are hidden instead, so a sync does not bring them back.
    public func remove(_ id: String) throws -> Item {
        var item = try self.item(id)
        if let file = localFile(for: item), item.file != nil, FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.trashItem(at: file, resultingItemURL: nil)
        }
        if let made = item.made {
            for extra in [made.mp4, made.png, made.gif].compactMap({ $0 }) where extra != item.file {
                let url = root.appending(path: extra)
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }
            }
        }
        if item.kind == .template {
            item.hidden = true
            items[id] = item
        } else {
            items[id] = nil
        }
        return item
    }
}

public struct ItemSummary: Codable, Sendable {
    public let id: String
    public let kind: Kind
    public let title: String
    public let source: String
    public let animated: Bool
    public let vibe: String?
    public let tags: [String]
    public let howUsed: String?
    public let boxes: Int
    public let rights: String
    public let popularity: Int?
    public let rising: Bool
    public let collections: [String]
    public let media: String?

    public init(_ item: Item, library: Library) {
        id = item.id
        kind = item.kind
        title = item.title
        source = item.source
        animated = item.animated
        vibe = item.vibe
        tags = Array(Set(item.tags + item.keywords.map { $0.lowercased() })).sorted()
        howUsed = item.howUsed
        boxes = item.boxes.isEmpty ? (item.boxCount ?? 0) : item.boxes.count
        rights = item.rights.post.label
        popularity = item.popularity
        rising = item.risingSince != nil
        collections = item.collections
        media = library.localFile(for: item)?.path ?? item.mediaURL
    }
}
