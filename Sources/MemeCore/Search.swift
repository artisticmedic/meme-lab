import Foundation

public struct SearchQuery: Sendable {
    public var words: String
    public var kind: Kind?
    public var collection: String?
    public var risingOnly: Bool
    public var limit: Int

    public init(words: String, kind: Kind? = nil, collection: String? = nil, risingOnly: Bool = false, limit: Int = 12) {
        self.words = words
        self.kind = kind
        self.collection = collection
        self.risingOnly = risingOnly
        self.limit = limit
    }
}

public enum Search {
    public static func normalize(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "'", with: "")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private static let stopWords: Set<String> = ["a", "an", "the", "of", "and", "or", "to", "with", "meme", "gif"]

    public static func run(_ query: SearchQuery, in items: [Item]) -> [Item] {
        let words = normalize(query.words).filter { !stopWords.contains($0) }
        let candidates = items.filter { item in
            !item.hidden
                && (query.kind == nil || item.kind == query.kind)
                && (query.collection == nil || item.collections.contains(query.collection!))
                && (!query.risingOnly || item.risingSince != nil)
        }
        let scored: [(Item, Double)] = candidates.compactMap { item in
            let score = words.isEmpty ? 0 : self.score(item, words)
            if !words.isEmpty && score <= 0 { return nil }
            return (item, score + boost(item))
        }
        return scored
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.title < $1.0.title }
            .prefix(query.limit)
            .map(\.0)
    }

    static func score(_ item: Item, _ words: [String]) -> Double {
        let fields: [(Double, [String])] = [
            (5, normalize(item.title) + normalize(item.id)),
            (4, (item.tags + item.keywords).flatMap(normalize)),
            (3, normalize(item.vibe ?? "")),
            (2, normalize((item.howUsed ?? "") + " " + item.example.joined(separator: " "))),
            (2, item.collections.flatMap(normalize)),
        ]
        var total = 0.0
        var matched = 0
        for word in words {
            let best = fields.map { weight, tokens in
                tokens.contains(word) ? weight : (word.count >= 3 && tokens.contains { $0.hasPrefix(word) } ? weight * 0.6 : 0)
            }.max() ?? 0
            if best > 0 { matched += 1 }
            total += best
        }
        return matched == words.count ? total * 1.5 : total
    }

    /// Small tie-breakers: popular templates, then things Tim has used.
    static func boost(_ item: Item) -> Double {
        var boost = 0.0
        if let rank = item.popularity { boost += Double(101 - min(rank, 100)) / 100 }
        boost += min(Double(item.useCount), 5) * 0.1
        return boost
    }
}
