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
- Every color is fixed by the palette. `.` is transparent, and so is any character that is not
  in `palette`. No character is reserved: the session accent shows on the label dot and the mood
  bubble, never on the sprite.
- The shipped packs all use `#` for the outline, `e` for eyes and a lowercase/uppercase pair for
  a color and its shade, but that is convention, not a rule.
- To use a pack, copy its directory to `~/.agent-pet/sprites/<name>/`. Every installed pack is in
  the pool that `/pet` draws from, and `agent-pet preview --sprite <name>` shows one on demand.

Shipped packs: `claude`, `golem`, `hatchling`, `mossling`, `nimbus`, `seon`, `tinowl`.
