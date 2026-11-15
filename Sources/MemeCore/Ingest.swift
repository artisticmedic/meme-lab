import CryptoKit
import Foundation

public struct SyncReport: Codable, Sendable {
    public var memegen: Int
    public var imgflip: Int
    public var matched: Int
    public var newTemplates: [String]
    public var rising: [String]
    public var seeded: Int
}

extension Library {
    public func sync(now: Date = Date()) async throws -> SyncReport {
        async let memegenItems = Memegen.fetch()
        async let imgflipMemes = Imgflip.fetch()
        let templates = try await memegenItems
        let popular = try await imgflipMemes

        var newTemplates: [String] = []
        for fresh in templates {
            if var existing = items[fresh.id] {
                existing.title = fresh.title
                existing.mediaURL = fresh.mediaURL
                existing.animated = fresh.animated
                existing.keywords = fresh.keywords
                existing.example = fresh.example
                existing.boxes = fresh.boxes
                existing.sourceURL = fresh.sourceURL
                items[fresh.id] = existing
            } else {
                var item = fresh
                item.added = now
                items[item.id] = item
                if lastSync != nil {
                    items[item.id]?.risingSince = now
                    newTemplates.append(item.id)
                }
            }
        }

        let previousTop = Set(imgflipTop)
        var rising: [String] = []
        var matched = 0
        for item in items.values where item.source == "memegen" || item.source == "imgflip" {
            items[item.id]?.popularity = nil
        }
        for (index, meme) in popular.enumerated() {
            let rank = index + 1
            let isNew = !previousTop.isEmpty && !previousTop.contains(meme.id)
            let targetID: String
            if let template = Imgflip.match(meme, in: templates) {
                matched += 1
                targetID = template.id
            } else {
                targetID = "imgflip-\(meme.id)"
                if items[targetID] == nil {
                    var item = Imgflip.item(meme, rank: rank)
                    item.added = now
                    items[targetID] = item
                    if lastSync != nil { newTemplates.append(targetID) }
                }
            }
            items[targetID]?.popularity = rank
            if isNew {
                items[targetID]?.risingSince = now
                rising.append(targetID)
            }
        }
        for item in items.values {
            if let since = item.risingSince, now.timeIntervalSince(since) > 14 * 86_400 {
                items[item.id]?.risingSince = nil
            }
        }

        let seeded = applySeedVibes(popular: popular)
        imgflipTop = popular.map(\.id)
        lastSync = now
        return SyncReport(
            memegen: templates.count, imgflip: popular.count, matched: matched,
            newTemplates: newTemplates.sorted(), rising: rising, seeded: seeded
        )
    }

    /// Fills in vibe, tags and "how it's used" from the bundled seed text, never over an agent's or Tim's own.
    func applySeedVibes(popular: [Imgflip.Response.Meme]) -> Int {
        let seeds = SeedVibes.all
        var count = 0
        for (id, item) in items where item.vibe == nil {
            let key = item.source == "imgflip" ? "imgflip:" + id.replacingOccurrences(of: "imgflip-", with: "") : id
            guard let seed = seeds[key] else { continue }
            items[id]?.vibe = seed.vibe
            items[id]?.tags = Array(Set(item.tags + seed.tags)).sorted()
            if item.howUsed == nil { items[id]?.howUsed = seed.howUsed }
            count += 1
        }
        return count
    }

    public func add(file: URL, recording: Bool = false, title: String? = nil, tags: [String] = [],
                    sourceURL: String? = nil, licence: String? = nil, attribution: String? = nil,
                    source: String? = nil, post: PostRight? = nil) throws -> Item {
        let ext = file.pathExtension.lowercased()
        guard Media.extensions.contains(ext) else {
            throw MemeError("\(file.lastPathComponent) is not a GIF, image or video Meme Lab can use (\(Media.extensions.sorted().joined(separator: ", "))).")
        }
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw MemeError("There is no file at \(file.path).")
        }
        let digest = SHA256.hash(data: try Data(contentsOf: file, options: .mappedIfSafe))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let prefix = recording ? "r-" : "s-"
        let id = prefix + hex.prefix(8)
        if let existing = items[id] { return existing }

        let info = try Media.probe(file)
        let relative = "Saved/\(id).\(ext)"
        let target = root.appending(path: relative)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: file, to: target)

        let name = title ?? file.deletingPathExtension().lastPathComponent
        var item = Item(
            id: id, kind: .clip, title: name, source: source ?? (recording ? "recording" : "saved"),
            rights: Rights(caption: true, post: post ?? (recording ? .freely : .personal)),
            sourceURL: sourceURL, file: relative, animated: info.animated,
            width: info.width, height: info.height, tags: tags.map { $0.lowercased() },
            licence: licence ?? (recording ? "Tim's own recording" : "Saved by Tim; origin unknown, personal use"),
            attribution: attribution
        )
        item.added = Date()
        items[id] = item
        return item
    }

    public func add(url: URL, title: String? = nil, tags: [String] = []) async throws -> Item {
        try Blocklist.check(url)
        let scratch = paths.work.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        if let fileTitle = Wikimedia.fileTitle(for: url) {
            let file = try await Wikimedia.lookup(title: fileTitle)
            let local = scratch.appending(path: file.download.lastPathComponent)
            try await HTTP.get(file.download).write(to: local)
            let name = title ?? file.title.replacingOccurrences(of: "File:", with: "")
                .split(separator: ".").dropLast().joined(separator: ".")
            return try add(
                file: local, title: name, tags: tags, sourceURL: file.page, licence: file.licence,
                attribution: "\(file.artist), \(file.licence), via Wikimedia Commons", source: "wikimedia",
                post: .freely
            )
        }

        let data = try await HTTP.get(url)
        var name = url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent
        if !Media.extensions.contains((name as NSString).pathExtension.lowercased()) {
            name += "." + (Self.sniffExtension(data) ?? "bin")
        }
        let local = scratch.appending(path: name)
        try data.write(to: local)
        return try add(file: local, title: title, tags: tags, sourceURL: url.absoluteString)
    }

    static func sniffExtension(_ data: Data) -> String? {
        let head = [UInt8](data.prefix(12))
        if head.starts(with: [0x47, 0x49, 0x46]) { return "gif" }
        if head.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        if head.starts(with: [0xFF, 0xD8]) { return "jpg" }
        if head.count >= 12, head[0...3] == [0x52, 0x49, 0x46, 0x46], head[8...11] == [0x57, 0x45, 0x42, 0x50] { return "webp" }
        if head.count >= 8, head[4...7] == [0x66, 0x74, 0x79, 0x70] { return "mp4" }
        return nil
    }

    public func importFolder(_ folder: URL, recording: Bool) throws -> (added: [Item], skipped: [String]) {
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { Media.extensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var added: [Item] = []
        var skipped: [String] = []
        for file in files {
            let before = items.count
            do {
                let item = try add(file: file, recording: recording)
                if items.count > before { added.append(item) }
            } catch {
                skipped.append("\(file.lastPathComponent): \(error)")
            }
        }
        return (added, skipped)
    }
}
