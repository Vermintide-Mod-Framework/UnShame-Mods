import os, sys

# Makes the unit of the Bio Rifle's splat, a projected decal like the game's own (units/decals/projection_blood_01). The game's decal
# manager (DecalManager.add_projection_decal) places the unit, scales it by the extents it is given, and draws it onto the surfaces it
# reaches, so it follows walls, corners and floors. The unit is a box, 1 by 1 by 1, with the material fx_decal_bio (make_combo_materials.py), whose
# shader draws the box as a decal. Each triangle is made twice, once for each side, because the decal shader draws only one of them.
# The y axis of the box is the way the decal faces (the decal shader compares it with the normal of the surface), so the box is deep along y.
# Usage: make_decal_unit.py

sys.path.insert(0, os.path.dirname(__file__))
import make_fx_meshes as fx

corners = [(x, y, z) for z in (-0.5, 0.5) for y in (-0.5, 0.5) for x in (-0.5, 0.5)]
faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
indices = []

for a, b, c, d in faces:
    indices += [a, b, c, a, c, d, a, c, b, a, d, c]

uvs = [(0, 0), (1, 0), (1, 1), (0, 1)]
uv_index = []

for _ in faces:
    uv_index += [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]

fx.write_unit('decal_bio', [fx.geometry('g_box', corners, indices, uvs, uv_index)], {'g_box': 'g_box'})
path = fx.FX + '/decal_bio.unit'
text = open(path).read().replace('units/ut/fx/fx_shock_sparkle', 'units/ut/fx/fx_decal_bio')

open(path, 'w', newline='\n').write(text)
print('decal_bio', len(indices) // 3, 'triangles')
