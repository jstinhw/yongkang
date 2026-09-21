import SwiftUI
import YongkangCore

/// Any agent session read the way its subagents are read: off its own transcript, as
/// steps. A session is an agent before it is anything else — assigned work, the product
/// voice, a walk through a block — and what it has actually said and done
/// is the answer to "what is it doing". The terminal shows the same work as a wall of
/// ANSI that scrolls away, and is the other pane of `AgentPage`, which draws the header and the
/// column beside both.
package struct SessionTranscript: View {
    let session: CodeSession
    let lines: [TranscriptLine]
    /// Typed into the session's own process, the same pipe a change request is
    /// typed into — so answering an agent does not mean leaving the transcript for its terminal.
    let send: (String) -> Void

    @State private var reply = ""

    package init(session: CodeSession, lines: [TranscriptLine], send: @escaping (String) -> Void) {
        self.session = session
        self.lines = lines
        self.send = send
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TranscriptTimeline(lines: lines)
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
    }

    /// One line to type back at the agent. Enter sends; a dead session has nothing to
    /// send to, so it says that instead.
    @ViewBuilder private var composer: some View {
        HStack(spacing: 9) {
            TextField(
                session.exited ? "Session has exited" : "Reply to \(session.title)…",
                text: $reply
            )
            .textFieldStyle(.plain)
            .font(Typography.body)
            .foregroundStyle(Theme.tx)
            .onSubmit(dispatch)
            .disabled(session.exited)
            Button(action: dispatch) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 17))
                    .foregroundStyle(canSend ? Theme.accent : Theme.tx4)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 11).fill(Theme.well))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.wellLine, lineWidth: 1))
        .padding(.horizontal, 22)
        .padding(.bottom, 16)
    }

    private var canSend: Bool {
        !session.exited && !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func dispatch() {
        guard canSend else { return }
        send(reply.trimmingCharacters(in: .whitespacesAndNewlines))
        reply = ""
    }
}
