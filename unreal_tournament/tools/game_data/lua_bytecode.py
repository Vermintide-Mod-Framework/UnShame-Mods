import os, re, sys

# Finds the compiled Lua (LuaJIT bytecode) in a file, such as an unpacked bundle (bundles.py unpack) or a mod's bundle, and writes each
# piece to a file of its own. The pieces are named by the chunk name that is in them ("@scripts/mods/<mod>/<file>"), and can be turned back into
# text with a LuaJIT decompiler (luajit-decompiler-v2).
#
# Usage:
#   lua_bytecode.py extract <file> <out dir>      writes every piece, as <out dir>/<chunk name>c, and lists them
#   lua_bytecode.py names <file> [pattern]         the chunk names in the file (a pattern is a regular expression to match, "scripts/" by default)

SIGNATURE = b'\x1bLJ'


def read_uleb(buffer, position):
    value, shift = 0, 0

    while True:
        byte = buffer[position]
        position += 1
        value |= (byte & 0x7f) << shift

        if not byte & 0x80:
            return value, position

        shift += 7


def extract(path, out_dir):
    data = open(path, 'rb').read()
    os.makedirs(out_dir, exist_ok=True)
    count = 0

    for match in re.finditer(re.escape(SIGNATURE), data):
        start = match.start()
        # (the signature and the version, then the flags: bit 2 is that the names are stripped, and then the pieces, each with its length,
        # until one of 0)
        position = start + 4
        flags, position = read_uleb(data, position)
        name = ''

        if not flags & 2:
            length, position = read_uleb(data, position)
            name = data[position:position + length].decode('latin1')
            position += length

        while True:
            length, position = read_uleb(data, position)

            if length == 0:
                break

            position += length

        file_name = name.lstrip('@') or 'stripped_%d' % start
        target = os.path.join(out_dir, file_name.replace('/', os.sep)) + 'c'
        os.makedirs(os.path.dirname(target), exist_ok=True)
        open(target, 'wb').write(data[start:position])
        count += 1
        print(flags, position - start, file_name)

    print(count, 'pieces')


def names(path, pattern):
    data = open(path, 'rb').read()
    print('bytecode pieces:', len(re.findall(re.escape(SIGNATURE), data)))
    found = {}

    for match in re.finditer(rb'@?(?:' + pattern.encode() + rb')[A-Za-z0-9_/.]*', data):
        found.setdefault(match.group(0).decode(), []).append(match.start())

    for name in sorted(found):
        print(name, found[name][:2])


if __name__ == '__main__':
    command, arguments = sys.argv[1], sys.argv[2:]

    if command == 'extract':
        extract(*arguments)
    elif command == 'names':
        names(arguments[0], arguments[1] if len(arguments) > 1 else 'scripts/')
    else:
        print('usage: lua_bytecode.py extract <file> <out dir> | names <file> [pattern]')
