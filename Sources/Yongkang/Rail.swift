import SwiftUI

/// What the window is showing. The rail picks one of these; the list column then holds that
/// section's objects and the work area holds whichever one is selected. Every screen is the
/// same four columns, so moving between sections never rearranges the window.
enum ConsoleSection: String, CaseIterable, Identifiable {
    case overview, board, agents, review, blocks

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .board: return "Board"
        case .agents: return "Agents"
        case .review: return "Review"
        case .blocks: return "Blocks"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .board: return "rectangle.split.3x1"
        case .agents: return "point.3.connected.trianglepath.dotted"
        case .review: return "chevron.left.forwardslash.chevron.right"
        case .blocks: return "tray.full"
        }
    }
}

/// The 64pt icon rail. It is the only navigation that never changes, which is what makes
/// the rest of the window safe to rearrange per section.
struct Rail: View {
    @Binding var section: ConsoleSection
    /// Counts that earn a dot: work waiting on the user, changes waiting to be read.
    let badges: [ConsoleSection: Color]
    let leave: () -> Void
    /// Whether the list column beside the rail is currently collapsed, and the toggle for it.
    var listHidden = false
    var toggleList: () -> Void = {}

    /// The tab under the pointer, which is the one wearing its name.
    @State private var hovered: ConsoleSection?

    /// `hovering` is only ever passed by the shot renderer, which has no pointer of its own
    /// and would otherwise photograph a rail whose labels never appear.
    init(section: Binding<ConsoleSection>, badges: [ConsoleSection: Color],
         leave: @escaping () -> Void, listHidden: Bool = false,
         toggleList: @escaping () -> Void = {}, hovering: ConsoleSection? = nil) {
        _section = section
        self.badges = badges
        self.leave = leave
        self.listHidden = listHidden
        self.toggleList = toggleList
        _hovered = State(initialValue: hovering)
    }

    var body: some View {
        VStack(spacing: 4) {
            Button(action: leave) {
                Text("YK")
                    .font(Typo.mono(12, .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0x141C28)))
                    .overlay(RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color(hex: 0x2B3B52), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("All projects (⌘[)")
            .padding(.bottom, 12)

            ForEach(ConsoleSection.allCases) { item in
                Button { section = item } label: { icon(item) }
                    .buttonStyle(.plain)
                    .help(item.title)
                    .onHover { inside in hovered = inside ? item : (hovered == item ? nil : hovered) }
                    .overlay(alignment: .leading) {
                        if hovered == item { flyout(item) }
                    }
            }
            Spacer(minLength: 8)
            Button(action: toggleList) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(listHidden ? Theme.tx3 : Theme.tx)
                    .frame(width: 40, height: 38)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("\\", modifiers: .command)
            .help(listHidden ? "Show list (⌘\\)" : "Hide list (⌘\\)")
        }
        .frame(width: Theme.railWidth)
        .padding(.vertical, 16)
        .background(Theme.rail)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
    }

    /// The tab's name, drawn beside it while the pointer is on it. The rail is icons only,
    /// so without this the only way to learn what one is is to click it — and `.help` waits
    /// out the system tooltip delay, which is longer than the guess it saves. It hangs past
    /// the rail's own width, which is why the rail is drawn above the list column.
    private func flyout(_ item: ConsoleSection) -> some View {
        Text(item.title)
            .font(Typo.text(11.5))
            .foregroundStyle(Theme.tx)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Theme.hairline, lineWidth: 1))
            .shadow(color: .black.opacity(0.45), radius: 10, y: 2)
            // Its own width, then pushed clear of the rail from the tab's leading edge —
            // pinning the far edge instead would slide a long name back over the icons.
            .fixedSize()
            .offset(x: Theme.railWidth + 2)
            .allowsHitTesting(false)
    }

    private func icon(_ item: ConsoleSection) -> some View {
        let on = section == item
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2)
                .fill(on ? Theme.accent : .clear)
                .frame(width: 2, height: 18)
                .offset(x: -1)
            Image(systemName: item.systemImage)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(on ? Theme.tx : Theme.tx3)
                .frame(width: 40, height: 38)
                .background(RoundedRectangle(cornerRadius: 9).fill(on ? Color(hex: 0x161C26) : .clear))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(on ? Theme.hairline : .clear, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if let tint = badges[item] {
                        Circle().fill(tint).frame(width: 6, height: 6).offset(x: -4, y: 6)
                    }
                }
                .padding(.leading, 9)
        }
        .frame(width: Theme.railWidth - 12, alignment: .leading)
    }
}

/// The header strip above the work area: where you are on the left, what you can do here
/// on the right.
struct TopBar<Trailing: View>: View {
    let crumbs: [String]
    let title: String
    var pill: AnyView? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        // Where you are gives way before what you can do: a long task title truncates and
        // the crumbs before it drop out entirely rather than pushing the actions off the
        // right edge of a narrow window.
        HStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { path }
                HStack(spacing: 10) { path.lineLimit(1).truncationMode(.tail) }
                Text(title).font(Typo.display(14)).lineLimit(1).truncationMode(.tail)
            }
            if let pill { pill }
            Spacer(minLength: 12)
            trailing.layoutPriority(1)
        }
        .padding(.horizontal, 20)
        .frame(height: Theme.topBarHeight)
        .background(Theme.bg)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    @ViewBuilder private var path: some View {
        ForEach(Array(crumbs.enumerated()), id: \.offset) { _, crumb in
            Text(crumb).font(Typo.mono(11)).foregroundStyle(Theme.tx3)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.tx4)
        }
        Text(title).font(Typo.display(14))
    }
}

/// The bar along the bottom of a screen that has one thing to do: the file path on the
/// left so you always know what you are looking at, the action on the right.
struct ActionBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) { content }
            .padding(.horizontal, 24)
            .frame(height: Theme.actionBarHeight)
            .background(Theme.panel)
            .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}

/// The column of whatever the current section is a list of. Its width is dragged by the
/// user — file paths and entry titles are as long as the project makes them.
struct ListPane<Content: View>: View {
    var width: CGFloat = Theme.listWidth
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(width: width)
            .background(Theme.panel)
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
    }
}

/// The right-hand column: what you would otherwise have to go and find.
struct Inspector<Content: View>: View {
    var width: CGFloat = Theme.inspectorWidth
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) { content }
            .padding(18)
            .frame(width: width, alignment: .topLeading)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.panel)
            .overlay(alignment: .leading) { Rectangle().fill(Theme.line).frame(width: 1) }
    }
}
