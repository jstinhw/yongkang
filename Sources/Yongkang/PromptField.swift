import AppKit
import SwiftUI

/// `@`-tagging for the prompt boxes. Type `@` and the folder is offered, so a prompt can
/// point an agent at files and folders it has not been told about yet.
enum Mention {
    /// The `@token` being typed, or nil when the caret is not in one.
    ///
    /// ponytail: the trailing token only — SwiftUI's TextField does not expose its caret,
    /// and a tag is typed at the end of what you have written so far in every case that
    /// matters. Revisit if editing a tag mid-sentence starts mattering.
    static func query(in text: String) -> String? {
        guard let at = text.lastIndex(of: "@") else { return nil }
        let before = text[..<at].last
        guard before == nil || before == " " || before == "\n" else { return nil }
        let token = text[text.index(after: at)...]
        guard !token.contains(where: { $0 == " " || $0 == "\n" }) else { return nil }
        return String(token)
    }

    /// Which folder a half-typed tag is inside, and the text that stands for that folder
    /// once something in it is picked.
    ///
    /// Under `root` first: `@/De` is Desktop in the folder you are tagging from, not
    /// `/dev` on the disk, and the leading slash is dropped so what completes is a path
    /// that is really there. A tag `root` has no such folder for is a path of its own —
    /// which is how an already absolute tag, the kind this box writes for a project that
    /// does not exist yet, keeps drilling down instead of being re-rooted into nothing.
    static func lookup(_ query: String, root: URL) -> (folder: URL, prefix: String, base: String) {
        let slash = query.lastIndex(of: "/")
        let typed = slash.map { String(query[..<query.index(after: $0)]) } ?? ""
        let prefix = slash.map { String(query[query.index(after: $0)...]) } ?? query
        let under = String(typed.drop(while: { $0 == "/" }))
        let candidate = under.isEmpty ? root : root.appendingPathComponent(under)
        if isFolder(candidate) { return (candidate, prefix, under) }
        return (URL(fileURLWithPath: (typed as NSString).expandingTildeInPath), prefix, typed)
    }

    /// What is inside that folder matching what has been typed of the name. Folders keep
    /// their trailing slash, so tagging one and pressing Tab again walks into it. Dotfiles
    /// stay hidden.
    static func matches(_ query: String, root: URL) -> [String] {
        let (folder, typed, base) = lookup(query, root: root)
        let prefix = typed.lowercased()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return
            names
            .filter { !$0.hasPrefix(".") && $0.lowercased().hasPrefix(prefix) }
            .sorted { $0.lowercased() < $1.lowercased() }
            .map { base + $0 + (isFolder(folder.appendingPathComponent($0)) ? "/" : "") }
    }

    /// What the tag reads as once picked: a path relative to `root`, or an absolute one
    /// when the agent will run somewhere else — a project folder that does not exist yet
    /// cannot be what its own prompt's paths are relative to. A match that is already a
    /// path of its own is left alone; re-rooting it is what stopped `@/Users/…/Desktop/`
    /// from listing anything.
    static func inserted(_ match: String, root: URL, absolute: Bool) -> String {
        let slash = match.hasSuffix("/") ? "/" : ""
        if match.hasPrefix("~") { return (match as NSString).expandingTildeInPath + slash }
        guard absolute, !match.hasPrefix("/") else { return match }
        return root.appendingPathComponent(match).path + slash
    }

    private static func isFolder(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Replaces the tag being typed with the picked path. A finished tag on a file closes
    /// with a space; a folder never does, so the next keystroke — or the next Tab — is
    /// still inside it.
    static func complete(_ text: String, with path: String, finished: Bool = true) -> String {
        guard let at = text.lastIndex(of: "@") else { return text }
        let close = finished && !path.hasSuffix("/") ? " " : ""
        return String(text[...at]) + path + close
    }

    /// Tab, the way a shell does it: fill in as far as every match agrees and leave the
    /// list up. One match completes — a folder keeps its slash, so what the list shows
    /// next is one level down inside it, and Tab again walks further. Nothing is picked
    /// for you while the matches still disagree; Return is what takes one.
    ///
    /// What the matches agree on is read the way they were found: case-insensitively.
    /// `justinzen/` beside `Justin Zen.pdf` agree on `Justin` — comparing case-sensitively
    /// made them agree on nothing past the folder, and Tab did nothing at all.
    ///
    /// A folder the tag already names in full is walked into even while a sibling still
    /// matches: `@…/justinzen` with a `justinzen_codes.txt` next to it agrees on nothing
    /// further, and stalling there is a dead Tab on the folder you were heading for.
    ///
    /// True whenever a tag is open, so Tab stays inside the box rather than moving focus.
    static func extend(_ text: inout String, root: URL, absolute: Bool) -> Bool {
        guard let query = query(in: text) else { return false }
        let all = matches(query, root: root)
        guard let first = all.first else { return false }
        let shared = all.dropFirst().reduce(first) {
            $0.commonPrefix(with: $1, options: .caseInsensitive)
        }
        let folder = all.first { $0.hasSuffix("/") && $0.dropLast().lowercased() == query.lowercased() }
        let deeper = shared.count > query.count ? shared : folder
        guard all.count == 1 || deeper != nil else { return true }
        text = complete(
            text, with: inserted(deeper ?? shared, root: root, absolute: absolute),
            finished: all.count == 1)
        return true
    }

    /// Return in a prompt box takes the first tag on offer before it sends anything —
    /// sending `@REA` would hand the agent a path that does not exist. True when it took
    /// the key, so the caller knows not to submit.
    static func accept(_ text: inout String, root: URL, absolute: Bool) -> Bool {
        guard let query = query(in: text), let top = matches(query, root: root).first
        else { return false }
        text = complete(text, with: inserted(top, root: root, absolute: absolute))
        return true
    }
}

/// The prompt box itself: what you type, and the tags offered under it while you type an
/// `@`. Tab fills in what the matches agree on and lists the next level down, the way a
/// shell does, and takes the highlighted tag once there is nothing left to fill in; ↑/↓
/// walk the list, Return takes the one they are sitting on, and Return with no tag open
/// sends.
struct PromptField: View {
    let placeholder: String
    /// Where `@` starts browsing.
    let root: URL
    var absolute = false
    @Binding var text: String
    let submit: () -> Void

