import SwiftUI
import AppKit

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
                  isDirectory.boolValue else { continue }
            return (parent, url.lastPathComponent)
        }
        return nil
    }

    /// Words that name nothing — every second prompt opens with them, and a folder called
    /// `build-a-tool-that` is worse than one called `weather-cli`.
    private static let filler: Set<String> = ["a", "an", "the", "and", "build", "create",
                                              "for", "it", "make", "of", "project", "that",
                                              "then", "to", "which", "with"]

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
/// goes is worked out from the prompt rather than asked for every time — a path named in
/// the prompt wins, otherwise it is a folder named after the prompt inside the projects
/// folder, which is asked for once. Opening a folder that already exists is the other
/// door, kept beside it.
struct NewProjectForm: View {
    let create: (URL, String) -> Void
    let openExisting: () -> Void
    let cancel: () -> Void

    @State private var text = ""
    @State private var failure = ""
    /// Where projects live, asked for the first time one needs it and remembered after.
    @AppStorage("projectsRoot") private var projectsRoot = ""

    private var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }
    private var stored: URL? { projectsRoot.isEmpty ? nil : URL(fileURLWithPath: projectsRoot) }
    private var root: URL { stored ?? home }
    private var prompt: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New project").font(Typo.display(16)).foregroundStyle(Theme.tx)

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("What should the agent build?")
                PromptField(placeholder: "A CLI that…", root: root, absolute: true,
                            text: $text, submit: submit)
                Text("@ tags a file or folder · Tab completes · ↑↓ picks · Return takes it")
                    .font(Typo.mono(10.5)).foregroundStyle(Theme.tx3)
            }

            // Not a question, an answer: where this one is about to land.
            Text(landing).font(Typo.mono(11)).foregroundStyle(Theme.tx2)
                .lineLimit(1).truncationMode(.head)

            if !failure.isEmpty {
                Text(failure).font(Typo.text(11.5)).foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Open a folder instead…", action: openExisting)
                    .buttonStyle(.consoleGhost)
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
        guard !prompt.isEmpty else { return "Named in the prompt, or wherever projects live." }
        let (parent, name) = destination
        guard let parent else { return "Ask me where projects live — once." }
        return abbreviated(parent) + "/" + name
    }

    /// A path named in the prompt wins; a folder it names that is already there is a
    /// parent to land in, not the project itself. `parent` is nil only while the projects
    /// folder is still unknown — `submit` is where that gets asked.
    private var destination: (parent: URL?, name: String) {
        let found = ProjectLocation.parse(text)
        if let found, !found.name.isEmpty { return (found.parent, found.name) }
        guard let parent = found?.parent ?? stored else { return (nil, ProjectLocation.suggest(prompt)) }
        return (parent, ProjectLocation.vacant(in: parent, named: ProjectLocation.suggest(prompt))
                            .lastPathComponent)
    }

    private func abbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    private func submit() {
        if Mention.accept(&text, root: root, absolute: true) { return }
        guard !prompt.isEmpty else { return }
        // Asked here rather than up front: a prompt that names its own path never needs it.
        if destination.parent == nil {
            guard let picked = pickDirectory(message: "New projects are created in here.")
            else { return }
            projectsRoot = picked
        }
        let (parent, name) = destination
        guard let parent else { return }
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
