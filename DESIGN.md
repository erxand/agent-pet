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
    State/                     PetSessionStore, ClaudeSessionDirectory, tmux run, hook log, subagent tracking, DirectoryChangeMonitor and RescanGate
    PetStates/                 PetStates (physics, input, visibility, level, their resolution and files), WindowDetection, SpaceMotion, see "Pet states"
    Ground/                    GroundProfile, GroundBody and GroundPlacement, DockTracker and the Dock geometry rules, see "The Dock as ground"
    Sprites/                   SpriteContract (fixed), PixelRenderer, ClaudeSprite (claude8Bit art), SpritePackLoader, SpritePackRegistry, SpritePackAssignment, SpritePackAccent, PackAccentResolver, SpriteAccentTint, PixelFont (nametag glyphs), TerminalSpriteRenderer
    Demo/                      DemoScript (scenes and cast), DemoRunner (timeline), DemoPlayback (clock and signals), DemoPixelFont, DemoCommand, see "Demo"
  Sources/agent-pet/
    main.swift                 hands argv and the overlay to AgentPetCommandLine
    Overlay/                   NSApplication daemon, PetWindow, PetAnimator, PetSpriteFrames, lanes, clicks, AppWindowWatcher, PetSpaceFlight, SystemDockSensing
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
  dock-access.json             the daemon's own Accessibility state, see "The Dock as ground"
  control/dock-access-ask      a request from `dock-access --ask`, consumed by the daemon
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
- `groupMode` is optional and absent unless `--group-mode lead` was passed; `--group-mode shared` or an empty
  `--group-mode ""` removes it.
  A group follows the lead rules when its flagged owner's own `groupMode` is `lead`, see "Lead groups".
  An unknown `groupMode` value reads as absent, so a record a newer build wrote stays readable.
- `disambiguator` and `disambiguationScope` are optional and absent unless `--disambiguator TEXT` and
  `--disambiguation-scope KEY` were passed, and an empty value removes each. They change a label only on a
  clash, see "Session differentiation".
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
   redraw, so the suffix goes away when one of them hides. A pet whose record has a `disambiguator`
   and a `disambiguationScope` gets a space and its `disambiguator` instead, when at least one other
   clashing pet has the same scope and no other clashing pet in that scope has the same
   `disambiguator`. Every other clashing pet keeps the session id suffix, so a clash across scopes
   reads as before.
4. **Lane position**: pets never overlap, and the lanes together cover the whole usable width. Lane `i`
   of `n` is the `i`-th of `n` equal slices of the width (`LaneLayout.lane(index:laneCount:screenFrame:)`),
   with its home at the slice's middle, so a lone pet's lane is the whole screen. Lanes go to pets in the order they stand: `LaneLayout.assignedLanes` keeps the
   left to right order of the pets already up and picks, among the order keeping choices, the one
   that moves them least, and a new pet takes a lane left free, where it emerges. A pet in a float holds
   no lane at all, so the pets on the ground share the whole width; when it lands the lanes are divided
   again, from where the pets are then, so nobody crosses the screen. `LaneRedivision.apply` is that step,
   pure and tested. A pet whose home moves keeps where it stands, and when it ends up outside its wander
   range it walks, at 40 px/s with `walk` frames and whatever its mood, only as far as the near end of the
   range, then wanders again. Within
   `LaneLayout.wanderHalfWidth(laneCount:screenFrame:minimumGap:)`: half the slice less half the gap, so it
   walks the whole slice except half a gap at each end, and two neighbours at the ends of their ranges
   still keep the gap. Lanes are divided again as pets come and go, and a pet left outside its new range
   walks there. Inside its range a pet wanders like a simple game character (`Stroll`, see "Wandering"). The gap is the widest pet on the
   ground, label and bubble included, plus 8 px (`LaneLayout.minimumGroundGap`), capped at 90% of the slice
   width so every lane stays reachable. So the names of two pets side by side never overlap: a label or
   bubble caption wider than that cap less 8 px, or longer than 28 characters, is shortened with an
   ellipsis (`PetAppearance.fitted(toWidth:)`, `LabelShortening`). The part that tells pets apart stays:
   a final `(...)` group or a short last word (6 characters or fewer, such as `T1` or a disambiguation
   suffix) is kept whole, and the text before it keeps its start and up to its last 4 characters around
   the ellipsis, the start giving way first (`TIC…140 (DEV)`), since numbers that tell tickets apart sit at
   the end of it. A label with neither is cut in the middle. The lengths are found by binary search when
   the pets are planned, never per frame. A change of the screen the pets use plans them again at the
   next poll, so the labels are fitted and the gap worked out for the new width. After every lane
   assignment, for any reason, two neighbours on the ground standing closer than the current gap both
   walk home. Only a sprite wider than
   the cap, which takes about ten pets on a laptop screen, can still touch its neighbour. On the ground a
   step that would cross a neighbour, or bring it closer than that gap, is not taken: the pet runs in place,
   and a wandering pet turns round when its next walk starts. A pet walking home that is refused sends
   the neighbour in its way home too, so a walker behind a pet that stands still (a question) never waits
   for ever. Moving apart is always allowed. Floating and diving pets are not in the way. Only the two
   neighbours in a per-frame sorted list are checked. When the display the pets use changes (for example
   `focused` and focus moves to another screen) every home and every standing position is carried to the
   same fraction of the new screen, the standing position held a half window inside its edges
   (`LaneRedivision.carry`), and the lanes are divided again at once, which is the one place a pet jumps.

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
`--nickname`, `--label`, `--accent`, `--agent`, `--tmux`, `--pid`, `--sprite`, `--focus-target`, `--group KEY`,
`--group-mode shared|lead`, `--disambiguator TEXT`, `--disambiguation-scope KEY`
and the `--owner` switch work on `on`, `show` and `preview` alike. An unknown `--group-mode` exits 2. `--group` puts the session in the pet named
KEY, and `--owner` makes it that pet's owner and clears `owner` on every other record of the group, see
"Groups".

