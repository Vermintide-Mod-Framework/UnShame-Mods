import os, sys

# Makes the unit of the Bio Rifle's splat, a projected decal like the game's own (units/decals/projection_blood_01). The game's decal
# manager (DecalManager.add_projection_decal) places the unit, scales it by the extents it is given, and draws it onto the surfaces it
# reaches, so it follows walls, corners and floors. The unit is a box, 1 by 1 by 1, with the material fx_decal_bio (make_combo_materials.py), whose
# shader draws the box as a decal. Each triangle is made twice, once for each side, because the decal shader draws only one of them.
# The engine places the unit with its z axis along the surface normal and its extents as width, length and depth (x, y, z), but the decal
# shader draws the texture on the x and z axes of the box and projects along y. So the box is a node turned a quarter about x: its y axis is the
# z of the unit.
# Usage: make_decal_unit.py

sys.path.insert(0, os.path.dirname(__file__))
import make_fx_meshes as fx

# (a quarter turn about x: the x axis stays, the y axis is the unit's z, and the z axis is the unit's -y)
TURNED = '1 0 0 0 0 0 1 0 0 -1 0 0 0 0 0 1'

corners = [(x, y, z) for z in (-0.5, 0.5) for y in (-0.5, 0.5) for x in (-0.5, 0.5)]
faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
indices = []

for a, b, c, d in faces:
    indices += [a, b, c, a, c, d, a, c, b, a, d, c]

uvs = [(0, 0), (1, 0), (1, 1), (0, 1)]
uv_index = []

for _ in faces:
    uv_index += [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]

fx.write_unit('decal_bio', [fx.geometry('g_box', corners, indices, uvs, uv_index)], {'g_box': 'g_box'}, TURNED, 'bounding_volume')
path = fx.FX + '/decal_bio.unit'
text = open(path).read().replace('units/ut/fx/fx_shock_sparkle', 'units/ut/fx/fx_decal_bio')

open(path, 'w', newline='\n').write(text)
print('decal_bio', len(indices) // 3, 'triangles')
