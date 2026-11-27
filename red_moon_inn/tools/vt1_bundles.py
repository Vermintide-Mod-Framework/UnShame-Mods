import os, struct, zlib

# Reads the bundles of Vermintide 1 (<game dir>/bundle).
# A bundle is a header of 12 bytes and then zlib chunks; a chunk that is 64 KB long is stored as it is.
# What they hold starts with the number of resources, 256 bytes, and a table of the resources: a type and a name,
# as hashes, 16 bytes each in the first bundles and 20 (with flags) in the patches.
# Each resource follows as its type, name, number of variants and stream offset, the variants' language and sizes, and their data.
# A patch of a bundle is a file of the same name with ".patch_NNN" after it, and the last patch that has a resource has its newest version.
# Names are hashed with the 64 bit MurmurHash of the engine, and the bundles hold the hashes only.

MULTIPLIER = 0xc6a4a7935bd1e995
MASK = (1 << 64) - 1


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


def name_hash32(name):
    """The 32 bit hash the engine uses in some places: the top half of the 64 bit one."""
    return name_hash(name) >> 32


def chunks(path):
    with open(path, 'rb') as f:
        f.read(12)

        while True:
            raw = f.read(4)

            if len(raw) < 4:
                return

            size = struct.unpack('<I', raw)[0]
            data = f.read(size)
            yield data if size == 0x10000 else zlib.decompress(data)


def _table_entry_size(data, count):
    """16 or 20: the first resource after the table starts with the type and name of the table's first entry."""
    for entry_size in (16, 20):
        pos = 0x104 + entry_size * count

        if data[pos:pos + 16] == data[0x104:0x114]:
            return entry_size

    raise ValueError('the table of resources is not 16 or 20 bytes an entry')


def types(path):
    """The types of a bundle's resources, from its first chunks only."""
    data = b''

    for chunk in chunks(path):
        data += chunk
        count = struct.unpack_from('<I', data, 0)[0]

        if len(data) >= 0x104 + 20 * count + 16:
            break

    entry_size = _table_entry_size(data, count)
    return {struct.unpack_from('<Q', data, 0x104 + entry_size * k)[0] for k in range(count)}


def resources(path):
    """The resources of a bundle, as (type hash, name hash, [data of each variant])."""
    data = b''.join(chunks(path))
    count = struct.unpack_from('<I', data, 0)[0]
    pos = 0x104 + _table_entry_size(data, count) * count

    for _ in range(count):
        if pos + 24 > len(data):
            return

        type_hash, name, variant_count, _ = struct.unpack_from('<QQII', data, pos)
        pos += 24
        sizes = []

        for _ in range(variant_count):
            _, size, _ = struct.unpack_from('<III', data, pos)
            sizes.append(size)
            pos += 12

        variants = []

        for size in sizes:
            variants.append(data[pos:pos + size])
            pos += size

        yield type_hash, name, variants


def bundle_files(bundle_dir, bundle):
    """The bundle and its patches, oldest first."""
    patches = sorted(f for f in os.listdir(bundle_dir) if f.startswith(bundle + '.patch_') and not f.endswith('.stream'))
    return [os.path.join(bundle_dir, bundle)] + [os.path.join(bundle_dir, f) for f in patches]


def newest_resource(bundle_dir, bundle, name, type_name):
    """The newest version of a resource of a bundle and its patches, and the file it was in."""
    wanted = (name_hash(type_name), name_hash(name))
    found = None

    for path in bundle_files(bundle_dir, bundle):
        for type_hash, name_h, variants in resources(path):
            if (type_hash, name_h) == wanted:
                found = (variants[0], path)

    if found is None:
        raise KeyError('%s %s is not in bundle %s' % (name, type_name, bundle))

    return found
