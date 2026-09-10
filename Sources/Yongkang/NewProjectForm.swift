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
/// and the folder is created and handed to an agent that writes the notebook. Opening a
/// folder that already exists is the other door, kept beside it.
struct NewProjectForm: View {
    let create: (URL, String) -> Void
    let openExisting: () -> Void
    let cancel: () -> Void

    @State private var text = ""
    @State private var parent: URL?
    @State private var name = ""
    /// Once the location has been picked by hand the prompt stops overwriting it.
    @State private var pinned = false
    @State private var failure = ""

    private var home: URL { URL(fileURLWithPath: NSHomeDirectory()) }
    private var root: URL { parent ?? home }
    private var prompt: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var valid: Bool {
        !prompt.isEmpty && parent != nil && !name.isEmpty && ProjectLocation.rejection(name) == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New project").font(Typo.display(16)).foregroundStyle(Theme.tx)

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("What should the agent build?")
                PromptField(placeholder: "A CLI that…", root: root, absolute: true,
                            text: $text, submit: submit)
                    .onChange(of: text) { _ in detectLocation() }
                Text("@ tags a file or folder · Tab completes · ↑↓ picks · Return takes it")
                    .font(Typo.mono(10.5)).foregroundStyle(Theme.tx3)
            }

            location

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
                    .disabled(!valid)
            }
        }
        .padding(22)
        .frame(width: 520)
        .background(Theme.bg)
    }

    private var location: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(parent == nil ? "Where should it go?" : "Location")
            HStack(spacing: 8) {
                Button(parent == nil ? "Choose…" : "Change…", action: choose)
                    .buttonStyle(.console)
                Text(parent.map { abbreviated($0) + "/" } ?? "not named in the prompt")
                    .font(Typo.mono(11))
                    .foregroundStyle(parent == nil ? Theme.tx3 : Theme.tx2)
                    .lineLimit(1).truncationMode(.head)
                TextField("folder-name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .font(Typo.mono(11))
                    .frame(width: 160)
                    .onChange(of: name) { _ in pinned = true }
            }
            if let rejection = ProjectLocation.rejection(name), !name.isEmpty {
                Text(rejection).font(Typo.text(11.5)).foregroundStyle(Theme.amber)
            }
        }
    }

    private func abbreviated(_ url: URL) -> String {
        (url.path as NSString).abbreviatingWithTildeInPath
    }

    /// The prompt names where it goes often enough that asking first would be a nag; when
    /// it does not, the empty location row is the question.
    private func detectLocation() {
        guard !pinned, let found = ProjectLocation.parse(text) else { return }
        parent = found.parent
        if !found.name.isEmpty { name = found.name }
    }

    private func choose() {
        guard let path = pickDirectory(message: "The new project folder is created in here.")
        else { return }
        parent = URL(fileURLWithPath: path)
        pinned = true
    }

    private func submit() {
        if Mention.accept(&text, root: root, absolute: true) { return }
        guard valid, let parent else { return }
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
