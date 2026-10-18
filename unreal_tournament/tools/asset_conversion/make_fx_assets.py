import struct, zlib, os, sys
from formats import read_tga, write_png
from resources import texture_text, particle_material_text

# Makes the assets of the effects of the skins: the textures of UT2004's effects, a unit with a quad, and the materials: one unlit
# material that adds its color to the screen, and one derived from it for each texture. Usage: make_fx_assets.py <export dir>
EXPORT = sys.argv[1]
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FX = REPO + '/units/ut/fx'
os.makedirs(FX, exist_ok=True)

# name of the asset: the exported tga
TEXTURES = {
    'shock_sparkle': 'XEffectMat/Texture/shock_sparkle.tga',
    'shock_flare_a': 'XEffectMat/Texture/shock_flare_a.tga',
    'shock_flare_b': 'XEffectMat/Texture/shock_flare_b.tga',
    'shock_ring_a': 'XEffectMat/Texture/Shock_ring_a.tga',
    'shock_ring_b': 'XEffectMat/Texture/shock_ring_b.tga',
    'shock_core': 'XEffectMat/Texture/shock_core.tga',
    'shock_core_low': 'XEffectMat/Texture/shock_core_low.tga',
    'shock_flash': 'XEffectMat/Texture/shock_flash.tga',
    'shock_combo_flash': 'XEffectMat/Texture/ShockComboFlash.tga',
    'shock_mark_heat': 'XEffectMat/Texture/shock_mark_heat.tga',
    'shock_purple_line': 'XEffectMat/Texture/purple_line.tga',
    'shock_elec_a': 'XEffectMat/Texture/Shock_Elec_a.tga',
    'shock_gradient_b': 'XEffectMat/Texture/shock_gradient_b.tga',
    'shock_beam': 'XWeapons_rc/Texture/ShockBeamTex.tga',
    # the Flak Cannon (XEffects)
    'flak_muzzle': 'XEffects/Texture/MuzFlashFlak_t.tga',
    'flak_trail': 'XEffects/Texture/FlakTrailTex.tga',
    'flak_explosion': 'XEffects/Texture/fexpt.tga',
    'explosion_flash': 'XEffects/Texture/ExplosionFlashTex.tga',
    'muzzle_white': 'XEffects/Texture/MuzFlashWhite_t.tga',
    'rocket_flare': 'XEffects/Texture/RocketFlare.tga',
    # the Bio Rifle (the goo, the splat decal)
    'bio_goop': 'XEffectMat/Texture/goop_green_a.tga',
    # the Link Gun (sparks, the flash, the beams, the rings, the splash of a plasma bolt)
    'link_spark_green': 'XEffectMat/Texture/link_spark_green.tga',
    'link_spark_yellow': 'XEffectMat/Texture/link_spark_yellow.tga',
    'link_muz_green': 'XEffectMat/Texture/link_muz_green.tga',
    'link_muz_yellow': 'XEffectMat/Texture/link_muz_yellow.tga',
    'link_beam_green': 'XEffectMat/Texture/link_beam_green.tga',
    'link_beam_yellow': 'XEffectMat/Texture/link_beam_yellow.tga',
    'link_ring_green': 'XEffectMat/Texture/link_ring_green.tga',
    'link_ring_yellow': 'XEffectMat/Texture/link_ring_yellow.tga',
    'link_projectile_splash': 'XEffectMat/Texture/Link_projectile_splash.tga',
    'smoke': 'XEffects/Texture/SmokeAlphab_t.tga',
    # the Shield Gun's sparks when the shield stops something (ShieldSparks)
    'shield_spark': 'XEffectMat/Texture/ShieldSpark.tga',
    # the sparks of a bullet that hits a wall (WallSparks, the Sniper Rifle's SniperWallHitEffect)
    'wall_spark': 'XEffects/Texture/pcl_Spark.tga',
    # the meshes of the combo and of the beam (ShockComboSphereDark's electricity, the others are above)
    'shock_electricity': 'DeployableTex/Texture/C_T_Electricity_SG.tga',
    # the dark sphere of the explosion of the ball (ShockDarkFB's texture)
    'shock_dark': 'XEffectMat/Texture/shock_Energy_green_faded.tga',
}

