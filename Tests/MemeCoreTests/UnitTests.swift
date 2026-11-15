import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import MemeCore

struct ParserTests {
    @Test func parsesMemegenConfig() {
        let parsed = MemegenConfigParser.parse("""
        name: Distracted Boyfriend
        source: https://knowyourmeme.com/memes/distracted-boyfriend
        keywords:
          -
        text:
          - style: default
            color: white
            font: thick
            anchor_x: 0.12
            anchor_y: 0.7
            angle: 0.0
            scale_x: 0.325
            scale_y: 0.1
          - style: upper
            color: black
            anchor_x: 0.55
            anchor_y: 0.45
        example:
          - ''
          - 'it''s a trap: really'
          - lol: no
        overlay:
          - center_x: 0.5
            scale: 0.25
        """)
        #expect(parsed.name == "Distracted Boyfriend")
        #expect(parsed.keywords.isEmpty)
        #expect(parsed.example == ["", "it's a trap: really", "lol: no"])
        #expect(parsed.boxes.count == 2)
        #expect(parsed.boxes[0] == TextBox(anchorX: 0.12, anchorY: 0.7, scaleX: 0.325, scaleY: 0.1, style: "default"))
        #expect(parsed.boxes[1].color == "black")
        #expect(parsed.boxes[1].scaleX == 1)
    }
}

struct RulesTests {
    @Test(arguments: [
        ("https://media.giphy.com/media/abc/giphy.gif", "GIPHY"),
        ("https://giphy.com/gifs/x", "GIPHY"),
        ("https://static.klipy.com/a.gif", "KLIPY"),
        ("https://media.tenor.com/x.gif", "Tenor"),
    ])
    func refusesLinkOnlyServices(url: String, name: String) {
        #expect(Blocklist.service(for: URL(string: url)!) == name)
        #expect(throws: MemeError.self) { try Blocklist.check(URL(string: url)!) }
    }

    @Test func allowsOtherHosts() throws {
        #expect(Blocklist.service(for: URL(string: "https://upload.wikimedia.org/a.gif")!) == nil)
        #expect(Blocklist.service(for: URL(string: "https://notgiphy.com/a.gif")!) == nil)
        try Blocklist.check(URL(string: "https://raw.githubusercontent.com/x.png")!)
    }

    @Test func madeMemesTakeTheStrictestRight() {
        #expect([PostRight.freely, .personal].max() == .personal)
        #expect(PostRight.linkOnly.label == "Link only")
    }
}

struct SearchTests {
    let items: [Item] = {
        var fine = Item(id: "fine", kind: .template, title: "This is Fine", source: "memegen", rights: Rights(caption: true, post: .personal))
        fine.vibe = "pretending everything is okay as it falls apart"
        var girl = Item(id: "disastergirl", kind: .template, title: "Disaster Girl", source: "memegen", rights: Rights(caption: true, post: .personal))
        girl.vibe = "smug calm while everything burns"
        girl.popularity = 11
        var clip = Item(id: "s-1", kind: .clip, title: "build-fail", source: "saved", rights: Rights(caption: true, post: .personal))
        clip.tags = ["work", "ci"]
        return [fine, girl, clip]
    }()

    @Test func findsByFeeling() {
        let results = Search.run(SearchQuery(words: "smug burns"), in: items)
        #expect(results.first?.id == "disastergirl")
    }

    @Test func prefixAndKindFilter() {
        #expect(Search.run(SearchQuery(words: "pretend"), in: items).map(\.id) == ["fine"])
        #expect(Search.run(SearchQuery(words: "", kind: .clip), in: items).map(\.id) == ["s-1"])
        #expect(Search.run(SearchQuery(words: "the meme"), in: items).count == 3)
    }

    @Test func hiddenItemsStayHidden() {
        var hidden = items
        hidden[0].hidden = true
        #expect(Search.run(SearchQuery(words: "fine"), in: hidden).isEmpty)
    }

