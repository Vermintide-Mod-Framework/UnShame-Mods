import os, sys, zlib, struct

# Makes the unit of the Bio Rifle's goop, as UT2004 has it: XWeapons.GoopMesh (a vertex mesh of UT's first format, .3d), with every frame of the
# animations that the glob plays, each frame a mesh of its own in the unit (units/ut/fx/goop). The skin shows one of them at a time.
#   Flying   frames 3 to 13   the glob in the air
#   Hit      frames 20 to 37  the glob landing on a surface
#   Drip     frames 40 to 78  the glob hanging from a ceiling
#   Slide    frames 83 to 121 the glob running down a wall
# (the sequences are in XWeapons_rc/BioRifle_rc.uc). The mesh is lit by itself and shows the material fx_goop (make_combo_materials.py).
# The mesh is made in meters, a UT unit being 0.02 m, with the DrawScale of the glob (1.2) in it. A raw vertex is scaled by the mesh map (0.04,
# 0.04, 0.08). The z axis of the mesh is the way a glob that has landed faces away from its surface.
# Each triangle is made twice, once for each side, because the glob is drawn on both (GoopFB is two sided).
# Usage: make_goop_mesh.py <umodel export dir of XWeapons_rc.u, the folder that has VertMesh>
#        (umodel -game=ut2 -export -out=<dir> XWeapons_rc.u GoopMesh)

sys.path.insert(0, os.path.dirname(__file__))
import make_fx_meshes as fx

EXPORT = sys.argv[1]
DRAW_SCALE = 1.2
MESH_MAP = (0.04, 0.04, 0.08)
SEQUENCES = {'flying': (3, 11), 'hit': (20, 18), 'drip': (40, 39), 'slide': (83, 39)}

frames, triangles, polygon_uvs, frame = fx.vertex_mesh('GoopMesh', EXPORT)
position_index = [v for t in triangles for v in t]
uvs = [(polygon_uvs[i][2 * k], 1.0 - polygon_uvs[i][2 * k + 1]) for i in range(len(triangles)) for k in range(3)]
uv_index = list(range(len(uvs)))
# (both sides: the corners of each triangle in the other order, with the same uvs)
back_index = [position_index[i + k] for i in range(0, len(position_index), 3) for k in (0, 2, 1)]
back_uv_index = [uv_index[i + k] for i in range(0, len(uv_index), 3) for k in (0, 2, 1)]
both_index = position_index + back_index
both_uv_index = uv_index + back_uv_index

geometries, nodes = [], {}

for name, (start, count) in SEQUENCES.items():
    for number in range(start, start + count):
        points = [fx.to_game((x * MESH_MAP[0] * DRAW_SCALE, y * MESH_MAP[1] * DRAW_SCALE, z * MESH_MAP[2] * DRAW_SCALE)) for x, y, z in frame(number)]
        points = [(x * fx.UNIT, y * fx.UNIT, z * fx.UNIT) for x, y, z in points]
        mesh = 'f%d' % number

        geometries.append(fx.geometry('g_' + mesh, points, both_index, uvs, both_uv_index))
        nodes['g_' + mesh] = 'g_' + mesh

fx.write_unit('goop', geometries, nodes)
print('goop', len(nodes), 'frames', len(triangles), 'triangles each')
