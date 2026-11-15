import ArgumentParser
import Darwin
import Foundation
import MemeCore

@main
struct Meme: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "meme",
        abstract: "Tim's Astonishing Meme Laboratory: find, caption and deliver meme GIFs.",
        discussion: "Reads print JSON. Errors are one plain sentence on stderr. Run `meme sync` first.",
        version: "0.1.0",
        subcommands: [
            SearchCommand.self, Info.self, Make.self, Propose.self, Send.self, Pick.self, Picks.self, Browse.self, KlipyCommand.self,
            Add.self, Import.self, Untagged.self, Tag.self, Collect.self, Remove.self, Sync.self,
            StatusCommand.self, GetCommand.self, SetCommand.self,
        ]
    )
}

func output<T: Encodable>(_ value: T) throws { print(try jsonString(value)) }

func say(_ message: String) { FileHandle.standardError.write(Data((message + "\n").utf8)) }

func openInBrowser(_ url: URL) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [url.absoluteString]
    try? process.run()
}

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(commandName: "search", abstract: "Find items by name or feeling.")
    @Argument(help: "Words to search for. Leave empty to list the most popular.") var words: [String] = []
    @Option(help: "template, clip or made.") var kind: Kind?
    @Option(help: "Only items in this collection.") var collection: String?
    @Flag(help: "Only templates new to Imgflip's popular list or to memegen in the last two weeks.") var rising = false
    @Option(help: "How many results.") var limit = 12

    func run() async throws {
        let library = try Library.open()
        let query = SearchQuery(words: words.joined(separator: " "), kind: kind, collection: collection, risingOnly: rising, limit: limit)
        try output(Search.run(query, in: Array(library.items.values)).map { ItemSummary($0, library: library) })
    }
}

extension Kind: ExpressibleByArgument {}
extension CaptionStyle: ExpressibleByArgument {}
extension Layout: ExpressibleByArgument {}

struct Info: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Everything about one item, plus a three-frame strip image to look at.",
        discussion: "Downloads a template the first time. Open the `strip` PNG to judge fit and motion."
    )
    @Argument var id: String

    struct Output: Encodable {
        let item: Item
        let media: String
        let strip: String
        let seconds: Double
        let frames: Int
    }

    func run() async throws {
        let library = try Library.open()
        let item = try library.item(id)
        let media = try await library.ensureMedia(item)
        let info = try MemeCore.Media.probe(media)
        let strip = try MemeCore.Media.strip(for: item, media: media, info: info, into: library.paths.strips)
        try output(Output(item: item, media: media.path, strip: strip.path, seconds: info.duration, frames: info.frames))
    }
}

struct Make: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Render a captioned meme from one to four items. Writes a GIF and an MP4, or a PNG when nothing moves.",
        discussion: """
        Styles: classic (Impact, top and bottom), bar (white bar above), subtitle (bottom), template (memegen's own boxes).
        Layouts: single, side, stack, sequence. --label puts a short label on each panel, in item order.
        """
    )
    @Argument(help: "Item ids, in panel order.") var ids: [String]
    @Option(name: .shortAndLong, help: "A caption. Repeat for top then bottom, or one per template box.") var caption: [String] = []
    @Option(help: "A label for each panel, in order.") var label: [String] = []
    @Option(help: "classic, bar, subtitle or template.") var style: CaptionStyle?
    @Option(help: "single, side, stack or sequence.") var layout: Layout?
    @Option(help: "Seconds to keep from each moving item, like 0.4-2.9. Repeat per item.") var trim: [String] = []
    @Option(help: "Output width in pixels.") var width: Int?
    @Option(help: "Frames per second.") var fps: Int?
    @Option(name: .customLong("max-mb"), help: "Shrink the GIF until it fits.") var maxMB: Double?
    @Option(name: .customLong("max-seconds"), help: "Longest a moving item may run.") var maxSeconds: Double?

    func run() async throws {
        let library = try Library.open()
        let result = try await library.make(MakeRequest(
            ids: ids, captions: caption, labels: label, style: style, layout: layout, trims: trim,
            width: width, fps: fps, maxMB: maxMB, maxSeconds: maxSeconds
        ))
        try library.save()
        try StatusStore(url: library.paths.status).update { $0.lastMade = result.id }
        try output(result)
    }
}