    @Test func matchesImgflipNamesToMemegen() {
        let drake = Item(id: "drake", kind: .template, title: "Drakeposting", source: "memegen",
                         rights: Rights(caption: true, post: .personal), keywords: ["Hotline Bling", "Drake"])
        let cat = Item(id: "woman-cat", kind: .template, title: "Woman Yelling at a Cat", source: "memegen",
                       rights: Rights(caption: true, post: .personal))
        func meme(_ name: String) -> Imgflip.Response.Meme {
            .init(id: "1", name: name, url: "https://i.imgflip.com/1.jpg", width: 1, height: 1, box_count: 2)
        }
        #expect(Imgflip.match(meme("Drake Hotline Bling"), in: [cat, drake])?.id == "drake")
        #expect(Imgflip.match(meme("Woman Yelling At Cat"), in: [drake, cat])?.id == "woman-cat")
        #expect(Imgflip.match(meme("Evil Kermit"), in: [drake, cat]) == nil)
    }

    @Test func seedVibesAreBundled() {
        #expect(SeedVibes.all.count > 300)
        #expect(SeedVibes.all["fine"]?.vibe.isEmpty == false)
    }
}

struct ConfigTests {
    @Test func partialFileFallsBackToDefaults() throws {
        let dir = try Scratch.make()
        let url = dir.appending(path: "config.json")
        try Data(#"{"fps": 20}"#.utf8).write(to: url)
        let config = try ConfigStore(url: url).load()
        #expect(config.fps == 20)
        #expect(config.width == Config.defaults.width)
    }

    @Test func brokenFileIsNeverOverwritten() throws {
        let dir = try Scratch.make()
        let url = dir.appending(path: "config.json")
        try Data("{ not json".utf8).write(to: url)
        #expect(throws: MemeError.self) { try ConfigStore(url: url).set("fps", to: "10") }
        #expect(try String(contentsOf: url, encoding: .utf8) == "{ not json")
    }

    @Test func validatesValues() throws {
        var config = Config.defaults
        #expect(throws: MemeError.self) { try config.set("fps", to: "500") }
        #expect(throws: MemeError.self) { try config.set("colour", to: "red") }
        try config.set("maxMB", to: "5")
        #expect(config.maxMB == 5)
    }

    @Test func trims() throws {
        #expect(try Trim.parse("0.4-2.9") == 0.4...2.9)
        #expect(try Trim.parse("-2") == 0...2)
        #expect(try Trim.parse("1.5-")?.lowerBound == 1.5)
        #expect(try Trim.parse("") == nil)
        #expect(throws: MemeError.self) { try Trim.parse("3-1") }
        #expect(throws: MemeError.self) { try Trim.parse("abc") }
    }
}

struct LayoutTests {
    @Test func panelsAreEvenAndAligned() {
        let sizes = [CGSize(width: 400, height: 300), CGSize(width: 300, height: 400)]
        let side = Planner.panels(layout: .side, sizes: sizes, width: 720)
        #expect(side.panels.allSatisfy { Int($0.height) == Int(side.height) })
        #expect(side.panels.allSatisfy { Int($0.width) % 2 == 0 && Int($0.height) % 2 == 0 })
        #expect(side.panels[1].minX == side.panels[0].maxX)

        let stack = Planner.panels(layout: .stack, sizes: sizes, width: 480)
        #expect(stack.panels.allSatisfy { $0.width == 480 })
        #expect(stack.height == stack.panels[1].maxY)

        let sequence = Planner.panels(layout: .sequence, sizes: sizes, width: 480)
        #expect(sequence.panels[0] == sequence.panels[1])
    }