# A texture that is made from another: name -> (the exported tga, what is made of its pixels (r, g, b, a) -> (r, g, b, a))
DERIVED = {
    # The Bio Rifle's splat (xbiosplat, BioDecal's projected texture). It is gray where it does nothing, and darker where the splat is: UT's
    # projector multiplies the surface by it (and by 2). Here it is a blend: the green of the splat, where the texture is darker than gray.
    'bio_splat': ('XEffects/Texture/xbiosplat.tga', lambda r, g, b, a: (30, 140, 30, max(0, min(255, (128 - r) * 255 // 104)))),
    # How much of the splat there is, as a gray: the decal shader cuts it out and blends it by this. (A texture's alpha did not make the decal
    # transparent.) It is not a color, so it is not made linear (units/ut/fx/bio_splat_mask.texture has srgb = false).
    'bio_splat_mask': ('XEffects/Texture/xbiosplat.tga', lambda r, g, b, a: ((max(0, min(255, (128 - r) * 255 // 104)),) * 3) + (255,)),
}

# Textures that are wider than they are high and are drawn as sprites
SQUARE = ('rocket_flare',)
# Textures that are masks, not colors: not sRGB, and with no particle material
MASKS = ('bio_splat_mask',)

def derived_rows(rows, make):
    out = []

    for row in rows:
        pixels = bytearray()

        for i in range(0, len(row), 4):
            pixels += bytes(make(row[i], row[i + 1], row[i + 2], row[i + 3]))

        out.append(bytes(pixels))

    return out

for name, tga in list(TEXTURES.items()) + [(name, derived[0]) for name, derived in DERIVED.items()]:
    w, h, rows = read_tga(EXPORT + '/' + tga)

    if name in DERIVED:
        rows = derived_rows(rows, DERIVED[name][1])

    if name in SQUARE:
        # (a sprite is a square: a texture that is wider than it is high is put in the middle of one, so that it is not stretched)
        blank = bytes(4 * w)
        rows = [blank] * ((w - h) // 2) + rows + [blank] * (w - h - (w - h) // 2)
        h = w

    write_png('%s/%s.png' % (FX, name), w, h, rows)
    open('%s/%s.texture' % (FX, name), 'w', newline='\n').write(texture_text('units/ut/fx/' + name, srgb=name not in MASKS))

    if name not in MASKS:
        open('%s/fx_%s.material' % (FX, name), 'w', newline='\n').write(particle_material_text(name))

    print('texture', name, w, h)

# ---------------------------------------------------------------- the quad: in the xy plane, 1 by 1, its front is +z
def fl(values):
    return ' '.join(str(v) for v in values)

positions = [-0.5, -0.5, 0, 0.5, -0.5, 0, 0.5, 0.5, 0, -0.5, 0.5, 0]
normals = [0, 0, 1]
uvs = [0, 0, 1, 0, 1, 1, 0, 1]
triangles = [0, 1, 2, 0, 2, 3]

def stream(name, ctype, stride, values, size):
    return ('\t\t\t{\n\t\t\t\tchannels = [ {\n\t\t\t\t\t\tindex = 0\n\t\t\t\t\t\tname = "%s"\n\t\t\t\t\t\ttype = "%s"\n\t\t\t\t\t} ]\n'
            '\t\t\t\tdata = [ %s ]\n\t\t\t\tsize = %d\n\t\t\t\tstride = %d\n\t\t\t}') % (name, ctype, fl(values), size, stride)

streams = [
    stream('POSITION', 'CT_FLOAT3', 12, positions, 4),
    stream('NORMAL', 'CT_FLOAT3', 12, normals, 1),
    stream('TEXCOORD', 'CT_FLOAT2', 8, uvs, 4),
    stream('BINORMAL', 'CT_FLOAT3', 12, [0, 1, 0], 1),
    stream('TANGENT', 'CT_FLOAT3', 12, [1, 0, 0], 1),
]
index_streams = [triangles, [0] * 6, triangles, [0] * 6, [0] * 6]
identity = '1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1'
text = ('\ngeometries = {\n\tg_quad = {\n\t\tindices = {\n\t\t\tsize = 6\n\t\t\tstreams = [ %s ]\n\t\t\ttype = "TRIANGLE_LIST"\n\t\t}\n'
        '\t\tmaterials = [\n\t\t\t{\n\t\t\t\tname = "m_fx"\n\t\t\t\tprimitives = [ 0 1 ]\n\t\t\t} ]\n\t\tsmoothing = [ 1 1 ]\n'
        '\t\tstreams = [\n%s ]\n\t}\n}\nnodes = {\n\troot = {\n\t\tchildren = {\n\t\t\tg_quad = {\n\t\t\t\tgeometries = [ "g_quad" ]\n'
        '\t\t\t\tlocal = [ %s ]\n\t\t\t\tparent = "root"\n\t\t\t}\n\t\t}\n\t\tlocal = [ %s ]\n\t}\n}\nsource_path = "make_fx_assets"\n') % (
    ' '.join('[ %s ]' % fl(s) for s in index_streams), '\n'.join(streams), identity, identity)
raw = text.encode('latin1')
open(FX + '/quad.bsi', 'wb').write(b'bsiz' + struct.pack('<I', len(raw)) + zlib.compress(raw))

open(FX + '/quad.unit', 'w', newline='\n').write('''materials = {
	m_fx = "units/ut/fx/fx_shock_sparkle"
}
renderables = {
	g_quad = {
		always_keep = false
		culling = "disabled"
		generate_uv_unwrap = false
		occluder = false
		shadow_caster = false
		surface_queries = false
		viewport_visible = true
	}
}
''')

# ---------------------------------------------------------------- the material that adds its color to the screen
OUT, UV, TEX, TINT, INTENSITY, ADDITIVE, MUL_COLOR, MUL_OPACITY = [
    'b3a0a1f0-0000-4000-8000-00000000000%d' % i for i in range(1, 9)]
SAMPLE_UV = '1ee9af1f-65f2-4739-ad28-5ea6a0e68fc3'
MUL_A = 'c5823c75-4ae5-4c71-b070-315fa4d03e8e'
MUL_B = '242d1648-a626-445b-9534-bccec094112f'
BASE_COLOR = 'aca690cb-6305-4a2f-bf3d-69183a493db3'
OPACITY = '34259752-b962-4b65-92c3-903a57338519'
ADDITIVE_INPUT = 'c9a30d71-a8ad-4b9e-aedf-d785ae7e301f'

def connection(source, destination, connector, select=None):
    s = '\t\t{\n\t\t\tdestination = {\n\t\t\t\tconnector_id = "%s"\n\t\t\t\tinstance_id = "%s"\n\t\t\t}\n' % (connector, destination)
    if select:
        s += '\t\t\tselect = [\n\t\t\t\t"%s"\n\t\t\t]\n' % select
    return s + '\t\t\tsource = {\n\t\t\t\tinstance_id = "%s"\n\t\t\t}\n\t\t}\n' % source

def node(node_id, node_type, position, options=(), export='', samplers='', title=None):
    s = '\t\t{\n\t\t\tcontent_size = [\n\t\t\t\t160\n\t\t\t\t0\n\t\t\t]\n\t\t\texport = {\n%s\t\t\t}\n\t\t\tid = "%s"\n\t\t\toptions = [\n' % (export, node_id)
    for o in options:
        s += '\t\t\t\t"%s"\n' % o
    s += '\t\t\t]\n\t\t\tposition = [\n\t\t\t\t%d\n\t\t\t\t%d\n\t\t\t]\n\t\t\tsamplers = {\n%s\t\t\t}\n' % (position[0], position[1], samplers)
    if title:
        s += '\t\t\ttitle = "%s"\n' % title
    return s + '\t\t\ttype = "%s"\n\t\t}\n' % node_type

def variable(name, display, kind, value):
    if kind == 'float3':
        ui = '\t\t\t\t\tui = {\n\t\t\t\t\t\tmax = [\n\t\t\t\t\t\t\t1\n\t\t\t\t\t\t\t1\n\t\t\t\t\t\t\t1\n\t\t\t\t\t\t]\n\t\t\t\t\t\tmin = [\n\t\t\t\t\t\t\t0\n\t\t\t\t\t\t\t0\n\t\t\t\t\t\t\t0\n\t\t\t\t\t\t]\n\t\t\t\t\t\tstep = [\n\t\t\t\t\t\t\t0.001\n\t\t\t\t\t\t\t0.001\n\t\t\t\t\t\t\t0.001\n\t\t\t\t\t\t]\n\t\t\t\t\t}\n'
        val = '\t\t\t\t\tvalue = [\n\t\t\t\t\t\t1\n\t\t\t\t\t\t1\n\t\t\t\t\t\t1\n\t\t\t\t\t]\n'
    else:
        ui = '\t\t\t\t\tui = {\n\t\t\t\t\t\tmax = 100\n\t\t\t\t\t\tmin = 0\n\t\t\t\t\t\tstep = 0.001\n\t\t\t\t\t}\n'
        val = '\t\t\t\t\tvalue = %s\n' % value
    return ('\t\t\t\tmaterial_variable = {\n\t\t\t\t\tdisplay_name = "%s"\n\t\t\t\t\tname = "%s"\n\t\t\t\t\ttype = "%s"\n%s%s\t\t\t\t}\n'
            % (display, name, kind, ui, val))

ADDRESS_CLAMP, FILTER_LINEAR, SRGB = 'acb6ef9d-5ba0-42e4-85f3-2924b4b4be25', 'f669a3a6-0376-4187-840e-80000e2939d5', 'fb3f709b-a54a-4e93-ac9f-e9fc76fb8bcd'
LAYER_TRANSPARENT, DOUBLE_SIDED, BLEND_TRANSPARENT, DISABLE_DEPTH_WRITE = (
    'c8d8b754-c567-4c7b-9cbd-8acab22beff5', '8df1b8f7-17c2-4ae4-8c4e-25517ec1df46',
    '435e14e4-556d-4ac1-af14-8dafe63aff8f', '7b8bc0bf-c453-49d2-9415-0e80fec1039f')

# The sampler's linear read (the texture's values as they are, not turned from srgb), and the unlit output's custom field of view (the
# weapon model's)
LINEAR = 'e94e53e6-49b6-4194-a747-8f064a5932e0'
CUSTOM_FOV = 'b2556764-e8e9-47cf-9ecc-f53b5d5d73c7'

def particle_material(linear, weapon):
    material = 'shader = {\n\tconnections = [\n'
    material += connection(UV, TEX, SAMPLE_UV)
    material += connection(TEX, MUL_COLOR, MUL_A, 'rgb')
    material += connection(TINT, MUL_COLOR, MUL_B)
    material += connection(MUL_COLOR, OUT, BASE_COLOR)
    material += connection(TEX, MUL_OPACITY, MUL_A, 'a')
    material += connection(INTENSITY, MUL_OPACITY, MUL_B)
    material += connection(MUL_OPACITY, OUT, OPACITY)
    material += connection(ADDITIVE, OUT, ADDITIVE_INPUT)
    material += '\t]\n\tconstants = [\n\t]\n\tgroups = [\n\t]\n\tnodes = [\n'
    material += node(OUT, 'core/stingray_renderer/output_nodes/unlit_base', (1280, 0),
                     (LAYER_TRANSPARENT, DOUBLE_SIDED, BLEND_TRANSPARENT, DISABLE_DEPTH_WRITE) + ((CUSTOM_FOV,) if weapon else ()))
    material += node(UV, 'core/shader_nodes/texture_coordinate0', (0, 0))
    material += node(TEX, 'core/shader_nodes/sample_texture', (300, 0), (ADDRESS_CLAMP, FILTER_LINEAR, LINEAR if linear else SRGB),
                     samplers='\t\t\t\ttexture_map = {\n\t\t\t\t\tdisplay_name = "Texture"\n\t\t\t\t\tslot_name = "texture_map"\n\t\t\t\t}\n', title='Texture')
    material += node(TINT, 'core/shader_nodes/material_variable', (300, 200), export=variable('tint', 'Tint', 'float3', None), title='Tint')
    material += node(INTENSITY, 'core/shader_nodes/material_variable', (300, 300), export=variable('intensity', 'Intensity', 'float', 1), title='Intensity')
    material += node(ADDITIVE, 'core/shader_nodes/material_variable', (300, 400), export=variable('additive', 'Additive', 'float', 1), title='Additive')
    material += node(MUL_COLOR, 'core/shader_nodes/mul', (700, 0))
    material += node(MUL_OPACITY, 'core/shader_nodes/mul', (700, 200))
    material += '\t]\n\tversion = 3\n}\ntextures = {\n}\nvariables = {\n\tadditive = {\n\t\ttype = "scalar"\n\t\tvalue = 1\n\t}\n\tintensity = {\n\t\ttype = "scalar"\n\t\tvalue = 1\n\t}\n\ttint = {\n\t\ttype = "vector3"\n\t\tvalue = [\n\t\t\t1\n\t\t\t1\n\t\t\t1\n\t\t]\n\t}\n}\n'

    return material

# particle reads its texture as srgb; the _linear ones read the values as they are (see make_lightning_assets.py). The _weapon ones draw
# with the weapon model's field of view, for the effects that are drawn with the weapon in the player's view.
for name, linear, weapon in (('particle', False, False), ('particle_linear', True, False), ('particle_weapon', False, True),
                             ('particle_weapon_linear', True, True)):
    open('%s/%s.material' % (FX, name), 'w', newline='\n').write(particle_material(linear, weapon))
print('wrote the quad and the materials')
