# agent-pet design contract

A macOS overlay pet that appears along the bottom of the screen only when an enrolled coding
agent session has finished its turn and is waiting on Xander. Sessions opt in one at a time, with
the `/pet` skill in Claude Code or the `/pet` command in pi. Nothing is global: a session that
never ran `/pet` has no hooks, no state and no pet.

## Layout

```
~/other-code/agent-pet/
  DESIGN.md, README.md         this contract, and install + usage
  Package.swift                swift-tools 5.9, one executable target `agent-pet`, macOS 14+
  Sources/agent-pet/
    main.swift                 argv dispatch to the commands below
    Commands/                  one file per subcommand, plus flag parsing and feedback
    State/                     PetSessionStore, ClaudeSessionDirectory, tmux run + color sync
    Overlay/                   NSApplication daemon, PetWindow, PetAnimator, lanes, clicks
    Sprites/                   SpriteContract (fixed), PixelRenderer, ClaudeSprite (claude8Bit art), SpritePackLoader, SpritePackRegistry
  skill/pet/SKILL.md           symlinked to ~/.claude/skills/pet/SKILL.md
  pi-extension/agent-pet.ts    symlinked to ~/.pi/agent/extensions/agent-pet.ts
  sprites/<pack>/              shipped sprite packs, see "Sprite packs"
  install.sh, uninstall.sh     build, symlink binary, skill and extension, install packs
```

## Runtime state, `~/.agent-pet/`

```
~/.agent-pet/
  sessions/<session_id>.json   one PetSession record per enrolled session
  sessions/<session_id>.lock   the flock file that serializes writers of that record
  sprites/<pack>/              installed sprite packs
  daemon.pid                   pid of the running overlay daemon
  daemon.log                   daemon stderr
  hooks.log                    one line per handled hook event
```

State lives outside `~/.claude/` because the tool is agent-neutral: Claude Code is one adapter
and pi is another. The record carries everything the daemon needs, so Claude session enrichment
is a fallback, never a requirement. The CLI writes each record and the daemon reads it, whole
file on every write (temp file in the same dir, then rename).

```json
{"sessionId":"1dd88945-2a6c-4903-88f8-c8837c6cd8d3","enabled":true,"visible":false,
 "nickname":"evidence set","label":"evidence set pipelines","accent":"cyan","mood":"ready",
 "message":"MR ready for review","agent":"claude-code","tmuxTarget":"par:@1.%1","pid":71481,
 "sprite":"claude","activeSubagentIds":[],"updatedAt":1790014288.12}
```

- `agent` is `claude-code` or `pi`, defaulting to `claude-code`. `nickname`, `label`, `accent`
  and `sprite` are optional overrides: `accent` is an `AccentColor` name, and `sprite` is a pack
  name where missing or unknown means `claude`. Label resolution order is `nickname`, `label`,
  Claude session `name`, basename of `cwd`.
- `tmuxTarget` is `SESSION:@WINDOW.%PANE`. When absent and the enrolling process has
  `$TMUX_PANE`, the CLI resolves it at `on` time with
  `tmux display-message -p -t $TMUX_PANE '#{session_name}:#{window_id}.#{pane_id}'`.
- `pid` is the process to liveness-check. Absent on a `claude-code` record, the record is alive only while a Claude
  session file carries its `sessionId` and that file's pid is alive, except that a record with no such file counts
  as alive until its `updatedAt` is 30 s old, so enrollment cannot lose a race with Claude Code writing the file.
  Absent on any other agent: treat as alive. `mood` is one of `ready`, `needsInput`, `blocked`.
- `visible: true` is the only thing that makes a pet appear, `enabled: false` makes `show` a no-op, and deleting the
  file removes the pet.
- `activeSubagentIds` holds the `agent_id` of every background subagent the session has started and not yet finished.
  It defaults to empty when absent, so records written before this field existed still decode. Only the three narrow
  writers `PetSubagentTracking.recordStartAndHide`, `recordStop` and `clear` touch it. A `SubagentStart` or
  `SubagentStop` payload without an `agent_id` is tracked under the synthetic id `unknown-<n>`, where `n` is the
  lowest number not already in the set: a start adds one, and a stop removes the most recently added `unknown-`
  id. A missing field therefore degrades to a counter instead of to no tracking at all.

