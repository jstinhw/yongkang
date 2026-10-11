import Testing

@testable import YongkangCore

/// The words of a `run:` line as the shell hands them over, which is what the command pane
/// resolves to files.
@Suite struct ShellWordsTests {
    private func words(_ line: String) -> [String] {
        ShellWords.split(line, home: "/Users/you").map(\.text)
    }

    @Test func quotesAndBackslashesKeepAWordWhole() {
        #expect(words(#"bash "/tmp/my dir/x.sh" --go"#) == ["bash", "/tmp/my dir/x.sh", "--go"])
        #expect(words(#"cat /tmp/my\ dir/x 'a b'"c"d"#) == ["cat", "/tmp/my dir/x", "a bcd"])
        #expect(words(#"echo """#) == ["echo", ""], "an empty quoted word is still a word")
    }

    @Test func onlyHomeIsFilledInAndEverythingElseSaysItExpands() {
        let split = ShellWords.split(#"x ~/a "$HOME/b" ${HOME}/c '$HOME/d' $S/e *.sh ~other"#, home: "/Users/you")
        #expect(
            split.map(\.text) == [
                "x", "/Users/you/a", "/Users/you/b", "/Users/you/c", "$HOME/d", "$S/e", "*.sh", "~other",
            ])
        #expect(split.map(\.expands) == [false, false, false, false, false, true, true, true])
    }

    @Test func theFirstWordOfEachCommandIsTheProgram() {
        let split = ShellWords.split("A=1 sudo -E deploy --go && git push; (./run.sh) | tee log > out", home: "/h")
        #expect(split.filter(\.isCommand).map(\.text) == ["sudo", "deploy", "git", "./run.sh", "tee"])
    }

    @Test func aCommentEndsTheLine() {
        #expect(words("ls -la # rm -rf /") == ["ls", "-la"])
        #expect(words("echo a#b") == ["echo", "a#b"], "a # inside a word is not a comment")
    }
}
