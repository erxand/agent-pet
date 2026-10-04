---
name: pet
description: Enroll or unenroll this session's desktop pet. Invoke for "/pet", "pet on", "show me a pet when you're done", "turn the pet off", or any request to show/enable/disable the agent-pet overlay.
hooks:
  Stop:
    - hooks:
        - type: command
          command: '"$HOME/.local/bin/agent-pet" hook'
          async: false
  Notification:
    - hooks:
        - type: command
          command: '"$HOME/.local/bin/agent-pet" hook'
          async: false
  UserPromptSubmit:
    - hooks:
        - type: command
          command: '"$HOME/.local/bin/agent-pet" hook'
          async: false
  PreToolUse:
    - hooks:
        - type: command
          command: '"$HOME/.local/bin/agent-pet" hook'
          async: false
  SessionEnd:
    - hooks:
        - type: command
          command: '"$HOME/.local/bin/agent-pet" hook'
          async: false
  SessionStart:
    - hooks:
        - type: command
          command: '"$HOME/.local/bin/agent-pet" hook'
          async: false
  SubagentStart:
    - hooks:
        - type: command
          command: '"$HOME/.local/bin/agent-pet" hook'
          async: false
  SubagentStop:
    - hooks:
        - type: command
          command: '"$HOME/.local/bin/agent-pet" hook'
          async: false
---

Parse `$ARGUMENTS`.

If it is empty, or it is anything that does not start with `off`, enroll this session:

1. Start from the full arguments text as the nickname candidate.
2. Check whether the text contains one of these eight accent names: `red`, `blue`, `green`,
   `yellow`, `purple`, `orange`, `pink`, `cyan`. If it does, remove that word from the
   nickname candidate and pass it as `--accent <color>`.
3. Check whether the text contains a token of the form `sprite:<name>`. If it does, remove
   that token from the nickname candidate and pass it as `--sprite <name>`.
4. Run `agent-pet on`. Pass `--nickname "<remaining nickname text>"` only if there is any
   text left after stripping the accent word and the sprite token. Pass `--accent <color>`
   only if step 2 found one, and `--sprite <name>` only if step 3 found one.

If `$ARGUMENTS` starts with `off`, run `agent-pet off` instead.

After the command runs, report back in exactly one line: the sprite and the resolved accent
from the command's output, that the pet will appear along the bottom of the screen when this
session's turn ends, and that clicking it jumps back to this session. Do not restate how
the tool works beyond that line.

Use `agent-pet status` if you need to check enrollment state instead of guessing.
