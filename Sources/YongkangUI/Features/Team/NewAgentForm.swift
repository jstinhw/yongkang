import SwiftUI
import YongkangCore

/// Adding one agent to the Engineering Lead's team, two ways.
///
/// **Manual** writes `.notebook/team/<name>.md` here and now: a name, the skill(s) that
/// become its system prompt — every skill this project can already load, plus anything
/// you fetch from a git repo — and a line on what it owns so the lead can route to it.
///
/// **Incubate** writes nothing. You describe the agent you want and a session goes and
/// finds the skills for it, the same rule the notebook follows: the app does not write
/// what an agent should be deciding. The new roster row appears when that session lands.
package struct NewAgentForm: View {
    /// The project folder: what skills resolve against, and where a fetched one is put.
    let directory: URL
    let taken: [String]
    let save: (TeamMember) -> Void
    let incubate: (String) -> Void
    let cancel: () -> Void

    enum Mode: String, CaseIterable, Identifiable {
        case manual = "Manual"
        case incubate = "Incubate"
        var id: Self { self }
    }

    @State private var mode: Mode = .manual
    @State private var name = ""
    @State private var owns = ""
    @State private var picked: Set<String> = []
    @State private var catalog: [SkillDoc] = []
    @State private var query = ""
    @State private var remote = ""
    @State private var fetching = false
    @State private var fetched = ""
    @State private var failure = ""
    @State private var brief = ""

    package init(
        directory: URL,
        taken: [String],
        save: @escaping (TeamMember) -> Void,
        incubate: @escaping (String) -> Void,
        cancel: @escaping () -> Void
    ) {
        self.directory = directory
        self.taken = taken
        self.save = save
        self.incubate = incubate
        self.cancel = cancel
    }

    private var slug: String { NotebookFormat.slug(name) }
    private var clash: Bool { !slug.isEmpty && taken.map(NotebookFormat.slug).contains(slug) }
    private var valid: Bool {
        mode == .incubate
            ? !brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            : !slug.isEmpty && !picked.isEmpty && !clash
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("New agent").font(Typo.display(16)).foregroundStyle(Theme.tx)
                Spacer()
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 170)
            }

            if mode == .manual { manual } else { incubation }

            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button(mode == .incubate ? "Incubate" : "Create", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!valid)
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(Theme.bg)
        .task { catalog = Skills.available(project: directory) }
    }

    // MARK: - Manual

    @ViewBuilder private var manual: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Name")
            TextField("mobile-dev", text: $name).textFieldStyle(.roundedBorder)
            if clash {
                Text("An agent named \(slug) already exists.")
                    .font(Typo.text(11)).foregroundStyle(Theme.red)
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(
                    "Skills",
                    trailing: picked.isEmpty
                        ? "its system prompt"
                        : "\(picked.count) picked")
                Spacer()
                TextField("filter", text: $query)
                    .textFieldStyle(.roundedBorder).frame(width: 140)
            }
            if catalog.isEmpty {
                Text(
                    "No skills installed. Fetch a repo below, or put one in "
                        + ".claude/skills/ in this project."
                )
                .font(Typo.text(11.5)).foregroundStyle(Theme.tx3)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(shown) { skillRow($0) }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 190)
        }

        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("From a git repo", trailing: "installs into .claude/skills/")
            HStack(spacing: 8) {
                TextField("https://github.com/owner/skills.git", text: $remote)
                    .textFieldStyle(.roundedBorder)
                    .disabled(fetching)
                    .onSubmit(fetch)
                Button(fetching ? "Fetching…" : "Fetch", action: fetch)
                    .buttonStyle(.console)
                    .disabled(fetching || !Skills.isRemote(remote))
            }
            if !failure.isEmpty {
                Text(failure).font(Typo.text(11)).foregroundStyle(Theme.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !fetched.isEmpty {
                Text(fetched).font(Typo.text(11)).foregroundStyle(Theme.green)
            }
        }

        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Owns", trailing: "how the lead routes to it")
            TextField("the kind of task that routes to it", text: $owns)
                .textFieldStyle(.roundedBorder)
        }
    }

    /// A machine with every skill its owner has ever installed makes this list long, so it
    /// filters — but a skill already ticked never disappears out from under the choice.
    private var shown: [SkillDoc] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return catalog }
        return catalog.filter {
            picked.contains($0.name) || $0.name.localizedCaseInsensitiveContains(needle)
                || $0.summary.localizedCaseInsensitiveContains(needle)
        }
    }

    private func skillRow(_ doc: SkillDoc) -> some View {
        Toggle(
            isOn: Binding(
                get: { picked.contains(doc.name) },
                set: { on in picked = on ? picked.union([doc.name]) : picked.subtracting([doc.name]) }
            )
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.name).font(Typo.mono(12)).foregroundStyle(Theme.tx2)
                if !doc.summary.isEmpty {
                    Text(doc.summary).font(Typo.text(10.5)).foregroundStyle(Theme.tx3)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .toggleStyle(.checkbox)
    }

    // MARK: - Incubate

    @ViewBuilder private var incubation: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Describe the agent")
            Text(
                "A session reads the skills you already have, fetches or writes what is "
                    + "missing, and adds the agent to the roster. It appears here when that "
                    + "session has written it."
            )
            .font(Typo.text(11.5)).foregroundStyle(Theme.tx3)
            .fixedSize(horizontal: false, vertical: true)
            TextField("An agent that owns database migrations and…", text: $brief, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(5...12)
                .font(Typo.text(12.5))
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line2, lineWidth: 1))
        }
    }

    // MARK: - Actions

    private func submit() {
        guard valid else { return }
        guard mode == .manual else {
            return incubate(brief.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        // Roster order follows the catalog, not the order the boxes were ticked — the file
        // reads the same whichever way the user got there.
        save(
            TeamMember(
                name: slug,
                skills: catalog.map(\.name).filter { picked.contains($0) },
                owns: owns.trimmingCharacters(in: .whitespaces)))
    }

    /// Clones the repo into the project's own skills folder and ticks what it brought, so
    /// fetching a skill and assigning it is one move rather than two. Off the main thread,
    /// unlike the app's other `git` calls: those read a local repo, this one is a network
    /// clone and would hold the sheet frozen for as long as the remote takes.
    private func fetch() {
        guard !fetching, Skills.isRemote(remote) else { return }
        let url = remote
        let project = directory
        fetching = true
        failure = ""
        fetched = ""
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try Skills.install(git: url, into: project) }
            let available = Skills.available(project: project)
            DispatchQueue.main.async {
                fetching = false
                catalog = available
                switch result {
                case .success(let installed):
                    picked.formUnion(installed)
                    fetched = "Installed \(installed.joined(separator: ", "))."
                    remote = ""
                case .failure(let error):
                    failure = error.localizedDescription
                }
            }
        }
    }
}
