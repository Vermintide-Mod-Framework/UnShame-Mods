import sys
from formats import read_tga, write_png

# Usage: tga2png.py in.tga out.png [tint_r tint_g tint_b]
# With a tint, the colour is the luminance of the texture times the tint (0..1 each), the alpha is kept.
src, dst = sys.argv[1:3]
tint = tuple(float(x) for x in sys.argv[3:6]) if len(sys.argv) >= 6 else None
w, h, rows = read_tga(src)

if tint:
    tinted = []

    for row in rows:
        out = bytearray()

        for x in range(w):
            r, g, b, a = row[x * 4:x * 4 + 4]
            lum = (0.3 * r + 0.59 * g + 0.11 * b) * 1.4
            r, g, b = (min(255, int(lum * t)) for t in tint)
            out += bytes((r, g, b, a))

        tinted.append(bytes(out))

    rows = tinted

write_png(dst, w, h, rows)
print('wrote', dst, w, h)