struct Propose: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show finished options in the picker page and wait for Tim to choose one.",
        discussion: "Prints {\"chosen\": [id], \"note\": \"...\"}. An empty choice with a note means \"change this\". Exit 124 on timeout."
    )
    @Argument(help: "Made ids, in the order to show them.") var ids: [String]
    @Option(name: .customLong("from"), help: "Who is asking, shown on the page (Claude, Codex, Cursor).") var agent: String?
    @Flag(help: "Also post the options to Riv's Meme Lab thread, for Tim on his phone.") var riv = false
    @Option(help: "Seconds to wait.") var timeout: Double = 900
    @Flag(name: .customLong("no-open"), help: "Print the link instead of opening the browser.") var noOpen = false

    func run() throws {
        let library = try Library.open()
        let items = try ids.map(library.item)
        if let notMade = items.first(where: { $0.kind != .made }) {
            throw MemeError("\(notMade.id) is not a finished meme; propose takes ids from `meme make`.")
        }
        let store = StatusStore(url: library.paths.status)
        try store.update { $0.proposal = MemeCore.Proposal(options: ids, from: agent, createdAt: Date()) }
        if riv {
            let files = items.compactMap { library.localFile(for: $0) }
            let result = try Riv.send(files, caption: "Meme Lab: \(files.count) options\(agent.map { " from \($0)" } ?? ""). Tell your agent which number.", config: library.config)
            say("Posted to Riv: \(result.links.joined(separator: " "))")
        }
        let picker = try Picker(library: library, mode: .propose(from: agent), ids: ids)
        try waitForChoice(picker, timeout: timeout, open: !noOpen)
    }
}

struct Pick: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Let Tim pick items in the picker page, and print his picks.",
        discussion: "Prints {\"chosen\": [ids], \"note\": \"\"}. Exit 124 on timeout."
    )
    @Option(help: "Limit the page to these ids (comma-separated) or the results for these words.") var from: String?
    @Option(help: "Most items Tim may pick.") var max = 2
    @Option(help: "Seconds to wait.") var timeout: Double = 900
    @Flag(name: .customLong("no-open"), help: "Print the link instead of opening the browser.") var noOpen = false

    func run() throws {
        let library = try Library.open()
        var ids: [String]?
        if let from {
            let listed = from.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            ids = listed.allSatisfy({ library.items[$0] != nil })
                ? listed
                : Search.run(SearchQuery(words: from, limit: 30), in: Array(library.items.values)).map(\.id)
            if ids?.isEmpty ?? true { throw MemeError("Nothing in the library matches \"\(from)\".") }
        }
        let picker = try Picker(library: library, mode: .pick(max: max), ids: ids)
        let result = try waitForChoice(picker, timeout: timeout, open: !noOpen)
        try StatusStore(url: library.paths.status).update { $0.picks = result.chosen }
    }
}

/// Keep the returned source alive.
func stopOnInterrupt(_ picker: Picker, exitCode: Int32) -> DispatchSourceSignal {
    let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
    signal(SIGINT, SIG_IGN)
    source.setEventHandler { picker.stop(); Darwin.exit(exitCode) }
    source.setCancelHandler { signal(SIGINT, SIG_DFL) }
    source.resume()
    return source
}

@discardableResult
func waitForChoice(_ picker: Picker, timeout: Double, open: Bool, print printResult: Bool = true) throws -> PickerResult {
    try picker.start()
    let interrupt = stopOnInterrupt(picker, exitCode: 130)
    defer { interrupt.cancel() }
    say("Picker page: \(picker.url.absoluteString)")
    if open { openInBrowser(picker.url) }
    let result = picker.wait(timeout: timeout)
    picker.stop()
    guard let result else {
        say("Nobody chose within \(Int(timeout)) second\(Int(timeout) == 1 ? "" : "s").")
        throw ExitCode(124)
    }
    if printResult { try output(result) }
    return result
}

struct Browse: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Open the whole library in the browser to look around and pick. Runs until Control-C.",
        discussion: "Picks made here are saved; an agent reads them with `meme picks`."
    )
    @Option(help: "Port on 127.0.0.1. 0 picks a free one.") var port: UInt16 = 0
    @Flag(name: .customLong("no-open"), help: "Print the link instead of opening the browser.") var noOpen = false

    func run() throws {
        let picker = try Picker(library: try Library.open(), mode: .browse, port: port)
        try picker.start()
        let interrupt = stopOnInterrupt(picker, exitCode: 0)
        defer { interrupt.cancel() }
        say("Meme Lab is open at \(picker.url.absoluteString)")
        say("Control-C to stop.")
        if !noOpen { openInBrowser(picker.url) }
        _ = picker.wait(timeout: .greatestFiniteMagnitude)
    }
}

