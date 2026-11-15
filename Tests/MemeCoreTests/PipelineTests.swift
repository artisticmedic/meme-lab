import Foundation
import Testing
@testable import MemeCore

@Suite(.serialized)
struct PipelineTests {
    static func library() throws -> (Library, URL) {
        let home = try Scratch.make()
        let paths = Paths.current(environment: ["MEME_LAB_HOME": home.path])
        return (try Library(paths: paths, config: .defaults), home)
    }

    static func clip(in dir: URL, name: String = "clip.mp4", seconds: Int = 2, size: String = "320x240") throws -> URL {
        let url = dir.appending(path: name)
        try Shell.run("ffmpeg", ["-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=\(size):rate=20:duration=\(seconds)",
                                 "-pix_fmt", "yuv420p", url.path])
        return url
    }

    static func still(in dir: URL) throws -> URL {
        let url = dir.appending(path: "still.png")
        try Shell.run("ffmpeg", ["-v", "error", "-y", "-f", "lavfi", "-i", "smptebars=size=400x300", "-frames:v", "1", url.path])
        return url
    }

    @Test func addIsIdempotentAndCopiesIntoTheLibrary() throws {
        let (library, home) = try Self.library()
        let source = try Self.clip(in: home)
        let first = try library.add(file: source, tags: ["Test"])
        let second = try library.add(file: source)
        #expect(first.id == second.id)
        #expect(first.animated)
        #expect(first.tags == ["test"])
        #expect(FileManager.default.fileExists(atPath: library.root.appending(path: first.file!).path))
        #expect(throws: MemeError.self) { try library.add(file: home.appending(path: "notes.txt")) }
    }

    @Test func makesAGifAndMp4WithABar() async throws {
        let (library, home) = try Self.library()
        let clip = try library.add(file: Self.clip(in: home))
        let result = try await library.make(MakeRequest(ids: [clip.id], captions: ["me watching CI"], style: .bar))
        #expect(result.file.hasSuffix(".gif"))
        #expect(result.mp4 != nil)
        #expect(!result.overLimit)
        let info = try Media.probe(URL(fileURLWithPath: result.file))
        #expect(info.animated)
        #expect(info.height > info.width * 3 / 4)
        #expect(library.items[result.id]?.kind == .made)
        #expect(library.items[clip.id]?.useCount == 1)
    }

    @Test func combinesSideBySideAndInSequence() async throws {
        let (library, home) = try Self.library()
        let a = try library.add(file: Self.clip(in: home, name: "a.mp4", seconds: 2))
        let b = try library.add(file: Self.clip(in: home, name: "b.mp4", seconds: 1, size: "240x320"))
        let side = try await library.make(MakeRequest(ids: [a.id, b.id], captions: ["", "friday"], labels: ["plan", "reality"], style: .classic, layout: .side))
        let sideInfo = try Media.probe(URL(fileURLWithPath: side.file))
        #expect(abs(sideInfo.width - 720) <= 4)
        #expect(abs(sideInfo.duration - 2) < 0.3)

        let sequence = try await library.make(MakeRequest(ids: [a.id, b.id], captions: ["deploy"], style: .subtitle, layout: .sequence))
        #expect(abs(try Media.probe(URL(fileURLWithPath: sequence.file)).duration - 3) < 0.4)
    }

    @Test func stillsBecomePngs() async throws {
        let (library, home) = try Self.library()
        let still = try library.add(file: Self.still(in: home))
        let result = try await library.make(MakeRequest(ids: [still.id], captions: ["top", "bottom"]))
        #expect(result.file.hasSuffix(".png"))
        #expect(result.mp4 == nil)
    }

    @Test func motionTurnsAStillIntoAGif() async throws {
        let (library, home) = try Self.library()
        let still = try library.add(file: Self.still(in: home))
        let reveal = try await library.make(MakeRequest(ids: [still.id], captions: ["top", "bottom"], motion: .reveal))
        #expect(reveal.file.hasSuffix(".gif"))
        #expect(abs(try Media.probe(URL(fileURLWithPath: reveal.mp4!)).duration - 3.7) < 0.2)
        #expect(library.items[reveal.id]?.made?.motion == "reveal")

        for motion in [Motion.zoom, .shake] {
            let result = try await library.make(MakeRequest(ids: [still.id], captions: ["moving"], motion: motion))
            #expect(try Media.probe(URL(fileURLWithPath: result.file)).frames > 10, "\(motion)")
        }
    }

    @Test func motionIsRefusedWhereItCannotWork() async throws {
        let (library, home) = try Self.library()
        let still = try library.add(file: Self.still(in: home))
        let clip = try library.add(file: Self.clip(in: home))
        await #expect(throws: MemeError.self) { try await library.make(MakeRequest(ids: [clip.id], captions: ["a"], motion: .zoom)) }
        await #expect(throws: MemeError.self) { try await library.make(MakeRequest(ids: [still.id, still.id], layout: .sequence, motion: .zoom)) }
        await #expect(throws: MemeError.self) { try await library.make(MakeRequest(ids: [still.id], motion: .reveal)) }
    }

