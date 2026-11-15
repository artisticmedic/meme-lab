import AppKit
import Foundation

public enum Clipboard {
    /// Puts the file itself on the clipboard, so pasting into Discord uploads it.
    public static func copyFile(_ url: URL, environment: [String: String] = ProcessInfo.processInfo.environment) throws {
        let board = environment["MEME_LAB_PASTEBOARD"].map { NSPasteboard(name: NSPasteboard.Name($0)) } ?? .general
        board.clearContents()
        guard board.writeObjects([url as NSURL]) else {
            throw MemeError("The clipboard refused \(url.lastPathComponent).")
        }
    }
}

public struct RivResult: Codable, Sendable {
    public let links: [String]
    public let dryRun: Bool
}

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
        let dropDir = config.rivDropDir ?? "~/riv/drop"
        let host = config.rivHost
        let remoteDir = dropDir.hasPrefix("~/") ? String(dropDir.dropFirst(2)) : dropDir
        let copy = try Shell.execute("scp", ["-q"] + files.map(\.path) + ["\(host):\(remoteDir)/"])
        guard copy.status == 0 else {
            throw MemeError("Copying to the M1 failed; it may be asleep or offline. \(copy.stderr)")
        }

        let post = try Shell.execute(
            "ssh", [host, command(dropDir: dropDir, names: files.map(remoteName), dryRun: dryRun)],
            input: Data(caption.replacingOccurrences(of: "\n", with: " ").utf8)
        )
        let err = post.stderr
        let links = String(decoding: post.stdout, as: UTF8.self).split(separator: "\n").map(String.init).filter { $0.hasPrefix("http") }

        switch post.status {
        case 0: return RivResult(links: links, dryRun: dryRun)
        case 65: throw MemeError("Riv refused the file or caption; nothing was posted. \(err)")
        case 69: throw MemeError("Riv could not post (Discord, the network or the M1 failed). Posted: \(links.isEmpty ? "nothing" : links.joined(separator: " ")). Safe to retry. \(err)")
        case 75: throw MemeError("Riv is rate-limited or took the job without answering yet. Do not resend; check the Meme Lab thread. \(err)")
        case 78: throw MemeError("Riv's Discord token or channel is not working; tell Tim. \(err)")
        case 255: throw MemeError("Could not reach the M1 over ssh; it may be asleep or offline. \(err)")
        default: throw MemeError("riv-drop exited \(post.status). \(err)")
        }
    }
}
