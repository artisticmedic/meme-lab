import AVFoundation
import AppKit
import ImageIO
import MemeCore
import SwiftUI

@MainActor
final class MediaStore {
    static let shared = MediaStore()
    private var downloads: [URL: Task<Bool, Never>] = [:]

    func file(for source: Library.MediaSource) async -> URL? {
        switch source {
        case .local(let url):
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        case .remote(let remote, let cache):
            if FileManager.default.fileExists(atPath: cache.path) { return cache }
            let task = downloads[cache] ?? Task.detached { (try? await Library.download(remote, to: cache)) != nil }
            downloads[cache] = task
            let ok = await task.value
            downloads[cache] = nil
            return ok ? cache : nil
        case .missing:
            return nil
        }
    }
}

struct Frames: @unchecked Sendable {
    let id = UUID()
    let images: [CGImage]
    let delays: [Double]
    var duration: Double { delays.reduce(0, +) }
}

enum FrameCache {
    private nonisolated(unsafe) static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.totalCostLimit = 300 * 1024 * 1024
        return cache
    }()

    private final class Box {
        let frames: Frames
        init(_ frames: Frames) { self.frames = frames }
    }

    static let maxFrames = 120

    static func frames(_ url: URL, maxPixel: Int, moving: Bool) async -> Frames? {
        let key = "\(url.path)#\(maxPixel)#\(moving)" as NSString
        if let hit = cache.object(forKey: key) { return hit.frames }
        let frames = await Task.detached(priority: .userInitiated) { decode(url, maxPixel: maxPixel, limit: moving ? maxFrames : 1) }.value
        if let frames {
            let cost = frames.images.reduce(0) { $0 + $1.bytesPerRow * $1.height }
            cache.setObject(Box(frames), forKey: key, cost: cost)
        }
        return frames
    }

    private static func decode(_ url: URL, maxPixel: Int, limit: Int) -> Frames? {
        if Media.videoExtensions.contains(url.pathExtension.lowercased()) { return poster(url, maxPixel: maxPixel) }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = min(CGImageSourceGetCount(source), limit)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        var images: [CGImage] = []
        var delays: [Double] = []
        for index in 0..<count {
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { continue }
            images.append(image)
            delays.append(delay(source, index))
        }
        return images.isEmpty ? nil : Frames(images: images, delays: delays)
    }

    private static func delay(_ source: CGImageSource, _ index: Int) -> Double {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
        let containers: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
        ]
        for (dictionary, unclamped, clamped) in containers {
            guard let values = properties[dictionary] as? [CFString: Any] else { continue }
            let seconds = (values[unclamped] as? Double).flatMap { $0 > 0 ? $0 : nil } ?? values[clamped] as? Double ?? 0.1
            // Browsers treat delays under 20 ms as 100 ms; GIFs made for the web rely on it.
            return seconds < 0.02 ? 0.1 : seconds
        }
        return 0.1
    }

    private static func poster(_ url: URL, maxPixel: Int) -> Frames? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var image: CGImage?
        generator.generateCGImageAsynchronously(for: .zero) { cgImage, _, _ in
            image = cgImage
            semaphore.signal()
        }
        semaphore.wait()
        return image.map { Frames(images: [$0], delays: [0]) }
    }
}

final class MediaLayerView: NSView {
    var frames: Frames? { didSet { if oldValue?.id != frames?.id { refresh() } } }
    var video: URL? { didSet { if oldValue != video { stopVideo(); refresh() } } }
    var playing = false { didSet { if oldValue != playing { refresh() } } }
    var onHover: ((Bool) -> Void)?
    var fill = true { didSet { if oldValue != fill { refresh() } } }
    private let imageLayer = CALayer()
    private var playerLayer: AVPlayerLayer?
    private var looper: AVPlayerLooper?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resizeAspectFill
        layer?.addSublayer(imageLayer)
    }

    required init?(coder: NSCoder) { fatalError("not used from a nib") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.frame = bounds
        playerLayer?.frame = bounds
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
    }

    // SwiftUI's onHover did not fire for tiles in the guest; an AppKit tracking area does, in the panel and the window.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }

    private func refresh() {
        imageLayer.contentsGravity = fill ? .resizeAspectFill : .resizeAspect
        imageLayer.removeAnimation(forKey: "frames")
        imageLayer.contents = frames?.images.first
        if playing, let video {
            playVideo(video)
            return
        }
        stopVideo()
        guard playing, let frames, frames.images.count > 1, frames.duration > 0 else { return }
        let animation = CAKeyframeAnimation(keyPath: "contents")
        animation.values = frames.images
        var elapsed = 0.0
        animation.keyTimes = frames.delays.map { delay in
            defer { elapsed += delay }
            return NSNumber(value: elapsed / frames.duration)
        }
        animation.calculationMode = .discrete
        animation.duration = frames.duration
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        imageLayer.add(animation, forKey: "frames")
    }

    private func playVideo(_ url: URL) {
        if let playerLayer {
            playerLayer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
            return
        }
        let player = AVQueuePlayer()
        player.isMuted = true
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = fill ? .resizeAspectFill : .resizeAspect
        layer.frame = bounds
        self.layer?.addSublayer(layer)
        playerLayer = layer
        player.play()
    }

    private func stopVideo() {
        playerLayer?.player?.pause()
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        looper = nil
    }
}

struct MediaLayer: NSViewRepresentable {
    let frames: Frames?
    let video: URL?
    let playing: Bool
    let fill: Bool
    var onHover: ((Bool) -> Void)?

    func makeNSView(context: Context) -> MediaLayerView { MediaLayerView(frame: .zero) }

    func updateNSView(_ view: MediaLayerView, context: Context) {
        view.fill = fill
        view.frames = frames
        view.video = video
        view.playing = playing
        view.onHover = onHover
    }
}

struct MediaPreview: View {
    @EnvironmentObject var model: AppModel
    let item: Item
    var playing: Bool
    var fill = true
    var maxPixel = 320
    var onHover: ((Bool) -> Void)?

    @State private var still: Frames?
    @State private var moving: Frames?
    @State private var file: URL?
    @State private var failed = false

    private var key: String { "\(item.id)#\(item.file ?? "")#\(maxPixel)" }
    private var video: URL? { file.flatMap { Media.videoExtensions.contains($0.pathExtension.lowercased()) ? $0 : nil } }

    var body: some View {
        MediaLayer(frames: moving ?? still, video: video, playing: playing, fill: fill, onHover: onHover)
            .background(Color.primary.opacity(0.06))
            .overlay {
                if failed {
                    Image(systemName: "photo").font(.system(size: 18)).foregroundStyle(.tertiary)
                } else if still == nil {
                    ProgressView().controlSize(.small)
                }
            }
            .task(id: key) { await loadStill() }
            .task(id: playing && still != nil ? key : nil) {
                guard playing, let file, video == nil, moving == nil, item.animated || file.pathExtension.lowercased() == "gif" else { return }
                moving = await FrameCache.frames(file, maxPixel: maxPixel, moving: true)
            }
            .accessibilityLabel(item.title)
    }

    private func loadStill() async {
        moving = nil
        guard let found = await MediaStore.shared.file(for: model.mediaSource(item)) else {
            failed = true
            return
        }
        file = found
        still = await FrameCache.frames(found, maxPixel: maxPixel, moving: false)
        failed = still == nil
    }
}
