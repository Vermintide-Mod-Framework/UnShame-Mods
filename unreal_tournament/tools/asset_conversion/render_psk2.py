import sys, struct, zlib

# Usage: render_psk.py in.psk in.tga out.png vflip(0/1) view(side|top|front) [mirror_u(0/1)]
src, tga, dst, vflip, view = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
mirror_u = int(sys.argv[6]) if len(sys.argv) > 6 else 0

def read_tga(path):
    d = open(path, 'rb').read()
    idlen, cmtype, imgtype = d[0], d[1], d[2]
    w, h = struct.unpack('<HH', d[12:16])
    bpp, desc = d[16], d[17]
    bp = bpp // 8
    p = 18 + idlen
    px = bytearray()
    if imgtype == 2:
        px = bytearray(d[p:p + w * h * bp])
    else:
        while len(px) < w * h * bp:
            head = d[p]; p += 1
            n = (head & 0x7f) + 1
            if head & 0x80:
                px += d[p:p + bp] * n; p += bp
            else:
                px += d[p:p + n * bp]; p += n * bp
    top_first = bool(desc & 0x20)
    def get(x, y):  # y=0 is the top row of the image
        sy = y if top_first else h - 1 - y
        o = (sy * w + x) * bp
        return px[o + 2], px[o + 1], px[o]
    return w, h, get

tw, th, tex = read_tga(tga)

data = open(src, 'rb').read()
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
s, c, b = ch['FACE0000']
faces = [struct.unpack_from('<3H', b, i * s) + (b[i * s + 6],) for i in range(c)]

# Stingray space: x right, y forward, z up
P = [(-p[1], p[0], p[2]) for p in pts]

def proj(p):
    if view == 'side':
        return p[1], p[2], p[0]      # screen x = forward, screen y = up, depth = x (viewer on +x)
    if view == 'left':
        return -p[1], p[2], -p[0]
    if view == 'top':
        return p[1], p[0], p[2]      # looking down: screen x = forward, screen y = x
    return p[0], p[2], p[1]

W, H = 1000, 500
allp = [proj(p) for p in P]
minx = min(a[0] for a in allp); maxx = max(a[0] for a in allp)
miny = min(a[1] for a in allp); maxy = max(a[1] for a in allp)
scale = min((W - 20) / (maxx - minx), (H - 20) / (maxy - miny))
img = [[(30, 30, 30)] * W for _ in range(H)]
zbuf = [[-1e9] * W for _ in range(H)]

def sx(a): return 10 + (a[0] - minx) * scale
def sy(a): return H - 10 - (a[1] - miny) * scale

for w0, w1, w2, mat in faces:
    if mat != 0:
        continue
    ws = [wed[w0], wed[w1], wed[w2]]
    pr = [proj(P[w[0]]) for w in ws]
    # outward-facing check in 3D with cross(b-a, c-a), viewer along +depth
    a3, b3, c3 = P[ws[0][0]], P[ws[2][0]], P[ws[1][0]]   # outward order is (w0, w2, w1) in this space
    e1 = (b3[0] - a3[0], b3[1] - a3[1], b3[2] - a3[2])
    e2 = (c3[0] - a3[0], c3[1] - a3[1], c3[2] - a3[2])
    n3 = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
    if view == 'side' and n3[0] <= 0:
        continue
    if view == 'left' and n3[0] >= 0:
        continue
    pts2 = [(sx(p), sy(p), p[2]) for p in pr]
    minxx = max(0, int(min(p[0] for p in pts2))); maxxx = min(W - 1, int(max(p[0] for p in pts2)) + 1)
    minyy = max(0, int(min(p[1] for p in pts2))); maxyy = min(H - 1, int(max(p[1] for p in pts2)) + 1)
    (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = pts2
    den = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)
    if abs(den) < 1e-9:
        continue
    for yy in range(minyy, maxyy + 1):
        for xx in range(minxx, maxxx + 1):
            l0 = ((y1 - y2) * (xx - x2) + (x2 - x1) * (yy - y2)) / den
            l1 = ((y2 - y0) * (xx - x2) + (x0 - x2) * (yy - y2)) / den
            l2 = 1 - l0 - l1
            if l0 < 0 or l1 < 0 or l2 < 0:
                continue
            z = l0 * z0 + l1 * z1 + l2 * z2
            if z <= zbuf[yy][xx]:
                continue
            zbuf[yy][xx] = z
            u = l0 * ws[0][1] + l1 * ws[1][1] + l2 * ws[2][1]
            v = l0 * ws[0][2] + l1 * ws[1][2] + l2 * ws[2][2]
            if mirror_u:
                u = 1 - u
            if vflip:
                v = 1 - v
            img[yy][xx] = tex(int(u * tw) % tw, int(v * th) % th)

def chunk(tag, body):
    c = struct.pack('>I', len(body)) + tag + body
    return c + struct.pack('>I', zlib.crc32(tag + body) & 0xffffffff)

rows = b''.join(b'\0' + b''.join(bytes(px) for px in row) for row in img)
open(dst, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b''))
print('wrote', dst)
