import AppKit
import MemeCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSDraggingDestination {
    let model = AppModel()
    let libraryState = LibraryState()
    private var item: NSStatusItem!
    private var panel: PanelController!
    private(set) var library: NSWindow?
    private var refreshTimer: Timer?
    private var waitingCommand: DispatchSourceProcess?
    private var watchedRequest: String?
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
        NSApp.mainMenu = mainMenu()
        statusChanged(model.status)
        model.refreshIfStale()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refreshIfStale() }
        }
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
            watchedRequest = nil
            return
        }
        // The waiting command may be killed without a chance to withdraw its request.
        if watchedRequest != request.id {
            waitingCommand?.cancel()
            watchedRequest = request.id
            let source = DispatchSource.makeProcessSource(identifier: request.pid, eventMask: .exit, queue: .main)
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

    func openPanel() {
        guard let button = item.button else { return }
        panel.open(relativeTo: button)
    }

    @objc func openLibrary() {
        panel.close()
        if library == nil {
            let host = NSHostingController(rootView: LibraryView(state: libraryState).environmentObject(model))
            host.sizingOptions = [.minSize]
            let window = LibraryWindow(contentViewController: host)
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
}

/// Centres the traffic lights in the 52 pt top bar. A toolbar would place them there too, but it takes every click
/// in that row, including the search field's. AppKit puts them back on many layout passes, so this runs after each one.
final class LibraryWindow: NSWindow {
    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        guard !styleMask.contains(.fullScreen), let close = standardWindowButton(.closeButton),
              let container = close.superview?.superview else { return }
        let frame = NSRect(x: container.frame.minX, y: self.frame.height - topBarHeight, width: container.frame.width, height: topBarHeight)
        if container.frame != frame { container.frame = frame }
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = standardWindowButton(kind) else { continue }
            let y = ((button.superview?.frame.height ?? topBarHeight) - button.frame.height) / 2
            if button.frame.minY != y { button.setFrameOrigin(NSPoint(x: button.frame.minX, y: y)) }
        }
    }
}
