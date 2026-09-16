import AppKit
import SwiftUI
import YongkangCore

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

    /// The name, or the next one along when a folder is already sitting there.
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
/// otherwise it lands beside the projects already open, under a name the selected agent
/// chooses from the description once Return is pressed. No path is shown before then;
/// naming one in the prompt is how you choose it yourself.
package struct NewProjectForm: View {
    /// Where a project lands when its prompt does not name anywhere.
    let parent: URL
    /// The CLI that names the folder: the one about to write its notebook.
    let agent: AgentKind
    let create: (URL, String) -> Void
    let cancel: () -> Void

    @State private var text = ""
    @State private var failure = ""
    /// The agent choosing a name, while it does. Cancel ends it, and the CLI with it.
    @State private var naming: Task<Void, Never>?

    package init(
        parent: URL, agent: AgentKind, create: @escaping (URL, String) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.parent = parent
        self.agent = agent
        self.create = create
        self.cancel = cancel
    }

    private var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }
    /// Where `@` starts browsing: beside the other projects, unless that folder is not
    /// there yet — an empty list is no place to start tagging from.
    private var root: URL {
        var isDirectory: ObjCBool = false
        let there = FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory)
        return there && isDirectory.boolValue ? parent : home
    }
    private var prompt: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    package var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New project").font(Typography.headline).foregroundStyle(Theme.tx)

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Describe it", trailing: "an agent builds it")
                PromptField(
                    placeholder: "A CLI that…", root: root, absolute: true,
                    text: $text, submit: submit)
                Text("@ tags a file or folder · Tab completes · ↑↓ picks · Return takes it")
                    .font(Typography.mono).foregroundStyle(Theme.tx3)
                // Naming can take half a minute on some CLIs; without this the sheet looks stuck.
                if naming != nil {
                    Text("\(agent.displayName) is naming the project…")
                        .font(Typography.mono).foregroundStyle(Theme.tx2)
                }
            }

            if !failure.isEmpty {
                Text(failure).font(Typography.body).foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    naming?.cancel()
                    cancel()
                }
                .keyboardShortcut(.cancelAction)
                Button("Create project", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(prompt.isEmpty || naming != nil)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(Theme.bg)
        .onDisappear { naming?.cancel() }
    }

    /// A path named in the prompt wins; a folder it names that is already there is a
    /// parent to land in, not the project itself. Nothing named lands beside the other
    /// projects, and has no name until the agent gives it one.
    private var destination: (parent: URL, name: String?) {
        let found = ProjectLocation.parse(text)
        if let found, !found.name.isEmpty { return (found.parent, found.name) }
        return (found?.parent ?? parent, nil)
    }

    private func submit() {
        if Mention.accept(&text, root: root, absolute: true) { return }
        guard !prompt.isEmpty, naming == nil else { return }
        let (parent, name) = destination
        if let name {
            make(parent.appendingPathComponent(name), rejecting: name, for: prompt)
            return
        }
        failure = ""
        let description = prompt
        naming = Task {
            do {
                let named = try await ProjectNaming.ask(agent, description: description)
                // What was typed when Return was pressed, not what the box holds by now.
                make(ProjectLocation.vacant(in: parent, named: named), rejecting: named, for: description)
            } catch is CancellationError {
                // Cancel closed the sheet; there is nobody left to tell.
            } catch {
                failure =
                    "\(error.localizedDescription). Name a path in the prompt, like ~/Projects/my-app, "
                    + "to choose the folder yourself."
            }
            naming = nil
        }
    }

    private func make(_ directory: URL, rejecting name: String, for description: String) {
        if let rejection = ProjectLocation.rejection(name) {
            failure = rejection
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            failure = "Could not create \(directory.path): \(error.localizedDescription)"
            return
        }
        create(directory, description)
    }
}
