# Sprite packs

A pack is a directory of plain text, so you can draw a new pet in any editor.

- `pack.json` holds the pack name, the `frameSize` (frames are square), an optional `accent`,
  and a `palette` that maps one character to one hex color.
- `accentInks` is optional, `{"accent":"A","shade":"a"}`: the characters that show the session's
  accent color. When the config turns `accentInks` on and a session chose its color
  (`/pet <nickname> <color>`, or `--accent`), every
  pixel drawn with `accent` is painted in that color and every pixel drawn with `shade` in a darker
  shade of it (each RGB channel at 68%). A session that only took the pack's own `accent` keeps
  the palette colors, so the pack looks the way you drew it. Both characters must be in `palette`;
  `shade` may be left out. Give it the part of the creature that reads as its color at a glance
  (a scarf, a cap, a gem), not the body, so the creature stays recognizable in every color.
  Preview one with `agent-pet render --pack <name> --accent <color>`.
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
- `jump.txt` and `fall.txt` are optional, 2 frames each, and they do not loop: the pet picks the
  frame from where it is in the air. `jump` frame 0 is the takeoff crouch, shown once for a tick
  or two when the pet hops onto the Dock; frame 1 is the stretch, held while it rises. Being sprung
  up by the Dock skips the crouch. `fall` frame 0 is the apex, shown for the first 0.15 s of a fall;
  frame 1 is the later fall, held until it lands. `fall` plays off the Dock, off its edge, and out
  of a float (where it loops at 8 fps like `walk`). A pack without `jump.txt` shows `walk`
  instead, and one without `fall.txt` shows `idle`.
- `highfive.txt` is optional, 3 frames, facing right like every other animation; the pet on the
  right of a pair shows them mirrored. Frame 0 raises the hand, frame 1 reaches out toward the
  other pet, frame 2 is the contact, with the hand at the front edge of the frame so two pets
  standing a little closer than usual touch hands. The frames are chosen by the greeting, not
  looped. A pack without `highfive.txt` shows its `wave` frames in their place.
- Every other color is fixed by the palette. `.` is transparent, and so is any character that is
  not in `palette`. No character is reserved: only the `accentInks` characters ever change color.
- The shipped packs all use `#` for the outline, `e` for eyes and a lowercase/uppercase pair for
  a color and its shade, but that is convention, not a rule.
- To use a pack, copy its directory to `~/.agent-pet/sprites/<name>/`. Every installed pack is in
  the pool that `/pet` draws from, and `agent-pet preview --sprite <name>` shows one on demand.
- Packs can also live outside `~/.agent-pet/sprites/`, for packs you do not want in this repo
  (prototypes, personal creatures, a folder synced through iCloud Drive). List the folders that
  hold them in `spriteDirectories` in `~/.agent-pet/config.json`:

  ```json
  { "spriteDirectories": ["~/pets/prototypes", "~/Library/Mobile Documents/com~apple~CloudDocs/pets"] }
  ```

  Each folder holds pack directories exactly like `~/.agent-pet/sprites/`. Their packs join the
  random pool and work with `packs`, `render --pack`, `preview --sprite` and `on --sprite`, and
  `reservedSprites` applies to them too. The daemon notices a pack added or removed there within
  a second, with no restart. When two folders hold a pack with the same name,
  `~/.agent-pet/sprites/` wins, then the folders in the order listed; the ignored pack is logged
  once in `~/.agent-pet/daemon.log`. A missing or unreadable folder is logged once and skipped, and
  a pack that fails to load is skipped like a broken installed pack.
- `install.sh` refreshes every shipped pack on each install: it deletes the installed copy of
  that name and copies the shipped one again. To customize a shipped pack, copy it under a new
  name and edit the copy. Packs with names that are not shipped are left alone.

| shipped pack | accent | accentInks                   |
|--------------|--------|------------------------------|
| claude       | orange | none, the reserved original  |
| golem        | green  | `A`/`a`, the chest gem       |
| hatchling    | cyan   | `A`/`a`, the scarf           |
| mossling     | red    | `A`/`a`, the cap             |
| nimbus       | blue   | `A`/`a`, the lightning bolts |
| seon         | yellow | `A`/`a`, the face mark       |
| tinowl       | purple | `A`/`a`, the bow tie         |
| walle        | yellow | none                         |
| astrocat     | blue   | `A`/`a`                      |
| bookwyrm     | red    | `A`/`a`                      |
| bopkin       | blue   | `A`/`a`                      |
| bumble       | purple | `A`/`a`                      |
| cactling     | pink   | `A`/`a`                      |
| dapperfox    | purple | `A`/`a`                      |
| docturtle    | blue   | `A`/`a`                      |
| gecklet      | purple | `A`/`a`                      |
| hermy        | green  | `A`/`a`                      |
| rangermot    | orange | `A`/`a`                      |
| raven        | purple | `A`/`a`                      |
| scruff       | green  | `A`/`a`                      |
| skyhop       | blue   | `A`/`a`                      |
| tapeling     | orange | `A`/`a`                      |
