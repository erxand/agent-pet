# agent-pet design contract

A macOS overlay pet that appears along the bottom of the screen only when an enrolled coding
agent session has finished its turn and is waiting on the user. Sessions opt in one at a time, with
the `/pet` skill in Claude Code or the `/pet` command in pi. Nothing is global: a session that
never enrolled has no state and no pet, even when the hooks are installed for every session (see
"`hook` dispatch"). With no config file, everything below is the default behavior; a config file
only swaps in the alternatives listed under "Contracts".

## Layout

```
agent-pet/
  DESIGN.md, README.md         this contract, and install + usage
  Package.swift                swift-tools 5.9, macOS 14+: library `AgentPetCore`, executable `agent-pet`, tests `AgentPetTests`
  Sources/AgentPetCore/
    Commands/                  one file per subcommand, plus flag parsing and feedback; AgentPetCommandLine is the entry point
    Contracts/                 AgentPetConfiguration, ConfigurationFile, the contract protocols and their implementations, PetDisplayPlanner
    Focusing/                  Focuser, TmuxItermFocuser, CommandFocuser
    State/                     PetSessionStore, ClaudeSessionDirectory, tmux run, hook log, subagent tracking
    Sprites/                   SpriteContract (fixed), PixelRenderer, ClaudeSprite (claude8Bit art), SpritePackLoader, SpritePackRegistry, SpritePackAssignment, SpritePackAccent, PackAccentResolver, SpriteAccentTint, PixelFont (nametag glyphs), TerminalSpriteRenderer
    Demo/                      DemoScript (scenes and cast), DemoRunner (timeline), DemoPlayback (clock and signals), DemoPixelFont, DemoCommand, see "Demo"
  Sources/agent-pet/
    main.swift                 hands argv and the overlay to AgentPetCommandLine
    Overlay/                   NSApplication daemon, PetWindow, PetAnimator, PetSpriteFrames, lanes, clicks
    Demo/                      the demo's AppKit stage: caption and title card panels, snapshots
  Tests/AgentPetTests/         characterization and contract tests, see "Tests"
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
  config.json                  optional, see "Configuration"
  focus.json                   written by a terminal integration: the pane in front, see "Held back"
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
 "sprite":"claude","focusTarget":"pane:42","activeSubagents":[{"id":"a184a0c2d9e1f3b47","startedAt":1790014201.4}],
 "transcriptPath":"/Users/me/.claude/projects/-Users-me-repo/1dd88945-2a6c-4903-88f8-c8837c6cd8d3.jsonl",
 "transcriptScanOffset":2702079,"updatedAt":1790014288.12}
```

- `agent` is `claude-code` or `pi`, defaulting to `claude-code`. `nickname`, `label`, `accent`
  and `sprite` are optional overrides: `accent` is an `AccentColor` name, and `sprite` is a pack
  name where missing or unknown means the compiled-in `claude` art. `on` and `preview` fill
  `sprite` when it is absent, then fill `accent` from that pack when `accent` is absent, see
  "Sprite assignment". `accentFromPack` is true when that fill wrote `accent`, and false whenever
  `--accent` sets it, so it tells an accent the session chose from one it only inherited from its
  pack, see "Accent on the sprite". Label resolution order is `nickname`,
  `label`, Claude session `name`, basename of `cwd`.
- `tmuxTarget` is `SESSION:@WINDOW.%PANE`. When absent and the enrolling process has
  `$TMUX_PANE`, the CLI resolves it at `on` time with
  `tmux display-message -p -t $TMUX_PANE '#{session_name}:#{window_id}.#{pane_id}'`.
- `pid` is the process to liveness-check. Absent on a `claude-code` record, the record is alive only while a Claude
  session file carries its `sessionId` and that file's pid is alive, except that a record with no such file counts
  as alive until its `updatedAt` is 30 s old, so enrollment cannot lose a race with Claude Code writing the file.
  Absent on any other agent: treat as alive. `mood` is one of `ready`, `needsInput`, `blocked`.
- `visible: true` is the only thing that makes a pet appear, `enabled: false` makes `show` a no-op, and deleting the
  file removes the pet. In a group of several sessions, a visible `ready` member can still be held back while
  another member works, see "Groups".
- `busy` is optional and present only as `true`: the session is in the middle of a turn. `UserPromptSubmit`,
  `PreToolUse` and `SubagentStart` set it, and a `Stop` with no active subagents left removes it. A record without
  it, including every record from before this field, is not busy. A session is working while it is `busy` or
  tracks any subagent. `busy` and `visible` are separate on purpose: a click or `hide` clears `visible` and leaves
  `busy` alone, so a dismissed session that had finished counts as done, not as working.
- `held` is optional and present only as `true`, with `heldAt` (seconds since 1970) beside it: a hook wanted
  to show the pet but its pane was the one in front, so the pet stayed down. `release` decides later whether it
  comes up. Any hide, `off` and the start of a new turn drop it. See "Held back".
- `waitingSince` is optional: when the session last started waiting on the user. Every show (`Stop`, a
  `needsInput` notification, `show`) and every hold stamps it, a `release` keeps it, and a hide removes it. A record without it, including every
  record from before this field and every `preview`, shows at once. See "Settling".
- `activeSubagents` holds one `TrackedSubagent` (`id`, the `agent_id`, and `startedAt`) for every background
  subagent the session has started and not yet finished. It defaults to empty when absent. A record from before
  this field still decodes: a legacy `activeSubagentIds` string array becomes entries whose `startedAt` is the
  record's `updatedAt`. Only `PetSubagentTracking.recordStartAndHide`, `recordStop` and `clear`, plus the
  `SubagentCleanup` step described under "Subagent completion", touch it. A fresh `SubagentStart` for an id that is
  already in the set resets its `startedAt`. A `SubagentStart` or `SubagentStop` payload without an `agent_id` is
  tracked under the synthetic id `unknown-<n>`, where `n` is the lowest number not already in the set: a start adds
  one, and a stop removes the most recently added `unknown-` id. A missing field therefore degrades to a counter
  instead of to no tracking at all.
- `group`, `owner` and `enrolledAt` are optional and absent unless `--group` or `--owner` was passed. `group`
  is the key of the pet the session belongs to; absent means the session id, which is the one pet per
  session model. `owner` is `true` on the member flagged with `--owner`. `enrolledAt` is stamped once,
  when the session first gets a `group`, and orders members for the owner fallback. See "Groups".
- `focusTarget` is optional and opaque: `--focus-target` stores it and the command focuser hands it on as
  `AGENT_PET_FOCUS_TARGET`. agent-pet never interprets it.
- `handoverPendingSince` is optional and present only on a record a `SessionEnd` with `reason` `clear` or
  `resume` kept for its process. The `SessionStart` that hands the record over, or one that resumes the same
  session id, removes it. A record still carrying it 30 s later counts as dead, see "Enrichment".
- `transcriptPath` is the last `transcript_path` a hook payload carried, and `transcriptScanOffset` (default 0) is the
  byte offset in that file up to which task notifications were already read. Storing a different path resets the
  offset to 0.

## Concurrency

Claude Code can run two hooks at once, so two `agent-pet hook` processes can hold the same record. Every
load-modify-save goes through `PetSessionStore.withLockedRecord(sessionId:)`, which opens
`sessions/<session_id>.lock`, takes `flock(LOCK_EX)`, loads the record, hands it to the caller's transform and
writes it back only when the transform changed it, then releases the lock on scope exit. The CLI, the hooks, the
pi extension's CLI calls and the daemon's own hide on a click all take the same lock, so a read can never be
interleaved with another process's write. Each writer stays its own narrow function; only the locking is shared.
Setting the record to `nil` inside the transform deletes it, and deleting removes the lock file with it.

