import SwiftUI
import YongkangCore

/// One of the setup card's three steps, as `NotebookSetupCard` works it out.
struct SetupStep {
    enum State { case done, active, waiting, pending, stopped }

    /// What sits under the step's title besides its line of detail.
    enum Content {
        case none
        /// What the agent last did, nil until its transcript says.
        case live(AgentActivity?)
        /// The plan draft to open, by its title.
        case plan(String)
        /// The notebook's entries by kind so far, and what it last did.
        case counts([(String, Int)], AgentActivity?)
    }

    let title: String
    /// The step is the user's, not the agent's.
    var you = false
    let state: State
    var meta: String? = nil
    var detail: String? = nil
    var content: Content = .none
    var review: (() -> Void)? = nil
}

/// A step: its glyph on a rail joining it to the next, then its title, detail and content.
struct SetupStepRow: View {
    let step: SetupStep
    let last: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 4) {
                glyph.frame(width: 20, height: 20)
                if !last {
                    Rectangle().fill(Theme.stepLine).frame(width: 1.5).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(step.title).font(Typography.body(.semibold)).foregroundStyle(titleColor)
                    if step.you {
                        Text("YOU").font(Typography.monoCaption(.semibold)).tracking(0.6)
                            .foregroundStyle(Theme.amber)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.amber.opacity(0.35), lineWidth: 1))
                    }
                    Spacer(minLength: 8)
                    if let meta = step.meta {
                        Text(meta).font(Typography.mono).foregroundStyle(Theme.tx3)
                    }
                }
                .frame(minHeight: 20)
                if let detail = step.detail {
                    Text(detail).font(Typography.body).foregroundStyle(Theme.tx2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content
            }
            .padding(.bottom, 20)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var titleColor: Color {
        switch step.state {
        case .active, .waiting: return Theme.tx
        case .done: return Theme.tx2
        case .stopped: return Theme.prose
        case .pending: return Theme.tx3
        }
    }

    @ViewBuilder private var glyph: some View {
        switch step.state {
        case .done:
            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.green)
                .frame(width: 20, height: 20).background(Circle().fill(Theme.green.opacity(0.15)))
        case .active:
            ProgressView().controlSize(.small)
        case .waiting:
            Circle().strokeBorder(Theme.amber, lineWidth: 2)
                .overlay(Circle().fill(Theme.amber).frame(width: 8, height: 8))
        case .pending:
            Circle().strokeBorder(Theme.tx4, lineWidth: 1.5)
        case .stopped:
            Circle().strokeBorder(Theme.tx3, lineWidth: 1.5)
                .overlay(Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.tx2))
        }
    }

    @ViewBuilder private var content: some View {
        switch step.content {
        case .none:
            EmptyView()
        case .live(let activity):
            if let activity, let verb = activity.verb { Self.liveLine(verb, activity.target) }
        case .plan(let title):
            plan(title)
        case .counts(let counts, let activity):
            HStack(spacing: 8) {
                ForEach(counts, id: \.0) { label, count in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(count)").font(Typography.headline).foregroundStyle(Theme.tx)
                        Text(label).font(Typography.caption).foregroundStyle(Theme.tx2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cardSurface(radius: 9, padding: 10, border: Theme.nestedLine, fill: Theme.nested)
                }
            }
            if let activity, let verb = activity.verb { Self.liveLine(verb, activity.target) }
        }
    }

    private func plan(_ title: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text").foregroundStyle(Theme.tx2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typography.body(.semibold)).foregroundStyle(Theme.tx)
                Text("What you will have, what waits on you, and the task graph")
                    .font(Typography.caption).foregroundStyle(Theme.tx2)
            }
            Spacer(minLength: 8)
            if let review = step.review {
                Button("Review plan", action: review).buttonStyle(.consolePrimary)
            }
        }
        .cardSurface(radius: 10, padding: 12, border: Theme.nestedLine, fill: Theme.nested)
    }

    /// "Read  Sources/App.swift", in the transcript's own type.
    static func liveLine(_ verb: String, _ target: String?) -> some View {
        HStack(spacing: 8) {
            Text(verb).foregroundStyle(Theme.accent)
            if let target {
                Text(target).foregroundStyle(Theme.prose).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .font(Typography.code)
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.well))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.wellLine, lineWidth: 1))
    }
}
