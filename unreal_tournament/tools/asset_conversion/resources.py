# The text of the SDK resource files that the conversion tools write

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

PARTICLE_MATERIAL_TEMPLATE = '''material_contexts = {
	surface_material = ""
}
parent_material = "units/ut/fx/%(parent)s"
textures = {
	texture_map = "units/ut/fx/%(name)s"
}
variables = {
}
'''

GUI_MATERIAL_TEMPLATE = '''%(name)s = {
	material_contexts = {
		surface_material = ""
	}
	shader = "gui:DIFFUSE_MAP"
	textures = {
		diffuse_map = "%(path)s"
	}
}
'''


def texture_text(path, srgb=True):
    """The .texture of the png at path (from the repository's root, without its extension)."""
    return TEXTURE_TEMPLATE % {'path': path, 'srgb': 'true' if srgb else 'false'}


def particle_material_text(name, parent='particle'):
    """The material of an effect's texture, units/ut/fx/<name>, on one of the particle materials in units/ut/fx."""
    return PARTICLE_MATERIAL_TEMPLATE % {'name': name, 'parent': parent}


def gui_material_text(name, path):
    """A gui material named name that draws the texture at path. A .material file can have several."""
    return GUI_MATERIAL_TEMPLATE % {'name': name, 'path': path}
