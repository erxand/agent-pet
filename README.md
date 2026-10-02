# agent-pet

A tiny pixel pet climbs out of the bottom of your screen when a coding-agent session is
waiting on you, and dives back under when you go back to that session. It works with Claude
Code and with pi. Each session opts in on its own by running `/pet`, and a session that never
runs it has no hooks, no state and no pet. One session gets one pet, and clicking that pet
jumps you back to the session it belongs to.

![agent-pet sprite sheet](docs/sprite-sheet.png)

<!-- TODO: add docs/screenshot.png, a real capture of pets along the bottom of the desktop. -->
![agent-pet on the desktop](docs/screenshot.png)

## Requirements

- macOS 14 or later.
- Xcode Command Line Tools, for `swift build`.
- tmux, optional. You need it for click-to-focus and for prompt bar color sync. Without
  tmux the pet still appears, hides and animates. It just cannot focus a session.
- iTerm2, optional. With it, a click selects the exact tab. Without it, the click brings your
  terminal to the front.
- Claude Code with support for skill-frontmatter hooks, or pi, or both.

## Quick start

1. `git clone https://github.com/erxand/agent-pet.git` and enter the directory.
2. Run `./install.sh`. It builds the binary and installs the skill, the pi extension and the
   overlay daemon.
3. Open a new Claude Code session. An already-open session does not see the skill.
4. Type `/pet`, then let a turn finish. The pet climbs out along the bottom of the screen.

`~/.local/bin` must be on your `PATH`, because that is where `install.sh` links the binary.

## Usage

| form | effect |
|---|---|
| `/pet` | enroll this session with a default label and an accent color derived from the session id |
| `/pet <nickname>` | enroll with a label of your choosing |
| `/pet <nickname> cyan` | enroll with a label and a named accent color |
| `/pet <nickname> cyan sprite:cat` | also pick a sprite pack |
| `/pet off` | unenroll this session and stop its pet |

Word order does not matter. The accent name and the `sprite:` token are pulled out of the
text, and the rest becomes the nickname.

Left-click a pet to focus its session's tmux pane and terminal tab, then hide the pet.
Right-click to hide it without focusing.

Four commands are useful from any shell:

- `agent-pet status` prints one row per enrolled session (short id, label, accent, enabled,
  visible, mood, running subagent count, alive) and the daemon's pid.
- `agent-pet preview` shows a fake pet for 20 seconds, so you can check the overlay without
  enrolling a real session.
- `agent-pet focus [--session ID]` runs exactly what a click runs. It exits 2 when the session
  has no record or no tmux pane. Add `--no-client-switch` to select the window and pane and
  leave every attached client where it is.
- `agent-pet clear-subagents [--session ID]` forgets every subagent the session counts as
  running and prints how many it dropped. It exits 2 when the session has no record.

## How it works

There are three parts:

1. The Claude Code skill registers session-scoped hooks, and the pi extension subscribes to pi
   events. Both call the `agent-pet` CLI, which writes one JSON record per session into
   `~/.agent-pet/sessions/`.
2. A launchd user agent runs the overlay daemon. It polls that directory and reconciles one
   borderless always-on-top window per record marked visible, so the record is the only thing
   that decides whether a pet is on screen.
3. A left click runs tmux `select-window`, `select-pane` and `switch-client`, then an
   AppleScript that selects the matching iTerm2 tab and brings the window forward.

Claude Code events:

| event | what agent-pet does |
|---|---|
| `Stop` | read finished subagents from the transcript and drop stale ones, then show the pet (mood `ready`, with the first line of the last assistant message as its status text) if no background subagents are left, or keep it hidden if any are still running |
| `Notification` of type `permission_prompt` or `agent_needs_input` | show the pet, mood `needsInput`, whatever the subagents are doing |
| `SubagentStart` | record that subagent as running, and hide the pet |
| `SubagentStop` | record that subagent as finished, and show or hide nothing |
| `UserPromptSubmit` | hide the pet, and nothing else. A new prompt does not end a running subagent |
| `PreToolUse` | hide the pet |
| `SessionEnd` | delete the session's record |

Claude Code fires `Stop` when the main agent's turn ends, and it fires it even while that
session has background subagents running, because finishing one of those subagents re-invokes
the main agent. So `Stop` on its own does not mean the session is waiting on you, which is why
the record tracks running subagents and a `Stop` with any of them left hides instead of shows.

`SubagentStop` does not fire for background agents in practice. When a background agent
finishes, Claude Code writes a task notification into the session's transcript file (the
`transcript_path` every hook receives) and re-invokes the main agent. So on `Stop`,
`SubagentStart` and `SubagentStop`, agent-pet reads the part of the transcript it has not read
yet, and every `<task-id>` followed by a `<status>` tag marks that subagent as finished. As a
safety net, a subagent recorded more than 3 hours ago is dropped as expired. If the pet still
stays hidden because of a subagent that is long gone, run `agent-pet clear-subagents`.

This changed nothing in the hook set, so a session that already ran `/pet` needs no
re-enrollment to get it.

pi events:

| event | agent-pet command |
|---|---|
| `agent_settled` | `show --mood ready` |
| `ui_prompt_start` | `show --mood needsInput` |
| `ui_prompt_end` | `hide` |
| `input`, when the source is `interactive` | `hide` |
| `tool_execution_start` | `hide` |
| `session_shutdown` | `remove` |

`agent_settled` is the only pi event that shows a ready pet. It fires once pi has fully
settled, with no retry, no auto-compaction and no queued follow-up left, so the pet stays
hidden while pi works. Every pi call is fire and forget with a two second timeout.

## Telling sessions apart

Every pet shares the same orange body. Sessions differ in four ways.

**Accent color**, on the sprite's scarf and on the label dot. The default is derived from the
session id. `/pet <nickname> <color>` overrides it.

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

These are the same eight names Claude Code's `/color` command takes. `/pet` sets the session's
prompt bar color to match the accent, by typing `/color <accent>` into the session's tmux pane,
and `/pet off` resets it to `default`. Pass `--no-color-sync` to `agent-pet on` or
`agent-pet off` to skip that. agent-pet never syncs a pi session, because pi has no prompt bar
color.

**Label**, shown under the sprite on a dark pill: your nickname, or the session's own name, or
the basename of its working directory.

**Lane**: the daemon sorts visible pets by last update time and spreads them evenly across the
screen width. Each pet wanders near its own spot, so two pets never overlap.

**Sprite pack**: `--sprite <name>` gives a session a different creature.

## Customizing the pet

A sprite pack is a directory of plain text, so you can draw a new pet in any editor. See
sprites/README.md for the full rules.

```
<pack-name>/pack.json                    name, frameSize, and a character-to-hex palette
<pack-name>/idle.txt walk.txt wave.txt sit.txt    frames of frameSize square rows, blank line between frames
<pack-name>/emerge.txt dive.txt          optional, 3 frames each
```

`A` and `a` are never in the palette. They always take the session accent and its shade, so
draw the scarf with them. Packs live in `~/.agent-pet/sprites/<name>/`, and `install.sh` copies
a shipped pack there only when no pack of that name exists, so your edits survive a reinstall.

## Troubleshooting

- `agent-pet status` prints every enrolled session and the daemon's pid. A `visible` session
  with no pet on screen, plus `daemon pid: none`, means the daemon is down.
- `~/.agent-pet/daemon.log` holds the daemon's output. Each run opens with a line like
  `agent-pet daemon started pid 80924 parent 1 at 2026-09-29T17:04:11Z`, so you can tell which
  run produced a later crash trace. The daemon truncates this log at startup past 1 MB.
- `~/.agent-pet/hooks.log` holds one line per handled hook event, such as
  `2026-09-29T18:14:07Z Stop 07619c1a - visible=true agents=0`: the time, the event, the first
  eight characters of the session id, the subagent's `agent_id` or `-`, and the record's state
  after the write. A pet that appears at the wrong moment shows up here as the event that set
  `visible=true`. `PreToolUse` lines also name the tool, as `tool=Bash`. A `Stop` line that
  dropped subagents ends with `completed=<n> expired=<m>`, and each expired subagent gets its own
  `SubagentExpired` line.
- A pet that never appears even though the session is waiting on you, with `agents=` above 0 on
  every `Stop` line, means agent-pet still counts a subagent as running. Run
  `agent-pet clear-subagents --session ID` to empty the count. It prints how many it dropped,
  and the next `Stop` shows the pet. A forgotten subagent also expires on its own after 3 hours.
- A record left behind by a session that ended without its `SessionEnd` hook shows `ALIVE no`,
  and the daemon sweeps it within about 5 seconds. To drop one now, run
  `agent-pet remove --session ID`.
- launchd restarts a crashed daemon on its own, and the next `Stop` hook kickstarts it too. To
  force it: `launchctl kickstart gui/$(id -u)/com.agent-pet.daemon`.
  `launchctl print gui/$(id -u)/com.agent-pet.daemon` shows the state and pid.
- Hooks live in the Claude Code process that ran `/pet`. A session you reopen with
  `claude --resume` is a new process with no hooks, so run `/pet` again in it.
- The first click that reaches iTerm2 makes macOS ask whether agent-pet may control it. Allow
  it to get the exact tab. Deny it and you keep everything else. agent-pet still selects the
  tmux window and the pane, and the terminal still comes to the front.

## Uninstall

Run `./uninstall.sh`. It unloads the launch agent, deletes its plist and the three symlinks,
and stops the daemon if it is still running. It leaves `~/.agent-pet` in place and prints the
`rm -rf` command for it.

## State directory

```
~/.agent-pet/
  sessions/<session_id>.json   one record per enrolled session
  sessions/<session_id>.lock   the lock that keeps two writers off one record
  sprites/<pack>/              installed sprite packs
  daemon.pid                   pid of the running overlay daemon
  daemon.log                   daemon output
  hooks.log                    one line per handled hook event
```

Delete a session's record, or run `/pet off` in that session, to remove its pet.

## Design notes

DESIGN.md is the contract: state shape, concurrency, daemon lifecycle, overlay and sprites.
