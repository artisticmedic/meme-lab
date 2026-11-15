import Foundation

/// GIPHY, KLIPY and Tenor terms forbid downloading, captioning or re-hosting their media. Links only.
public enum Blocklist {
    static let services: [(name: String, domains: [String])] = [
        ("GIPHY", ["giphy.com", "gph.is"]),
        ("KLIPY", ["klipy.com", "klipy.co"]),
        ("Tenor", ["tenor.com", "tenor.co", "tenor.googleapis.com"]),
    ]

    public static func service(for url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        return services.first { $0.domains.contains { host == $0 || host.hasSuffix("." + $0) } }?.name
    }

    public static func check(_ url: URL) throws {
        if let name = service(for: url) {
            throw MemeError("\(name) media is link-only: its terms forbid downloading, captioning or re-hosting it. Share the link itself instead.")
        }
    }
}

/// Parses the small YAML subset memegen's `config.yml` files use: top-level scalars and lists of scalars or flat maps.
public enum MemegenConfigParser {
    public struct Parsed: Equatable {
        public var name: String?
        public var source: String?
        public var keywords: [String] = []
        public var example: [String] = []
        public var boxes: [TextBox] = []
    }

    private static let mapLists: Set<String> = ["text", "overlay"]

    public static func parse(_ text: String) -> Parsed {
        var scalars: [String: String] = [:]
        var lists: [String: [String]] = [:]
        var maps: [String: [[String: String]]] = [:]
        var key: String?

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.replacingOccurrences(of: "\t", with: "  ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = line.prefix { $0 == " " }.count

            if indent == 0, !trimmed.hasPrefix("-") {
                let (k, v) = split(trimmed)
                key = k
                if let v, !v.isEmpty { scalars[k] = unquote(v) }
                continue
            }
            guard let key else { continue }
            let isMapList = mapLists.contains(key)
            if trimmed.hasPrefix("-") {
                let rest = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                if isMapList {
                    let pair = mapPair(rest)
                    maps[key, default: []].append(pair.map { [$0.0: $0.1] } ?? [:])
                } else {
                    lists[key, default: []].append(unquote(rest))
                }
            } else if isMapList, let pair = mapPair(trimmed), !(maps[key]?.isEmpty ?? true) {
                maps[key]![maps[key]!.count - 1][pair.0] = pair.1
            }
        }

        var parsed = Parsed()
        parsed.name = scalars["name"]
        parsed.source = scalars["source"]
        parsed.keywords = (lists["keywords"] ?? []).filter { !$0.isEmpty }
        parsed.example = lists["example"] ?? []
        parsed.boxes = (maps["text"] ?? []).map { m in
            func number(_ k: String, _ fallback: Double) -> Double { m[k].flatMap(Double.init) ?? fallback }
            return TextBox(
                anchorX: number("anchor_x", 0), anchorY: number("anchor_y", 0),
                scaleX: number("scale_x", 1), scaleY: number("scale_y", 0.2),
                angle: number("angle", 0), style: m["style"] ?? "upper",
                color: m["color"] ?? "white", font: m["font"] ?? "thick"
            )
        }
        return parsed
    }

    private static func split(_ line: String) -> (String, String?) {
        guard let colon = line.firstIndex(of: ":") else { return (line, nil) }
        let k = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
        let v = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return (k, v)
    }

    private static func mapPair(_ text: String) -> (String, String)? {
        let (k, v) = split(text)
        guard let v, !k.isEmpty else { return nil }
        return (k, unquote(v))
    }

    static func unquote(_ value: String) -> String {
        if value.count >= 2, value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
        }
        return value
    }
}

enum Memegen {
    static let repo = "jacebrowning/memegen"
    static let raw = "https://raw.githubusercontent.com/\(repo)/main/templates"

    struct Tree: Decodable {
        struct Entry: Decodable { let path: String }
        let tree: [Entry]
        let truncated: Bool
    }

    /// Template id to the file name of its default image, preferring an animated one.
    static func templateFiles(from tree: Tree) -> [String: String] {
        var defaults: [String: [String]] = [:]
        var configs: Set<String> = []
        for entry in tree.tree {
            let parts = entry.path.split(separator: "/")
            guard parts.count == 3, parts[0] == "templates", !parts[1].hasPrefix("_") else { continue }
            let id = String(parts[1])
            if parts[2] == "config.yml" { configs.insert(id) }
            if parts[2].hasPrefix("default.") { defaults[id, default: []].append(String(parts[2])) }
        }
        var result: [String: String] = [:]
        for id in configs {
            let files = defaults[id] ?? []
            if let chosen = files.first(where: { $0.hasSuffix(".gif") }) ?? files.first(where: { $0.hasSuffix(".jpg") }) ?? files.first {
                result[id] = chosen
            }
        }
        return result
    }