struct KlipyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "klipy",
        abstract: "Search KLIPY in its own grid and let Tim pick one to share as a link. Needs a KLIPY_API_KEY secret.",
        discussion: "KLIPY media is link-only: never downloaded, captioned or re-ordered. Prints {\"chosen\": [slug], \"link\": \"...\"}."
    )
    @Argument(help: "What to search for.") var words: [String]
    @Flag(help: "Put the chosen link on the clipboard as text.") var copy = false
    @Option(help: "Seconds to wait.") var timeout: Double = 900
    @Flag(name: .customLong("no-open"), help: "Print the link instead of opening the browser.") var noOpen = false

    func run() async throws {
        let library = try Library.open()
        let key = try Klipy.key()
        let query = words.joined(separator: " ")
        let results = try await Klipy.search(query, key: key)
        let picker = try Picker(library: library, mode: .klipy(query: query, results: results, key: key), ids: [])
        let result = try waitForChoice(picker, timeout: timeout, open: !noOpen, print: false)
        if copy, let link = result.link { try Clipboard.copyText(link) }
        try output(result)
    }
}

struct Picks: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "The items Tim has picked, with their details.",
        subcommands: [Show.self, AddPick.self, Clear.self], defaultSubcommand: Show.self
    )

    struct Show: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "show", abstract: "Print the picks.")
        func run() throws {
            let library = try Library.open()
            let picks = StatusStore(url: library.paths.status).load().picks
            try output(picks.compactMap { library.items[$0] }.map { ItemSummary($0, library: library) })
        }
    }

    struct AddPick: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "add", abstract: "Add items to the picks.")
        @Argument var ids: [String]
        func run() throws {
            let library = try Library.open()
            for id in ids { _ = try library.item(id) }
            let status = try StatusStore(url: library.paths.status).update { status in
                status.picks += ids.filter { !status.picks.contains($0) }
            }
            try output(status.picks)
        }
    }

    struct Clear: ParsableCommand {
        static let configuration = CommandConfiguration(commandName: "clear", abstract: "Empty the picks.")
        func run() throws {
            try StatusStore(url: Paths.current().status).update { $0.picks = [] }
            try output([String]())
        }
    }
}

struct Send: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Deliver a finished meme: the clipboard (default), a folder, or Riv's Discord thread.",
        discussion: "The clipboard gets the file itself, so pasting into Discord uploads it."
    )
    @Argument var id: String
    @Flag(help: "Put the file on the clipboard. The default when nothing else is chosen.") var copy = false
    @Option(help: "Copy the file into this folder.") var save: String?
    @Flag(help: "Post it to Riv's Meme Lab thread in Discord.") var riv = false
    @Option(help: "One-line caption for the Riv post.") var caption: String?
    @Flag(help: "Send the MP4 instead of the GIF.") var mp4 = false
    @Flag(name: .customLong("dry-run"), help: "With --riv: Riv checks the file, token and thread and posts nothing. The file is still copied to the M1.") var dryRun = false

    struct Output: Encodable {
        let id: String
        let file: String
        var copied = false
        var saved: String?
        var riv: RivResult?
    }

    func run() async throws {
        let library = try Library.open()
        let item = try library.item(id)
        let file: URL
        if mp4 {
            guard let path = item.made?.mp4 else { throw MemeError("\(id) has no MP4.") }
            file = library.root.appending(path: path)
        } else {
            file = try await library.ensureMedia(item)
        }
        var result = Output(id: id, file: file.path)
        if copy || (save == nil && !riv) {
            try Clipboard.copyFile(file)
            result.copied = true
        }
        if let save {
            let folder = URL(fileURLWithPath: (save as NSString).expandingTildeInPath, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appending(path: file.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) {
                throw MemeError("\(target.path) already exists.")
            }
            try FileManager.default.copyItem(at: file, to: target)
            result.saved = target.path
        }
        if riv {
            let text = caption ?? item.made?.captions.first { !$0.isEmpty } ?? item.title
            result.riv = try Riv.send([file], caption: text, config: library.config, dryRun: dryRun)
        }
        if !dryRun {
            _ = try library.update(id) { $0.lastUsed = Date(); $0.useCount += 1 }
            try library.save()
        }
        try output(result)
    }
}

struct Add: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Add a GIF, image or video to the library from a file or a link.",
        discussion: "Wikimedia Commons links keep their licence and credit. GIPHY, KLIPY and Tenor links are refused: their terms allow links only."
    )
    @Argument(help: "A file path or an http(s) link.") var source: String
    @Flag(help: "This is Tim's own recording (posts freely).") var recording = false
    @Option(help: "A title. Defaults to the file name.") var title: String?
    @Option(help: "A tag. Repeat for more.") var tag: [String] = []

    func run() async throws {
        let library = try Library.open()
        let item: Item
        if let url = URL(string: source), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            item = try await library.add(url: url, title: title, tags: tag)
        } else {
            item = try library.add(file: URL(fileURLWithPath: (source as NSString).expandingTildeInPath), recording: recording, title: title, tags: tag)
        }
        try library.save()
        try output(ItemSummary(item, library: library))
    }
}

