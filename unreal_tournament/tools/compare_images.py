import sys, os, struct, zlib

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

def read_png(path):
    d = open(path, 'rb').read()
    pos = 8
    idat = b''
    while pos < len(d):
        length, = struct.unpack('>I', d[pos:pos + 4])
        kind = d[pos + 4:pos + 8]
        body = d[pos + 8:pos + 8 + length]

        if kind == b'IHDR':
            width, height, depth, color = struct.unpack('>IIBB', body[:10])
        elif kind == b'IDAT':
            idat += body

        pos += 12 + length

    assert depth == 8 and color in (2, 6), 'only 8 bit rgb and rgba'
    channels = 3 if color == 2 else 4
    raw = zlib.decompress(idat)
    stride = width * channels
    rows = []
    previous = bytearray(stride)
    offset = 0

    for _ in range(height):
        kind = raw[offset]
        line = bytearray(raw[offset + 1:offset + 1 + stride])
        offset += 1 + stride

        for i in range(stride):
            left = line[i - channels] if i >= channels else 0
            up = previous[i]
            up_left = previous[i - channels] if i >= channels else 0

            if kind == 1:
                line[i] = (line[i] + left) & 255
            elif kind == 2:
                line[i] = (line[i] + up) & 255
            elif kind == 3:
                line[i] = (line[i] + (left + up) // 2) & 255
            elif kind == 4:
                p = left + up - up_left
                pa, pb, pc = abs(p - left), abs(p - up), abs(p - up_left)
                line[i] = (line[i] + (left if pa <= pb and pa <= pc else up if pb <= pc else up_left)) & 255

        previous = line
        rows.append([tuple(line[x * channels:x * channels + 3]) for x in range(width)])

    return width, height, rows

def write_png(path, rows):
    height, width = len(rows), len(rows[0])
    raw = b''.join(b'\0' + bytes(c for pixel in row for c in pixel) for row in rows)

    def chunk(kind, body):
        c = struct.pack('>I', len(body)) + kind + body
        return c + struct.pack('>I', zlib.crc32(kind + body) & 0xffffffff)

    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)) +
                           chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))

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
