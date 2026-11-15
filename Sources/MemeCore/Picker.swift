import Foundation

public enum PickerMode: Sendable, Equatable {
    case browse
    case pick(max: Int)
    case propose(from: String?)
    case klipy(query: String, results: [Klipy.Result], key: String)

    var name: String {
        switch self {
        case .browse: "browse"
        case .pick: "pick"
        case .propose: "propose"
        case .klipy: "klipy"
        }
    }

    var waits: Bool {
        if case .browse = self { false } else { true }
    }
}

public struct PickerResult: Codable, Sendable, Equatable {
    public var chosen: [String]
    public var note: String
    /// For KLIPY picks: the link to share, as KLIPY returned it.
    public var link: String?

    public init(chosen: [String], note: String, link: String? = nil) {
        self.chosen = chosen
        self.note = note
        self.link = link
    }
}

struct PageItem: Codable, Sendable {
    let id: String
    let kind: String
    let title: String
    let vibe: String?
    let tags: [String]
    let howUsed: String?
    let source: String
    let sourceURL: String?
    let rights: String
    let licence: String?
    let attribution: String?
    let animated: Bool
    let video: Bool
    let popularity: Int?
    let rising: Bool
    let media: String
    let captions: [String]
    let recipe: String?
}

struct PageState: Codable, Sendable {
    let mode: String
    let max: Int
    let from: String?
    let items: [PageItem]
    let picks: [String]
    let total: Int
    let query: String?
    let klipy: [Klipy.Result]?
}

public final class Picker: @unchecked Sendable {
    public let url: URL
    let mode: PickerMode
    private let token: String
    private let items: [PageItem]
    private let total: Int
    private let local: [String: URL]
    private let remote: [String: URL]
    private let status: StatusStore
    private let server: HTTPServer
    private let lock = NSLock()
    private var result: PickerResult?
    private var klipyShown: [Klipy.Result] = []
    private var klipySeen: [String: String] = [:]
    private var klipyQuery = ""
    private let finished = DispatchSemaphore(value: 0)

    public init(library: Library, mode: PickerMode, ids: [String]? = nil, port: UInt16 = 0) throws {
        self.mode = mode
        self.token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        self.status = StatusStore(url: library.paths.status)

        var chosen: [Item] = try ids.map { try $0.map(library.item) }
            ?? library.visible.sorted { ($0.popularity ?? 1000, $0.title) < ($1.popularity ?? 1000, $1.title) }
        var local: [String: URL] = [:]
        var remote: [String: URL] = [:]
        var missing: [String] = []
        for item in chosen {
            if let file = library.localFile(for: item), FileManager.default.fileExists(atPath: file.path) { local[item.id] = file }
            else if let url = item.mediaURL.flatMap(URL.init(string:)), Blocklist.service(for: url) == nil { remote[item.id] = url }
            else { missing.append(item.id) }
        }
        if ids != nil, !missing.isEmpty {
            throw MemeError("These have no file to show: \(missing.joined(separator: ", ")). Remove them with `meme remove`.")
        }
        chosen.removeAll { missing.contains($0.id) }
        self.local = local
        self.remote = remote
        self.total = library.visible.count
        if case .klipy(let query, let results, _) = mode {
            klipyShown = results
            klipyQuery = query
            for result in results { klipySeen[result.slug] = result.link }
        }
        let token = self.token
        self.items = chosen.map { item in
            let ext = (item.file ?? item.mediaURL ?? "").split(separator: ".").last.map { String($0).lowercased() } ?? ""
            return PageItem(
                id: item.id, kind: item.kind.rawValue, title: item.title, vibe: item.vibe,
                tags: Array(Set(item.tags + item.keywords.map { $0.lowercased() })).sorted(),
                howUsed: item.howUsed, source: item.source, sourceURL: item.sourceURL, rights: item.rights.post.label,
                licence: item.licence, attribution: item.attribution, animated: item.animated,
                video: Media.videoExtensions.contains(ext), popularity: item.popularity, rising: item.risingSince != nil,
                media: "/media/\(item.id)?t=\(token)", captions: item.made?.captions ?? [],
                recipe: item.made.map(Self.recipe)
            )
        }
        let route = Route()
        let server = try HTTPServer(port: port) { request in route.target?.handle(request) ?? .text(503, "Starting.") }
        self.server = server
        self.url = URL(string: "http://127.0.0.1:\(server.port)/?t=\(token)")!
        route.target = self
    }

    private final class Route: @unchecked Sendable {
        weak var target: Picker?
    }

    public func start() throws {
        server.start()
        let mode = self.mode
        let url = self.url
        try status.update { status in
            status.picker = PickerState(mode: mode.name, url: url.absoluteString, pid: getpid())
            if mode.waits { status.waitingForPick = true }
        }
    }

    public func wait(timeout: TimeInterval) -> PickerResult? {
        let outcome = finished.wait(timeout: .now() + timeout)
        lock.lock()
        let result = self.result
        lock.unlock()
        return outcome == .success ? result : nil
    }

    public func stop() {
        server.stop()
        _ = try? status.update { status in
            status.picker = nil
            status.waitingForPick = false
        }
    }

