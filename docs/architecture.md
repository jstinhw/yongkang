# Architecture

## Reading a project

Nothing the poll does touches a file on the main actor. Each open project owns a
**`ProjectReader`** (`Sources/YongkangCore/Watching/`), a Foundation-only actor holding one
project's reads: the notebook, each session's subagents and run records, the usage ledger, the
transcript on screen, and git. It answers with values. **`ProjectModel` is the only thing that
publishes them**, and only when they differ from what it already holds — an unchanged notebook
leaves every screen that reads it alone.

- **When it reads.** Each project watches its own folders with FSEvents (`FSEventWatcher`, in
  `Watching/`) and reads when one of them is written — about 300 ms after the first write of a
  burst, so the twenty files an agent just wrote are one read. `reloadNow()` is the read
  itself, which the watcher and the safety poll await; `AppModel.reload()` is the same read
  started and not waited for. Two callers await it on purpose: `AppModel.add`, which needs the
  card it just wrote before it can open it, and the window's `restore()`, which has no route to
  validate until a notebook has been read. The tests await it for the same reason.
- **The safety poll** behind the watchers is 30 s (`AppModel.start(polling:)`). FSEvents drops
  events on network volumes and across sleep, and a board that had quietly stopped updating
  would be a miserable bug to reproduce. It is also what covers a folder that did not exist
  when the watch was set up.
- **What is watched**, per project: its own tree, which holds `.notebook/` and everything git
  diffs, less `.git/objects` — rewritten by every git command an agent runs, and never a change
  to what `git status` says; and each live session's transcript folder, which its CLI keeps
  under its own home rather than in the project. `ProjectReader.watch(of:)` finds them, on each
  read and when a session is added, and the watcher leaves its stream alone when they come back
  unchanged.
- **Teardown is explicit**: `ProjectModel.stopWatching()` when the project is closed,
  `AppModel.stop()` when the app quits. A `@MainActor` owner's `deinit` is nonisolated, and
  `isolated deinit` needs macOS 15 while the app targets 14, so nothing else could do it.
- **Every open project is read in full**, not only the one on screen: its notebook, its run
  records and git. The sidebar says what each project's agents are waiting on you for, and a
  block or a finished task in a project you are not looking at is exactly what it is there to
  tell you. A resolved block is typed into its waiting session wherever it is; only in the
  project on screen does the window go there too.
- **A gate goes back to the agent that filed it.** A new file in `blocks/` whose `kind` is
  neither `demo` nor `proposal` is handed straight back to the session its `session:` names
  (`ProjectModel.nextGate`/`takeGate`, typed in by `AppModel.startGuide`), without asking and
  without the window moving. That session is stopped at its prompt having just written the
  file: it knows the task, and it is one thread and one sidebar row. A session of the gate's
  own, `Unblock <title>`, is the fallback for when that agent has gone. Most gates turn out to
  need nothing from the user; the ones that do are asked one step at a time, and you hear about
  it when the agent finishes its turn, like any other session. While it is being worked the
  gate is that session's row and is not counted as waiting on you (`Project.guide(of:)`,
  `blocksForUser`). One gate at a time per project, once each per run: an agent that gives up
  puts the gate back on your desk rather than being replaced. The page the block names in
  `url:` is shown beside the terminal (`GuideBrowser`), so the agent changes that field instead
  of opening a browser behind the app.
  `Project.guided` is in memory only, so a relaunch puts a half-worked gate back on the desk
  and hands it over once more — the resumed session is told again what it was on.
- **git** is asked at most every 6 s a project (`ProjectModel.repoReadIsDue`): an agent writing
  a file a second must not mean a repo-wide diff a second. The project on screen can be asked
  at once — when it is picked, and after a commit — and only its review screens count lines.
- **The usage screen has no beat of its own.** `ProjectReader.watch(of:)` hands back the sizes of
  the files it reads along with the folders to watch, `ProjectModel` publishes that fingerprint
  only when it differs, and `UsageBoard` reloads on it.
- **In flight.** `ProjectModel` keeps one notebook read and one session read at a time. A poll
  landing on top of a notebook read joins it; one landing on top of a session read starts
  nothing. Neither can pile up behind a slow disk.
- **Ordering.** Actors are reentrant, so a read suspended on git lets the next one past and
  answers can arrive in an order the reads did not start in. `refreshRepo` therefore numbers
  every repo read (`repoReads`/`repoShown`) and shows only an answer newer than what is on
  screen, so `approve` and `commit` come back with their own read or a later one.
