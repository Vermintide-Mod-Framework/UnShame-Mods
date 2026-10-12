import os, sys, shutil

# Makes the material of the Shock Rifle's chamber, the ShockPowerFinal of UT2004 (UT2004Weapons.utx, Shaders.ShockPowerShader), as a
# shader graph that runs on the GPU: nothing of it is baked, so it needs no frames and animates by itself.
#
# What ShockPowerShader is (read from the UModel export of the objects, and in UnrealEd):
#   Shader: Diffuse and SelfIllumination are both Combiner3
#   Combiner3 (CO_Add_With_Mask_Modulation): the reflection of the cube map geothermalTexEnv (world space) on the Combiner0, masked by
#       the ShockGlass texture
#   Combiner0 (CO_AlphaBlend_With_Mask): ShockGlass and Combiner1, by the alpha of the ShockControl color
#   Combiner1 (CO_Multiply, Modulate2X): PowerGel, run through TexRotator0 (turning, yaw 2048 a second of 65536 to the turn, about the
#       middle), TexOscillator0 (stretch about the middle, U 0.2 times a second by 0.1, V 0.1 times a second by 0.2) and TexPanner0
#       (along -V, 0.1 of the texture a second), times the ShockControl color
#   ShockControl: R192 G0 B255, and its alpha is 128 times how much the glow has come back after a shot (ShockRifle.RenderOverlays)
#   Final blend: FB_AlphaModulate (the alpha of the control, the glow, modulates what is added)
# What is here: all of it but the cube map (the world's reflection: the mesh's cube map would need a cubemap texture), the glass
# share of the blend is half of the glow and the glow is the material's "intensity" (the skin sets it); the liquid is blended over what
# is in the chamber, half see through at full glow (the alpha of the control), lit by itself (the shader's self illumination).
# Usage: make_chamber_material.py <scratch dir>      (needs the UModel export of the textures: umodel/out3 and out6)

SCRATCH = sys.argv[1]
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
UNITS = REPO + '/units/ut/shock'

sys.path.insert(0, os.path.dirname(__file__))
from convert_weapon import read_tga, write_png, TEXTURE_TEMPLATE

# the textures
for name, tga in (('shock_power_df', SCRATCH + '/umodel/out3/UT2004Weapons/Texture/PowerGel.tga'),
                  ('shock_glass', SCRATCH + '/umodel/out6/UT2004Weapons/Texture/ShockGlass.tga')):
    w, h, rows = read_tga(tga)
    write_png('%s/%s.png' % (UNITS, name), w, h, rows)
    # (not sRGB: UT does its sums on the colours as they are in the texture, which are then shown as they are, see the end of the graph)
    open('%s/%s.texture' % (UNITS, name), 'w', newline='\n').write((TEXTURE_TEMPLATE % ('units/ut/shock/' + name)).replace('srgb = true', 'srgb = false'))

def guid(n):
    return 'c0de0000-0000-4000-8000-%012d' % n

# the connectors of the nodes (inputs) of the SDK's core/shader_nodes
IN_SAMPLE_UV = '1ee9af1f-65f2-4739-ad28-5ea6a0e68fc3'
IN_MUL_A, IN_MUL_B = 'c5823c75-4ae5-4c71-b070-315fa4d03e8e', '242d1648-a626-445b-9534-bccec094112f'
IN_ADD_A, IN_ADD_B = 'f72597c4-7487-419a-affb-df690e6582e1', '0806db0d-2c4a-43ca-99cc-f5a2f036a8e8'
IN_SUB_A, IN_SUB_B = 'd5e375bc-daa4-4464-8448-14bf08d97f0e', 'cff85d3c-d5da-4ffc-ad20-f3872809ac4f'
IN_SIN = '0505200e-439a-476b-b6a6-d643cf80e20b'
IN_LERP_A, IN_LERP_B, IN_LERP_W = '995996dc-408e-4e6f-a310-0db5b3276075', '5551ea38-126d-4d89-ab57-14b36b92a93c', 'cdc83a63-3365-4c10-9353-79ff5f2fd1f0'
IN_ROT_UV, IN_ROT_TIME, IN_ROT_SPEED = '96650519-54EC-47A2-B34E-3B1989F56BB3', '178ABCED-40BA-40B1-BAA4-FB5F9732353B', '399aba19-4e60-4287-b1d3-ee2acb8fd406'
IN_PAN_UV, IN_PAN_TIME, IN_PAN_SPEED_U, IN_PAN_SPEED_V = ('40A76949-E7DB-47FB-9AEC-3FA98DD3FA2E', '0CE9AD0A-0B3F-43B1-9139-12176F3AAD8E',
                                                         '9a282471-a2d2-4591-a57e-c70179bb1962', 'e3419eb2-3635-4586-b58c-89ffd88d20d5')
