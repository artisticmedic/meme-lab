import Foundation

public struct MediaInfo: Equatable, Sendable {
    public var width: Int
    public var height: Int
    public var duration: Double
    public var frames: Int

    public var animated: Bool { frames > 1 && duration > 0.05 }
    public var fps: Double { duration > 0 ? Double(frames) / duration : 0 }
}

public enum Media {
    public static let extensions: Set<String> = ["gif", "png", "jpg", "jpeg", "webp", "mp4", "mov", "m4v"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    public static func probe(_ url: URL) throws -> MediaInfo {
        struct Probe: Decodable {
            struct Stream: Decodable {
                let codec_type: String?
                let width: Int?
                let height: Int?
                let nb_frames: String?
                let nb_read_frames: String?
                let duration: String?
            }
            struct Format: Decodable { let duration: String? }
            let streams: [Stream]
            let format: Format?
        }
        func read(countFrames: Bool) throws -> Probe {
            var args = ["-v", "error", "-select_streams", "v:0", "-show_streams", "-show_format", "-of", "json"]
            if countFrames { args.append("-count_frames") }
            return try JSONDecoder().decode(Probe.self, from: Shell.run("ffprobe", args + [url.path]))
        }
        var probe = try read(countFrames: false)
        if probe.streams.first?.nb_frames.flatMap(Int.init) == nil {
            probe = try read(countFrames: true)
        }
        guard let stream = probe.streams.first, let width = stream.width, let height = stream.height else {
            throw MemeError("\(url.lastPathComponent) has no picture ffprobe can read.")
        }
        let frames = stream.nb_frames.flatMap(Int.init) ?? stream.nb_read_frames.flatMap(Int.init) ?? 1
        let duration = stream.duration.flatMap(Double.init) ?? probe.format?.duration.flatMap(Double.init) ?? 0
        return MediaInfo(width: width, height: height, duration: frames > 1 ? duration : 0, frames: frames)
    }

    public static func strip(for item: Item, media: URL, info: MediaInfo, into dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appending(path: "\(item.id).png")
        if FileManager.default.fileExists(atPath: out.path) { return out }
        guard info.animated else {
            try Shell.run("ffmpeg", ["-v", "error", "-y", "-i", media.path, "-vf", "scale=480:-2", "-frames:v", "1", out.path])
            return out
        }
        let work = dir.appending(path: "\(item.id).parts")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        var parts: [String] = []
        for (n, fraction) in [0.03, 0.5, 0.92].enumerated() {
            let part = work.appending(path: "\(n).png").path
            try Shell.run("ffmpeg", [
                "-v", "error", "-y", "-ss", String(format: "%.3f", info.duration * fraction), "-i", media.path,
                "-vf", "scale=240:-2", "-frames:v", "1", part,
            ])
            parts.append(part)
        }
        try Shell.run("ffmpeg", ["-v", "error", "-y"] + parts.flatMap { ["-i", $0] } + [
            "-filter_complex", "hstack=inputs=3", out.path,
        ])
        return out
    }
}
