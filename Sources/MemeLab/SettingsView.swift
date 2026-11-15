import AppKit
import MemeCore
import ServiceManagement
import SwiftUI

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
            SectionLabel(text: "Panel").padding(.top, 10)
            Card {
                LoginRow()
                RowDivider()
                Row(title: "Tiles always move", caption: "Otherwise a tile moves while the pointer is on it.") {
                    Toggle("", isOn: Binding(get: { model.config.animateAlways }, set: { model.setting("animateAlways", String($0)) }))
                        .toggleStyle(.switch).labelsHidden()
                }
                RowDivider()
                AgentCommandRow()
            }
            SectionLabel(text: "Command line").padding(.top, 10)
            Card {
                CommandLinkRow()
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

private struct CommandLinkRow: View {
    @EnvironmentObject var model: AppModel
    @State private var linked = CommandLink.isLinked

    var body: some View {
        Row(title: "meme command", caption: linked ? "~/.local/bin/meme runs this app." : "Links ~/.local/bin/meme to this app, so agents can run it.") {
            if !linked {
                Button("Link") {
                    do { try CommandLink.link() } catch { model.error = "\(error)" }
                    linked = CommandLink.isLinked
                }
                .buttonStyle(PillButtonStyle())
            }
        }
    }
}

enum CommandLink {
    static var path: URL { FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/bin/meme") }
    static var target: URL? { Bundle.main.executableURL?.resolvingSymlinksInPath() }

    static var isLinked: Bool {
        guard let target else { return false }
        return path.resolvingSymlinksInPath() == target
    }

    static func link() throws {
        guard let target else { throw MemeError("Could not find this app's binary.") }
        let fm = FileManager.default
        try fm.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let kind = try? fm.attributesOfItem(atPath: path.path)[.type] as? FileAttributeType {
            guard kind == .typeSymbolicLink else {
                throw MemeError("~/.local/bin/meme is a file, not a link. Move it aside, then try again.")
            }
            try fm.removeItem(at: path)
        }
        try fm.createSymbolicLink(at: path, withDestinationURL: target)
    }
}
