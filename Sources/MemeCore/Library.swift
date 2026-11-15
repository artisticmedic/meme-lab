import Foundation

public final class Library {
    public let paths: Paths
    public let config: Config
    public internal(set) var items: [String: Item] = [:]
    public var lastSync: Date?
    /// Imgflip ids from the previous sync, to spot templates new to the popular list.
    public var imgflipTop: [String] = []

    private struct IndexFile: Codable {
        var version: Int
        var lastSync: Date?
        var imgflipTop: [String]
        var items: [Item]
    }

    public init(paths: Paths, config: Config) throws {
        self.paths = paths
        self.config = config
        guard FileManager.default.fileExists(atPath: paths.index.path) else { return }
        do {
            let file = try JSONFile.decoder().decode(IndexFile.self, from: Data(contentsOf: paths.index))
            items = Dictionary(file.items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            lastSync = file.lastSync
            imgflipTop = file.imgflipTop
        } catch {
            throw MemeError("\(paths.index.path) does not parse (\(error)). Restore it or move it aside, then run `meme sync`.")
        }
    }

    public static func open(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Library {
        let paths = Paths.current(environment: environment)
        return try Library(paths: paths, config: try ConfigStore(url: paths.config).load())
    }

    public var root: URL {
        guard let dir = config.libraryDir, !dir.isEmpty else { return paths.defaultLibrary }
        return URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
    }

    public func save() throws {
        let sorted = items.values.sorted { $0.id < $1.id }
        try JSONFile.write(IndexFile(version: 1, lastSync: lastSync, imgflipTop: imgflipTop, items: sorted), to: paths.index)
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

    /// The item's media on disk, downloading a template into the cache the first time it is used.
    public func ensureMedia(_ item: Item) async throws -> URL {
        if let local = localFile(for: item) {
            guard FileManager.default.fileExists(atPath: local.path) else {
                throw MemeError("\(item.id)'s file is missing: \(local.path).")
            }
            return local
        }
        guard let remote = item.mediaURL.flatMap(URL.init(string:)), let target = cachedTemplate(item) else {
            throw MemeError("\(item.id) has no media.")
        }
        try Blocklist.check(remote)
        let data = try await HTTP.get(remote)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
        return target
    }

    public func uniqueID(prefix: String) -> String {
        let alphabet = Array("abcdefghijkmnpqrstuvwxyz23456789")
        while true {
            let id = prefix + String((0..<5).map { _ in alphabet.randomElement()! })
            if items[id] == nil { return id }
        }
    }

    /// Moves a saved or made item's file to the Trash. Templates are hidden instead, so a sync does not bring them back.
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
