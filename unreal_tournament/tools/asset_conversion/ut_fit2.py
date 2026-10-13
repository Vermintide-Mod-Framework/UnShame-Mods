import struct, math, sys

# Usage: ut_fit2.py <scratch dir>      (the dir has umodel/out3, the export of NewWeapons2004's ShockRifle, see README.md)
data = open(sys.argv[1] + '/umodel/out3/NewWeapons2004/SkeletalMesh/ShockRifle.psk', 'rb').read()
pos = 0
ch = {}
while pos + 32 <= len(data):
    cid = data[pos:pos + 20].split(b'\0')[0].decode('latin1')
    t, s, c = struct.unpack('<iii', data[pos + 20:pos + 32])
    ch[cid] = (s, c, data[pos + 32:pos + 32 + s * c])
    pos += 32 + s * c
s, c, b = ch['PNTS0000']
pts = [struct.unpack_from('<3f', b, i * s) for i in range(c)]
s, c, b = ch['VTXW0000']
wed = [(struct.unpack_from('<H', b, i * s)[0],) + struct.unpack_from('<2f', b, i * s + 4) for i in range(c)]

DELTA = (31.347 + 0.279, -15.422, -26.761)
def ue(p):  # psk -> (forward, right, up) in UT units, in the idle pose
    return (p[0] + DELTA[0], -(p[1] + DELTA[1]), p[2] + DELTA[2])

def feature(px0, py0, px1, py1, tex=1024):
    sel = [w for w in wed if px0 <= w[1] * tex <= px1 and py0 <= w[2] * tex <= py1]
    if not sel:
        return None
    ps = [ue(pts[w[0]]) for w in sel]
    n = len(ps)
    return tuple(sum(p[i] for p in ps) / n for i in range(3)), n

features = {
    'radar': ((765, 283, 815, 335), (1558, 845)),
    'button_top': ((830, 285, 860, 310), (1550, 897)),
    'button_bottom': ((830, 330, 860, 360), (1590, 897)),
    'st115': ((440, 380, 600, 430), (1440, 830)),
}

def project(m, fov_h, width, cx, cy, draw_scale, offset, pitch_deg, mirror=1):
    th = math.radians(pitch_deg)
    X, Y, Z = m
    Xr = X * math.cos(th) - Z * math.sin(th)
    Zr = X * math.sin(th) + Z * math.cos(th)
    cam = (draw_scale * Xr + offset[0], mirror * (draw_scale * Y) + offset[1], draw_scale * Zr + offset[2])
    f = (width / 2) / math.tan(math.radians(fov_h) / 2)
    return cx + f * cam[1] / cam[0], cy - f * cam[2] / cam[0], cam

W, H = 1921, 1076
CX, CY = 958, 571
found = {}
for name, (rect, px) in features.items():
    r = feature(*rect)
    if r:
        found[name] = (r[0], px)
        print(name, 'mesh (fwd,right,up)', tuple(round(v, 1) for v in r[0]), 'verts', r[1])
    else:
        print(name, 'no vertices')

def report(label, fov_h, draw_scale, offset, pitch):
    print('==', label)
    err = 0
    for name, (m, px) in found.items():
        x, y, cam = project(m, fov_h, W, CX, CY, draw_scale, offset, pitch)
        e = math.hypot(x - px[0], y - px[1])
        err += e
        print('  %-14s predicted (%.0f, %.0f) observed %s  error %.0f  cam %s' % (name, x, y, px, e, tuple(round(v, 1) for v in cam)))
    print('  total error %.0f' % err)

k = 90 / 70
report('UT source, hfov 70', 70, 0.7, (4 * k, 8 * k, -2 * k), -1000 / 65536 * 360)
report('UT source, hfov 90', 90, 0.7, (4 * k, 8 * k, -2 * k), -1000 / 65536 * 360)
report('no offset scaling, hfov 70', 70, 0.7, (4, 8, -2), -1000 / 65536 * 360)
