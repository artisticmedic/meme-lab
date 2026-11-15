import Foundation

/// Original one-line descriptions shipped with the tool, so a fresh library is searchable by feeling.
enum SeedVibes {
    struct Entry: Decodable, Sendable {
        let vibe: String
        let tags: [String]
        let howUsed: String
    }

    static let all: [String: Entry] = (try? JSONDecoder().decode([String: Entry].self, from: Data(seedVibesJSON.utf8))) ?? [:]
}
