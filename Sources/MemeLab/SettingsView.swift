import AppKit
import MemeCore
import ServiceManagement
import SwiftUI
import Synchronization

struct SettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            TopBar {
                Text("Settings").font(.system(size: 15, weight: .semibold))
                    .padding(.leading, 30).frame(maxWidth: 640, alignment: .leading).frame(maxWidth: .infinity)
            }
            ScrollView { content }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let problem = model.configProblem {
                Text(problem).font(.system(size: 13)).padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.07)))
            }
            if let error = model.error {
                HStack(alignment: .top) {
                    Text(error).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    IconButton(symbol: "xmark", label: "Dismiss") { model.error = nil }
                }
                .padding(.leading, 12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.07)))
            }
            SectionLabel(text: "Library")
            Card {
                Row(title: "Library folder", caption: "\(libraryFolder). Choosing another folder moves your saved and made files there.") {
                    Button("Choose…", action: chooseFolder).buttonStyle(PillButtonStyle())
                }
                RowDivider()
                Row(title: "Templates", caption: templatesCaption) {
                    Button(model.syncing ? "Refreshing…" : "Refresh Now") { model.sync() }
                        .buttonStyle(PillButtonStyle())
                        .disabled(model.syncing)
                }
            }
            SectionLabel(text: "Making memes").padding(.top, 10)
            Card {
                NumberRow(title: "Largest GIF", caption: "Frame rate, then size, drop until the GIF fits.", unit: "MB", key: "maxMB", value: model.config.maxMB.formatted())
                RowDivider()
                NumberRow(title: "Width", caption: nil, unit: "px", key: "width", value: "\(model.config.width)")
                RowDivider()
                NumberRow(title: "Frame rate", caption: nil, unit: "fps", key: "fps", value: "\(model.config.fps)")
                RowDivider()
                NumberRow(title: "Longest clip", caption: "Longer clips are cut to this.", unit: "s", key: "maxSeconds", value: model.config.maxSeconds.formatted())
            }
            SectionLabel(text: "Browsing").padding(.top, 10)
            Card {
                Row(title: "Tiles always move", caption: "Otherwise a tile moves while the pointer is on it.") {
                    Toggle("", isOn: Binding(get: { model.config.animateAlways }, set: { model.setting("animateAlways", String($0)) }))
                        .toggleStyle(.switch).labelsHidden()
                }
            }
            SectionLabel(text: "Agents").padding(.top, 10)
            Card {
                AgentCommandRow()
            }
            SectionLabel(text: "Command line").padding(.top, 10)
            CommandLineCard()
            SectionLabel(text: "Startup").padding(.top, 10)
            Card {
                LoginRow()
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 24).padding(.top, 4)
        .frame(maxWidth: 640, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private var libraryFolder: String {
        (model.config.libraryDir.flatMap { $0.isEmpty ? nil : $0 } ?? model.paths.defaultLibrary.path)
            .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private var templatesCaption: String {
        let count = model.count(.templates)
        guard let last = model.lastSync else { return "Not refreshed yet. Refreshing reads memegen and Imgflip's popular list." }
        return "\(count) templates. Refreshed \(last.formatted(.relative(presentation: .named)))."
    }

    private func chooseFolder() {
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.canCreateDirectories = true
        open.prompt = "Use Folder"
        guard open.runModal() == .OK, let url = open.url else { return }
        model.moveLibrary(to: url)
    }
}

private struct NumberRow: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let caption: String?
    let unit: String
    let key: String
    let value: String
    @State private var text = ""

    var body: some View {
        Row(title: title, caption: caption) {
            HStack(spacing: 6) {
                TextField("", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15).monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 64)
                    .padding(.horizontal, 8).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                    .onSubmit { model.setting(key, text) }
                Text(unit).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 26, alignment: .leading)
            }
        }
        .onAppear { text = value }
        .onChange(of: value) { _, fresh in text = fresh }
    }
}

private struct LoginRow: View {
    @EnvironmentObject var model: AppModel
    @State private var on = SMAppService.mainApp.status == .enabled

