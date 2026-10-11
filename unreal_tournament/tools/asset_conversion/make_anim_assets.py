import struct, math, zlib, os

REPO = 'E:/Git/vmb/mods/unreal_tournament'
SCRATCH = 'C:/Users/UnShame/AppData/Local/Temp/claude/E--Git-vmb-mods/070374a7-2283-43c8-bdec-22b0376758d1/scratchpad'
OUT = SCRATCH + '/umodel/out3'
FRAMES = 200         # gel flipbook frames
LOOP_SECONDS = 10.0  # one loop of the pan; the oscillations are 5 s and 10 s
SIZE = 128

# ---------------------------------------------------------------- animation keys
def chunks(path):
    d = open(path, 'rb').read()
    pos = 0
    ch = {}
    while pos + 32 <= len(d):
        cid = d[pos:pos + 20].split(b'\0')[0].decode('latin1')
        t, s, c = struct.unpack('<iii', d[pos + 20:pos + 32])
        ch[cid] = (s, c, d[pos + 32:pos + 32 + s * c])
        pos += 32 + s * c
    return ch

def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)

def qconj(a):
    return (-a[0], -a[1], -a[2], a[3])

def rotate(q, v):
    r = qmul(qmul(q, (v[0], v[1], v[2], 0)), qconj(q))
    return r[:3]

psk = chunks(OUT + '/NewWeapons2004/SkeletalMesh/ShockRifle.psk')
psa = chunks(OUT + '/NewWeapons2004/MeshAnimation/ShockRifle.psa')
s, c, b = psk['REFSKELT']
q_ref = struct.unpack_from('<4f', b, 76)
p_ref = struct.unpack_from('<3f', b, 92)
s, c, b = psa['ANIMINFO']
anims = []
for i in range(c):
    o = i * s
    name = b[o:o + 64].split(b'\0')[0].decode()
    tb, ri, kc, kq, kr, tt, rate, sb, first, num = struct.unpack_from('<4i3f3i', b, o + 128)
    anims.append((name, rate, first, num))
key_size, _, keys = psa['ANIMKEYS']

def to_model(v):  # psk (x forward, y left, z up) -> the model's (right, forward, up)
    return (-v[1], v[0], v[2])

def fmt(values):
    return ', '.join(('%.6f' % v).rstrip('0').rstrip('.') for v in values)

lines = ['-- The root bone of the animations of the UT2004 Shock Rifle (NewWeapons2004.ShockRifle), against its mesh, as a',
         '-- rotation of the mesh (x, y, z, w) and a move of it in UT units (right, forward, up): one row of the frames each.',
         '-- Made from the psa by make_anim_assets.py, never to be committed.', 'return {']
for name, rate, first, num in anims:
    if name == 'PutDown':
        continue  # the game has no animation of putting a weapon down
    lines.append('\t%s = {' % name)
    lines.append('\t\trate = %g,' % rate)
    lines.append('\t\tframes = {')
    for f in range(num):
        o = (first + f) * 2 * key_size
        p_a = struct.unpack_from('<3f', keys, o)
        q_a = struct.unpack_from('<4f', keys, o + 12)
        rd = qmul(q_a, qconj(q_ref))
        rp = rotate(rd, p_ref)
        move = tuple(p_a[i] - rp[i] for i in range(3))
        rx, ry, rz = to_model(rd[:3])
        mx, my, mz = to_model(move)
        lines.append('\t\t\t{ %s },' % fmt((rx, ry, rz, rd[3], mx, my, mz)))
    lines.append('\t\t},')
    lines.append('\t},')
lines.append('}')
open(REPO + '/scripts/mods/unreal_tournament/shock_rifle_skin_animations.lua', 'w', newline='\n').write('\n'.join(lines) + '\n')
print('animations', [(a[0], a[3]) for a in anims])

# ---------------------------------------------------------------- gel flipbook
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
            head = d[p]
            p += 1
            n = (head & 0x7f) + 1
            if head & 0x80:
                px += d[p:p + bp] * n
                p += bp
            else:
                px += d[p:p + n * bp]
                p += n * bp
    top_first = bool(desc & 0x20)
    img = []
    for y in range(h):
        sy = y if top_first else h - 1 - y
        row = []
        for x in range(w):
            o = (sy * w + x) * bp
            row.append((px[o + 2], px[o + 1], px[o], px[o + 3] if bp == 4 else 255))
        img.append(row)
    return w, h, img

gw, gh, gel = read_tga(OUT + '/UT2004Weapons/Texture/PowerGel.tga')

def sample(u, v):
    x = (u % 1.0) * gw - 0.5
    y = (v % 1.0) * gh - 0.5
    x0 = math.floor(x)
    y0 = math.floor(y)
    fx = x - x0
    fy = y - y0
    out = [0.0] * 4
    for dx, dy, w in ((0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)):
        px = gel[(y0 + dy) % gh][(x0 + dx) % gw]
        for k in range(4):
            out[k] += px[k] * w
    return out

def png(path, w, h, rows):
    def chunk(tag, body):
        c = struct.pack('>I', len(body)) + tag + body
        return c + struct.pack('>I', zlib.crc32(tag + body) & 0xffffffff)
    raw = b''.join(b'\0' + bytes(r) for r in rows)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) +
                           chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))

TINT = (192 / 255, 0.1, 1.0)  # ShockControl / ConstantColor2 (R192 B255) with a little green so it isn't black in the shade
texture_template = open(REPO + '/units/ut/shock_power_df.texture').read()
material_template = open(REPO + '/units/ut/shock_rifle_power.material').read()
names = []
for f in range(FRAMES):
    t = f / FRAMES * LOOP_SECONDS
    stretch_u = 1 + 0.1 * math.sin(2 * math.pi * 0.2 * t)    # TexOscillator0, OT_Stretch about the middle
    stretch_v = 1 + 0.2 * math.sin(2 * math.pi * 0.1 * t)
    pan = -0.1 * t                                            # TexPanner0, yaw -16384: along -v
    rows = []
    for j in range(SIZE):
        row = []
        for i in range(SIZE):
            u = (i + 0.5) / SIZE
            v = (j + 0.5) / SIZE
            r, g, b_, a = sample(0.5 + (u - 0.5) * stretch_u, 0.5 + (v - 0.5) * stretch_v + pan)
            # (the chamber is lit by itself and adds its light: the whole of it glows, the streaks of the gel more, and the alpha of the
            # texture, which is what the glass masks with in UT, is not used)
            lum = (0.3 * r + 0.59 * g + 0.11 * b_) * 1.6 / 255
            lum = 0.35 + 0.65 * min(1.0, lum)
            row.extend((int(255 * lum * TINT[0]), int(255 * lum * TINT[1]), int(255 * lum * TINT[2]), 255))
        rows.append(row)
    name = 'shock_gel_%02d' % f
    png('%s/units/ut/%s.png' % (REPO, name), SIZE, SIZE, rows)
    open('%s/units/ut/%s.texture' % (REPO, name), 'w').write(texture_template.replace('units/ut/shock_power_df', 'units/ut/' + name))
    open('%s/units/ut/shock_rifle_power_%02d.material' % (REPO, f), 'w').write(material_template.replace('units/ut/shock_power_df', 'units/ut/' + name))
    names.append('units/ut/shock_rifle_power_%02d' % f)
print('gel frames', FRAMES, 'size', SIZE)
open(SCRATCH + '/gel_materials.txt', 'w').write('\n'.join('\t"%s"' % n for n in names) + '\n')
