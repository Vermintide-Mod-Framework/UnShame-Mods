import sys, os

# Splits UT2004's FlakTrailTex, which make_fx_assets.py converts as it is, into the two textures the skin uses. The texture is two tiles
# stacked: a streak that runs across the tile (along u), and a glow for the head of the trail.
# The skin's beam maps v along its length, so the streak tile is turned a quarter (transposed).
# The glow tile has a bright white middle that looks like a solid dot, so the glow texture is generated instead: a soft orange-yellow
# falloff with no bright middle.
# Usage: split_flak_trail.py <scratch dir>     (run after make_fx_assets.py, which writes flak_trail.png the first time)

sys.argv = [sys.argv[0], sys.argv[1]]
SCRATCH = sys.argv[1]
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FX = REPO + '/units/ut/fx'

sys.path.insert(0, os.path.dirname(__file__))
import importlib.util

# (the helpers of make_fx_assets.py, without running its conversion)
source = open(os.path.join(os.path.dirname(__file__), 'make_fx_assets.py'), encoding='utf8').read()
helpers = source[source.index('def read_tga'):source.index('TEXTURE_TEMPLATE = ')]
material_start = source.index('MATERIAL_TEMPLATE = ')
templates = source[source.index('TEXTURE_TEMPLATE = '):source.index("'''\n", material_start + 25) + 4]
import struct, zlib
exec(helpers)
exec(templates)

tga = None
for export in ('out4', 'out9', 'out11'):
    path = '%s/umodel/%s/XEffects/Texture/FlakTrailTex.tga' % (SCRATCH, export)

    if os.path.exists(path):
        tga = path

        break

w, h, rows = read_tga(tga)
tile = h // 2


def pixels(row):
    # (a row of the png: the filter byte, then four bytes for each pixel)
    return [row[1 + 4 * x:5 + 4 * x] for x in range(w)]


def write(name, width, height, new_rows):
    write_png('%s/%s.png' % (FX, name), width, height, new_rows)
    open('%s/%s.texture' % (FX, name), 'w', newline='\n').write(TEXTURE_TEMPLATE % {'name': name})
    open('%s/fx_%s.material' % (FX, name), 'w', newline='\n').write(MATERIAL_TEMPLATE % {'name': name})
    print('texture', name, width, height)


# The streak: the pixel at column x, row y of the tile goes to column y, row x
streak = [pixels(row) for row in rows[:tile]]
turned = []
for x in range(w):
    turned.append(b'\0' + b''.join(streak[y][x] for y in range(tile)))
write('flak_trail', tile, w, turned)

# The glow: an orange-yellow disc that fades smoothly to nothing at the edge
GLOW_COLOR = (255, 170, 40)
glow = []
for y in range(tile):
    row = bytes([0])
    for x in range(w):
        distance = (((x + 0.5) / w - 0.5) ** 2 + ((y + 0.5) / tile - 0.5) ** 2) ** 0.5 * 2
        brightness = max(0.0, 1 - distance) ** 2.5 * 0.7
        row += bytes([int(c * brightness) for c in GLOW_COLOR] + [255])
    glow.append(row)
write('flak_chunk_glow', w, tile, glow)
