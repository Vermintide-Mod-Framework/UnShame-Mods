import sys, re, zlib, struct, math

# Usage: render_icon.py in.bsi out.png size yaw pitch roll texture0.png[,texture1.png...]
# A software render of a converted mesh (psk2bsi.py's bsi: one geometry per material, a texture per geometry, in the order given) as an
# icon: a square png with a transparent background, the mesh lit from above and the left, seen from its right side turned by yaw (about
# the vertical) and pitch (degrees), and rolled in the picture by roll (degrees, so that a weapon lies diagonally as the game's icons do).
src, dst, size = sys.argv[1], sys.argv[2], int(sys.argv[3])
yaw, pitch, roll = [math.radians(float(v)) for v in sys.argv[4:7]]
texture_paths = sys.argv[7].split(',')
SUPER = 3


def read_png(path):
    data = open(path, 'rb').read()
    pos = 8
    idat = b''
    while pos < len(data):
        length, tag = struct.unpack('>I4s', data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + length]
        if tag == b'IHDR':
            w, h, depth, ctype, _, _, interlace = struct.unpack('>IIBBBBB', body)
            assert depth == 8 and interlace == 0 and ctype in (0, 2, 4, 6), 'unsupported png'
        elif tag == b'IDAT':
            idat += body
        pos += 12 + length
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = w * channels
    rows = []
    prev = bytearray(stride)
    p = 0
    for _ in range(h):
        ft = raw[p]
        line = bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = prev[i]
            c = prev[i - channels] if i >= channels else 0
            if ft == 1:
                line[i] = (line[i] + a) & 255
            elif ft == 2:
                line[i] = (line[i] + b) & 255
            elif ft == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif ft == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[i] = (line[i] + pr) & 255
        rows.append(line)
        prev = line

    def get(x, y):
        o = x * channels
        row = rows[y]
        if channels in (3, 4):
            return row[o], row[o + 1], row[o + 2]
        return row[o], row[o], row[o]
    return w, h, get


textures = [read_png(path) for path in texture_paths]

raw = zlib.decompress(open(src, 'rb').read()[8:]).decode('latin1')


def floats(text):
    return [float(v) for v in text.split()]


def stream_data(name):
    i = raw.find('name = "%s"' % name)
    j = raw.find('data = [', i)
    k = raw.find(']', j)
    return floats(raw[j + 8:k])


pos_data = stream_data('POSITION')
uv_data = stream_data('TEXCOORD')
points = [tuple(pos_data[i:i + 3]) for i in range(0, len(pos_data), 3)]
uvs = [tuple(uv_data[i:i + 2]) for i in range(0, len(uv_data), 2)]

geometries = []
for m in re.finditer(r'\n\t(g_\w+) = \{\n\t\tindices = \{\n\t\t\tsize = \d+\n\t\t\tstreams = \[ (.*?) \]\n\t\t\ttype', raw, re.S):
    groups = re.findall(r'\[ ([\d ]*) \]', m.group(2))
    pos_idx = [int(v) for v in groups[0].split()]
    uv_idx = [int(v) for v in groups[2].split()]
    geometries.append((pos_idx, uv_idx))

# Rotation: yaw about the vertical (z), then pitch about the right axis (x); the view is from +x: screen x is y, screen y is z, depth is x
cy, sy_, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
cr, sr = math.cos(roll), math.sin(roll)


def transform(p):
    x, y, z = p
    x, y = x * cy - y * sy_, x * sy_ + y * cy
    y, z = y * cp - z * sp, y * sp + z * cp
    sx, sy = y, z
    return sx * cr - sy * sr, sx * sr + sy * cr, x


T = [transform(p) for p in points]
minx = min(t[0] for t in T); maxx = max(t[0] for t in T)
miny = min(t[1] for t in T); maxy = max(t[1] for t in T)
W = size * SUPER
scale = (W * 0.92) / max(maxx - minx, maxy - miny)
offx = (W - (maxx - minx) * scale) / 2
offy = (W - (maxy - miny) * scale) / 2


def to_screen(t):
    return offx + (t[0] - minx) * scale, W - offy - (t[1] - miny) * scale, t[2]


light = (-0.4, 0.5, 0.75)
ll = math.sqrt(sum(c * c for c in light))
light = tuple(c / ll for c in light)

color = [[None] * W for _ in range(W)]
depth = [[-1e9] * W for _ in range(W)]

for g, (pos_idx, uv_idx) in enumerate(geometries):
    tw, th, tex = textures[min(g, len(textures) - 1)]
    for t in range(0, len(pos_idx), 3):
        ids = pos_idx[t:t + 3]
        uid = uv_idx[t:t + 3]
        a3, b3, c3 = [points[i] for i in ids]
        e1 = (b3[0] - a3[0], b3[1] - a3[1], b3[2] - a3[2])
        e2 = (c3[0] - a3[0], c3[1] - a3[1], c3[2] - a3[2])
        n = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
        # (the normal in the view's frame: lit as it faces the viewer)
        nv = transform(n)
        nv = (nv[0] - transform((0, 0, 0))[0], nv[1] - transform((0, 0, 0))[1], nv[2])
        nl = math.sqrt(sum(c * c for c in nv)) or 1.0
        nv = tuple(c / nl for c in nv)
        if nv[2] < 0:
            nv = tuple(-c for c in nv)
        shade = 0.7 + 0.55 * max(0.0, sum(nv[i] * light[i] for i in range(3)))
        pr = [to_screen(T[i]) for i in ids]
        (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = pr
        den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
        if abs(den) < 1e-9:
            continue
        for yy in range(max(0, int(min(y0, y1, y2))), min(W - 1, int(max(y0, y1, y2)) + 1) + 1):
            for xx in range(max(0, int(min(x0, x1, x2))), min(W - 1, int(max(x0, x1, x2)) + 1) + 1):
                l0 = ((y1 - y2) * (xx - x2) + (x2 - x1) * (yy - y2)) / den
                l1 = ((y2 - y0) * (xx - x2) + (x0 - x2) * (yy - y2)) / den
                l2 = 1 - l0 - l1
                if l0 < 0 or l1 < 0 or l2 < 0:
                    continue
                z = l0 * z0 + l1 * z1 + l2 * z2
                if z <= depth[yy][xx]:
                    continue
                depth[yy][xx] = z
                u = l0 * uvs[uid[0]][0] + l1 * uvs[uid[1]][0] + l2 * uvs[uid[2]][0]
                v = l0 * uvs[uid[0]][1] + l1 * uvs[uid[1]][1] + l2 * uvs[uid[2]][1]
                r, gr, b = tex(int(u * tw) % tw, int((1 - v) * th) % th)
                color[yy][xx] = (min(255, r * shade), min(255, gr * shade), min(255, b * shade))

# Down to the size: the average of the covered samples, the coverage is the alpha
rows = []
for y in range(size):
    row = bytearray([0])
    for x in range(size):
        r = g = b = n = 0
        for j in range(SUPER):
            for i in range(SUPER):
                c = color[y * SUPER + j][x * SUPER + i]
                if c:
                    r += c[0]; g += c[1]; b += c[2]; n += 1
        if n:
            row += bytes((int(r / n), int(g / n), int(b / n), int(255 * n / (SUPER * SUPER))))
        else:
            row += bytes((0, 0, 0, 0))
    rows.append(bytes(row))


def chunk(tag, body):
    c = struct.pack('>I', len(body)) + tag + body
    return c + struct.pack('>I', zlib.crc32(tag + body) & 0xffffffff)


open(dst, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b''.join(rows))) + chunk(b'IEND', b''))
print('wrote', dst)