IN_CONSTANT_VECTOR3 = '6ff26be7-68a1-4b89-b9dd-551d216086c2'
IN_CONSTRUCT_X, IN_CONSTRUCT_Y = '8231a2cb-b751-4ecd-94eb-3e6d048ba173', '46536067-b418-47a5-bc6b-234972e963e9'
IN_OUT_BASE_COLOR, IN_OUT_OPACITY, IN_OUT_ADDITIVE = 'aca690cb-6305-4a2f-bf3d-69183a493db3', '34259752-b962-4b65-92c3-903a57338519', 'c9a30d71-a8ad-4b9e-aedf-d785ae7e301f'

ADDRESS_WRAP, FILTER_LINEAR, SRGB = '5dd59b3d-1762-4a14-9930-7500230ef3db', 'f669a3a6-0376-4187-840e-80000e2939d5', 'e94e53e6-49b6-4194-a747-8f064a5932e0'
IN_SATURATE, IN_POWER_A, IN_POWER_B = '6cebb808-14e4-45d6-9816-3838b1f6f4c7', '447b3fe2-c820-4511-a923-b38b0f6c9fe6', 'e16267f4-8b4e-4079-b13d-f380cfd386ec'
LAYER_TRANSPARENT, DOUBLE_SIDED, BLEND_TRANSPARENT, DISABLE_DEPTH_WRITE = (
    'c8d8b754-c567-4c7b-9cbd-8acab22beff5', '8df1b8f7-17c2-4ae4-8c4e-25517ec1df46',
    '435e14e4-556d-4ac1-af14-8dafe63aff8f', '7b8bc0bf-c453-49d2-9415-0e80fec1039f')

nodes = []       # (id, type, options, export, samplers, title)
connections = [] # (source, destination, connector, select)
constants = []   # (instance, connector, values)
ids = {}

def add_node(name, node_type, options=(), export='', samplers='', title=None):
    ids[name] = guid(len(ids) + 1)
    nodes.append((ids[name], node_type, options, export, samplers, title))

def connect(source, destination, connector, select=None):
    connections.append((ids[source], ids[destination], connector, select))

def constant(node, connector, *values):
    constants.append((ids[node], connector, values))

def variable(name, display, kind, value):
    return ('\t\t\t\tmaterial_variable = {\n\t\t\t\t\tdisplay_name = "%s"\n\t\t\t\t\tname = "%s"\n\t\t\t\t\ttype = "%s"\n'
            '\t\t\t\t\tui = {\n\t\t\t\t\t\tmax = 100\n\t\t\t\t\t\tmin = 0\n\t\t\t\t\t\tstep = 0.001\n\t\t\t\t\t}\n\t\t\t\t\tvalue = %s\n\t\t\t\t}\n'
            % (display, name, kind, value))

