import Foundation

/// A waiting `meme propose` or `meme pick`, shown in the app's panel.
public struct AppRequest: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable { case propose, pick }

    public var id: String
    public var mode: Mode
    /// propose: the options, in order. pick: the items to choose from; empty means the whole library.
    public var items: [String]
    public var max: Int
    public var from: String?
    /// The waiting command. The app drops a request whose command has exited.
    public var pid: Int32
    /// Open the panel when the request arrives, instead of only marking the menu bar icon.
    public var open: Bool
    public var createdAt: Date

    public init(mode: Mode, items: [String], max: Int, from: String?, pid: Int32 = getpid(), open: Bool = true) {
        self.id = UUID().uuidString.lowercased()
        self.mode = mode
        self.items = items
        self.max = max
        self.from = from
        self.pid = pid
        self.open = open
        self.createdAt = Date()
    }
}

public struct AppAnswer: Codable, Equatable, Sendable {
    public var id: String
    public var chosen: [String]
    public var note: String

    public init(id: String, chosen: [String], note: String) {
        self.id = id
        self.chosen = chosen
        self.note = note
    }
}

public struct AppState: Codable, Equatable, Sendable {
    public var pid: Int32
    public var startedAt: Date

    public init(pid: Int32, startedAt: Date = Date()) {
        self.pid = pid
        self.startedAt = startedAt
    }
}

public struct PickerState: Codable, Equatable, Sendable {
    public var mode: String
    public var url: String
    public var pid: Int32
}

public struct Status: Codable, Equatable, Sendable {
    public var picks: [String] = []
    public var request: AppRequest?
    public var answer: AppAnswer?
    public var waitingForPick = false
    public var lastMade: String?
    public var picker: PickerState?
    /// The running app, if any.
    public var app: AppState?
    public var updatedAt: Date?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        picks = try c.decodeIfPresent([String].self, forKey: .picks) ?? []
        request = try? c.decodeIfPresent(AppRequest.self, forKey: .request)
        answer = try? c.decodeIfPresent(AppAnswer.self, forKey: .answer)
        waitingForPick = try c.decodeIfPresent(Bool.self, forKey: .waitingForPick) ?? false
        lastMade = try c.decodeIfPresent(String.self, forKey: .lastMade)
        picker = try c.decodeIfPresent(PickerState.self, forKey: .picker)
        app = try? c.decodeIfPresent(AppState.self, forKey: .app)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

public struct StatusStore: Sendable {
    public let url: URL

    public init(url: URL) { self.url = url }

    /// Writes are atomic and missing keys decode as empty, so only a hand-mangled file reads as empty; the next update
    /// replaces it. Status mirrors live state and holds nothing that cannot be picked again.
    public func load() -> Status {
        (try? JSONFile.decoder().decode(Status.self, from: Data(contentsOf: url))) ?? Status()
    }

    /// Serialised across threads and processes, since the app, the picker page and an agent's commands all update the file.
    @discardableResult
    public func update(_ change: (inout Status) -> Void) throws -> Status {
        try FileLock.holding(url) {
            var status = load()
            change(&status)
            status.updatedAt = Date()
            try JSONFile.write(status, to: url)
            return status
        }
    }
}

enum FileLock {
    private static let threadLock = NSRecursiveLock()

    /// flock on `<file>.lock`, plus a thread lock because flock does not exclude threads of one process.
    static func holding<T>(_ file: URL, _ body: () throws -> T) throws -> T {
        threadLock.lock()
        defer { threadLock.unlock() }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(file.path + ".lock", O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw MemeError("Could not open \(file.lastPathComponent).lock.") }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}