## Concurrency

Claude Code can run two hooks at once, so two `agent-pet hook` processes can hold the same record. Every
load-modify-save goes through `PetSessionStore.withLockedRecord(sessionId:)`, which opens
`sessions/<session_id>.lock`, takes `flock(LOCK_EX)`, loads the record, hands it to the caller's transform and
writes it back only when the transform changed it, then releases the lock on scope exit. The CLI, the hooks, the
pi extension's CLI calls and the daemon's own hide on a click all take the same lock, so a read can never be
interleaved with another process's write. Each writer stays its own narrow function; only the locking is shared.
Setting the record to `nil` inside the transform deletes it, and deleting removes the lock file with it.

The `Stop` decision is part of one locked section: `showUnlessSubagentsActive` reads `activeSubagentIds` and
writes `visible` under the same lock, so it can never decide on a set that another process is in the middle of
changing. Ordering comes from the skill: every hook is `async: false`, so Claude Code runs hooks in event order
and a `SubagentStart` completes before the `Stop` that follows it. The `Stop` hook still has no blocking effect,
because the command exits 0 and prints nothing. `SubagentStart` also hides, in that same locked write, because a
subagent starting means the session is not waiting on Xander. `SubagentStop` stays record-only: the main agent is
about to be re-invoked, and its own `Stop` decides.

## Enrichment from Claude Code's own session files

Claude Code writes `~/.claude/sessions/<pid>.json` for every live session, carrying `pid`,
`sessionId`, `cwd`, `name`, `nameSource`, `status`, `tmux` and `messagingSocketPath`.
`ClaudeSessionDirectory` matches PetSession.sessionId to one of these by `sessionId` to fill in a
missing label or tmux target. Never trust `status`, it goes stale.

`ProcessLiveness.isAlive(session:claudeSession:)` is the one liveness rule, and the daemon sweep and
the `status` table both call it, so they cannot disagree. A `preview-` record is always alive. A
record with its own `pid` is alive while `kill(pid, 0)` says so. A `claude-code` record without a
`pid` is alive only while a Claude session file carries its `sessionId` and that file's pid is alive,
with the 30 s grace above for a record whose file is not there at all. Any other agent without a
`pid` is alive. When the rule says dead, the daemon dives the pet and deletes the PetSession file,
which is what sweeps records that a missed `SessionEnd` hook left behind.

## Session differentiation

1. **Accent color** on the sprite's accent pixels (scarf or bandana) and the label dot. Default
   is `AccentColor.allCases[fnv1a(sessionId) % count]`, overridable with `--accent`.
2. **Label** under the sprite: the resolved label, in a small bold monospaced font on a dark
   rounded pill, with an accent-colored dot at the left.
3. **Lane position**: pets never overlap. Visible pets are sorted by `updatedAt`; pet `i` of `n`
   gets home x at `(i + 1) / (n + 1)` of the screen width and wanders within +/-120 px of home.
4. **Sprite pack**, chosen with `--sprite`.

`AccentColor` cases and hex. These are exactly the eight names Claude Code's `/color` command
takes, so the bandana and the prompt bar always agree by name. Do not add a case without
updating this file and the accent lists in the skill and the pi extension.

| name   | hex     |
|--------|---------|
| red    | #FF5252 |
| blue   | #4C8DFF |
| green  | #4ADE80 |
| yellow | #FFD93D |
| purple | #A970FF |
| orange | #FF9F1C |
| pink   | #FF7EB6 |
| cyan   | #2EE6D6 |

`orange` is deliberately a bright amber so it still reads against the terracotta body. Body
palette (fixed): body `#D97757`, bodyShade `#B85C3E`, outline `#3B2418`, eye `#1A1A1A`,
highlight `#F5D0BF`.

## CLI, one binary `agent-pet`

All session-taking commands default `--session` to `$CLAUDE_CODE_SESSION_ID` and fail with exit 2
and a one-line stderr message if neither is set. The identity flags `--nickname`, `--label`,
`--accent`, `--agent`, `--tmux`, `--pid` and `--sprite` work on `on`, `show` and `preview` alike.