| command | effect |
|---|---|
| `daemon` | run the overlay in the foreground (accessory app, no dock icon) |
| `ensure-daemon` | kickstart the launchd agent when its plist exists, otherwise start `daemon` detached if `daemon.pid` is missing or dead; idempotent, see "Daemon lifecycle" |
| `on [identity flags] [--no-color-sync]` | upsert record: enabled true, and visible false for a new or disabled record (an enabled record keeps `visible` and `held`, so a relabel never takes a pet down), `sprite` assigned if absent, then `accent` filled from that pack if absent; ensure-daemon; print one line naming the sprite and the resolved accent; then sync the prompt bar color. Re-running it updates the record in place: only the fields the flags name change, and `sprite`, `accent`, `focusTarget`, `activeSubagents` and the transcript offset are kept |
| `off [--session ID] [--no-color-sync]` | enabled false, visible false; then reset the prompt bar color |
| `show [--mood MOOD] [--message TEXT]` | if enabled: visible true, mood, message; ensure-daemon. Not enrolled or disabled: silent exit 0 |
| `hide [--session ID \| --focus-target T \| --pid N]` | visible false, `held` dropped. When a selected record is the lead of a lead group (its live flagged owner, whose own `groupMode` is `lead`), every other live member of that group that is visible and `ready`, or `held`, is hidden too and its hold dropped, see "Lead groups" |
| `release [--session ID \| --focus-target T \| --pid N] [--grace S]` | for a `held` record: drop the hold, and when the record is enabled, not working, not visible and (with `--grace`) was held less than S seconds ago, show it with the mood and message it was held with; ensure-daemon when it came up. Anything else is untouched |
| `remove [--session ID \| --focus-target T \| --pid N]` | delete the record |
| `status [--json]` | table: session id (short), label, sprite, accent, enabled, visible, mood, active subagent count, alive; plus daemon pid. `--json` prints `{"daemonPid": N or null, "sessions": [...], "states": {...}}` (`states` is described under "Pet states") with `sessionId`, `group`, `label`, `sprite`, `accent`, `agent`, `enabled`, `visible`, `mood`, `activeSubagents` (a count), `alive`, `pid`, `focusTarget` and `updatedAt` per session, plus `group` (the record's `group`, else its session id) and `owner` (true when the session is the resolved owner of its live pet, false for every other member and for a dead session), `flaggedOwner` (the record's own `owner` flag), `groupMode` (`shared` or `lead`), `disambiguator` and `disambiguationScope` (null when absent) |
| (selection) | `hide`, `release` and `remove` act on `--session`, else on every record whose `focusTarget` is `--focus-target` (what a terminal knows about its pane), else on every record whose `pid` is `--pid` (what knows the process after a `/clear` changed its id), else on `$CLAUDE_CODE_SESSION_ID` |
| `hook` | read one Claude Code hook JSON object from stdin, dispatch below; always exit 0; never write to stdout |
| `preview [--mood MOOD] [--seconds N]` | show a fake pet (sessionId `preview-<random>`, label `preview`, `sprite` assigned like `on` unless `--sprite` is given) for N seconds (default 20) so the overlay can be tested without a real session |
| `focus [--session ID] [--no-client-switch]` | run the configured Focuser the way a left click does, so focusing can be tested from a shell; exit 2 when the record is missing, or, with the `tmux-iterm` focuser, when it has no tmux target. `--no-client-switch` leaves every attached client alone: it skips both `switch-client` and the iTerm tab script, so a test can prove the window and pane selection without moving a real client. The CLI waits for a command focuser to finish |
| `clear-subagents [--session ID]` | empty `activeSubagents` under the record lock and print how many entries it dropped; exit 2 when the record is missing. The manual unwedge for a pet held hidden by a subagent the tool still counts as running |
| `render --pack NAME [--animation idle] [--frame N] [--accent COLOR]` | print one frame, recolored as a session that chose COLOR would see it (see "Accent on the sprite"), to stdout with truecolor half blocks: two pixel rows per text line, `▀` with the top pixel as foreground and the bottom as background, `▄` or a space where a pixel is transparent, so transparency shows the terminal background. Each line ends with a reset. A pack named `claude` that is not installed draws the compiled-in art. Exit 2 when `--pack` is missing, the pack does not load, the animation is unknown, N is not a frame of it, or COLOR is not an accent name. Exit 1, saying so on stderr, when the pack is not downloaded yet (see "Files iCloud has evicted") |
| `packs [--json]` | one row per installed pack: name, accent (as `on` would fill it), reserved (in the config's `reservedSprites`), and live pets (live groups whose owner uses the pack). `--json` prints `{"packs": [{"name", "accent", "reserved", "livePets", "downloaded"}]}` with `accent` null for a pack that yields none. A pack that is not downloaded yet has `downloaded` false and `accent` null, and its text row ends with `not downloaded` |
| `scan-transcript --path FILE [--from OFFSET]` | diagnostic: run `TranscriptCompletionScanner` over FILE from byte OFFSET (default 0) and print one line per event in file order, as `<byte offset> <finished\|interim> <agent_id>`. It reads the file only and touches no record; exit 2 when `--path` is missing, OFFSET is not a number of 0 or more, or the file cannot be read |
| `physics ground\|float\|auto`, `input on\|off\|auto`, `visibility shown\|hidden\|auto`, `level normal\|above BUNDLE_ID\|auto` | set one pet state for every pet, or hand it back with `auto`; prints `<state>: <value>`; exit 2 for any other value. See "Pet states" |
| `capabilities` | print one word per line, in `AgentPetCapability` order, naming each feature a caller may depend on: `release-grace` (`release --grace`), `focus-hold` (hooks read `focus.json`, see "Held back"), `lead-focus-hold` (that hold, its release and its hide cover a whole lead group), `focus-target-select` (`hide` and `remove` take `--focus-target`), `group-mode-lead` (`on --group-mode lead`, see "Lead groups"), `disambiguator` (`on --disambiguator` and `--disambiguation-scope`), `hide-labels-floating` (the `hideLabelsWhileFloating` config key), `dock-ground` (the `dockGround` config key, the `dock-access` command and the optional `jump` and `fall` animations, see "The Dock as ground") and `ground-gap` (the `groundGap` config key). It reads and writes nothing. A word is added with the feature it names and never renamed, so a caller tests for the word rather than for a version. A build without the command exits 2 with the usage text |
| `dock-access [--ask]` | print `granted`, `not granted` or `unknown`: whether the running daemon may read the Dock's exact frame through the Accessibility API, see "The Dock as ground". The answer is the daemon's, read from `dock-access.json`, never the command's own process, because a command started from a terminal is judged by the terminal's grant. `unknown` means no running daemon has written a report. Without `--ask` it reads and never prompts. `--ask` ensures the daemon, leaves `control/dock-access-ask`, and waits up to 3 s for the daemon to call macOS itself (which shows the system prompt) and report. Exit 0 only for `granted` |
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
  `com.agent-pet.daemon`, `ProgramArguments` of the absolute binary path plus `daemon`,
  `RunAtLoad` true and `KeepAlive` `{SuccessfulExit: false}`, `ProcessType` `Interactive`, `LimitLoadToSessionType` `Aqua`,
  `EnvironmentVariables` with `PATH` of
  `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`, and both
  `StandardOutPath` and `StandardErrorPath` set to `~/.agent-pet/daemon.log`. It then runs
  `launchctl bootout gui/<uid>/com.agent-pet.daemon`, ignoring failure, and
  `launchctl bootstrap gui/<uid> <plist>`. `uninstall.sh` does the bootout and removes the plist.
- `KeepAlive` means a crashed daemon is back within seconds, with no CLI call needed. Only a failed exit is
  relaunched: a daemon that leaves on purpose (another daemon already runs, a refused home, a signal) exits 0
  and stays down until something ensures it again, instead of coming back every 10 s.
- `ensure-daemon` and `DaemonCommand.ensureRunning()`: when the plist exists, run
  `launchctl kickstart gui/<uid>/com.agent-pet.daemon` and return. There is no `-k`, so a running
  daemon is left alone. A kickstart of a service that was booted out fails with "could not find
  service", so a failed kickstart is followed by `launchctl bootstrap gui/<uid> <plist>`, which
  loads the agent and starts it through `RunAtLoad`. When the plist is missing, fall back to the
  old detached spawn, guarded by the liveness check on `daemon.pid`. The spawn disclaims responsibility
  where macOS allows it, so the daemon is not judged by the terminal that ran the command (see "Who is asked"), except
  for a binary inside a folder macOS guards per app (`~/Desktop`, `~/Documents`, `~/Downloads`, iCloud Drive,
  `~/Library/CloudStorage`, `/Volumes`, `/Network`). A disclaimed daemon there is judged by its own signature for that folder
  too, which can mean a question for the user on every new build, and one such daemon, from a build in
  `~/Documents`, stalled for 100 s and then had no main bundle, so AppKit's first window server connection crashed
  in `CFBundleCopyExecutableURL`. Such a binary is spawned without
  the disclaim and is judged by the app that started it, which already reached it. The daemon also checks that its
  main bundle names its executable before it creates `NSApplication`, and exits with a line in `daemon.log` when it
  does not, after cutting the log back if it has grown, since a launch agent restarts it every 10 s. The spawn sets `POSIX_SPAWN_CLOEXEC_DEFAULT`, so the daemon inherits only its standard streams and never holds a caller's
  pipe or lock. `launchctl` calls are cut off after 5 s, and a `kickstart` that timed out is not followed by a
  `bootstrap`.
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
  default picks `NSScreen.main`, else the first screen, as before. With `dockGround` on (the
  default) and a bottom Dock on that display, the ground is the true screen bottom plus the Dock as
  a raised step, see "The Dock as ground".
- With a `display` other than `focused`, the daemon observes
  `NSApplication.didChangeScreenParametersNotification`. On it every pet, a diving one included, is
  re-placed on the chosen display with its home and where it stands at the same fraction of the width
  (`LaneRedivision.carry`), and the lanes are divided again for the new width. Only the window frame moves, so no animation restarts, and
  no pet stays on a display that went away. The `focused` default ignores the notification, as
  upstream does.
- Animation: sprite frames at 8 fps, walk speed 40 px/s, a lane change walked, never jumped (renderer flips
  horizontally for leftward travel).
- Wandering: a `ready` pet strolls to a destination, pauses, and picks the next one (`Stroll.destination`, all
  randomness from the animator's own source, which tests seed). A stroll is short to medium most of the time,
  1 to 4 units of 40 pt with the shorter ones likelier (`unitInPoints`, `shortStrollUnits`), and a long trip of
  40% to 100% of the range one time in seven (`longTripProbability` 0.15, `longTripFractionOfRange`). It keeps its
  heading 70% of the time in the middle of its range (`keepHeadingProbability`), and the chance of heading further
  out falls in proportion to how close it is to the end it faces, so near an edge the next stroll almost always
  heads back in. A destination is always inside the range; a stroll shorter than 8 pt (`shortestStroll`) is turned
  round, or skipped for a pause. While a neighbour blocks a stroll the pet stands on `idle`, keeps its destination
  and tries again every tick, walking on as soon as the way is clear; blocked for a second (`strollGiveUpInSeconds`)
  the stroll ends, and the next one heads the other way. The pet faces the way it walks on every tick, and a lane
  change moves the destination with the home, so it never walks backwards. While it is in the air (a hop, a
  spring, a fall) it starts no stroll and does not look around. Between strolls the pet waves (35%, as before) or idles for 0.6 to 4 s with the
  shorter pauses likelier, and one idle in five it turns to look the other way halfway through
  (`lookAroundProbability`). `sit` keeps meaning blocked.
- High fives (`HighFiveDirector`, one at a time, all randomness from its own injectable source): two pets on the
  ground in neighbouring lanes that come to face each other within 320 pt (`greetingDistance`) are an encounter.
  Each encounter is asked once, when it begins, and starts a high five one time in ten (`chancePerEncounter`), and
  a pair high fives at most once every 10 minutes (`pairCooldownInSeconds`). Over an hour of normal wandering two
  neighbouring pets on a 1440 pt screen high five about 2 times (1 to 4 in seeded runs). Both drop what they were
  doing and head for the border between their lanes, stopping 85% of a sprite apart (`meetSpacingFraction`), closer
  than the usual gap only for this moment and never across the border. They never arrive together: the pet with
  the shorter walk goes first, and the other waits, facing it, until its own walk ends at least 0.6 s later
  (`arrivalStaggerInSeconds`). The first to arrive raises its hand (`highfive` frame 0, then frame 1 after 0.15 s)
  and holds it while it waits; the second arrives, raises (frame 0, then frame 1, 0.15 s each), and both show the
  contact frame on the same tick, hold it 0.4 s (`contactHoldInSeconds`), then step back to the edges of their own ranges and wander
  again. A pet takes part only while it is on the ground and standing (not floating, in the air, diving or walking
  home), its session's mood is `ready` (a pet with a `!` or `?` bubble is never pulled away), and the ground from
  it to the border is level (no Dock edge in between, `HighFiveDirector.levelPath`). Whenever two neighbouring pets
  on the ground stand closer than the usual gap less half a point (so two pets resting exactly a gap apart keep
  them) (a greeting pair while it meets and while it steps back) both
  labels fade out over 0.15 s (`labelFadeInSeconds`, `HighFiveDirector.hiddenLabels`) and come back once they are
  apart again, so two labels never overlap. A pet at a meeting point is outside its own range by design, so a lane
  replan does not send it walking home; when the greeting ends, a pet left outside its range (say its session
  asked a question meanwhile) walks back into it, and a greeting survives a replan that moves neither home. If either stops qualifying, stops being the other's neighbour, its home or range changes, or the
  walk takes over 10 s, the greeting ends: a pet still on the ground steps back and wanders again, and one that
  is diving or in the air just drops the greeting. Re-planning lanes that moves neither pet does not end it. The
  cooldown runs on the system uptime clock, and expired entries are dropped.
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
- The SessionSource directories and the sprite pack folders change rarely, so the daemon does not list
  them on every poll. A `DirectoryChangeMonitor` (one FSEvents stream with file events, 50 ms latency, on
  the folders the last scan found) marks a change, and `RescanGate` lets the next poll rescan when a
  change was marked, when the config changed, or when 5 s passed since the last rescan. The 5 s fallback
  catches what the stream cannot see, such as a new folder that starts matching a `~/.claude-*/sessions`
  pattern. A monitor that could not start counts as a change on every poll, which is the old behavior. The
  stream's callback never touches the monitor: its context holds a separate change sink that the stream retains
  and releases, so a callback still in flight when the monitor goes away writes to the sink, and the monitor's
  deinit never runs on the callback queue. A
  new or edited pack or Claude session file is therefore seen within 50 ms plus one poll, about 0.35 s,
  as before; the worst case, for a change the stream cannot see, is 5.3 s.
- On a rescan the poll signs every SessionSource directory the same way. On change the daemon reconciles every
  record again, which re-resolves every visible pet's label and pushes it into the existing `PetView`, so a
  `/rename` shows up within one poll interval without recreating the window or restarting the animation, and
  a session that went `busy` is seen as well (see "Settling").
- Drawing is skipped when nothing changed. A window is moved only when its rounded frame differs from
  the current one. `PetView` is a container of three layer-backed parts inside one clipping content view:
  the sprite, the label (pill or nametag) and the bubble. The sprite's frame image is the sprite layer's
  `contents` with nearest filtering, so a new animation frame is a contents swap with no Core Graphics
  drawing, and the emerge and dive move that layer instead of redrawing. The label and the bubble draw
  with Core Graphics into 8 bit layers, only when the appearance or the chrome opacity changes; the
  bubble bob, snapped to device pixels, moves the bubble layer and redraws nothing. While a pet floats,
  the content view is rotated about its center. `demo --snapshot` renders offscreen through
  `cacheDisplay`, which does not honor a layer's filter, so its pet views draw the sprite with Core
  Graphics instead (`drawSpriteWithCoreGraphics`); upright pets come out byte identical to the
  single-view drawing this replaced.
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

In a lead group (see "Lead groups") a member's `ready` is also held when the pane in front is any live,
enabled member's of its group, so the window counts as one place: a finish in the lead's pane, or in a
helper's, while any pane of that window is in front never flashes the window's pet. A question
(`needsInput`, `blocked`) is held only by its own pane, as before. A `release` that names any member of a
lead group does nothing while the pane in front (read from `focus.json`, which the integration writes
first) still belongs to a live member of that group, so moving between the window's panes keeps every
hold and its `heldAt`. Once focus has left the group, it releases that member and every other held member
of the group, each on its own `heldAt`. A `hide` that names the lead drops the hold of every member whose
held mood is `ready`; a held question keeps its hold.

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

### Lead groups

A lead group is for a window where one session leads and the others support it. The lead is the live member
flagged `owner`, the earliest enrolled when two are flagged, and the group is a lead group only when that
member's own `groupMode` is `lead`. The members' modes do not decide it, so `on --group-mode shared` on the lead
turns the group back into a plain group even while other members still have `lead`, and `--group-mode lead` on
a member that is not the lead changes nothing while the lead lives. The planner and `hide` read this one rule
(`PetGroup.lead`). With a lead:

- The lead's pet keeps the group key. It is waiting while the lead is waiting, in any mood, or while any
  member is visible and `ready` and no member is working (the rule above). Its label, sprite, accent and
  click are the lead's, its message is the lead's, and it has no bubble caption.
- A visible `needsInput` or `blocked` member other than the lead gets its own pet at once, keyed
  `<group>#<session id>`, with that member's own label, sprite, message and click. Its click hides only
  that member, and the lead's pet leaves it out of the members it hides.
- `hide` naming the lead (by `--session`, `--focus-target` or `--pid`) also hides every other enabled member
  whose process is alive and that is visible and `ready`, so seeing the lead counts as seeing the window. A
  member's question stays up.
- A member's own pet counts as up for settling, like the group's pet, so a new question on a pet that is
  already up never takes it down to settle again.

With no live flagged owner and a member whose `groupMode` is `lead` (the lead has exited), the group follows
the plain rules, except that the label is the waiting member's own and there is no bubble caption. A group
whose live flagged owner has no `lead` mode, and a group where no member has it, follow the plain rules
unchanged.

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
it is hidden. The ground line is `NSScreen.main.visibleFrame.minY` (or the ground profile under the pet, see "The
Dock as ground"), and an emerge or a dive never moves the window vertically: `PetView`
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

### The Dock as ground

With `dockGround` on (the default), a pet never stands over the Dock's icons. When an auto-hidden Dock slides in under
pets, they are sprung up onto its top, overshoot a little and land on it; they walk on it, fall off when it hides or
when they walk past its end, and jump up onto it when its edge is in their lane. An always-visible Dock is a step on
the screen bottom: pets beside it stand on the true bottom of the screen and jump up and down its edges. With the key
off, or with no bottom Dock on the pets' display, the ground is `visibleFrame.minY + 4` as before. One thing is not
tied to the key: a float that falls back to the ground plays `fall` (with `idle` as its stand-in), whatever the key says.

**Ground profile.** `GroundProfile` (AgentPetCore, pure) is what a pet stands on, rebuilt every animation tick by
`GroundProfile.resolve`. It is `flat` (the old ground, `visibleFrame.minY + 4`) when the key is off, the Dock is not
at the bottom of the pets' display, or its frame is unknown. Otherwise it is `dock`: a base at `screenFrame.minY + 4`
and one raised `GroundSegment` from the drawn bar's left to right edge at its top plus 4. A pet counts by its body,
the middle 60% of its sprite (`LaneLayout.bodyWidthFraction`), not by its label or bubble: `height(over:)` is the
segment top while any part of that body span is over the bar, else the base. A hidden Dock still makes a `dock`
profile whose segment is below the base, so a pet falls off it rather than snapping down. Lanes, homes and wander
widths are unchanged; the profile moves pets only vertically.

**Vertical state.** Each grounded pet on a `dock` profile has a `GroundBody` (AgentPetCore, pure): a height, a
vertical velocity under gravity (`SpaceMotion.fallAcceleration`, 1400 pt/s squared, moved by the exact step for
constant gravity so the apex does not depend on the tick) with the ground under its body as a floor, and a phase:
`standing`, `riding`, `rising` or `falling`. The phase alone picks the animation: `rising` plays `jump`, `falling`
plays `fall`, and `standing` and `riding` play whatever the walk does, so a pet enters `fall` once per time in the
air and goes straight back to its ground animation on the tick it lands.

- **Riding and the spring.** The pet is always a ballistic body; a rising floor pushes it. The floor's speed is the
  rise of the floor under the pet's body since the last tick (so walking across an edge never reads as a moving
  floor), taken over the last 3 ticks (`floorVelocitySamples`) as their total rise over their total time, so one
  repeated reading mid-slide cannot stop the push and one long tick counts for its full length. When the floor meets the pet while that speed is above 60 pt/s (`rideSpeed`), the pet rides: it stands on
  the floor and its velocity becomes the smaller of the floor's speed and the speed that would carry it, in free
  flight, to `springOvershoot` (16 pt) above the Dock's resting top (`speedToPeak`). As long as the floor is faster
  the floor keeps pushing; the moment the floor slows below that speed, the pet simply keeps going, decelerates
  under gravity, peaks 16 pt above where the Dock comes to rest and falls back onto it. There is no pause and no
  second impulse: the velocity is continuous except where the floor itself changes speed abruptly. The Dock's
  resting top comes from the geometry source (`DockTracker.restingTop`). It is the last top seen with the Dock at
  rest (two equal readings, the bar wholly above the display's bottom and within 2 pt of the predicted rest, so a
  stuttered slide is never taken for a rest), kept as a height above the display's bottom so it follows the Dock to
  another display, and dropped when the tile size changes; else it is predicted with `DockListFrame.restingTop`: the display's bottom, a 10 pt gap under the list,
  and the bar's height. The estimate uses the same formula. The 10 pt gap was measured at tile size 54 only and is
  assumed not to scale with the tile size (the probe measured no other size, and changing the tile size of a live
  Dock to measure it is not read only). So the apex is the same for any slide curve, slide length and poll rate,
  up to the error of that prediction on a first reveal at another tile size. A ride shows whatever the animator is
  playing (walk, idle, a wave); it turns into `rising` only when the pet is more than 3 pt
  (`rideGap`) above the floor and has not been pushed for more than one tick, so a stuttered reading never flickers
  into `jump`. A floor that drops away, or that the pet walks off, leaves it in the air with the velocity it had.
- **Falling.** A floor that drops away faster than gravity leaves the pet in the air, and it falls.
- **Steps and jumps.** Walking is still `PetAnimator`'s; every step also asks the body. A step is measured from the
  ground under the pet now, not from its last height, so a floor rising under a walking pet is never mistaken for
  an edge. A step onto ground more than 2 pt higher is refused, and a pet on the ground (standing or riding) then
  jumps with the speed that clears the edge by `jumpClearance` (16 pt), which leaves any ride, and takes the step
  once it is above the top. A step up of more than 160 pt is refused with no jump, so the pet turns as it does at
  a neighbour.

With a `flat` profile there is no body and the
window is placed exactly as before. A body is dropped when the pet floats or its display changes, and a new one
starts standing on the ground under the pet. `GroundPlacement.windowBottom` is the one rule the overlay calls, through
`PetGround`, which also answers the step check; both measure the body at the pet's center after its window is
clamped to the screen, so the check and the placement never disagree at a screen edge.

**Geometry source.** The Dock posts no event when it slides, so the overlay polls. `DockTracker` (AgentPetCore,
pure, driven by a `DockSensing`) decides when to read and turns readings into the drawn bar in AppKit coordinates;
`SystemDockSensing` (overlay) does the reading:

- With Accessibility granted to the daemon, it reads the Dock's `AXList` position and size (about 1 ms; the Dock
  moves it every 16 ms through a 0.23 s show and a 0.2 s hide; hidden, the list sits just below the screen). The
  drawn bar is that list frame through `DockBarInset`: measured at tile size 54 as top 5 pt lower, 26 pt wider on
  each side and bottom 3 pt lower, and scaled in proportion to the tile size (`DockBarInset.scaled`), on the
  assumption that the Dock draws its bar padding in proportion to its tiles. Only tile size 54 was measured. A 50 ms
  messaging timeout, set on the application element and on the list element, keeps a stuck Dock from stalling the
  overlay's main thread.
- A read that fails keeps the last real frame for 1.5 s (`DockTracker.accessibilityGraceInSeconds`) before the
  estimate takes over, so one bad read never moves the ground.
- No Dock process means no ground. The Dock is an `LSUIElement` app, so `NSWorkspace` posts no launch or terminate
  notification for it. Its pid is cached, re-checked every 0.5 s (`NSRunningApplication(processIdentifier:)`, still
  the Dock and not terminated), looked up again at once when key-value observing of
  `NSWorkspace.shared.runningApplications` reports a change, and looked up at most once a second while there is
  none, so a Dock that restarts (`killall Dock`, a crash) or starts after the daemon is found without a daemon
  restart. A new pid drops the cached Accessibility elements and window ids. While there is no Dock, the last bar is
  lowered out of sight, so pets standing on it fall, and nothing else is read.
- Without the grant, it never asks. It reads the shown flag of the Dock's layer 20 window, autohide or not (the
  window is on screen only while the Dock is shown, so a full screen Space with no Dock is flat ground), and takes
  the Dock's display from that window's bounds, which cover the whole display it is on. The window ids are looked
  up once (again every 2 s while none is known, and at once when a cached id no longer describes a window) and then
  described by id, so no read lists every window. The bar
  is estimated from `com.apple.dock` preferences: tile size, pinned apps, running apps that are not pinned, recents
  and other items, plus Finder and Trash, centered on that display. `DockSlide` eases it in over 0.23 s and out over
  0.2 s. Minimized windows and folder stacks are not counted, so the estimate can be shorter than the real bar.
