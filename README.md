# agent-pet

agent-pet is a macOS overlay that shows a small pixel-art pet along the bottom of the
screen when an enrolled Claude Code session finishes its turn and is waiting on you. Each
session opts in by running `/pet`; a session that never runs it has no hooks, no state, and
no pet. Clicking a pet's window jumps back to that session.

## Install

Run `./install.sh` from this directory. It builds the binary with `swift build -c release`,
then symlinks `.build/release/agent-pet` into `~/.local/bin/agent-pet`, `skill/pet` into
`~/.claude/skills/pet`, and `pi-extension/agent-pet.ts` into
`~/.pi/agent/extensions/agent-pet.ts`. It also creates `~/.agent-pet/sessions` and
`~/.agent-pet/sprites`, and copies each sprite pack from `sprites/` into
`~/.agent-pet/sprites/` unless a pack of that name is already installed, so your edits to an
installed pack are never overwritten. Make sure `~/.local/bin` is on your `PATH`. Sessions
already running do not pick up the new skill; start a new Claude Code session to use `/pet`.

`install.sh` also installs the overlay daemon as a launchd user agent,
`~/Library/LaunchAgents/com.agent-pet.daemon.plist`, and loads it. launchd owns the daemon, so
it starts when you log in and comes back within seconds if it ever crashes. To stop and start
it by hand:

```
launchctl bootout gui/$(id -u)/com.agent-pet.daemon
launchctl kickstart gui/$(id -u)/com.agent-pet.daemon
```

`launchctl print gui/$(id -u)/com.agent-pet.daemon` shows the state and pid of the service.

To remove it, run `./uninstall.sh`. It unloads the launch agent, deletes its plist and the
three symlinks, and stops the overlay daemon if it is still running. It leaves `~/.agent-pet`
in place and prints the `rm -rf` command to run if you want the state directory gone too.

## Troubleshooting

- `agent-pet status` prints every enrolled session and the daemon's pid. A `visible` session
  with no pet on screen and `daemon pid: none` means the daemon is down.
- `~/.agent-pet/daemon.log` holds the daemon's output. Each run starts with a line like
  `agent-pet daemon started pid 80924 parent 1 at 2026-09-29T17:04:11Z`, so you can tell which
  run produced a later crash trace. The daemon truncates the log at startup once it passes 1 MB.
- No pet after a crash: launchd restarts the daemon on its own, and the next `Stop` hook also
  kickstarts it. `launchctl kickstart gui/$(id -u)/com.agent-pet.daemon` forces the issue.
- `~/.agent-pet/hooks.log` holds one line per hook event agent-pet handled, such as
  `2026-09-29T18:14:07Z Stop 07619c1a - visible=true agents=0`: the time, the event, the first
  eight characters of the session id, the subagent's `agent_id` or `-`, and the record's state
  after the write. A pet that appears at the wrong moment shows up here as the event that set
  `visible=true`. The file is truncated once it passes 1 MB.
- A pet that appears while a background subagent is still running means that session is running
  the old hooks. Hooks are registered at the moment you invoke `/pet`, and both the subagent
  hooks and the synchronous ordering they depend on came later, so a session enrolled before
  that needs `/pet` again.
- The `/pet` skill's hooks live in the Claude Code process that ran `/pet`. A session you
  resume with `claude --resume` is a new process with no hooks, so run `/pet` again in it.

## Usage

- `/pet` enrolls this session, with a default nickname and an accent color derived from the
  session id.
- `/pet <nickname>` enrolls with a custom nickname.
- `/pet <nickname> cyan` enrolls with a custom nickname and a specific accent color.
- `/pet off` unenrolls this session; its pet stops appearing.
- Clicking a pet focuses that session's tmux pane and terminal tab, then hides the pet.
  Right-clicking just hides it. See "Focusing a session" below.
- `agent-pet focus [--session ID]` runs exactly what a click runs, from any shell, so you can
  test focusing without waiting for a pet. It exits 2 when the session has no record or no
  tmux pane. Add `--no-client-switch` to select the window and pane and leave every attached
  client where it is.
