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
}

public struct StatusStore: Sendable {
    public let url: URL
    private static let lock = NSLock()

    public init(url: URL) { self.url = url }

    /// Status only mirrors live state, so a missing or unreadable file starts empty and is replaced on the next update.
    public func load() -> Status {
        (try? JSONFile.decoder().decode(Status.self, from: Data(contentsOf: url))) ?? Status()
    }

    @discardableResult
    public func update(_ change: (inout Status) -> Void) throws -> Status {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        var status = load()
        change(&status)
        status.updatedAt = Date()
        try JSONFile.write(status, to: url)
        return status
    }
}
