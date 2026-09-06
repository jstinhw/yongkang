import SwiftUI

/// Create one `.notebook/team/<name>.md`: a name, the skill(s) that become its system
/// prompt, and a line on what it owns. Editing an agent afterwards is done in the file.
struct NewAgentForm: View {
    let skills: [String]
    let taken: [String]
    let save: (TeamMember) -> Void
    let cancel: () -> Void

    @State private var name = ""
    @State private var owns = ""
    @State private var picked: [String] = []

    private var slug: String { NotebookFormat.slug(name) }
    private var clash: Bool { taken.map(NotebookFormat.slug).contains(slug) && !slug.isEmpty }
    private var valid: Bool { !slug.isEmpty && !picked.isEmpty && !clash }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New agent").font(Typo.display(16)).foregroundStyle(Theme.tx)

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Name")
                TextField("mobile-dev", text: $name).textFieldStyle(.roundedBorder)
                if clash {
                    Text("An agent named \(slug) already exists.")
                        .font(Typo.text(11)).foregroundStyle(Theme.red)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Skills", trailing: "its system prompt")
                ForEach(skills, id: \.self) { skill in
                    Toggle(isOn: Binding(
                        get: { picked.contains(skill) },
                        set: { on in
                            picked = on ? picked + [skill] : picked.filter { $0 != skill }
                        }
                    )) {
                        Text(skill).font(Typo.text(12)).foregroundStyle(Theme.tx2)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("Owns")
                TextField("the kind of task that routes to it", text: $owns)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Create") {
                    save(TeamMember(name: slug,
                                    skills: skills.filter { picked.contains($0) },
                                    owns: owns.trimmingCharacters(in: .whitespaces)))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!valid)
            }
        }
        .padding(22)
        .frame(width: 420)
        .background(Theme.bg)
    }
}