struct Import: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Add every GIF, image and video in a folder, such as GIF Machine's save folder.")
    @Argument var folder: String
    @Flag(help: "These are Tim's own recordings.") var recording = false

    struct Output: Encodable {
        let added: [ItemSummary]
        let skipped: [String]
    }

    func run() throws {
        let library = try Library.open()
        let result = try library.importFolder(URL(fileURLWithPath: (folder as NSString).expandingTildeInPath), recording: recording)
        try library.save()
        try output(Output(added: result.added.map { ItemSummary($0, library: library) }, skipped: result.skipped))
    }
}

struct Untagged: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Items with no feeling written yet. Look at each with `meme info`, then `meme tag`."
    )
    @Option var limit = 20

    func run() throws {
        let library = try Library.open()
        let items = library.visible.filter { $0.vibe == nil }.sorted { $0.added > $1.added }.prefix(limit)
        try output(items.map { ItemSummary($0, library: library) })
    }
}

struct Tag: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Write an item's feeling, tags or how it's used.")
    @Argument var id: String
    @Option(help: "One line on the feeling or situation, like \"smug calm while everything burns\".") var vibe: String?
    @Option(help: "Add a tag. Repeat for more.") var add: [String] = []
    @Option(help: "Remove a tag. Repeat for more.") var remove: [String] = []
    @Option(name: .customLong("how-used"), help: "One sentence on how the format is used.") var howUsed: String?
    @Option(help: "A new title.") var title: String?

    func run() throws {
        let library = try Library.open()
        let item = try library.update(id) { item in
            if let vibe { item.vibe = vibe }
            if let howUsed { item.howUsed = howUsed }
            if let title { item.title = title }
            let removed = Set(remove.map { $0.lowercased() })
            item.tags = Array(Set(item.tags + add.map { $0.lowercased() }).subtracting(removed)).sorted()
        }
        try library.save()
        try output(ItemSummary(item, library: library))
    }
}

struct Collect: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Put an item in a collection, or take it out.")
    @Argument var id: String
    @Argument var collection: String
    @Flag(help: "Take it out instead.") var remove = false

    func run() throws {
        let library = try Library.open()
        let item = try library.update(id) { item in
            item.collections.removeAll { $0 == collection }
            if !remove { item.collections.append(collection) }
        }
        try library.save()
        try output(ItemSummary(item, library: library))
    }
}

struct Remove: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove an item. Saved and made files go to the Trash; templates are hidden."
    )
    @Argument var id: String

    func run() throws {
        let library = try Library.open()
        let item = try library.remove(id)
        try library.save()
        try StatusStore(url: library.paths.status).update { $0.picks.removeAll { $0 == id } }
        say(item.kind == .template ? "Hid \(id)." : "Removed \(id). Its files, if it had any, are in the Trash.")
    }
}

struct Sync: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Refresh templates from memegen and Imgflip's popular list. Images download on first use."
    )

    func run() async throws {
        let library = try Library.open()
        let report = try await library.sync()
        try library.save()
        try output(report)
    }
}

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "status", abstract: "What Meme Lab is doing now, and where its files are.")

    struct Output: Encodable {
        let status: MemeCore.Status
        let items: [String: Int]
        let untagged: Int
        let klipy: Bool
        let lastSync: Date?
        let library: String
        let config: String
        let statusFile: String
    }

    func run() throws {
        let library = try Library.open()
        var counts: [String: Int] = [:]
        for item in library.visible { counts[item.kind.rawValue, default: 0] += 1 }
        try output(Output(
            status: StatusStore(url: library.paths.status).load(), items: counts,
            untagged: library.visible.filter { $0.vibe == nil }.count, klipy: Klipy.configured(), lastSync: library.lastSync,
            library: library.root.path, config: library.paths.config.path, statusFile: library.paths.status.path
        ))
    }
}

struct GetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "get", abstract: "Print a setting, or all of them.")
    @Argument var key: String?

    func run() throws {
        let config = try ConfigStore(url: Paths.current().config).load()
        if let key { print(try config.value(of: key)) } else { try output(config) }
    }
}

struct SetCommand: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "set", abstract: "Change a setting in config.json.")
    @Argument var key: String
    @Argument var value: String

    func run() throws {
        try output(try ConfigStore(url: Paths.current().config).set(key, to: value))
    }
}
