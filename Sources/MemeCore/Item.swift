import Foundation

public enum Kind: String, Codable, CaseIterable, Sendable {
    case template, clip, made
}

/// Ordered from most to least permissive.
public enum PostRight: String, Codable, Comparable, Sendable {
    case freely
    case personal
    case linkOnly = "link_only"

    public var label: String {
        switch self {
        case .freely: "Post freely"
        case .personal: "Personal chat"
        case .linkOnly: "Link only"
        }
    }

    private var rank: Int {
        switch self {
        case .freely: 0
        case .personal: 1
        case .linkOnly: 2
        }
    }

    public static func < (a: PostRight, b: PostRight) -> Bool { a.rank < b.rank }
}

public struct Rights: Codable, Equatable, Sendable {
    public var caption: Bool
    public var post: PostRight

    public init(caption: Bool, post: PostRight) {
        self.caption = caption
        self.post = post
    }
}

/// A memegen text box, in fractions of the image size.
public struct TextBox: Codable, Equatable, Sendable {
    public var anchorX: Double
    public var anchorY: Double
    public var scaleX: Double
    public var scaleY: Double
    public var angle: Double
    public var style: String
    public var color: String
    public var font: String

    public init(
        anchorX: Double, anchorY: Double, scaleX: Double, scaleY: Double,
        angle: Double = 0, style: String = "upper", color: String = "white", font: String = "thick"
    ) {
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.angle = angle
        self.style = style
        self.color = color
        self.font = font
    }
}

public struct MadeInfo: Codable, Equatable, Sendable {
    public var inputs: [String]
    public var captions: [String]
    public var labels: [String]
    public var style: String
    public var layout: String
    public var gif: String?
    public var mp4: String?
    public var png: String?
    public var bytes: Int
    public var fps: Int?
    public var width: Int
    public var overLimit: Bool
    public var motion: String? = nil
}

public struct Item: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var kind: Kind
    public var title: String
    public var source: String
    public var sourceURL: String?
    public var mediaURL: String?
    /// Local file, relative to the library folder.
    public var file: String?
    public var animated: Bool
    public var width: Int?
    public var height: Int?
    public var keywords: [String]
    public var tags: [String]
    public var vibe: String?
    public var howUsed: String?
    public var example: [String]
    public var boxes: [TextBox]
    public var boxCount: Int?
    public var licence: String?
    public var attribution: String?
    public var rights: Rights
    public var popularity: Int?
    public var collections: [String]
    public var added: Date
    public var risingSince: Date?
    public var lastUsed: Date?
    public var useCount: Int
    public var hidden: Bool
    public var made: MadeInfo?

    public init(
        id: String, kind: Kind, title: String, source: String, rights: Rights, added: Date = Date(),
        sourceURL: String? = nil, mediaURL: String? = nil, file: String? = nil, animated: Bool = false,
        width: Int? = nil, height: Int? = nil, keywords: [String] = [], tags: [String] = [],
        vibe: String? = nil, howUsed: String? = nil, example: [String] = [], boxes: [TextBox] = [],
        boxCount: Int? = nil, licence: String? = nil, attribution: String? = nil, popularity: Int? = nil,
        made: MadeInfo? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.source = source
        self.rights = rights
        self.added = added
        self.sourceURL = sourceURL
        self.mediaURL = mediaURL
        self.file = file
        self.animated = animated
        self.width = width
        self.height = height
        self.keywords = keywords
        self.tags = tags
        self.vibe = vibe
        self.howUsed = howUsed
        self.example = example
        self.boxes = boxes
        self.boxCount = boxCount
        self.licence = licence
        self.attribution = attribution
        self.popularity = popularity
        self.collections = []
        self.risingSince = nil
        self.lastUsed = nil
        self.useCount = 0
        self.hidden = false
        self.made = made
    }
}
