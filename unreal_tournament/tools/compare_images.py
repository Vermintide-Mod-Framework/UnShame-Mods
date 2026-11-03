import sys, os

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'asset_conversion'))
import formats

# Puts two screenshots (the same size, as screenshot.ps1 makes them) together in one picture, so that a weapon in Vermintide 2 can be
# compared with the same weapon in Unreal Tournament 2004. It needs no packages.
#   compare_images.py <mode> <a.png> <b.png> <out.png> [x0 y0 x1 y1]
# modes:
#   side      a on the left and b on the right
#   blend     the two over each other, half and half
#   diff      how much they differ: the absolute difference of each color, made brighter
#   checker   a and b in a checkerboard of 120 pixel squares, so that an edge that continues across squares lines up
#   red-cyan  a in the red channel and b in green and blue: where they agree it is gray, and a mismatch shows as a color fringe
# The numbers at the end crop both to that part of the picture first (in pixels).

# Returns a picture as (width, height, rows), each row a list of (r, g, b)
def read_png(path):
    width, height, channels, rows = formats.read_png(path)

    return width, height, [[formats.rgb_at(rows, channels, x, y) for x in range(width)] for y in range(height)]

# Writes rows of (r, g, b) as an RGB png
def write_png(path, rows):
    formats.write_png(path, len(rows[0]), len(rows), [bytes(c for pixel in row for c in pixel) for row in rows], channels=3)

def main():
    mode, a_path, b_path, out = sys.argv[1:5]
    _, _, a = read_png(a_path)
    _, _, b = read_png(b_path)

    if len(sys.argv) >= 9:
        x0, y0, x1, y1 = [int(v) for v in sys.argv[5:9]]
        a = [row[x0:x1] for row in a[y0:y1]]
        b = [row[x0:x1] for row in b[y0:y1]]

    height = min(len(a), len(b))
    width = min(len(a[0]), len(b[0]))
    rows = []

    for y in range(height):
        if mode == 'side':
            rows.append(a[y][:width] + b[y][:width])
        elif mode == 'blend':
            rows.append([tuple((a[y][x][c] + b[y][x][c]) // 2 for c in range(3)) for x in range(width)])
        elif mode == 'diff':
            rows.append([tuple(min(255, abs(a[y][x][c] - b[y][x][c]) * 3) for c in range(3)) for x in range(width)])
        elif mode == 'checker':
            rows.append([(a if ((x // 120) + (y // 120)) % 2 == 0 else b)[y][x] for x in range(width)])
        elif mode == 'red-cyan':
            rows.append([(sum(a[y][x]) // 3, sum(b[y][x]) // 3, sum(b[y][x]) // 3) for x in range(width)])
        else:
            raise SystemExit('unknown mode ' + mode)

    write_png(out, rows)
    print('wrote', out, len(rows[0]), 'x', len(rows))

main()
