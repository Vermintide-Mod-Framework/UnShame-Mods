import sys, struct, zlib, math
from formats import read_chunks, read_psk
from quat import rotate

# Usage: psk2bsi.py in.psk out.bsi geometry_prefix material0,material1,... [scale]
# One geometry per PSK material index, named <prefix>_<index>, with the material named by the list.
src, dst, prefix, mat_list = sys.argv[1:5]
mat_names = mat_list.split(',')
scale = float(sys.argv[5]) if len(sys.argv) > 5 else 1.0

chunks = read_chunks(src)
points, wedges, psk_faces = read_psk(src)
faces = [corners + (material,) for corners, material in psk_faces]

msize, mcount, mbody = chunks['MATT0000']
psk_materials = [mbody[i * msize:i * msize + 64].split(b'\0')[0].decode('latin1') for i in range(mcount)]
print('points', len(points), 'wedges', len(wedges), 'faces', len(faces), 'materials', psk_materials)
assert len(mat_names) >= mcount, 'need a name for each of %d materials' % mcount

# UModel's psk is right handed: X forward, Y left, Z up. Stingray: X right, Y forward, Z up.
P = [(-p[1] * scale, p[0] * scale, p[2] * scale) for p in points]

def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def norm(a):
    l = math.sqrt(a[0] ** 2 + a[1] ** 2 + a[2] ** 2) or 1.0
    return (a[0] / l, a[1] / l, a[2] / l)

# The psk's front faces are clockwise, Stingray's counter-clockwise (the signed volume of the mesh is positive this way).
tris_by_mat = {}
for w0, w1, w2, mat in faces:
    tris_by_mat.setdefault(mat, []).append((w0, w2, w1))

normals = [[0.0, 0.0, 0.0] for _ in P]
for tris in tris_by_mat.values():
    for a, b, c in tris:
        pa, pb, pc = wedges[a][0], wedges[b][0], wedges[c][0]
        n = cross(sub(P[pb], P[pa]), sub(P[pc], P[pa]))
        for pi in (pa, pb, pc):
            for k in range(3):
                normals[pi][k] += n[k]
normals = [norm(n) for n in normals]

def fl(values):
    return ' '.join(str(int(v)) if float(v).is_integer() else repr(float('%.7g' % v)) for v in values)

def il(values):
    return ' '.join(str(v) for v in values)

def stream(name, ctype, stride, values, size):
    return ('\t\t\t{\n\t\t\t\tchannels = [ {\n\t\t\t\t\t\tindex = 0\n\t\t\t\t\t\tname = "%s"\n\t\t\t\t\t\ttype = "%s"\n\t\t\t\t\t} ]\n'
            '\t\t\t\tdata = [ %s ]\n\t\t\t\tsize = %d\n\t\t\t\tstride = %d\n\t\t\t}') % (name, ctype, values, size, stride)

shared = [
    stream('POSITION', 'CT_FLOAT3', 12, fl([c for p in P for c in p]), len(P)),
    stream('NORMAL', 'CT_FLOAT3', 12, fl([c for n in normals for c in n]), len(normals)),
    stream('TEXCOORD', 'CT_FLOAT2', 8, fl([x for pi, u, v in wedges for x in (u, 1.0 - v)]), len(wedges)),
]

geometries, nodes = [], []
identity = '1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1'
for mat in sorted(tris_by_mat):
    tris = tris_by_mat[mat]
    name = '%s_%d' % (prefix, mat)
    pos_idx, uv_idx, bin_data, tan_data = [], [], [], []
    for a, b, c in tris:
        pa, pb, pc = wedges[a][0], wedges[b][0], wedges[c][0]
        pos_idx += [pa, pb, pc]
        uv_idx += [a, b, c]
        e1, e2 = sub(P[pb], P[pa]), sub(P[pc], P[pa])
        du1, dv1 = wedges[b][1] - wedges[a][1], wedges[b][2] - wedges[a][2]
        du2, dv2 = wedges[c][1] - wedges[a][1], wedges[c][2] - wedges[a][2]
        det = du1 * dv2 - du2 * dv1
        if abs(det) < 1e-12:
            t, bn = (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)
        else:
            r = 1.0 / det
            t = norm(tuple((e1[k] * dv2 - e2[k] * dv1) * r for k in range(3)))
            bn = norm(tuple((e2[k] * du1 - e1[k] * du2) * r for k in range(3)))
        for _ in range(3):
            tan_data += list(t)
            bin_data += list(bn)
    n_idx = len(pos_idx)
    seq = list(range(n_idx))
    streams = shared + [
        stream('BINORMAL', 'CT_FLOAT3', 12, fl(bin_data), n_idx),
        stream('TANGENT', 'CT_FLOAT3', 12, fl(tan_data), n_idx),
    ]
    index_streams = [pos_idx, pos_idx, uv_idx, seq, seq]
    geometries.append(
        '\t%s = {\n\t\tindices = {\n\t\t\tsize = %d\n\t\t\tstreams = [ %s ]\n\t\t\ttype = "TRIANGLE_LIST"\n\t\t}\n'
        '\t\tmaterials = [\n\t\t\t{\n\t\t\t\tname = "%s"\n\t\t\t\tprimitives = [ %s ]\n\t\t\t} ]\n'
        '\t\tsmoothing = [ %s ]\n\t\tstreams = [\n%s ]\n\t}\n'
        % (name, n_idx, ' '.join('[ %s ]' % il(s) for s in index_streams), mat_names[mat],
           il(range(len(tris))), il([1] * len(tris)), '\n'.join(streams)))
    nodes.append('\t\t\t%s = {\n\t\t\t\tgeometries = [ "%s" ]\n\t\t\t\tlocal = [ %s ]\n\t\t\t\tparent = "root"\n\t\t\t}\n'
                 % (name, name, identity))
    print('geometry', name, 'material', mat_names[mat], 'triangles', len(tris))

# The second bone of the skeleton (the muzzle: 'tip' to UT) as a node of its own, where it is in the model (the root bone turns
# the bone by its own rotation and moves it by its position)
rs, rc, rb = chunks['REFSKELT']
if rc > 1:
    root_q = struct.unpack_from('<4f', rb, 76)
    root_p = struct.unpack_from('<3f', rb, 92)
    child_p = struct.unpack_from('<3f', rb, rs + 92)
    turned = rotate(root_q, child_p)
    tip = tuple(turned[i] + root_p[i] for i in range(3))
    tip_local = '1 0 0 0 0 1 0 0 0 0 1 0 %s %s %s 1' % (fl([-tip[1] * scale]), fl([tip[0] * scale]), fl([tip[2] * scale]))
    nodes.append('\t\t\ttip = {\n\t\t\t\tlocal = [ %s ]\n\t\t\t\tparent = "root"\n\t\t\t}\n' % tip_local)
    print('tip (right, forward, up in UT units)', -tip[1], tip[0], tip[2])

text = ('\ngeometries = {\n%s}\nnodes = {\n\troot = {\n\t\tchildren = {\n%s\t\t}\n\t\tlocal = [ %s ]\n\t}\n}\nsource_path = "psk2bsi"\n'
        % (''.join(geometries), ''.join(nodes), identity))
raw = text.encode('latin1')
open(dst, 'wb').write(b'bsiz' + struct.pack('<I', len(raw)) + zlib.compress(raw))
print('wrote', dst, len(raw), 'bytes raw')
