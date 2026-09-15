import Foundation
import Testing

@testable import YongkangCore

@Suite struct DefaultsMigrationTests {
    @Test func copiesOldSettingsWithoutOverwritingNewOnes() throws {
        let names = ["yongkang.test.old.\(UUID())", "yongkang.test.new.\(UUID())"]
        defer { names.forEach(UserDefaults.standard.removePersistentDomain(forName:)) }
        let old = try #require(UserDefaults(suiteName: names[0]))
        let new = try #require(UserDefaults(suiteName: names[1]))
        old.set(#"["/tmp/project"]"#, forKey: "openProjects")
        old.set(300.0, forKey: "listWidth")
        old.set(true, forKey: "listHidden")
        old.set("codex", forKey: "agentKind")
        old.set("stays behind", forKey: "unrelated")
        new.set(false, forKey: "listHidden")

        DefaultsMigration.run(from: old, to: new)

        #expect(new.string(forKey: "openProjects") == #"["/tmp/project"]"#, "open projects survive the move")
        #expect(new.double(forKey: "listWidth") == 300)
        #expect(new.object(forKey: "listHidden") as? Bool == false, "a value set after the move wins")
        #expect(new.string(forKey: "agentKind") == "codex")
        #expect(new.object(forKey: "unrelated") == nil, "only the listed keys move")

        new.set(240.0, forKey: "listWidth")
        DefaultsMigration.run(from: old, to: new)
        #expect(new.double(forKey: "listWidth") == 240, "running again on the next launch changes nothing")
    }
}