def variable3(name, display, values):
    # (a color: three numbers)
    def triple(first, indent):
        return '\t' * indent + '[\n' + ''.join('\t' * (indent + 1) + '%s\n' % v for v in first) + '\t' * indent + ']\n'
    return ('\t\t\t\tmaterial_variable = {\n\t\t\t\t\tdisplay_name = "%s"\n\t\t\t\t\tname = "%s"\n\t\t\t\t\ttype = "float3"\n'
            '\t\t\t\t\tui = {\n\t\t\t\t\t\tmax = %s\t\t\t\t\t\tmin = %s\t\t\t\t\t\tstep = %s\t\t\t\t\t\tui_type = "RGBColor"\n\t\t\t\t\t}\n'
            '\t\t\t\t\tvalue = %s\t\t\t\t}\n'
            % (display, name, triple((100, 100, 100), 6).lstrip('\t'), triple((0, 0, 0), 6).lstrip('\t'),
               triple((0.001, 0.001, 0.001), 6).lstrip('\t'), triple(values, 5).lstrip('\t')))

def sampler(slot):
    # (the key of the sampler of a sample_texture node is always texture_map: the slot of the material is its slot_name)
    return '\t\t\t\ttexture_map = {\n\t\t\t\t\tdisplay_name = "%s"\n\t\t\t\t\tslot_name = "%s"\n\t\t\t\t}\n' % (slot, slot)

TWO_PI = 6.283185307

add_node('out', 'core/stingray_renderer/output_nodes/unlit_base', (LAYER_TRANSPARENT, DOUBLE_SIDED, BLEND_TRANSPARENT, DISABLE_DEPTH_WRITE))
add_node('uv', 'core/shader_nodes/texture_coordinate0')
add_node('time', 'core/shader_nodes/current_time')
# TexRotator0: 2048 of 65536 to the turn, a second
add_node('rotate', 'core/shader_nodes/rotator')
connect('uv', 'rotate', IN_ROT_UV)
connect('time', 'rotate', IN_ROT_TIME)
constant('rotate', IN_ROT_SPEED, 2048 / 65536 * TWO_PI)
# TexOscillator0: OT_Stretch, U 0.2 times a second by 0.1, V 0.1 by 0.2
for axis, rate, amplitude in (('u', 0.2, 0.1), ('v', 0.1, 0.2)):
    add_node('angle_' + axis, 'core/shader_nodes/mul')
    connect('time', 'angle_' + axis, IN_MUL_A)
    constant('angle_' + axis, IN_MUL_B, TWO_PI * rate)
    add_node('sin_' + axis, 'core/shader_nodes/sin')
    connect('angle_' + axis, 'sin_' + axis, IN_SIN)
    add_node('swing_' + axis, 'core/shader_nodes/mul')
    connect('sin_' + axis, 'swing_' + axis, IN_MUL_A)
    constant('swing_' + axis, IN_MUL_B, amplitude)
    add_node('scale_' + axis, 'core/shader_nodes/add')
    connect('swing_' + axis, 'scale_' + axis, IN_ADD_A)
    constant('scale_' + axis, IN_ADD_B, 1)