    @FocusState private var focused: Bool
    /// Live only while this box has focus — see `claimTab()`.
    @State private var tabWatch: Any?
    /// Which tag the arrow keys are sitting on. Reset whenever the list changes under it.
    @State private var selection = 0

    /// Every match, and the handful of them that fit under the box.
    private var suggestions: [String] {
        Mention.query(in: text).map { Mention.matches($0, root: root) } ?? []
    }
    private var shown: [String] { Array(suggestions.prefix(6)) }
    /// The list can shrink a keystroke before `selection` hears about it.
    private var highlighted: Int { min(selection, max(shown.count - 1, 0)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(4...14)
                .font(Typo.text(13))
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line2, lineWidth: 1))
                .focused($focused)
                .onSubmit(submit)
            if !suggestions.isEmpty { tags }
        }
        .task { focused = true }
        .onChange(of: text) { _ in selection = 0 }
        .onChange(of: focused) { $0 ? claimTab() : releaseTab() }
        .onDisappear(perform: releaseTab)
    }

    /// Tab, the arrows and Return belong to the tag being typed, not to the next field:
    /// moving focus away mid-path leaves a half-typed tag the agent cannot resolve, and
    /// Return would send a prompt naming a path that does not exist. With no tag open
    /// every one of them is handed back and behaves as usual.
    ///
    /// ponytail: a key monitor scoped to this box's focus, rather than wrapping NSTextView
    /// to get at `doCommandBy:`. Upgrade if the box ever needs more key handling than this.
    private func claimTab() {
        guard tabWatch == nil else { return }
        tabWatch = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard !event.modifierFlags.contains(.shift) else { return event }
            let open = !shown.isEmpty
            switch event.keyCode {
            case 125 where open:
                selection = min(highlighted + 1, shown.count - 1)
            case 126 where open:
                selection = max(highlighted - 1, 0)
            case 36 where open:
                take(shown[highlighted])
            case 48:
                var draft = text
                guard Mention.extend(&draft, root: root, absolute: absolute) else { return event }
                // Nothing left to fill in — `sources/` and `website/` agree on nothing —
                // so Tab takes the highlighted one rather than sitting there dead.
                if draft == text { take(shown[highlighted]) } else { text = draft }
            default:
                return event
            }
            return nil
        }
    }

    /// Writes a picked tag into the box and puts the list back at the top for whatever
    /// the next level down offers.
    private func take(_ match: String) {
        text = Mention.complete(text, with: Mention.inserted(match, root: root, absolute: absolute))
        selection = 0
    }

    private func name(of match: String) -> String {
        let trimmed = match.hasSuffix("/") ? String(match.dropLast()) : match
        return (trimmed as NSString).lastPathComponent + (match.hasSuffix("/") ? "/" : "")
    }

    private func releaseTab() {
        if let tabWatch { NSEvent.removeMonitor(tabWatch) }
        tabWatch = nil
    }

    private var tags: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element) { index, match in
                Button {
                    take(match)
                    focused = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: match.hasSuffix("/") ? "folder" : "doc")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.tx3)
                        // The name, not the path: the path is already in the box above,
                        // and drilling down makes it long enough to push the row out.
                        Text(name(of: match)).font(Typo.mono(11))
                            .foregroundStyle(index == highlighted ? Theme.tx : Theme.tx2)
                        Spacer(minLength: 8)
                        if index == highlighted {
                            Text("↩").font(Typo.mono(9.5)).foregroundStyle(Theme.tx3)
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(index == highlighted ? Theme.line2 : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if suggestions.count > shown.count {
                Text("+\(suggestions.count - shown.count) more — keep typing")
                    .font(Typo.mono(10)).foregroundStyle(Theme.tx3)
                    .padding(.horizontal, 10).frame(height: 20)
            }
        }
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line2, lineWidth: 1))
    }
}