- **Off-actor by being `async`.** `UsageLedger.load`, `AgentUsage.claudeQuota`/`codexQuota` and
  the usage screen's file-size checks are `nonisolated async`, so they run on the cooperative
  pool rather than on whichever actor asked.

`Tests/YongkangUITests/ProjectModelTests.swift` checks the claim rather than asserting it from
the code's shape: `aReloadDoesItsReadingOffTheMainActor` reads a 401-page notebook to completion
while the test, itself a main-actor job, spins without once giving the main actor up.
`FSEventWatcherTests` covers the watcher itself — a burst of forty writes is a handful of
wake-ups, `stop()` ends the stream and releases the box the C callback reads through, and a
folder that is missing or deleted while watched is not a crash. `ProjectWatchTests` covers the
two halves together: a page written into a notebook reaches the board with nothing on a clock,
and the safety beat still reads when the watch is taken away.

## How a message travels between projects

An agent never writes in another project's folder. When it needs a change there it writes a
message in its own notebook, `.notebook/messages/<slug>.md` (the shape is in
`Sources/YongkangCore/Notebook/Messages.swift`), and the app types it into a session there:

1. **Read.** `Messages.load` reads the folder on the same pass as `blocks/`, so a message reaches
   `NotebookSnapshot.messages` the way a block does: the watcher sees the write, the read picks
   it up. A file with no `to`, or a `session`/`reply_to` that is not a session id, is skipped.
2. **Routed** (`ProjectModel.deliveries`, `ProjectModel+Messages.swift`). `to` is resolved against
   the sender's folder and matched to an open project. A `reply_to` naming a session running
   there is typed into that session as `NotebookFormat.incomingMessage`, which ends with the
   answer's frontmatter filled in. Anything else goes to that project's Product as
   `asked\n` + the same text: typed into the one running, or the prompt of one `startProduct`
   opens, let into the sender's folder to read it. Its board then shows a `BoardRequest` whose
   `from` is the asking folder, so what Product files there is marked new and its own Approve
   and commit lands only its own files. A `to` naming no open project is answered in the
   sender's session in one line (`NotebookFormat.undeliveredMessage`); with the sender gone
   too, the message waits for a read that finds the project open.
3. **Typed** (`AppModel.deliverMessages`), after every project has been read, by
   `TerminalRegistry.send`. The window never moves, in either project: the conversation is two
   agents', each in its own terminal, and the sidebar shows the session that opened or woke.
4. **Once.** The app never writes a message file, so it remembers what it delivered itself:
   `AppModel.deliveredMessages`, by `ProjectMessage.deliveryKey` — the file plus a hash of what
   is in it, so a slug reused for a new message is delivered again and a message read again is
   not. `RootView` keeps the set in `@AppStorage("deliveredMessages")` and restores it before
   the first read of a launch.

`ProjectModel.waitingOn` is the sender's side: a session that wrote to another project and has
had no answer typed in since, with that project's folder. It and `BoardRequest.from` are in
memory only, so a relaunch forgets who asked and who is waiting until the next message.
`Tests/YongkangUITests/MessageDeliveryTests.swift` covers the round trip, the two boards'
commits, and typing once across a relaunch, with `/bin/sh` standing in for the CLIs.

## Diagnostics

`Log` (`Sources/YongkangCore/Diagnostics/`) is `os.Logger` under the subsystem
`ai.yongkang.Yongkang`, with the four categories D14 names — `notebook`, `git`, `terminal`,
`providers` — and `online`, for the app's own requests (below). `log show --predicate 'subsystem == "ai.yongkang.Yongkang"'` reads it back. The
readers that used to swallow a failure with a bare `try?` go through `Log.contents(of:)` or
their own `catch`, so a parser that stopped matching a new CLI version says so instead of
drawing an empty pane.

**Only paths, counts, exit statuses and error descriptions are ever logged.** Never a file's
contents, a prompt body, a transcript line, git's own output or a process's command line, and
no log line leaves the Mac. Log the unexpected, too: a file a CLI has not written yet, `git status`
exiting 128 in a folder nobody has made a repo, and a read the window cancelled are the normal
case on every read and say nothing.

### What goes online

