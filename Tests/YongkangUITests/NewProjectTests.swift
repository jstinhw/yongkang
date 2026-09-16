import Foundation
import Testing

@testable import YongkangCore
@testable import YongkangUI

/// What the new-project prompt has to get right: an `@` tags something that is really
/// there, and a folder named in the prompt is where the project lands.
@Suite struct NewProjectTests {

    /// The folder the prompt box tags from:
    /// `SPEC.md .hidden design-notes.md designs/{logo.png, type/BODY.md} cases/{Alpha.md, alpha-two.md} cases-old.md`
    private func makeMentionRoot(in dir: URL) throws -> URL {
        let fm = FileManager.default
        let root = dir.appendingPathComponent("mention")
        try fm.createDirectory(at: root.appendingPathComponent("designs/type"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("cases"), withIntermediateDirectories: true)
        for file in [
            "SPEC.md", ".hidden", "design-notes.md", "designs/logo.png", "designs/type/BODY.md",
            "cases-old.md", "cases/Alpha.md", "cases/alpha-two.md",
        ] {
            try Data().write(to: root.appendingPathComponent(file))
        }
        return root
    }

    @Test(
        arguments: [
            ("build @des", "des", ""),
            ("build @des ", nil, "a finished tag is not still being typed"),
            ("a@b.com", nil, "an email address is not a tag"),
        ] as [(String, String?, String)])
    func queryIsTheTagBeingTyped(text: String, query: String?, why: String) {
        #expect(Mention.query(in: text) == query, Comment(rawValue: why))
    }

    @Test func matchesListOneLevel() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try makeMentionRoot(in: dir)

        #expect(
            Mention.matches("", root: root)
                == ["cases/", "cases-old.md", "design-notes.md", "designs/", "SPEC.md"],
            "folders keep their slash, dotfiles stay hidden")
        #expect(Mention.matches("designs", root: root) == ["designs/"])
        #expect(
            Mention.matches("designs/", root: root) == ["designs/logo.png", "designs/type/"],
            "tagging a folder lists one level down inside it")
        #expect(Mention.matches("nope", root: root).isEmpty)
    }

    // Tab, the way a shell does it: as far as the matches agree, then a level at a time.
    @Test func tabExtendsLikeAShell() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try makeMentionRoot(in: dir)

        var tab = "build from @de"
        #expect(Mention.extend(&tab, root: root))
        #expect(tab == "build from @design", "two matches only agree this far")
        #expect(
            Mention.extend(&tab, root: root),
            "and Tab stays in the box rather than moving focus")
        #expect(tab == "build from @design", "with nothing left to add, nothing is picked")
        tab += "s"
        #expect(Mention.extend(&tab, root: root))
        #expect(tab == "build from @designs/", "one match completes, a folder keeps its slash")
        let query = try #require(Mention.query(in: tab))
        #expect(Mention.matches(query, root: root).count == 2, "so the list is now what is inside it")
        #expect(Mention.extend(&tab, root: root))
        #expect(tab == "build from @designs/", "its two children agree on nothing further")
        tab += "t"
        #expect(Mention.extend(&tab, root: root))
        #expect(tab == "build from @designs/type/", "Tab walks down a level at a time")
        #expect(Mention.extend(&tab, root: root))
        #expect(
            tab == "build from @designs/type/BODY.md ",
            "and closes the tag on the one file at the bottom")
    }

    // A sibling that shares the whole folder name must not strand Tab on the folder.
    @Test func tabWalksIntoAFolderTheTagNames() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try makeMentionRoot(in: dir)

        var into = "build from @cases"
        #expect(Mention.extend(&into, root: root))
        #expect(into == "build from @cases/", "Tab walks into a folder the tag already names")
        #expect(Mention.extend(&into, root: root))
        #expect(into == "build from @cases/alpha", "and carries on inside it")
    }

    // Names are matched without regard to case, so what they agree on is read the
    // same way — otherwise Tab sits there doing nothing on `@cases/a`.
    @Test func tabAgreesWithoutRegardToCase() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try makeMentionRoot(in: dir)

        var mixed = "build from @cases/a"
        #expect(Mention.extend(&mixed, root: root))
        #expect(mixed == "build from @cases/alpha", "a lowercase name and a capitalised one still agree")
    }

    @Test func returnTakesTheFirstTag() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try makeMentionRoot(in: dir)

        var text = "build from @SP"
        #expect(Mention.accept(&text, root: root))
        #expect(text == "build from @SPEC.md ", "Return takes the first tag before it sends")
        #expect(!Mention.accept(&text, root: root), "and then gets out of the way")
    }

    @Test func aTagTypedAsAFullPathDrillsDown() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try makeMentionRoot(in: dir)

        var typed = "build from @\(root.path)/designs"
        #expect(Mention.extend(&typed, root: root))
        #expect(typed == "build from @\(root.path)/designs/", "a full path stays one")
        // The one that was broken: a full-path tag has to keep listing what is inside it,
        // not be re-rooted under the box's root and come back empty.
        #expect(
            Mention.matches("\(root.path)/designs/", root: root)
                == ["\(root.path)/designs/logo.png", "\(root.path)/designs/type/"],
            "a tag that is already a path of its own drills down from where it points")
        #expect(Mention.extend(&typed, root: root))
        #expect(typed == "build from @\(root.path)/designs/", "two children, nothing agreed")
        typed += "t"
        #expect(Mention.extend(&typed, root: root))
        #expect(typed == "build from @\(root.path)/designs/type/")
        #expect(Mention.extend(&typed, root: root))
        #expect(typed == "build from @\(root.path)/designs/type/BODY.md ")
    }

    /// The new-project box shows tags relative to where it browses; its agent runs in the new
    /// folder, so they are rewritten from there when the project is created.
    @Test func tagsAreRebasedOntoTheNewProject() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try makeMentionRoot(in: dir)
        let prompt = "build from @SPEC.md and @designs/type/\nmail a@b.com, ask @nobody, see @/etc/hosts"

        #expect(
            Mention.rebased(prompt, from: root, to: root.appendingPathComponent("photo-app"))
                == "build from @../SPEC.md and @../designs/type/\nmail a@b.com, ask @nobody, see @/etc/hosts",
            "a project beside the tags climbs one level; what is not a tag under root is untouched")
        #expect(
            Mention.rebased("read @SPEC.md", from: root, to: dir.appendingPathComponent("code/todo"))
                == "read @../../mention/SPEC.md",
            "a project named somewhere else climbs out as far as it has to")
    }

    // `@/De` is the folder you are tagging from, not `/dev` on the disk, and the
    // slash goes so what completes is a path that is really there.
    @Test func leadingSlashIsTheTaggingFolder() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try makeMentionRoot(in: dir)

        var rooted = "build from @/designs"
        #expect(Mention.matches("/de", root: root) == ["design-notes.md", "designs/"])
        #expect(Mention.extend(&rooted, root: root))
        #expect(rooted == "build from @designs/")
        // String expansion only: nothing under the real home folder is read.
        #expect(
            Mention.inserted("~/notes/") == NSHomeDirectory() + "/notes/",
            "a tag written from home is expanded — the agent gets a path it can open")
    }

    @Test func parseFindsTheNamedFolder() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try makeMentionRoot(in: dir)

        #expect(ProjectLocation.parse("a todo app") == nil, "nothing named means the form asks")
        let named = try #require(ProjectLocation.parse("a todo app in \(root.path)/todo"))
        #expect(named.parent.path == root.path)
        #expect(named.name == "todo")
        let folder = try #require(ProjectLocation.parse("put it in \(root.path), please"))
        #expect(folder.parent.path == root.path, "an existing folder is where projects live")
        #expect(folder.name.isEmpty, "the name is still missing")
        #expect(
            ProjectLocation.parse("read @\(root.path)/SPEC.md") == nil,
            "a tag is a reference, not a destination")
        #expect(
            ProjectLocation.parse("in \(root.path)/gone/todo") == nil,
            "a parent that is not there is not a location")
    }

    @Test func vacantSkipsAFolderAlreadyThere() throws {
        let dir = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let root = try makeMentionRoot(in: dir)

        #expect(
            ProjectLocation.vacant(in: root, named: "designs").lastPathComponent == "designs-2",
            "a folder already sitting there is not written into")
        #expect(ProjectLocation.vacant(in: root, named: "todo").lastPathComponent == "todo")
    }

    @Test func rejectionAcceptsAPlainName() {
        #expect(ProjectLocation.rejection("todo-app") == nil)
    }

    // A folder name is one component under the parent the user picked: nothing that walks
    // out of it and nothing hidden. `a/b` and `..` are added beyond the original two.
    @Test(arguments: ["../escape", ".hide", "a/b", ".."])
    func rejectionRefuses(name: String) {
        #expect(ProjectLocation.rejection(name) != nil)
    }
}
