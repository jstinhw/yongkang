import Foundation

/// A notebook page's body, parsed into structured content instead of left as raw
/// Markdown — this is the schema the UI renders, never the unparsed file text. Built
/// against real notebook pages (not just the empty scaffold `NotebookFormat` writes):
/// agents write a `# Title` restating the frontmatter, intro prose, then headed
/// sections — but a checkbox list often sits right after the intro with no heading of
/// its own, and a bullet list of `[[id]]` links is how a project names its own tasks
/// and decisions.
enum NotebookContent {
    struct Section: Equatable {
        /// nil for the untitled block of text before the first `## ` heading.
        var heading: String?
        var blocks: [Block]
    }

    enum Block: Equatable {
        case paragraph(String)
        case checklist([ChecklistItem])
        case list([String])
    }

    struct ChecklistItem: Equatable {
        var text: String
        var done: Bool
    }

    /// The page's body, already stripped of frontmatter (`NotebookIndex.body`), split
    /// into sections and then into paragraphs, checklists and plain bullet lists. A
    /// checkbox is recognized wherever it appears, not only directly under a heading
    /// meant for it. A wrapped line — no bullet, no blank line before it — is folded
    /// into whichever list item or paragraph was open, rather than starting a stray
    /// paragraph in the middle of one.
    static func sections(_ body: String) -> [Section] {
        var result: [Section] = []
        var heading: String?
        var blocks: [Block] = []
        var paragraph: [String] = []
        var checklist: [ChecklistItem] = []
        var list: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }
        func flushChecklist() {
            guard !checklist.isEmpty else { return }
            blocks.append(.checklist(checklist))
            checklist = []
        }
        func flushList() {
            guard !list.isEmpty else { return }
            blocks.append(.list(list))
            list = []
        }
        func flushBlocks() { flushParagraph(); flushChecklist(); flushList() }
        func flushSection() {
            flushBlocks()
            if !blocks.isEmpty { result.append(Section(heading: heading, blocks: blocks)) }
            blocks = []
        }

        for raw in body.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let hashes = line.prefix { $0 == "#" }

            if !hashes.isEmpty, line.count > hashes.count,
               line[line.index(line.startIndex, offsetBy: hashes.count)] == " " {
                let title = String(line.dropFirst(hashes.count + 1))
                if hashes.count == 2 {
                    flushSection()
                    heading = title
                } else {
                    // `# Title` restates the frontmatter title; anything deeper than
                    // `##` is not a heading level this format uses — neither is shown
                    // as its own block, but nothing before it is lost.
                    flushBlocks()
                }
            } else if line.hasPrefix("- [x] ") || line.hasPrefix("- [X] ") {
                flushParagraph(); flushList()
                checklist.append(ChecklistItem(text: String(line.dropFirst(6)), done: true))
            } else if line.hasPrefix("- [ ] ") {
                flushParagraph(); flushList()
                checklist.append(ChecklistItem(text: String(line.dropFirst(6)), done: false))
            } else if line.hasPrefix("- ") {
                flushParagraph(); flushChecklist()
                list.append(String(line.dropFirst(2)))
            } else if line.isEmpty {
                flushBlocks()
            } else if !checklist.isEmpty {
                checklist[checklist.count - 1].text += " " + line
            } else if !list.isEmpty {
                list[list.count - 1] += " " + line
            } else {
                paragraph.append(line)
            }
        }
        flushSection()
        return result
    }

    // MARK: - Cross-links

    enum Token: Equatable {
        case text(String)
        case link(String)
    }

    /// `text`, split into plain runs and `[[id]]` references, in order. An unmatched
    /// `[[` is kept as plain text rather than swallowing the rest of the line.
    static func tokens(_ text: String) -> [Token] {
        var result: [Token] = []
        var remaining = Substring(text)
        while let open = remaining.range(of: "[[") {
            let before = remaining[remaining.startIndex..<open.lowerBound]
            if !before.isEmpty { result.append(.text(String(before))) }
            guard let close = remaining.range(of: "]]", range: open.upperBound..<remaining.endIndex) else {
                result.append(.text(String(remaining[open.lowerBound...])))
                return result
            }
            result.append(.link(String(remaining[open.upperBound..<close.lowerBound])))
            remaining = remaining[close.upperBound...]
        }
        if !remaining.isEmpty { result.append(.text(String(remaining))) }
        return result
    }

    static func wikilinks(in text: String) -> [String] {
        tokens(text).compactMap { if case .link(let id) = $0 { return id }; return nil }
    }

    /// True when `text` is nothing but one or more `[[id]]` references — a plain
    /// cross-link list item (how a project names its own tasks and decisions), as
    /// opposed to prose that happens to mention one.
    static func isPureLinks(_ text: String) -> Bool {
        let found = tokens(text)
        guard !found.isEmpty else { return false }
        return found.allSatisfy { token in
            switch token {
            case .link: return true
            case .text(let s): return s.trimmingCharacters(in: .whitespaces).isEmpty
            }
        }
    }
}
