import Foundation
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// Ordering and grouping the open projects. A group is a name its projects carry, so what the
/// sidebar draws as one group is a run of neighbours naming it — which only holds if every move
/// keeps a group's projects adjacent. That is what these lock in.
@Suite @MainActor struct ProjectGroupTests {
    private func model(_ names: [String]) -> AppModel {
        let model = AppModel(terminals: TerminalRegistry(), notify: { _, _, _ in })
        model.restore(OpenProjects.encode(names.map { "/tmp/yk-\($0)" }))
        return model
    }

    private func order(_ model: AppModel) -> [String] {
        model.projects.map { String($0.directory.lastPathComponent.dropFirst(3)) }
    }

    private func groups(_ model: AppModel) -> [String?] {
        model.projects.map(\.group)
    }

    /// Every group is one run of neighbours: once a group's run ends, its name never comes back.
    private func adjacent(_ model: AppModel) -> Bool {
        let named = groups(model)
        let runs = zip(named, [nil] + named).filter { $0 != $1 }.compactMap(\.0)
        return Set(runs).count == runs.count
    }

    @Test func aProjectDraggedDownLandsWhereTheLineWas() {
        let model = model(["a", "b", "c", "d"])
        let a = model.projects[0].id
        // The line was in the gap before "d", so "a" ends up above "d".
        model.move(a, before: 3, into: nil)
        #expect(order(model) == ["b", "c", "a", "d"])
    }

    @Test func aProjectDraggedUpLandsWhereTheLineWas() {
        let model = model(["a", "b", "c", "d"])
        let d = model.projects[3].id
        model.move(d, before: 1, into: nil)
        #expect(order(model) == ["a", "d", "b", "c"])
    }

    @Test func theGapPastTheLastProjectPutsItAtTheEnd() {
        let model = model(["a", "b", "c"])
        model.move(model.projects[0].id, before: 3, into: nil)
        #expect(order(model) == ["b", "c", "a"])
    }

    @Test func aGroupStartsAtOneProjectAndTakesTheOnesDraggedIn() {
        let model = model(["a", "b", "c"])
        model.group(model.projects[0].id, as: "  Client work  ")
        #expect(groups(model) == ["Client work", nil, nil])

        // Dropped in the gap after the group's last project: same level, adjacent.
        model.move(model.projects[2].id, before: 1, into: "Client work")
        #expect(order(model) == ["a", "c", "b"])
        #expect(groups(model) == ["Client work", "Client work", nil])
    }

    @Test func droppingAtTheTopLevelTakesAProjectOutOfItsGroup() {
        let model = model(["a", "b", "c"])
        model.group(model.projects[0].id, as: "Client work")
        model.move(model.projects[1].id, before: 1, into: "Client work")
        #expect(groups(model) == ["Client work", "Client work", nil])

        // The line was flush with the headers, so "b" comes out of the group where it sits.
        model.move(model.projects[1].id, before: 1, into: nil)
        #expect(order(model) == ["a", "b", "c"])
        #expect(groups(model) == ["Client work", nil, nil])
    }

    @Test func renamingAGroupMovesEveryProjectInItAndUngroupingLetsThemGo() {
        let model = model(["a", "b", "c"])
        model.group(model.projects[0].id, as: "Client work")
        model.move(model.projects[1].id, before: 1, into: "Client work")

        model.renameGroup("Client work", to: "Paid")
        #expect(groups(model) == ["Paid", "Paid", nil])
        // An empty name is not a group: nothing moves rather than everything losing its name.
        model.renameGroup("Paid", to: "   ")
        #expect(groups(model) == ["Paid", "Paid", nil])

        model.ungroup("Paid")
        #expect(groups(model) == [nil, nil, nil])
        #expect(order(model) == ["a", "b", "c"], "ungrouping leaves them where they sit")
    }

    @Test func aGroupNamedFromThePlusMenuIsNothingUntilAProjectIsDraggedIn() {
        let model = model(["a", "b"])
        model.newGroup(named: " Client work ")
        #expect(model.pendingGroup == "Client work")
        #expect(groups(model) == [nil, nil], "naming a group writes nothing down on its own")
        #expect(model.storedGroups == "{}", "and nothing a relaunch would bring back")

        // Dropped on its "drag a project here" row, which is the gap past the last project.
        model.move(model.projects[0].id, before: 2, into: "Client work")
        #expect(order(model) == ["b", "a"])
        #expect(groups(model) == [nil, "Client work"])
    }

    @Test func ungroupingTakesBackAGroupThatNothingIsInYet() {
        let model = model(["a"])
        model.newGroup(named: "Client work")
        model.ungroup("Client work")
        #expect(model.pendingGroup == nil)

        model.newGroup(named: "Client work")
        model.renameGroup("Client work", to: "Paid")
        #expect(model.pendingGroup == "Paid", "it is still the same offer, under a new name")
    }

    @Test func aProjectOpenedIntoAGroupInTheMiddleLandsAfterItsLastMember() {
        let model = model(["a", "b", "c", "d"])
        model.group(model.projects[0].id, as: "One")
        model.move(model.projects[1].id, before: 1, into: "One")
        model.group(model.projects[2].id, as: "Two")

        _ = model.open(URL(fileURLWithPath: "/tmp/yk-e"), into: "One")
        #expect(order(model) == ["a", "b", "e", "c", "d"])
        #expect(groups(model) == ["One", "One", "One", "Two", nil])
        #expect(adjacent(model))

        let after = AppModel(terminals: TerminalRegistry(), notify: { _, _, _ in })
        after.restore(model.storedProjects, groups: model.storedGroups)
        #expect(order(after) == ["a", "b", "e", "c", "d"], "a relaunch keeps where it was opened")
        #expect(groups(after) == ["One", "One", "One", "Two", nil])
        model.stop()
    }

