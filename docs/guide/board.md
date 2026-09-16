# Board

![The board, one column per project](../images/board.png)

`Board` is one column per project, its tasks reading downwards in build order. A task sits
under everything it waits on, so position is the dependency and no card has to spell it
out — the only `waits on` line left is for an id nothing resolves to, which shows in
amber, and is how you catch a typo in `depends_on`. Columns are bounded by how many
projects you have rather than by the longest chain, so the board never scrolls sideways.

Detail goes where it is worth something. A whole card is spent on the live edge of each
chain — what is being designed, what is waiting on your approval, what an agent is on,
what is blocked, and whatever could start next — and everything finished or still queued
behind something is one line. Clicking any of them picks it for a batch and dims what is
unrelated; the arrow on a card opens its own page.

The inspector carries the batch: what you picked, what came along as a blocker, and in
which order it will be built. The roadmap and projects are in the list column beside the
board, which no longer repeats the tasks the board is already showing.

Completed projects and tasks are hidden from the list, board and project task lists by
default. `Completed` in the toolbar, or `View ▸ Show Completed`, reveals them everywhere at once. A project counts as
finished when its own status says so, or when every task under it is done.
