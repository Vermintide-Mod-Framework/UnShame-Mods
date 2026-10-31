import struct, zlib, os, sys
from formats import read_chunks as chunks

# Makes the units of the meshes of the effects, from the UModel export (export.py):
#   units/ut/fx/coil    ShockCoil: a prism that turns about the beam (static mesh, 30 long: ShockBeamCoil makes pieces of it along the beam)
#   units/ut/fx/sphere  Editor.TexPropSphere (a static mesh of 960 triangles, 128 units in radius), the mesh of ShockComboSphereDark
#   units/ut/fx/vortex  ShockVortexMesh (a vertex mesh of UT's first format, .3d), its first frame: a flat disc that faces the camera
#   units/ut/fx/flak_flash_mesh  XEffects.FlakMuzFlashMesh, the Flak Cannon's first person muzzle flash; its long axis is y, the way the
#                       barrel points
#   units/ut/fx/minigun_flash_mesh  XEffects.MinigunMuzFlash1stMesh, the Minigun's first person muzzle flash, and
#   units/ut/fx/minigun_flash_3rd_mesh  XEffects.MinigunFlashMesh, the mesh of the Rocket Launcher's third person flash (RocketMuzFlash3rd)
#   units/ut/fx/shell_casing_mesh  XEffects.ShellCasing, the shell of ShellSpewer
#   units/ut/fx/shield_mesh  WeaponStaticMesh.Shield, the Shield Gun's shield (ShieldEffect): a dish 3 units deep and 20 across, facing along x
#   units/ut/fx/explosion_ring, explosion_sphere  ParticleMeshes.ExplosionRing (a flat ring 512 units across) and ExplosionSphere (256
#                       across), the meshes of the Redeemer's blast
#   units/ut/fx/tele_ring  XEffects.TeleRing, the ring of the Berserk combo's OffensiveEffect
#   units/ut/fx/link_bolt_mesh  WeaponStaticMesh.LinkProjectile, the Link Gun's bolt: it lies along y, the way it flies, from 0.6
#                       to 26 units, and is 20 across
#   units/ut/fx/link_flash_mesh  XEffects.LinkMuzFlashMesh, the mesh of the Link Gun's flashes of a bolt (LinkMuzFlashProj1st and 3rd)
#   units/ut/fx/shock_flash_mesh  WeaponStaticMesh.ShockMuzFlash, the mesh of the Shock Rifle's first person flash of a beam
#                       (ShockBeamMuzFlash)
#   units/ut/fx/beam_strip  a strip of triangles whose corners the effects place, for the Link Gun's beam (see make_strip)
# They are made in meters, a UT unit being 0.02 m (as everything of the effects is), turned from UT's axes (x forward, y right, z up) to
# this game's (x right, y forward, z up), which makes the mesh the other way round: the long axis of the coil is y.
# One material slot, m_fx, as the quad of the particles has (units/ut/fx/quad): the effects set the material of the texture they want.
# Usage: make_fx_meshes.py <export dir>

EXPORT = sys.argv[1] if len(sys.argv) > 1 else ''
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FX = REPO + '/units/ut/fx'
XEFFECTS = EXPORT + '/XEffects'
UNIT = 0.02

def static_mesh(path):
    # (points, wedges: (point, u, v), triangles of wedges)
    psk = chunks(path)
    ps, pc, pb = psk['PNTS0000']
    points = [struct.unpack_from('<3f', pb, i * ps) for i in range(pc)]
    ws, wc, wb = psk['VTXW0000']
    wedges = []

    for i in range(wc):
        point = struct.unpack_from('<H', wb, i * ws)[0] if ws == 16 else struct.unpack_from('<I', wb, i * ws)[0]
        u, v = struct.unpack_from('<2f', wb, i * ws + 4)
        wedges.append((point, u, v))

    fs, fc, fb = psk['FACE0000']
    triangles = [struct.unpack_from('<3H', fb, i * fs) for i in range(fc)]

    return points, wedges, triangles

def vertex_mesh(name, export=XEFFECTS):
    # UT's first mesh format: <name>_d.3d has the polygons, <name>_a.3d the frames, a vertex of which is 11, 11 and 10 bits
    d = open('%s/VertMesh/%s_d.3d' % (export, name), 'rb').read()
    a = open('%s/VertMesh/%s_a.3d' % (export, name), 'rb').read()
    polygons, vertices = struct.unpack('<HH', d[:4])
    frames, frame_size = struct.unpack('<HH', a[:4])
    assert frame_size == vertices * 4

    triangles, uvs = [], []

    for i in range(polygons):
        o = 48 + i * 16
        triangles.append(struct.unpack_from('<3H', d, o))
        uvs.append([d[o + 8 + k] / 255.0 for k in range(6)])

    def frame(index):
        out = []

        for k in range(vertices):
            v = struct.unpack_from('<I', a, 4 + index * frame_size + k * 4)[0]
            x, y, z = v & 0x7ff, (v >> 11) & 0x7ff, (v >> 22) & 0x3ff

            if x >= 0x400:
                x -= 0x800

            if y >= 0x400:
                y -= 0x800

            if z >= 0x200:
                z -= 0x400

            out.append((x, y, z))

        return out

    return frames, triangles, uvs, frame

