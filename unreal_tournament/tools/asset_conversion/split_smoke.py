import sys, os
from formats import read_tga, write_png
from resources import texture_text, particle_material_text

# Splits UT2004's smoke texture (SmokeAlphab_t), which make_fx_assets.py converts as it is, into one texture for each of its 16 puffs
# (a 4 by 4 sheet). UT picks one puff at random for every smoke particle, and the skins do the same with the textures smoke_0 to smoke_15.
# Usage: split_smoke.py <export dir>     (run after make_fx_assets.py)

EXPORT = sys.argv[1]
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FX = REPO + '/units/ut/fx'
COLUMNS = ROWS = 4

w, h, rows = read_tga(EXPORT + '/XEffects/Texture/SmokeAlphab_t.tga')
tile_w, tile_h = w // COLUMNS, h // ROWS

for index in range(COLUMNS * ROWS):
    column, row = index % COLUMNS, index // COLUMNS
    # (a row is four bytes for each pixel)
    tile = [line[4 * column * tile_w:4 * (column + 1) * tile_w] for line in rows[row * tile_h:(row + 1) * tile_h]]
    name = 'smoke_%d' % index

    write_png('%s/%s.png' % (FX, name), tile_w, tile_h, tile)
    open('%s/%s.texture' % (FX, name), 'w', newline='\n').write(texture_text('units/ut/fx/' + name))
    open('%s/fx_%s.material' % (FX, name), 'w', newline='\n').write(particle_material_text(name))

print('wrote smoke_0 to smoke_%d, %d by %d' % (COLUMNS * ROWS - 1, tile_w, tile_h))
