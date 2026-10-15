import sys, os, struct, zlib

# Makes the effect textures and the scope textures of the Lightning Gun, from the UModel exports in <export dir> (XEffects, XWeapons_rc
# and XGameShaders exported there, see README.md):
#   units/ut/fx/lightning_bolt, lightning_charge, blue_spark: UT's LightningBoltT, LightningChargeT and pcl_BlueSpark, each with the
#       material fx_<name> that adds its colour to the screen (the same as make_fx_assets.py makes)
#   ui/ut/lightning_scope_*: the textures of the scope's overlay (SniperRifle.RenderOverlays) as gui materials, in the file
#       ui/ut/lightning_scope.material: the ring (SniperFocus), the four arrows (SniperArrows), and the scan lines and lens of the
#       screen (XGameShaders.ZoomFB, a multiply of the screen that is turned here into black with an alpha, which is as near as the
#       user interface's blend gets)
# Usage: make_lightning_assets.py <umodel export dir>

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
EXPORT = sys.argv[1]

sys.path.insert(0, os.path.dirname(__file__))
from convert_weapon import read_tga, write_png

# name: the tga, and which part of it (first row, last row, first column, last column, each as a share of the size of the texture).
# LightningBoltT is two pictures: the streak of lightning in the top half, and the flare in the bottom half. UT's bolt draws each from
# the half it needs. LightningChargeT is four pictures (the charge's emitter has 2 columns and 2 rows of tiles), which a spark picks from.
# The textures that are made brighter: each colour times this, up to white. NewLightningBolt's 30 particles each add the flare at the
# start of the bolt, and UT adds them up to white, which makes a white disk with a bright edge where the texture is faint.
BRIGHTER = {'lightning_flare_bright': 30}

# The textures that are turned a quarter, because they are drawn on a beam
TURNED = ('lightning_bolt',)

FX = {
    'lightning_bolt': ('XEffects/Texture/LightningBoltT.tga', (0, 0.5, 0, 1)),
    'lightning_flare': ('XEffects/Texture/LightningBoltT.tga', (0.5, 1, 0, 1)),
    'lightning_flare_bright': ('XEffects/Texture/LightningBoltT.tga', (0.5, 1, 0, 1)),
    'lightning_charge_0': ('XEffects/Texture/LightningChargeT.tga', (0, 0.5, 0, 0.5)),
    'lightning_charge_1': ('XEffects/Texture/LightningChargeT.tga', (0, 0.5, 0.5, 1)),
    'lightning_charge_2': ('XEffects/Texture/LightningChargeT.tga', (0.5, 1, 0, 0.5)),
    'lightning_charge_3': ('XEffects/Texture/LightningChargeT.tga', (0.5, 1, 0.5, 1)),
    'blue_spark': ('XEffects/Texture/pcl_BlueSpark.tga', None),
}

TEXTURE_TEMPLATE = '''common = {
	input = {
		filename = "%(path)s"
	}
	output = {
		apply_processing = true
		category = "texture_categories/ut"
		cut_alpha_threshold = 0.5
		enable_cut_alpha_threshold = false
		format = "DXT5"
		mipmap_filter = "kaiser"
		mipmap_filter_wrap_mode = "mirror"
		mipmap_keep_original = false
		mipmap_num_smallest_steps_to_discard = 0
		resident_mips = 0
		srgb = true
		streamable = false
	}
}
win32 = {
	output = {
		mipmap_num_largest_steps_to_discard = 0
	}
}
'''

FX_MATERIAL = '''material_contexts = {
	surface_material = ""
}
parent_material = "units/ut/fx/particle"
textures = {
	texture_map = "units/ut/fx/%(name)s"
}
variables = {
}
'''

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

def write_texture(directory, name, width, height, rows):
    write_png('%s/%s/%s.png' % (REPO, directory, name), width, height, rows)
    open('%s/%s/%s.texture' % (REPO, directory, name), 'w', newline='\n').write(TEXTURE_TEMPLATE % {'path': directory + '/' + name})

for name, (tga, crop) in FX.items():
    width, height, rows = read_tga('%s/%s' % (EXPORT, tga))

    if crop:
        # (a row is four bytes for each pixel)
        first, last = int(crop[2] * width), int(crop[3] * width)
        rows = [row[first * 4:last * 4] for row in rows[int(crop[0] * height):int(crop[1] * height)]]
        height = len(rows)
        width = last - first

    if name in BRIGHTER:
        factor = BRIGHTER[name]
        rows = [bytes(min(255, v * factor) if i % 4 != 3 else v for i, v in enumerate(row)) for row in rows]

    if name in TURNED:
        # (the skin's beam maps v along its length, so a streak that runs along u is turned a quarter, as split_flak_trail.py does)
        rows = [b''.join(rows[y][x * 4:x * 4 + 4] for y in range(height)) for x in range(width)]
        width, height = height, width

    write_texture('units/ut/fx', name, width, height, rows)
    open('%s/units/ut/fx/fx_%s.material' % (REPO, name), 'w', newline='\n').write(FX_MATERIAL % {'name': name})
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
