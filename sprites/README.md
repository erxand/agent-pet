# Sprite packs

A pack is a directory of plain text, so you can draw a new pet in any editor.

- `pack.json` holds the pack name, the `frameSize` (frames are square), and a `palette` that
  maps one character to one hex color.
- `idle.txt`, `walk.txt`, `wave.txt` and `sit.txt` hold that animation's frames in order.
  Each frame is `frameSize` lines of `frameSize` characters. One blank line separates frames.
  Frame counts: idle 2, walk 4, wave 3, sit 2. Frames face right; the pet flips them to walk left.
- `emerge.txt` and `dive.txt` are optional, 3 frames each. They play once while the pet rises
  out of the ground as it appears and drops back into it as it hides. A pack without them holds
  `idle` frame 0 for both moves.
- Character legend for the shipped `claude` pack: `o` body, `O` body shade, `#` outline,
  `e` eye, `w` highlight, `.` transparent.
- `A` and `a` are never in `palette`. They always take the session accent color and its shade,
  which is how you tell one session's pet from another, so draw the scarf with them.
- Any character that is not in `palette` and is not `A` or `a` is transparent.
- To use a pack, copy its directory to `~/.agent-pet/sprites/<name>/` and start a pet with
  `agent-pet on --sprite <name>` (or `agent-pet preview --sprite <name>`).