- `agent-pet status` prints a table of enrolled sessions (id, label, accent, enabled,
  visible, mood, running subagent count, alive) and the daemon's pid.
- `agent-pet preview` shows a fake pet for a fixed number of seconds so you can check the
  overlay without enrolling a real session.

## How sessions are told apart

Every pet uses the same orange pixel body by default. Sessions differ in four ways:

- Accent color, applied to the sprite's scarf and the label dot. The default is chosen
  deterministically from the session id; `/pet <nickname> <color>` overrides it. The eight
  accent colors:

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

  These are the same eight names Claude Code's `/color` command takes, so the pet's accent
  and the session's prompt bar always match by name.

- Label: the nickname you gave, or the session's own name, or the basename of its working
  directory, shown under the sprite on a dark pill.
- Lane position: visible pets are sorted by their last update time and spread evenly across
  the screen width, each wandering near its own spot so they never overlap.
- Sprite pack: `--sprite <name>` picks a different body from `~/.agent-pet/sprites/`, so two
  sessions can run different creatures. See sprites/README.md.

## Focusing a session

Clicking a pet, and `agent-pet focus`, do the same five steps:

1. `tmux select-window` on the session's window.
2. `tmux select-pane` on its pane.
3. `tmux list-clients`, then `tmux switch-client -c <client tty>` to put a client on that
   session. The client is the one already attached to the session if there is one, otherwise
   the most recently active client. A client already on the session needs no switch.
4. If iTerm2 is running, an AppleScript finds the tab whose tty is that client's tty, selects
   the tab and its session, brings that window to the front and activates iTerm2.
5. If step 4 finds nothing, or your terminal is not iTerm2, the first running terminal among
   iTerm2, Terminal and Ghostty is activated instead.

The first time step 4 runs, macOS asks whether agent-pet may control iTerm2. Allow it to get
the exact tab. Deny it and you keep everything else: the tmux window and pane are still
selected, and the terminal still comes to the front.

The daemon runs under launchd with a minimal `PATH`, so it finds tmux by absolute path:
`$TMUX_EXECUTABLE` if you set it, then `/opt/homebrew/bin/tmux`, `/usr/local/bin/tmux`,
`/usr/bin/tmux`, then the first `tmux` on `PATH`. With no tmux anywhere, every tmux step is
skipped and only the terminal is activated.

## How it decides when to show

The `/pet` skill registers session-scoped hooks that call `agent-pet hook` on every
relevant event. Claude Code runs them in event order, so a subagent that starts is recorded
before the `Stop` that follows it. Each run takes a few milliseconds, exits 0 and prints
nothing, so it never blocks or fails the turn.

| event | what agent-pet does |
|---|---|
| `Stop`, with no background subagents left | shows the pet with mood `ready`, with the first line of the assistant's last message as the status text |
| `Stop`, with background subagents still running | keeps the pet hidden, because the session is waiting on its own subagents |
| `Notification`, when the type is `permission_prompt` or `agent_needs_input` | shows the pet with mood `needsInput`, even while subagents run |
| `SubagentStart` | records that subagent as running and hides the pet, since the session is now waiting on its own subagent |
| `SubagentStop` | records that subagent as finished; shows and hides nothing |
| `UserPromptSubmit` | forgets every recorded subagent and hides the pet |
| `PreToolUse` | hides the pet, since the session is working again |
| `SessionEnd` | deletes the session's pet record entirely |

Claude Code fires `Stop` when the main agent's turn ends, and it fires it even when the
session started subagents in the background, because finishing one of those subagents
re-invokes the main agent. So `Stop` on its own does not mean the session is waiting on you,
and agent-pet holds the pet back until the session has no running subagent left. A permission
prompt is the exception: it waits on you whatever the subagents are doing.

When a `SubagentStart` or `SubagentStop` event arrives without an `agent_id`, agent-pet tracks it
under a synthetic id instead: a start adds the next free `unknown-<n>`, and a stop drops the most
recently added one. A missing field costs you the exact identity of that subagent, not the count.

