import Foundation
import YongkangCore

extension ProjectModel {
    /// One terminal per runnable service, all started together, because a front end
    /// reviewed without its service behind it is a page of errors. A service named after
    /// its repo (the common single-app case) keeps that name; one of several under a repo
    /// is named `repo/service`. Anything with nothing to run is named rather than skipped
    /// in silence: those labels come back as `unstarted`, for the caller to say so.
    ///
    /// A service already running is shown, not started again: a second `npm run dev`
    /// fights the first one for its port, and the loser exits — which is exactly what was
    /// pushing a "default to :3000" preview onto whatever port the collision left it on.
    func runServices(
        _ steps: [(repo: String, directory: URL, services: [Service.Runnable])]
    ) -> (destination: Destination, unstarted: [String]) {
        let named = steps.flatMap { step in
            step.services.map { service in
                (
                    label: service.name == step.repo ? step.repo : "\(step.repo)/\(service.name)",
                    directory: service.directory, command: service.command
                )
            }
        }
        // The last service started or shown is the one left on screen.
        var destination = Destination(section: .agents)
        for service in named where service.command != nil {
            let title = "Run \(service.label)"
            if let running = sessions.first(where: { $0.title == title }) {
                destination.route = .session(running.id)
                continue
            }
            let id = UUID()
            addSession(
                id: id, title: title, icon: "play.circle",
                line: AgentCommand.line(directory: service.directory.path, run: service.command!))
            destination.route = .session(id)
        }
        return (destination, named.filter { $0.command == nil }.map(\.label))
    }
}
