import SwiftUI
import YongkangCore

/// Beside a session clearing a gate: the page its step needs, or — while the block names a
/// command only the user can run — that command and everything it runs.
///
/// The command wins while `run:` is set, because it is the step in hand; the page stays a click
/// away. Both stay alive under the switch, so going to read the command does not reload a page
/// someone is halfway through signing in on.
package struct GuidePane: View {
    let block: UserBlock
    /// The project folder: where the session the command is typed into runs.
    let directory: URL
    /// Types the approved command into that session.
    let run: (String) -> Void

    @State private var showingPage = false

    package init(block: UserBlock, directory: URL, run: @escaping (String) -> Void) {
        self.block = block
        self.directory = directory
        self.run = run
    }

    package var body: some View {
        VStack(spacing: 0) {
            if hasCommand, block.link != nil {
                tabs
                Divider().overlay(Theme.line)
            }
            ZStack {
                if let link = block.link {
                    GuideBrowser(url: link).opacity(pageOnTop ? 1 : 0).allowsHitTesting(pageOnTop)
                }
                if hasCommand {
                    CommandPane(line: block.run, directory: directory, run: run)
                        .opacity(pageOnTop ? 0 : 1).allowsHitTesting(!pageOnTop)
                }
            }
        }
        .background(Theme.panel)
        // A new command is the new step: it comes to the front even if the page was.
        .onChange(of: block.run) { showingPage = false }
    }

    private var hasCommand: Bool { !block.run.isEmpty }
    private var pageOnTop: Bool { !hasCommand || showingPage }

    private var tabs: some View {
        HStack(spacing: 0) {
            tab("Command", selected: !showingPage, waiting: true) { showingPage = false }
            tab("Page", selected: showingPage, waiting: false) { showingPage = true }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.well))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.wellLine, lineWidth: 1))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func tab(_ label: String, selected: Bool, waiting: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                // The command is what is waiting on the user, whichever tab is up.
                if waiting { Circle().fill(Theme.amber).frame(width: 6, height: 6) }
                Text(label)
            }
            .font(Typography.caption(selected ? .semibold : .regular))
            .foregroundStyle(selected ? Theme.tx : Theme.tx3)
            .padding(.horizontal, 10).frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(selected ? Theme.raised : .clear))
            .overlay(
                RoundedRectangle(cornerRadius: 5).strokeBorder(selected ? Theme.controlLine : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
