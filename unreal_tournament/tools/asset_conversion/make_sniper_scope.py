import sys, os

# Makes the Sniper Rifle's scope (UTClassic.ClassicSniperRifle.RenderOverlays): the texture it draws its overlay from in pieces,
# NewSniperRifle.COGAssaultZoomedCrosshair, as ui/ut/sniper_scope.png, with a gui material in ui/ut/sniper_scope.material. UT draws it
# black, with the texture's alpha.
# Usage: make_sniper_scope.py <export dir>        (NewSniperRifle exported there: umodel_64 -game=ut2 -export NewSniperRifle)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
EXPORT = sys.argv[1]

sys.path.insert(0, os.path.dirname(__file__))
from convert_weapon import read_tga, write_png

TEXTURE = '''common = {
	input = {
		filename = "ui/ut/sniper_scope"
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

MATERIAL = '''ut_sniper_scope = {
	material_contexts = {
		surface_material = ""
	}
	shader = "gui:DIFFUSE_MAP"
	textures = {
		diffuse_map = "ui/ut/sniper_scope"
	}
}
'''

width, height, rows = read_tga('%s/newsniperrifle/Texture/CogAssaultZoomedCrosshair.tga' % EXPORT)

write_png('%s/ui/ut/sniper_scope.png' % REPO, width, height, rows)
open('%s/ui/ut/sniper_scope.texture' % REPO, 'w', newline='\n').write(TEXTURE)
open('%s/ui/ut/sniper_scope.material' % REPO, 'w', newline='\n').write(MATERIAL)
print('scope', width, height)