    var body: some View {
        Row(title: "Open at login", caption: nil) {
            Toggle("", isOn: Binding(get: { on }, set: { want in
                do {
                    if want { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                } catch {
                    model.error = "macOS did not change the login item: \(error.localizedDescription)"
                }
                on = SMAppService.mainApp.status == .enabled
            }))
            .toggleStyle(.switch).labelsHidden()
        }
    }
}

private struct AgentCommandRow: View {
    @EnvironmentObject var model: AppModel
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask agent command").font(.system(size: 15))
            Text("Runs in a login shell when you press Ask agent. The prompt is in $MEME_PROMPT. Leave it empty to hide the button.")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("A shell command", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, design: .monospaced))
                .padding(.horizontal, 9).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
                .onSubmit { model.setting("agentCommand", text) }
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .onAppear { text = model.config.agentCommand }
        .onChange(of: model.config.agentCommand) { _, fresh in text = fresh }
    }
}

private struct CommandLineCard: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("commandFolder") private var folderPath = CommandLink.defaultFolder.path
    @State private var state = CommandLink.State.missing
    @State private var onPath: Bool?
    @State private var copied = false

    private var folder: URL { URL(fileURLWithPath: folderPath, isDirectory: true) }
    private var link: String { CommandLink.display(folder.appending(path: "meme")) }
    private var writable: Bool { CommandLink.canWrite(folder) }

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: state == .installed ? "checkmark.circle.fill" : "exclamationmark.circle")
                    .font(.system(size: 20)).foregroundStyle(state == .installed ? .primary : .secondary)
                    .frame(width: 22).padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 15))
                    Text(caption).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                switch state {
                case .installed:
                    Button("Remove") { act { try CommandLink.remove(in: folder) } }.buttonStyle(PillButtonStyle())
                case .missing, .elsewhere, .broken:
                    Button("Install") { act { try CommandLink.install(in: folder) } }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .disabled(!writable)
                case .file:
                    EmptyView()
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            RowDivider()
            Row(title: "Install in", caption: writable ? nil : "This folder needs an administrator. Copy the command and run it in a terminal.") {
                Menu {
                    ForEach(CommandLink.folders, id: \.self) { option in
                        Button(CommandLink.display(option)) { folderPath = option.path }
                    }
                    Divider()
                    Button("Choose Folder…", action: chooseFolder)
                } label: {
                    Text(CommandLink.display(folder))
                }
                .menuStyle(.button)
                .buttonStyle(PillButtonStyle())
                .fixedSize()
            }
            RowDivider()
            Row(title: "Terminal command", caption: "Installs it from a terminal instead.") {
                Button(copied ? "Copied" : "Copy Command") {
                    act { try Clipboard.copyText(CommandLink.command(in: folder)) }
                    copied = true
                    Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
                }
                .buttonStyle(PillButtonStyle())
            }
        }
        .task(id: folderPath) {
            state = CommandLink.state(in: folder)
            onPath = nil
            onPath = await CommandLink.onLoginPath(folder)
        }
    }

    private var title: String {
        switch state {
        case .installed: "The meme command is installed"
        case .missing: "The meme command is not installed"
        case .elsewhere: "The meme command runs another copy"
        case .broken: "The meme command is broken"
        case .file: "A file is in the way"
        }
    }

    private var caption: String {
        let dir = CommandLink.display(folder)
        switch state {
        case .installed where onPath == false:
            return "\(link) runs this app, but \(dir) is not on your shell's PATH, so terminals will not find it. Add it in your shell's startup file, or install in another folder."
        case .installed:
            return "\(link) runs this app, so agents can make memes with it."
        case .missing:
            return "Agents run meme to make memes for you. Install puts it at \(link)."
        case .elsewhere(let other):
            return "\(link) runs another copy, \(CommandLink.display(URL(fileURLWithPath: other))). Install points it at this app."
        case .file:
            return "\(link) is a file, not a link to this app. Move it aside, or install in another folder."
        case .broken:
            return "\(link) points to a copy of Meme Lab that is no longer there. Install points it at this app."
        }
    }

    private func act(_ work: () throws -> Void) {
        do { try work() } catch { model.error = "\(error)" }
        state = CommandLink.state(in: folder)
    }

    private func chooseFolder() {
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = false
        open.canCreateDirectories = true
        open.prompt = "Install Here"
        if open.runModal() == .OK, let url = open.url { folderPath = url.path }
    }
}

