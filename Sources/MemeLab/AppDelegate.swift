import AppKit
import MemeCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSDraggingDestination {
    private let model = AppModel()
    private let libraryState = LibraryState()
    private var item: NSStatusItem!
    private var panel: PanelController!
    private var library: NSWindow?
    private var waitingCommand: DispatchSourceProcess?
    private var openedRequest: String?

    func applicationDidFinishLaunching(_ note: Notification) {
        if let other = AppLink.appPID(model.store), other != getpid(),
           NSRunningApplication(processIdentifier: other)?.bundleIdentifier == AppLink.bundleID {
            DistributedNotificationCenter.default().postNotificationName(AppLink.command, object: "open-library", userInfo: nil, deliverImmediately: true)
            NSApp.terminate(nil)
            return
        }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        item.button?.window?.registerForDraggedTypes([.fileURL])
        item.button?.window?.delegate = self
        panel = PanelController(model: model) { [weak self] action in
            switch action {
            case .library: self?.openLibrary()
            case .quit: NSApp.terminate(nil)
            }
        }
        model.onStatusChange = { [weak self] _, status in self?.statusChanged(status) }
        model.startWatching()
        do {
            try model.store.update { $0.app = AppState(pid: getpid()) }
        } catch {
            model.error = "Could not write \(model.paths.status.path): \(error)"
        }
        DistributedNotificationCenter.default().addObserver(forName: AppLink.command, object: nil, queue: .main) { [weak self] note in
            let verb = note.object as? String
            MainActor.assumeIsolated {
                switch verb {
                case "open-library": self?.openLibrary()
                case "open-panel": self?.openPanel()
                default: self?.model.filesChanged()
                }
            }
        }
        NSApp.mainMenu = Self.mainMenu()
        statusChanged(model.status)
        let arguments = CommandLine.arguments
        let atLogin = NSAppleEventManager.shared().currentAppleEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        if arguments.contains("--library") || (!atLogin && !arguments.contains("--quiet") && model.status.request == nil) { openLibrary() }
    }

    func applicationWillTerminate(_ note: Notification) {
        _ = try? model.store.update { status in
            if status.app?.pid == getpid() { status.app = nil }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        openLibrary()
        return false
    }

    private func statusChanged(_ status: Status) {
        item.button?.image = Mark.menuBarIcon(waiting: status.request != nil)
        panel.state.sync(with: status.request)
        guard let request = status.request else {
            waitingCommand?.cancel()
            waitingCommand = nil
            return
        }
        // The waiting command may be killed without a chance to withdraw its request.
        if waitingCommand?.handle != request.pid {
            waitingCommand?.cancel()
            let source = DispatchSource.makeProcessSource(identifier: request.pid, eventMask: .exit, queue: .main)
            // An exited command that its parent has not reaped yet still answers kill(pid, 0), so withdraw here, not by liveness.
            let id = request.id, store = model.store
            source.setEventHandler { [weak self] in
                AppLink.withdraw(id, store: store)
                MainActor.assumeIsolated { self?.model.reloadStatus() }
            }
            source.resume()
            waitingCommand = source
            if !AppLink.isAlive(request.pid) { model.reloadStatus() }
        }
        if request.open, openedRequest != request.id {
            openedRequest = request.id
            panel.close()
            openPanel()
        }
    }

    @objc private func togglePanel() {
        guard let button = item.button else { return }
        panel.toggle(relativeTo: button)
    }

    private func openPanel() {
        guard let button = item.button else { return }
        panel.open(relativeTo: button)
    }

    @objc func openLibrary() {
        panel.close()
        if library == nil {
            let host = NSHostingController(rootView: LibraryView(state: libraryState).environmentObject(model))
            host.sizingOptions = [.minSize]
            let window = NSWindow(contentViewController: host)
            window.title = About.short
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.setContentSize(NSSize(width: 1180, height: 760))
            window.center()
            window.setFrameAutosaveName("LibraryWindow")
            library = window
        }
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async { [weak self] in
            NSApp.activate()
            self?.library?.makeKeyAndOrderFront(nil)
        }
    }

    @objc func openSettings() {
        libraryState.shelf = .settings
        openLibrary()
    }

    @objc func addFiles() {
        openLibrary()
        guard let files = LibraryView.chooseMedia() else { return }
        model.add(files, recording: false)
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === library else { return }
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
    }

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Self.files(sender).isEmpty ? [] : .copy
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let files = Self.files(sender)
        guard !files.isEmpty else { return false }
        model.add(files, recording: false)
        return true
    }

    private static func files(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    private static func mainMenu() -> NSMenu {
        let main = NSMenu()
        func add(_ title: String, _ items: [NSMenuItem]) {
            let item = NSMenuItem(), menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            item.submenu = menu
            main.addItem(item)
        }
        add(About.short, [
            NSMenuItem(title: "About \(About.short)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""),
            NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","),
            .separator(),
            NSMenuItem(title: "Hide \(About.short)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"),
            .separator(),
            NSMenuItem(title: "Quit \(About.short)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"),
        ])
        add("File", [
            NSMenuItem(title: "Add Files…", action: #selector(addFiles), keyEquivalent: "o"),
            NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
        ])
        add("Edit", [
            NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"),
            NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"),
            .separator(),
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ])
        add("Window", [
            NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"),
            NSMenuItem(title: "Library", action: #selector(openLibrary), keyEquivalent: "l"),
        ])
        return main
    }
}