- With `magnification` on, a bar is trusted as resting only after the pointer has been out of the band over the Dock
  (the only place it can magnify) for 0.3 s, so the Dock has shrunk back. Any other bar taller than the last resting
  one is cut back to that bar's height and span, so
  hovering the icons never lifts or widens the ground. Before any resting bar was seen, the height for the tile size
  and the estimated width centred on the bar stand in.
- Preferences are read every 5 s. The Dock is read every 0.3 s while idle, and every tick (30 Hz) while the pointer
  is in the band over the Dock (its span plus 40 pt each side, tile size plus 50 pt deep, on the Dock's display),
  for 0.6 s after a change, and while an estimate slides.
- A left or right Dock gives no ground (the profile stays flat). The Accessibility frame is wherever the Dock really
  is: its display is the one under the list's bottom centre, on both axes, so displays stacked above each other are
  told apart; the profile then checks the bar against the pets' display.
- With `dockGround` off, the overlay builds no Dock sensing at all, and drops it when the key is turned off: no
  observers, no reads. Only the access reporter
  below runs, at one file check per 0.3 s poll and one trust check every 5 s, so `dock-access` still answers.

**Who is asked.** macOS judges Accessibility by the process that asks and, for a process a terminal started, by that
terminal. So the daemon is the authority: `DockAccessReporter` checks `AXIsProcessTrusted` at start and every 5 s
and writes `dock-access.json` (`granted`, the daemon's pid, `checkedAt`, `askedAt`, `askNonce`) when the answer
changes, when the file is missing, or when it names another pid. `agent-pet dock-access` reads that file and trusts
it only when its pid is the running daemon's. `agent-pet dock-access --ask` is the only path that asks:

- It starts the daemon through `launchctl` when the launch agent is installed. Otherwise it spawns it with
  `posix_spawn` and its responsibility disclaimed (`responsibility_spawnattrs_setdisclaim`, looked up at run time),
  so macOS judges the daemon by its own signature. When that is not available, or a daemon is already running
  whose parent is not launchd (pid 1) or with no launch agent installed, it says on stderr that the grant shown may
  be the launching app's. A daemon spawned by a command that has since exited is also a child of launchd, so this
  test catches a daemon whose launcher is still running, not every one.
- It writes a random nonce to `control/dock-access-ask`, or joins a nonce already waiting there, and waits up to 3 s
  for a report that echoes it. The daemon, on its next 0.3 s poll, claims the request by renaming it to a unique
  name (so a request written after the claim is left for the next poll), reads and deletes that copy, calls
  `AXIsProcessTrustedWithOptions` with the prompt, stamps `askedAt` after that call returns and writes the report
  with the nonce. A request within 10 s of the last prompt is answered from `AXIsProcessTrusted` with no second
  prompt.

Claimed requests a crashed daemon left behind are all deleted at the next daemon start, since only one daemon runs.

A grant belongs to the daemon binary's code signature, so a binary that is re-signed on every build loses it. `install.sh`
signs the release binary with the identifier `com.agent-pet` when `AGENT_PET_SIGN_IDENTITY` names a code signing
identity (default: no signing, as before), which keeps the designated requirement, and so the grant, the same
across rebuilds; README "Letting pets stand on the Dock exactly" has the steps.

**Animations.** A pet in the air plays `jump` while it rises (a jump, or the spring) and `fall` while it comes
down: off the Dock, off an edge, after the spring, and in a float when `physics` goes back to `ground`. Both are
optional in a pack; see "Sprite packs".

### Pet states

Four runtime states change what every pet does, whatever its session record says. They are building
blocks for the user's own scripts: each is set from the CLI, each means something on its own, and a
config rule can set them while an app shows a full screen window. Nothing is specific to one app.

| state | values | default | what it does |
|---|---|---|---|
| `physics` | `ground`, `float` | `ground` | `float` lifts every pet off and lets it drift and spin; back to `ground`, it falls, lands and walks to its lane |
| `input` | `on`, `off` | `on` | `off` makes every pet inert: no click, no focus, no tooltip |
| `visibility` | `shown`, `hidden` | `shown` | `hidden` dives every pet; the records are untouched and the pets come back up on `shown` |
| `level` | `normal`, `above <bundle id>` | `normal` | `above` draws pets one level above that app's topmost on screen window |

**Sources and precedence.** Each state has one effective value and one source: a CLI command (`cli`), else
a matching config rule (`trigger`), else the default (`default`). A CLI command always beats a trigger.
`agent-pet <state> auto` drops the command, so the trigger or the default applies again.
`PetEffectiveStates.resolve(commands:trigger:)` is that rule, pure and tested.

**Labels in a float.** With `hideLabelsWhileFloating` set to `true` in the config (off by default), a pet
that is floating or falling draws no label and no bubble. They come back when it lands, before it walks to
its lane. `PetChrome.shownOpacity` is the rule; a dive or an emerge fades the chrome as before.

**Delivery.** `agent-pet physics float` and the other three commands read
`~/.agent-pet/control/states.json`, change one key, and write the whole file back with sorted keys through a
temp file and a rename (the file is removed when every state is `auto`). The read, change and write happen
under an exclusive `flock` on `~/.agent-pet/states.lock` (`PetRecordLock`, outside `control/` so taking it never
wakes the daemon), so two commands at the same instant both land. The daemon watches `control/` with a
`DirectoryChangeMonitor` (FSEvents, the same as the sprite and session folders), so a command lands within
about 50 ms plus one 300 ms poll, with the 5 s rescan as the fallback. A file with its own folder keeps the
stream quiet: hook writes to `sessions/` and `hooks.log` never wake it.

**Transient.** The daemon deletes `control/states.json` when it starts, so a command does not survive a
daemon restart (a crash, a launchd restart, a reboot). A state a script set is a reaction to something
happening now, and a pet left floating or inert after a restart, with nothing left to undo it, would be
worse than a script having to set it again. Config rules do survive, because they live in the config.

**Status.** The daemon writes the effective states to `~/.agent-pet/states-effective.json` whenever they
change. `status --json` has a `states` object, `{"physics": {"value": "float", "source": "cli"}, ...}`,
from that file while the daemon runs, else from the commands file alone. Plain `status` prints a
`states:` line only when some state is not its default, so with nothing set its output is as before.

**The rule.** `whenFullScreen` in the config is a list of rules, each `{"bundleIds": [...], "apply":
{...}}`, where `apply` sets any of `physics`, `input`, `visibility`, and `level` as `normal` or `above` (above
the app that matched). A rule matches while a window of a running app with one of its bundle ids covers
at least 90% of an active display. When several rules match, the first rule that sets a state wins it.
When the window goes, the states it set go back to `auto`, that is to a command if one is set, else to
the default. The default is no rules, so with no config nothing is watched and nothing changes.

**Detection.** `AppWindowWatcher` keeps the pids of the running apps whose bundle id appears in a rule
or in a `level above` command (from `NSWorkspace` launch and terminate notifications). While one of them
runs it reads `CGWindowListCopyWindowInfo` (on screen only) at most once a second; with none running it
reads nothing. `WindowDetection.summaries` is the pure rule: per bundle id, the highest layer of its on
screen windows with an alpha above 0, and whether one of them covers 90% of an active display
(`CGDisplayBounds`, in the same top left coordinates as the window list). Owner pid, bounds, layer and
alpha are in the window list without Screen Recording permission (only window names are withheld), so
this needs no permission. Verified 2026-10-05 from a launchd job without the permission: names were
missing, bounds and owners were there.

**Level.** `above <bundle id>` puts every pet window one level above that app's topmost on screen window,
never below the normal pet level (`.screenSaver`) and never at or above `CGShieldingWindowLevel()`. While
the app has no window on screen the pets keep the normal level. The real macOS lock screen is not an app
window, no app draws over it, and agent-pet never tries to.

**Physics.** With `float`, each grounded pet (a pet still emerging floats once it is up) gets a
`SpaceMotion` seeded by its pet key, so the same pet always moves the same way. It lifts off at 24 to 48
pt/s between 30 and 150 degrees, drifts in a straight line and bounces off the screen edges (the whole
screen frame, minus half the window, and never below its ground), and spins at 0.25 to 0.6 rad/s either
way. While it floats, `PetView` uses a square window as wide as the diagonal of its content and rotates
its content view about the center, and the sprite plays `idle`. Back to `ground`, each floating pet
falls at 1400 pt/s squared, its sideways drift damped by a factor of e per half second, and it turns
toward upright by the short way at 3 rad/s. While it falls the sprite plays `fall` on the 8 fps clock (`idle`, its
stand-in, for a pack without `fall.txt`). It lands exactly upright and the motion ends there (`SpacePhase.landed`);
the lanes are assigned again from where the pets are (see "Lane position"), and `PetAnimator` walks it at 40 pt/s
with `walk` frames into its lane, never through
another pet, and then the normal mood behavior takes over. Two floating pets that touch (closer than 60% of
their two sprite widths) are pushed apart and bounce like two equal balls with a restitution of 0.97,
each speed capped at 72 pt/s (`SpaceMotion.collide`); a floating pet's speed eases back toward its launch
speed at a rate of 0.5 per second, so a long float never ends with every pet racing. A pet that dives in
a float goes under where it is and, back up, walks home from there. A pet hidden while it floats dives where
it is, upright. The frame clock and the bubble bob run while a pet floats, so nothing jumps when it lands.

**Input.** With `input off`, and for a pet still falling or walking home from a float, a pet is inert
(`PetInputPolicy.acceptsInput`): its window has `ignoresMouseEvents` set, so every click goes through to
whatever is under it (a lock style app can never be interrupted by a pet, and no window it hides is
revealed), `PetView.isInert` makes `hitTest` return nil, refuses first mouse, ignores `mouseDown` and
`rightMouseDown` and drops the tooltip (its only tracking area), and the controller's click handlers
check the same rule before they hide a session or run the Focuser. When `input` turns `off`, every focus
command still running is killed (`RunningFocusCommands.cancelAll`, one line in `daemon.log`) and its
timeout or exit report is skipped. A pet window never becomes key or main (`canBecomeKey` and
`canBecomeMain` are false, the style is borderless, it is not movable, the collection behavior has no
flag that takes focus), and with the mouse ignored no click can activate the app.

**Visibility.** With `hidden` the planner's items are replaced by none, so every pet dives and the
records are untouched; back to `shown`, the next reconcile brings the visible pets up with an emerge.

`PetSpaceFlight` is the overlay's one driver of a `SpaceMotion`, shared by the daemon and the demo.

## Sprite contract

`SpriteContract.swift` is fixed. `PixelFrame` derives its square side length per frame, so packs may be 16, 24 or
32 px and the renderer still scales by 4. `SpriteSheet` carries `frameSize` and `colorsByCharacter`; `SpritePalette`
is data (a `[Character: NSColor]`, nothing else) and the compiled-in palette is its default instance, so a sprite
image depends only on its pack, animation, frame and facing, plus the session's chosen accent when the pack names
`accentInks` (the recolor swaps palette entries and leaves the contract types alone). The
initializer is `SpriteSheet(idle:walk:wave:sit:emerge:dive:colorsByCharacter:)` with `emerge` and `dive` defaulting
to `[]`, and `SpriteAnimationName` covers them all plus the optional `jump` and `fall` (also defaulting to `[]`). `ClaudeSprite.swift` provides the built-in art as
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
  jump.txt, fall.txt           optional, 2 frames each: picked by flight phase, never looped
  highfive.txt                 optional, 3 frames: raise, reach, contact; picked by the greeting, never looped
```

- Every character in `palette` maps to a fixed hex color. `.` and any character not in `palette`
  are transparent. No character is reserved. Only the inks a pack names in `accentInks` ever show the
  session accent, see "Accent on the sprite".
- `accent` is optional and holds one `AccentColor` name. It becomes the accent of every session that gets the
  pack, see "Sprite assignment". An unknown name is ignored: the daemon logs one line and the pack falls back to
  its dominant color.
- The repo ships 22 packs (`claude` is the same art as `claude8Bit` exported to text):

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
  | astrocat  | blue   | `A`/`a`                         |
  | bookwyrm  | red    | `A`/`a`                         |
  | bopkin    | blue   | `A`/`a`                         |
  | bumble    | purple | `A`/`a`                         |
  | cactling  | pink   | `A`/`a`                         |
  | dapperfox | purple | `A`/`a`                         |
  | docturtle | blue   | `A`/`a`                         |
  | gecklet   | purple | `A`/`a`                         |
  | hermy     | green  | `A`/`a`                         |
  | rangermot | orange | `A`/`a`                         |
  | raven     | purple | `A`/`a`                         |
  | scruff    | green  | `A`/`a`                         |
  | skyhop    | blue   | `A`/`a`                         |
  | tapeling  | orange | `A`/`a`                         |

  `docs/sprite-sheet.png` shows every shipped pack, one per row, and `scripts/sprite-sheet/sheet.py` redraws it
  (no arguments: every pack in `sprites/`, the first eight in the order above, then the rest by name).

- `install.sh` copies each shipped pack directory into `~/.agent-pet/sprites/` on every install. An installed pack
  with a shipped name is deleted and copied fresh, and an installed pack whose name is not shipped is left alone.
  To customize a shipped pack, copy it under a new name. Every installed pack is in the assignment pool, so adding
  a pet is adding a directory.
- The daemon loads packs from `~/.agent-pet/sprites/<name>/` and the config's `spriteDirectories` at
  startup. On every rescan (see "Overlay behavior": an FSEvents change, a config change, or 5 s) it lists those folders again, loads a pack that appeared, drops
  one that went away, and re-reads a pack when its directory mtime changes or it is now read from a
  different folder. A config change applies new `spriteDirectories` on the next tick. A pack that fails to parse logs one line and falls back to
  `claude8Bit`; one without `emerge.txt` or `dive.txt` holds `idle` frame 0 during the offset move.
- `jump.txt` and `fall.txt` are optional and do not loop: `GroundBody.frameIndex` picks the frame from the flight
  phase. `jump` frame 0 is the takeoff crouch, shown only for the first 0.07 s of a hop the pet makes itself
  (`crouchSeconds`, one or two ticks); frame 1 is the stretch, held for the rest of the rise. A spring from the Dock
  skips the crouch and shows the stretch at once. `fall` frame 0 is the apex, shown for the first 0.15 s of a fall
  (`firstFallFrameSeconds`); frame 1 is the later fall, held until the pet lands. Each phase change starts its own
  frames again, and a frame a pack does not have falls back to its last frame. A pack without the file shows its
  stand-in (`walk`, `idle`) on the usual 8 fps clock instead. The overlay renders a pet after its
  body has moved, so the launch tick already shows the rise and the touchdown tick shows the ground animation. A
  float's fall still uses the 8 fps clock. The fallback rule is
  `SpriteAnimationName.standIn`: a pack without `jump.txt` plays `walk` for it, and one without `fall.txt` plays
  `idle`, which is what every pet showed in those moments before the files existed. `shown(in:)` applies it, then
  the first animation the pack has.
- Files iCloud has evicted. A file iCloud Drive has evicted is dataless: its metadata is local and its
  bytes are not, and reading it blocks until the download finishes, or for as long as the Mac is offline.
  No command and no daemon tick reads one. Before reading a pack, `SpritePackLoader` checks the pack
  directory and then `pack.json` and every animation file for `SF_DATALESS` in `lstat`'s `st_flags`,
  which reads metadata only and starts no download. A dataless pack directory is not looked inside. A
  pack with anything dataless is not downloaded yet: the daemon logs it once to `daemon.log`, asks iCloud
  to download those files (`startDownloadingUbiquitousItem`), keeps the sheet it already had (or draws
  `claude8Bit`), and does not record the pack's directory state. Every poll (0.3 s) the daemon then
  checks the flags of the pending packs only (`SpritePackRegistry.pendingDownloadBecameLocal`, an
  `lstat` of at most seven files per pending pack, and of each pending sprite folder), and once one is
  local it rescans and loads it, whether or not the directory mtime moved and whether or not FSEvents
  reported the download. With nothing pending the check costs nothing. A sprite folder
  that is itself dataless is not listed: it is logged once as not downloaded yet, its download is
  requested, and the packs already loaded from it are kept. `packs` marks such a pack, `on` fills no
  accent from it, `render` exits 1, and the demo draws it as `claude8Bit`.
  `AGENT_PET_SIMULATED_DATALESS_PATHS`, a `:` separated list of paths, makes those paths read as
  dataless; it exists for the tests, which cannot evict a file.
- Art direction shared by every pack: idle 2 = breathe or blink; walk 4 = a leg cycle facing right; wave 3 = raise
  something, hold, lower; sit 2 = settle lower, then eyes closed. emerge = eyes closed under a few loose dirt pixels,
  then eyes open wide, then a shake. dive = look down, squash flat, then a small dust puff where the body was.
  jump 2 = frame 0 a takeoff crouch with the legs tucked (shown once, at takeoff), frame 1 stretched upward with the
  arms or ears up (held while rising). fall 2 = frame 0 the apex, arms or ears up and eyes wide; frame 1 the later
  fall, the body a pixel longer. Neither needs to loop; the frames face right like the rest. highfive 3 = frame 0
  the hand raised, frame 1 the arm reaching forward, frame 2 the contact with the palm at the frame's front edge,
  facing right (the right-hand pet of a pair shows them mirrored). A pack without it shows `wave` frame for frame.

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
- `DemoScript.extraScenes` holds scenes outside the tour, played only with `--scene`. Today that is
  `space`: three pets come up, a stand-in screensaver (a dark panel over the chosen screen, one level
  below the pets) comes up at 2 s, the pets float with `PetSpaceFlight`, and at 9 s it goes and they fall,
  land and walk home. `--snapshot DIR` with `--scene space` also writes `space-1.png` to `space-5.png`,
  the same `SpaceMotion` stepped at 30 Hz to five moments on a 960 by 560 stand-in screen.
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
| Full screen rules | none | set pet states while a listed app covers a display, see "Pet states" | `whenFullScreen` |
| Labels while floating | shown: the label and bubble float with the pet | while a pet floats or falls its label and bubble are hidden; they come back the moment it lands | `hideLabelsWhileFloating` |
| Dock as ground | on: a bottom Dock is a raised step pets stand on, jump onto and fall off, see "The Dock as ground" | off: the ground is `visibleFrame.minY + 4` everywhere | `dockGround` |
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
  "dockGround": true,
  "hideLabelsWhileFloating": false,
  "display": "primary",
  "whenFullScreen": [
    {"bundleIds": ["com.example.screensaver"], "apply": {"physics": "float", "input": "off", "level": "above"}}
  ]
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

- `groundGap` is a number of points from 0 to 200, absent by default: the gap between a pet's feet and whatever it
  stands on, the bottom of the screen and the top of the Dock alike. Absent keeps the old look: the window sits
  4 pt up with the label pill (or 3 pt of padding, with `nametag`) under the feet, 25 pt or 7 pt in all. Set, the
  feet sit exactly that many points up and the pill moves over the head (where the nametag already is), so nothing
  is drawn below the feet and no label lies over the Dock's icons. Any other value means absent.
- `dockGround` is a boolean, default `true`: a bottom Dock is ground pets stand on, see "The Dock as ground".
  `false` keeps the ground at `visibleFrame.minY + 4` everywhere.
- `whenFullScreen` is a list of rules, default `[]`, see "Pet states". A rule needs a non-empty
  `bundleIds` list and an `apply` object with at least one known state; anything else is dropped, and so
  are non-string and empty bundle ids and unknown state values.

## Tests

`scripts/test.sh` runs `swift test` for `AgentPetTests`, adding the framework flags `swift test` needs on a
machine with only the Command Line Tools, where Swift Testing is not on the default search path. The characterization tests run the built `agent-pet` binary in a
temporary home (`HOME` and `CFFIXED_USER_HOME`, since `NSHomeDirectory` ignores `HOME`), with
`TMUX_EXECUTABLE` pointing at a stub that records its arguments and a `daemon.pid` naming the test process,
so no test reads or writes `~/.agent-pet` or `~/.claude`, calls `launchctl` or starts a daemon. The pid file alone
was not enough: a command still running when its test process was killed found that pid dead and spawned a real
daemon in the temporary home. So no daemon is started for a home that is not the account's own. The account's home is the
first that exists of the password entry's (`getpwuid`, then `getpwuid_r`) and `/Users/<NSUserName>`; the home in
use (`NSHomeDirectory`) is the same folder when `stat` gives both one device and inode, and only when either cannot
be read are the paths compared, with links and `/System/Volumes/Data` resolved. When no account home exists the
refusal says that instead. The starter refuses before it creates any state directory, `LaunchAgent.start`, the spawn
and the `daemon` command each refuse too (the daemon exits 0, so the launch agent does not bring it back), and
`ensure-daemon` and `dock-access --ask` say so on stderr and exit 1. The silent callers (hooks, `preview`, `on`,
`show`) write the refusal to `daemon.log` in the home in use, at most once an hour and only where its state
directory already exists, so someone with a deliberate custom `HOME` can find out why no pet appears. The tests
of that refusal keep the live `daemon.pid`, so a broken guard still finds a running daemon and cannot spawn one. No
test opens a window, observes `NSWorkspace` or otherwise connects to the window server: a pet's window is reached
through `PetWindowing`, the window watcher through `AppWindowWatching`, both faked in tests, and the Dock sensing
takes its running-applications observer as a parameter. The three
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
