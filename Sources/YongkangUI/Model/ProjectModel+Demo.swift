import Foundation
import YongkangCore

extension ProjectModel {
    /// The command that would bring the demo's page back, when it is down and can be: a page
    /// on this Mac, not answering, whose file says how to serve it. Nil means leave it alone.
    func downDemo(_ block: UserBlock) async -> (url: URL, command: String)? {
        guard block.isDemo, let url = block.link, DemoServer.isLocal(url), !block.serve.isEmpty else { return nil }
        return await DemoServer.answers(url) ? nil : (url, block.serve)
    }

    /// The demo's `serve:` command in a terminal of its own. That terminal is a service, like
    /// `Run`: shown in the list, so the page can be stopped, and not kept across a quit.
    /// One already starting is waited on, not joined by a second fighting it for the port.
    func startServing(_ block: UserBlock) {
        let title = "Serve \(block.task ?? block.slug)"
        guard !sessions.contains(where: { $0.title == title }) else { return }
        addSession(
            id: UUID(), title: title, icon: "play.circle",
            line: AgentCommand.line(directory: directory.path, run: block.serve))
    }

    /// Whether the user has let this project run this exact command. `serve:` is read from a
    /// file in the project, which a cloned repo brings with it, so it is never run on the
    /// file's say-so alone: the first time is always asked, and a changed command asks again.
    func trustsServe(_ command: String) -> Bool {
        (UserDefaults.standard.stringArray(forKey: Self.trustedServeKey) ?? []).contains(trustEntry(command))
    }

    func trustServe(_ command: String) {
        let trusted = UserDefaults.standard.stringArray(forKey: Self.trustedServeKey) ?? []
        UserDefaults.standard.set(Array(Set(trusted + [trustEntry(command)])), forKey: Self.trustedServeKey)
    }

    private static let trustedServeKey = "trustedServeCommands"

    private func trustEntry(_ command: String) -> String { directory.path + "\n" + command }
}
