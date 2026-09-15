import AppKit
import SwiftUI

/// Where a folder named in a prompt would go: `~/code/todo` is a folder to create inside
/// an existing `~/code`, `~/code` on its own is where projects live and the name is still
/// missing. Nothing named means the form has to ask.
enum ProjectLocation {
    static func parse(_ prompt: String) -> (parent: URL, name: String)? {
        let fm = FileManager.default
        for token in prompt.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
            // A tag is a reference, not a destination: `@/Users/me/spec.md` never wins.
            let raw = token.trimmingCharacters(in: CharacterSet(charactersIn: "`'\"“”,.;:()[]"))
            guard raw.hasPrefix("~/") || raw.hasPrefix("/") else { continue }
            let url = URL(fileURLWithPath: (raw as NSString).expandingTildeInPath)
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue { return (url, "") }
                continue
            }
            let parent = url.deletingLastPathComponent()
            guard fm.fileExists(atPath: parent.path, isDirectory: &isDirectory),
                isDirectory.boolValue
            else { continue }
            return (parent, url.lastPathComponent)
        }
        return nil
    }

    /// Words that name nothing — every second prompt opens with them, and a folder called
    /// `build-a-tool-that` is worse than one called `weather-cli`.
    private static let filler: Set<String> = [
        "a", "an", "the", "and", "build", "create",
        "for", "it", "make", "of", "project", "that",
        "then", "to", "which", "with",
    ]

    /// A folder name for a prompt that named no path: the first few words that carry
    /// meaning. Tags and paths are left out — the agent's own references are not a name.
    static func suggest(_ prompt: String) -> String {
        let words = prompt.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .filter { !"@/~".contains($0.first ?? " ") }
            .map { NotebookFormat.slug(String($0)) }
            .filter { !$0.isEmpty && !filler.contains($0) }
        let name = words.prefix(4).joined(separator: "-")
        return name.isEmpty ? "project" : name
    }

    /// The suggested name, or the next one along when a folder is already sitting there.
    /// Nothing an earlier project left behind is written into.
    static func vacant(in parent: URL, named name: String) -> URL {
        var url = parent.appendingPathComponent(name)
        var next = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = parent.appendingPathComponent("\(name)-\(next)")
            next += 1
        }
        return url
    }

    /// A folder name is one path component the user can find again: no separators, no
    /// walking up out of the parent they picked, nothing hidden.
    static func rejection(_ name: String) -> String? {
        if name.contains("/") { return "A folder name cannot contain a slash." }
        if name.hasPrefix(".") { return "A folder name starting with a dot is hidden in Finder." }
        if name == ".." { return "Name the folder." }
        return nil
    }
}

/// New project as a prompt: say what to build, tag whatever it should look at with `@`,
/// and the folder is created and handed to an agent that writes the notebook. Where it
/// goes is worked out rather than asked for at all — a path named in the prompt wins,
/// otherwise it is a folder named after the prompt beside the projects already open. The
/// line under the box says which, before Return, so deciding for you is never a surprise;
/// naming a path in the prompt is how you say otherwise.
struct NewProjectForm: View {
    /// Where a project lands when its prompt does not name anywhere.
    let parent: URL
    let create: (URL, String) -> Void
    let cancel: () -> Void

    @State private var text = ""
    @State private var failure = ""

    private var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }
    /// Where `@` starts browsing: beside the other projects, unless that folder is not
    /// there yet — an empty list is no place to start tagging from.
    private var root: URL {
        var isDirectory: ObjCBool = false
        let there = FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory)
        return there && isDirectory.boolValue ? parent : home
    }
    private var prompt: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New project").font(Typo.display(16)).foregroundStyle(Theme.tx)

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Describe it", trailing: "an agent builds it")
                PromptField(
                    placeholder: "A CLI that…", root: root, absolute: true,
                    text: $text, submit: submit)
                Text("@ tags a file or folder · Tab completes · ↑↓ picks · Return takes it")
                    .font(Typo.mono(10.5)).foregroundStyle(Theme.tx3)
                // Not a question, an answer: where this one is about to land.
                if !prompt.isEmpty {
                    Text(landing).font(Typo.mono(11)).foregroundStyle(Theme.tx2)
                        .lineLimit(1).truncationMode(.head)
                }
            }

            if !failure.isEmpty {
                Text(failure).font(Typo.text(11.5)).foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Create project", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(prompt.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(Theme.bg)
    }

    /// Where the prompt as it stands would put the project, so dropping the question
    /// does not make the answer a mystery.
    private var landing: String {
        let (parent, name) = destination
        return abbreviated(parent) + "/" + name
    }

    /// A path named in the prompt wins; a folder it names that is already there is a
    /// parent to land in, not the project itself. Nothing named lands beside the other
    /// projects under a name taken from the prompt.
    private var destination: (parent: URL, name: String) {
        let found = ProjectLocation.parse(text)
        if let found, !found.name.isEmpty { return (found.parent, found.name) }
        let base = found?.parent ?? parent
        return (
            base,
            ProjectLocation.vacant(in: base, named: ProjectLocation.suggest(prompt))
                .lastPathComponent
        )
    }

    private func abbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private func submit() {
        if Mention.accept(&text, root: root, absolute: true) { return }
        guard !prompt.isEmpty else { return }
        let (parent, name) = destination
        if let rejection = ProjectLocation.rejection(name) {
            failure = rejection
            return
        }
        let directory = parent.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            failure = "Could not create \(directory.path): \(error.localizedDescription)"
            return
        }
        create(directory, prompt)
    }
}