The `Stop` decision is part of one locked section: `showUnlessSubagentsActive` runs the transcript scan and the
expiry, reads `activeSubagents` and writes `visible` under the same lock, so it can never decide on a set that
another process is in the middle of changing. Ordering comes from the skill: every hook is `async: false`, so Claude Code runs hooks in event order
and a `SubagentStart` completes before the `Stop` that follows it. The `Stop` hook still has no blocking effect,
because the command exits 0 and prints nothing. `SubagentStart` also hides, in that same locked write, because a
subagent starting means the session is not waiting on the user. `SubagentStop` stays record-only: the main agent is
about to be re-invoked, and its own `Stop` decides.

## Enrichment from Claude Code's own session files

Claude Code writes `~/.claude/sessions/<pid>.json` for every live session, carrying `pid`,
`sessionId`, `cwd`, `name`, `nameSource`, `status`, `tmux` and `messagingSocketPath`.
`ClaudeSessionDirectory` matches PetSession.sessionId to one of these by `sessionId` to fill in a
missing label or tmux target. Never trust `status` on its own, it goes stale. The one use of it is a
`busy` written after a pet's `waitingSince`, which is fresh by definition, see "Settling". Which directories are read is the
SessionSource contract: by default only `~/.claude/sessions/`, and `sessionDirectories` in the config
adds others, such as the `sessions/` directory of a second Claude config root.

`ProcessLiveness.isAlive(session:claudeSession:)` is the one liveness rule, and the daemon sweep and
the `status` table both call it, so they cannot disagree. A `preview-` record is always alive. A
record whose `handoverPendingSince` is 30 s old or more is dead, because no `SessionStart` claimed it. A
record with its own `pid` is alive while `kill(pid, 0)` says so. A `claude-code` record without a
`pid` is alive only while a Claude session file carries its `sessionId` and that file's pid is alive,
with the 30 s grace above for a record whose file is not there at all. Any other agent without a
`pid` is alive. When the rule says dead, the daemon dives the pet and deletes the PetSession file,
which is what sweeps records that a missed `SessionEnd` hook left behind.

## Session differentiation

1. **Sprite pack**: assigned at `on` time when the record has no `sprite`, or chosen with
   `--sprite`. See "Sprite assignment".
2. **Accent color** on the label dot, the mood bubble and the prompt bar, and on the sprite itself
   when the pack opts in and the session chose its accent, see "Accent on the sprite". It matches
   the sprite, so the prompt bar color tells you which creature belongs to the session.
   Resolution order: `--accent`, then the pack's declared `accent`, then the pack's dominant
   color, then `AccentColor.allCases[fnv1a(sessionId) % count]` when there is no installed pack.
3. **Label** under the sprite: the resolved label, in a small bold monospaced font on a dark
   rounded pill, with an accent-colored dot at the left. With `labelPlacement` `nametag` it sits
   over the head instead, on a square dark tag with a 2 pt accent stripe along its bottom, in
   `PixelFont`, a 3 by 5 pixel font drawn at 2 pt per pixel so it matches the sprite art. A label
   with a character the font lacks is drawn in unantialiased 9 pt Menlo Bold on the same tag. With
   `disambiguateLabels` on, two visible pets whose labels read the same (after the 28 character cut)
   both get a space and the last 4 characters of their owner's session id, recomputed on every
   redraw, so the suffix goes away when one of them hides.
4. **Lane position**: pets never overlap. Visible pets are sorted by `updatedAt`; pet `i` of `n`
   gets home x at `(i + 1) / (n + 1)` of the screen width and wanders within +/-120 px of home.

### Accent on the sprite

Several sessions can share a creature, so a pack may hand one ink and its shade over to the session
accent. `accentInks` in `pack.json` names them: `{"accent":"A","shade":"a"}`. Pixels drawn with
`accent` are painted in the accent color and pixels drawn with `shade` in that color with each sRGB
channel multiplied by `SpriteAccentTint.shadeBrightness`, 0.68 (the hand drawn shades in the shipped
packs sit near 0.7, and the result stays readable for all eight accents). Both must be single
characters present in `palette`: an `accent` that is not drops the whole key, a `shade` that is not
drops only the shade. A pack without the key, and the compiled-in `claude8Bit`, never recolor.

This is off unless the config sets `accentInks` to `true`. With no config a chosen accent colors the
label dot, the bubble and the prompt bar, as upstream always did, and every sprite keeps its palette.

The rule is `SpriteAccentTint.tint(chosenAccent:accentInks:)`: with `accentInks` on, the sprite is
recolored when the pack has `accentInks` and the record has a chosen accent,
`PetSession.chosenAccent(packAccent:)`. That is `accent` when `accentFromPack` is false, nothing when it
is true. So `--accent` (which hq passes for every account) recolors, and an accent that `on` or
`preview` only filled from the pack keeps the pack's own palette, the look the pack was drawn with. A
record written before `accentFromPack` existed has no flag, and `on` filled its `accent` from the pack
whenever none was given, so such a record counts as filled from the pack when its `accent` equals the
pack's own accent, and as chosen otherwise. An explicit accent equal to the pack's own accent still
recolors, so two sessions on one pack with different chosen accents never look alike. With no `accent`
at all (the session hash case) the sprite keeps its palette.

`SpritePackRegistry.sheet(forPackNamed:chosenAccent:)` returns the sheet and the tint it applied.
It recolors each pack and accent pair once and keeps the result until that pack reloads, and the
overlay's frame image cache is keyed by pack, tint, animation, frame and facing, so a tick never
recolors. `render --accent` applies the same rule with the flag as the chosen accent.

### Sprite assignment

`SpritePackAssignment` runs inside `on` and `preview` whenever the record would otherwise have no
`sprite`. It lists the installed packs (`~/.agent-pet/sprites/*/` plus the packs in the config's
`spriteDirectories`) minus the `reservedSprites` of
the config, counts how many other live pets use each one (a pet's sprite is its owner's, so a group
counts once), keeps the packs with the lowest count, and picks one of those at random. A session
that joins a group whose live owner already has a sprite takes that sprite instead, so the pet looks
the same whichever member ends up owning it. A reserved pack is never picked at random, and with
every pack reserved the record stays without `sprite`. With fewer live sessions than packs every session gets a different pet; past that the
duplicates spread evenly. The pick is written into the record once, so a session keeps its pet
across `show` and `hide`, and `/pet` on an already enrolled session keeps the pet it has. An
explicit `--sprite` always wins, reserved or not, and with no packs installed the record stays without `sprite`
and the daemon draws the compiled-in art.

Right after the sprite is assigned or confirmed, `on` and `preview` fill the record's `accent`
when it is absent and `sprite` names an installed pack that loads: `SpritePackAccent` writes the
pack's declared `accent`, or else what `PackAccentResolver` computes from the pack. The identity
overrides run before this step, so `--accent` always wins. A record that already has `accent`
keeps it. A record with `sprite` but no `accent`, such as one enrolled before this rule, gets its
accent the next time `on` runs for it, and until then `resolvedAccent` falls back to the session
hash. With no pack at all, `accent` stays absent and `resolvedAccent` uses the session hash.

`PackAccentResolver.dominantAccent(colorsByCharacter:frames:)` is a pure function. It drops the
two darkest palette entries by luminance (the outline and, by convention, the eyes), counts how
often each remaining character occurs across every frame of every animation, takes the most
frequent one (ties go to the lower character), and returns the `AccentColor` nearest to it by
Euclidean distance in sRGB. A palette with two entries or fewer keeps them all. A pack whose
frames use none of the candidates gives no accent, which leaves the session hash in charge.

`AccentColor` cases and hex. These are exactly the eight names Claude Code's `/color` command
takes, so the label dot and the prompt bar always agree by name. Do not add a case without
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

Compiled-in `claude` palette (fixed): body `#D97757`, bodyShade `#B85C3E`, outline `#3B2418`,
eye `#1A1A1A`, highlight `#F5D0BF`, scarf `#2EE6D6`, scarfShade `#20A196`.

