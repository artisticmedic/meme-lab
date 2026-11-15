import AppKit
import ArgumentParser
import MemeCore

enum AppBridge {
    static var bundle: URL? {
        let executable = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0]).resolvingSymlinksInPath()
        let bundle = executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return bundle.pathExtension == "app" ? bundle : nil
    }

    static func isMemeLab(_ pid: Int32) -> Bool {
        AppLink.isAlive(pid) && NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == AppLink.bundleID
    }

    /// With MEME_LAB_HOME set it never starts one, because `open` would not pass the variable on.
    static func connect(_ paths: Paths, launchArguments: [String] = ["--quiet"]) -> (() -> Bool)? {
        let store = StatusStore(url: paths.status)
        if let pid = AppLink.appPID(store, alive: isMemeLab) { return { isMemeLab(pid) } }
        guard ProcessInfo.processInfo.environment["MEME_LAB_HOME"] == nil, let bundle else { return nil }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", "-a", bundle.path, "--args"] + launchArguments
        guard (try? open.run()) != nil else { return nil }
        open.waitUntilExit()
        for _ in 0..<50 {
            if let pid = AppLink.appPID(store, alive: isMemeLab) { return { isMemeLab(pid) } }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return nil
    }

    static func notify(_ verb: String) {
        DistributedNotificationCenter.default().postNotificationName(AppLink.command, object: verb, userInfo: nil, deliverImmediately: true)
    }

    static func wait(_ request: AppRequest, store: StatusStore, timeout: Double, appAlive: () -> Bool) throws -> PickerResult {
        let interrupt = onInterrupt(exitCode: 130) {
            AppLink.withdraw(request.id, store: store)
            notify("changed")
        }
        defer { interrupt.cancel() }
        let outcome = try AppLink.ask(request, store: store, timeout: timeout, appAlive: appAlive, notify: { notify("changed") })
        notify("changed")
        switch outcome {
        case .answered(let result):
            return result
        case .timedOut:
            throw nobodyChose(timeout)
        case .withdrawn:
            throw MemeError("Another request replaced this one before anyone chose.")
        case .appQuit:
            throw MemeError("Meme Lab quit before anyone chose. Run the command again.")
        }
    }
}
