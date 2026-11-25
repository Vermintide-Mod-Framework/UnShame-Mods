import sys, os

# Makes the textures of the adrenaline counter (HudCDeathmatch.DrawAdrenaline): UT's HUD texture (HudContent.Generic.HUD, 512 by 512),
# from which the counter's background, disc, icon and digits are drawn by their texture coordinates, as ui/ut/hud.png, and the glow
# circle that pulses around the icon when the adrenaline is full (fb_Pulse001: GlowCirclePulse over ScaledGlowCircle over GlowCircle), as
# ui/ut/glow_circle.png. Their gui materials are in ui/ut/adrenaline.material: ut_hud and ut_glow_circle.
# Usage: make_adrenaline_hud.py <export dir>

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
EXPORT = sys.argv[1]

sys.path.insert(0, os.path.dirname(__file__))
from formats import read_tga, write_png
from resources import texture_text, gui_material_text

materials = []

for tga, name, material in (('HUD', 'hud', 'ut_hud'), ('GlowCircle', 'glow_circle', 'ut_glow_circle')):
    width, height, rows = read_tga('%s/HudContent/Texture/%s.tga' % (EXPORT, tga))

    write_png('%s/ui/ut/%s.png' % (REPO, name), width, height, rows)
    open('%s/ui/ut/%s.texture' % (REPO, name), 'w', newline='\n').write(texture_text('ui/ut/' + name))
    materials.append(gui_material_text(material, 'ui/ut/' + name))
    print(name, width, height)

open('%s/ui/ut/adrenaline.material' % REPO, 'w', newline='\n').write(''.join(materials))
