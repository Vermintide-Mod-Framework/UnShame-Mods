import sys, os, struct, zlib

# Makes the effect textures and the scope textures of the Lightning Gun, from the UModel exports in <export dir> (XEffects, XWeapons_rc
# and XGameShaders exported there, see README.md):
#   units/ut/fx/lightning_bolt, lightning_charge, blue_spark_line: UT's LightningBoltT, LightningChargeT and pcl_BlueSpark, each with the
#       material fx_<name> that adds its colour to the screen (the same as make_fx_assets.py makes, except for the flare: see LINEAR)
#   ui/ut/lightning_scope_*: the textures of the scope's overlay (SniperRifle.RenderOverlays) as gui materials, in the file
#       ui/ut/lightning_scope.material: the ring (SniperFocus), the four arrows (SniperArrows), and the scan lines and lens of the
#       screen (XGameShaders.ZoomFB, a multiply of the screen that is turned here into black with an alpha, which is as near as the
#       user interface's blend gets)
# Usage: make_lightning_assets.py <umodel export dir>

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
EXPORT = sys.argv[1]

sys.path.insert(0, os.path.dirname(__file__))
from formats import read_tga, write_png
from resources import texture_text, particle_material_text

# name: the tga, and which part of it (first row, last row, first column, last column, each as a share of the size of the texture).
# LightningBoltT is two pictures: the streak of lightning in the top half, and the flare in the bottom half. UT's bolt draws each from
# the half it needs. LightningChargeT is four pictures (the charge's emitter has 2 columns and 2 rows of tiles), which a spark picks from.
# The textures that are turned a quarter, because they are drawn on a beam
TURNED = ('lightning_bolt', 'blue_spark_line')

FX = {
    'lightning_bolt': ('XEffects/Texture/LightningBoltT.tga', (0, 0.5, 0, 1)),
    'lightning_flare': ('XEffects/Texture/LightningBoltT.tga', (0.5, 1, 0, 1)),
    'lightning_charge_0': ('XEffects/Texture/LightningChargeT.tga', (0, 0.5, 0, 0.5)),
    'lightning_charge_1': ('XEffects/Texture/LightningChargeT.tga', (0, 0.5, 0.5, 1)),
    'lightning_charge_2': ('XEffects/Texture/LightningChargeT.tga', (0.5, 1, 0, 0.5)),
    'lightning_charge_3': ('XEffects/Texture/LightningChargeT.tga', (0.5, 1, 0.5, 1)),
    # pcl_BlueSpark is a streak above a dot. A line particle (the sparks of ChildBlueSparks) is the streak along its length.
    'blue_spark_line': ('XEffects/Texture/pcl_BlueSpark.tga', (0, 0.5, 0, 1)),
}

# UT adds an effect's texture to the screen as it is. The particle materials draw after tone mapping, onto the screen's colours, but
# units/ut/fx/particle reads its texture as srgb, which turns each value v into about v^2.2 and leaves the faint parts of the texture
# much fainter than UT's. particle_linear reads the values as they are. The flare, the bolt and the sparks use it (checked against
# pictures of UT2004).
LINEAR = ('lightning_flare', 'lightning_bolt', 'blue_spark_line')

GUI_MATERIAL = '''%(name)s = {
	material_contexts = {
		surface_material = ""
	}
	shader = "gui:DIFFUSE_MAP"
	textures = {
		diffuse_map = "ui/ut/%(texture)s"
	}
}
'''

# An effect's texture is marked as not srgb, so that its smaller mipmaps are made from its values as they are, as its material reads them
def write_texture(directory, name, width, height, rows, srgb=True):
    write_png('%s/%s/%s.png' % (REPO, directory, name), width, height, rows)
    open('%s/%s/%s.texture' % (REPO, directory, name), 'w', newline='\n').write(texture_text(directory + '/' + name, srgb))

for name, (tga, crop) in FX.items():
    width, height, rows = read_tga('%s/%s' % (EXPORT, tga))

    if crop:
        # (a row is four bytes for each pixel)
        first, last = int(crop[2] * width), int(crop[3] * width)
        rows = [row[first * 4:last * 4] for row in rows[int(crop[0] * height):int(crop[1] * height)]]
        height = len(rows)
        width = last - first

    if name in TURNED:
        # (the skin's beam maps v along its length, so a streak that runs along u is turned a quarter, as split_flak_trail.py does)
        rows = [b''.join(rows[y][x * 4:x * 4 + 4] for y in range(height)) for x in range(width)]
        width, height = height, width

    write_texture('units/ut/fx', name, width, height, rows, srgb=name not in LINEAR)
    open('%s/units/ut/fx/fx_%s.material' % (REPO, name), 'w', newline='\n').write(particle_material_text(
        name, 'particle_linear' if name in LINEAR else 'particle'))
    print('fx', name, width, height)

# The scope. UT draws the ring and the arrows with the alpha of their textures.
SCOPE = {
    'lightning_scope_focus': 'XWeapons_rc/Texture/SniperFocus.tga',
    'lightning_scope_arrows': 'XWeapons_rc/Texture/SniperArrows.tga',
}

for name, tga in SCOPE.items():
    width, height, rows = read_tga('%s/%s' % (EXPORT, tga))
    write_texture('ui/ut', name, width, height, rows)
    print('scope', name, width, height)

# ZoomFB draws the middle quarter of the overlay's texture (128 to 384 of 512 in both directions) over the whole screen and multiplies
# the screen by it. As black with an alpha it darkens as much: the alpha is how far from white the texture is.
width, height, rows = read_tga('%s/XGameShaders/Texture/fulloverlay.tga' % EXPORT)
lens = []

for y in range(128, 384):
    out = bytearray()

    for x in range(128, 384):
        shade = rows[y][x * 4]
        out += bytes((0, 0, 0, 255 - shade))

    lens.append(bytes(out))

write_texture('ui/ut', 'lightning_scope_lens', 256, 256, lens)
print('scope lens')

materials = ''

for name in list(SCOPE) + ['lightning_scope_lens']:
    materials += GUI_MATERIAL % {'name': 'ut_' + name, 'texture': name}

open('%s/ui/ut/lightning_scope.material' % REPO, 'w', newline='\n').write(materials)