add_node('scale', 'core/shader_nodes/construct_vector2')
connect('scale_u', 'scale', IN_CONSTRUCT_X)
connect('scale_v', 'scale', IN_CONSTRUCT_Y)
add_node('centered', 'core/shader_nodes/subtract')
connect('rotate', 'centered', IN_SUB_A)
constant('centered', IN_SUB_B, 0.5)
add_node('stretched', 'core/shader_nodes/mul')
connect('centered', 'stretched', IN_MUL_A)
connect('scale', 'stretched', IN_MUL_B)
add_node('stretched_back', 'core/shader_nodes/add')
connect('stretched', 'stretched_back', IN_ADD_A)
constant('stretched_back', IN_ADD_B, 0.5)
# TexPanner0: along -V, 0.1 a second
add_node('pan', 'core/shader_nodes/panner')
connect('stretched_back', 'pan', IN_PAN_UV)
connect('time', 'pan', IN_PAN_TIME)
constant('pan', IN_PAN_SPEED_U, 0)
constant('pan', IN_PAN_SPEED_V, -0.1)
add_node('gel', 'core/shader_nodes/sample_texture', (ADDRESS_WRAP, FILTER_LINEAR, SRGB), samplers=sampler('gel_map'), title='PowerGel')
connect('pan', 'gel', IN_SAMPLE_UV)
# Combiner1: times the ShockControl color (R192 B255), Modulate2X
add_node('control_color', 'core/shader_nodes/material_variable', export=variable3('control_color', 'Control Color', (192 / 255, 0, 1)), title='Control Color')
add_node('control', 'core/shader_nodes/mul')
connect('gel', 'control', IN_MUL_A, 'rgb')
connect('control_color', 'control', IN_MUL_B)
add_node('modulated', 'core/shader_nodes/mul')
connect('control', 'modulated', IN_MUL_A)
constant('modulated', IN_MUL_B, 2)
# Combiner0: the glass over it, by the alpha of the control (128 of 255 when the glow is all back, less before)
add_node('glass', 'core/shader_nodes/sample_texture', (ADDRESS_WRAP, FILTER_LINEAR, SRGB), samplers=sampler('glass_map'), title='ShockGlass')
connect('uv', 'glass', IN_SAMPLE_UV)
add_node('intensity', 'core/shader_nodes/material_variable', export=variable('intensity', 'Intensity', 'float', 1), title='Intensity')
add_node('glass_weight', 'core/shader_nodes/mul')
connect('intensity', 'glass_weight', IN_MUL_A)
constant('glass_weight', IN_MUL_B, 0.5)
add_node('blend', 'core/shader_nodes/lerp')
connect('modulated', 'blend', IN_LERP_A)
connect('glass', 'blend', IN_LERP_B, 'rgb')
connect('glass_weight', 'blend', IN_LERP_W)
# (the "brightness": how bright the liquid is, which the skin makes pulse while the weapon overheats or vents, without the liquid going
# away: it is not the intensity, which is how much of it there is)
add_node('brightness', 'core/shader_nodes/material_variable', export=variable('brightness', 'Brightness', 'float', 1), title='Brightness')
add_node('brightened', 'core/shader_nodes/mul')
connect('blend', 'brightened', IN_MUL_A)
connect('brightness', 'brightened', IN_MUL_B)
# UT does its sums on gamma colours and shows them as they are: the result (at most 1) is made the light that is shown as it
# (the reflection of the cube map, which UT adds, is not here: a gain and a lift in its place, for the light it adds)
add_node('gain', 'core/shader_nodes/mul')
connect('brightened', 'gain', IN_MUL_A)
constant('gain', IN_MUL_B, 1.5)
add_node('lift', 'core/shader_nodes/add')
connect('gain', 'lift', IN_ADD_A)
constant('lift', IN_ADD_B, 0.12)
add_node('shown', 'core/shader_nodes/saturate')
connect('lift', 'shown', IN_SATURATE)
add_node('light', 'core/shader_nodes/power')
connect('shown', 'light', IN_POWER_A)
constant('light', IN_POWER_B, 2.2)
connect('light', 'out', IN_OUT_BASE_COLOR)
# (the alpha of the control, 128 of 255 when the glow is all there: the liquid is half see through, UT's final blend modulates by it)
connect('glass_weight', 'out', IN_OUT_OPACITY)
# (blended, not added, at half the opacity: the liquid is half see through in UT, and the glow takes it away after a shot)
constant('out', IN_OUT_ADDITIVE, 0)

text = 'shader = {\n\tconnections = [\n'
for source, destination, connector, select in connections:
    text += '\t\t{\n\t\t\tdestination = {\n\t\t\t\tconnector_id = "%s"\n\t\t\t\tinstance_id = "%s"\n\t\t\t}\n' % (connector, destination)
    if select:
        text += '\t\t\tselect = [\n\t\t\t\t"%s"\n\t\t\t]\n' % select
    text += '\t\t\tsource = {\n\t\t\t\tinstance_id = "%s"\n\t\t\t}\n\t\t}\n' % source
