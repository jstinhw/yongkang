import SwiftUI
import YongkangCore
import YongkangUI

extension DesignShots {
    /// A session asking for a command to be run, with the pane beside its terminal that shows the
    /// command, the two scripts behind it and the program the second puts on `PATH`. The scripts
    /// are written to /tmp so the pane reads them off disk, as it does in the app.
    @MainActor static func writeCommandShot(_ project: Project, into directory: URL) {
        let scratch = URL(fileURLWithPath: "/tmp/yongkang-shots-command")
        for (name, text) in commandScripts {
            let url = scratch.appendingPathComponent(name)
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: scratch.appendingPathComponent("tool/git-filter-repo").path)

        let session = project.sessions[0]
        let gate = UserBlock(
            id: "/tmp/move-branches.md", url: URL(fileURLWithPath: "/tmp/move-branches.md"), slug: "move-branches",
            title: "Recreate the repo with clean history", status: "open", kind: "block", stage: "ready",
            session: session.id, action: "", link: URL(string: "https://github.com/you/yongkang/settings"),
            task: session.taskIDs.first, resolution: "", body: "", before: nil, branch: "", revisions: [],
            run: "bash \(scratch.path)/finish.sh")
        var asking = project
        asking.blocks.append(gate)
        write(
            console(asking, section: .agents, selection: .session(session.id)) {
                AgentPage(
                    session: session, project: asking,
                    row: asking.agentRows(summary: ChangeSummary(), asking: [:])
                        .first { $0.route == .session(session.id) },
                    openBlock: { _ in },
                    content: {
                        HSplitView {
                            Theme.bg.frame(minWidth: 420)
                            GuidePane(block: gate, directory: asking.directory) { _ in }.frame(minWidth: 360)
                        }
                    })
            }, "session-command", into: directory)
    }

    private static let commandScripts: [(String, String)] = [
        (
            "finish.sh",
            """
            #!/bin/bash
            # Move this repo's branches onto the rewritten history, then push main to the new repo.
            set -euo pipefail
            S=$(cd "$(dirname "$0")" && pwd)
            REPO=$HOME/sources/yongkang
            bash "$S/rewrite.sh" "$REPO" --apply
            cd "$REPO"
            git remote remove origin
            git remote add origin git@github.com:you/yongkang.git
            git push -u origin main
            echo "finished"
            """
        ),
        (
            "rewrite.sh",
            """
            #!/bin/bash
            # Rewrite every local branch's history without touching any worktree's files.
            set -euo pipefail
            S=$(cd "$(dirname "$0")" && pwd)
            W=$S/w
            rm -rf "$W" && mkdir -p "$W"
            git clone -q --mirror "$1" "$W/mirror.git"
            PATH=$S/tool:$PATH git -C "$W/mirror.git" filter-repo --force --replace-text "$S/rules.txt"
            [ "${2:-}" = --apply ] || exit 0
            git -C "$1" fetch -q "$W/mirror.git" '+refs/heads/*:refs/rewrite/heads/*'
            git -C "$1" for-each-ref --format='update %(refname)' refs/rewrite | git -C "$1" update-ref --stdin
            echo applied
            """
        ),
        (
            "tool/git-filter-repo",
            """
            #!/usr/bin/env python3
            \"\"\"
            git-filter-repo filters git repositories, similar to git filter-branch, BFG
            repo cleaner, and others.
            \"\"\"
            import sys
            """
        ),
    ]
}
