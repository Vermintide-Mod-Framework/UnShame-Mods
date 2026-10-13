import sys, os

# Splits the sheets of the frames of UT2004's explosion (ExplosionTex: we1_frames and exp2_frames, 4 by 4 frames each, exported with UModel
# into umodel/out36) into one texture for each frame: explosion_a_0 to explosion_a_15 and explosion_b_0 to explosion_b_15. NewExplosionA
# plays one of the two sheets on each of its fireballs, and the skins show the frames one after the other.
# Usage: split_explosion.py <scratch dir>     (run after make_fx_assets.py)

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

for sheet, prefix in (('we1_frames', 'explosion_a'), ('exp2_frames', 'explosion_b')):
    w, h, rows = read_tga('%s/umodel/out36/ExplosionTex/Texture/%s.tga' % (SCRATCH, sheet))
    tile_w, tile_h = w // COLUMNS, h // ROWS

    for index in range(COLUMNS * ROWS):
        column, row = index % COLUMNS, index // COLUMNS
        # (a row of the png: the filter byte, then four bytes for each pixel)
        tile = [b'\0' + line[1 + 4 * column * tile_w:1 + 4 * (column + 1) * tile_w] for line in rows[row * tile_h:(row + 1) * tile_h]]
        name = '%s_%d' % (prefix, index)

        write_png('%s/%s.png' % (FX, name), tile_w, tile_h, tile)
        open('%s/%s.texture' % (FX, name), 'w', newline='\n').write(TEXTURE_TEMPLATE % {'name': name})
        open('%s/fx_%s.material' % (FX, name), 'w', newline='\n').write(MATERIAL_TEMPLATE % {'name': name})

    print('wrote %s_0 to %s_%d, %d by %d' % (prefix, prefix, COLUMNS * ROWS - 1, tile_w, tile_h))
