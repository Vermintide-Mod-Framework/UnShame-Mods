import sys, os

# Makes the effect textures of the Minigun, Shield Gun, Assault Rifle and Redeemer from the UModel exports in <export dir> (XEffects,
# XGameShaders, AW-2004Explosions, AW-2004Particles, WeaponSkins and so on, exported into that one folder, see README.md): each as
# units/ut/fx/<name>.png and .texture, with the material fx_<name> that adds its colour to the screen (the same as make_fx_assets.py
# makes). A sheet of tiles (a texture with columns and rows of pictures, which UT's emitters pick from) is cut into one texture for each
# tile, named <name>_0, <name>_1 and so on from the top left.
# The effects that UT adds to the screen are read linearly (units/ut/fx/particle_linear, see make_lightning_assets.py): the values of the
# texture are added as they are. The shell casing is blended, not added, so it keeps the srgb read.
# Usage: make_weapon_fx.py <umodel export dir>

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
EXPORT = sys.argv[1]

sys.path.insert(0, os.path.dirname(__file__))
from convert_weapon import read_tga, write_png

# name: (the tga, columns, rows). A texture that is not a sheet has 1 and 1.
TEXTURES = {
    # The Minigun (MinigunMuzFlash1st, MinigunFlash, NewMinigunMFlash, NewTracer, ShellSpewer)
    'minigun_burst': ('XGameShaders/Texture/Minigun_burst.tga', 2, 2),
    'minigun_flash_3rd': ('XGameShaders/Texture/minigunflash.tga', 1, 1),
    'minigun_flame': ('AW-2004Explosions/Texture/Part_explode2s.tga', 4, 4),
    'tracer_shot': ('AW-2004Particles/Texture/TracerShot.tga', 1, 1),
    'shell_casing': ('XEffects/Texture/ShellCasingTex.tga', 1, 1),
}

SRGB = ('shell_casing',)

# The textures that are turned a quarter, because they are drawn on a beam, which lays v along its length (TracerShot is a streak along
# u, the way NewTracer's sprite moves: PTDU_Right)
TURNED = ('tracer_shot',)

# The effects that UT draws with the weapon in the player's view (attached to it) also get fx_weapon_<name>, which draws with the
# weapon model's field of view (units/ut/fx/particle_weapon_linear, or particle_weapon for an srgb one), so they are among the model's
# parts. The Minigun's flash and shells are attached to the weapon (MinigunFire.InitEffects, Minigun.PostBeginPlay).
WEAPON = ('minigun_burst', 'shell_casing')

TEXTURE_TEMPLATE = '''common = {
	input = {
		filename = "units/ut/fx/%(name)s"
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
		srgb = %(srgb)s
		streamable = false
	}
}
win32 = {
	output = {
		mipmap_num_largest_steps_to_discard = 0
	}
}
'''

MATERIAL_TEMPLATE = '''material_contexts = {
	surface_material = ""
}
parent_material = "units/ut/fx/%(parent)s"
textures = {
	texture_map = "units/ut/fx/%(name)s"
}
variables = {
}
'''

def write(name, width, height, rows, linear, weapon=False):
    if linear:
        # UT's additive styles (and MinigunMuzFlash1stFinal's FB_Brighten) leave out the texture's alpha, while the particle material
        # multiplies the colour by it, so it is made opaque here (Minigun_burst's alpha is at most 97 of 255)
        rows = [bytes(255 if i % 4 == 3 else v for i, v in enumerate(row)) for row in rows]
    write_png('%s/units/ut/fx/%s.png' % (REPO, name), width, height, rows)
    open('%s/units/ut/fx/%s.texture' % (REPO, name), 'w', newline='\n').write(TEXTURE_TEMPLATE % {
        'name': name, 'srgb': 'false' if linear else 'true'})
    open('%s/units/ut/fx/fx_%s.material' % (REPO, name), 'w', newline='\n').write(MATERIAL_TEMPLATE % {
        'name': name, 'parent': 'particle_linear' if linear else 'particle'})
    if weapon:
        open('%s/units/ut/fx/fx_weapon_%s.material' % (REPO, name), 'w', newline='\n').write(MATERIAL_TEMPLATE % {
            'name': name, 'parent': 'particle_weapon_linear' if linear else 'particle_weapon'})

for name, (tga, columns, rows_count) in TEXTURES.items():
    width, height, rows = read_tga('%s/%s' % (EXPORT, tga))

    if name in TURNED:
        rows = [b''.join(rows[y][x * 4:x * 4 + 4] for y in range(height)) for x in range(width)]
        width, height = height, width

    if columns == 1 and rows_count == 1:
        write(name, width, height, rows, name not in SRGB, name in WEAPON)
        print('texture', name, width, height)

        continue

    tile_width, tile_height = width // columns, height // rows_count

    for index in range(columns * rows_count):
        column, row = index % columns, index // columns
        # (a row from read_tga is four bytes for each pixel)
        tile = [line[4 * column * tile_width:4 * (column + 1) * tile_width] for line in rows[row * tile_height:(row + 1) * tile_height]]

        write('%s_%d' % (name, index), tile_width, tile_height, tile, name not in SRGB, name in WEAPON)

    print('sheet', name, columns * rows_count, 'tiles of', tile_width, tile_height)