    static func fetch() async throws -> [Item] {
        let treeURL = URL(string: "https://api.github.com/repos/\(repo)/git/trees/main?recursive=1")!
        let tree = try JSONDecoder().decode(Tree.self, from: try await HTTP.get(treeURL))
        let files = templateFiles(from: tree)
        guard !files.isEmpty else { throw MemeError("memegen's file list came back without templates.") }

        return try await withThrowingTaskGroup(of: Item?.self) { group in
            var pending = files.sorted { $0.key < $1.key }[...]
            var items: [Item] = []
            func enqueue() {
                guard let (id, file) = pending.popFirst() else { return }
                group.addTask {
                    let data = try await HTTP.get(URL(string: "\(raw)/\(id)/config.yml")!)
                    return item(id: id, file: file, config: MemegenConfigParser.parse(String(decoding: data, as: UTF8.self)))
                }
            }
            for _ in 0..<12 { enqueue() }
            while let next = try await group.next() {
                if let next { items.append(next) }
                enqueue()
            }
            return items
        }
    }

    static func item(id: String, file: String, config: MemegenConfigParser.Parsed) -> Item {
        Item(
            id: id, kind: .template, title: config.name ?? id, source: "memegen",
            rights: Rights(caption: true, post: .personal),
            sourceURL: config.source, mediaURL: "\(raw)/\(id)/\(file)", animated: file.hasSuffix(".gif"),
            keywords: config.keywords, example: config.example, boxes: config.boxes,
            licence: "Third-party template image, kept for personal use; not redistributed"
        )
    }
}

enum Imgflip {
    struct Response: Decodable {
        struct Meme: Decodable {
            let id: String
            let name: String
            let url: String
            let width: Int
            let height: Int
            let box_count: Int
        }
        struct Payload: Decodable { let memes: [Meme] }
        let success: Bool
        let data: Payload
    }

    static func fetch() async throws -> [Response.Meme] {
        let data = try await HTTP.get(URL(string: "https://api.imgflip.com/get_memes")!)
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.success else { throw MemeError("Imgflip's popular list did not answer successfully.") }
        return response.data.memes
    }

    static func item(_ meme: Response.Meme, rank: Int) -> Item {
        Item(
            id: "imgflip-\(meme.id)", kind: .template, title: meme.name, source: "imgflip",
            rights: Rights(caption: true, post: .personal),
            mediaURL: meme.url, animated: meme.url.lowercased().hasSuffix(".gif"),
            width: meme.width, height: meme.height, boxCount: meme.box_count,
            licence: "Third-party template image, kept for personal use; not redistributed", popularity: rank
        )
    }

    private static let filler: Set<String> = ["a", "an", "the", "at", "of", "to", "is", "my", "vs"]

    static func words(_ text: String) -> Set<String> { Set(Search.normalize(text)).subtracting(filler) }

    /// Finds the memegen template that is the same meme: the same words in a name or keyword first, then one name
    /// of two or more words contained in the other ("Hotline Bling" in "Drake Hotline Bling").
    static func match(_ meme: Response.Meme, in templates: [Item]) -> Item? {
        let name = words(meme.name)
        guard !name.isEmpty else { return nil }
        let keyed = templates.map { template in (template, ([template.title] + template.keywords).map(words).filter { !$0.isEmpty }) }
        if let exact = keyed.first(where: { $0.1.contains(name) }) { return exact.0 }
        return keyed.first { _, keys in
            keys.contains { key in (key.count >= 2 && key.isSubset(of: name)) || (name.count >= 2 && name.isSubset(of: key)) }
        }?.0
    }
}

enum Wikimedia {
    struct Response: Decodable {
        struct Query: Decodable { let pages: [String: Page] }
        struct Page: Decodable { let title: String?; let imageinfo: [Info]? }
        struct Info: Decodable {
            let url: String
            let descriptionurl: String?
            let extmetadata: [String: Value]?
        }
        /// Commons metadata values are usually strings but sometimes numbers; only the strings are used.
        struct Value: Decodable {
            let value: String?
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                value = try? c.decode(String.self, forKey: .value)
            }
            enum CodingKeys: String, CodingKey { case value }
        }
        let query: Query?
    }

    struct File {
        let title: String
        let download: URL
        let page: String
        let licence: String
        let artist: String
    }

    static func fileTitle(for url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        let last = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        if host == "commons.wikimedia.org", last.hasPrefix("File:") { return last }
        if host == "upload.wikimedia.org", !last.isEmpty { return "File:" + last }
        return nil
    }

    static func lookup(title: String) async throws -> File {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"), .init(name: "format", value: "json"),
            .init(name: "prop", value: "imageinfo"), .init(name: "iiprop", value: "url|extmetadata"),
            .init(name: "titles", value: title),
        ]
        let response = try JSONDecoder().decode(Response.self, from: try await HTTP.get(components.url!))
        guard let page = response.query?.pages.values.first, let info = page.imageinfo?.first,
              let download = URL(string: info.url)
        else { throw MemeError("Wikimedia Commons has no file called \(title).") }
        let meta = info.extmetadata ?? [:]
        return File(
            title: page.title ?? title, download: download, page: info.descriptionurl ?? info.url,
            licence: meta["LicenseShortName"]?.value.map(stripTags) ?? "See the file page",
            artist: meta["Artist"]?.value.map(stripTags) ?? "Unknown"
        )
    }

    static func stripTags(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
