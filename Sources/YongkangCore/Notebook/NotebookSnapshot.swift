import Foundation

/// What one project's `.notebook/` said at the last read, as one immutable value. The poll
/// reads a fresh one and the project keeps it only when it differs, so a notebook nobody
/// wrote to leaves every screen that reads it alone.
package struct NotebookSnapshot: Equatable {
    package let entries: [NotebookEntry]
    /// Frontmatter for the board, read only while you are inside the project.
    package let cards: [NotebookCard]
    /// What the agents need from the user before they can go on, read the same way.
    package let blocks: [UserBlock]
    /// The Engineering Lead's named specialists, from `.notebook/team/` (shipped defaults
    /// until that folder exists).
    package let team: [TeamMember]
    /// Every lead's run records on disk, by session id — including leads that are closed or
    /// ran before a relaunch, whose finished work may still be waiting for review.
    package let records: [UUID: LeadCoordination]

    package init(
        entries: [NotebookEntry] = [],
        cards: [NotebookCard] = [],
        blocks: [UserBlock] = [],
        team: [TeamMember] = Team.defaults,
        records: [UUID: LeadCoordination] = [:]
    ) {
        self.entries = entries
        self.cards = cards
        self.blocks = blocks
        self.team = team
        self.records = records
    }

    /// The notebook under `root` read again. The file list is always read; `frontmatter`
    /// adds the cards, blocks and team, and `records` the run records. What a read skips
    /// is carried over from this snapshot, so a cheap read never blanks the board.
    package func reread(root: URL, frontmatter: Bool, records readRecords: Bool) -> NotebookSnapshot {
        let entries = NotebookLoader.load(root: root)
        guard frontmatter else {
            return NotebookSnapshot(entries: entries, cards: cards, blocks: blocks, team: team, records: records)
        }
        return NotebookSnapshot(
            entries: entries,
            cards: NotebookIndex.load(root: root),
            blocks: Blocks.load(root: root),
            team: Team.load(root: root),
            records: readRecords ? LeadCoordination.all(root: root) : records)
    }
}
