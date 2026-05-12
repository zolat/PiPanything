# Retro: 2026-05-11 00:46
Session: aad69221-675a-4bcf-b5ed-02a0f67946dc
Topic: overlay-resize-bounds
Branch: main
CWD: /Users/zolat/projects/PiPanything
Duration: ~75 min
Key files: PiPanything/Sources/App/OverlaySession.swift, PiPanything/Sources/Features/Settings.swift, PiPanything/Sources/Features/StatusBarController.swift

## Context
User asked for a min size so the overlay can't be made invisible, plus a higher configurable max. Most of the plumbing (Settings.maxOverlayDimension, status-bar submenu, applyMaxDimension broadcast) already existed in stashed work from a sibling session — but mid-session a `feat/tabs` merge + a stash pop fired off concurrently, leaving conflict markers in `OverlaySession.swift` / `AppDelegate.swift`. Eventually the conflicts were resolved out-of-band (commit `dfb88f6`), and my net contribution narrowed to belt-and-suspenders `NSWindow.minSize` / `maxSize` so AX/scripting paths can't bypass the resize-handle clamp.

## Learnings
- `ResizeHandle`'s clamp only catches user drags; `window.setFrame` (and AX `set size`) walks straight past it. `NSWindow.minSize` / `maxSize` plus their `contentMin/MaxSize` siblings are the belt-and-suspenders that catch every path.
- AX `set size` honors `NSWindow.minSize`/`maxSize` but does NOT preserve aspect — it sets w/h independently. The resize handle is the only aspect-preserving path.

## Dead ends
- Built and verified my own version of the feature on top of pre-merge code — entire diff got nuked when a `feat/tabs` branch was merged + stash popped underneath me. Re-investigation cost ~20 min of the session.

## Mental model corrections
- I assumed the working tree was stable for the duration of the session. It isn't — sibling Claude sessions and user-side git operations can rewrite files mid-task. When the file-state-changed errors started firing, my first instinct was "linter ran"; the real cause was a concurrent merge.
- Re-read `git status` whenever a Read result contradicts what I just wrote. The stale-SourceKit warning in CLAUDE.md ("trust xcodebuild") looks like the same shape but masks a totally different problem (a real merge happened).

## Conventions and decisions
- For overlay size constraints: the resize handle owns aspect-preserving user clamping; `NSWindow.minSize`/`maxSize` own the bypass-proof floor/ceiling. Both should be kept in sync via `applyMaxDimension`.

## What would have helped at the start
- A heads-up that another session was mid-stash-pop on the same files. `git status` at session start would have flagged unmerged paths if I'd looked, but the auto-injected gitStatus snapshot was already stale by the time I read it.

## Capability gaps
- Gap: programmatic verification of the user-drag clamp (the only aspect-preserving path).
  - Workaround: AX `set size` smoke test, which proved the NSWindow guards but not the handle's aspect math.
  - Suggested unblock: a `PIP_TEST_DRAG_RESIZE` env hook that synthesizes mouseDown/mouseDragged on the handle and reports the resulting frame, exercising the same path a real cursor would.

## Processed: 2026-05-11

### Actions taken
- Rewrote the project `CLAUDE.md` "Shipping" section: `/feature` worktree flow is now the default for features and bug fixes beyond a few lines; main is reserved for trivial edits and read-only work. Directly addresses the concurrent-merge incident this retro surfaced.
- Added "Parallel Development" subsection to `~/.claude/CLAUDE.md` so the agent surfaces the worktree question on any project where parallel sessions begin appearing.
- Folded the `PIP_TEST_DRAG_RESIZE` suggested-unblock into the new "Headless verification toolkit" BACKLOG track (item 3).

### Items discussed but not acted on
- Heads-up about concurrent stash pops mid-session — partly mitigated by the worktree-default rule above; agent-side drift-detection wasn't added because isolation is the better solution than detection.
