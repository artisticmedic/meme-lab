import Foundation

public struct Config: Codable, Equatable, Sendable {
    public var libraryDir: String?
    public var maxMB: Double
    public var width: Int
    public var fps: Int
    public var maxSeconds: Double
    public var rivHost: String
    public var rivDropDir: String?
    /// A shell command the panel's Ask agent button runs, with the prompt in MEME_PROMPT. Empty hides the button.
    public var agentCommand: String
    public var animateAlways: Bool

    public static let defaults = Config(
        libraryDir: nil, maxMB: 8, width: 480, fps: 15, maxSeconds: 6, rivHost: "m1", rivDropDir: nil,
        agentCommand: "", animateAlways: false
    )

    public init(
        libraryDir: String?, maxMB: Double, width: Int, fps: Int, maxSeconds: Double,
        rivHost: String, rivDropDir: String?, agentCommand: String = "", animateAlways: Bool = false
    ) {
        self.libraryDir = libraryDir
        self.maxMB = maxMB
        self.width = width
        self.fps = fps
        self.maxSeconds = maxSeconds
        self.rivHost = rivHost
        self.rivDropDir = rivDropDir
        self.agentCommand = agentCommand
        self.animateAlways = animateAlways
    }

    /// Missing keys fall back to defaults, so a partial file is valid.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config.defaults
        libraryDir = try c.decodeIfPresent(String.self, forKey: .libraryDir)
        maxMB = try c.decodeIfPresent(Double.self, forKey: .maxMB) ?? d.maxMB
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? d.width
        fps = try c.decodeIfPresent(Int.self, forKey: .fps) ?? d.fps
        maxSeconds = try c.decodeIfPresent(Double.self, forKey: .maxSeconds) ?? d.maxSeconds
        rivHost = try c.decodeIfPresent(String.self, forKey: .rivHost) ?? d.rivHost
        rivDropDir = try c.decodeIfPresent(String.self, forKey: .rivDropDir)
        agentCommand = try c.decodeIfPresent(String.self, forKey: .agentCommand) ?? d.agentCommand
        animateAlways = try c.decodeIfPresent(Bool.self, forKey: .animateAlways) ?? d.animateAlways
    }

    public static let keys = ["libraryDir", "maxMB", "width", "fps", "maxSeconds", "rivHost", "rivDropDir", "agentCommand", "animateAlways"]

    public func value(of key: String) throws -> String {
        switch key {
        case "libraryDir": libraryDir ?? ""
        case "maxMB": String(maxMB)
        case "width": String(width)
        case "fps": String(fps)
        case "maxSeconds": String(maxSeconds)
        case "rivHost": rivHost
        case "rivDropDir": rivDropDir ?? ""
        case "agentCommand": agentCommand
        case "animateAlways": String(animateAlways)
        default: throw Config.unknown(key)
        }
    }

    public mutating func set(_ key: String, to raw: String) throws {
        func number<T: LosslessStringConvertible & Comparable>(_ type: T.Type, min: T, max: T) throws -> T {
            guard let value = T(raw), value >= min, value <= max else {
                throw MemeError("\(key) must be a number from \(min) to \(max); got \"\(raw)\".")
            }
            return value
        }
        switch key {
        case "libraryDir": libraryDir = raw.isEmpty ? nil : raw
        case "maxMB": maxMB = try number(Double.self, min: 0.5, max: 20)
        case "width": width = try number(Int.self, min: 120, max: 1280)
        case "fps": fps = try number(Int.self, min: 5, max: 50)
        case "maxSeconds": maxSeconds = try number(Double.self, min: 1, max: 30)
        case "rivHost": rivHost = raw
        case "rivDropDir": rivDropDir = raw.isEmpty ? nil : raw
        case "agentCommand": agentCommand = raw
        case "animateAlways":
            guard let value = Bool(raw) else { throw MemeError("animateAlways must be true or false; got \"\(raw)\".") }
            animateAlways = value
        default: throw Config.unknown(key)
        }
    }

    private static func unknown(_ key: String) -> MemeError {
        MemeError("There is no setting called \(key). Settings: \(keys.joined(separator: ", ")).")
    }
}

public struct ConfigStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> Config {
        guard FileManager.default.fileExists(atPath: url.path) else { return .defaults }
        do {
            return try JSONFile.decoder().decode(Config.self, from: Data(contentsOf: url))
        } catch {
            throw MemeError(
                "\(url.path) does not parse, so Meme Lab is ignoring it and will not save settings until it does. Fix or remove the file."
            )
        }
    }

    /// Refuses to write when the existing file does not parse, so a hand-edited file is never overwritten.
    public func set(_ key: String, to value: String) throws -> Config {
        try FileLock.holding(url) {
            var config = try load()
            try config.set(key, to: value)
            try JSONFile.write(config, to: url)
            return config
        }
    }
}