def fl(values):
    return ' '.join(repr(float(v)) if not float(v).is_integer() else str(int(v)) for v in values)

def il(values):
    return ' '.join(str(v) for v in values)

def stream(name, ctype, stride, values, size):
    return ('\t\t\t{\n\t\t\t\tchannels = [ {\n\t\t\t\t\t\tindex = 0\n\t\t\t\t\t\tname = "%s"\n\t\t\t\t\t\ttype = "%s"\n\t\t\t\t\t} ]\n'
            '\t\t\t\tdata = [ %s ]\n\t\t\t\tsize = %d\n\t\t\t\tstride = %d\n\t\t\t}') % (name, ctype, fl(values), size, stride)

def geometry(name, positions, position_index, uvs, uv_index):
    # positions: the points (x, y, z in meters), position_index: the point of each corner, uvs: (u, v) for each uv, uv_index: for each corner
    corners = len(position_index)
    triangles = corners // 3
    streams = [
        stream('POSITION', 'CT_FLOAT3', 12, [c for p in positions for c in p], len(positions)),
        stream('NORMAL', 'CT_FLOAT3', 12, [0, 0, 1], 1),
        stream('TEXCOORD', 'CT_FLOAT2', 8, [c for uv in uvs for c in uv], len(uvs)),
        stream('BINORMAL', 'CT_FLOAT3', 12, [0, 1, 0], 1),
        stream('TANGENT', 'CT_FLOAT3', 12, [1, 0, 0], 1),
    ]
    index_streams = [position_index, [0] * corners, uv_index, [0] * corners, [0] * corners]

    return ('\t%s = {\n\t\tindices = {\n\t\t\tsize = %d\n\t\t\tstreams = [ %s ]\n\t\t\ttype = "TRIANGLE_LIST"\n\t\t}\n'
            '\t\tmaterials = [\n\t\t\t{\n\t\t\t\tname = "m_fx"\n\t\t\t\tprimitives = [ %s ]\n\t\t\t} ]\n\t\tsmoothing = [ %s ]\n'
            '\t\tstreams = [\n%s ]\n\t}\n') % (name, corners, ' '.join('[ %s ]' % il(s) for s in index_streams),
                                                il(range(triangles)), il([1] * triangles), '\n'.join(streams))

IDENTITY = '1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1'

def write_unit(unit_name, geometries, nodes, node_local=IDENTITY, culling='disabled'):
    # geometries: text of each, nodes: { node name: geometry name } (the renderables are keyed by the node), node_local: the pose of the nodes,
    # culling: "disabled" so that the engine does not cull the unit by its distance (the small effects vanished at a distance)
    text = '\ngeometries = {\n' + ''.join(geometries) + '}\nnodes = {\n\troot = {\n\t\tchildren = {\n'

    for node, geometry_name in nodes.items():
        text += '\t\t\t%s = {\n\t\t\t\tgeometries = [ "%s" ]\n\t\t\t\tlocal = [ %s ]\n\t\t\t\tparent = "root"\n\t\t\t}\n' % (node, geometry_name, node_local)

    text += '\t\t}\n\t\tlocal = [ %s ]\n\t}\n}\nsource_path = "make_fx_meshes"\n' % IDENTITY
    raw = text.encode('latin1')
    open('%s/%s.bsi' % (FX, unit_name), 'wb').write(b'bsiz' + struct.pack('<I', len(raw)) + zlib.compress(raw))

    renderables = ''.join('\t%s = {\n\t\talways_keep = false\n\t\tculling = "%s"\n\t\tgenerate_uv_unwrap = false\n\t\toccluder = false\n'
                          '\t\tshadow_caster = false\n\t\tsurface_queries = false\n\t\tviewport_visible = true\n\t}\n' % (node, culling) for node in nodes)
    open('%s/%s.unit' % (FX, unit_name), 'w', newline='\n').write(
        'materials = {\n\tm_fx = "units/ut/fx/fx_shock_sparkle"\n}\nrenderables = {\n%s}\n' % renderables)

def to_game(point):
    # (UT's x forward, y right, z up: this game's x right, y forward, z up)
    return (point[1] * UNIT, point[0] * UNIT, point[2] * UNIT)

def make_static(unit_name, mesh_file, export=XEFFECTS, tile=None):
    # tile: (columns, rows, column, row) for a mesh whose UVs cover one tile of a sheet of tiles (UT steps through them with
    # mTileAnimation). The UVs are made to cover the whole texture, as the sheet is cut into a texture for each tile.
    points, wedges, triangles = static_mesh('%s/StaticMesh/%s.pskx' % (export, mesh_file))
    positions = [to_game(p) for p in points]
    position_index = [wedges[w][0] for t in triangles for w in t]
    if tile:
        columns, rows, column, row = tile
        wedges = [(i, u * columns - column, v * rows - row) for i, u, v in wedges]
    uvs = [(u, 1.0 - v) for _, u, v in wedges]
    uv_index = [w for t in triangles for w in t]

    write_unit(unit_name, [geometry('g_mesh', positions, position_index, uvs, uv_index)], {'g_mesh': 'g_mesh'})
    print(unit_name, len(points), 'points', len(triangles), 'triangles')

