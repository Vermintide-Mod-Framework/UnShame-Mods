import multiprocessing, os, re, sys, time

import vt1_bundles

# Writes the strings of Vermintide 1's bundles that could be names, each with its hash: "<hash> <string>" a line.
# The compiled resources keep names only as hashes, and these strings (in the game's Lua, flow, units, packages and so on)
# give the names of most of them. Textures, meshes and sounds have none, so only bundles with other resources are read.
#
# The bundles are read in batches. Each batch's strings are saved in a folder next to the out file as it finishes,
# so a run that is stopped goes on from the next batch.
#
# Usage: vt1_strings.py <Vermintide 1 dir> <out file> [bundles a batch]

PATH = re.compile(rb'[a-z0-9_]+(?:/[a-z0-9_.\-]+)+')
WORD = re.compile(rb'[A-Za-z_][A-Za-z0-9_]{2,}')

# The resources whose data has names in it
TYPES = {vt1_bundles.name_hash(t) for t in ('lua', 'flow', 'level', 'package', 'unit', 'config', 'data', 'strings', 'state_machine',
                                              'network_config', 'particles', 'material', 'shading_environment', 'physics_properties')}

BATCH_SIZE = 200


def _strings(path):
    found = set()

    try:
        if not vt1_bundles.types(path) & TYPES:
            return found

        for type_hash, _, variants in vt1_bundles.resources(path):
            if type_hash not in TYPES:
                continue

            for data in variants:
                for pattern in (PATH, WORD):
                    found.update(m.group().decode() for m in pattern.finditer(data))
    except Exception as error:
        print('%s: %s' % (path, error), flush=True)

    return found


def main():
    vt1_dir, out_path = sys.argv[1:3]
    batch_size = int(sys.argv[3]) if len(sys.argv) > 3 else BATCH_SIZE
    bundle_dir = os.path.join(vt1_dir, 'bundle')
    paths = sorted(os.path.join(bundle_dir, f) for f in os.listdir(bundle_dir) if not f.endswith('.stream'))
    batches = [paths[k:k + batch_size] for k in range(0, len(paths), batch_size)]
    batch_dir = out_path + '.batches'
    os.makedirs(batch_dir, exist_ok=True)
    start = time.time()

    with multiprocessing.Pool() as pool:
        for k, batch in enumerate(batches):
            batch_path = os.path.join(batch_dir, '%04d.txt' % k)

            if os.path.exists(batch_path):
                continue

            found = set()

            for strings in pool.imap_unordered(_strings, batch):
                found |= strings

            with open(batch_path + '.part', 'w', encoding='utf8', newline='\n') as out:
                out.write('\n'.join(sorted(found)))

            os.replace(batch_path + '.part', batch_path)
            print('batch %d of %d: %d strings, %.0f s so far' % (k + 1, len(batches), len(found), time.time() - start), flush=True)

    found = set()

    for k in range(len(batches)):
        with open(os.path.join(batch_dir, '%04d.txt' % k), encoding='utf8') as f:
            found.update(s for s in f.read().split('\n') if s)

    with open(out_path, 'w', encoding='utf8', newline='\n') as out:
        for s in sorted(found):
            out.write('%016x %s\n' % (vt1_bundles.name_hash(s), s))

    print('%d strings written to %s' % (len(found), out_path), flush=True)


if __name__ == '__main__':
    main()
