import Foundation

/// KLIPY search, link-only. KLIPY's integration rules require its results in its own order, unfiltered, in a grid
/// of their own, with media loaded straight from its URLs; nothing is downloaded, stored or captioned.
/// https://docs.klipy.com/integration-requirements.md
public enum Klipy {
    public struct Result: Codable, Sendable, Equatable {
        public let slug: String
        public let title: String
        /// The URL exactly as KLIPY returned it, for sharing. Nil only for an entry KLIPY sent without media.
        public let link: String?
        public let preview: String?
        public let previewIsVideo: Bool
    }

    struct Response: Decodable {
        struct Page: Decodable { let data: [Entry] }
        /// Decodes whatever shape an entry has, so one odd entry neither fails the search nor disappears from it.
        struct Entry: Decodable {
            let slug: String?
            let title: String?
            let file: [String: [String: Rendition]]

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                slug = try? c.decode(String.self, forKey: .slug)
                title = try? c.decode(String.self, forKey: .title)
                file = (try? c.decode([String: [String: Rendition]].self, forKey: .file)) ?? [:]
            }

            enum CodingKeys: String, CodingKey { case slug, title, file }
        }
        struct Rendition: Decodable { let url: String }
        let result: Bool
        let data: Page?
    }

    static let sizes = ["md", "hd", "sm", "xs"]
    static let shareFormats = ["gif", "webp", "mp4", "webm", "jpg"]
    static let previewFormats = ["webp", "gif", "jpg"]

    static let secretName = "KLIPY_API_KEY"

    /// Whether a key is set up, without reading its value.
    public static func configured(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        if environment[secretName]?.isEmpty == false { return true }
        guard let secrets = secretsTool(environment), let outcome = try? Shell.execute(secrets.path, ["names"]) else { return false }
        return outcome.status == 0 && String(decoding: outcome.stdout, as: UTF8.self).split(whereSeparator: \.isNewline).contains { $0 == secretName }
    }

    public static func key(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> String {
        if let key = environment[secretName], !key.isEmpty { return key }
        if let secrets = secretsTool(environment) {
            let outcome = try Shell.execute(secrets.path, ["get", secretName])
            let key = String(decoding: outcome.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if outcome.status == 0, !key.isEmpty { return key }
        }
        throw MemeError("KLIPY search is off: there is no \(secretName). Add it with `secrets`, or set \(secretName).")
    }

    private static func secretsTool(_ environment: [String: String]) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin").path
        let dirs = (environment["PATH"] ?? "").split(separator: ":").map(String.init) + [home]
        return dirs.lazy.map { URL(fileURLWithPath: $0).appending(path: "secrets") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    public static func search(_ words: String, key: String) async throws -> [Result] {
        // The key sits in the URL path, so errors name the request instead of printing the URL.
        guard let escaped = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~"))),
              var components = URLComponents(string: "https://api.klipy.com/api/v1/\(escaped)/gifs/search")
        else { throw MemeError("The KLIPY key could not be put in a request.") }
        components.queryItems = [.init(name: "q", value: words), .init(name: "per_page", value: "24")]
        guard let url = components.url else { throw MemeError("The KLIPY search words could not be put in a request.") }
        let data: Data
        do {
            data = try await HTTP.get(url, label: "a KLIPY search")
        } catch let error as HTTPStatusError where error.status == 401 || error.status == 404 {
            throw MemeError("KLIPY refused the API key.")
        }
        return try results(from: data)
    }

    /// For callers outside Swift concurrency, such as the picker's request threads and synchronous commands.
    public static func searchWaiting(_ words: String, key: String) throws -> [Result] {
        let box = Outcome()
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            do { box.value = .success(try await search(words, key: key)) } catch { box.value = .failure(error) }
            done.signal()
        }
        done.wait()
        return try box.value!.get()
    }

    private final class Outcome: @unchecked Sendable {
        var value: Swift.Result<[Result], Error>?
    }

    static func results(from data: Data) throws -> [Result] {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw MemeError("KLIPY's answer did not parse.")
        }
        guard response.result, let entries = response.data?.data else { throw MemeError("KLIPY returned no results list.") }
        // Every result is kept, in KLIPY's order: its rules forbid removing any.
        return entries.enumerated().map { index, entry in
            func first(_ formats: [String], sizes: [String] = sizes) -> String? {
                sizes.lazy.compactMap { size in formats.lazy.compactMap { entry.file[size]?[$0]?.url }.first }.first
            }
            let link = first(shareFormats)
            let image = first(previewFormats, sizes: ["sm", "xs", "md", "hd"])
            let slug = entry.slug ?? "result-\(index + 1)"
            return Result(slug: slug, title: entry.title ?? slug, link: link, preview: image ?? link, previewIsVideo: image == nil && link != nil)
        }
    }
}
