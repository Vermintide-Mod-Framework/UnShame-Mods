import sys, os

# Splits UT2004's smoke texture (SmokeAlphab_t), which make_fx_assets.py converts as it is, into one texture for each of its 16 puffs
# (a 4 by 4 sheet). UT picks one puff at random for every smoke particle, and the skins do the same with the textures smoke_0 to smoke_15.
# Usage: split_smoke.py <scratch dir>     (run after make_fx_assets.py)

SCRATCH = sys.argv[1]
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FX = REPO + '/units/ut/fx'
COLUMNS = ROWS = 4

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
    path = '%s/umodel/%s/XEffects/Texture/SmokeAlphab_t.tga' % (SCRATCH, export)

    if os.path.exists(path):
        tga = path

        break

w, h, rows = read_tga(tga)
tile_w, tile_h = w // COLUMNS, h // ROWS

for index in range(COLUMNS * ROWS):
    column, row = index % COLUMNS, index // COLUMNS
    # (a row of the png: the filter byte, then four bytes for each pixel)
    tile = [b'\0' + line[1 + 4 * column * tile_w:1 + 4 * (column + 1) * tile_w] for line in rows[row * tile_h:(row + 1) * tile_h]]
    name = 'smoke_%d' % index

    write_png('%s/%s.png' % (FX, name), tile_w, tile_h, tile)
    open('%s/%s.texture' % (FX, name), 'w', newline='\n').write(TEXTURE_TEMPLATE % {'name': name})
    open('%s/fx_%s.material' % (FX, name), 'w', newline='\n').write(MATERIAL_TEMPLATE % {'name': name})

print('wrote smoke_0 to smoke_%d, %d by %d' % (COLUMNS * ROWS - 1, tile_w, tile_h))
