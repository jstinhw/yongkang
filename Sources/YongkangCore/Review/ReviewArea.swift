import Foundation

/// Which part of the product a changed file belongs to, so a reviewer can see at a glance
/// that a task touched the database or an endpoint before reading any of it. Worked out
/// here from the path, the diff and the worker that owned the file — an agent never
/// declares it, so it cannot be talked out of flagging a schema change.
package enum ReviewArea: String, CaseIterable, Identifiable {
    case database = "Database"
    case api = "API & services"
    case frontend = "Frontend"
    case tests = "Tests"
    case config = "Config"
    case other = "Docs & other"
    case notebook = "Notebook records"

    package var id: Self { self }

    package var systemImage: String {
        switch self {
        case .database: return "cylinder.split.1x2"
        case .api: return "server.rack"
        case .frontend: return "macwindow"
        case .tests: return "testtube.2"
        case .config: return "gearshape"
        case .other: return "doc.text"
        case .notebook: return "book.closed"
        }
    }

    /// Rules in order, first match wins: records, tests, database, config, API, frontend,
    /// then the owning worker's skill. Tests go before the database so a test that seeds
    /// rows reads as the test it is.
    /// ponytail: name and folder heuristics, not a parser — a repo with its own layout gets
    /// the skill fallback, which is the lead's own routing and rarely far off.
    package static func of(_ path: String, skill: String = "", diff: [DiffLine] = []) -> ReviewArea {
        let lower = path.lowercased()
        let folders = Set(lower.split(separator: "/").dropLast().map(String.init))
        let name = (lower as NSString).lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension

        if folders.contains(".notebook") { return .notebook }
        if !folders.isDisjoint(with: ["test", "tests", "__tests__", "spec", "specs", "e2e", "playwright", "cypress"])
            || [".test.", ".spec.", "_test.", "_spec."].contains(where: name.contains)
            || stem.hasSuffix("test") || stem.hasSuffix("tests")
        {
            return .tests
        }
        if !folders.isDisjoint(with: [
            "migrations", "migration", "migrate", "db", "database", "prisma", "drizzle", "supabase",
        ])
            || ["sql", "prisma"].contains(ext) || stem.contains("schema") || stem.contains("migration")
            || touchesSQL(diff)
        {
            return .database
        }
        if [
            "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "package.swift", "package.resolved",
            "dockerfile", "docker-compose.yml", "makefile", "vercel.json", "tsconfig.json", ".env.example",
        ].contains(name)
            || !folders.isDisjoint(with: [".github", ".circleci", "deploy", "infra", "terraform", "k8s"])
            || ["yml", "yaml", "toml", "sh"].contains(ext) || stem.hasSuffix(".config")
        {
            return .config
        }
        if !folders.isDisjoint(with: [
            "api", "server", "routes", "controllers", "handlers", "services", "backend",
            "functions", "graphql", "trpc", "endpoints",
        ])
            || ["actions", "route", "middleware"].contains(stem)
        {
            return .api
        }
        if !folders.isDisjoint(with: ["components", "pages", "views", "ui", "styles", "screens", "frontend", "client"])
            || ["tsx", "jsx", "vue", "svelte", "css", "scss", "html"].contains(ext)
        {
            return .frontend
        }

        let owner = skill.lowercased()
        if owner.contains("frontend") || owner.contains("design") { return .frontend }
        if owner.contains("backend") { return .api }
        if owner.contains("qa") { return .tests }
        if owner.contains("sre") { return .config }
        return .other
    }

    /// SQL written into the change itself — a data layer with no migration folder still
    /// touches the database, and that is exactly the file a reviewer must not miss.
    static func touchesSQL(_ diff: [DiffLine]) -> Bool {
        let changed = diff.filter { $0.kind == .add || $0.kind == .remove }.map(\.text).joined(separator: "\n")
        return changed.range(
            of:
                #"\b(select\b[^;]*?\bfrom|insert\s+into|update\s+[\w."`]+\s+set|delete\s+from|(create|alter|drop)\s+(table|index))\b"#,
            options: [.regularExpression, .caseInsensitive]) != nil
    }
}

/// One comment on one diff line, kept until the user sends the review.
package struct ReviewComment: Identifiable, Equatable {
    package let id = UUID()
    package var path: String
    /// The line number as the diff shows it: the new side, or the old side for a removal.
    package var line: String
    /// The code the comment is about, so the agent reads it without opening the file.
    package var code: String
    package var text: String

    package init(path: String, line: String, code: String, text: String) {
        self.path = path
        self.line = line
        self.code = code
        self.text = text
    }
}

/// What the user has to say about one task before they approve it or send it back.
package struct ReviewDraft: Equatable {
    package var comments: [ReviewComment] = []
    package var note = ""

    package init(comments: [ReviewComment] = [], note: String = "") {
        self.comments = comments
        self.note = note
    }

    package var isEmpty: Bool { comments.isEmpty && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Typed into the lead's terminal, so it opens with the exact words the lead skill
    /// listens for and closes with what to do — the lead routes each comment to the owner
    /// of that file.
    package func message(taskID: String, title: String) -> String {
        var lines = ["Changes requested on \(taskID) — \"\(title)\"."]
        let said = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !said.isEmpty { lines += ["", said] }
        if !comments.isEmpty { lines.append("") }
        for comment in comments {
            lines.append(
                "- \(comment.path):\(comment.line) — \(comment.text.trimmingCharacters(in: .whitespacesAndNewlines))")
            let code = comment.code.trimmingCharacters(in: .whitespaces)
            if !code.isEmpty { lines.append("  > \(code)") }
        }
        lines += [
            "",
            "Quote these under ## Change request in the new attempt's Work file, send them to the "
                + "owner of each file, rerun QA, and mark the task done again. Do not commit.",
        ]
        return lines.joined(separator: "\n")
    }
}
