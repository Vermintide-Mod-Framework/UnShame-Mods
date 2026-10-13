import struct, zlib, os, sys

# Makes the assets of the effects of the skins: the textures of UT2004's effects (exported with UModel to <scratch>/umodel/out4),
# a unit with a quad, and the materials: one unlit material that adds its color to the screen, and one derived from it for each
# texture. Usage: make_fx_assets.py <scratch dir>
SCRATCH = sys.argv[1]
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
    'rocket_muzzle': 'XEffects/Texture/MuzFlashRocket_t.tga',
    'rocket_flare': 'XEffects/Texture/RocketFlare.tga',
    # the Bio Rifle (the goo, the splat decal)
    'bio_goop': 'XEffectMat/Texture/goop_green_a.tga',
    'bio_splat': 'XEffects/Texture/xbiosplat.tga',
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
    # the meshes of the combo and of the beam (ShockComboSphereDark's electricity, the others are above)
    'shock_electricity': 'DeployableTex/Texture/C_T_Electricity_SG.tga',
    # the dark sphere of the explosion of the ball (ShockDarkFB's texture)
    'shock_dark': 'XEffectMat/Texture/shock_Energy_green_faded.tga',
}

# A texture that is made from another: name -> (the exported tga, what is made of its pixels (r, g, b, a) -> (r, g, b, a))
DERIVED = {
}

def read_tga(path):
    d = open(path, 'rb').read()
    idlen, cmtype, imgtype = d[0], d[1], d[2]
    w, h = struct.unpack('<HH', d[12:16])
    bpp, desc = d[16], d[17]
    bp = bpp // 8
    p = 18 + idlen
    px = bytearray()
    if imgtype == 2:
        px = bytearray(d[p:p + w * h * bp])
    else:
        while len(px) < w * h * bp:
            head = d[p]
            p += 1
            n = (head & 0x7f) + 1
            if head & 0x80:
                px += d[p:p + bp] * n
                p += bp
            else:
                px += d[p:p + n * bp]
                p += n * bp
    top_first = bool(desc & 0x20)
    rows = []
    for y in range(h):
        sy = y if top_first else h - 1 - y
        out = bytearray()
        for x in range(w):
            o = (sy * w + x) * bp
            out += bytes((px[o + 2], px[o + 1], px[o], px[o + 3] if bp == 4 else 255))
        rows.append(b'\0' + bytes(out))
    return w, h, rows

def write_png(path, w, h, rows):
    def chunk(tag, body):
        c = struct.pack('>I', len(body)) + tag + body
        return c + struct.pack('>I', zlib.crc32(tag + body) & 0xffffffff)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) +
                           chunk(b'IDAT', zlib.compress(b''.join(rows), 6)) + chunk(b'IEND', b''))

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

MATERIAL_TEMPLATE = '''material_contexts = {
	surface_material = ""
}
parent_material = "units/ut/fx/particle"
textures = {
	texture_map = "units/ut/fx/%(name)s"
}
variables = {
}
'''

def find(tga):
    # (out4 has the effects of the Shock Rifle, out9 those of the others: static meshes and the textures of XEffects)
    for export in ('out4', 'out9', 'out11'):
        path = '%s/umodel/%s/%s' % (SCRATCH, export, tga)

        if os.path.exists(path):
            return path

    raise FileNotFoundError(tga)

# Textures that are wider than they are high and are drawn as sprites
SQUARE = ('rocket_flare',)

def derived_rows(rows, make):
    out = []

    for row in rows:
        pixels = bytearray(b'\0')

        for i in range(1, len(row), 4):
            pixels += bytes(make(row[i], row[i + 1], row[i + 2], row[i + 3]))

        out.append(bytes(pixels))

    return out

for name, tga in list(TEXTURES.items()) + [(name, derived[0]) for name, derived in DERIVED.items()]:
    w, h, rows = read_tga(find(tga))

    if name in DERIVED:
        rows = derived_rows(rows, DERIVED[name][1])

    if name in SQUARE:
        # (a sprite is a square: a texture that is wider than it is high is put in the middle of one, so that it is not stretched)
        blank = b'\0' + bytes(4 * w)
        rows = [blank] * ((w - h) // 2) + rows + [blank] * (w - h - (w - h) // 2)
        h = w

    write_png('%s/%s.png' % (FX, name), w, h, rows)
    open('%s/%s.texture' % (FX, name), 'w', newline='\n').write(TEXTURE_TEMPLATE % {'name': name})
    open('%s/fx_%s.material' % (FX, name), 'w', newline='\n').write(MATERIAL_TEMPLATE % {'name': name})
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
material += node(OUT, 'core/stingray_renderer/output_nodes/unlit_base', (1280, 0), (LAYER_TRANSPARENT, DOUBLE_SIDED, BLEND_TRANSPARENT, DISABLE_DEPTH_WRITE))
material += node(UV, 'core/shader_nodes/texture_coordinate0', (0, 0))
material += node(TEX, 'core/shader_nodes/sample_texture', (300, 0), (ADDRESS_CLAMP, FILTER_LINEAR, SRGB),
                 samplers='\t\t\t\ttexture_map = {\n\t\t\t\t\tdisplay_name = "Texture"\n\t\t\t\t\tslot_name = "texture_map"\n\t\t\t\t}\n', title='Texture')
material += node(TINT, 'core/shader_nodes/material_variable', (300, 200), export=variable('tint', 'Tint', 'float3', None), title='Tint')
material += node(INTENSITY, 'core/shader_nodes/material_variable', (300, 300), export=variable('intensity', 'Intensity', 'float', 1), title='Intensity')
material += node(ADDITIVE, 'core/shader_nodes/material_variable', (300, 400), export=variable('additive', 'Additive', 'float', 1), title='Additive')
material += node(MUL_COLOR, 'core/shader_nodes/mul', (700, 0))
material += node(MUL_OPACITY, 'core/shader_nodes/mul', (700, 200))
material += '\t]\n\tversion = 3\n}\ntextures = {\n}\nvariables = {\n\tadditive = {\n\t\ttype = "scalar"\n\t\tvalue = 1\n\t}\n\tintensity = {\n\t\ttype = "scalar"\n\t\tvalue = 1\n\t}\n\ttint = {\n\t\ttype = "vector3"\n\t\tvalue = [\n\t\t\t1\n\t\t\t1\n\t\t\t1\n\t\t]\n\t}\n}\n'
open(FX + '/particle.material', 'w', newline='\n').write(material)
print('wrote the quad and the materials')
