import os, sys, struct, zlib, collections

# Reads the bundles of Vermintide 2 (<game dir>/bundle): finds which bundle has a resource, lists what a bundle holds, and unpacks one.
# A bundle is chunks of zstd (the game's compression.dictionary is in the bundle folder; a chunk that is 64 KB long is stored as it is, and the
# bundles of older versions are zlib), and what they hold starts with a table of the resources: a type and a name, as hashes, and sizes.
# The names are hashed with the 64 bit MurmurHash that the engine uses (names of resources are not in the bundles, they have to be guessed).
# Needs the zstandard package (pip install zstandard).
#
# Usage:
#   bundles.py find <name> [name ...]            the bundles that have a resource of this name (of any type), and its type
#   bundles.py where <name> <type>               the bundle that has this resource, as in "units/weapons/player/wpn_x/wpn_x unit"
#   bundles.py list <bundle>                     the number of resources by type, and what the Wwise ones hold
#   bundles.py unpack <bundle> <out>             the bundle decompressed, as it is (what is in it can be searched)
# The game folder is in the VT2_DIR environment variable (the folder that has the bundle folder). A bundle is a file of the bundle
# folder with no extension.

MULTIPLIER = 0xc6a4a7935bd1e995
MASK = (1 << 64) - 1
ZSTD_VERSION = 0xf0000007

# The types of the resources that are known by name (the hash of the name of the type is what the bundles have)
TYPE_NAMES = ['lua', 'unit', 'material', 'texture', 'wwise_bank', 'wwise_dep', 'wwise_stream', 'wwise_metadata', 'package', 'mod', 'config',
              'particles', 'animation', 'state_machine', 'bones', 'strings', 'mesh', 'shader', 'render_config', 'level', 'font', 'flow',
              'physics_properties', 'shading_environment', 'ini', 'data', 'tag', 'common_package', 'network_config']


def murmur64(data, seed=0):
    r = 47
    h = (seed ^ (len(data) * MULTIPLIER)) & MASK
    blocks = len(data) // 8

    for i in range(blocks):
        k = struct.unpack_from('<Q', data, i * 8)[0]
        k = (k * MULTIPLIER) & MASK
        k ^= k >> r
        k = (k * MULTIPLIER) & MASK
        h ^= k
        h = (h * MULTIPLIER) & MASK

    tail = data[blocks * 8:]

    if tail:
        for i in range(len(tail) - 1, -1, -1):
            h ^= tail[i] << (8 * i)

        h = (h * MULTIPLIER) & MASK

    h ^= h >> r
    h = (h * MULTIPLIER) & MASK
    h ^= h >> r

    return h


def name_hash(name):
    return murmur64(name.encode())


TYPES = {name_hash(name): name for name in TYPE_NAMES}


def bundle_folder():
    game = os.environ.get('VT2_DIR')

    if not game:
        sys.exit('Set the VT2_DIR environment variable to the folder of the game (the one that has the bundle folder).')

    return game + '/bundle'


_decompressor = None


def decompressor():
    global _decompressor

    if _decompressor is None:
        import zstandard

        dictionary = zstandard.ZstdCompressionDict(open(bundle_folder() + '/compression.dictionary', 'rb').read())
        _decompressor = zstandard.ZstdDecompressor(dict_data=dictionary)

    return _decompressor


def chunks(path):
    """The decompressed chunks of a bundle, one by one."""
    with open(path, 'rb') as f:
        head = f.read(12)

        if len(head) < 12:
            return

        version = struct.unpack('<I', head[:4])[0]

        while True:
            raw = f.read(4)

            if len(raw) < 4:
                return

            size = struct.unpack('<I', raw)[0]

            if size == 0:
                return

            data = f.read(size)

            if size == 0x10000:
                yield data
            elif version == ZSTD_VERSION:
                try:
                    yield decompressor().decompress(data, max_output_size=1 << 24)
                except Exception:
                    yield data
            else:
                yield zlib.decompress(data)


def table(path):
    """The resources of a bundle, from its first chunks: (type, name, size, size) of each, as hashes."""
    buffer = b''

    for chunk in chunks(path):
        buffer += chunk

        if len(buffer) >= 4:
            count = struct.unpack('<I', buffer[:4])[0]

            if len(buffer) >= 0x104 + 24 * count:
                return [struct.unpack_from('<QQII', buffer, 0x104 + 24 * k) for k in range(count)]

    return []


def bundles():
    folder = bundle_folder()

    for name in sorted(os.listdir(folder)):
        if '.' not in name:
            yield name, folder + '/' + name


def find(names):
    wanted = {name_hash(name): name for name in names}

    for bundle, path in bundles():
        try:
            resources = table(path)
        except Exception:
            continue

        for resource_type, resource_name, size_a, size_b in resources:
            if resource_name in wanted:
                print(bundle, 'type', TYPES.get(resource_type, hex(resource_type)), wanted[resource_name], size_a, size_b)


def where(name, type_name):
    wanted, wanted_type = name_hash(name), name_hash(type_name)

    for bundle, path in bundles():
        try:
            resources = table(path)
        except Exception:
            continue

        for resource_type, resource_name, _, _ in resources:
            if resource_name == wanted and resource_type == wanted_type:
                print(bundle)

                return

    print('not found')


def list_bundle(path):
    data = b''.join(chunks(path))
    count = struct.unpack('<I', data[:4])[0]
    resources = [struct.unpack_from('<QQII', data, 0x104 + 24 * k) for k in range(count)]
    print(count, 'resources', dict(collections.Counter(TYPES.get(r[0], hex(r[0])) for r in resources)))

    # The resources follow the table, each with a header of 20 bytes and then what it holds
    position = 0x104 + 24 * count

    for k, (resource_type, resource_name, _, size) in enumerate(resources):
        type_name = TYPES.get(resource_type)

        if type_name and type_name.startswith('wwise'):
            print(k, type_name, hex(resource_name), 'size', size, 'header', data[position:position + 20].hex(' '))
            print('   starts with', data[position + 20:position + 20 + min(size, 120)].hex(' '))

        position += 20 + size


def unpack(path, out_path):
    total = 0

    with open(out_path, 'wb') as out:
        for chunk in chunks(path):
            out.write(chunk)
            total += len(chunk)

    print('decompressed', total, 'bytes')


if __name__ == '__main__':
    command, arguments = sys.argv[1], sys.argv[2:]

    if command == 'find':
        find(arguments)
    elif command == 'where':
        where(*arguments)
    elif command == 'list':
        list_bundle(arguments[0])
    elif command == 'unpack':
        unpack(*arguments)
    else:
        print('usage: bundles.py find <name> ... | where <name> <type> | list <bundle> | unpack <bundle> <out>')