| command | effect |
|---|---|
| `daemon` | run the overlay in the foreground (accessory app, no dock icon) |
| `ensure-daemon` | kickstart the launchd agent when its plist exists, otherwise start `daemon` detached if `daemon.pid` is missing or dead; idempotent, see "Daemon lifecycle" |
| `on [identity flags] [--no-color-sync]` | upsert record: enabled true, visible false; ensure-daemon; print one line naming the resolved accent; then sync the prompt bar color |
| `off [--session ID] [--no-color-sync]` | enabled false, visible false; then reset the prompt bar color |
| `show [--mood MOOD] [--message TEXT]` | if enabled: visible true, mood, message; ensure-daemon. Not enrolled or disabled: silent exit 0 |
| `hide [--session ID]` | visible false |
| `remove [--session ID]` | delete the record |
| `status` | table: session id (short), label, accent, enabled, visible, mood, active subagent count, alive; plus daemon pid |
| `hook` | read one Claude Code hook JSON object from stdin, dispatch below; always exit 0; never write to stdout |
| `preview [--mood MOOD] [--seconds N]` | show a fake pet (sessionId `preview-<random>`, label `preview`) for N seconds (default 20) so the overlay can be tested without a real session |
| `focus [--session ID] [--no-client-switch]` | run the same `SessionFocuser.focus` a left click runs, so focusing can be tested from a shell; exit 2 when the record is missing or has no tmux target. `--no-client-switch` leaves every attached client alone: it skips both `switch-client` and the iTerm tab script, so a test can prove the window and pane selection without moving a real client |

## `hook` dispatch on `hook_event_name`

| event | action |
|---|---|
| `Stop`, record has no active subagent ids | `show --mood ready` (message: first line of `last_assistant_message`, truncated to 80 chars, if present) |
| `Stop`, record has active subagent ids | `hide`, and do not ensure the daemon |
| `Notification` with `notification_type` in `permission_prompt`, `agent_needs_input` | `show --mood needsInput`, whatever the subagent set holds |
| `SubagentStart` | `PetSubagentTracking.recordStartAndHide` with the payload's `agent_id`: records the id and hides, in one locked write |
| `SubagentStop` | `PetSubagentTracking.recordStop` with the payload's `agent_id`; shows and hides nothing |
| `UserPromptSubmit` | `PetSubagentTracking.clear`, then `hide` |
| `PreToolUse` | `hide` |
| `SessionEnd` | `remove` |
| anything else | nothing |

Claude Code fires `Stop` when the main agent's turn ends, including while that session still has
background subagents running, and finishing a background subagent re-invokes the main agent. `Stop`
on its own therefore does not mean the session is waiting on Xander, so the record carries
`activeSubagentIds` and a `Stop` with a non-empty set hides instead of showing. A permission prompt
is the exception, because it really is waiting on Xander whatever the subagents are doing.

`UserPromptSubmit` clears the set as well as hiding: a new prompt from Xander makes the previous
turn's bookkeeping stale, and the clear self-heals a `SubagentStop` that never arrived, so a missed
event can strand the pet for one turn at most.

The hook path must be fast (<50 ms) and never throw. Unknown JSON, missing fields or a missing
state dir all exit 0 quietly.

Every handled hook appends one line to `~/.agent-pet/hooks.log`: ISO timestamp, event name, the first 8
characters of the session id, the `agent_id` or `-`, and the record state after the write as
`visible=<bool> agents=<count>`. The log is truncated before the append once it passes 1 MiB, the same rule
`daemon.log` follows, and both share `LogFileTruncation`. The hook never writes to stdout.

## Daemon lifecycle

The daemon runs under launchd, not as a child of whatever process asked for it. A daemon spawned
from a Claude Code Bash tool call is reparented to launchd anyway and dies with no supervisor, so a
crash left every later hook updating records that nothing drew.

- `install.sh` writes `~/Library/LaunchAgents/com.agent-pet.daemon.plist` with label
  `com.agent-pet.daemon`, `ProgramArguments` of the absolute binary path plus `daemon`, `RunAtLoad`
  and `KeepAlive` true, `ProcessType` `Interactive`, `LimitLoadToSessionType` `Aqua`,
  `EnvironmentVariables` with `PATH` of
  `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`, and both
  `StandardOutPath` and `StandardErrorPath` set to `~/.agent-pet/daemon.log`. It then runs
  `launchctl bootout gui/<uid>/com.agent-pet.daemon`, ignoring failure, and
  `launchctl bootstrap gui/<uid> <plist>`. `uninstall.sh` does the bootout and removes the plist.
