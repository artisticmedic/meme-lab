import AppKit
import MemeCLI
import MemeCore

// One binary: run as `meme`, or with a verb, it is the command; opened as the app, it is the menu bar app.
let arguments = Array(CommandLine.arguments.dropFirst())
let invokedAs = (CommandLine.arguments.first as NSString?)?.lastPathComponent
if invokedAs == "meme" || arguments.first.map(Meme.verbs.contains) == true {
    Task.detached {
        await Meme.main(arguments)
        exit(0)
    }
    dispatchMain()
}

if let flag = arguments.firstIndex(of: "--icon"), arguments.count > flag + 1 {
    exit(MainActor.assumeIsolated { Mark.writeAppIcon(to: URL(fileURLWithPath: arguments[flag + 1])) })
}
if let flag = arguments.firstIndex(of: "--render"), arguments.count > flag + 1 {
    exit(MainActor.assumeIsolated { Renderer.run(into: URL(fileURLWithPath: arguments[flag + 1])) })
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
