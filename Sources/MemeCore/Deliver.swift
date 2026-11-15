import AppKit
import Foundation

public enum Clipboard {
    /// Puts the file itself on the clipboard, so pasting into Discord uploads it. `MEME_LAB_PASTEBOARD` names a private
    /// pasteboard instead of the general one, for tests.
    public static func copyFile(_ url: URL, environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        let board = environment["MEME_LAB_PASTEBOARD"].map { NSPasteboard(name: NSPasteboard.Name($0)) } ?? .general
        board.clearContents()
        guard board.writeObjects([url as NSURL]) else {
            throw MemeError("The clipboard refused \(url.lastPathComponent).")
        }
    }

    public static func fileURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let board = environment["MEME_LAB_PASTEBOARD"].map { NSPasteboard(name: NSPasteboard.Name($0)) } ?? .general
        return board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.first as? URL
    }
}

public struct RivResult: Codable, Sendable {
    public let links: [String]
    public let dryRun: Bool
}

/// Hands files to Riv on the M1, which posts them to its "Meme Lab" Discord thread through `riv-drop`.
/// Riv owns that side; this only copies into `~/riv/drop/` and runs the command.
public enum Riv {
    static let tool = "~/riv/ingress/tools/riv-drop"

    static func remoteName(_ file: URL) -> String {
        let cleaned = file.lastPathComponent.map { $0.isLetter || $0.isNumber || ".-_".contains($0) ? $0 : "-" }
        return String(cleaned)
    }

    static func command(dropDir: String, names: [String], dryRun: Bool) -> String {
        var parts = [tool, "--caption", "-", "--from", "'Meme Lab'"]
        if dryRun { parts.append("--dry-run") }
        parts += names.map { "\(dropDir)/\($0)" }
        return parts.joined(separator: " ")
    }

    public static func send(_ files: [URL], caption: String, config: Config, dryRun: Bool = false) throws -> RivResult {
        guard !files.isEmpty else { throw MemeError("Nothing to send to Riv.") }
        let caption = caption.replacingOccurrences(of: "\n", with: " ")
        guard caption.count <= 300 else { throw MemeError("Riv takes a caption of 300 characters at most.") }
        for file in files {
            let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            guard size <= 20 * 1_048_576 else { throw MemeError("\(file.lastPathComponent) is over Riv's 20 MiB limit.") }
        }
        let dropDir = config.rivDropDir ?? "~/riv/drop"
        let names = files.map(remoteName)
        let host = config.rivHost
        let remoteDir = dropDir.hasPrefix("~/") ? String(dropDir.dropFirst(2)) : dropDir
        try runChecked("scp", ["-q"] + files.map(\.path) + ["\(host):\(remoteDir)/"], what: "Copying to Riv")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = [host, command(dropDir: dropDir, names: names, dryRun: dryRun)]
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        input.fileHandleForWriting.write(Data(caption.utf8))
        try input.fileHandleForWriting.close()
        let out = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit()
        let links = out.split(separator: "\n").map(String.init).filter { $0.hasPrefix("http") }

        switch process.terminationStatus {
        case 0: return RivResult(links: links, dryRun: dryRun)
        case 65: throw MemeError("Riv refused the file or caption; nothing was posted. \(err)")
        case 69: throw MemeError("Riv could not post (Discord, the network or the M1 failed). Posted: \(links.isEmpty ? "nothing" : links.joined(separator: " ")). Safe to retry. \(err)")
        case 75: throw MemeError("Riv is rate-limited or took the job without answering yet. Do not resend; check the Meme Lab thread. \(err)")
        case 78: throw MemeError("Riv's Discord token or channel is not working; tell Tim. \(err)")
        case 255: throw MemeError("Could not reach the M1 over ssh; it may be asleep or offline. \(err)")
        default: throw MemeError("riv-drop exited \(process.terminationStatus). \(err)")
        }
    }

    private static func runChecked(_ tool: String, _ args: [String], what: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/\(tool)")
        process.arguments = args
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let err = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw MemeError("\(what) failed: \(err.trimmingCharacters(in: .whitespacesAndNewlines)). The M1 may be asleep or offline.")
        }
    }
}
