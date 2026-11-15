import Foundation

/// KLIPY search, link-only. KLIPY's integration rules require its results in its own order, unfiltered, in a grid
/// of their own, with media loaded straight from its URLs; nothing is downloaded, stored or captioned.
/// https://docs.klipy.com/integration-requirements.md
public enum Klipy {
    public struct Result: Codable, Sendable, Equatable {
        public let slug: String
        public let title: String
        /// The GIF URL exactly as KLIPY returned it, for sharing.
        public let link: String
        public let preview: String
    }

    struct Response: Decodable {
        struct Page: Decodable { let data: [Entry] }
        struct Entry: Decodable {
            let slug: String
            let title: String?
            let file: [String: [String: Rendition]]
        }
        struct Rendition: Decodable { let url: String }
        let result: Bool
        let data: Page?
    }

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
        var components = URLComponents(string: "https://api.klipy.com/api/v1/\(key)/gifs/search")!
        components.queryItems = [.init(name: "q", value: words), .init(name: "per_page", value: "24")]
        var request = URLRequest(url: components.url!)
        request.setValue(HTTP.userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw MemeError(status == 404 || status == 401 ? "KLIPY refused the API key." : "KLIPY answered HTTP \(status).")
        }
        return try results(from: data)
    }

    static func results(from data: Data) throws -> [Result] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.result, let entries = response.data?.data else { throw MemeError("KLIPY returned no results list.") }
        // Every result is kept, in order: KLIPY forbids removing any. An entry without a GIF falls back to another format.
        return entries.compactMap { entry in
            let any = ["md", "hd", "sm", "xs"].lazy.compactMap { entry.file[$0]?.values.first?.url }.first
            guard let link = entry.file["md"]?["gif"]?.url ?? entry.file["hd"]?["gif"]?.url ?? any else { return nil }
            let preview = entry.file["sm"]?["webp"]?.url ?? entry.file["sm"]?["gif"]?.url ?? link
            return Result(slug: entry.slug, title: entry.title ?? entry.slug, link: link, preview: preview)
        }
    }
}
