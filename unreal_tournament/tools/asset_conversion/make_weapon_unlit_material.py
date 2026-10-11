import os

# Makes the material that the weapons' models are drawn with: their color map as it is, lit by itself, times a brightness. UT2004 lights
# the weapon in the hand brightly in every level (and the textures have their shading in them); this game's lights are those of the level
# and leave the weapon dark in the shade, which an emissive map of the standard material did not change.
# Usage: make_weapon_unlit_material.py

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

def guid(n):
    return 'c0de0001-0000-4000-8000-%012d' % n

IN_SAMPLE_UV = '1ee9af1f-65f2-4739-ad28-5ea6a0e68fc3'
IN_MUL_A, IN_MUL_B = 'c5823c75-4ae5-4c71-b070-315fa4d03e8e', '242d1648-a626-445b-9534-bccec094112f'
IN_OUT_BASE_COLOR = 'aca690cb-6305-4a2f-bf3d-69183a493db3'
ADDRESS_WRAP, FILTER_LINEAR, SRGB = '5dd59b3d-1762-4a14-9930-7500230ef3db', 'f669a3a6-0376-4187-840e-80000e2939d5', 'fb3f709b-a54a-4e93-ac9f-e9fc76fb8bcd'

OUT, UV, TEX, BRIGHTNESS, MUL = [guid(i) for i in range(1, 6)]

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

brightness_variable = ('\t\t\t\tmaterial_variable = {\n\t\t\t\t\tdisplay_name = "Brightness"\n\t\t\t\t\tname = "brightness"\n\t\t\t\t\ttype = "float"\n'
                       '\t\t\t\t\tui = {\n\t\t\t\t\t\tmax = 10\n\t\t\t\t\t\tmin = 0\n\t\t\t\t\t\tstep = 0.001\n\t\t\t\t\t}\n\t\t\t\t\tvalue = 1\n\t\t\t\t}\n')
sampler = '\t\t\t\ttexture_map = {\n\t\t\t\t\tdisplay_name = "Color Map"\n\t\t\t\t\tslot_name = "color_map"\n\t\t\t\t}\n'

text = 'shader = {\n\tconnections = [\n'
text += connection(UV, TEX, IN_SAMPLE_UV)
text += connection(TEX, MUL, IN_MUL_A, 'rgb')
text += connection(BRIGHTNESS, MUL, IN_MUL_B)
text += connection(MUL, OUT, IN_OUT_BASE_COLOR)
text += '\t]\n\tconstants = [\n\t]\n\tgroups = [\n\t]\n\tnodes = [\n'
text += node(OUT, 'core/stingray_renderer/output_nodes/unlit_base', (900, 0))
text += node(UV, 'core/shader_nodes/texture_coordinate0', (0, 0))
text += node(TEX, 'core/shader_nodes/sample_texture', (300, 0), (ADDRESS_WRAP, FILTER_LINEAR, SRGB), samplers=sampler, title='Color Map')
text += node(BRIGHTNESS, 'core/shader_nodes/material_variable', (300, 200), export=brightness_variable, title='Brightness')
text += node(MUL, 'core/shader_nodes/mul', (600, 0))
text += '\t]\n\tversion = 3\n}\ntextures = {\n}\nvariables = {\n\tbrightness = {\n\t\ttype = "scalar"\n\t\tvalue = 1\n\t}\n}\n'
open(REPO + '/units/ut/weapon_unlit.material', 'w', newline='\n').write(text)
print('wrote units/ut/weapon_unlit.material')
