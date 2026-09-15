# Architecture

## Terminal lifetime

Each running agent's PTY lives inside an `AttentionTerminalView`, a SwiftTerm
`LocalProcessTerminalView`, and nothing on screen decides how long it lives (D13 in
`docs/refactor-plan.md`).

- **`TerminalRegistry`** (`Sources/YongkangUI/Terminal/`), owned by `AppModel` as `terminals`,
  creates one view per session when `ProjectModel.addSession` adds it. Closing the session or its
  project calls `terminate(_:)`. Typing into a session (`send(_:to:)`) and steering its CLI to a
  child agent (`showChild(_:in:)`) go through it too.
- **`TerminalHost`**, an `NSViewRepresentable`, **re-parents** the registry's view into the work
  area while that session's pane is on screen, and lets go of it when the pane goes.

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
- **Keep terminals in one window.** Moving to another `NSWindow` is untested. A second app window
  showing the same session would take the terminal from the first. With Metal on, it
  rebuilds the Metal view (`MacTerminalView.swift:220-226`, 583-592).
- **Hiding a terminal isn't free.** A detached terminal still parses its output on the main
  thread, as the hidden terminals in the old `opacity(0)` stack did.
