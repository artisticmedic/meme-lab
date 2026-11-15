import Foundation

public struct Proposal: Codable, Equatable, Sendable {
    public var options: [String]
    public var from: String?
    public var createdAt: Date

    public init(options: [String], from: String?, createdAt: Date = Date()) {
        self.options = options
        self.from = from
        self.createdAt = createdAt
    }
}

public struct PickerState: Codable, Equatable, Sendable {
    public var mode: String
    public var url: String
    public var pid: Int32
}

public struct Status: Codable, Equatable, Sendable {
    public var picks: [String] = []
    public var proposal: Proposal?
    public var waitingForPick = false
    public var lastMade: String?
    public var picker: PickerState?
    public var updatedAt: Date?

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        picks = try c.decodeIfPresent([String].self, forKey: .picks) ?? []
        proposal = try c.decodeIfPresent(Proposal.self, forKey: .proposal)
        waitingForPick = try c.decodeIfPresent(Bool.self, forKey: .waitingForPick) ?? false
        lastMade = try c.decodeIfPresent(String.self, forKey: .lastMade)
        picker = try c.decodeIfPresent(PickerState.self, forKey: .picker)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
    }
}

public struct StatusStore: Sendable {
    public let url: URL
    private static let threadLock = NSLock()

    public init(url: URL) { self.url = url }

    /// Writes are atomic and missing keys decode as empty, so only a hand-mangled file reads as empty; the next update
    /// replaces it. Status mirrors live state and holds nothing that cannot be picked again.
    public func load() -> Status {
        (try? JSONFile.decoder().decode(Status.self, from: Data(contentsOf: url))) ?? Status()
    }

    /// Serialised across threads and processes, since the picker page and an agent's commands both update the file.
    @discardableResult
    public func update(_ change: (inout Status) -> Void) throws -> Status {
        Self.threadLock.lock()
        defer { Self.threadLock.unlock() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path + ".lock", O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { throw MemeError("Could not open \(url.lastPathComponent).lock.") }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        var status = load()
        change(&status)
        status.updatedAt = Date()
        try JSONFile.write(status, to: url)
        return status
    }
}
