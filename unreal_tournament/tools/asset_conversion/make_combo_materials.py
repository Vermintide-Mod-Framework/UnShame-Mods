import os, sys, math

# Makes the materials of the two meshes of the Shock Rifle's combo, as UT2004 has them, as shader graphs that run on the GPU (as the chamber's
# does, see make_chamber_material.py): the panning is done by the graph, so that nothing is baked and the effect needs no frames.
#
#   fx_combo_sphere  ShockComboSphereDark's Shader N_energy01_S_JM (WarEffectsTextures): FinalBlend8 (FB_Overwrite) of the TexPanner
#                    C_T_BoltPanner_AW (DeployableTex) of the texture C_T_Electricity_SG: the bolts, panned along U at 10 a second (PanDirection
#                    yaw 1000 of 65536 turns, PanRate 10), translucent: they are what is there of the sphere, the rest of it is see through
#   fx_combo_vortex  ShockComboVortex's FinalBlend ShockElecRingFB (XEffectMat): FB_Translucent of the Combiner ShockElecRingComb
#                    (CO_Multiply) of the TexPanner ShockElecAPanner (Shock_Elec_a, PanDirection yaw 16000, PanRate -1: along -V, a texture a
#                    second) and the texture shock_gradient_b (a band: it is only there that the lines are seen)
#   fx_explosion_dark  ShockExplosion's ShockDarkFB (not the combo's: the dark sphere that the ball's explosion makes)
# Each is a graph (fx_combo_*_graph) and a material derived from it that binds its textures. The effects set their "intensity" (UT's ScaleGlow,
# how much of it there is) and "tint" (a color that multiplies it).
# Usage: make_combo_materials.py        (the textures are those of make_fx_assets.py: units/ut/fx/shock_electricity, shock_elec_a, shock_gradient_b)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FX = REPO + '/units/ut/fx'

def guid(n):
    return 'c0de0001-0000-4000-8000-%012d' % n

# the connectors of the nodes (inputs) of the SDK's core/shader_nodes, and the options (as the material of the particles and the chamber have them)
IN_SAMPLE_UV = '1ee9af1f-65f2-4739-ad28-5ea6a0e68fc3'
IN_MUL_A, IN_MUL_B = 'c5823c75-4ae5-4c71-b070-315fa4d03e8e', '242d1648-a626-445b-9534-bccec094112f'
IN_PAN_UV, IN_PAN_TIME, IN_PAN_SPEED_U, IN_PAN_SPEED_V = ('40A76949-E7DB-47FB-9AEC-3FA98DD3FA2E', '0CE9AD0A-0B3F-43B1-9139-12176F3AAD8E',
                                                         '9a282471-a2d2-4591-a57e-c70179bb1962', 'e3419eb2-3635-4586-b58c-89ffd88d20d5')
IN_OUT_BASE_COLOR, IN_OUT_OPACITY, IN_OUT_ADDITIVE = 'aca690cb-6305-4a2f-bf3d-69183a493db3', '34259752-b962-4b65-92c3-903a57338519', 'c9a30d71-a8ad-4b9e-aedf-d785ae7e301f'
SAMPLE_OPTIONS = ('5dd59b3d-1762-4a14-9930-7500230ef3db', 'f669a3a6-0376-4187-840e-80000e2939d5', 'fb3f709b-a54a-4e93-ac9f-e9fc76fb8bcd')
OUT_OPTIONS = ('c8d8b754-c567-4c7b-9cbd-8acab22beff5', '8df1b8f7-17c2-4ae4-8c4e-25517ec1df46',
               '435e14e4-556d-4ac1-af14-8dafe63aff8f', '7b8bc0bf-c453-49d2-9415-0e80fec1039f')

def float_variable(name, display, value):
    return ('\t\t\t\tmaterial_variable = {\n\t\t\t\t\tdisplay_name = "%s"\n\t\t\t\t\tname = "%s"\n\t\t\t\t\ttype = "float"\n'
            '\t\t\t\t\tui = {\n\t\t\t\t\t\tmax = 100\n\t\t\t\t\t\tmin = 0\n\t\t\t\t\t\tstep = 0.001\n\t\t\t\t\t}\n\t\t\t\t\tvalue = %s\n\t\t\t\t}\n' % (display, name, value))

def color_variable(name, display):
    return ('\t\t\t\tmaterial_variable = {\n\t\t\t\t\tdisplay_name = "%s"\n\t\t\t\t\tname = "%s"\n\t\t\t\t\ttype = "float3"\n'
            '\t\t\t\t\tui = {\n\t\t\t\t\t\tmax = [\n\t\t\t\t\t\t\t1\n\t\t\t\t\t\t\t1\n\t\t\t\t\t\t\t1\n\t\t\t\t\t\t]\n\t\t\t\t\t\tmin = [\n\t\t\t\t\t\t\t0\n\t\t\t\t\t\t\t0\n\t\t\t\t\t\t\t0\n\t\t\t\t\t\t]\n'
            '\t\t\t\t\t\tstep = [\n\t\t\t\t\t\t\t0.001\n\t\t\t\t\t\t\t0.001\n\t\t\t\t\t\t\t0.001\n\t\t\t\t\t\t]\n\t\t\t\t\t}\n'
            '\t\t\t\t\tvalue = [\n\t\t\t\t\t\t1\n\t\t\t\t\t\t1\n\t\t\t\t\t\t1\n\t\t\t\t\t]\n\t\t\t\t}\n' % (display, name))

def sampler(slot):
    # (the key of the sampler of a sample_texture node is always texture_map: the slot of the material is its slot_name)
    return '\t\t\t\ttexture_map = {\n\t\t\t\t\tdisplay_name = "%s"\n\t\t\t\t\tslot_name = "%s"\n\t\t\t\t}\n' % (slot, slot)

