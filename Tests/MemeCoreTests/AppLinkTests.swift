import Foundation
import Testing
@testable import MemeCore
import MemeCLI

struct AppLinkTests {
    static func store() throws -> StatusStore {
        StatusStore(url: try Scratch.make().appending(path: "status.json"))
    }

    /// Plays the app: waits for the request to appear, then answers it.
    static func answer(after seconds: Double, in store: StatusStore, chosen: [String], note: String = "") {
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: seconds)
            guard let id = store.load().request?.id else { return }
            _ = try? AppLink.answer(id, chosen: chosen, note: note, store: store)
        }
    }

    @Test func theAppsAnswerComesBackAndTheRequestIsCleared() throws {
        let store = try Self.store()
        Self.answer(after: 0.3, in: store, chosen: ["m-2"], note: "shorter")
        let request = AppRequest(mode: .propose, items: ["m-1", "m-2"], max: 1, from: "Codex")
        let outcome = try AppLink.ask(request, store: store, timeout: 5, poll: 0.05, appAlive: { true })
        #expect(outcome == .answered(PickerResult(chosen: ["m-2"], note: "shorter")))
        let after = store.load()
        #expect(after.request == nil)
        #expect(after.answer == nil)
        #expect(!after.waitingForPick)
    }

    @Test func timingOutWithdrawsTheRequest() throws {
        let store = try Self.store()
        let request = AppRequest(mode: .pick, items: [], max: 2, from: nil)
        #expect(try AppLink.ask(request, store: store, timeout: 0.2, poll: 0.05, appAlive: { true }) == .timedOut)
        #expect(store.load().request == nil)
    }

    @Test func aQuitAppEndsTheWait() throws {
        let store = try Self.store()
        let request = AppRequest(mode: .propose, items: ["m-1"], max: 1, from: nil)
        #expect(try AppLink.ask(request, store: store, timeout: 5, poll: 0.05, appAlive: { false }) == .appQuit)
    }

    @Test func aReplacedRequestIsWithdrawnAndStaleAnswersAreRefused() throws {
        let store = try Self.store()
        let first = AppRequest(mode: .propose, items: ["m-1"], max: 1, from: nil)
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 0.2)
            _ = try? store.update { $0.request = AppRequest(mode: .pick, items: [], max: 1, from: nil) }
        }
        #expect(try AppLink.ask(first, store: store, timeout: 5, poll: 0.05, appAlive: { true }) == .withdrawn)
        #expect(try !AppLink.answer(first.id, chosen: ["m-1"], note: "", store: store))
        #expect(store.load().request?.mode == .pick)
    }

    @Test func statusReadsOldFilesAndOddRequests() throws {
        let old = try JSONFile.decoder().decode(Status.self, from: Data(#"{"picks": ["drake"], "proposal": {"options": ["m-1"]}, "request": 7}"#.utf8))
        #expect(old.picks == ["drake"])
        #expect(old.request == nil)
    }

    @Test func aDeadProcessIsNotAlive() {
        #expect(AppLink.isAlive(getpid()))
        #expect(!AppLink.isAlive(0))
        #expect(!AppLink.isAlive(Int32.max))
    }

    @Test func anUnreapedChildIsNotAlive() throws {
        var pid: pid_t = 0
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup("/usr/bin/true"), nil]
        defer { argv.forEach { free($0) } }
        #expect(posix_spawn(&pid, "/usr/bin/true", nil, nil, argv, nil) == 0)
        Thread.sleep(forTimeInterval: 0.3)
        #expect(kill(pid, 0) == 0, "the child should still be a zombie")
        #expect(!AppLink.isAlive(pid))
        var status: Int32 = 0
        waitpid(pid, &status, 0)
    }
}

struct LibrarySaveTests {
    @Test func twoWritersKeepEachOthersChanges() throws {
        let (first, home) = try PipelineTests.library()
        let rights = Rights(caption: true, post: .personal)
        first.upsert(Item(id: "a", kind: .clip, title: "A", source: "saved", rights: rights))
        first.upsert(Item(id: "b", kind: .clip, title: "B", source: "saved", rights: rights))
        try first.save()

        let paths = Paths.current(environment: ["MEME_LAB_HOME": home.path])
        let second = try Library(paths: paths, config: .defaults)
        _ = try first.update("a") { $0.vibe = "from the app" }
        _ = try second.update("b") { $0.vibe = "from a command" }
        second.upsert(Item(id: "c", kind: .made, title: "C", source: "made", rights: rights))
        try second.save()
        try first.save()

        let merged = try Library(paths: paths, config: .defaults)
        #expect(merged.items["a"]?.vibe == "from the app")
        #expect(merged.items["b"]?.vibe == "from a command")
        #expect(merged.items["c"] != nil)

        _ = try merged.remove("c")
        try merged.save()
        try first.reload()
        #expect(first.items["c"] == nil)
    }
}

struct AppConfigTests {
    @Test func agentCommandAndAnimationAreSettings() throws {
        let store = ConfigStore(url: try Scratch.make().appending(path: "config.json"))
        #expect(try store.load().agentCommand == "")
        #expect(try store.set("agentCommand", to: "echo \"$MEME_PROMPT\"").agentCommand == "echo \"$MEME_PROMPT\"")
        #expect(try store.set("animateAlways", to: "true").animateAlways)
        #expect(throws: MemeError.self) { try store.set("animateAlways", to: "yes") }
        #expect(try store.load().value(of: "animateAlways") == "true")
    }
}

struct CommandVerbTests {
    @Test func everySubcommandStartsTheCommandNotTheApp() {
        let verbs = Meme.verbs
        for verb in ["sync", "make", "propose", "pick", "picks", "send", "browse", "add", "import", "tag", "remove", "search", "status", "get", "set", "--help"] {
            #expect(verbs.contains(verb), "\(verb)")
        }
        #expect(!verbs.contains("--render"))
    }
}