    @Test func graphLoopsShortClipsAndSkipsFpsForStills() {
        let item = Item(id: "a", kind: .clip, title: "a", source: "saved", rights: Rights(caption: true, post: .personal))
        let long = RenderInput(item: item, file: URL(fileURLWithPath: "/a.gif"), info: MediaInfo(width: 100, height: 100, duration: 4, frames: 40), trim: nil)
        let short = RenderInput(item: item, file: URL(fileURLWithPath: "/b.gif"), info: MediaInfo(width: 100, height: 100, duration: 1, frames: 10), trim: nil)
        let plan = Planner.plan(layout: .side, inputs: [long, short], width: 400, maxSeconds: 6, barText: nil)
        #expect(plan.duration == 4)
        let args = FFmpegGraph.arguments(plan: plan, layout: .side, inputs: [long, short], panelOverlays: [nil, nil],
                                         globalOverlay: nil, fps: 10, outputs: .init(frames: URL(fileURLWithPath: "/f"), mp4: URL(fileURLWithPath: "/o.mp4")))
        let graph = args[args.firstIndex(of: "-filter_complex")! + 1]
        #expect(graph.contains("hstack=inputs=2"))
        #expect(graph.components(separatedBy: "loop=loop=-1").count == 2)

        let still = RenderInput(item: item, file: URL(fileURLWithPath: "/c.png"), info: MediaInfo(width: 100, height: 100, duration: 0, frames: 1), trim: nil)
        let stillPlan = Planner.plan(layout: .single, inputs: [still], width: 400, maxSeconds: 6, barText: nil)
        let stillArgs = FFmpegGraph.arguments(plan: stillPlan, layout: .single, inputs: [still], panelOverlays: [nil],
                                              globalOverlay: nil, fps: 1, outputs: .init(png: URL(fileURLWithPath: "/o.png")))
        #expect(!stillArgs.joined(separator: " ").contains("fps="))
        #expect(stillArgs.contains("-frames:v"))
    }

    @Test func captionsCheckTheirCount() throws {
        let plan = Plan(width: 400, contentHeight: 300, bar: 0, panels: [CGRect(x: 0, y: 0, width: 400, height: 300)], segments: [], duration: 0)
        #expect(throws: MemeError.self) { try Captions.blocks(style: .classic, captions: ["a", "b", "c"], plan: plan) }
        #expect(try Captions.blocks(style: .classic, captions: ["a", "b"], plan: plan).map(\.text) == ["A", "B"])
        #expect(throws: MemeError.self) {
            try Captions.templateBlocks(boxes: [TextBox(anchorX: 0, anchorY: 0, scaleX: 1, scaleY: 0.2)], captions: ["a", "b"], panel: CGSize(width: 10, height: 10))
        }
    }

    @Test func colorsAndCases() throws {
        #expect(Colors.named("khaki").components?.map { Int(($0 * 255).rounded()) } == [240, 230, 140, 255])
        #expect(Colors.named("#BBB").components?.first == Colors.named("#bbbbbb").components?.first)
        #expect(Colors.named("no-such-colour") == Colors.white)
        let boxes = [TextBox(anchorX: 0, anchorY: 0, scaleX: 1, scaleY: 0.2, style: "mock")]
        #expect(try Captions.templateBlocks(boxes: boxes, captions: ["meme lab"], panel: CGSize(width: 10, height: 10)).first?.text == "mEmE LaB")
        #expect(try Captions.templateBlocks(boxes: boxes, captions: ["aß"], panel: CGSize(width: 10, height: 10)).first?.text == "aSS")
        #expect(Colors.named("decade") == Colors.white)
        #expect(Colors.named("red") != Colors.white)
    }

