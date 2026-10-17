import os, struct, zlib

# Splits UT2004's spark textures (link_spark_green, the Link Gun's, and shield_spark, the Shield Gun's, which make_fx_assets.py converts as
# they are) into the two things each is made of: the top half is the body of a spark, a line that fades in from the tail and ends sharply
# at the head, lying along the texture's x axis, and the bottom half is the head, a round glow. Both textures have them in the same places.
# A spark is drawn as a body along its way with a head at its front. The body is turned so that it lies along the texture's y axis, which
# is the length of a beam's quad (its tail is at the top of the texture, where y is lowest).
# Usage: split_spark.py     (run after make_fx_assets.py)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FX = REPO + '/units/ut/fx'

# (the helpers of make_fx_assets.py, without running its conversion)
source = open(os.path.join(os.path.dirname(__file__), 'make_fx_assets.py'), encoding='utf8').read()
helpers = source[source.index('def write_png'):source.index('TEXTURE_TEMPLATE = ')]
material_start = source.index('MATERIAL_TEMPLATE = ')
templates = source[source.index('TEXTURE_TEMPLATE = '):source.index("'''\n", material_start + 25) + 4]
exec(helpers)
exec(templates)


def read_png(path):
    data = open(path, 'rb').read()
    position, compressed = 8, b''

    while position < len(data):
        size, tag = struct.unpack('>I4s', data[position:position + 8])
        body = data[position + 8:position + 8 + size]

        if tag == b'IHDR':
            width, height = struct.unpack('>II', body[:8])
        elif tag == b'IDAT':
            compressed += body

        position += 12 + size

    raw = zlib.decompress(compressed)
    stride = width * 4 + 1
    previous = bytearray(width * 4)
    rows = []

    for y in range(height):
        kind, line = raw[y * stride], bytearray(raw[y * stride + 1:(y + 1) * stride])

        for i in range(len(line)):
            a = line[i - 4] if i >= 4 else 0
            b = previous[i]
            c = previous[i - 4] if i >= 4 else 0

            if kind == 1:
                line[i] = (line[i] + a) & 255
            elif kind == 2:
                line[i] = (line[i] + b) & 255
            elif kind == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif kind == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255

        previous = line
        rows.append(line)

    return width, height, rows


def pixel(rows, x, y):
    return bytes(rows[y][4 * x:4 * x + 4])


def write(name, width, height, pixels):
    rows = [b'\0' + b''.join(pixels[y]) for y in range(height)]

    write_png('%s/%s.png' % (FX, name), width, height, rows)
    open('%s/%s.texture' % (FX, name), 'w', newline='\n').write(TEXTURE_TEMPLATE % {'name': name})
    open('%s/fx_%s.material' % (FX, name), 'w', newline='\n').write(MATERIAL_TEMPLATE % {'name': name})
    print('wrote', name, width, height)


# The body: the rows of the top half that have the line, turned so that the tail is at the top and the head at the bottom.
BODY_ROWS = (16, 48)
# The head: the square of the bottom half that has the glow.
HEAD = (16, 80, 48, 112)

for name in ('link_spark_green', 'shield_spark'):
    width, height, rows = read_png('%s/%s.png' % (FX, name))

    body_height = BODY_ROWS[1] - BODY_ROWS[0]
    body = [[pixel(rows, x, BODY_ROWS[0] + column) for column in range(body_height)] for x in range(width)]

    write(name + '_body', body_height, width, body)

    head = [[pixel(rows, x, y) for x in range(HEAD[0], HEAD[2])] for y in range(HEAD[1], HEAD[3])]

    write(name + '_head', HEAD[2] - HEAD[0], HEAD[3] - HEAD[1], head)
