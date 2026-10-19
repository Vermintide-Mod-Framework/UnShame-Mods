import sys, os
from formats import read_tga, write_png
from resources import texture_text, particle_material_text

# Splits the sheets of the frames of UT2004's explosions (ExplosionTex) into one texture for each frame, numbered along the rows:
# NewExplosionA plays one of we1_frames and exp2_frames (4 by 4 frames each) on each of its fireballs, as explosion_a_0 to
# explosion_a_15 and explosion_b_0 to explosion_b_15; NewExplosionB, the Assault Rifle grenade's, plays exp1_frames (2 columns by 4
# rows), as explosion_c_0 to explosion_c_7. The skins show the frames one after the other, down each column.
# Usage: split_explosion.py <export dir>     (run after make_fx_assets.py)

EXPORT = sys.argv[1]
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FX = REPO + '/units/ut/fx'

# (the sheet, the prefix of its frames, its columns and rows)
SHEETS = (('we1_frames', 'explosion_a', 4, 4), ('exp2_frames', 'explosion_b', 4, 4), ('exp1_frames', 'explosion_c', 2, 4))

for sheet, prefix, COLUMNS, ROWS in SHEETS:
    w, h, rows = read_tga('%s/ExplosionTex/Texture/%s.tga' % (EXPORT, sheet))
    tile_w, tile_h = w // COLUMNS, h // ROWS

    for index in range(COLUMNS * ROWS):
        column, row = index % COLUMNS, index // COLUMNS
        # (a row is four bytes for each pixel)
        tile = [line[4 * column * tile_w:4 * (column + 1) * tile_w] for line in rows[row * tile_h:(row + 1) * tile_h]]
        name = '%s_%d' % (prefix, index)

        write_png('%s/%s.png' % (FX, name), tile_w, tile_h, tile)
        open('%s/%s.texture' % (FX, name), 'w', newline='\n').write(texture_text('units/ut/fx/' + name))
        open('%s/fx_%s.material' % (FX, name), 'w', newline='\n').write(particle_material_text(name))

    print('wrote %s_0 to %s_%d, %d by %d' % (prefix, prefix, COLUMNS * ROWS - 1, tile_w, tile_h))