`Sources/YongkangUI/Online/` is the only code that talks to a server. Updates and analytics run
only in a Release build: Info.plist carries `YKConfiguration = $(CONFIGURATION)`, and
`Online.isRelease` is false under `swift test`, in `shots` and in `make run`. Each part is off
while its key in `App/Config/Info.plist` is empty.

- **`Updates`**: Sparkle 2, checking the appcast daily, downloading in the background, and
  handing over a "Restart to Update" rather than opening a window.
- **`Account`**: optional GitHub sign-in through Supabase Auth, PKCE in
  `ASWebAuthenticationSession`. The user is kept; the tokens are not.
- **`Analytics`**: PostHog's capture API, one POST per event. An event says only *that*
  something happened, with an agent's kind or a count, under the same rule as the log: no path,
  name, prompt or file contents. **Share Usage Analytics** in the app menu turns it off.

[`docs/release.md`](release.md#what-goes-online) lists every event and what the website's
privacy page has to say.

## Nothing is read while a screen draws

A view body derives; it never opens a file or runs detection. What that costs is paid once, by
whoever read the notebook:

- **A card carries its page's Markdown** (`NotebookCard.body`, and `SummaryTask.body` through
  the summary). The project, task, page and review screens draw a card's text from the snapshot.
  `NotebookEditor` is the exception: it edits the raw file, frontmatter and all, so it reads
  that file — off the main actor, in a `.task`.
- **Service detection is a value.** `Service.plan` answers with `ServicePlan`s that already say
  whether the folder is on disk and whether a service has a front end. `ProjectModel.services`
  is detected when the cards change.
- **`ChangeSummary` is stored**, re-derived when the snapshot, the sessions or the repo change,
  and published only when it differs. The sidebar's `Project.agentRows` takes it rather than
  deriving its own, for every open project on every redraw — which is why it is a lookup over
  values already read, and never a read.
- **Anything that still has to read** does it in a `.task` that bails on `Task.isCancelled`
  before assigning — the diffs in `ChangeReview` and `TaskReview`, and the tag list in
  `PromptField`.

## How the window is composed

One window, and three things side by side inside it (`RootView.chrome`):

```
HStack
├── Rail                       64pt, fixed: Board, Agents
├── ProjectSidebar             @AppStorage listWidth, 180–560, opens at 268; absent while listHidden
├── ListDivider                1pt line, 9pt grip: drag to resize, past the narrowest to shut
└── work                       Usage (every project's), screen(for:) the picked project, or NothingPicked
                               .navigationTitle + .navigationSubtitle + .toolbar
```

- **Every project at once.** The sidebar lists every open project with its running sessions
  under it — `Project.agentRows`, in Core, so the sidebar and the project's Agents page read one
  rule. The sidebar and the page list only `isRunningSession` rows; the rest, what a session that
  has exited left waiting on you, only counts on the project and is opened from the board. Under
  Board a project lists its tasks that are not idle instead — `Project.taskRows`, the board's own
  states for a task — and a task row opens its page, block or review without leaving the board.
  **Usage** is every project's, so `AppModel.openUsage()` opens it with none entered, and the
  window draws it before any project's screen. Picking
  a row is `AppModel.enter(_:at:)`: that project becomes the one the selection lives in,
  on the route the row names. The section stays, so picking a project on the board shows its
  board. `entered` is still the one project a `Route` means something in; nothing picked is
  `entered == nil`, and the screen says to pick something.

- **The rail stays outside.** The rail is the only navigation that never changes — it is what
  makes the window recognisable. It is also drawn above the sidebar (`zIndex(1)`), because
  its hover labels hang past its own width.
- **The sidebar is a pane with a divider of our own, not a native one.** On macOS 26 a
  `NavigationSplitView` sidebar floats as an inset glass panel — 8pt clear of the rail, the top
  and the bottom, with a shadow over the screen — and no split view style turns that off, so
  the window read as having a gap beside the list. `HSplitView` put the panes edge to edge but
  opened the list at its minimum and handed back no width, so the list could not be dragged
  narrower than it opened, dragged shut, or reopened at the width it was left at.
  `ListDivider` does those: it is the list's edge, stores the width in `@AppStorage("listWidth")`,
  follows the pointer down to the list's narrowest and shuts it the moment the pointer goes past
  — no hold at the narrowest with the pointer carrying on, the gap a collapsible `NSSplitView`
  pane leaves — and opens it again under the pointer when dragged out from the rail.
  `ListDivider.dragged(from:by:)` is that rule, which `ChromeTests` pins. What is still missing
  from a native sidebar: the collapse animation and a VoiceOver structure that says "sidebar".
