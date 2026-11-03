import sys, os

# Makes the Sniper Rifle's scope (UTClassic.ClassicSniperRifle.RenderOverlays): the texture it draws its overlay from in pieces,
# NewSniperRifle.COGAssaultZoomedCrosshair, as ui/ut/sniper_scope.png, with a gui material in ui/ut/sniper_scope.material. UT draws it
# black, with the texture's alpha.
# Usage: make_sniper_scope.py <export dir>

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
EXPORT = sys.argv[1]

sys.path.insert(0, os.path.dirname(__file__))
from formats import read_tga, write_png
from resources import texture_text, gui_material_text

width, height, rows = read_tga('%s/newsniperrifle/Texture/CogAssaultZoomedCrosshair.tga' % EXPORT)

write_png('%s/ui/ut/sniper_scope.png' % REPO, width, height, rows)
open('%s/ui/ut/sniper_scope.texture' % REPO, 'w', newline='\n').write(texture_text('ui/ut/sniper_scope'))
open('%s/ui/ut/sniper_scope.material' % REPO, 'w', newline='\n').write(gui_material_text('ut_sniper_scope', 'ui/ut/sniper_scope'))
print('scope', width, height)