def make_vortex(unit_name, mesh_name):
    # The first frame only: UT's ShockComboVortex is a MeshEffect, which animates its scale and how much of it there is, and plays no
    # animation of the mesh (it shows the frame it starts at). It lies in the plane of x and y (its disc faces the camera, z is the way it faces).
    frames, triangles, polygon_uvs, frame = vertex_mesh(mesh_name)
    position_index = [v for t in triangles for v in t]
    uvs = [(polygon_uvs[i][2 * k], 1.0 - polygon_uvs[i][2 * k + 1]) for i in range(len(triangles)) for k in range(3)]
    uv_index = list(range(len(uvs)))
    # (ShockVortexMesh is scaled 1, 1, 2 by its mesh map, and what is up in it is made the way it faces in the plane: what was up is now y)
    positions = [(x * UNIT, z * 2 * UNIT, y * UNIT) for x, y, z in frame(0)]

    write_unit(unit_name, [geometry('g_mesh', positions, position_index, uvs, uv_index)], {'g_mesh': 'g_mesh'})
    print(unit_name, 'frame 0 of', frames, len(triangles), 'triangles')

def make_strip(unit_name, segments):
    # A strip for a beam that is one piece, as UT's PT_Beam is: two triangles for each stretch between two of its points, each on a node of
    # its own, t_<i>_a and t_<i>_b. A triangle's corners are at (0, 0, 0), (1, 0, 0) and (0, 1, 0), so the pose of its node (sheared,
    # which the engine draws) puts them anywhere: skin_particles.lua's strip puts them on the corners of the stretch, which the next one
    # shares. Across the beam is u, and v goes from 0 to 1 along a stretch, so the texture repeats once a stretch.
    #   a: the stretch's first left corner (u 0, v 0), its first right corner (1, 0) and its next left corner (0, 1)
    #   b: its next right corner (1, 1), its next left corner (0, 1) and its first right corner (1, 0)
    triangle = [(0.0, 0.0, 0.0), (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)]
    uvs = {'a': [(0, 0), (1, 0), (0, 1)], 'b': [(1, 1), (0, 1), (1, 0)]}
    geometries, nodes = [], {}

    for i in range(segments):
        for half in ('a', 'b'):
            name = 't_%d_%s' % (i, half)
            geometries.append(geometry(name, triangle, [0, 1, 2], uvs[half], [0, 1, 2]))
            nodes[name] = name

    write_unit(unit_name, geometries, nodes)
    print(unit_name, segments, 'stretches', len(nodes), 'triangles')

def make_light(unit_name):
    # A unit that is only a point light at its root (what UT's dynamic lights, LightType Steady, are: the effects set its color, brightness and
    # reach, and move it)
    write_unit(unit_name, [], {})
    open('%s/%s.unit' % (FX, unit_name), 'w', newline='\n').write(
        'lights = {\n\tlight = {\n\t\tcast_shadows = false\n\t\tcolor = [ 1 1 1 ]\n\t\tfalloff_end = 2\n\t\tfalloff_exponent = 1\n\t\tfalloff_start = 0\n'
        '\t\tnode = "root"\n\t\ttype = "omni"\n\t\tvolumetric_intensity = 0\n\t}\n}\n')
    print(unit_name, 'a light')

if __name__ == '__main__':
    make_static('coil', 'ShockCoil')
    make_light('light')
    make_static('sphere', 'TexPropSphere', EXPORT + '/Editor')
    make_vortex('vortex', 'ShockVortexMesh')
    make_static('flak_flash_mesh', 'FlakMuzFlashMesh')
    # (its UVs are in the tile of column 0 and row 1 of Minigun_burst's 2 by 2)
    make_static('minigun_flash_mesh', 'MinigunMuzFlash1stMesh', tile=(2, 2, 0, 1))
    make_static('minigun_flash_3rd_mesh', 'MinigunFlashMesh')
    make_static('shell_casing_mesh', 'ShellCasing')
    make_static('shield_mesh', 'Shield', EXPORT + '/WeaponStaticMesh')
    make_static('explosion_ring', 'ExplosionRing', EXPORT + '/ParticleMeshes')
    make_static('explosion_sphere', 'ExplosionSphere', EXPORT + '/ParticleMeshes')
    make_static('tele_ring', 'TeleRing')
    make_static('link_bolt_mesh', 'LinkProjectile', EXPORT + '/WeaponStaticMesh')
    # (its UVs are in the tile of column 0 and row 1 of link_muzmesh_green's 2 by 2)
    make_static('link_flash_mesh', 'LinkMuzFlashMesh', tile=(2, 2, 0, 1))
    make_static('shock_flash_mesh', 'ShockMuzFlash', EXPORT + '/WeaponStaticMesh')
    # (the Link Gun's beam, up to 3525 units long with links and a link (LinkFire.TraceRange and its link scale), a point every 65)
    make_strip('beam_strip', 64)