- **The top bar is the window's toolbar.** `RootView+Toolbar.swift` builds it: the screen's
  name is `.navigationTitle`, the project (or, on the working tree, the branch) is `.navigationSubtitle`,
  and what the old bar drew on its right is one `ToolbarItemGroup`. The bar was 56pt; the
  title bar is the system's ~52.
- **One list toggle.** `RootView` puts its own in the toolbar's navigation slot, so the
  toggle is ours to label and to disable. The rail's own toggle is gone with it. ⌘\ lives on
  its menu item (below), not on this button — the button keeps the `.help` that names the
  shortcut.
- **No width math.** Nothing adds `railWidth + listWidth` up to position a pane, the way the
  pre-3.4 code did. Each pane is laid out by its container, and the terminal with it.
- **The inspector is still hand-built** (`Inspector`, in `Rail.swift`), not `.inspector()`.
  On macOS 26 a native inspector is an
  `NSContainerConcentricGlassEffectView` composited by the window server, which
  `NSView.cacheDisplay` photographs as a white rectangle. Every
  screen with an inspector would lose that pane from its shot, and the shots are how this repo
  checks a layout. See the `ponytail:` marker on `Inspector`.
  **Decided in 5.2, not deferred by accident:** keep the pane hand-built while it is the only
  version anyone can look at. What would change the answer is a capture path that sees glass,
  or the shots composing each screen's inspector content the way `console` already composes the
  list column. Until one of those exists, a native inspector buys resize behaviour and costs
  the gate on the nine screens that draw one: the board, a task, a demo, a block, an agent, a
  subagent, a team member, a task's review and the working tree's — the last two opening from
  an agent's row in the sidebar.

## The menu bar

`YongkangCommands` (`Sources/YongkangUI/App/Commands.swift`) is the scene's `.commands`, and
every keyboard shortcut in the app is one of its items. A shortcut hung on a button only
answers while that button is drawn, and a toolbar item can scroll out of a narrow window
taking its shortcut with it; a menu item answers from any screen, and the menu bar is what
Full Keyboard Access and VoiceOver read an app through.

| Menu | Items | Lit when |
|---|---|---|
| **Yongkang** | Check for Updates… / Restart to Update to X | a Release build with an update key |
| | Sign In with GitHub… / Sign Out · Share Usage Analytics | a Supabase project is set · always |
| **File** | New Project ⇧⌘N · Open Project ⌘O | always |
| | Close Project · Reveal in Finder | a project is picked |
| **View** | Board ⌘1 · Agents ⌘2 · Hide List ⌘\ | always |
| | Show Completed | a project is picked |
| **Agent** | New Agent… ⌘N | always |
| | New Session · New Session With ▸ · New Terminal ⌘T | a project is picked |
| | Assign Task · Assign Task To ▸ | `AppModel.assignableTask` is not nil |
| | Product Review · New Request… ⌥⌘N | the project has a notebook and no Notebook Setup is writing it |
| | New Team Member… | the project has a notebook |
| **Notebook** | New Roadmap Entry… · New Milestone… · New Task… | a project is picked |
| | New Memory… | the selection sits in a milestone |

- **Nothing is ever hidden.** An item the window cannot act on is disabled, so the shortcut it
  carries stays readable and the menu keeps the same shape on every screen.
- **One binding per shortcut.** ⌘\ came off the toolbar's list toggle when its item landed,
  and the toggle keeps its `.help`, which still names the shortcut. ⌘N is New Agent's, since
  putting an agent on work is what the window is for; New Project moved to ⇧⌘N. The sidebar's
  New Terminal rows and the empty screen's two buttons carry no shortcut of their own. The
  toolbar starts nothing new — no `+` menu, no New Agent button: the File, Agent and Notebook
  menus are the one place to look for anything new. There is no Go menu: with every project in the sidebar there is no page of projects to go back to.
- **Assign Task is the selected task**, not the board's ticked batch. Those ticks are
  `NotebookBoard`'s own `@State`, which no menu can see; picking several is still the board's
  job. `AppModel.assignableTask` is the rule — a task card, not done, not already with a session —
  and it is the same one `TaskDetail`'s button is disabled by, so `MenuCommandTests` checks it
  with no window.
- **Replacing `.newItem` is also what drops New Window,** which is why the group was there
  before there was anything to put in it.