    func handle(_ request: HTTPRequest) -> HTTPResponse {
        guard request.query["t"] == token || request.headers["x-meme-token"] == token else {
            return .text(403, "This page needs the link Meme Lab printed.")
        }
        switch (request.method, request.path) {
        case ("GET", "/"), ("HEAD", "/"):
            return HTTPResponse(status: 200, headers: ["Content-Type": "text/html; charset=utf-8"], body: Data(PickerPage.html.utf8))
        case ("GET", "/api/state"):
            let max: Int = switch mode {
            case .pick(let max): max
            case .propose, .klipy: 1
            case .browse: 4
            }
            let from: String? = if case .propose(let from) = mode { from } else { nil }
            lock.lock()
            let klipy: [Klipy.Result]? = if case .klipy = mode { klipyShown } else { nil }
            let query = klipyQuery
            lock.unlock()
            return .json(PageState(mode: mode.name, max: max, from: from, items: items, picks: status.load().picks,
                                   total: total, query: klipy == nil ? nil : query, klipy: klipy))
        case ("GET", "/api/klipy"):
            guard case .klipy(_, _, let key) = mode, let words = request.query["q"], !words.isEmpty else {
                return .text(400, "Search KLIPY with ?q=words.")
            }
            do {
                let results = try Klipy.searchWaiting(words, key: key)
                lock.lock()
                klipyShown = results
                klipyQuery = words
                for result in results { klipySeen[result.slug] = result.link }
                lock.unlock()
                return .json(results)
            } catch let error as MemeError {
                return .text(502, error.description)
            } catch {
                return .text(502, "KLIPY search failed.")
            }
        case ("POST", "/api/picks"):
            guard mode == .browse, let body = try? JSONDecoder().decode(PickerResult.self, from: request.body) else {
                return .text(400, "Send {\"chosen\": [ids], \"note\": \"\"}.")
            }
            let known = Set(items.map(\.id))
            let picks = body.chosen.filter(known.contains)
            do {
                try status.update { $0.picks = picks }
            } catch {
                return .text(500, "Could not save the picks: \(error)")
            }
            return .json(picks)
        case ("POST", "/api/choose"):
            guard mode.waits, let body = try? JSONDecoder().decode(PickerResult.self, from: request.body) else {
                return .text(400, "Send {\"chosen\": [ids], \"note\": \"\"}.")
            }
            lock.lock()
            let seen = klipySeen
            lock.unlock()
            if case .klipy = mode {
                guard body.chosen.count == 1, let slug = body.chosen.first, let link = seen[slug] ?? nil else {
                    return .text(400, "Pick one KLIPY result that has a link.")
                }
                return finish(PickerResult(chosen: [slug], note: body.note, link: link))
            }
            let chosen = body.chosen.filter(Set(items.map(\.id)).contains)
            if case .pick(let max) = mode, chosen.count > max { return .text(400, "Pick \(max) at most.") }
            return finish(PickerResult(chosen: chosen, note: body.note))
        case ("GET", let path) where path.hasPrefix("/media/"):
            return media(String(path.dropFirst("/media/".count)), range: request.headers["range"])
        default:
            return .text(404, "Not found.")
        }
    }

    private func finish(_ outcome: PickerResult) -> HTTPResponse {
        lock.lock()
        let first = result == nil
        if first { result = outcome }
        lock.unlock()
        guard first else { return .text(409, "Already sent.") }
        finished.signal()
        return .json(outcome)
    }

    private func media(_ id: String, range: String?) -> HTTPResponse {
        if let file = local[id], let data = try? Data(contentsOf: file, options: .mappedIfSafe) {
            var headers = ["Content-Type": Self.contentType(file.pathExtension), "Accept-Ranges": "bytes", "Cache-Control": "max-age=3600"]
            if let range, let (start, end) = Self.parseRange(range, size: data.count) {
                headers["Content-Range"] = "bytes \(start)-\(end)/\(data.count)"
                return HTTPResponse(status: 206, headers: headers, body: data.subdata(in: start..<(end + 1)))
            }
            return HTTPResponse(status: 200, headers: headers, body: data)
        }
        if let url = remote[id] {
            return HTTPResponse(status: 302, headers: ["Location": url.absoluteString], body: Data())
        }
        return .text(404, "No media for \(id).")
    }

    public static func recipe(_ made: MadeInfo) -> String {
        let layouts = ["single": "One picture", "side": "Side by side", "stack": "Stacked", "sequence": "One after another"]
        let styles = ["classic": "classic captions", "bar": "caption bar", "subtitle": "subtitle", "template": "template boxes"]
        let motions = ["reveal": "captions one at a time", "zoom": "slow zoom", "shake": "shaking"]
        var parts = [layouts[made.layout] ?? made.layout, styles[made.style] ?? made.style]
        if let motion = made.motion { parts.append(motions[motion] ?? motion) }
        return parts.joined(separator: ", ")
    }

    static func parseRange(_ header: String, size: Int) -> (Int, Int)? {
        guard header.hasPrefix("bytes="), size > 0 else { return nil }
        let parts = header.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        if parts[0].isEmpty, let suffix = Int(parts[1]), suffix > 0 { return (max(0, size - suffix), size - 1) }
        guard let start = Int(parts[0]), start < size else { return nil }
        let end = Int(parts[1]).map { min($0, size - 1) } ?? size - 1
        return end >= start ? (start, end) : nil
    }

    static func contentType(_ ext: String) -> String {
        switch ext.lowercased() {
        case "gif": "image/gif"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "webp": "image/webp"
        case "mp4", "m4v": "video/mp4"
        case "mov": "video/quicktime"
        default: "application/octet-stream"
        }
    }
}