class Graph:
    def __init__(self):
        self.nodes = []        # (id, type, options, export, samplers, title)
        self.connections = []  # (source, destination, connector, select)
        self.constants = []    # (instance, connector, value)
        self.ids = {}
        self.no_variables = False    # (a graph that has none of the variables of the effects, such as the decal's)

    def add(self, name, node_type, options=(), export='', samplers='', title=None):
        self.ids[name] = guid(len(self.ids) + 1)
        self.nodes.append((self.ids[name], node_type, options, export, samplers, title))

    def connect(self, source, destination, connector, select=None):
        self.connections.append((self.ids[source], self.ids[destination], connector, select))

    def constant(self, node, connector, value):
        self.constants.append((self.ids[node], connector, value))

    def text(self):
        text = 'shader = {\n\tconnections = [\n'

        for source, destination, connector, select in self.connections:
            text += '\t\t{\n\t\t\tdestination = {\n\t\t\t\tconnector_id = "%s"\n\t\t\t\tinstance_id = "%s"\n\t\t\t}\n' % (connector, destination)

            if select:
                text += '\t\t\tselect = [\n\t\t\t\t"%s"\n\t\t\t]\n' % select

            text += '\t\t\tsource = {\n\t\t\t\tinstance_id = "%s"\n\t\t\t}\n\t\t}\n' % source

        text += '\t]\n\tconstants = [\n'

        for n, (instance, connector, value) in enumerate(self.constants):
            text += '\t\t{\n\t\t\tconnector_id = "%s"\n\t\t\tid = "%s"\n\t\t\tinstance_id = "%s"\n\t\t\tvalue = [\n' % (connector, guid(1000 + n), instance)
            # (a number, or a list of them for a vector)
            for component in (value if isinstance(value, (list, tuple)) else [value]):
                text += '\t\t\t\t%s\n' % (repr(float(component)) if not float(component).is_integer() else '%d' % int(component))
            text += '\t\t\t]\n\t\t}\n'

        text += '\t]\n\tgroups = [\n\t]\n\tnodes = [\n'

        for n, (node_id, node_type, options, export, samplers, title) in enumerate(self.nodes):
            text += '\t\t{\n\t\t\tcontent_size = [\n\t\t\t\t160\n\t\t\t\t0\n\t\t\t]\n\t\t\texport = {\n%s\t\t\t}\n\t\t\tid = "%s"\n\t\t\toptions = [\n' % (export, node_id)

            for option in options:
                text += '\t\t\t\t"%s"\n' % option

            text += '\t\t\t]\n\t\t\tposition = [\n\t\t\t\t%d\n\t\t\t\t%d\n\t\t\t]\n\t\t\tsamplers = {\n%s\t\t\t}\n' % (300 * (n % 6), 200 * (n // 6), samplers)

            if title:
                text += '\t\t\ttitle = "%s"\n' % title

            text += '\t\t\ttype = "%s"\n\t\t}\n' % node_type

        if self.no_variables:
            return text + '\t]\n\tversion = 3\n}\ntextures = {\n}\nvariables = {\n}\n'

        text += ('\t]\n\tversion = 3\n}\ntextures = {\n}\nvariables = {\n\tadditive = {\n\t\ttype = "scalar"\n\t\tvalue = 0\n\t}\n\tage = {\n\t\ttype = "scalar"\n\t\tvalue = 0\n\t}\n\tintensity = {\n\t\ttype = "scalar"\n\t\tvalue = 1\n\t}\n'
                 '\ttint = {\n\t\ttype = "vector3"\n\t\tvalue = [\n\t\t\t1\n\t\t\t1\n\t\t\t1\n\t\t]\n\t}\n}\n')

        return text

UNLIT = 'core/stingray_renderer/output_nodes/unlit_base'
# (the unlit node that blends as FB_Brighten does: make_brighten_node.py)
BRIGHTEN = 'units/ut/fx/brighten_base'

def common(graph, output=UNLIT):
    graph.add('out', output, OUT_OPTIONS)
    graph.add('uv', 'core/shader_nodes/texture_coordinate0')
    # (the time of the panning is how long the effect has been going, set by the particle: UT's panners start with the effect, not with the game)
    graph.add('time', 'core/shader_nodes/material_variable', export=float_variable('age', 'Age', 0), title='Age')
    graph.add('intensity', 'core/shader_nodes/material_variable', export=float_variable('intensity', 'Intensity', 1), title='Intensity')
    graph.add('tint', 'core/shader_nodes/material_variable', export=color_variable('tint', 'Tint'), title='Tint')
    # (blended by its opacity, not added: the effects of the particles set "additive" on all the materials of a unit, and this is 0 as it is)
    graph.add('additive', 'core/shader_nodes/material_variable', export=float_variable('additive', 'Additive', 0), title='Additive')
    graph.connect('additive', 'out', IN_OUT_ADDITIVE)

def panned(graph, name, speed_u, speed_v):
    # (the coordinates of the texture, moved by speed_u and speed_v of it a second)
    graph.add(name, 'core/shader_nodes/panner')
    graph.connect('uv', name, IN_PAN_UV)
    graph.connect('time', name, IN_PAN_TIME)
    graph.constant(name, IN_PAN_SPEED_U, speed_u)
    graph.constant(name, IN_PAN_SPEED_V, speed_v)

def texture(graph, name, slot, uv):
    graph.add(name, 'core/shader_nodes/sample_texture', SAMPLE_OPTIONS, samplers=sampler(slot), title=slot)
    graph.connect(uv, name, IN_SAMPLE_UV)

def multiply(graph, name, a, b, a_select=None, b_select=None):
    graph.add(name, 'core/shader_nodes/mul')
    graph.connect(a, name, IN_MUL_A, a_select)
    graph.connect(b, name, IN_MUL_B, b_select)

def write(name, graph, textures):
    open('%s/fx_%s_graph.material' % (FX, name), 'w', newline='\n').write(graph.text())
    # (the textures are bound by a material derived from the graph, as the materials of the effects are)
    bound = ''.join('\t%s = "units/ut/fx/%s"\n' % (slot, texture_name) for slot, texture_name in textures.items())
    open('%s/fx_%s.material' % (FX, name), 'w', newline='\n').write(
        'material_contexts = {\n\tsurface_material = ""\n}\nparent_material = "units/ut/fx/fx_%s_graph"\ntextures = {\n%s}\nvariables = {\n}\n' % (name, bound))
    print('wrote fx_%s.material and fx_%s_graph.material, %d nodes' % (name, name, len(graph.nodes)))

# ---------------------------------------------------------------- the sphere: the bolts, panned along U at 10 a second
sphere = Graph()
common(sphere)
# (PanDirection yaw 1000 of 65536: cos and sin of 5.5 degrees, times PanRate 10)
panned(sphere, 'pan', 9.9540, 0.9585)
texture(sphere, 'bolts', 'bolts_map', 'pan')
# (it is the color of the texture that is the bolts, not its alpha: UT's FB_Overwrite draws the color as it is, and the white zigzag of the lightning
# over the blue line is in the color, where the alpha is all but nothing; it is added, so that the dark of the texture is not seen)
multiply(sphere, 'color', 'bolts', 'tint', 'rgb')
sphere.connect('color', 'out', IN_OUT_BASE_COLOR)
sphere.connect('intensity', 'out', IN_OUT_OPACITY)
write('combo_sphere', sphere, {'bolts_map': 'shock_electricity'})

# ---------------------------------------------------------------- the vortex: the lines, panned along -V a texture a second, in a band
vortex = Graph()
common(vortex)
# (PanDirection yaw 16000 of 65536: cos and sin of 87.9 degrees, times PanRate -1)
panned(vortex, 'pan', -0.0368, -0.9993)
texture(vortex, 'lines', 'lines_map', 'pan')
texture(vortex, 'band', 'band_map', 'uv')
multiply(vortex, 'lit', 'lines', 'band', 'rgb', 'rgb')
multiply(vortex, 'color', 'lit', 'tint')
# (the lines are blue on black, and the band is a gradient in its color: the product of their colors is the lightning of the ring, added, so that its
# black is not seen: blended by their alpha it was drawn dark)
vortex.connect('color', 'out', IN_OUT_BASE_COLOR)
vortex.connect('intensity', 'out', IN_OUT_OPACITY)
write('combo_vortex', vortex, {'lines_map': 'shock_elec_a', 'band_map': 'shock_gradient_b'})

# ---------------------------------------------------------------- the dark sphere of the explosion of the ball
# ShockExplosion's FinalBlend ShockDarkFB (XEffectMat): FB_Darken of the TexPanner ShockElecDPanner (PanDirection yaw 0, PanRate 1: along U, a texture
# a second) of the texture shock_Energy_green_faded. It darkens what is behind it by what its texture is bright: here it is black, blended by the
# green of the texture (the stock blends cannot darken each color of the screen by itself).
dark = Graph()
common(dark)
panned(dark, 'pan', 1, 0)
texture(dark, 'blobs', 'blobs_map', 'pan')
multiply(dark, 'opacity', 'blobs', 'intensity', 'g')
dark.connect('tint', 'out', IN_OUT_BASE_COLOR)
dark.connect('opacity', 'out', IN_OUT_OPACITY)
write('explosion_dark', dark, {'blobs_map': 'shock_dark'})

# ---------------------------------------------------------------- the goop
# GoopMesh's FinalBlend GoopFB (XEffectMat): FB_Translucent of the Shader GoopShader, whose diffuse and self illumination are the TexOscillator
# GoopOsc (OT_Pan, 0.07 of the texture a second along U and 0.17 along V) of the texture goop_green_a. It is lit by itself and see through
# (the effect blends it by its opacity).
goop = Graph()
common(goop)
panned(goop, 'pan', 0.07, 0.17)
texture(goop, 'goop', 'goop_map', 'pan')
multiply(goop, 'color', 'goop', 'tint', 'rgb')
# (it is see through as much as intensity says: the alpha of the texture did not make it so)
goop.connect('color', 'out', IN_OUT_BASE_COLOR)
goop.connect('intensity', 'out', IN_OUT_OPACITY)
write('goop', goop, {'goop_map': 'bio_goop'})

# ---------------------------------------------------------------- the splat decal
# BioDecal's xbiosplat, drawn by the decal shader onto the surfaces under the box of the unit decal_bio: the green of bio_splat, cut out and
# blended by bio_splat_mask (a gray, see make_fx_assets.py).
IN_DECAL_BASE_COLOR_OPACITY = 'ad5e052f-d316-4a0f-8b79-53c38204d61b'
IN_DECAL_MASK, IN_DECAL_MASK_THRESHOLD = '34259752-b962-4b65-92c3-903a57338519', '7a9306c6-95ae-4cdb-9fef-0eedacce4e83'
decal = Graph()
decal.no_variables = True
# (the decal group 0, 1 and 2, not 3: the first person weapons are in the group 3, see units/ut/weapon_standard.material, and the decal does not
# draw on them)
decal.add('out', 'core/stingray_renderer/output_nodes/decal_base', ('4035efa3-d637-4d4d-865d-24653f90b7a3',))
decal.add('uv', 'core/shader_nodes/decal_uv')
texture(decal, 'splat', 'splat_map', 'uv')
texture(decal, 'shape', 'shape_map', 'uv')
decal.connect('splat', 'out', IN_OUT_BASE_COLOR, 'rgb')
decal.connect('shape', 'out', IN_DECAL_BASE_COLOR_OPACITY, 'r')
decal.connect('shape', 'out', IN_DECAL_MASK, 'r')
decal.constant('out', IN_DECAL_MASK_THRESHOLD, 0.05)
write('decal_bio', decal, {'splat_map': 'bio_splat', 'shape_map': 'bio_splat_mask'})

# ---------------------------------------------------------------- the goop in the Bio Rifle's tank
# The Bio Rifle's first person mesh has its third material, BRPickupC (WeaponSkins): a Combiner (CO_AlphaBlend_With_Mask) of the TexPanner BRpickupP
# (BioGoo.BRInnerGoo, PanRate 0.3 along U) and the TexPanner BRBubblesP (BioGoo.BRInnerBubbles, PanRate 0.8 along V), with the bubbles as the mask:
# the green goop, with the bubbles in it. It is on the pieces of the mesh inside the tank, and one of them moves with the plunger. The mesh is drawn
# with the game's field of view for weapons, as the other materials of the weapon are (units/ut/weapon_standard.material), so that it is not
# placed differently from them. The material that binds the textures is units/ut/bio/bio_rifle_m2.material.
CUSTOM_FOV = 'b2556764-e8e9-47cf-9ecc-f53b5d5d73c7'
LAYER_EMISSIVE = '52c7ce01-ee57-4770-914e-727fc1966962'
IN_LERP_A, IN_LERP_B, IN_LERP_W = '995996dc-408e-4e6f-a310-0db5b3276075', '5551ea38-126d-4d89-ab57-14b36b92a93c', 'cdc83a63-3365-4c10-9353-79ff5f2fd1f0'
goo = Graph()
goo.no_variables = True
# (in the emissive layer, which is drawn before the transparent ones, so that the glass of the tank blends over it: blended, it was drawn over the glass)
# (double sided, and with the weapons' custom FOV)
goo.add('out', 'core/stingray_renderer/output_nodes/unlit_base', (OUT_OPTIONS[1], LAYER_EMISSIVE, CUSTOM_FOV))
goo.add('uv', 'core/shader_nodes/texture_coordinate0')
goo.add('time', 'core/shader_nodes/current_time')
panned(goo, 'pan_goo', 0.3, 0)
panned(goo, 'pan_bubbles', 0, 0.8)
texture(goo, 'goo', 'goo_map', 'pan_goo')
texture(goo, 'bubbles', 'bubbles_map', 'pan_bubbles')
goo.add('mix', 'core/shader_nodes/lerp')
goo.connect('goo', 'mix', IN_LERP_A, 'rgb')
goo.connect('bubbles', 'mix', IN_LERP_B, 'rgb')
goo.connect('bubbles', 'mix', IN_LERP_W, 'a')
# (the emissive layer is HDR, where 1 is very bright: dimmed so that the goop is the green of the texture)
goo.add('dim', 'core/shader_nodes/mul')
goo.connect('mix', 'dim', IN_MUL_A)
goo.constant('dim', IN_MUL_B, 0.04)
goo.connect('dim', 'out', IN_OUT_BASE_COLOR)
open('%s/fx_bio_goo_graph.material' % FX, 'w', newline='\n').write(goo.text())
open('%s/units/ut/bio/bio_rifle_m2.material' % REPO, 'w', newline='\n').write(
    'material_contexts = {\n\tsurface_material = ""\n}\nparent_material = "units/ut/fx/fx_bio_goo_graph"\ntextures = {\n'
    '\tgoo_map = "units/ut/bio/bio_rifle_brinnergoo"\n\tbubbles_map = "units/ut/bio/bio_rifle_brinnerbubbles"\n}\nvariables = {\n}\n')
print('wrote fx_bio_goo_graph.material and bio_rifle_m2.material, %d nodes' % len(goo.nodes))

# ---------------------------------------------------------------- the Lightning Gun's screen
# The first person mesh's second material, SniperScreen1C (WeaponSkins): a Combiner (CO_AlphaBlend_With_Mask) of the scope's readout,
# SniperScreen1, over the TexPanner SniperScreen1P (the scan lines of SniperScreen1Pan, PanDirection yaw 16384: along V, PanRate 0.2), with
# the panned lines' alpha as the mask. The lines pan along +V here as in UT (checked in the game: the mesh's V being turned over by
# convert_weapon.py doesn't turn the panning over, as the texture is stored the other way up too). It is lit as the rest of
# the weapon is: the SDK's standard output node, with the options of units/ut/weapon_standard.material (its three, the weapons' custom field of
# view, and the decal group 3), roughness 0.9 as the weapon's, and not metallic. The material that binds the textures is
# units/ut/lightning/lightning_gun_m1.material.
IN_STANDARD_ROUGHNESS, IN_STANDARD_METALLIC = '36ba46d2-f6ea-4e60-a428-fdc17c75bc62', 'ad5e052f-d316-4a0f-8b79-53c38204d61b'
STANDARD_OPTIONS = ('2b136447-676e-4943-997b-04a28ae68497', 'b2c7c0d2-beff-4b1a-a9d4-068a507625a2', 'b5bb2062-c8fa-43c5-8657-493a0be6860c',
                    '901b44ce-d128-498a-9912-32cd9635c556', 'fe20cc01-4cec-4217-98a0-07220ad3add9')
screen = Graph()
screen.no_variables = True
screen.add('out', 'core/stingray_renderer/output_nodes/standard_base', STANDARD_OPTIONS)
screen.add('uv', 'core/shader_nodes/texture_coordinate0')
screen.add('time', 'core/shader_nodes/current_time')
panned(screen, 'pan_lines', 0, 0.2)
texture(screen, 'readout', 'screen_map', 'uv')
texture(screen, 'lines', 'lines_map', 'pan_lines')
screen.add('mix', 'core/shader_nodes/lerp')
screen.connect('lines', 'mix', IN_LERP_A, 'rgb')
screen.connect('readout', 'mix', IN_LERP_B, 'rgb')
screen.connect('lines', 'mix', IN_LERP_W, 'a')
screen.connect('mix', 'out', IN_OUT_BASE_COLOR)
screen.constant('out', IN_STANDARD_ROUGHNESS, 0.9)
screen.constant('out', IN_STANDARD_METALLIC, 0)
open('%s/fx_sniper_screen_graph.material' % FX, 'w', newline='\n').write(screen.text())
open('%s/units/ut/lightning/lightning_gun_m1.material' % REPO, 'w', newline='\n').write(
    'material_contexts = {\n\tsurface_material = ""\n}\nparent_material = "units/ut/fx/fx_sniper_screen_graph"\ntextures = {\n'
    '\tscreen_map = "units/ut/lightning/lightning_gun_sniperscreen1"\n\tlines_map = "units/ut/lightning/lightning_gun_sniperscreen1pan"\n}\n'
    'variables = {\n}\n')
print('wrote fx_sniper_screen_graph.material and lightning_gun_m1.material, %d nodes' % len(screen.nodes))

# ---------------------------------------------------------------- the Shield Gun's shield
# ShieldEffect's FinalBlend Shield3rdFB (XEffectMat): FB_Brighten of the Shader Shader3, whose diffuse is the TexPanner TexPanner2 (PanDirection
# yaw 16384: along V, PanRate 0.2) of the TexOscillator TexOscillator2 (OT_Pan along U, amplitude 0.1, rate 0.2 a second) of the texture
# shield_elec_green_a, and whose opacity is that texture as it is, not panned. Its alpha fades in over the first sixth of V, which is the rim
# of the shield's dish, so the rim fades out; here the colour is multiplied by it.
# FB_Brighten is c + d * (1 - c) for each channel. The output node blends by one number for all three, as c + d * (1 - a) with a its opacity
# times (1 - additive). Here a is the luminance of c: on a grey background that gives the same brightness as UT, and only the tint behind the
# shield is a little off. (Its brightest channel, which the texture had baked in before, darkened what is behind it too much.) So the opacity
# is the intensity, and additive is 1 - luminance.
# The oscillation is left out: it sways the lines by a tenth of the texture every five seconds. It is drawn with the weapons' field of view,
# as UT draws it with the weapon (ShieldAltFire.DrawMuzzleFlash), and the texture is read as it is (not srgb), alpha and all
# (units/ut/fx/shield_elec, make_weapon_fx.py).
IN_DOT_A, IN_DOT_B = '1227923c-0ef1-4823-b673-301cc9a5fc69', '0e627d0f-2503-4925-9811-d44aca00e49c'
IN_SUBTRACT_A, IN_SUBTRACT_B = 'd5e375bc-daa4-4464-8448-14bf08d97f0e', 'cff85d3c-d5da-4ffc-ad20-f3872809ac4f'
IN_ADD_A, IN_ADD_B = 'f72597c4-7487-419a-affb-df690e6582e1', '0806db0d-2c4a-43ca-99cc-f5a2f036a8e8'
IN_CONSTANT_VECTOR3 = '6ff26be7-68a1-4b89-b9dd-551d216086c2'
IN_CONSTANT_SCALAR = 'c4d6bc08-c489-430f-a836-ed490e59c3f9'
LINEAR_SAMPLE_OPTIONS = ('5dd59b3d-1762-4a14-9930-7500230ef3db', 'f669a3a6-0376-4187-840e-80000e2939d5', 'e94e53e6-49b6-4194-a747-8f064a5932e0')

# The shield's graph: the lines panned by pan_u and pan_v a second, faded by the alpha of the fade texture as it is, and with
# lines_alpha by the lines' own alpha too. In the world (a shield on another player) it is drawn with the camera's field of view.
def shield_graph(pan_u, pan_v, lines_alpha, world=False):
    shield = Graph()
    shield.add('out', 'core/stingray_renderer/output_nodes/unlit_base', OUT_OPTIONS + (() if world else (CUSTOM_FOV,)))
    shield.add('uv', 'core/shader_nodes/texture_coordinate0')
    shield.add('time', 'core/shader_nodes/material_variable', export=float_variable('age', 'Age', 0), title='Age')
    shield.add('intensity', 'core/shader_nodes/material_variable', export=float_variable('intensity', 'Intensity', 1), title='Intensity')
    shield.add('tint', 'core/shader_nodes/material_variable', export=color_variable('tint', 'Tint'), title='Tint')
    shield.add('additive', 'core/shader_nodes/material_variable', export=float_variable('additive', 'Additive', 0), title='Additive')
    panned(shield, 'pan', pan_u, pan_v)
    shield.add('lines', 'core/shader_nodes/sample_texture', LINEAR_SAMPLE_OPTIONS, samplers=sampler('lines_map'), title='lines_map')
    shield.connect('pan', 'lines', IN_SAMPLE_UV)
    shield.add('fade', 'core/shader_nodes/sample_texture', LINEAR_SAMPLE_OPTIONS, samplers=sampler('fade_map'), title='fade_map')
    shield.connect('uv', 'fade', IN_SAMPLE_UV)
    # (the colour: the lines, faded at the rim, tinted)
    if lines_alpha:
        multiply(shield, 'lines_faded', 'lines', 'lines', 'rgb', 'a')
        multiply(shield, 'faded', 'lines_faded', 'fade', None, 'a')
    else:
        multiply(shield, 'faded', 'lines', 'fade', 'rgb', 'a')
    multiply(shield, 'color', 'faded', 'tint')
    brightened(shield)
    return shield

# Draws a graph's 'color' node as FB_Brighten does, as near as one number for the three channels can: c + d * (1 - a), with a the
# luminance of c. FB_Brighten is exact in each channel; one number can only be exact in one, and the luminance is right for a grey and
# near for a pale colour. The opacity is the intensity, and additive is 1 - a plus the particles' own additive, which they set to 0 for
# these. The shield is drawn this way; the other FB_Brighten materials are drawn by BRIGHTEN, which blends each channel as FB_Brighten
# does.
def brightened(graph):
    graph.connect('color', 'out', IN_OUT_BASE_COLOR)
    graph.connect('intensity', 'out', IN_OUT_OPACITY)
    graph.add('weights', 'core/shader_nodes/constant_vector3')
    graph.constant('weights', IN_CONSTANT_VECTOR3, [0.2126, 0.7152, 0.0722])
    graph.add('luminance', 'core/shader_nodes/dot')
    graph.connect('color', 'luminance', IN_DOT_A)
    graph.connect('weights', 'luminance', IN_DOT_B)
    graph.add('one', 'core/shader_nodes/constant_scalar')
    graph.constant('one', IN_CONSTANT_SCALAR, 1)
    graph.add('see_through', 'core/shader_nodes/subtract')
    graph.connect('one', 'see_through', IN_SUBTRACT_A)
    graph.connect('luminance', 'see_through', IN_SUBTRACT_B)
    graph.add('blend', 'core/shader_nodes/add')
    graph.connect('see_through', 'blend', IN_ADD_A)
    graph.connect('additive', 'blend', IN_ADD_B)
    graph.connect('blend', 'out', IN_OUT_ADDITIVE)

write('shield', shield_graph(0, 0.2, False), {'lines_map': 'shield_elec', 'fade_map': 'shield_elec'})
write('shield_world', shield_graph(0, 0.2, False, True), {'lines_map': 'shield_elec', 'fade_map': 'shield_elec'})

# ShieldEffect's other skin, ShieldRip3rdFB, which ShieldEffect.Flash shows for 0.2 seconds when the shield stops something: FB_Brighten of the
# Combiner ShieldRipComb, the colour of the TexPanner ShieldRipPanner (PanDirection yaw 12000, PanRate 0.35) of shield_elec_green_rip_a,
# and the alpha of that times the alpha of edgegrad (AO_Multiply), which fades the rim as the shield's own does
# (units/ut/fx/shield_rip_elec and shield_edge, make_weapon_fx.py).
RIP_PAN = 12000 / 65536 * 2 * math.pi
write('shield_rip', shield_graph(0.35 * math.cos(RIP_PAN), 0.35 * math.sin(RIP_PAN), True), {'lines_map': 'shield_rip_elec', 'fade_map': 'shield_edge'})
write('shield_rip_world', shield_graph(0.35 * math.cos(RIP_PAN), 0.35 * math.sin(RIP_PAN), True, True), {'lines_map': 'shield_rip_elec', 'fade_map': 'shield_edge'})

# ---------------------------------------------------------------- the particles that UT draws with FB_Brighten
# The Minigun's first person flash (MinigunMuzFlash1stFinal, FB_Brighten) and the dust where its rounds hit (pclImpactSmoke, STY_Translucent,
# which is the same: c + d * (1 - c) for each channel) are drawn by these, with the node that blends each channel as FB_Brighten does
# (BRIGHTEN). The texture is read as it is (not srgb), and the colour is its own, tinted. fx_particle_brighten_graph draws with the
# camera's field of view and fx_particle_weapon_brighten_graph with the weapons'. make_weapon_fx.py derives a material of each of those
# textures from them. The _srgb ones read the texture as srgb: UT2004 draws in gamma space and puts a texture's values on the screen as
# they are, and read linearly the game turns them into the screen's values brighter and paler (the first person flash's orange).
def brighten_graph(weapon, srgb=False):
    graph = Graph()
    graph.add('out', BRIGHTEN, OUT_OPTIONS + ((CUSTOM_FOV,) if weapon else ()))
    graph.add('uv', 'core/shader_nodes/texture_coordinate0')
    # (the particles set the age of every material, which these don't use)
    graph.add('time', 'core/shader_nodes/material_variable', export=float_variable('age', 'Age', 0), title='Age')
    graph.add('intensity', 'core/shader_nodes/material_variable', export=float_variable('intensity', 'Intensity', 1), title='Intensity')
    graph.add('tint', 'core/shader_nodes/material_variable', export=color_variable('tint', 'Tint'), title='Tint')
    graph.add('additive', 'core/shader_nodes/material_variable', export=float_variable('additive', 'Additive', 0), title='Additive')
    graph.add('texture', 'core/shader_nodes/sample_texture', SAMPLE_OPTIONS if srgb else LINEAR_SAMPLE_OPTIONS, samplers=sampler('texture_map'), title='texture_map')
    graph.connect('uv', 'texture', IN_SAMPLE_UV)
    multiply(graph, 'color', 'texture', 'tint', 'rgb')
    graph.connect('color', 'out', IN_OUT_BASE_COLOR)
    graph.connect('intensity', 'out', IN_OUT_OPACITY)
    # (the particles set "additive" on every material: with this node it only changes the alpha, which the blend doesn't use)
    graph.connect('additive', 'out', IN_OUT_ADDITIVE)
    return graph

for name, weapon, srgb in (('particle_brighten', False, False), ('particle_weapon_brighten', True, False),
                           ('particle_brighten_srgb', False, True), ('particle_weapon_brighten_srgb', True, True)):
    open('%s/fx_%s_graph.material' % (FX, name), 'w', newline='\n').write(brighten_graph(weapon, srgb).text())
    print('wrote fx_%s_graph.material' % name)

# ---------------------------------------------------------------- the Redeemer blast's spheres
# RedeemerExplosion's mesh emitters keep UseMeshBlendMode, so UT draws them with their meshes' own materials, not their Texture. Both
# spheres are ExplosionSphere, whose material is IonSphereFinal (EpicParticles), FB_Brighten of the Shader IonSphere, whose diffuse, opacity and self illumination are the Combiner Combiner4
# (CO_AlphaBlend_With_Mask with no mask: the second layer over the first by the first's alpha) of two layers of the texture IonBurn,
# which is 256 texels square (units/ut/fx/ion_burn, make_weapon_fx.py):
#   the first, TexPanner5 (along U, half the texture a second) of TexScaler1 (UScale 0.5, VScale 1.5, V moved by 48 texels)
#   the second, TexScaler2 (VScale 2, moved by 64 texels) of TexPanner6 (along U, a texture a second the other way) of TexOscillator0
#   (along V, a tenth of the texture each way, once a second)
# A modifier changes the coordinates before the material inside it reads them (the renderer multiplies their matrices from the outside
# in, D3DDrv.dll decompiled). The particle sets the tint (its colour) and the
# intensity (its fade).
IN_SIN = '0505200e-439a-476b-b6a6-d643cf80e20b'
ion = Graph()
common(ion, BRIGHTEN)

def vector2(graph, name, value):
    graph.add(name, 'core/shader_nodes/constant_vector2')
    graph.constant(name, IN_CONSTANT_VECTOR3, value)

def scaled(graph, name, uv, scale, offset):
    # (uv divided by scale, plus offset, as UE2's TexScaler does: its matrix has 1 / UScale and 1 / VScale (Engine.dll, decompiled), so
    # a scale of 2 draws the texture twice as big)
    vector2(graph, name + '_scale', [1 / s for s in scale])
    multiply(graph, name + '_times', uv, name + '_scale')
    vector2(graph, name + '_offset', offset)
    graph.add(name, 'core/shader_nodes/add')
    graph.connect(name + '_times', name, IN_ADD_A)
    graph.connect(name + '_offset', name, IN_ADD_B)

def panned_from(graph, name, uv, speed_u, speed_v):
    graph.add(name, 'core/shader_nodes/panner')
    graph.connect(uv, name, IN_PAN_UV)
    graph.connect('time', name, IN_PAN_TIME)
    graph.constant(name, IN_PAN_SPEED_U, speed_u)
    graph.constant(name, IN_PAN_SPEED_V, speed_v)

def burn(graph, name, uv):
    graph.add(name, 'core/shader_nodes/sample_texture', LINEAR_SAMPLE_OPTIONS, samplers=sampler('burn_map'), title='burn_map')
    graph.connect(uv, name, IN_SAMPLE_UV)

# The first layer
panned_from(ion, 'pan_first', 'uv', 0.5, 0)
scaled(ion, 'first_uv', 'pan_first', [0.5, 1.5], [0, 48 / 256])
burn(ion, 'first', 'first_uv')
# The second layer: the oscillation is a tenth of the texture along V times the sine of a turn a second
scaled(ion, 'scale_second', 'uv', [1, 2], [0, 64 / 256])
panned_from(ion, 'pan_second', 'scale_second', -1, 0)
ion.add('turns', 'core/shader_nodes/mul')
ion.connect('time', 'turns', IN_MUL_A)
ion.constant('turns', IN_MUL_B, 2 * math.pi)
ion.add('sine', 'core/shader_nodes/sin')
ion.connect('turns', 'sine', IN_SIN)
vector2(ion, 'swing', [0, 0.1])
multiply(ion, 'sway', 'swing', 'sine')
ion.add('second_uv', 'core/shader_nodes/add')
ion.connect('pan_second', 'second_uv', IN_ADD_A)
ion.connect('sway', 'second_uv', IN_ADD_B)
burn(ion, 'second', 'second_uv')
# The second over the first by the first's alpha, tinted, and drawn as FB_Brighten draws
ion.add('mix', 'core/shader_nodes/lerp')
ion.connect('second', 'mix', IN_LERP_A, 'rgb')
ion.connect('first', 'mix', IN_LERP_B, 'rgb')
ion.connect('first', 'mix', IN_LERP_W, 'a')
multiply(ion, 'color', 'mix', 'tint')
ion.connect('color', 'out', IN_OUT_BASE_COLOR)
ion.connect('intensity', 'out', IN_OUT_OPACITY)
write('ion_sphere', ion, {'burn_map': 'ion_burn'})

# ---------------------------------------------------------------- the Redeemer blast's ring
# The ring is ExplosionRing, whose material is FireFinal (EpicParticles): FB_Brighten of the Shader FlameRingShader, whose self
# illumination is the Combiner Combiner3 (CO_AlphaBlend_With_Mask: the first layer over the second by the alpha of Grad_Falloff, which
# fades from the top of the texture to its bottom) of two layers of FlameGradient, which is 512 texels square (units/ut/fx/flame_gradient
# and grad_falloff, make_weapon_fx.py):
#   the first, TexPanner2 (up V, a quarter of the texture a second) of TexScaler5 (UScale 0.5)
#   the second, TexPanner3 (up V, 0.4 of the texture a second) of TexScaler6 (UScale 0.5, moved by 128 texels)
# The shader's opacity is Grad_Falloff too, which fades the colour to nothing at the mesh's inner edge (v 1), which is jagged.
ring = Graph()
common(ring, BRIGHTEN)

def sample(graph, name, slot, uv):
    graph.add(name, 'core/shader_nodes/sample_texture', LINEAR_SAMPLE_OPTIONS, samplers=sampler(slot), title=slot)
    graph.connect(uv, name, IN_SAMPLE_UV)

panned_from(ring, 'pan_first', 'uv', 0, -0.25)
scaled(ring, 'first_uv', 'pan_first', [0.5, 1], [0, 0])
sample(ring, 'first', 'flame_map', 'first_uv')
panned_from(ring, 'pan_second', 'uv', 0, -0.4)
scaled(ring, 'second_uv', 'pan_second', [0.5, 1], [128 / 512, 0])
sample(ring, 'second', 'flame_map', 'second_uv')
sample(ring, 'falloff', 'falloff_map', 'uv')
ring.add('mix', 'core/shader_nodes/lerp')
ring.connect('second', 'mix', IN_LERP_A, 'rgb')
ring.connect('first', 'mix', IN_LERP_B, 'rgb')
ring.connect('falloff', 'mix', IN_LERP_W, 'a')
multiply(ring, 'faded', 'mix', 'falloff', None, 'a')
multiply(ring, 'color', 'faded', 'tint')
ring.connect('color', 'out', IN_OUT_BASE_COLOR)
ring.connect('intensity', 'out', IN_OUT_OPACITY)
write('flame_ring', ring, {'flame_map': 'flame_gradient', 'falloff_map': 'grad_falloff'})

# ---------------------------------------------------------------- the Berserk combo's rings
# OffensiveEffect's skin RedBoltFB (XEffectMat): FB_Brighten of the TexPanner RedBoltPanner (PanDirection yaw 0, PanRate 1: along U, a texture a
# second) of the texture redbolt (units/ut/fx/red_bolt, make_weapon_fx.py), on the mesh TeleRing (units/ut/fx/tele_ring, make_fx_meshes.py).
# The particle sets the tint (its colour) and the intensity (its fade).
berserk = Graph()
common(berserk, BRIGHTEN)
panned(berserk, 'pan', 1, 0)
sample(berserk, 'bolts', 'bolts_map', 'pan')
multiply(berserk, 'color', 'bolts', 'tint', 'rgb')
berserk.connect('color', 'out', IN_OUT_BASE_COLOR)
berserk.connect('intensity', 'out', IN_OUT_OPACITY)
write('berserk_ring', berserk, {'bolts_map': 'red_bolt'})

# ---------------------------------------------------------------- the Invisible combo
# What UT draws a pawn and its weapons with while it is invisible (xPawn.SetInvisibility, Weapon's OverlayMaterial): InvisMaterial, the
# FinalBlend InvisOverlayFB (XEffectMat): FB_Brighten of the TexPanner InvisPanner (PanDirection yaw 8000, PanRate 0.25) of the
# TexScaler TexScaler0 (no change) of invis_overlay (units/ut/fx/invis_overlay, make_weapon_fx.py). It writes depth and is one sided.
# It goes on every mesh of the character, so it pans with the game's time, not with a particle's age. fx_invisible draws with the
# camera's field of view, and fx_weapon_invisible with the first person weapons'.
INVIS_PAN = 8000 / 65536 * 2 * math.pi

def invisible_graph(weapon):
    graph = Graph()
    # (OUT_OPTIONS without DOUBLE_SIDED and DISABLE_DEPTH_WRITE)
    graph.add('out', BRIGHTEN, (OUT_OPTIONS[0], OUT_OPTIONS[2]) + ((CUSTOM_FOV,) if weapon else ()))
    graph.add('uv', 'core/shader_nodes/texture_coordinate0')
    graph.add('time', 'core/shader_nodes/current_time')
    # (unused: every graph here has the variables of the particles)
    graph.add('age', 'core/shader_nodes/material_variable', export=float_variable('age', 'Age', 0), title='Age')
    graph.add('intensity', 'core/shader_nodes/material_variable', export=float_variable('intensity', 'Intensity', 1), title='Intensity')
    graph.add('tint', 'core/shader_nodes/material_variable', export=color_variable('tint', 'Tint'), title='Tint')
    graph.add('additive', 'core/shader_nodes/material_variable', export=float_variable('additive', 'Additive', 0), title='Additive')
    graph.connect('additive', 'out', IN_OUT_ADDITIVE)
    panned(graph, 'pan', 0.25 * math.cos(INVIS_PAN), 0.25 * math.sin(INVIS_PAN))
    sample(graph, 'overlay', 'overlay_map', 'pan')
    multiply(graph, 'color', 'overlay', 'tint', 'rgb')
    graph.connect('color', 'out', IN_OUT_BASE_COLOR)
    graph.connect('intensity', 'out', IN_OUT_OPACITY)
    return graph

write('invisible', invisible_graph(False), {'overlay_map': 'invis_overlay'})
write('weapon_invisible', invisible_graph(True), {'overlay_map': 'invis_overlay'})

# ---------------------------------------------------------------- the Link Gun's beam
# LinkBeamEffect's and LinkBeamChild's skins LinkBeamGreenFB, LinkBeamYellowFB and LinkBeamBlueFB (XEffectMat): FB_Brighten of the TexPanners
# LinkBeamGreenPanner, LinkBeamYellowPanner and LinkBeamBluePanner (PanDirection yaw 16384: along V, which is along the beam; PanRate -2, and 2
# for the blue one) of link_beam_green, link_beam_yellow and link_beam_blue (make_fx_assets.py). The texture is read as it is: the
# particles are drawn after tone mapping, onto the screen's colours, as UT draws, and read as srgb its green sides and grey middle were
# nearly gone (see make_lightning_assets.py). The materials are fx_link_beam_panned_<color>. A beam is drawn as a quad for each stretch,
# made at different times, so it pans with the game's time, not with a particle's age, and the stretches line up.
# The texture times the beam's colour (its tint, mColorRange) is doubled and clamped at 1, as Direct3D's MODULATE2X does. The texture is
# dim (its middle is 101 of 255), and in a picture of UT2004 the beam's middle is white over a floor of (175, 105, 80): FB_Brighten
# reaches that only with about twice the texture times its colour of 240.
IN_SATURATE = '6cebb808-14e4-45d6-9816-3838b1f6f4c7'

def link_beam_graph(pan_v):
    graph = Graph()
    graph.add('out', BRIGHTEN, OUT_OPTIONS)
    graph.add('uv', 'core/shader_nodes/texture_coordinate0')
    graph.add('time', 'core/shader_nodes/current_time')
    # (unused: every graph here has the variables of the particles)
    graph.add('age', 'core/shader_nodes/material_variable', export=float_variable('age', 'Age', 0), title='Age')
    graph.add('intensity', 'core/shader_nodes/material_variable', export=float_variable('intensity', 'Intensity', 1), title='Intensity')
    graph.add('tint', 'core/shader_nodes/material_variable', export=color_variable('tint', 'Tint'), title='Tint')
    graph.add('additive', 'core/shader_nodes/material_variable', export=float_variable('additive', 'Additive', 0), title='Additive')
    graph.connect('additive', 'out', IN_OUT_ADDITIVE)
    panned(graph, 'pan', 0, pan_v)
    sample(graph, 'beam', 'beam_map', 'pan')
    multiply(graph, 'tinted', 'beam', 'tint', 'rgb')
    graph.add('doubled', 'core/shader_nodes/mul')
    graph.connect('tinted', 'doubled', IN_MUL_A)
    graph.constant('doubled', IN_MUL_B, 2)
    graph.add('color', 'core/shader_nodes/saturate')
    graph.connect('doubled', 'color', IN_SATURATE)
    graph.connect('color', 'out', IN_OUT_BASE_COLOR)
    graph.connect('intensity', 'out', IN_OUT_OPACITY)
    return graph

# (the pan's sign is the way that moves the texture along the beam as UT's does: the other sign scrolled it backwards)
for color, pan_v in (('green', 2), ('yellow', 2), ('blue', -2)):
    write('link_beam_panned_' + color, link_beam_graph(pan_v), {'beam_map': 'link_beam_' + color})

# ---------------------------------------------------------------- the Link Gun's model
# UT2004's first person Link Gun (NewWeapons2004.FatLinkGun) has three materials (UT2004Weapons, group Shaders; read from a UModel export with
# -groups, as other groups have objects of the same names). The model here has them as m_0, m_1 and m_2 (convert_weapon.py), and this
# makes the first two, run after convert_weapon.py. LinkGun.UpdateLinkColor swaps them for the gold ones with links, and the team's
# while it links an ally (the heroes are one team, as UT's blue).
#   m_0  LinkGunShader: the body (FatLinkGunTex0), lit, with SelfIllumination TexPanner1 (PanDirection yaw 2048, PanRate -1) of TexScaler1
#        (UScale 4, VScale 1) of LinkPowerGreen, masked by LinkPowerGreen's alpha (SelfIlluminationMask), which is the green eye on its side.
#        Gold: TexPanner5 (yaw 0, -1) of TexScaler4 (5, 2, VOffset -32) of LinkPowerYellow. Blue: as green, of LinkPowerBlue.
#   m_1  PowerPulseShader: the tubes, all self lit (Diffuse and SelfIllumination are Combiner12): CO_Add of TexPanner3 (yaw 4096, -0.2)
#        of TexScaler2 (2, 2) of LinkPowerGreen, and TexScaler3 (2, 2, offset 32, 32) of TexRotator2 (constantly turning, yaw 1024 a
#        second, about 64, 64) of TexPanner4 (yaw -4096, -0.2) of LinkPowerGreen. Blue (Combiner15): the same of LinkPowerBlue. Gold
#        (Combiner17): CO_Add of TexScaler7 (3, 3) of TexRotator3 (yaw 5120 a second, about 24, 24) of TexOscillator2 (stretching U and V
#        0.2 times a second by 0.5, V half a cycle later, about 48, 48) of LinkPowerYellow, and TexPanner7 (yaw 0, -1) of TexScaler8
#        (2, 2) of LinkPowerYellow.
#   m_2  LinkGlassShader: the glass, a reflection of a cube map, left as convert_weapon.py makes it.
#   m_3  the body again (convert_weapon.py's overlays): m_0's glow, added over it. m_0 itself is the lit colour less the glow's mask.
# The coordinates go through the outermost modifier first, then in to the texture: D3DDrv.dll (decompiled) multiplies the modifiers'
# matrices from the outside in, and a texture's coordinates are a row times the matrix. A scaler divides by its scale (see scaled).
# Offsets are texels of the 128 by 128 power textures. A panner moves along its yaw (65536 to the turn) at its rate in textures a
# second; a rotator turns at its yaw a second, the other way from the SDK's rotator node. The glow is in the emissive layer, which is HDR: dimmed as the Bio Rifle's goo is, so that it shows as
# the texture. The textures are units/ut/fx/link_power_<color> (make_weapon_fx.py), alpha and all.
LINK_GLOW = 0.04
IN_ROT_UV, IN_ROT_TIME, IN_ROT_PIVOT, IN_ROT_SPEED = ('96650519-54EC-47A2-B34E-3B1989F56BB3', '178ABCED-40BA-40B1-BAA4-FB5F9732353B',
                                                      'ffac2478-636b-4b9b-95b9-cd504781e2c2', '399aba19-4e60-4287-b1d3-ee2acb8fd406')
IN_CONSTRUCT_X, IN_CONSTRUCT_Y = '8231a2cb-b751-4ecd-94eb-3e6d048ba173', '46536067-b418-47a5-bc6b-234972e963e9'
POWER_SIZE = 128.0

def link_pan(graph, name, uv, yaw, rate):
    angle = yaw / 65536 * 2 * math.pi
    panned_from(graph, name, uv, math.cos(angle) * rate, math.sin(angle) * rate)

def link_scale(graph, name, uv, u_scale, v_scale, u_offset=0, v_offset=0):
    scaled(graph, name, uv, [u_scale, v_scale], [u_offset / POWER_SIZE, v_offset / POWER_SIZE])

def link_rotate(graph, name, uv, yaw_rate, u_center, v_center):
    vector2(graph, name + '_pivot', [u_center / POWER_SIZE, v_center / POWER_SIZE])
    graph.add(name, 'core/shader_nodes/rotator')
    graph.connect(uv, name, IN_ROT_UV)
    graph.connect('time', name, IN_ROT_TIME)
    graph.connect(name + '_pivot', name, IN_ROT_PIVOT)
    graph.constant(name, IN_ROT_SPEED, -yaw_rate / 65536 * 2 * math.pi)

def link_stretch(graph, name, uv, rate, amplitude, phases, u_center, v_center):
    # (OT_Stretch: each axis is scaled by 1 + amplitude * sin(rate turns a second, from its phase), about the center)
    for axis, phase in zip(('u', 'v'), phases):
        graph.add(name + '_angle_' + axis, 'core/shader_nodes/mul')
        graph.connect('time', name + '_angle_' + axis, IN_MUL_A)
        graph.constant(name + '_angle_' + axis, IN_MUL_B, 2 * math.pi * rate)
        graph.add(name + '_phase_' + axis, 'core/shader_nodes/add')
        graph.connect(name + '_angle_' + axis, name + '_phase_' + axis, IN_ADD_A)
        graph.constant(name + '_phase_' + axis, IN_ADD_B, 2 * math.pi * phase)
        graph.add(name + '_sin_' + axis, 'core/shader_nodes/sin')
        graph.connect(name + '_phase_' + axis, name + '_sin_' + axis, IN_SIN)
        graph.add(name + '_swing_' + axis, 'core/shader_nodes/mul')
        graph.connect(name + '_sin_' + axis, name + '_swing_' + axis, IN_MUL_A)
        graph.constant(name + '_swing_' + axis, IN_MUL_B, amplitude)
        graph.add(name + '_scale_' + axis, 'core/shader_nodes/add')
        graph.connect(name + '_swing_' + axis, name + '_scale_' + axis, IN_ADD_A)
        graph.constant(name + '_scale_' + axis, IN_ADD_B, 1)
    graph.add(name + '_scale', 'core/shader_nodes/construct_vector2')
    graph.connect(name + '_scale_u', name + '_scale', IN_CONSTRUCT_X)
    graph.connect(name + '_scale_v', name + '_scale', IN_CONSTRUCT_Y)
    vector2(graph, name + '_center', [u_center / POWER_SIZE, v_center / POWER_SIZE])
    graph.add(name + '_centered', 'core/shader_nodes/subtract')
    graph.connect(uv, name + '_centered', IN_SUBTRACT_A)
    graph.connect(name + '_center', name + '_centered', IN_SUBTRACT_B)
    multiply(graph, name + '_stretched', name + '_centered', name + '_scale')
    graph.add(name, 'core/shader_nodes/add')
    graph.connect(name + '_stretched', name, IN_ADD_A)
    graph.connect(name + '_center', name, IN_ADD_B)

# The glow of a color: the modifiers of the coordinates from the outside in, and the textures they read, into the node 'glow'. The
# body's eye reads one, as it is; the tubes add two.
def link_body_glow(graph, color):
    if color == 'yellow':
        link_pan(graph, 'body_pan', 'uv', 0, -1)
        link_scale(graph, 'body_uv', 'body_pan', 5, 2, 0, -32)
    else:
        link_pan(graph, 'body_pan', 'uv', 2048, -1)
        link_scale(graph, 'body_uv', 'body_pan', 4, 1)
    sample(graph, 'glow', 'power_map', 'body_uv')

def link_glow(graph, color):
    if color == 'yellow':
        link_scale(graph, 'first_scale', 'uv', 3, 3)
        link_rotate(graph, 'first_turn', 'first_scale', 5120, 24, 24)
        link_stretch(graph, 'first_uv', 'first_turn', 0.2, 0.5, (0, 0.5), 48, 48)
        link_pan(graph, 'second_pan', 'uv', 0, -1)
        link_scale(graph, 'second_uv', 'second_pan', 2, 2)
    else:
        link_pan(graph, 'first_pan', 'uv', 4096, -0.2)
        link_scale(graph, 'first_uv', 'first_pan', 2, 2)
        link_scale(graph, 'second_scale', 'uv', 2, 2, 32, 32)
        link_rotate(graph, 'second_turn', 'second_scale', 1024, 64, 64)
        link_pan(graph, 'second_uv', 'second_turn', -4096, -0.2)
    texture(graph, 'first', 'power_map', 'first_uv')
    texture(graph, 'second', 'power_map', 'second_uv')
    graph.add('glow', 'core/shader_nodes/add')
    graph.connect('first', 'glow', IN_ADD_A, 'rgb')
    graph.connect('second', 'glow', IN_ADD_B, 'rgb')
    return 'glow'

def link_power_graph(color):
    graph = Graph()
    graph.no_variables = True
    graph.add('out', UNLIT, (LAYER_EMISSIVE, CUSTOM_FOV))
    graph.add('uv', 'core/shader_nodes/texture_coordinate0')
    graph.add('time', 'core/shader_nodes/current_time')
    glow = link_glow(graph, color)
    graph.add('clamped', 'core/shader_nodes/saturate')
    graph.connect(glow, 'clamped', IN_SATURATE)
    graph.add('dim', 'core/shader_nodes/mul')
    graph.connect('clamped', 'dim', IN_MUL_A)
    graph.constant('dim', IN_MUL_B, LINK_GLOW)
    graph.connect('dim', 'out', IN_OUT_BASE_COLOR)
    return graph

def link_body_graph(color, options=STANDARD_OPTIONS):
    # (the body lit, but for the glow: its colour times 1 - mask)
    graph = Graph()
    graph.no_variables = True
    graph.add('out', 'core/stingray_renderer/output_nodes/standard_base', options)
    graph.add('uv', 'core/shader_nodes/texture_coordinate0')
    texture(graph, 'body', 'body_map', 'uv')
    texture(graph, 'mask', 'power_map', 'uv')
    graph.add('unmasked', 'core/shader_nodes/subtract')
    graph.constant('unmasked', IN_SUBTRACT_A, 1)
    graph.connect('mask', 'unmasked', IN_SUBTRACT_B, 'a')
    multiply(graph, 'lit', 'body', 'unmasked', 'rgb')
    graph.connect('lit', 'out', IN_OUT_BASE_COLOR)
    graph.constant('out', IN_STANDARD_ROUGHNESS, 0.9)
    graph.constant('out', IN_STANDARD_METALLIC, 0)
    return graph

def link_eye_graph(color, world=False):
    # (the glow times the mask, added over the body: the body's faces again as m_3, convert_weapon.py's overlays. The lit node's
    # emissive didn't show on the weapon: it draws where the depth is the same as the gbuffer's, which the first person layer's isn't.
    # This is drawn as the effects drawn with the weapon are, after tone mapping, with the texture read as it is. world: for the third
    # person mesh, without the weapon's field of view.)
    graph = Graph()
    graph.no_variables = True
    graph.add('out', UNLIT, (OUT_OPTIONS[0], OUT_OPTIONS[2], OUT_OPTIONS[3]) + (() if world else (CUSTOM_FOV,)))
    graph.add('uv', 'core/shader_nodes/texture_coordinate0')
    graph.add('time', 'core/shader_nodes/current_time')
    sample(graph, 'mask', 'power_map', 'uv')
    link_body_glow(graph, color)
    multiply(graph, 'masked_glow', 'glow', 'mask', 'rgb', 'a')
    graph.connect('masked_glow', 'out', IN_OUT_BASE_COLOR)
    graph.constant('out', IN_OUT_OPACITY, 1)
    graph.constant('out', IN_OUT_ADDITIVE, 1)
    return graph

# The options of a third person weapon's material (make_base_materials.py's world_standard): STANDARD_OPTIONS without the weapon's field
# of view (HAS_FOV), which drew the mesh as the first person weapon is drawn, out of place in the world, and with jitter transparency, so
# that it fades out near the camera as the characters do
HAS_FOV = '901b44ce-d128-498a-9912-32cd9635c556'
JITTER_TRANSPARENCY = '580cc6eb-3591-4c71-aa50-528af18ba160'
WORLD_STANDARD_OPTIONS = tuple(option for option in STANDARD_OPTIONS if option != HAS_FOV) + (JITTER_TRANSPARENCY,)

# The third person mesh, NewLinkGun_3rd, whose skin is LinkGunShader too: m_0 the body, lit but for the glow, and m_1 the eye's glow,
# drawn over it as the first person model's is (convert_static.py's overlays). As the emissive of the lit material the glow was too dim
# to see in the world. UT's attachment keeps it green whatever the links.
for part, slot, make in (('body', 'm0', lambda color: link_body_graph(color, WORLD_STANDARD_OPTIONS)),
                         ('eye', 'm1', lambda color: link_eye_graph(color, world=True))):
    graph = make('green')
    open('%s/fx_link_gun_world_%s_green_graph.material' % (FX, part), 'w', newline='\n').write(graph.text())
    bound = '\tpower_map = "units/ut/fx/link_power_green"\n'
    if part == 'body':
        bound += '\tbody_map = "units/ut/link/link_gun_fatlinkguntex0"\n'
    open('%s/units/ut/link/link_gun_world_%s.material' % (REPO, slot), 'w', newline='\n').write(
        'material_contexts = {\n\tsurface_material = ""\n}\nparent_material = "units/ut/fx/fx_link_gun_world_%s_green_graph"\ntextures = {\n%s}\n'
        'variables = {\n}\n' % (part, bound))
    print('wrote fx_link_gun_world_%s_green_graph.material and link_gun_world_%s.material, %d nodes' % (part, slot, len(graph.nodes)))

for color in ('green', 'yellow', 'blue'):
    for part, slot, make in (('body', 'm0', link_body_graph), ('power', 'm1', link_power_graph), ('eye', 'm3', link_eye_graph)):
        name = 'link_gun_%s_%s' % (part, color)
        graph = make(color)
        open('%s/fx_%s_graph.material' % (FX, name), 'w', newline='\n').write(graph.text())
        bound = '\tpower_map = "units/ut/fx/link_power_%s"\n' % color
        if part == 'body':
            bound += '\tbody_map = "units/ut/link/link_gun_fatlinkguntex0"\n'
        # (green is the model's own material, link_gun_m0, m1 and m3; the skin swaps in the others, link_gun_m0_yellow and so on)
        material = 'link_gun_%s' % slot if color == 'green' else 'link_gun_%s_%s' % (slot, color)
        open('%s/units/ut/link/%s.material' % (REPO, material), 'w', newline='\n').write(
            'material_contexts = {\n\tsurface_material = ""\n}\nparent_material = "units/ut/fx/fx_%s_graph"\ntextures = {\n%s}\nvariables = {\n}\n'
            % (name, bound))
        print('wrote fx_%s_graph.material and %s.material, %d nodes' % (name, material, len(graph.nodes)))
