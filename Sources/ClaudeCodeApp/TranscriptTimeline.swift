import SwiftUI

/// An agent's work, read off its transcript and laid out the way Claude Code's own view
/// lays it out: the brief, what the agent has said back, and everything in between
/// collapsed to one line per run of tool work — "Searched for 1 pattern, read 14 files,
/// ran 8 shell commands". Printing every call and every result buries the two things
/// worth reading. A run opens when you click it, so nothing is lost; it is just not all
/// shouted at once.
///
/// Shared by every agent the console can watch: a dispatched subagent and the lead that
/// dispatched it are the same kind of file and read the same way.
struct TranscriptTimeline: View {
    let lines: [TranscriptLine]

    /// Runs of tool work the reader has opened, by position — position rather than identity
    /// because the transcript is re-parsed every two seconds while the agent works.
    @State private var opened: Set<Int> = []

    private var steps: [TranscriptStep] { TranscriptSteps.steps(lines) }

    var body: some View {
        if lines.isEmpty {
            empty
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(steps) { item in
                            step(item, last: item.id == steps.count - 1).id(item.id)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                }
                .onAppear { scrollToEnd(proxy) }
                .onChange(of: lines.count) { _ in scrollToEnd(proxy) }
            }
        }
    }

    // MARK: - One step

    @ViewBuilder private func step(_ item: TranscriptStep, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            spine(item, last: last)
            switch item.kind {
            case .task, .say:
                VStack(alignment: .leading, spacing: 6) {
                    // Only the brief is labelled. What the agent says needs no heading —
                    // it is the one thing on the screen written for a person to read.
                    if item.kind == .task {
                        Text("TASK").font(Typo.section).tracking(1.4)
                            .foregroundStyle(tint(item.kind))
                    }
                    Text(item.text)
                        .font(Typo.text(12.5))
                        .foregroundStyle(Color(hex: 0xC7D0DC))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface(radius: 11, padding: 13)
            case .skill:
                HStack(spacing: 8) {
                    Text(item.text).font(Typo.mono(11.5)).foregroundStyle(Theme.tx)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7)
            case .note:
                Text(item.text)
                    .font(Typo.text(11.5))
                    .foregroundStyle(Theme.tx2)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 7)
                    .textSelection(.enabled)
            case .work:
                work(item)
            }
        }
        .padding(.bottom, item.kind == .task || item.kind == .say ? 12 : 6)
    }

    /// The collapsed run: one line of what happened, and the calls themselves only if you
    /// ask for them.
    @ViewBuilder private func work(_ item: TranscriptStep) -> some View {
        let isOpen = opened.contains(item.id)
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if isOpen { opened.remove(item.id) } else { opened.insert(item.id) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.tx4)
                    Text(item.text).font(Typo.text(12)).foregroundStyle(Theme.tx3)
                    if item.errors > 0 {
                        NotebookStyle.pill("\(item.errors) failed", Theme.amber)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isOpen {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(item.detail) { line in call(line) }
                }
                .padding(.bottom, 6)
            }
        }
    }

    private func call(_ line: TranscriptLine) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if line.label == "Tool" {
                // `Read(file_path: …)` — the name carries, the arguments trail off.
                let split = line.text.firstIndex(of: "(")
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(split.map { String(line.text[..<$0]) } ?? line.text)
                        .foregroundStyle(Theme.accent)
                    Text(split.map { String(line.text[$0...]) } ?? "")
                        .foregroundStyle(Theme.tx2)
                }
                .font(Typo.mono(11))
                .textSelection(.enabled)
            } else {
                Text(line.text)
                    .font(Typo.mono(10.5))
                    .foregroundStyle(line.isError ? Color(hex: 0xF1BDBD) : Theme.tx2)
                    .lineSpacing(2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x0E1116)))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(line.isError ? Theme.red.opacity(0.25)
                                                   : Color(hex: 0x1E242F), lineWidth: 1))
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func spine(_ item: TranscriptStep, last: Bool) -> some View {
        ZStack(alignment: .top) {
            if !last {
                Rectangle().fill(Theme.line).frame(width: 1).padding(.top, 22)
            }
            switch item.kind {
            case .task, .say:
                Image(systemName: item.kind == .task ? "arrow.down.right.circle" : "bubble.left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(tint(item.kind))
                    .frame(width: 23, height: 23)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x12161E)))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(hex: 0x242B37), lineWidth: 1))
            default:
                Circle().fill(tint(item.kind))
                    .frame(width: 6, height: 6)
                    .frame(width: 23, height: 23)
            }
        }
        .frame(width: 23)
    }

    private func tint(_ kind: TranscriptStep.Kind) -> Color {
        switch kind {
        case .task: return Theme.violet
        case .say: return Theme.green
        case .skill: return Theme.accent
        case .note: return Theme.amber
        case .work: return Theme.tx4
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "hourglass").font(.system(size: 22)).foregroundStyle(Theme.tx4)
            Text("Nothing recorded yet.").font(Typo.text(13)).foregroundStyle(Theme.tx3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The rows carry step positions, so the scroll target is the last step — handing this
    /// a `TranscriptLine` id matches no row and scrolls nowhere.
    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard !lines.isEmpty else { return }
        proxy.scrollTo(steps.count - 1, anchor: .bottom)
    }
}