## CLI, one binary `agent-pet`

All session-taking commands default `--session` to `$CLAUDE_CODE_SESSION_ID` and fail with exit 2
and a one-line stderr message if neither is set. `--session` works from any shell; the tmux target is
still resolved from the caller's `$TMUX_PANE` unless `--tmux` is passed. The identity flags
`--nickname`, `--label`, `--accent`, `--agent`, `--tmux`, `--pid`, `--sprite`, `--focus-target`, `--group KEY`
and the `--owner` switch work on `on`, `show` and `preview` alike. `--group` puts the session in the pet named
KEY, and `--owner` makes it that pet's owner and clears `owner` on every other record of the group, see
"Groups".

| command | effect |
|---|---|
| `daemon` | run the overlay in the foreground (accessory app, no dock icon) |
| `ensure-daemon` | kickstart the launchd agent when its plist exists, otherwise start `daemon` detached if `daemon.pid` is missing or dead; idempotent, see "Daemon lifecycle" |
| `on [identity flags] [--no-color-sync]` | upsert record: enabled true, and visible false for a new or disabled record (an enabled record keeps `visible` and `held`, so a relabel never takes a pet down), `sprite` assigned if absent, then `accent` filled from that pack if absent; ensure-daemon; print one line naming the sprite and the resolved accent; then sync the prompt bar color. Re-running it updates the record in place: only the fields the flags name change, and `sprite`, `accent`, `focusTarget`, `activeSubagents` and the transcript offset are kept |
| `off [--session ID] [--no-color-sync]` | enabled false, visible false; then reset the prompt bar color |
| `show [--mood MOOD] [--message TEXT]` | if enabled: visible true, mood, message; ensure-daemon. Not enrolled or disabled: silent exit 0 |
| `hide [--session ID \| --focus-target T \| --pid N]` | visible false, `held` dropped |
| `release [--session ID \| --focus-target T \| --pid N] [--grace S]` | for a `held` record: drop the hold, and when the record is enabled, not working, not visible and (with `--grace`) was held less than S seconds ago, show it with the mood and message it was held with; ensure-daemon when it came up. Anything else is untouched |
| `remove [--session ID \| --focus-target T \| --pid N]` | delete the record |
| `status [--json]` | table: session id (short), label, sprite, accent, enabled, visible, mood, active subagent count, alive; plus daemon pid. `--json` prints `{"daemonPid": N or null, "sessions": [...]}` with `sessionId`, `group`, `label`, `sprite`, `accent`, `agent`, `enabled`, `visible`, `mood`, `activeSubagents` (a count), `alive`, `pid`, `focusTarget` and `updatedAt` per session, plus `group` (the record's `group`, else its session id) and `owner` (true when the session is the resolved owner of its live pet, false for every other member and for a dead session) |
| (selection) | `hide`, `release` and `remove` act on `--session`, else on every record whose `focusTarget` is `--focus-target` (what a terminal knows about its pane), else on every record whose `pid` is `--pid` (what knows the process after a `/clear` changed its id), else on `$CLAUDE_CODE_SESSION_ID` |
| `hook` | read one Claude Code hook JSON object from stdin, dispatch below; always exit 0; never write to stdout |
| `preview [--mood MOOD] [--seconds N]` | show a fake pet (sessionId `preview-<random>`, label `preview`, `sprite` assigned like `on` unless `--sprite` is given) for N seconds (default 20) so the overlay can be tested without a real session |
| `focus [--session ID] [--no-client-switch]` | run the configured Focuser the way a left click does, so focusing can be tested from a shell; exit 2 when the record is missing, or, with the `tmux-iterm` focuser, when it has no tmux target. `--no-client-switch` leaves every attached client alone: it skips both `switch-client` and the iTerm tab script, so a test can prove the window and pane selection without moving a real client. The CLI waits for a command focuser to finish |
| `clear-subagents [--session ID]` | empty `activeSubagents` under the record lock and print how many entries it dropped; exit 2 when the record is missing. The manual unwedge for a pet held hidden by a subagent the tool still counts as running |
| `render --pack NAME [--animation idle] [--frame N] [--accent COLOR]` | print one frame, recolored as a session that chose COLOR would see it (see "Accent on the sprite"), to stdout with truecolor half blocks: two pixel rows per text line, `▀` with the top pixel as foreground and the bottom as background, `▄` or a space where a pixel is transparent, so transparency shows the terminal background. Each line ends with a reset. A pack named `claude` that is not installed draws the compiled-in art. Exit 2 when `--pack` is missing, the pack does not load, the animation is unknown, N is not a frame of it, or COLOR is not an accent name |
| `packs [--json]` | one row per installed pack: name, accent (as `on` would fill it), reserved (in the config's `reservedSprites`), and live pets (live groups whose owner uses the pack). `--json` prints `{"packs": [{"name", "accent", "reserved", "livePets"}]}` with `accent` null for a pack that yields none |
| `scan-transcript --path FILE [--from OFFSET]` | diagnostic: run `TranscriptCompletionScanner` over FILE from byte OFFSET (default 0) and print one line per event in file order, as `<byte offset> <finished\|interim> <agent_id>`. It reads the file only and touches no record; exit 2 when `--path` is missing, OFFSET is not a number of 0 or more, or the file cannot be read |
| `demo [--scene NAME] [--list] [--auto] [--speed N] [--dry-run] [--snapshot DIR]` | play the scripted tour described under "Demo". `--list` prints the scenes, `--auto` plays every scene on a timer instead of waiting for the space bar, `--dry-run` prints the timeline instead of drawing it, `--snapshot` writes PNGs of the panels and exits. Exit 2 for an unknown scene or a speed that is not a number above 0; 130 after ctrl-c and 143 after SIGTERM |

## `hook` dispatch on `hook_event_name`

Before anything else, a session with no record ends the hook: exit 0, no lock taken, no lock file, no
`hooks.log` line, no state directory created. That is what makes it safe to install these hooks for every
session in `settings.json`, beside or instead of the `/pet` skill hooks. A disabled record still counts as
enrolled and goes through the table below.

| event | action |
|---|---|
| any event whose payload has `transcript_path` | first store it as the record's `transcriptPath`, in its own locked write; a missing record is left alone |
| `Stop` | scan the transcript and expire old entries (see "Subagent completion"), then decide in the same locked section: no active subagents left means clear `busy` and show with mood `ready` (message: first line of `last_assistant_message`, truncated to 80 chars, if present), or hold it back when its pane is in front (see "Held back"); any left means `hide` and keep `busy`, and do not ensure the daemon |
| `Notification` with `notification_type` in `permission_prompt`, `worker_permission_prompt`, `agent_needs_input`, `elicitation_dialog`, `elicitation_url_dialog` | show with mood `needsInput`, whatever the subagent set holds, or hold it back when its pane is in front |
| `Notification` with `notification_type` `idle_prompt` | clear `busy` and nothing else: the session has sat at its prompt for a minute, so whatever turn it was in is over, including one an interrupt (Esc) ended, which fires no `Stop`. It never shows a pet |
| `SubagentStart` | scan and expire, then `PetSubagentTracking.recordStartAndHide` with the payload's `agent_id`: records the id, sets `busy` and hides, in one locked write |
| `SubagentStop` | scan and expire, then `PetSubagentTracking.recordStop` with the payload's `agent_id`; shows and hides nothing |
| `UserPromptSubmit` | set `busy` and `hide`, in one locked write. The subagent set is left as it is, because a new prompt does not end a running subagent |
| `PreToolUse` | set `busy` and `hide`. With `subagentToolsKeepNeedsInput` in the config, a call from a subagent (the payload has an `agent_id`) leaves a visible `needsInput` pet up: another subagent may still be waiting on a permission prompt, and nothing the first one does answers it. Without it, a subagent's tool call hides the pet like any other |
| `SessionEnd` | `remove`, except with `reason` `clear` or `resume` on a record that has a `pid`: then clear `busy`, hide, stamp `handoverPendingSince` and keep the record, because the same process goes on under a new session id and the `SessionStart` that follows hands it over. A record with no `pid` (the plain `/pet` flow) can never be handed over, so it is removed as before. A kept record that no `SessionStart` claims dies 30 s later |
| `SessionStart` with `source` `clear` or `resume` | the one event that may act for a session with no record: the record whose `pid` is the process of the new session id moves to that id, keeping its identity (label, sprite, accent, group, owner, focus target, pid) and starting its turn state fresh. The process is the `pid` in Claude Code's own session file for the new session id (any `sessionDirectories`), and, until Claude Code has written that file, the hook's parent, since Claude Code runs a hook as its child. No other ancestor counts: a Claude started from another Claude's Bash tool (`claude -p --resume`, say) has the parent Claude a few levels up, and must never take the parent's pet. A new session id that already has a record of its own keeps it: a `SessionStart` that resumes the same id removes that record's `handoverPendingSince`, and a handover never overwrites a record. Logged as `SessionStart <new> - ... source=<source>`. Any other source, or no such record, writes nothing |
| anything else | nothing |

A session that has both global hooks and `/pet` skill hooks sees every event twice. Every event in the table
is idempotent for a repeated payload, apart from timestamps, with one exception: show and hide land on the same
state, a second `Stop` scans an already scanned transcript, a `SubagentStart` or `SubagentStop` with an
`agent_id` touches the same entry, a second `SessionEnd` finds the record already kept or gone, and a second
`SessionStart` finds the handover done. The exception is a subagent event without an `agent_id`, which is not
deduplicated: two same-type subagents send byte-identical `SubagentStart` payloads, so a duplicate cannot be told
from a second subagent. It does not need to be. A doubled delivery adds two `unknown-<n>` ids and removes two, so
the set ends where a single delivery leaves it, and the pet shows and hides at the same steps. `HookIdempotencyTests`
replays a whole session (every event and notification type above, a transcript completion, a `/clear` handover
and every `SessionEnd` kind) with each payload delivered once in one home and twice in another, with no config and
with two sessions in one group (one the owner) and `holdWhileBusy`, `settleSeconds`, `subagentToolsKeepNeedsInput`, `accentInks` and `diveOnExit` on, and the records match after
every step.

Claude Code fires `Stop` when the main agent's turn ends, including while that session still has
background subagents running, and finishing a background subagent re-invokes the main agent. `Stop`
on its own therefore does not mean the session is waiting on the user, so the record carries
`activeSubagents` and a `Stop` with a non-empty set hides instead of showing. A permission prompt
is the exception, because it really is waiting on the user whatever the subagents are doing.

### Subagent completion

Field data from `hooks.log` shows that `SubagentStart` fires reliably for background agents but
`SubagentStop` does not fire for them at all. A background agent finishes by a different path: the
harness appends a user-role task notification to the parent session's transcript JSONL and re-invokes
the main agent. The notification carries `<task-id>ID</task-id>`, where `ID` is the `agent_id` that
`SubagentStart` reported, followed by a `<status>` tag. agent-pet therefore reads completion from the
transcript.

Two more findings from a transcript-vs-log timeline (2026-10-02) shaped the scan:

- **Interim notifications.** The harness also writes a task notification with `<status>completed</status>` when an
  agent only pauses while background work of its own is still running. Its `<note>` says the agent "stopped with
  background work of its own still running" and that "the result below may be interim". That agent can resume on
  its own (a fresh `SubagentStart`) and notify again later. A final notification's `<note>` instead says the agent
  "stops with no live background children of its own". Treating the interim one as finished showed the pet while
  the agent was still working.
- **Hand-back messages.** Some agents end with no task notification at all. Their only completion signal is a
  user-role message that opens with `<agent-message from="ID">` and then, a line later, `[Subagent hand-back]`.
  A plain agent-message without that marker is not a completion.

On `Stop`, `SubagentStart` and `SubagentStop`, inside the locked record section and before the event's
own write, `SubagentCleanup` does two things:

1. **Transcript scan.** `TranscriptTailReader` opens `transcriptPath`, rescans from 0 when the file is
   smaller than `transcriptScanOffset`, and reads from the offset to the end of the file. One read is
   capped at 64 MiB: when more is unread, it reads only the last 64 MiB and the hook logs one
   `TranscriptReadTruncated` line. `TranscriptCompletionScanner` is a pure function from bytes to
   events in file order, each `.finished(ID)` or `.interim(ID)` with its byte offset. It finds two shapes:
   - Every `<task-id>ID</task-id>` whose `<status>` tag follows within 2 KB and before the next
     `<task-id>`, with any text between the tags (literal `\n` sequences from the JSON escaping or real
     newlines). It anchors on `<task-id>` and `<status>`, never on the `<task-notification>` wrapper,
     because tool description text also contains that wrapper. Any status value counts. The `<note>`
     after the `<status>` tag, inside the same window, decides the kind: a note that contains the interim
     marker `stopped with background work of its own still running` makes `.interim(ID)`; the final
     marker `stops with no live background children of its own`, any other note, or no note at all makes
     `.finished(ID)`.
   - Every `<teammate-message teammate_id="NAME">` envelope whose payload, within 120 bytes, starts
     `{"type":"idle_notification"` and names the same `from":"NAME"` within 160 bytes after that (JSON-escaped
     or raw): a named teammate went idle, whatever its `idleReason`. It makes `.teammateIdle(NAME, at:)`, with the payload's own
     `timestamp` when it has one, and it finishes every tracked id that is `a`, NAME, `-` and 16 hex digits
     (the shape of a teammate's `agent_id`) whose `startedAt` is at or before that time. An earlier teammate of
     the same name going idle says nothing about one spawned since. A notification with no timestamp finishes
     every such id. A payload quoted outside its envelope (a Read of a fixture, say), or under an envelope
     that names someone else, finishes nobody. A teammate whose turn failed (a usage limit) sends this and no
     `SubagentStop`, which held its lead's pet down until the 3 hour expiry. Any `idleReason` counts, because a
     teammate that a message wakes again gets a fresh `SubagentStart` for the same `agent_id`: on 2026-10-05 every
     turn of three teammates in one lead ended with a `SubagentStop` and every later turn began with a
     `SubagentStart`, an idle teammate's within a second of the lead's `SendMessage`, while the teammate went on
     in the same transcript file. The scan runs before that start is recorded, so it never finishes the new run.
   - Every `agent-message from=` followed by `\"ID\"` (the JSON-escaped form) or `"ID"` (the raw form),
     where the marker `[Subagent hand-back]` follows within 400 bytes and before the next
     `agent-message from=`. That makes `.finished(ID)`.

   The four markers are named constants on the scanner. Only a `.finished` id leaves the set. An
   `.interim` id stays tracked, and the cleanup reports how many tracked ids the scan saw as interim
   without a `.finished` for them. The offset moves to the end of the last complete line read, so a line
   still being written is read again next time. A missing or unreadable transcript is a no-op.
2. **Expiry.** Entries whose `startedAt` is more than 3 hours old leave the set, and the hook logs one
   `SubagentExpired` line per entry. This is the safety net for a completion the scan cannot see.

The same id can complete more than once, because an agent resumed by a message gets a fresh
`SubagentStart` and a fresh notification. The scan runs before the start is recorded, so an old
notification never removes the new run. When the set is still wrong, `agent-pet clear-subagents`
empties it by hand, and `agent-pet scan-transcript --path FILE` shows exactly which events the scanner
reads from a transcript, without touching any record.

The hook path must be fast (<50 ms) and never throw. Unknown JSON, missing fields or a missing
state dir all exit 0 quietly.

Every handled hook appends one line to `~/.agent-pet/hooks.log`: ISO timestamp, event name, the first 8
characters of the session id, the `agent_id` or `-`, and the record state after the write as
`visible=<bool> agents=<count>`. A `PreToolUse` line then adds `tool=<tool_name>`, a `Notification` line
`type=<notification_type>`, a `SessionEnd` line `reason=<reason>`, a `SessionStart` line `source=<source>`, and a
line whose record ended up held back `held=true`, and a `Stop` line whose
cleanup found any completed, interim or expired subagent adds `completed=<n> interim=<k> expired=<m>`. The cleanup can also write its own lines before
the event's line: `SubagentExpired <session> <agent_id> startedAt=<ISO timestamp>` per expired entry, and
`TranscriptReadTruncated <session> - skippedBytes=<count>` when the 64 MiB cap applied. The log is truncated before the append once it passes 1 MiB, the same rule
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
  `visibleFrame.minY + 4` of the display the DisplayChooser picks, so it rides above the Dock. The
  default picks `NSScreen.main`, else the first screen, as before.
- With a `display` other than `focused`, the daemon observes
  `NSApplication.didChangeScreenParametersNotification`. On it every pet, a diving one included, is
  re-placed on the chosen display with its home at the same fraction of the width
  (`LaneLayout.carriedHorizontalCenter`). Only the window frame moves, so no animation restarts, and
  no pet stays on a display that went away. The `focused` default ignores the notification, as
  upstream does.
- Animation: sprite frames at 8 fps, walk speed 40 px/s, turn around at lane bounds (renderer flips horizontally for
  leftward travel), random idle pauses of 1 to 3 s.
- Mood: `ready` walks and occasionally plays `wave`; `needsInput` stands on `idle` with a bobbing `!` bubble;
  `blocked` plays `sit` with a `?` bubble.
- Left click: focus the session, then hide. Right click: hide only. Focus is the configured Focuser,
  described under "Focusing a session".
- What is on screen comes from `PetDisplayPlanner`: enabled, live records, oldest `updatedAt` first,
  passed through the Grouping contract, keeping each group with at least one waiting member (see "Groups"). Each item
  carries the owner (for sprite, accent and label), the mood, the waiting member's message, the bubble
  caption, every member's session id, and the FocusRequest a click hands the Focuser. Without `group`
  on any record every group is one session, so this is exactly one pet per visible session.
- A click (either button) hides every member of the pet, not only the one that was focused.
- The daemon polls `~/.agent-pet/sessions/` every 300 ms (mtime of the dir, then file contents on
  change) and reconciles windows to records. Liveness check every 5 s.
- The same poll signs every SessionSource directory the same way. On change the daemon reconciles every
  record again, which re-resolves every visible pet's label and pushes it into the existing `PetView`, so a
  `/rename` shows up within one poll interval without recreating the window or restarting the animation, and
  a session that went `busy` is seen as well (see "Settling").
- The same poll checks the config file's mtime. On change the daemon reloads it, rebuilds the contracts
  and reconciles every record again, so no restart is needed after editing it.

### Held back

A pet exists to fetch the user, so it never comes up for the pane he is already looking at. A terminal
integration says which pane that is by writing `~/.agent-pet/focus.json`, `{"focusTarget": "<target>", "pid":
<its own pid>}`, on every change, and `"focusTarget": null` when nothing of its own is in front (Termie writes
`termie:<pane id>`, the same string hq stamps as the record's `focusTarget`). `FocusedTarget.current()` reads it
and ignores it unless the writer pid is alive, so a terminal that crashed while focused holds nothing back.

Every show a hook makes (`Stop`, the needs-input notifications) reads it inside the record lock. When the
record's `focusTarget` is the one in front, the record keeps the new mood and message but stays hidden, with
`held` and `heldAt`, so the pet never flashes up and down. The integration then calls `release --focus-target T
--grace S` when the user leaves that pane: inside S seconds of the hold, a session that still wants him
(enabled, not busy, no subagents) gets its pet; past S, staying on the pane counted as seeing it, so the hold is
dropped and nothing comes up for that turn. A prompt in between (`UserPromptSubmit` hides, and so drops the
hold) also keeps it down. The `show` command never holds back: it is a direct request.

A hold stamps `waitingSince` like a show does, and a release keeps it, so a released pet still settles from the
moment its session started waiting and a `!` command since then still keeps it down (see "Settling").

Because the integration writes the file before it runs `release`, a hook deciding at the same moment either
still sees the old pane and holds (which the `release` then answers) or already sees the new one and shows.

### Groups

Sessions that share a `group` share one pet. `SharedKeyGrouping` keys each record by `group`, else its
session id, and the planner applies these rules to the live members of each key:

- A group with no live member has no pet, and the 5 s sweep deletes dead records as before.
- A visible `needsInput` or `blocked` member is waiting at once, whatever the other members are doing.
- A visible `ready` member is waiting only when no live member is working, that is, no member is `busy`
  and no member tracks a subagent. Until then the ready member stays visible in its record and the pet
  stays hidden, so a ticket's dev, review and QA tabs do not interrupt while any of them is still at work.
  When the last one finishes, the pet appears with the held `ready`. A member the user dismissed is not
  visible and not `busy`, so it counts as done.
- The pet is visible while any live member is waiting. The mood is the strongest among the waiting
  members: `needsInput`, then `blocked`, then `ready`.
- A group of one live member ignores the working rule and shows whenever it is visible, exactly as
  before groups existed. Hooks never leave a lone session visible and working, so the rule would change
  nothing there, and the exception makes that a guarantee for any record.
- When the group has more than one live member, the bubble names the most recently updated waiting
  member: its nickname, its label, its Claude session name, or else `#` and the last 4 characters of its
  session id. The bubble then widens to hold the caption, and shows even for `ready`, which otherwise
  has no bubble.
- A click focuses the most recently updated waiting member, else the owner. `FocusRequest.group` and
  so `AGENT_PET_GROUP` are the group key.
- The owner is the live member flagged `owner`, else the live member with the earliest `enrolledAt`
  (falling back to `updatedAt` for a record without it). The pet's sprite, accent and label come from
  the owner, so when the owner exits the next member takes over on the next poll.
- Subagent tracking stays per session: a member's running subagents hide that member, and they hold
  back the `ready` of the others through the working rule above, never their `needsInput`.

### Settling

A session that has just started waiting often stops again within a moment: a message queued while Claude worked
is submitted about 0.1 s after the `Stop` that ends the turn (a `UserPromptSubmit` follows), and a `!` command
queued the same way runs right after it. So the planner can hold a pet back until its session has stayed waiting
for `settleSeconds` (config key `settleSeconds`, default 0, `AgentPetConfiguration.defaultSettleSeconds`, so with no
config a pet comes up at once, as upstream), and one that stops waiting inside that time never comes up at all. The hooks stay instant and nothing sleeps: the hook
only stamps `waitingSince`, and the daemon decides.

- A visible member whose `waitingSince` is less than `settleSeconds` old is treated as not visible, unless its pet
  is already up (emerging or grounded, not diving). The delay only keeps a pet from coming up; it never takes one
  down. A pet that is diving is not up, so a `Stop` during a dive waits out the delay too.
- `needsInput` settles the same way. A permission prompt is answered by a person, which takes longer than a
  second, so the delay costs it nothing, and a prompt that a hook or an auto mode answers at once never flashes a
  pet. One rule for every mood is also easier to reason about.
- With `holdWhileBusy` set to `true` in the config (off by default): a `!` command (Claude Code's bash mode)
  fires no hook at all, typed or queued: `hooks.log` shows the `Stop`
  before it and the `Stop` after Claude's reply, nothing between. Claude Code does write `status: "busy"` to its
  own session file within about 0.1 s of the command starting, and `idle` when it is done. So a visible `ready`
  member whose Claude session file says `busy` with a `statusUpdatedAt` at or after its `waitingSince` is treated
  as not visible and as working, whether its pet is up or not: it holds back the `ready` of its group and an
  up pet dives. A `busy` written before `waitingSince` is the turn that just ended and is ignored. `needsInput`
  is exempt, because a subagent's permission prompt arrives while the main turn is still `busy`.
- The daemon re-plans on any change to the pet records, to a Claude session file (so a `busy` is seen within one
  poll), and once the earliest settling pet is due (`nextSettleDeadline`), so a pet comes up between
  `settleSeconds` and `settleSeconds` plus one poll interval after its `Stop`.
- `settleSeconds` 0 turns the delay off. The `busy` rule is separate and follows `holdWhileBusy` alone.
- Status `shell` is not read: it means idle with background shell tasks running, not a `!` command.

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
- **Every way a pet goes away dives**: hidden (a hook, `hide`, a click, its pane focused), removed (`remove`, session
  end, the liveness sweep), disabled (`off`), a group whose last waiting member stops waiting, and, with
  `diveOnExit` set to `true` in the config (off by default, read when the daemon starts), the daemon itself
  stopping (SIGTERM from launchd on a restart or uninstall, or SIGINT), which dives every pet and exits once they are
  under (2 s at most, and 3 s after the signal even when the main thread is stuck, since the signal is handled on a
  queue of its own; a second signal exits at once). Records are untouched, so a daemon that starts again brings
  the visible pets back up. Without `diveOnExit` the signals keep their default action, as upstream.
- A pet hidden mid-emerge dives from its current offset and still plays every `dive` frame over the full 350 ms
  descent; its label fades from its current opacity. Only a pet with nothing above ground yet goes straight under.
- An emerge or dive advances at most 1/15 s per animation tick, so a late tick (a busy main thread or Mac) slows
  the move down rather than skipping its frames. A diving window is not re-placed, so it dives where it was even if
  `NSScreen.main` moves to another display.

## Sprite contract

`SpriteContract.swift` is fixed. `PixelFrame` derives its square side length per frame, so packs may be 16, 24 or
32 px and the renderer still scales by 4. `SpriteSheet` carries `frameSize` and `colorsByCharacter`; `SpritePalette`
is data (a `[Character: NSColor]`, nothing else) and the compiled-in palette is its default instance, so a sprite
image depends only on its pack, animation, frame and facing, plus the session's chosen accent when the pack names
`accentInks` (the recolor swaps palette entries and leaves the contract types alone). The
initializer is `SpriteSheet(idle:walk:wave:sit:emerge:dive:colorsByCharacter:)` with `emerge` and `dive` defaulting
to `[]`, and `SpriteAnimationName` covers all six. `ClaudeSprite.swift` provides the built-in art as
`extension SpriteSheet { static let claude8Bit: SpriteSheet }`: frames of `PixelInk` raw characters, `.` transparent,
idle 2 frames, walk 4, wave 3, sit 2, facing right for the renderer to mirror. The character is a squat, rounded,
friendly orange critter in the spirit of the pixel Claude persona Anthropic uses (terracotta body, two dark eyes,
tiny stub legs, no mouth or a tiny one), original art rather than a copy of any Anthropic asset, with a fixed teal
scarf drawn in the `scarf` and `scarfShade` inks.

### Sprite packs

Art also ships as plain-text packs so anyone can draw a new pet in a text editor:

```
sprites/<pack-name>/
  pack.json      {"name":"claude","frameSize":16,"accent":"orange",
                  "palette":{"o":"#D97757","O":"#B85C3E","#":"#3B2418","e":"#1A1A1A","w":"#F5D0BF",
                             "A":"#2EE6D6","a":"#20A196"},
                  "accentInks":{"accent":"A","shade":"a"}}
  idle.txt       frames of <frameSize> rows, separated by one blank line
  walk.txt, wave.txt, sit.txt
  emerge.txt, dive.txt         optional, 3 frames each recommended
```

- Every character in `palette` maps to a fixed hex color. `.` and any character not in `palette`
  are transparent. No character is reserved. Only the inks a pack names in `accentInks` ever show the
  session accent, see "Accent on the sprite".
- `accent` is optional and holds one `AccentColor` name. It becomes the accent of every session that gets the
  pack, see "Sprite assignment". An unknown name is ignored: the daemon logs one line and the pack falls back to
  its dominant color.
- The repo ships eight packs (`claude` is the same art as `claude8Bit` exported to text):

  | pack      | accent | accentInks                      |
  |-----------|--------|---------------------------------|
  | claude    | orange | none, the reserved original     |
  | golem     | green  | `A`/`a`, the chest gem          |
  | hatchling | cyan   | `A`/`a`, the scarf              |
  | mossling  | red    | `A`/`a`, the cap                |
  | nimbus    | blue   | `A`/`a`, the lightning bolts    |
  | seon      | yellow | `A`/`a`, the face mark          |
  | tinowl    | purple | `A`/`a`, the bow tie            |
  | walle     | yellow | none                            |

- `install.sh` copies each shipped pack directory into `~/.agent-pet/sprites/` on every install. An installed pack
  with a shipped name is deleted and copied fresh, and an installed pack whose name is not shipped is left alone.
  To customize a shipped pack, copy it under a new name. Every installed pack is in the assignment pool, so adding
  a pet is adding a directory.
- The daemon loads packs from `~/.agent-pet/sprites/<name>/` and the config's `spriteDirectories` at
  startup. Every reconcile tick (0.3 s) it lists those folders again, loads a pack that appeared, drops
  one that went away, and re-reads a pack when its directory mtime changes or it is now read from a
  different folder. A config change applies new `spriteDirectories` on the next tick. A pack that fails to parse logs one line and falls back to
  `claude8Bit`; one without `emerge.txt` or `dive.txt` holds `idle` frame 0 during the offset move.
- Art direction shared by every pack: idle 2 = breathe or blink; walk 4 = a leg cycle facing right; wave 3 = raise
  something, hold, lower; sit 2 = settle lower, then eyes closed. emerge = eyes closed under a few loose dirt pixels,
  then eyes open wide, then a shake. dive = look down, squash flat, then a small dust puff where the body was.

## Demo

`agent-pet demo` is a short tour for people who have never seen a pet. It
shows only the core flow, then one card that points at Configuration. The `states` scene holds the two
moods a hook sets (`ready`, `needsInput`) side by side for 9.5 s, and the hidden working state as an
empty dashed spot. It leaves out `blocked`, because no hook sets it and a user never sees it. Each slot has a
`DemoStateLabelView` above it in the panel style. The other scenes are a click and the last card. It does not show lanes, the dive on return, groups, nametags or reserved
sprites, and it uses the pill labels a new user sees. It changes nothing for
anyone who never runs it, and it never touches real state:

- The cast is a list of `PetSession` values built in memory (`DemoScript.cast`, session ids prefixed
  `demo-`, `pid` set to the demo's own process so `ProcessLiveness` keeps them alive). Nothing is written
  to `~/.agent-pet`, the daemon is never ensured, no Focuser runs and no ColorSync types into a pane. A
  dry run in a fresh home leaves it empty.
- `DemoScript.scenes` is data: each `DemoScene` has a name, a one line caption, a duration, a label
  placement, steps at offsets into the scene (show an actor with a mood, hide actors, click an actor,
  show or hide the title card), an optional hold offset, and optional state slots (a label and an actor,
  or no actor for the working state). Only the title has no hold offset.
- `DemoRunner` is the timeline. It keeps the cast's visibility and moods, and after every step it runs the
  real `PetDisplayPlanner` with `SharedKeyGrouping`, so the moods in the demo are the shipped
  rules, not a copy. Entering a scene resets the cast, so `--scene` and
  skipping always start clean. The click scene shows a click instead of a description:
  `pointCursor` makes the stage draw `DemoCursorView`, a 12 by 17 pixel arrow at 4 px per pixel in
  `DemoPalette.text` with a `DemoPalette.frame` outline, in its own clear window. The arrow eases toward
  the pet's sprite and follows it. `click` presses the arrow down one art pixel for 0.2 s and hides
  every member of the pet, so it dives. `showTerminal` fades in `DemoTerminalView`, a simple picture of a
  Claude Code session: a title bar (three dots, the session label, an accent underline), a header with
  the idle frame of the `claude` pack and two lines (the product name in pixel bold, the
  folder), the user message after `>`, the reply after a bullet in the pet's
  accent, an input line with a chevron and a block cursor between two thin rules, and a muted status
  line. The content is generic: no version, model, account, plan, company or permission mode. These are drawings only: nothing moves the system cursor and nothing posts a system event, and a
  test scans the demo sources for the APIs that could (cursor warps, `CGEvent`, `NSEvent` mouse, key and
  enter or exit constructors, `AXUIElement` posting and actions, AppleScript). The one posted event is
  app-local: `DemoApplication.stopRunLoop()` posts an `.applicationDefined` event to its own queue to wake
  its run loop, and the test allows `postEvent(` only there. The demo pets have no session, so their windows
  ignore the mouse and the stage gives `PetView` no interaction handler.
- Interactive mode is the default (`waitsForUser`). The clock of a scene stops at its hold offset, after
  its animation, and the runner waits until `skipToNextScene()`. The steps after the hold offset are the
  timed exit and run only with `--auto`. The title has no hold offset, so it moves on by itself after
  6 s. `--auto`, `--dry-run`, `--snapshot` and the tests use the timed mode, where a scene ends at its
  duration.
- `DemoPlayback` drives the runner from a 30 Hz timer, scaled by `--speed`, and owns SIGINT and SIGTERM
  through dispatch signal sources: the stage tears down every window, a line is printed, and the exit code is
  128 plus the signal. `handle(key:)` takes a `DemoKey`: space calls `skipToNextScene()`, esc stops the
  demo with exit code 0. A `DemoFocus` takes the focus at start and gets it back at every end (the
  last scene, esc, SIGINT or SIGTERM). At the end it waits for the stage to settle (pets dived, panels
  faded) for at most 2.5 s, then tears down.
- Keys: `DemoAppFocus` remembers the frontmost app, activates the demo once, and makes `DemoKeyWindow`
  key. That window is a 1 by 1 clear borderless window that can become key and ignores the mouse, so
  the title card, which has no caption, also gets the keys. A local key-down monitor sends space and esc
  without command, control or option to the playback, and swallows them. Other keys pass. A local
  monitor sees keys only while the demo is the active app, so a demo that lost the focus waits and
  never activates again. At the end, the focus goes back to the remembered app only when the demo is
  still the active app.
- Getting the keys back: `NSApp.activate()` at start can be refused, for example from a background
  shell, and the user can click another app. Every text panel (caption, title card, state label,
  terminal) takes mouse clicks. A click calls `DemoAppFocus.reclaimFocus()`, which activates the demo and
  makes `DemoKeyWindow` key again, and does not change the scene. The demo never activates itself except
  at start and after such a click. `applicationDidBecomeActive` and `applicationDidResignActive` set
  `hasFocus` on the stage, and the caption and the title card change their key hint from
  `DemoScript.focusedKeyHint` ("space: next   esc: quit") to `DemoScript.unfocusedKeyHint` ("click here,
  then press space"), drawn in the brighter text color. The pets, the cursor and the empty spot still
  ignore the mouse.
- The AppKit stage reuses `PetView`, `PetWindow`, `PetAnimator` and `PetSpriteFrames`, so the pets are drawn
  exactly as the daemon draws them. It is built from `AgentPetContracts.loaded()`: the sprite loader is
  the configured `spritePackLoader`, so packs in `spriteDirectories` are found, and the screen is the one
  the configured `displayChooser` picks. From a checkout, the `sprites/` directory of the repo backs up
  the installed packs. The demo pets stand on a row of their own, above the daemon's pets: their ground
  is lifted by the full height of a daemon pet (the tallest installed pack, the configured label
  placement, the bubble) plus 16 pt, and the caption sits above that. A real pet is therefore never
  under a demo pet, and a click on a real pet still reaches it. It eases a pet's lane home when the lane count changes. Every panel
  uses one frame (`DemoPanelFrame`): a border, a rim and a fill from `DemoPalette`, cut pixel corners, one
  padding and three pixel sizes of `DemoPixelFont`, a proportional 5 by 7 pixel font with lowercase and
  descenders. It is not `PixelFont`: that one is the 3 by 5 uppercase nametag font, sized to fit a pill
  on the pet, and caption sentences in it read as shouting and wrap badly. The two share the ink test
  (`PixelFont.isInk`). The only other colors are the eight accent colors. The caption has a stripe and a progress
  bar in the accent of the first pet its scene shows. The title card has an accent underline. It is at most 60% of the screen width and never wider
  than 1100 pt. `DemoPixelFont.wrap` breaks its title and subtitle at word boundaries onto centered lines.
  Its top padding is 1.5 times the panel padding and its bottom padding is 2 times, with the key hint
  near the bottom edge. Text is
  off-white or a muted gray, and a test measures that both have at least 4.5:1 contrast on the panel
  tones. Nothing flashes or shakes: panels fade over 0.45 s.
- `--dry-run` swaps in `DemoTranscriptStage`, which prints the timeline, so the whole flow is testable
  without a window server. `--snapshot DIR` renders the panels offscreen to PNGs.

## Focusing a session

A left click on a pet, and the `focus` command, build a `FocusRequest` (session id, pid, focus target,
group, agent, tmux target, and whether a client switch is allowed) and hand it to the configured Focuser.
The click takes the tmux target from the record or else from the Claude session file; the `focus`
command reads the record only. The default focuser is `tmux-iterm`, `TmuxItermFocuser`, which takes its
tmux and terminal calls through two small protocols so tests can record them:

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

### Command focuser

With `"focuser": {"kind": "command", "command": [ARGV]}` a click runs ARGV instead, with no tmux and no
AppleScript. The child inherits the daemon's environment plus `AGENT_PET_SESSION_ID`, `AGENT_PET_PID` (the
record's pid, else the Claude session file's, else empty), `AGENT_PET_FOCUS_TARGET` (empty when unset),
`AGENT_PET_GROUP` (the session id until grouping exists) and `AGENT_PET_AGENT`. Stdin, stdout and stderr are
`/dev/null`. After 5 seconds it gets SIGTERM, and SIGKILL when it is still running a second later. The exit status is ignored except for one stderr line
(`daemon.log` for a click) when it is not 0, when it timed out, or when it could not start. The daemon
supervises the child on a background thread, so a slow command never stalls the animation; the `focus`
command waits for it.

### Finding the tmux binary

The daemon runs under launchd with a minimal `PATH`, so `/usr/bin/env tmux` failed for every call the
daemon made while hooks and the CLI, which run from real shells, worked. `TmuxCommandRunner` instead
resolves the binary once into a `static let` and runs it by absolute path: `$TMUX_EXECUTABLE` when it
is set and executable, then `/opt/homebrew/bin/tmux`, `/usr/local/bin/tmux`, `/usr/bin/tmux`, then the
first `tmux` on `PATH`. When none of those exists every tmux call is a silent no-op, as before.
`$TMUX_EXECUTABLE` also lets a test point the tool at a stub binary.

## Prompt bar color sync

This is the ColorSync contract's default, `tmux-color`. `"colorSync": "none"` in the config turns every
part of it off, for `on` and `off` alike.

Claude Code has a per-session prompt bar color, set by
`/color [red|blue|green|yellow|purple|orange|pink|cyan|default]` (binary 2.1.278 marks it
`immediate` and `supportsNonInteractive`). The user never sets it, so the tool owns it, and
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
synchronous, needs `/pet` again to pick the new frontmatter up. Reading completion from the transcript did not
change the hook set, so a session that is already enrolled needs no re-enrollment for it: the next hook runs the
new binary. The absolute path is deliberate: hook shells do
not reliably have `~/.local/bin` on `PATH`.
Invoking `/pet` is the whole opt-in; the body tells Claude to run `agent-pet on` with an optional nickname, accent
and sprite from `$ARGUMENTS`, or `agent-pet off` for `/pet off`, then report the sprite and accent in one line.

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

## Contracts

Each contract is a protocol in `AgentPetCore` with today's behavior as the default implementation.
`AgentPetContracts` builds the set from an `AgentPetConfiguration`, so a missing config file always gives
the defaults.

| contract | default | alternative | config key |
|---|---|---|---|
| Focuser | `tmux-iterm`, `TmuxItermFocuser` | `command`, `CommandFocuser` | `focuser` |
| SessionSource | `~/.claude/sessions` | any list of directories | `sessionDirectories` |
| ColorSync | `tmux-color`, `TmuxPromptBarColorSync` | `none`, `DisabledColorSync` | `colorSync` |
| SpriteStrategy | least used at random, `LeastUsedSpriteStrategy` | the same with a reserved set left out of the random pick; `--sprite` is the explicit choice | `reservedSprites` |
| Sprite pack folders | `~/.agent-pet/sprites` | that folder plus any list of folders searched after it | `spriteDirectories` |
| PetGrouping | `SharedKeyGrouping`: one pet per session unless sessions name a `group` | `OnePetPerSessionGrouping` stays for comparison in tests | `--group` on the session, not config |
| LabelPlacement | `pill` under the sprite | `nametag` over the head | `labelPlacement` |
| LabelDisambiguation | off | last 4 of the owner's session id on duplicate labels | `disambiguateLabels` |
| Settle delay | none (0 s) | any number of seconds | `settleSeconds` |
| Hold while busy | off | a ready pet stays down while Claude Code's own status says `busy` (a `!` command) | `holdWhileBusy` |
| Accent inks | off: a chosen accent colors the dot, bubble and prompt bar only | the sprite's accent inks take the chosen accent too | `accentInks` |
| Dive on exit | off: SIGTERM and SIGINT end the daemon at once | the daemon dives its pets first | `diveOnExit` |
| Subagent tool calls and needsInput | off: any `PreToolUse` hides the pet | a subagent's `PreToolUse` leaves a `needsInput` pet up | `subagentToolsKeepNeedsInput` |
| DisplayChooser | `focused`, `FocusedDisplayChooser`: the display with keyboard focus, else the first | `primary`, `PrimaryDisplayChooser`; `name:<name>`, `NamedDisplayChooser`, primary while that display is absent | `display` |

The accent stays as before: the pack accent, or `--accent`. Both label placements are drawn by `PetView`;
the placement and the disambiguation are decided in `AgentPetCore`, so they are testable without AppKit.
So is the display: the overlay hands the chooser an `AttachedDisplays` (each screen's `localizedName` in
`NSScreen.screens` order and the index of `NSScreen.main`) and takes back an index.

## Configuration

`~/.agent-pet/config.json`, or the file `AGENT_PET_CONFIG` names. It is read by every command that
needs a contract and by the daemon, which reloads it on change. A missing file, unreadable JSON, a
missing key, an unknown key and a bad value all mean the default for that key, never an error:

```json
{
  "focuser": { "kind": "command", "command": ["/abs/path/focus-script"] },
  "sessionDirectories": ["~/.claude/sessions", "~/.claude-*/sessions"],
  "colorSync": "none",
  "labelPlacement": "nametag",
  "disambiguateLabels": true,
  "reservedSprites": ["claude"],
  "spriteDirectories": ["~/pets/prototypes"],
  "settleSeconds": 1,
  "holdWhileBusy": true,
  "accentInks": true,
  "diveOnExit": true,
  "subagentToolsKeepNeedsInput": true,
  "display": "primary"
}
```

- `focuser.kind` is `tmux-iterm` or `command`. `command` needs a non-empty `command` array whose first
  entry is an absolute path, because launchd gives the daemon a minimal `PATH`.
- `sessionDirectories` is a list of directories holding Claude Code session files. A leading `~`
  expands to the home directory and `*`, `?` and `[...]` match within one path component. Later
  directories never override a session id an earlier one already had. An empty list means the default.
- `colorSync` is `tmux-color` or `none`.
- `labelPlacement` is `pill` or `nametag`.
- `disambiguateLabels` is a boolean, default `false`.
- `reservedSprites` is a list of pack names never chosen by random assignment. Non-string and empty
  entries are dropped.
- `spriteDirectories` is a list of extra folders of sprite packs, each laid out like
  `~/.agent-pet/sprites/`. `~` and the wildcards expand as in `sessionDirectories`. `SpritePackLoader`
  searches `~/.agent-pet/sprites/` first and then these folders in order, and the first folder holding
  a pack name wins, so an installed pack always beats one of the same name here. Its packs are
  installed packs for every purpose: the random pool, `reservedSprites`, `packs`, `render --pack`,
  `preview --sprite` and `on --sprite`. A folder that is missing, unreadable or not an absolute path
  after expansion is skipped, and so is a clashing pack. The daemon logs each such problem once to
  `daemon.log` and again only if it goes away and comes back. Non-string and empty entries are dropped.

- `settleSeconds` is a number of seconds, default `0`: how long a session must stay waiting before its pet
  comes up, see "Settling". `0` is no delay. A negative or non-number value means the default.
- `holdWhileBusy` is a boolean, default `false`: keep a ready pet down while its Claude session file says
  `busy` after the turn ended, see "Settling".
- `accentInks` is a boolean, default `false`: a chosen accent also paints the pack's `accentInks`, see
  "Accent on the sprite".
- `diveOnExit` is a boolean, default `false`: a daemon stopped by SIGTERM or SIGINT dives its pets
  before it exits, see "Emerge and dive". Read when the daemon starts, so a change needs a restart.
- `subagentToolsKeepNeedsInput` is a boolean, default `false`: a `PreToolUse` from a subagent leaves a visible
  `needsInput` pet up, see "`hook` dispatch".
- `display` is `focused` (the default), `primary` or `name:<localizedName>`. `primary` is
  `NSScreen.screens.first`, the display with the menu bar, so it follows macOS when the primary changes.
  `name:` matches `NSScreen.localizedName` exactly and falls back to the primary display while no
  attached display has that name. An empty name, any other string and a non-string mean the default.
  A change takes effect on the reload, because the reload rebuilds the contracts and reconciles, which
  recomputes every home on the newly chosen display. `primary` may be the better default; it stays
  `focused` so that no config keeps today's behavior, and that call is left to the maintainer.

## Tests

`scripts/test.sh` runs `swift test` for `AgentPetTests`, adding the framework flags `swift test` needs on a
machine with only the Command Line Tools, where Swift Testing is not on the default search path. The characterization tests run the built `agent-pet` binary in a
temporary home (`HOME` and `CFFIXED_USER_HOME`, since `NSHomeDirectory` ignores `HOME`), with
`TMUX_EXECUTABLE` pointing at a stub that records its arguments and a `daemon.pid` naming the test process,
so no test reads or writes `~/.agent-pet` or `~/.claude`, calls `launchctl` or starts a daemon. The three
tests that run a real `focus` with a client switch skip themselves while iTerm2, Terminal or Ghostty is
running, so they can never move a real terminal. The contract tests drive the protocols in process with
recording fakes. They were written against the code before the split into `AgentPetCore` and passed there
first.

## Code rules for every file

- No single-letter or abbreviated names, including loop variables and closure parameters.
- Zero comments unless explaining a non-obvious why. No section-divider comments.
- No magic strings: hook event names, mood names, accent names, bundle ids, tmux subcommands and
  flags, and file names are enums or `static let` constants.
- Every `switch` over an enum is exhaustive with no `default`.
- Avoid `as!` and `try!`; decode with `Codable`. No em dashes in any prose.