- `KeepAlive` means a crashed daemon is back within seconds, with no CLI call needed.
- `ensure-daemon` and `DaemonCommand.ensureRunning()`: when the plist exists, run
  `launchctl kickstart gui/<uid>/com.agent-pet.daemon` and return. There is no `-k`, so a running
  daemon is left alone. A kickstart of a service that was booted out fails with "could not find
  service", so a failed kickstart is followed by `launchctl bootstrap gui/<uid> <plist>`, which
  loads the agent and starts it through `RunAtLoad`. When the plist is missing, fall back to the
  old detached spawn, guarded by the liveness check on `daemon.pid`.
- Every path that shows a pet ensures the daemon: `on`, `show`, `preview`, and the `hook` command
  on `Stop` and on a `Notification` of type `permission_prompt` or `agent_needs_input`. The hook
  ensures only after `PetTurnState.show` reports that the record exists and is enabled, so a
  session that never enrolled never starts a daemon.
- The daemon still writes `daemon.pid` at startup, so `status` reports the pid whoever started it.
  It also writes one line to stderr at startup:
  `agent-pet daemon started pid <pid> parent <ppid> at <ISO timestamp>`, which makes a later crash
  in the log attributable to one run. If `daemon.log` is larger than 1 MB at startup, the daemon
  truncates it first.

## Overlay behavior

- One borderless `NSWindow` per visible pet: `level = .screenSaver`, `backgroundColor = .clear`,
  `isOpaque`/`hasShadow`/`ignoresMouseEvents` false, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`.
- Sprite rendered at 4x pixel scale (16 px frame -> 64 px), label pill beneath. Window sits on
  `NSScreen.main.visibleFrame.minY + 4` so it rides above the Dock.
- Animation: sprite frames at 8 fps, walk speed 40 px/s, turn around at lane bounds (renderer flips horizontally for
  leftward travel), random idle pauses of 1 to 3 s.
- Mood: `ready` walks and occasionally plays `wave`; `needsInput` stands on `idle` with a bobbing `!` bubble;
  `blocked` plays `sit` with a `?` bubble.
- Left click: focus the session, then hide. Right click: hide only. Focus is `SessionFocuser.focus`,
  described under "Focusing a session".
- The daemon polls `~/.agent-pet/sessions/` every 300 ms (mtime of the dir, then file contents on
  change) and reconciles windows to records. Liveness check every 5 s.
- The same poll signs `~/.claude/sessions/` the same way. On change the daemon re-resolves every
  visible pet's label and pushes it into the existing `PetView`, so a `/rename` shows up within one
  poll interval without recreating the window or restarting the animation.

### Emerge and dive

The pet comes up out of the "ground" (the bottom edge of the usable screen) when it appears and dives back down when
it is hidden. The ground line is `NSScreen.main.visibleFrame.minY`, and the window never moves vertically: `PetView`
draws the sprite with a vertical `groundOffset` and clips at the view's bottom edge, so the underground part is
invisible whatever sits below. The hook and CLI paths stay instant; only the daemon animates.

- **Emerge**, on a record becoming visible: `groundOffset` goes from `spriteHeight` to 0 over 450 ms with ease-out
  while the `emerge` frames play once (evenly spread over the duration); the label pill and bubble fade in over the
  last 150 ms. Then the mood behavior starts.
- **Dive**, on a record becoming hidden or removed: label and bubble fade out over 100 ms, the `dive` frames play
  once over 350 ms while `groundOffset` goes from 0 to `spriteHeight` with ease-in, then the window closes. A record
  that becomes visible again mid-dive reverses into an emerge from the current offset. Liveness-sweep removals dive.

## Sprite contract

`SpriteContract.swift` is fixed. `PixelFrame` derives its square side length per frame, so packs may be 16, 24 or
32 px and the renderer still scales by 4. `SpriteSheet` carries `frameSize` and `colorsByCharacter`; `SpritePalette`
is data (a `[Character: NSColor]` plus the accent) and the compiled-in palette is its default instance. The
initializer is `SpriteSheet(idle:walk:wave:sit:emerge:dive:colorsByCharacter:)` with `emerge` and `dive` defaulting
to `[]`, and `SpriteAnimationName` covers all six. `ClaudeSprite.swift` provides the built-in art as
`extension SpriteSheet { static let claude8Bit: SpriteSheet }`: frames of `PixelInk` raw characters, `.` transparent,
idle 2 frames, walk 4, wave 3, sit 2, facing right for the renderer to mirror. The character is a squat, rounded,
friendly orange critter in the spirit of the pixel Claude persona Anthropic uses (terracotta body, two dark eyes,
tiny stub legs, no mouth or a tiny one), original art rather than a copy of any Anthropic asset, with the accent
pixels forming the scarf or bandana.

### Sprite packs

Art also ships as plain-text packs so anyone can draw a new pet in a text editor:

```
sprites/<pack-name>/
  pack.json      {"name":"claude","frameSize":16,
                  "palette":{"o":"#D97757","O":"#B85C3E","#":"#3B2418","e":"#1A1A1A","w":"#F5D0BF"}}
  idle.txt       frames of <frameSize> rows, separated by one blank line
  walk.txt, wave.txt, sit.txt
  emerge.txt, dive.txt         optional, 3 frames each recommended
