---
name: pet
description: Enroll or unenroll this session's desktop pet. Invoke for "/pet", "pet on", "show me a pet when you're done", "turn the pet off", or any request to show/enable/disable the agent-pet overlay.
hooks:
  Stop:
    - hooks:
        - type: command
          command: '"$HOME/.local/bin/agent-pet" hook'
          async: true
  Notification:
    - hooks:
        - type: command
          command: '"$HOME/.local/bin/agent-pet" hook'
          async: true
  UserPromptSubmit:
    - hooks:
        - type: command
          command: '"$HOME/.local/bin/agent-pet" hook'
          async: true
  PreToolUse:
    - hooks:
        - type: command
          command: '"$HOME/.local/bin/agent-pet" hook'
          async: true
  SessionEnd:
    - hooks:
        - type: command
          command: '"$HOME/.local/bin/agent-pet" hook'
          async: true
---

Parse `$ARGUMENTS`.

If it is empty, or it is anything that does not start with `off`, enroll this session:

1. Start from the full arguments text as the nickname candidate.
2. Check whether the text contains one of these eight accent names: `red`, `blue`, `green`,
   `yellow`, `purple`, `orange`, `pink`, `cyan`. If it does, remove that word from the
   nickname candidate and pass it as `--accent <color>`.
3. Run `agent-pet on`. Pass `--nickname "<remaining nickname text>"` only if there is any
   text left after stripping the accent word. Pass `--accent <color>` only if step 2 found one.

If `$ARGUMENTS` starts with `off`, run `agent-pet off` instead.

After the command runs, report back in exactly one line: the resolved accent from the
command's output, that the pet will appear along the bottom of the screen when this
session's turn ends, and that clicking it jumps back to this session. Do not restate how
the tool works beyond that line.

Use `agent-pet status` if you need to check enrollment state instead of guessing.
