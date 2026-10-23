import sys, os
from formats import read_tga, write_png
from resources import texture_text, particle_material_text

# Splits UT2004's FlakTrailTex, which make_fx_assets.py converts as it is, into the two textures the skin uses. The texture is two tiles
# stacked: a streak that runs across the tile (along u), and a glow for the head of the trail.
# The skin's beam maps v along its length, so the streak tile is turned a quarter (transposed).
# The glow tile has a bright white middle that looks like a solid dot, so the glow textures are generated instead.
# Usage: split_flak_trail.py <export dir>     (run after make_fx_assets.py, which writes flak_trail.png the first time)

EXPORT = sys.argv[1]
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FX = REPO + '/units/ut/fx'

w, h, rows = read_tga(EXPORT + '/XEffects/Texture/FlakTrailTex.tga')
tile = h // 2


def pixels(row):
    # (a row is four bytes for each pixel)
    return [row[4 * x:4 + 4 * x] for x in range(w)]


def write(name, width, height, new_rows):
    write_png('%s/%s.png' % (FX, name), width, height, new_rows)
    open('%s/%s.texture' % (FX, name), 'w', newline='\n').write(texture_text('units/ut/fx/' + name))
    open('%s/fx_%s.material' % (FX, name), 'w', newline='\n').write(particle_material_text(name))
    print('texture', name, width, height)


# The streak: the pixel at column x, row y of the tile goes to column y, row x
streak = [pixels(row) for row in rows[:tile]]
turned = []
for x in range(w):
    turned.append(b''.join(streak[y][x] for y in range(tile)))
write('flak_trail', tile, w, turned)

def glow_texture(name, color, brightness_at):
    # A disc: brightness_at(distance) is the brightness from 0 at the middle to 1 at the edge of the texture
    pixels_out = []
    for y in range(tile):
        row = bytes()
        for x in range(w):
            distance = (((x + 0.5) / w - 0.5) ** 2 + ((y + 0.5) / tile - 0.5) ** 2) ** 0.5 * 2
            brightness = brightness_at(min(distance, 1))
            row += bytes([int(c * brightness) for c in color] + [255])
        pixels_out.append(row)
    write(name, w, tile, pixels_out)


# The glow of a chunk: an orange-yellow disc that fades smoothly to nothing at the edge
glow_texture('flak_chunk_glow', (255, 170, 40), lambda distance: (1 - distance) ** 2.5 * 0.7)

# The glow of the shell: a gold disc that is as bright over most of its width, so the ring that shows around the shell's mesh is bright
glow_texture('flak_shell_glow', (255, 190, 70), lambda distance: min(1.0, (1 - distance) / 0.35) ** 1.5)
