import AppKit
import MemeCore

/// Every action is sent to the first responder, so Copy and Select All reach a focused text field first and
/// fall through to the app delegate, which applies them to the library selection.
extension AppDelegate: NSMenuItemValidation {
    func mainMenu() -> NSMenu {
        let main = NSMenu()
        func menu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let item = NSMenuItem(), submenu = NSMenu(title: title)
            items.forEach(submenu.addItem)
            item.submenu = submenu
            main.addItem(item)
            return submenu
        }
        func item(_ title: String, _ action: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.tag = tag
            return item
        }
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services")
        NSApp.servicesMenu = services.submenu

        _ = menu(About.short, [
            item("About \(About.short)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("Settings…", #selector(openSettings), ","),
            .separator(),
            services,
            .separator(),
            item("Hide \(About.short)", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit \(About.short)", #selector(NSApplication.terminate(_:)), "q"),
        ])
        _ = menu("File", [
            item("Make GIF…", #selector(makeGIF), "n"),
            .separator(),
            item("Add Files…", #selector(addFiles), "o"),
            item("Add My Own Recordings…", #selector(addRecordings), "o", [.command, .shift]),
            item("New Collection…", #selector(newCollection), "n", [.command, .shift]),
            .separator(),
            item("Show in Finder", #selector(showInFinder), "r", [.command, .shift]),
            item("Move to Trash…", #selector(moveToTrash), "\u{8}"),
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w"),
        ])
        _ = menu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            item("Deselect All", #selector(deselectAll), "a", [.command, .option]),
            .separator(),
            item("Find…", #selector(find), "f"),
        ])
        _ = menu("View", Shelf.library.enumerated().map { index, shelf in
            item(shelf.title, #selector(showShelf(_:)), "\(index + 1)", tag: index)
        } + [
            .separator(),
            item("Show Details", #selector(toggleDetails), "i"),
            item("Tiles Always Move", #selector(toggleAnimation)),
            .separator(),
            item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]),
        ])
        _ = menu("Meme", [
            item("Pick", #selector(togglePickSelection), "d"),
            item("Clear Picks", #selector(clearPicks), "d", [.command, .shift]),
            .separator(),
            item("Copy Prompt for Agent", #selector(copyPrompt), "c", [.command, .shift]),
            item("Ask Agent", #selector(askAgent), "\r"),
            .separator(),
            item("Refresh Templates", #selector(refreshTemplates), "r"),
        ])
        NSApp.windowsMenu = menu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Library", #selector(openLibrary), "l"),
            item("Menu Bar Panel", #selector(showPanel), "m", [.command, .option]),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))),
        ])
        NSApp.helpMenu = menu("Help", [
            item("\(About.short) Help", #selector(openHelp)),
            item("Report an Issue…", #selector(reportIssue)),
        ])
        return main
    }

    private var inLibrary: Bool { NSApp.keyWindow === library && libraryState.shelf != .settings }
    private var editingText: Bool { NSApp.keyWindow?.firstResponder is NSText }
    private var selection: [String] { libraryState.selection }
    private var selectedFile: URL? {
        guard let item = selection.last.flatMap(model.item), item.kind != .template else { return nil }
        return model.localFile(item)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(makeGIF): return inLibrary && DetailPane.canMake(selection, model: model)
        case #selector(newCollection), #selector(deselectAll): return inLibrary && !selection.isEmpty
        case #selector(showInFinder): return inLibrary && selectedFile != nil
        case #selector(moveToTrash), #selector(copy(_:)): return inLibrary && !selection.isEmpty && !editingText
        case #selector(selectAll(_:)): return inLibrary
        case #selector(showShelf(_:)):
            item.state = library != nil && Shelf.library.indices.contains(item.tag) && libraryState.shelf == Shelf.library[item.tag] ? .on : .off
            return true
        case #selector(toggleDetails):
            item.title = libraryState.showsDetails ? "Hide Details" : "Show Details"
            return library != nil && libraryState.shelf != .settings
        case #selector(toggleAnimation):
            item.state = model.config.animateAlways ? .on : .off
            return true
        case #selector(togglePickSelection):
            item.title = !selection.isEmpty && selection.allSatisfy(model.status.picks.contains) ? "Unpick" : "Pick"
            return inLibrary && !selection.isEmpty && !editingText
        case #selector(clearPicks), #selector(copyPrompt): return !model.status.picks.isEmpty
        case #selector(askAgent): return inLibrary && !model.status.picks.isEmpty && !model.config.agentCommand.isEmpty
        case #selector(refreshTemplates): return !model.syncing
        default: return true
        }
    }

    @objc func makeGIF() { libraryState.making = selection }

    @objc func addRecordings() {
        openLibrary()
        guard let files = LibraryView.chooseMedia() else { return }
        model.add(files, recording: true)
    }

    @objc func newCollection() { libraryState.naming = true }

    @objc func showInFinder() {
        if let selectedFile { NSWorkspace.shared.activateFileViewerSelecting([selectedFile]) }
    }

    @objc func moveToTrash() { libraryState.removing = selection }

    @objc func copy(_ sender: Any?) {
        let items = selection.compactMap(model.item)
        Task { await model.copy(items) }
    }

    @objc func selectAll(_ sender: Any?) {
        libraryState.selection = model.items(libraryState.shelf, matching: libraryState.query).map(\.id)
    }

    @objc func deselectAll() { libraryState.selection = [] }

    @objc func find() {
        if libraryState.shelf == .settings { libraryState.shelf = .all }
        libraryState.wantsSearchFocus = true
        openLibrary()
    }

    @objc func showShelf(_ sender: NSMenuItem) {
        guard Shelf.library.indices.contains(sender.tag) else { return }
        libraryState.shelf = Shelf.library[sender.tag]
        libraryState.selection = []
        openLibrary()
    }

    @objc func toggleDetails() { libraryState.showsDetails.toggle() }

    @objc func toggleAnimation() { model.setting("animateAlways", model.config.animateAlways ? "false" : "true") }

    @objc func togglePickSelection() {
        if selection.allSatisfy(model.status.picks.contains) { model.unpick(selection) } else { model.pick(selection) }
    }

    @objc func clearPicks() { model.clearPicks() }
    @objc func copyPrompt() { model.copyPrompt(idea: "") }
    @objc func askAgent() { model.askAgent(idea: "") }
    @objc func refreshTemplates() { model.sync() }
    @objc func showPanel() { openPanel() }

    @objc func openHelp() { NSWorkspace.shared.open(URL(string: "https://github.com/artisticmedic/meme-lab#readme")!) }
    @objc func reportIssue() { NSWorkspace.shared.open(URL(string: "https://github.com/artisticmedic/meme-lab/issues/new")!) }
}
