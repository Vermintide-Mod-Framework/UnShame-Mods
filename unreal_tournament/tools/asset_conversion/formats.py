import struct, zlib

# Reading and writing the files that the conversion tools use: TGA and PNG images, and UModel's psk, pskx and psa.
#
# An image is (width, height, rows). The rows are top first, and each is the bytes of its pixels (RGBA unless channels says otherwise),
# with no PNG filter byte.


def read_tga(path):
    """Returns (width, height, rows) of a TGA, true colour or run length encoded, with RGBA rows (alpha 255 for a 24 bit TGA)."""
    data = open(path, 'rb').read()
    id_length, image_type = data[0], data[2]
    width, height = struct.unpack('<HH', data[12:16])
    bytes_per_pixel, descriptor = data[16] // 8, data[17]
    position = 18 + id_length
    pixels = bytearray()

    if image_type == 2:
        pixels = bytearray(data[position:position + width * height * bytes_per_pixel])
    else:
        while len(pixels) < width * height * bytes_per_pixel:
            head = data[position]
            position += 1
            count = (head & 0x7f) + 1

            if head & 0x80:
                pixels += data[position:position + bytes_per_pixel] * count
                position += bytes_per_pixel
            else:
                pixels += data[position:position + count * bytes_per_pixel]
                position += count * bytes_per_pixel

    rows = []

    for y in range(height):
        source_y = y if descriptor & 0x20 else height - 1 - y
        row = bytearray()

        for x in range(width):
            o = (source_y * width + x) * bytes_per_pixel
            row += bytes((pixels[o + 2], pixels[o + 1], pixels[o], pixels[o + 3] if bytes_per_pixel == 4 else 255))

        rows.append(bytes(row))

    return width, height, rows


def write_png(path, width, height, rows, channels=4):
    """Writes rows of RGBA (or RGB, with channels 3) as an 8 bit PNG."""
    def chunk(tag, body):
        return struct.pack('>I', len(body)) + tag + body + struct.pack('>I', zlib.crc32(tag + body) & 0xffffffff)

    color_type = 6 if channels == 4 else 2
    raw = b''.join(b'\0' + bytes(row) for row in rows)

    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, color_type, 0, 0, 0)) +
                           chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))


def read_png(path):
    """Returns (width, height, channels, rows) of an 8 bit, not interlaced PNG: grey (1), grey and alpha (2), RGB (3) or RGBA (4)."""
    data = open(path, 'rb').read()
    position, compressed = 8, b''

    while position < len(data):
        length, tag = struct.unpack('>I4s', data[position:position + 8])
        body = data[position + 8:position + 8 + length]

        if tag == b'IHDR':
            width, height, depth, color_type, _, _, interlace = struct.unpack('>IIBBBBB', body)
            assert depth == 8 and interlace == 0 and color_type in (0, 2, 4, 6), 'unsupported png'
        elif tag == b'IDAT':
            compressed += body

        position += 12 + length

    channels = {0: 1, 2: 3, 4: 2, 6: 4}[color_type]
    raw = zlib.decompress(compressed)
    stride = width * channels
    rows, previous, position = [], bytearray(stride), 0

    for _ in range(height):
        filter_type = raw[position]
        line = bytearray(raw[position + 1:position + 1 + stride])
        position += 1 + stride

        for i in range(stride):
            a = line[i - channels] if i >= channels else 0
            b = previous[i]
            c = previous[i - channels] if i >= channels else 0

            if filter_type == 1:
                line[i] = (line[i] + a) & 255
            elif filter_type == 2:
                line[i] = (line[i] + b) & 255
            elif filter_type == 3:
                line[i] = (line[i] + ((a + b) >> 1)) & 255
            elif filter_type == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else (b if pb <= pc else c))) & 255

        rows.append(line)
        previous = line

    return width, height, channels, rows


def rgb_at(rows, channels, x, y):
    """The colour of a pixel of read_png's rows, as (r, g, b). A grey image gives its grey three times."""
    o = x * channels
    row = rows[y]

    return (row[o], row[o + 1], row[o + 2]) if channels >= 3 else (row[o], row[o], row[o])


def chunk_offsets(data):
    """The chunks of a psk, pskx or psa, by name: (size of an item, number of items, where the items start in data)."""
    chunks, position = {}, 0

    while position + 32 <= len(data):
        name = data[position:position + 20].split(b'\0')[0].decode('latin1')
        _, size, count = struct.unpack('<iii', data[position + 20:position + 32])
        chunks[name] = (size, count, position + 32)
        position += 32 + size * count

    return chunks


def read_chunks(path):
    """The chunks of a psk, pskx or psa file, by name: (size of an item, number of items, the items' bytes)."""
    data = open(path, 'rb').read()

    return {name: (size, count, data[start:start + size * count]) for name, (size, count, start) in chunk_offsets(data).items()}


def read_psk(path):
    """Returns the points, the wedges (point, u, v) and the faces ((wedge, wedge, wedge), material) of a psk or pskx."""
    chunks = read_chunks(path)
    size, count, body = chunks['PNTS0000']
    points = [struct.unpack_from('<3f', body, i * size) for i in range(count)]
    size, count, body = chunks['VTXW0000']
    wedges = []

    for i in range(count):
        point = struct.unpack_from('<H' if size == 16 else '<I', body, i * size)[0]
        wedges.append((point,) + struct.unpack_from('<2f', body, i * size + 4))

    face_chunk = 'FACE0000' if 'FACE0000' in chunks else 'FACE3200'
    size, count, body = chunks[face_chunk]
    corners = '<3H' if face_chunk == 'FACE0000' else '<3I'
    corner_bytes = struct.calcsize(corners)
    faces = [(struct.unpack_from(corners, body, i * size), body[i * size + corner_bytes]) for i in range(count)]

    return points, wedges, faces
