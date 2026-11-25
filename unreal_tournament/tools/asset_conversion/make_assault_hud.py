import sys, os

# Makes the Assault Rifle's grenade icon (AssaultRifle.NewDrawWeaponInfo): the tile of HudContent.Generic.HUD that UT draws for each
# grenade, 46 by 45 from (174, 259), as ui/ut/assault_grenade.png, with a gui material in ui/ut/assault_grenade.material. UT draws it white,
# with the texture's alpha.
# Usage: make_assault_hud.py <export dir>

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
EXPORT = sys.argv[1]

sys.path.insert(0, os.path.dirname(__file__))
from formats import read_tga, write_png
from resources import texture_text, gui_material_text

# (x, y, width, height) of the tile
TILE = (174, 259, 46, 45)

width, height, rows = read_tga('%s/HudContent/Texture/HUD.tga' % EXPORT)
x, y, tile_width, tile_height = TILE
# (a row from read_tga is four bytes for each pixel)
tile = [row[4 * x:4 * (x + tile_width)] for row in rows[y:y + tile_height]]

write_png('%s/ui/ut/assault_grenade.png' % REPO, tile_width, tile_height, tile)
open('%s/ui/ut/assault_grenade.texture' % REPO, 'w', newline='\n').write(texture_text('ui/ut/assault_grenade'))
open('%s/ui/ut/assault_grenade.material' % REPO, 'w', newline='\n').write(gui_material_text('ut_assault_grenade', 'ui/ut/assault_grenade'))
print('grenade icon', tile_width, tile_height, 'of', width, height)