enum CommandLink {
    enum State: Equatable {
        case installed, missing, file, broken
        case elsewhere(String)
    }

    static var defaultFolder: URL { FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin") }
    static var target: URL? { Bundle.main.executableURL?.resolvingSymlinksInPath() }

    static var folders: [URL] {
        [defaultFolder] + ["/opt/homebrew/bin", "/usr/local/bin"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    static func display(_ url: URL) -> String {
        url.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    /// A folder that does not exist yet counts as writable when its nearest existing parent is.
    static func canWrite(_ folder: URL) -> Bool {
        var probe = folder
        while !FileManager.default.fileExists(atPath: probe.path), probe.path != "/" { probe.deleteLastPathComponent() }
        return FileManager.default.isWritableFile(atPath: probe.path)
    }

    static func state(in folder: URL) -> State {
        let path = folder.appending(path: "meme")
        guard let kind = try? FileManager.default.attributesOfItem(atPath: path.path)[.type] as? FileAttributeType else { return .missing }
        guard kind == .typeSymbolicLink else { return .file }
        guard FileManager.default.fileExists(atPath: path.path) else { return .broken }
        let resolved = path.resolvingSymlinksInPath()
        return resolved == target ? .installed : .elsewhere(resolved.path)
    }

    static func install(in folder: URL) throws {
        guard let target else { throw MemeError("Could not find this app's binary.") }
        let path = folder.appending(path: "meme")
        if state(in: folder) == .file { throw MemeError("\(display(path)) is a file, not a link. Move it aside, then try again.") }
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        if state(in: folder) != .missing { try fm.removeItem(at: path) }
        try fm.createSymbolicLink(at: path, withDestinationURL: target)
    }

    static func remove(in folder: URL) throws {
        guard state(in: folder) == .installed else { return }
        try FileManager.default.removeItem(at: folder.appending(path: "meme"))
    }

    static func command(in folder: URL) throws -> String {
        guard let target else { throw MemeError("Could not find this app's binary.") }
        // Double quotes, because the app's own name has an apostrophe in it.
        func quoted(_ path: String) -> String {
            "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "$", with: "\\$").replacingOccurrences(of: "`", with: "\\`") + "\""
        }
        let sudo = canWrite(folder) ? "" : "sudo "
        return "\(sudo)mkdir -p \(quoted(folder.path)) && \(sudo)ln -sf \(quoted(target.path)) \(quoted(folder.appending(path: "meme").path))"
    }

    /// Asks the user's login shell, since an app opened from Finder does not get the PATH a terminal gets. Nil when the shell does not answer in time.
    static func onLoginPath(_ folder: URL) async -> Bool? {
        await Task.detached {
            let shell = getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_shell) } ?? "/bin/zsh"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: shell)
            // printenv and ';' read the same in zsh, bash and fish.
            process.arguments = ["-l", "-i", "-c", "printenv MEME_LAB_MARK; printenv PATH"]
            process.environment = ProcessInfo.processInfo.environment.merging(["MEME_LAB_MARK": "MEMEPATH"]) { _, new in new }
            let output = Pipe()
            let received = Mutex(Data())
            // Read as it arrives: a shell's background helpers can hold the pipe open after the shell exits.
            output.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                received.withLock { $0.append(chunk) }
            }
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.standardInput = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            defer {
                output.fileHandleForReading.readabilityHandler = nil
                if process.isRunning { process.terminate() }
            }
            let deadline = Date().addingTimeInterval(5)
            var pollsSinceExit = 0
            while Date() < deadline {
                let lines = received.withLock { String(decoding: $0, as: UTF8.self) }.split(separator: "\n").map(String.init)
                if let mark = lines.lastIndex(of: "MEMEPATH"), mark + 1 < lines.count {
                    let paths = lines[mark + 1].split(separator: ":").map { URL(fileURLWithPath: String($0)).standardizedFileURL.path }
                    return paths.contains(folder.standardizedFileURL.path)
                }
                if !process.isRunning {
                    pollsSinceExit += 1
                    if pollsSinceExit > 4 { return nil }
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
            return nil
        }.value
    }
}
