import Foundation

public struct MemeError: Error, CustomStringConvertible, Equatable {
    public let description: String
    public init(_ description: String) { self.description = description }
}

public struct Paths: Sendable {
    public let support: URL
    public let cache: URL
    public let defaultLibrary: URL

    public init(support: URL, cache: URL, defaultLibrary: URL) {
        self.support = support
        self.cache = cache
        self.defaultLibrary = defaultLibrary
    }

    public static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> Paths {
        if let home = environment["MEME_LAB_HOME"], !home.isEmpty {
            let root = URL(fileURLWithPath: (home as NSString).expandingTildeInPath, isDirectory: true)
            return Paths(
                support: root.appending(path: "Support"),
                cache: root.appending(path: "Cache"),
                defaultLibrary: root.appending(path: "Library")
            )
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return Paths(
            support: home.appending(path: "Library/Application Support/Meme Lab"),
            cache: home.appending(path: "Library/Caches/Meme Lab"),
            defaultLibrary: home.appending(path: "Pictures/Meme Lab")
        )
    }

    public var config: URL { support.appending(path: "config.json") }
    public var status: URL { support.appending(path: "status.json") }
    public var index: URL { support.appending(path: "index.json") }
    public var templates: URL { cache.appending(path: "templates") }
    public var strips: URL { cache.appending(path: "strips") }
    public var work: URL { cache.appending(path: "work") }
}

enum JSONFile {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder().encode(value).write(to: url, options: .atomic)
    }
}

public func jsonString<T: Encodable>(_ value: T) throws -> String {
    String(decoding: try JSONFile.encoder().encode(value), as: UTF8.self)
}

enum Shell {
    static func locate(_ tool: String) throws -> URL {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let dirs = path.split(separator: ":").map(String.init) + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"]
        for dir in dirs {
            let url = URL(fileURLWithPath: dir).appending(path: tool)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        throw MemeError("\(tool) is not installed. Install it with `brew install \(tool)`.")
    }

    private final class Collected: @unchecked Sendable { var data = Data() }

    struct Outcome {
        let status: Int32
        let stdout: Data
        let stderr: String
    }

    /// Reads stderr on another thread so a full pipe cannot stall it.
    static func execute(_ tool: String, _ arguments: [String], input: Data? = nil) throws -> Outcome {
        let process = Process()
        process.executableURL = try locate(tool)
        process.arguments = arguments
        let out = Pipe()
        let err = Pipe()
        let stdin = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin
        try process.run()
        if let input {
            stdin.fileHandleForWriting.write(input)
            try stdin.fileHandleForWriting.close()
        }
        let stderr = Collected()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            stderr.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()
        return Outcome(
            status: process.terminationStatus, stdout: stdout,
            stderr: String(decoding: stderr.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) throws -> Data {
        let outcome = try execute(tool, arguments)
        guard outcome.status == 0 else {
            throw MemeError("\(tool) failed: \(outcome.stderr.split(separator: "\n").suffix(3).joined(separator: " "))")
        }
        return outcome.stdout
    }
}

func fileSize(_ url: URL) throws -> Int {
    guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
        throw MemeError("Could not read the size of \(url.lastPathComponent).")
    }
    return size
}

enum HTTP {
    static let userAgent = "MemeLab/0.1 (personal meme tool)"

    static func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MemeError("\(url.host() ?? "The server") answered HTTP \(http.statusCode) for \(url.absoluteString).")
        }
        return data
    }
}