    @Test func aProjectOpenedIntoTheLastGroupLandsAtTheEnd() {
        let model = model(["a", "b", "c"])
        model.group(model.projects[1].id, as: "One")
        model.group(model.projects[2].id, as: "Two")

        _ = model.open(URL(fileURLWithPath: "/tmp/yk-e"), into: "Two")
        #expect(order(model) == ["a", "b", "c", "e"])
        #expect(groups(model) == [nil, "One", "Two", "Two"])
        #expect(adjacent(model))
        model.stop()
    }

    @Test func aProjectOpenedIntoTheGroupNamedFromThePlusMenuFillsIt() {
        let model = model(["a", "b"])
        model.group(model.projects[0].id, as: "One")
        model.newGroup(named: "Client work")

        _ = model.open(URL(fileURLWithPath: "/tmp/yk-e"), into: "Client work")
        #expect(order(model) == ["a", "b", "e"], "where the empty group's placeholder was drawn")
        #expect(groups(model) == ["One", nil, "Client work"])
        #expect(model.pendingGroup == nil, "the real group replaces the placeholder")
        #expect(model.storedGroups.contains("Client work"), "and a relaunch brings it back")
        #expect(adjacent(model))
        model.stop()
    }

    @Test func aProjectOpenedWithNoGroupOrAGoneOneIsLooseAtTheEnd() {
        let model = model(["a", "b"])
        model.group(model.projects[0].id, as: "One")

        _ = model.open(URL(fileURLWithPath: "/tmp/yk-e"))
        // A group ungrouped while its sheet was up is not brought back.
        _ = model.open(URL(fileURLWithPath: "/tmp/yk-f"), into: "Gone")
        #expect(order(model) == ["a", "b", "e", "f"])
        #expect(groups(model) == ["One", nil, nil, nil])
        #expect(adjacent(model))
        model.stop()
    }

    @Test func theSheetFromAGroupJoinsItAndTheNextFromTheFileMenuDoesNot() {
        let model = model(["a", "b"])
        model.group(model.projects[0].id, as: "One")

        model.newProject(in: "One")
        #expect(model.creatingProject)
        _ = model.open(URL(fileURLWithPath: "/tmp/yk-e"), into: model.newProjectGroup)
        model.creatingProject = false
        // File > New Project… and the + menu open it with no group, whatever the last one had.
        model.newProject()
        _ = model.open(URL(fileURLWithPath: "/tmp/yk-f"), into: model.newProjectGroup)
        #expect(order(model) == ["a", "e", "b", "f"])
        #expect(groups(model) == ["One", "One", nil, nil])
        model.stop()
    }

    @Test func theSheetOffersEveryGroupInSidebarOrderWithTheEmptyOneLast() {
        let model = model(["a", "b", "c"])
        #expect(model.groupNames.isEmpty, "no groups, no picker")
        model.group(model.projects[2].id, as: "Two")
        model.group(model.projects[0].id, as: "One")
        model.newGroup(named: "Side projects")
        #expect(model.groupNames == ["One", "Two", "Side projects"])
        // A pending name a run already carries is that group, offered once.
        model.newGroup(named: "One")
        #expect(model.groupNames == ["One", "Two"])
        model.stop()
    }

    @Test func aGroupPickedInTheSheetIsWhereTheProjectLandsAndCancelForgetsIt() {
        let model = model(["a", "b"])
        model.group(model.projects[0].id, as: "One")
        model.newGroup(named: "Side projects")

        // Picked from the + menu's sheet, then cancelled: nothing moves, and the next sheet from
        // the + menu starts on no group again.
        model.newProject()
        model.newProjectGroup = "One"
        model.creatingProject = false
        #expect(groups(model) == ["One", nil])
        model.newProject()
        #expect(model.newProjectGroup == nil)

        model.newProjectGroup = "One"
        _ = model.open(URL(fileURLWithPath: "/tmp/yk-e"), into: model.newProjectGroup)
        model.newProject()
        model.newProjectGroup = "Side projects"
        _ = model.open(URL(fileURLWithPath: "/tmp/yk-f"), into: model.newProjectGroup)
        #expect(order(model) == ["a", "e", "b", "f"], "the group's last member, and the empty one's first")
        #expect(groups(model) == ["One", "One", nil, "Side projects"])
        #expect(model.pendingGroup == nil)
        #expect(adjacent(model))
        model.stop()
    }

    @Test func cancellingTheSheetFromAnEmptyGroupLeavesItWaiting() {
        let model = model(["a"])
        model.newGroup(named: "Side projects")
        model.newProject(in: "Side projects")
        model.creatingProject = false
        #expect(model.pendingGroup == "Side projects")
        #expect(groups(model) == [nil])
        model.stop()
    }

    @Test func theGroupsComeBackWithTheProjectsAfterARelaunch() {
        let before = model(["a", "b", "c"])
        before.group(before.projects[0].id, as: "Client work")
        before.move(before.projects[1].id, before: 1, into: "Client work")

        let after = AppModel(terminals: TerminalRegistry(), notify: { _, _, _ in })
        after.restore(before.storedProjects, groups: before.storedGroups)
        #expect(order(after) == ["a", "b", "c"])
        #expect(groups(after) == ["Client work", "Client work", nil])
    }

    @Test func aStoredGroupMapThatIsNotOneLeavesEveryProjectLoose() {
        let model = AppModel(terminals: TerminalRegistry(), notify: { _, _, _ in })
        model.restore(OpenProjects.encode(["/tmp/yk-a"]), groups: "[\"not\", \"a map\"]")
        #expect(groups(model) == [nil])
    }
}
