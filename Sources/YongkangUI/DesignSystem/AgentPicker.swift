import AppKit
import SwiftUI
import YongkangCore

/// Which CLI a session runs, sized for however many are integrated: a button naming the current
/// one, opening a list you can type into. The CLIs found on this Mac come first and the rest fold
/// under one row, so a dozen integrations are as many rows as the user has installed.
///
/// It replaced a segmented control, which held four names in 320 pt and had nowhere to put a
/// fifth.
struct AgentPicker: View {
    @Binding var agent: AgentKind
    /// `AppModel.foundAgents`: nil until the first look is back, and nothing folds away before.
    let found: Set<AgentKind>?
    /// Asked each time the list opens, so a CLI installed a minute ago is not folded away.
    let lookUp: () -> Void
    /// What the choice is for, for a reader that cannot see where the button sits.
    let purpose: String

    @State private var open = false

    var body: some View {
        Button {
            lookUp()
            open = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: agent.systemImage).font(.system(size: 11)).foregroundStyle(Theme.tx2)
                Text(agent.displayName)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Theme.tx3)
            }
        }
        .buttonStyle(.console)
        .accessibilityLabel(purpose)
        .accessibilityValue(agent.displayName)
        .help(purpose)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            AgentList(agent: $agent, found: found) { open = false }
        }
    }

    /// The rows for what has been typed: the CLIs found on this Mac, then the ones that are not.
    /// A name or an executable matches.
    nonisolated static func rows(
        _ query: String, found: Set<AgentKind>?
    ) -> (installed: [AgentKind], missing: [AgentKind]) {
        let typed = query.trimmingCharacters(in: .whitespaces)
        let matching = AgentKind.allCases.filter {
            typed.isEmpty || $0.displayName.localizedCaseInsensitiveContains(typed)
                || $0.rawValue.localizedCaseInsensitiveContains(typed)
        }
        return (matching.filter { found?.contains($0) ?? true }, matching.filter { found?.contains($0) == false })
    }
}

/// The popover. ↑↓ walk the CLIs that can be picked, Return takes the one highlighted, Esc is
/// the popover's own. `package` only so the shots can draw it open.
package struct AgentList: View {
    @Binding var agent: AgentKind
    let found: Set<AgentKind>?
    let close: () -> Void

    package init(agent: Binding<AgentKind>, found: Set<AgentKind>?, close: @escaping () -> Void) {
        _agent = agent
        self.found = found
        self.close = close
    }

    @State private var query = ""
    @State private var showMissing = false
    @State private var highlighted: AgentKind?
    /// Live only while the list is open. See `PromptField.claimTab()` for why a monitor.
    @State private var keyWatch: Any?
    @FocusState private var focused: Bool

    private var rows: (installed: [AgentKind], missing: [AgentKind]) { AgentPicker.rows(query, found: found) }

    package var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            filterField
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(found == nil ? "Agents" : "On this Mac")
                    .padding(.horizontal, 10).padding(.bottom, 2)
                if rows.installed.isEmpty {
                    Text("None here matches.").font(Typography.body).foregroundStyle(Theme.tx3)
                        .padding(.horizontal, 10).frame(height: 30)
                }
                ForEach(rows.installed) { row($0, pickable: true) }
            }
            if !rows.missing.isEmpty { missing(rows.missing) }
            Text("type to filter · ↑↓ picks · Return takes it")
                .font(Typography.mono).foregroundStyle(Theme.tx4).padding(.horizontal, 2)
        }
        .padding(10)
        .frame(width: 300)
        .background(Theme.panel)
        .task {
            highlighted = agent
            focused = true
        }
        .onAppear(perform: claimKeys)
        .onDisappear(perform: releaseKeys)
        // The monitor holds the rows it was armed with; a look that lands while the list is
        // open must not leave Return able to take a CLI it has just found missing.
        .onChange(of: found) {
            releaseKeys()
            claimKeys()
        }
        .onChange(of: query) { highlighted = rows.installed.first }
    }

    private var filterField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.tx3)
            TextField("Filter agents", text: $query).textFieldStyle(.plain).font(Typography.body)
                .focused($focused)
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
        .overlay(
            RoundedRectangle(cornerRadius: 8).strokeBorder(focused ? Theme.accent : Theme.controlLine, lineWidth: 1))
    }

    private func missing(_ kinds: [AgentKind]) -> some View {
        // A name you typed is never kept behind a closed fold.
        let expanded = showMissing || !query.isEmpty
        return VStack(alignment: .leading, spacing: 2) {
            Button {
                showMissing.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).frame(width: 16)
                    Text("Not found on this Mac").font(Typography.body)
                    Spacer(minLength: 8)
                    Text("\(kinds.count)").font(Typography.mono)
                }
                .foregroundStyle(Theme.tx3)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!query.isEmpty)
            if expanded { ForEach(kinds) { row($0, pickable: false) } }
        }
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    /// A CLI the login shell cannot find is listed but not pickable: a session on it would open
    /// a terminal that says `command not found` and nothing else.
    private func row(_ kind: AgentKind, pickable: Bool) -> some View {
        let current = kind == agent
        return Button {
            pick(kind)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: kind.systemImage).font(.system(size: 12))
                    .foregroundStyle(current ? Theme.accent : pickable ? Theme.tx2 : Theme.tx4)
                    .frame(width: 16)
                Text(kind.displayName).font(Typography.body(.medium))
                    .foregroundStyle(pickable ? Theme.tx : Theme.tx3)
                Spacer(minLength: 8)
                Text(kind.rawValue).font(Typography.mono).foregroundStyle(pickable ? Theme.tx3 : Theme.tx4)
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.accent).opacity(current ? 1 : 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .rowSelection(pickable && kind == highlighted)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!pickable)
        .onHover { if $0 && pickable { highlighted = kind } }
        .help(pickable ? "" : "\(kind.rawValue) is not on your login shell's PATH")
        .accessibilityAddTraits(current ? .isSelected : [])
    }

    private func pick(_ kind: AgentKind) {
        agent = kind
        close()
    }

    private func claimKeys() {
        guard keyWatch == nil else { return }
        keyWatch = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let pickable = rows.installed
            switch event.keyCode {
            case 125: step(1, in: pickable)
            case 126: step(-1, in: pickable)
            case 36, 76:
                guard let highlighted, pickable.contains(highlighted) else { return nil }
                pick(highlighted)
            default: return event
            }
            return nil
        }
    }

    private func step(_ offset: Int, in pickable: [AgentKind]) {
        guard !pickable.isEmpty else { return }
        let at = highlighted.flatMap(pickable.firstIndex(of:)) ?? (offset > 0 ? -1 : pickable.count)
        highlighted = pickable[min(max(at + offset, 0), pickable.count - 1)]
    }

    private func releaseKeys() {
        if let keyWatch { NSEvent.removeMonitor(keyWatch) }
        keyWatch = nil
    }
}

/// A session on any CLI but the default, for the toolbar's New menu and the menu bar's Agent
/// menu. Starting one here leaves the default alone, and a CLI the shell cannot find is
/// disabled, never hidden.
struct OtherAgentMenu: View {
    let title: String
    let agent: AgentKind
    let found: Set<AgentKind>?
    let start: (AgentKind) -> Void

    var body: some View {
        Menu(title) {
            ForEach(AgentKind.allCases.filter { $0 != agent }) { other in
                Button(other.displayName, systemImage: other.systemImage) { start(other) }
                    .disabled(found?.contains(other) == false)
            }
        }
    }
}