`UserPromptSubmit` clears the list as well as hiding the pet. A new prompt from you makes the
last turn's bookkeeping stale, and the clear also repairs a `SubagentStop` that never arrived,
so a missed event costs you one turn at most.

A session you enrolled before this change has only the five older hooks, because the `/pet`
skill registers its hooks at the moment you invoke it. Run `/pet` again in that session to pick
up `SubagentStart` and `SubagentStop`.

Two hooks can run at once, so every writer takes an exclusive lock on the session's record
first, and the `Stop` hook reads the subagent list and writes `visible` inside that one lock.
No pair of events can interleave into a pet that shows while a subagent runs.

## Prompt bar color sync

Claude Code gives each session a prompt bar color through its `/color` command, and agent-pet
keeps that color in step with the pet's accent. There is no API for `/color`, so the CLI types
it into the session's tmux pane: `agent-pet on` sends the literal text `/color <accent>`
followed by Enter, and `agent-pet off` sends `/color default`. Because `/color` is an
immediate command, it takes effect even while the session is still working on the `/pet` turn.

- Pass `--no-color-sync` to `on` or `off` to skip it.
- Sessions enrolled with `--agent pi` are never synced, because pi has no prompt bar color.
- A session with no tmux pane is never synced, and a failed tmux call is ignored.
- No other command types into a pane. `show`, `hide`, `remove` and `hook` never do.

## pi

The same pet works in the `pi` coding agent through a single-file extension,
`pi-extension/agent-pet.ts`. `./install.sh` symlinks it to
`~/.pi/agent/extensions/agent-pet.ts`, which is pi's global extension directory, so every
pi project sees it. A pi session that is already running picks it up after `/reload`; new
sessions load it at startup. The extension shells out to the same `agent-pet` binary, so
`~/.local/bin` must be on your `PATH`. If the binary is missing, `/pet` says to run
`install.sh` and does nothing else.

Enrollment is per session, exactly as in Claude Code. Until you run `/pet` in a pi session,
the extension makes no CLI calls at all.

- `/pet` enrolls this pi session with a label taken from the pi session name, or from the
  basename of the working directory when the session has no name.
- `/pet <nickname>` enrolls with a nickname.
- `/pet <nickname> cyan sprite:cat` enrolls with a nickname, the `cyan` accent and the `cat`
  sprite pack. The accent word and the `sprite:` token are removed from the nickname, and
  their order does not matter.
- `/pet off` unenrolls this session and stops all further CLI calls.

The extension records the session with `--agent pi` and passes pi's own process id, so the
daemon can check liveness. It does not pass `--tmux`; the CLI resolves the pane from
`$TMUX_PANE` itself.

| pi event | agent-pet command |
|---|---|
| `agent_settled` | `show --mood ready` |
| `ui_prompt_start` | `show --mood needsInput` |
| `ui_prompt_end` | `hide` |
| `input`, when the source is `interactive` | `hide` |
| `tool_execution_start` | `hide` |
| `session_shutdown` | `remove` |

`agent_settled` is the only event that shows the pet in mood `ready`. It fires after pi has
fully settled, which means no retry, no auto-compaction and no queued follow-up is left, so
the pet stays hidden while pi works, including while tools and subagents run.
`ui_prompt_start` and `ui_prompt_end` fire around blocking prompts such as a confirmation
dialog from another extension, which is pi's closest equivalent to a permission prompt.

Every call is fire and forget, with a two second timeout. Failures are logged to the pi
console with a `[agent-pet]` prefix and never interrupt the turn.

## State directory

```
~/.agent-pet/
  sessions/<session_id>.json   one record per enrolled session: nickname, label, accent,
                                mood, message, agent, tmuxTarget, pid, sprite, enabled,
                                visible, activeSubagentIds, updatedAt
  sessions/<session_id>.lock   the lock file that keeps two writers off one record
  sprites/<pack>/              installed sprite packs, see sprites/README.md
  daemon.pid                   pid of the running overlay daemon
  daemon.log                   daemon stderr
  hooks.log                    one line per hook event agent-pet handled
```

Deleting a session's record, or running `/pet off` in that session, removes its pet.