```

- `A` and `a` are never in `palette`; they always take the session accent and its shade. Any
  other character in `palette` maps to a fixed hex color, and unknown characters are transparent.
- The repo ships `sprites/claude/`, the same art as `claude8Bit` exported to text. `install.sh` copies each pack
  directory into `~/.agent-pet/sprites/` only when no pack of that name is installed, so local edits survive.
- The daemon loads packs from `~/.agent-pet/sprites/<name>/` at startup and re-reads a pack when
  its directory mtime changes. A pack that fails to parse logs one line and falls back to
  `claude8Bit`; one without `emerge.txt` or `dive.txt` holds `idle` frame 0 during the offset move.
- Art direction for `claude`: emerge = eyes closed and squinting up with a dirt-ruffled top (a few
  `#` and `O` pixels above the head), then eyes open wide, then a shake. dive = look down, squash
  flat, then a small `#`/`O` dust puff where the body was.

## Focusing a session

A left click on a pet, and the `focus` command, run the same `SessionFocuser.focus`.

1. `tmux select-window -t SESSION:@WINDOW`, then `tmux select-pane -t %PANE`.
2. `tmux list-clients -F '#{client_tty}\t#{session_name}\t#{client_activity}'`, parsed into one record
   per row. The chosen client is the first one already attached to the target session, or else the one
   with the greatest `client_activity`.
3. `tmux switch-client -c <client_tty> -t SESSION`, skipped when no client was found, when the chosen
   client is already on the target session, or when `--no-client-switch` was passed. Steps 1 and 2 run
   either way.
4. When a client was chosen, `--no-client-switch` was not passed and iTerm2 is running,
   `/usr/bin/osascript` runs a script that walks the
   windows, tabs and sessions of application `iTerm2`, and for the session whose `tty` is the chosen
   client tty selects the tab and the session, sets that window's `index` to 1, activates iTerm2 and
   returns a success marker. Any other result, including a missing tty and a terminal that is not
   iTerm2, falls through to step 5.
5. Activate the first running app among `com.googlecode.iterm2`, `com.apple.Terminal`,
   `com.mitchellh.ghostty`.

macOS asks once for Automation permission the first time step 4 runs, so agent-pet may control
iTerm2. Denying it costs only the exact tab: step 5 still brings the terminal forward, and the tmux
selection in steps 1 to 3 already happened.

Every tmux and osascript failure is ignored.

### Finding the tmux binary

The daemon runs under launchd with a minimal `PATH`, so `/usr/bin/env tmux` failed for every call the
daemon made while hooks and the CLI, which run from real shells, worked. `TmuxCommandRunner` instead
resolves the binary once into a `static let` and runs it by absolute path: `$TMUX_EXECUTABLE` when it
is set and executable, then `/opt/homebrew/bin/tmux`, `/usr/local/bin/tmux`, `/usr/bin/tmux`, then the
first `tmux` on `PATH`. When none of those exists every tmux call is a silent no-op, as before.
`$TMUX_EXECUTABLE` also lets a test point the tool at a stub binary.