- **What is deliberately not here:** a shortcut that means nothing off its own screen. ⌘S
  saves in `NotebookEditor`, and a sheet's default and cancel actions belong to that sheet.
  Hoisting those would put a permanently-disabled item in the menu bar for every other
  screen, which is worse than not having one.

## What comes back after a relaunch

`@AppStorage("openProjects")` reopens the folders. `@SceneStorage` in `RootView` keeps the
rest of the address — `enteredProject` (a path), `section`, and `route`, which is
`Route.stored`: the route through `Codable`, as one string. That shape is deliberately not a
format anything else reads or writes, so a string that no longer decodes is simply no route.

`AppModel.restore(entered:section:route:)` (`Model/AppModel+Restore.swift`) enters the project
and applies the two. It runs after the first notebook read is awaited, not before: a route
names a card, a block or a team member, and a `ProjectModel` holds none of those until it has
read one — validated any earlier, every stored route would look stale on every launch.

**A stale route degrades to the section's default, never to an empty screen.**
`restorable(_:in:)` is what decides:

- A card, block, entry or team member has to still be there, and a card has to still be the
  kind the route says.
- A session route holds when that session came back (below); a subagent route never does,
  since subagents are read off disk later.
- Review, review-task and preview routes count as stale too, because git and service detection
  have not been read when the window restores. The next task to finish opens its own review
  once that read lands, which is the same answer a moment later.

