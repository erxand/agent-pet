# Sprite packs

A pack is a directory of plain text, so you can draw a new pet in any editor.

- `pack.json` holds the pack name, the `frameSize` (frames are square), an optional `accent`,
  and a `palette` that maps one character to one hex color.
- `accent` names one of the eight accent colors: `red`, `blue`, `green`, `yellow`, `purple`,
  `orange`, `pink` or `cyan`. Every session that gets the pack uses it for the label dot, the
  mood bubble and the Claude Code prompt bar, unless the session asked for a color of its own.
  An unknown name is ignored and logged once in `~/.agent-pet/daemon.log`.
- Without `accent`, agent-pet picks the color for you: it leaves out the two darkest palette
  colors (the outline and the eyes), takes the color whose character occurs most often across
  all frames of all animations, and uses the accent nearest to it in RGB.
- `idle.txt`, `walk.txt`, `wave.txt` and `sit.txt` hold that animation's frames in order.
  Each frame is `frameSize` lines of `frameSize` characters. One blank line separates frames.
  Frame counts: idle 2, walk 4, wave 3, sit 2. Frames face right; the pet flips them to walk left.
- `emerge.txt` and `dive.txt` are optional, 3 frames each. They play once while the pet rises
  out of the ground as it appears and drops back into it as it hides. A pack without them holds
  `idle` frame 0 for both moves.
- Every color is fixed by the palette. `.` is transparent, and so is any character that is not
  in `palette`. No character is reserved: the session accent shows on the label dot and the mood
  bubble, never on the sprite.
- The shipped packs all use `#` for the outline, `e` for eyes and a lowercase/uppercase pair for
  a color and its shade, but that is convention, not a rule.
- To use a pack, copy its directory to `~/.agent-pet/sprites/<name>/`. Every installed pack is in
  the pool that `/pet` draws from, and `agent-pet preview --sprite <name>` shows one on demand.
- `install.sh` refreshes every shipped pack on each install: it deletes the installed copy of
  that name and copies the shipped one again. To customize a shipped pack, copy it under a new
  name and edit the copy. Packs with names that are not shipped are left alone.

| shipped pack | accent |
|--------------|--------|
| claude       | orange |
| golem        | green  |
| hatchling    | cyan   |
| mossling     | red    |
| nimbus       | blue   |
| seon         | yellow |
| tinowl       | purple |
