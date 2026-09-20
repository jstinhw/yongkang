import SwiftUI

/// What the window is showing. The rail picks one of these; the list column then holds that
/// section's objects and the work area holds whichever one is selected. Every screen is the
/// same four columns, so moving between sections never rearranges the window.
package enum ConsoleSection: String, CaseIterable, Identifiable {
    case board, agents

    package var id: Self { self }

    package var title: String {
        switch self {
        case .board: return "Board"
        case .agents: return "Agents"
        }
    }

    var systemImage: String {
        switch self {
        case .board: return "rectangle.split.3x1"
        case .agents: return "point.3.connected.trianglepath.dotted"
        }
    }
}

/// The 64pt icon rail. It is the only navigation that never changes, which is what makes
/// the rest of the window safe to rearrange per section. It holds sections only: the way back
/// to every project is Go → All Projects (⌘[), not a mark at its top.
package struct Rail: View {
    @Binding var section: ConsoleSection
    /// The tabs that earn a dot, and its colour: what is waiting on the user.
    let badges: [ConsoleSection: Color]
    var agentCount = 0

    /// The tab under the pointer, which is the one wearing its name.
    @State private var hovered: ConsoleSection?

    /// `hovering` is only ever passed by the shot renderer, which has no pointer of its own
    /// and would otherwise photograph a rail whose labels never appear.
    package init(
        section: Binding<ConsoleSection>, badges: [ConsoleSection: Color],
        agentCount: Int = 0, hovering: ConsoleSection? = nil
    ) {
        _section = section
        self.badges = badges
        self.agentCount = agentCount
        _hovered = State(initialValue: hovering)
    }

    package var body: some View {
        VStack(spacing: 4) {
            ForEach(ConsoleSection.allCases) { item in
                Button {
                    section = item
                } label: {
                    icon(item)
                }
                .buttonStyle(.plain)
                .help(item == .agents ? "Agents · \(agentCount) online" : item.title)
                .accessibilityLabel(item == .agents ? "Agents, \(agentCount) online" : item.title)
                .onHover { inside in hovered = inside ? item : (hovered == item ? nil : hovered) }
                .overlay(alignment: .leading) {
                    if hovered == item { flyout(item) }
                }
            }
            // No list toggle down here any more: it lives in the window's toolbar, where the
            // system puts a sidebar's switch, and it still answers to ⌘\.
            Spacer(minLength: 8)
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
            .font(Typography.body)
            .foregroundStyle(Theme.tx)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
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
                .background(RoundedRectangle(cornerRadius: 9).fill(on ? Theme.railActive : .clear))
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(on ? Theme.hairline : .clear, lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if item == .agents {
                        Text("\(agentCount)").font(Typography.monoCaption(.semibold))
                            .foregroundStyle(Theme.tx)
                            .padding(.horizontal, 4)
                            .background(Capsule().fill(Theme.panel))
                            .offset(x: 2, y: 1)
                    }
                }
                // Its own corner, because Agents wears the online count in the other one and
                // is also the tab everything waiting on you now hangs from.
                .overlay(alignment: .bottomTrailing) {
                    if let tint = badges[item] {
                        Circle().fill(tint).frame(width: 6, height: 6).offset(x: -4, y: -6)
                    }
                }
                .padding(.leading, 9)
        }
        .frame(width: Theme.railWidth - 12, alignment: .leading)
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

/// The column of whatever the current section is a list of. It fills the split view's first
/// pane, which owns its width and draws the divider that resizes it — file paths and entry
/// titles are as long as the project makes them, so the user drags it.
struct ListPane<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.panel)
    }
}

/// The right-hand column: what you would otherwise have to go and find.
///
/// ponytail: still hand-built. 5.2 moved the top bar to the window's toolbar; `.inspector()` is
/// held because on macOS 26 it renders into an `NSContainerConcentricGlassEffectView` that the
/// window server composites, and the shot renderer photographs one as a white rectangle —
/// every screen with an inspector would lose that pane from its shot, and with it the only way
/// this repo checks a layout. Move it when the shots can see one, or when the screens are
/// checked some other way.
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
