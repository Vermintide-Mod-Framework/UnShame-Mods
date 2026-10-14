import os, sys

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
            text += '\t\t\t\t%s\n' % (repr(float(value)) if not float(value).is_integer() else '%d' % int(value))
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

def common(graph):
    graph.add('out', 'core/stingray_renderer/output_nodes/unlit_base', OUT_OPTIONS)
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
# (the effect blends it by the alpha of its texture).
goop = Graph()
common(goop)
panned(goop, 'pan', 0.07, 0.17)
texture(goop, 'goop', 'goop_map', 'pan')
multiply(goop, 'color', 'goop', 'tint', 'rgb')
# (it is see through, as the texture's alpha says, and as much as intensity says of that)
multiply(goop, 'opacity', 'goop', 'intensity', 'a')
goop.connect('color', 'out', IN_OUT_BASE_COLOR)
goop.connect('opacity', 'out', IN_OUT_OPACITY)
write('goop', goop, {'goop_map': 'bio_goop'})

# ---------------------------------------------------------------- the splat decal
# BioDecal's xbiosplat, drawn by the decal shader onto the surfaces under the box of the unit decal_bio: the green of bio_splat, cut out and
# blended by bio_splat_mask (a gray, see make_fx_assets.py).
IN_DECAL_BASE_COLOR_OPACITY = 'ad5e052f-d316-4a0f-8b79-53c38204d61b'
IN_DECAL_MASK, IN_DECAL_MASK_THRESHOLD = '34259752-b962-4b65-92c3-903a57338519', '7a9306c6-95ae-4cdb-9fef-0eedacce4e83'
decal = Graph()
decal.no_variables = True
decal.add('out', 'core/stingray_renderer/output_nodes/decal_base')
decal.add('uv', 'core/shader_nodes/decal_uv')
texture(decal, 'splat', 'splat_map', 'uv')
texture(decal, 'shape', 'shape_map', 'uv')
decal.connect('splat', 'out', IN_OUT_BASE_COLOR, 'rgb')
decal.connect('shape', 'out', IN_DECAL_BASE_COLOR_OPACITY, 'r')
decal.connect('shape', 'out', IN_DECAL_MASK, 'r')
decal.constant('out', IN_DECAL_MASK_THRESHOLD, 0.05)
write('decal_bio', decal, {'splat_map': 'bio_splat', 'shape_map': 'bio_splat_mask'})
