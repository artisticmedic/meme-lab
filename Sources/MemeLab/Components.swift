import AppKit
import MemeCore
import SwiftUI

/// Surfaces for the window, the same in both appearances as No Orange Dot's.
enum Surface {
    private static func pair(_ light: NSColor, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light })
    }
    private static func hex(_ v: Int, _ a: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
    }
    static let page = pair(hex(0xF4F4F5), hex(0x242527))
    static let card = pair(hex(0xFFFFFF), hex(0x2D2F32))
    static let border = pair(hex(0x000000, 0.09), hex(0x3A3C40))
}

/// Every button with words on it. `prominent` inverts it: label-colour fill, background-colour text.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var selected = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let filled = prominent || selected
        return configuration.label
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(filled ? Color(nsColor: .windowBackgroundColor) : Color.primary)
            .padding(.horizontal, 11).frame(minHeight: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(filled ? Color.primary.opacity(configuration.isPressed ? 0.75 : 0.9) : Color.primary.opacity(configuration.isPressed ? 0.16 : 0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .opacity(enabled ? 1 : 0.4)
    }
}

/// A symbol-only button with a 34 pt target.
struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .medium)).frame(width: 34, height: 34).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct SearchField: View {
    @Binding var text: String
    var prompt = "Search by name or feeling"
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused(focus)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

struct InputField: View {
    let prompt: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding?

    var body: some View {
        let field = TextField(prompt, text: $text).textFieldStyle(.plain).font(.system(size: 13))
        Group {
            if let focus { field.focused(focus) } else { field }
        }
        .padding(.horizontal, 9).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Surface.card))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Surface.border, lineWidth: 1))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 6)
    }
}

struct Row<Trailing: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15))
                if let caption { Text(caption).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }
}

struct RowDivider: View {
    var body: some View { Divider().padding(.leading, 14) }
}

/// A word in a pill, with an optional remove button: tags, collections and picks.
struct Chip: View {
    let text: String
    var remove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(text).font(.system(size: 12)).lineLimit(1)
            if let remove {
                Button(action: remove) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Remove \(text)")
            }
        }
        .padding(.horizontal, 8).frame(height: 24)
        .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}

/// Lays children out in rows, wrapping when a row is full.
struct FlowLayout: SwiftUI.Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += row + spacing; row = 0 }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            row = max(row, size.height)
        }
        return CGSize(width: min(widest, width), height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}

/// The system sidebar material, so the window's left column picks up the desktop behind it.
struct SidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// One tile in a grid: the moving picture, its title, and whether it is picked, selected or numbered.
struct Tile: View {
    @EnvironmentObject var model: AppModel
    let item: Item
    var number: Int?
    var picked = false
    var selected = false
    var height: CGFloat = 100
    var caption: String?
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            MediaPreview(item: item, playing: hovering || model.config.animateAlways)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if let number {
                        Text("\(number)").font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.primary.opacity(0.85)))
                            .padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if picked {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.primary.opacity(0.9)))
                            .padding(6)
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(picked || selected ? 0.85 : 0), lineWidth: 2)
                }
            Text(caption ?? item.title).font(.system(size: 12)).lineLimit(caption == nil ? 1 : 2)
                .foregroundStyle(caption == nil ? .primary : .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(4)
        .background {
            if selected { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.09)) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onDrag { model.dragProvider(item) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([number.map { "Option \($0)" }, item.title, caption, picked ? "picked" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
    }
}

extension AppModel {
    /// The file itself, so dropping a tile into Discord or Finder uploads or copies it.
    func dragProvider(_ item: Item) -> NSItemProvider {
        guard let file = localFile(item) else { return NSItemProvider() }
        return NSItemProvider(contentsOf: file) ?? NSItemProvider()
    }

    func recipe(_ item: Item) -> String? {
        guard let made = item.made else { return nil }
        let layouts = ["single": "One picture", "side": "Side by side", "stack": "Stacked", "sequence": "One after another"]
        let styles = ["classic": "classic captions", "bar": "caption bar", "subtitle": "subtitle", "template": "template boxes"]
        return "\(layouts[made.layout] ?? made.layout), \(styles[made.style] ?? made.style)"
    }
}