**The agents come back too.** `@AppStorage("openSessions")` keeps each open project's agent
sessions (`OpenSessions`): id, title, the line that started it, its tasks and the folders it
reads. It is written whenever a session is added or closed, so it survives a crash as well as
a quit. `AppModel.resumeSessions` starts each again before the route is restored, on its own
conversation where its CLI kept one — `claude --resume`, `codex resume <thread>`,
`grok --resume`, `agy --continue` (each provider's `resume`) — and on the line it was first
started with where it kept nothing, which is a session that never got going. Coming back with
its task ids is what keeps finished, unapproved work in Review: a task counts as handed out
only while a session, a work record or a block names it. Services are not kept. The one
exception is a waiting demo: its page died with the designer's session, so after the first read
`AppModel.serveDemos()` runs each local demo's `serve:` command again in a `Serve <task>`
terminal, only when its address does not answer, and only a command the user has already let
that project run (`ProjectModel.trustsServe`). `serve:` is read from a file in the project, so
an unapproved one is never run at launch: opening its demo asks first, showing the command.
That terminal is not stored either; the next launch asks the same question.

Anything that fails drops the route, and `openSectionDefault()` fills it with the section's own
page for the project: its board, or its running sessions side by side. `RestorationTests` covers the
round trip, an unparseable string, a card deleted while the app was closed, a dead session,
and a resolved block.

The list column's **width** is not restored. SwiftUI takes `min`/`ideal`/`max` for a split
view column and hands back no binding for the width the user dragged it to, so `@SceneStorage`
has nothing to store; `Theme.listWidth` is the width it opens at, every launch. Whether it is
*collapsed* does persist, in `@AppStorage("listHidden")` — until a rail icon is clicked, which
asks for that section's list and so brings the column back.

## Terminal lifetime

Each running agent's PTY lives inside an `AttentionTerminalView`, a SwiftTerm
`LocalProcessTerminalView`, and nothing on screen decides how long it lives (D13 in
`docs/refactor-plan.md`).

- **`TerminalRegistry`** (`Sources/YongkangUI/Terminal/`), owned by `AppModel` as `terminals`,
  creates one view per session when `ProjectModel.addSession` adds it. Closing the session or its
  project calls `terminate(_:)`. Typing into a session (`send(_:to:)`) and steering its CLI to a
  child agent (`showChild(_:in:)`) go through it too, and so does answering a folder's question
  once: the keys the user pressed to answer a trust question in one session are typed into
  every other session of that CLI in the same folder that is still asking it.
- **`TerminalHost`**, an `NSViewRepresentable`, **re-parents** the registry's view into the work
  area while that session's pane is on screen, and lets go of it when the pane goes. Since 5.2
  the work area is the split view's second pane, which is a plain hosting view like the
  `VStack` before it — the terminal is still pinned to its container's edges by constraints,
  and collapsing the list is one more resize (verdict 3 below).

A spike (PR 2.1) checked whether re-parenting is safe, before the registry was built.
`Tests/YongkangUITests/TerminalReparentingTests.swift` runs real `/bin/sh` children inside
`AttentionTerminalView`s. It moves them between panes of different sizes in an offscreen
`NSWindow`, and through `TerminalHost` inside an `NSHostingView`. It stays as the regression test
for that behaviour, beside `TerminalRegistryTests.swift`. Source lines below are from SwiftTerm
1.18.0 (`Package.resolved`), under `.build/checkouts/SwiftTerm/Sources/SwiftTerm/`.

### Verdicts

1. **Removing the view, or SwiftUI dismantling its host, doesn't touch the process.**
   - `LocalProcessTerminalView` (`Mac/MacLocalTerminalView.swift`, the whole file) doesn't
     override `viewDidMoveToWindow`, `viewDidMoveToSuperview`, `removeFromSuperview` or
     `deinit`.
   - Its only path to the process is `terminate()` at lines 193-195, which calls
     `LocalProcess.terminate()` (`LocalProcess.swift:561-587`: SIGTERM, then close the I/O).
   - `TerminalView.viewDidMoveToWindow` (`Mac/MacTerminalView.swift:583-592`) only starts or
     stops the macOS 26 mouse-move fallback (1144-1166). It also rebinds the Metal renderer,
     but only when Metal is on, and the app never calls `setUseMetal`.
   - `TerminalView.deinit` (606-615) only removes observers and a timer.
   - No SwiftTerm Mac or Apple view overrides `viewDidMoveToSuperview` or `removeFromSuperview`.
   - Tests: `detachedTerminalKeepsItsProcessAndReadsOutput` checks `kill(pid, 0)` and
     `process.running` after `removeFromSuperview()`.
     `swiftUIHostBorrowsTheTerminalAcrossRemovalAndResize` checks the same after
     `dismantleNSView`.
2. **Output keeps flowing while detached, and the child never blocks on it.**
   - The read loop is `DispatchIO` on a private queue (`LocalProcess.swift:555-557`, re-armed
     at 338-342). It hands chunks to the main queue (134-153) and then to
     `delegate?.dataReceived` (199).
   - `dataReceived` is `feed(byteArray:)` (`MacLocalTerminalView.swift:207-209`, then
     `Apple/AppleTerminalView.swift:2597-2602`). None of it depends on a window or superview.
   - Reads pause only when more than 4 MB is waiting for the main queue (`LocalProcess.swift:96-107`).
     That limit is about a busy main thread, and applies whether or not the view is in a window.
   - Tests: `detachedTerminalKeepsItsProcessAndReadsOutput` sees ticks reach the buffer while
     detached, and still there after re-attaching.
     `detachedTerminalDrainsAFloodWithoutBlockingTheChild` detaches before any output is read.
     Its child still finishes writing `seq 1 200000`, far more than a PTY buffer holds.
3. **Re-attaching into a different size re-lays out the terminal, and the child gets SIGWINCH
   with the new size.**
   - Auto Layout sets the frame, which calls `setFrameSize` (`MacTerminalView.swift:1041-1061`).
     That calls `processSizeChange` (`AppleTerminalView.swift:353-374`), which resizes the
     `Terminal` and calls `sizeChanged`.
   - `LocalProcessTerminalView.sizeChanged` (`MacLocalTerminalView.swift:104-112`) sets the
     PTY size with `TIOCSWINSZ`, and the kernel sends the child SIGWINCH.
   - Tests: `reattachingIntoADifferentSizeResizesTheTerminalAndTheChild`. A `trap … WINCH`
     in the child prints `stty size`, which must match the terminal's rows and columns after
     each move.
4. **After re-attaching, the view can become first responder and takes typed input,** but
   focus isn't restored by itself.
   - AppKit resigns a first responder that leaves the window. `acceptsFirstResponder` is
     always true (`MacTerminalView.swift:1105-1109`), and `becomeFirstResponder` and
     `resignFirstResponder` (1085-1103) only update focus state.
   - Tests: `reattachedTerminalTakesFocusAndTypedInput` covers two input paths. `send(txt:)`
     reaches the process, and so does a real `keyDown` sent through `NSWindow.sendEvent`.
5. **Attention detection is unaffected.**
   - `onAttention` and `attentionReason` are plain members of `AttentionTerminalView`. The check
     is a main-queue work item started from `dataReceived`, which runs as long as the process
     does (point 2).
   - Tests: `attentionSurvivesDetachAndReattach`. The trust question appears while the view is
     detached, and the notice fires. After re-attaching into a smaller pane, the notice doesn't
     repeat. Answering after re-attaching clears it.
6. **The real SwiftUI path works.**
   - The host is a container `NSView` from `makeNSView`, with the terminal pinned to its edges.
   - The test removes the host, inserts it into a smaller slot, and moves it straight from one
     slot to the other in a single update.
   - The process survives each time. The terminal gets exactly the slot's frame.
   - The PTY is resized once per insert into a new size, not on removal, and never to a
     transient size while SwiftUI lays out.
   - Tests: `swiftUIHostBorrowsTheTerminalAcrossRemovalAndResize`.

### Recommendation the registry followed

**Re-parent, as D13 proposes.** Every question above passed, so the spike didn't build D13's
fallback, one permanent host view positioned from outside. If it's ever needed, it resizes
through the same `setFrameSize` path as point 3.

### Constraints the registry and host respect

- **The registry must hold the view strongly, and end a session only with `terminate()`.**
  - The view is the only owner of its `LocalProcess` (`MacLocalTerminalView.swift:69`).
  - When the view is deallocated, `LocalProcess.deinit` closes its I/O but deliberately
    doesn't signal the child (`LocalProcess.swift:349-363`).
  - In a throwaway run, dropping the last reference freed both the view and the process. The
    child was still running 3.5 s later, with nothing reading it and no pid left to stop it.
- **Keep a strong reference to `processDelegate`.** The view holds it `weak`
  (`MacLocalTerminalView.swift:99`), so the registry must own whatever object receives the
  exit and size callbacks.
- **The host never terminates.** Only `TerminalRegistry.terminate(_:)` calls `terminate()`. The
  key-down `NSEvent` monitor is the registry's too, one for every terminal.
- **`dismantleNSView` removes only what its own container still holds,** meaning
  `container.subviews`, never the terminal by reference.
  - When a session moves between panes in one update, SwiftUI calls `makeNSView` on the new
    host before `dismantleNSView` on the old one. By then the new container has already taken
    the terminal.
  - If dismantle removed the terminal by reference, the pane would stay blank. The SwiftUI test
    fails that way when dismantle is written like that.
- **In `makeNSView`, pin with constraints; don't set a frame first.**
  - Set `translatesAutoresizingMaskIntoConstraints = false`, then add the view to the new
    container. `addSubview` removes it from the old container.
  - The new container starts at 0x0, but the terminal only sees one frame change, straight to
    the slot's size.
  - A 0x0 size is ignored (`AppleTerminalView.swift:354`), but a tiny non-zero size isn't. Such a
    size gives the child a 2x1 window and reflows the buffer (`Terminal.swift:6656-6659`), so
    don't animate a host up from zero size.
- **Request focus after the terminal is in the window.**
  - `makeNSView`, and the first `updateNSView` after it, run before the container has a
    window. `TerminalHost` defers `window.makeFirstResponder(terminal)` with
    `DispatchQueue.main.async`.
  - Check `window.firstResponder === terminal`, not the return value.
    `makeFirstResponder` also returns true for a view that isn't in the window.
- **Reap what you terminate.** `terminate()` cancels the exit watcher before the child exits
  (`LocalProcess.swift:586`, then 269-277).
  - As a result, `processDelegate.processTerminated` never fires for a session the app
    terminates.
  - Unless something calls `waitpid`, the child stays a zombie until the app quits, as it did
    before the registry.
  - So `TerminalRegistry.terminate(_:)` forgets the session itself and reaps the pid off the
    main thread, with SIGKILL if the child is still there after 5 s. `onExit` only covers a child
    that exits by itself, and SwiftTerm reaps that one, so closing its session sends nothing to a
    pid that may have been reused.
- **A clean exit closes its session.** A CLI that exits 0 was quit by the user (Ctrl+C, `/exit`),
  so its session goes and the window returns to the board. Any other exit keeps the session,
  marked exited, with a notice in the terminal saying how it ended.
- **Keep terminals in one window.** Moving to another `NSWindow` is untested. A second app window
  showing the same session would take the terminal from the first. With Metal on, it
  rebuilds the Metal view (`MacTerminalView.swift:220-226`, 583-592).
- **Hiding a terminal isn't free.** A detached terminal still parses its output on the main
  thread, as the hidden terminals in the old `opacity(0)` stack did.
