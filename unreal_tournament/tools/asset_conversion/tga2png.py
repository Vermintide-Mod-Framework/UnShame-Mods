import sys, struct, zlib

# Usage: tga2png.py in.tga out.png [tint_r tint_g tint_b]
# With a tint, the colour is the luminance of the texture times the tint (0..1 each), the alpha is kept.
src, dst = sys.argv[1:3]
tint = tuple(float(x) for x in sys.argv[3:6]) if len(sys.argv) >= 6 else None
d = open(src, 'rb').read()
idlen, cmtype, imgtype = d[0], d[1], d[2]
w, h = struct.unpack('<HH', d[12:16])
bpp, desc = d[16], d[17]
assert cmtype == 0 and imgtype in (2, 10), (cmtype, imgtype)
bytes_pp = bpp // 8
p = 18 + idlen
pixels = bytearray()
if imgtype == 2:
    pixels = bytearray(d[p:p + w * h * bytes_pp])
else:
    while len(pixels) < w * h * bytes_pp:
        head = d[p]
        p += 1
        n = (head & 0x7f) + 1
        if head & 0x80:
            pixels += d[p:p + bytes_pp] * n
            p += bytes_pp
        else:
            pixels += d[p:p + n * bytes_pp]
            p += n * bytes_pp

rows = []
for y in range(h):
    sy = y if desc & 0x20 else h - 1 - y
    row = pixels[sy * w * bytes_pp:(sy + 1) * w * bytes_pp]
    out = bytearray()
    for x in range(w):
        b, g, r = row[x * bytes_pp], row[x * bytes_pp + 1], row[x * bytes_pp + 2]
        a = row[x * bytes_pp + 3] if bytes_pp == 4 else 255
        if tint:
            lum = (0.3 * r + 0.59 * g + 0.11 * b) * 1.4
            r, g, b = (min(255, int(lum * t)) for t in tint)
        out += bytes((r, g, b, a))
    rows.append(b'\0' + bytes(out))

def chunk(tag, body):
    c = struct.pack('>I', len(body)) + tag + body
    return c + struct.pack('>I', zlib.crc32(tag + body) & 0xffffffff)

png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) + \
    chunk(b'IDAT', zlib.compress(b''.join(rows), 6)) + chunk(b'IEND', b'')
open(dst, 'wb').write(png)
print('wrote', dst, w, h, bpp)