    @Test func previewDrawsCaptionsWithoutRendering() async throws {
        let (library, home) = try Self.library()
        let still = try library.add(file: Self.still(in: home))
        let preview = try await library.preview(MakeRequest(ids: [still.id, still.id], captions: ["a caption"], style: .bar, layout: .stack))
        #expect(preview.bar > 0)
        #expect(preview.panels.count == 2)
        #expect(preview.panels[0].minY == preview.bar)
        #expect(preview.canvas.height == preview.panels[1].maxY)
        #expect(FileManager.default.fileExists(atPath: preview.overlay.path))
        #expect(library.items.values.allSatisfy { $0.kind != .made })
    }

    @Test func shrinksToFitTheLimit() async throws {
        let (library, home) = try Self.library()
        let clip = try library.add(file: Self.clip(in: home, seconds: 4, size: "640x480"))
        let result = try await library.make(MakeRequest(ids: [clip.id], captions: ["tiny"], width: 640, fps: 20, maxMB: 0.6))
        #expect(result.bytes <= 600_000 || result.overLimit)
        #expect((result.fps ?? 20) < 20 || result.width < 640)
    }

    @Test func refusesBadRequests() async throws {
        let (library, home) = try Self.library()
        let clip = try library.add(file: Self.clip(in: home))
        await #expect(throws: MemeError.self) { try await library.make(MakeRequest(ids: [clip.id, clip.id], layout: .single)) }
        await #expect(throws: MemeError.self) { try await library.make(MakeRequest(ids: [clip.id], captions: ["a"], style: .template)) }
        await #expect(throws: MemeError.self) { try await library.make(MakeRequest(ids: ["nope"])) }
    }

    @Test func pickerHandsTheChoiceBack() async throws {
        let (library, home) = try Self.library()
        let clip = try library.add(file: Self.clip(in: home))
        let made = try await library.make(MakeRequest(ids: [clip.id], captions: ["x"], style: .bar))
        let picker = try Picker(library: library, mode: .propose(from: "Tests"), ids: [made.id])
        try picker.start()
        defer { picker.stop() }

        let base = "http://127.0.0.1:\(picker.url.port!)"
        let token = URLComponents(url: picker.url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "t" }!.value!
        let (_, refused) = try await URLSession.shared.data(from: URL(string: "\(base)/api/state")!)
        #expect((refused as! HTTPURLResponse).statusCode == 403)

        let (stateData, _) = try await URLSession.shared.data(from: URL(string: "\(base)/api/state?t=\(token)")!)
        let state = try JSONDecoder().decode(PageState.self, from: stateData)
        #expect(state.mode == "propose")
        #expect(state.items.map(\.id) == [made.id])

        var request = URLRequest(url: URL(string: "\(base)/api/choose")!)
        request.httpMethod = "POST"
        request.setValue(token, forHTTPHeaderField: "X-Meme-Token")
        request.httpBody = try JSONEncoder().encode(PickerResult(chosen: [made.id, "unknown"], note: "shorter"))
        _ = try await URLSession.shared.data(for: request)
        #expect(picker.wait(timeout: 5) == PickerResult(chosen: [made.id], note: "shorter"))
        #expect(StatusStore(url: library.paths.status).load().waitingForPick)
        picker.stop()
        #expect(!StatusStore(url: library.paths.status).load().waitingForPick)
        _ = home
    }

    @Test func klipyPickReturnsTheLinkUntouched() async throws {
        let (library, _) = try Self.library()
        let results = try Klipy.results(from: KlipyTests.fixture)
        let picker = try Picker(library: library, mode: .klipy(query: "hi", results: results, key: "unused"), ids: [])
        try picker.start()
        defer { picker.stop() }
        let token = URLComponents(url: picker.url, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "t" }!.value!
        func choose(_ slugs: [String]) async throws -> Int {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(picker.url.port!)/api/choose")!)
            request.httpMethod = "POST"
            request.setValue(token, forHTTPHeaderField: "X-Meme-Token")
            request.httpBody = try JSONEncoder().encode(PickerResult(chosen: slugs, note: ""))
            return (try await URLSession.shared.data(for: request).1 as! HTTPURLResponse).statusCode
        }
        #expect(try await choose([]) == 400)
        #expect(try await choose(["not-shown"]) == 400)
        #expect(try await choose(["result-4"]) == 400)
        #expect(picker.wait(timeout: 0.2) == nil)
        #expect(try await choose(["b-second"]) == 200)
        #expect(picker.wait(timeout: 5)?.link == "https://static.klipy.com/ii/x/b.gif?k=1")
    }
}