text += '\t]\n\tconstants = [\n'
for n, (instance, connector, values) in enumerate(constants):
    text += '\t\t{\n\t\t\tconnector_id = "%s"\n\t\t\tid = "%s"\n\t\t\tinstance_id = "%s"\n\t\t\tvalue = [\n' % (connector, guid(1000 + n), instance)
    for v in values:
        text += '\t\t\t\t%s\n' % repr(float(v)) if not float(v).is_integer() else '\t\t\t\t%d\n' % int(v)
    text += '\t\t\t]\n\t\t}\n'
text += '\t]\n\tgroups = [\n\t]\n\tnodes = [\n'
for n, (node_id, node_type, options, export, samplers, title) in enumerate(nodes):
    text += '\t\t{\n\t\t\tcontent_size = [\n\t\t\t\t160\n\t\t\t\t0\n\t\t\t]\n\t\t\texport = {\n%s\t\t\t}\n\t\t\tid = "%s"\n\t\t\toptions = [\n' % (export, node_id)
    for o in options:
        text += '\t\t\t\t"%s"\n' % o
    text += '\t\t\t]\n\t\t\tposition = [\n\t\t\t\t%d\n\t\t\t\t%d\n\t\t\t]\n\t\t\tsamplers = {\n%s\t\t\t}\n' % (300 * (n % 6), 200 * (n // 6), samplers)
    if title:
        text += '\t\t\ttitle = "%s"\n' % title
    text += '\t\t\ttype = "%s"\n\t\t}\n' % node_type
text += '\t]\n\tversion = 3\n}\ntextures = {\n}\nvariables = {\n\tbrightness = {\n\t\ttype = "scalar"\n\t\tvalue = 1\n\t}\n\tcontrol_color = {\n\t\ttype = "vector3"\n\t\tvalue = [\n\t\t\t0.752941\n\t\t\t0\n\t\t\t1\n\t\t]\n\t}\n\tintensity = {\n\t\ttype = "scalar"\n\t\tvalue = 1\n\t}\n}\n'
# Two graphs: the chamber of the pickup (and of the character's hand), and the chamber of the first person rifle, which is drawn with the game's
# custom FOV for weapons (the option HAS_CUSTOM_FOV of unlit_base), as the game's own first person weapons are: it is that option that makes the
# outlines of other players not be drawn over it, see units/ut/weapon_standard.material.
HAS_CUSTOM_FOV = 'b2556764-e8e9-47cf-9ecc-f53b5d5d73c7'
last_option = '\t\t\t\t"%s"\n' % DISABLE_DEPTH_WRITE
assert text.count(last_option) == 1
variants = {
    'shock_rifle_chamber': text,
    'shock_rifle_fp_chamber': text.replace(last_option, last_option + '\t\t\t\t"%s"\n' % HAS_CUSTOM_FOV),
}
for name, graph_text in variants.items():
    open('%s/%s.material' % (UNITS, name), 'w', newline='\n').write(graph_text)
    # (the textures are bound by a material derived from the graph, as the materials of the effects are)
    power_name = name.replace('chamber', 'power')
    open('%s/%s.material' % (UNITS, power_name), 'w', newline='\n').write('''material_contexts = {
	surface_material = ""
}
parent_material = "units/ut/shock/%s"
textures = {
	gel_map = "units/ut/shock/shock_power_df"
	glass_map = "units/ut/shock/shock_glass"
}
variables = {
}
''' % name)
    # The Instagib Shock Rifle: its ShockControl color is the team's, red (HUD.RedColor)
    open('%s/%s_instagib.material' % (UNITS, power_name), 'w', newline='\n').write('''material_contexts = {
	surface_material = ""
}
parent_material = "units/ut/shock/%s"
textures = {
	gel_map = "units/ut/shock/shock_power_df"
	glass_map = "units/ut/shock/shock_glass"
}
variables = {
	control_color = {
		type = "vector3"
		value = [
			1
			0
			0
		]
	}
}
''' % name)
print('wrote the chamber and power materials of the pickup and of the first person rifle,', len(nodes), 'nodes')
