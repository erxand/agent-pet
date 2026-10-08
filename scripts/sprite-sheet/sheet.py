"""Render agent-pet sprite packs. Layout matches docs/sprite-sheet.png in
erxand/agent-pet: scale 4, 4px margin, 4px between frames, 16px between
animations, animations idle walk wave sit emerge dive jump fall highfive,
one pack per row.

Run from anywhere: python3 scripts/sprite-sheet/sheet.py [OUT.png [PACK_DIR ...]]
With no arguments it writes docs/sprite-sheet.png from every pack in sprites/."""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import png

ANIMATIONS = [('idle', 2), ('walk', 4), ('wave', 3), ('sit', 2), ('emerge', 3), ('dive', 3), ('jump', 2), ('fall', 2), ('highfive', 3)]
STAND_INS = {'jump': 'walk', 'fall': 'idle', 'highfive': 'wave'}
TRANSPARENT = (0, 0, 0, 0)
FIRST_PACKS = ['claude', 'golem', 'hatchling', 'mossling', 'nimbus', 'seon', 'tinowl', 'walle']


def color_from_hex(hex_color):
    """'#RRGGBB' or '#RRGGBBAA' as an (r, g, b, a) tuple, opaque when no alpha is given."""
    digits = hex_color.lstrip('#')
    red, green, blue = (int(digits[index:index + 2], 16) for index in (0, 2, 4))
    alpha = int(digits[6:8], 16) if len(digits) >= 8 else 255
    return (red, green, blue, alpha)


def read_frames(path):
    """The frames in one animation file: blocks of rows separated by blank lines."""
    frames = []
    current = []
    with open(path) as animation_file:
        for line in animation_file:
            row = line.rstrip('\n')
            if row.strip() == '':
                if current:
                    frames.append(current)
                    current = []
            else:
                current.append(row)
    if current:
        frames.append(current)
    return frames


def load_pack(pack_dir):
    """A pack's manifest, frame size, palette and frames per animation, with agent-pet's fallbacks applied."""
    with open(os.path.join(pack_dir, 'pack.json')) as manifest_file:
        manifest = json.load(manifest_file)
    frame_size = manifest['frameSize']
    palette = {character: color_from_hex(hex_color) for character, hex_color in manifest['palette'].items()}
    frames_by_animation = {}
    for animation, _ in ANIMATIONS:
        path = os.path.join(pack_dir, animation + '.txt')
        frames_by_animation[animation] = read_frames(path) if os.path.exists(path) else None
    for animation, frame_count in ANIMATIONS:
        if frames_by_animation[animation] is not None:
            continue
        if animation in STAND_INS:
            frames_by_animation[animation] = frames_by_animation[STAND_INS[animation]]
        else:
            frames_by_animation[animation] = [frames_by_animation['idle'][0]] * frame_count
    return manifest, frame_size, palette, frames_by_animation


def frame_pixels(frame, frame_size, palette):
    """A frame as rows of colors; '.', unknown characters and short rows are transparent."""
    def pixel(column, line):
        if line >= len(frame) or column >= len(frame[line]) or frame[line][column] == '.':
            return TRANSPARENT
        return palette.get(frame[line][column], TRANSPARENT)
    return [[pixel(column, line) for column in range(frame_size)] for line in range(frame_size)]


def draw(canvas, pixels, left, top, scale):
    """Copy pixels onto canvas at (left, top), each pixel a scale by scale square. Transparent pixels are skipped."""
    for row_index, row in enumerate(pixels):
        for column_index, color in enumerate(row):
            if color[3] == 0:
                continue
            for row_offset in range(scale):
                canvas_row = canvas[top + row_index * scale + row_offset]
                for column_offset in range(scale):
                    canvas_row[left + column_index * scale + column_offset] = color


def sheet(pack_dirs, out, scale=4, margin=4, frame_gap=4, animation_gap=16):
    """Write one row per pack to out and return the sheet's (width, height)."""
    packs = [load_pack(pack_dir) for pack_dir in pack_dirs]
    cell = packs[0][1] * scale
    frame_total = sum(frame_count for _, frame_count in ANIMATIONS)
    width = (2 * margin + frame_total * cell + (frame_total - len(ANIMATIONS)) * frame_gap
             + (len(ANIMATIONS) - 1) * animation_gap)
    height = 2 * margin + len(packs) * cell + (len(packs) - 1) * frame_gap
    canvas = [[TRANSPARENT] * width for _ in range(height)]
    for pack_index, (_, frame_size, palette, frames_by_animation) in enumerate(packs):
        left = margin
        top = margin + pack_index * (cell + frame_gap)
        for animation, frame_count in ANIMATIONS:
            for frame_index, frame in enumerate(frames_by_animation[animation][:frame_count]):
                draw(canvas, frame_pixels(frame, frame_size, palette), left, top, scale)
                left += cell + (frame_gap if frame_index < frame_count - 1 else 0)
            left += animation_gap
    png.write(out, width, height, canvas)
    return width, height


def default_pack_dirs(root):
    """Every pack in sprites/, the original eight first."""
    sprites = os.path.join(root, 'sprites')
    names = [name for name in os.listdir(sprites) if os.path.exists(os.path.join(sprites, name, 'pack.json'))]
    ordered = [name for name in FIRST_PACKS if name in names] + sorted(name for name in names if name not in FIRST_PACKS)
    return [os.path.join(sprites, name) for name in ordered]


if __name__ == '__main__':
    repo_root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    output = sys.argv[1] if len(sys.argv) > 1 else os.path.join(repo_root, 'docs', 'sprite-sheet.png')
    print(sheet(sys.argv[2:] or default_pack_dirs(repo_root), output))