    @Test func statusToleratesMissingKeys() throws {
        let status = try JSONFile.decoder().decode(Status.self, from: Data(#"{"picks": ["drake"]}"#.utf8))
        #expect(status.picks == ["drake"])
        #expect(!status.waitingForPick)
    }

    @Test func rivChecksBeforeUploading() throws {
        let file = try Scratch.make().appending(path: "x.gif")
        try Data("GIF89a".utf8).write(to: file)
        var config = Config.defaults
        config.rivHost = "invalid.host.example"
        #expect(throws: MemeError.self) { try Riv.send([file], caption: String(repeating: "a", count: 301), config: config) }
    }

    @Test func textShrinksToFit() {
        let big = TextLayout.fittingSize("hi", font: Fonts.classic, box: CGSize(width: 400, height: 100), maxSize: 100)
        let small = TextLayout.fittingSize("a much longer caption that has to wrap onto several lines", font: Fonts.classic, box: CGSize(width: 400, height: 100), maxSize: 100)
        #expect(big > small)
        #expect(TextLayout.widestWord("supercalifragilistic", font: Fonts.classic, size: small) <= 400)
    }
}

struct DeliveryTests {
    @Test func rivNamesAndCommand() {
        #expect(Riv.remoteName(URL(fileURLWithPath: "/x/m ab$c.gif")) == "m-ab-c.gif")
        let command = Riv.command(dropDir: "~/riv/drop", names: ["m-1.gif", "m-2.gif"], dryRun: true)
        #expect(command == "~/riv/ingress/tools/riv-drop --caption - --from 'Meme Lab' --dry-run ~/riv/drop/m-1.gif ~/riv/drop/m-2.gif")
    }

    @Test func rangesParse() {
        #expect(Picker.parseRange("bytes=0-99", size: 1000)! == (0, 99))
        #expect(Picker.parseRange("bytes=900-", size: 1000)! == (900, 999))
        #expect(Picker.parseRange("bytes=-100", size: 1000)! == (900, 999))
        #expect(Picker.parseRange("bytes=2000-", size: 1000) == nil)
    }

    @Test func clipboardUsesTheNamedPasteboard() throws {
        let file = try Scratch.make().appending(path: "x.gif")
        try Data("GIF89a".utf8).write(to: file)
        let name = "com.timgailey.memelab.test.\(UUID().uuidString)"
        try Clipboard.copyFile(file, environment: ["MEME_LAB_PASTEBOARD": name])
        let board = NSPasteboard(name: NSPasteboard.Name(name))
        #expect((board.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL)?.path == file.path)
    }
}

enum Scratch {
    /// Test files live in the package's .build folder, on the projects volume.
    static func make() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dir = root.appending(path: ".build/test-scratch/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

struct KlipyTests {
    static let fixture = Data("""
    {"result": true, "data": {"data": [
      {"slug": "b-second", "title": "B", "file": {"md": {"gif": {"url": "https://static.klipy.com/ii/x/b.gif?k=1"}}, "sm": {"webp": {"url": "https://static.klipy.com/ii/x/b.webp"}}}},
      {"slug": "a-first", "title": "A", "file": {"hd": {"mp4": {"url": "https://static.klipy.com/ii/x/a.mp4"}}}}
    ], "current_page": 1, "per_page": 24, "has_next": false}}
    """.utf8)

    @Test func keepsKlipysOrderAndEveryResult() throws {
        let results = try Klipy.results(from: Self.fixture)
        #expect(results.map(\.slug) == ["b-second", "a-first"])
        #expect(results[0].link == "https://static.klipy.com/ii/x/b.gif?k=1")
        #expect(results[0].preview.hasSuffix("b.webp"))
        #expect(results[1].link.hasSuffix("a.mp4"))
    }

    /// A stand-in `secrets` helper, ahead of the real one on the PATH.
    static func secrets(holding name: String, value: String) throws -> [String: String] {
        let dir = try Scratch.make()
        let tool = dir.appending(path: "secrets")
        let script = "#!/bin/sh\n[ \"$1\" = names ] && echo \(name) && exit 0\n[ \"$2\" = \(name) ] && echo \(value) && exit 0\nexit 1\n"
        try Data(script.utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        return ["PATH": dir.path]
    }

    @Test func readsTheKeyFromSecrets() throws {
        let env = try Self.secrets(holding: "KLIPY_API_KEY", value: "from-keychain")
        #expect(Klipy.configured(environment: env))
        #expect(try Klipy.key(environment: env) == "from-keychain")
    }

    @Test func offWithoutAKey() throws {
        let env = try Self.secrets(holding: "OTHER_SECRET", value: "x")
        #expect(!Klipy.configured(environment: env))
        let error = #expect(throws: MemeError.self) { try Klipy.key(environment: env) }
        #expect(error?.description.hasPrefix("KLIPY search is off") == true)
        #expect(Klipy.configured(environment: env.merging(["KLIPY_API_KEY": "k"]) { $1 }))
        #expect(try Klipy.key(environment: ["KLIPY_API_KEY": "k"]) == "k")
    }
}