## Prompt bar color sync

Claude Code has a per-session prompt bar color, set by
`/color [red|blue|green|yellow|purple|orange|pink|cyan|default]` (binary 2.1.278 marks it
`immediate` and `supportsNonInteractive`). Xander never sets it himself, so the tool owns it, and
because there is no API for `/color` the CLI types it into the session's tmux pane.

- `on`, when the record's agent is `claude-code` and a tmux target was resolved: after writing
  the record and printing the accent line, run `tmux send-keys -t <target> -l "/color <accent>"`
  then `tmux send-keys -t <target> Enter`. `off` does the same with `/color default`.
- `--no-color-sync` on `on` and `off` skips it. Agent `pi` never syncs, because pi has no prompt
  bar color. A record with no tmux target never syncs.
- Failures, including no tmux and a stale target, are silently ignored.
- Nothing else ever types into a pane. `show`, `hide`, `remove` and `hook` do not.
- The keystrokes land in the Claude Code input box of the pane that invoked `/pet`; because
  `/color` is an immediate command it runs even while Claude works on the `/pet` turn.

## Skill `/pet`

`skill/pet/SKILL.md` frontmatter registers session-scoped hooks so enrollment is inherently per-session: `Stop`,
`Notification`, `UserPromptSubmit`, `PreToolUse`, `SessionEnd`, `SubagentStart`, `SubagentStop`, each running
`"$HOME/.local/bin/agent-pet" hook` as a command hook with `async: false` and the default timeout. Synchronous is
what puts the hooks in event order, which `Stop` depends on, and it costs nothing: each run is well under 50 ms
and the command exits 0 with no output, so no hook can block or fail a turn. Hooks are registered when `/pet` is
invoked, so a session enrolled before `SubagentStart` and `SubagentStop` existed, or before the hooks became
synchronous, needs `/pet` again to pick the new frontmatter up. The absolute path is deliberate: hook shells do
not reliably have `~/.local/bin` on `PATH`.
Invoking `/pet` is the whole opt-in; the body tells Claude to run `agent-pet on` with an optional nickname and accent
from `$ARGUMENTS`, or `agent-pet off` for `/pet off`, then report the accent in one line.

## pi extension

`pi-extension/agent-pet.ts` is one file, symlinked to `~/.pi/agent/extensions/agent-pet.ts` so every pi project sees
it. It registers `/pet` with the same argument shape as the skill plus a `sprite:<name>` token, and shells out to the
same binary; if the binary is not on `PATH`, `/pet` says to run `install.sh` and does nothing else. Until `/pet` runs
it makes no CLI calls at all. It enrolls with `--agent pi`, `--label` from the pi session name or the basename of
`cwd`, and `--pid` for liveness, and never passes `--tmux`, so the CLI resolves the pane itself.

| pi event | command |
|---|---|
| `agent_settled` | `show --mood ready` |
| `ui_prompt_start` | `show --mood needsInput` |
| `ui_prompt_end`, `tool_execution_start` | `hide` |
| `input`, when the source is `interactive` | `hide` |
| `session_shutdown` | `remove` |

`agent_settled` is the only event that shows mood `ready`. It fires after pi has fully settled, so no retry,
auto-compaction or queued follow-up is left, and the pet stays hidden while tools and subagents run.
`ui_prompt_start` and `ui_prompt_end` bracket blocking prompts, pi's closest thing to a permission prompt. Every call
is fire and forget with a two second timeout, and failures log one `[agent-pet]` line without interrupting the turn.

## Code rules for every file

- No single-letter or abbreviated names, including loop variables and closure parameters.
- Zero comments unless explaining a non-obvious why. No section-divider comments.
- No magic strings: hook event names, mood names, accent names, bundle ids, tmux subcommands and
  flags, and file names are enums or `static let` constants.
- Every `switch` over an enum is exhaustive with no `default`.
- Avoid `as!` and `try!`; decode with `Codable`. No em dashes in any prose.
