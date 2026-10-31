import re, struct, sys

# Looks into the engine's executable (vermintide2_dx12.exe) from the outside: what it says, what refers to a string, and what calls a
# function. It is how the mod's code could be checked against what the engine does where there is no source (the engine's own functions are
# not named, so the way in is a string that a function uses). Addresses are the RVAs of the memory image of the executable, in hex.
# Needs the pefile and capstone packages (pip install pefile capstone).
#
# Usage:
#   engine.py strings <exe> <start> <length>        the strings that are in that range, in the order they come
#   engine.py xref <exe> <string> [string ...]      where in the code each string is used (the instructions that load its address)
#   engine.py refs <exe> <address> [address ...]    the instructions that load an address (when the string's address is known)
#   engine.py callers <exe> <address>               the calls and jumps to a function
#   engine.py disassemble <exe> <address> <length>  the code at an address

import pefile


def image(path):
    pe = pefile.PE(path)

    return pe, pe.get_memory_mapped_image()


def strings(path, start, length):
    _, data = image(path)
    seen = []

    for match in re.finditer(rb'[ -~]{4,}', data[int(start, 16):int(start, 16) + int(length, 16)]):
        text = match.group(0).decode()

        if text not in seen:
            seen.append(text)

    print(len(seen), 'strings')
    print(' | '.join(seen[:220]))


def refs_to(data, targets):
    """The instructions that load an address (a lea or a mov of an address relative to the code), for each of the addresses."""
    found = []

    for i in range(len(data) - 7):
        if data[i] in (0x48, 0x4c) and data[i + 1] == 0x8d and (data[i + 2] & 0xc7) == 0x05:
            displacement = struct.unpack('<i', data[i + 3:i + 7])[0]

            if i + 7 + displacement in targets:
                found.append((i + 7 + displacement, i))

    return found


def xref(path, needles):
    _, data = image(path)
    targets = {}

    for needle in needles:
        address = data.find(needle.encode() + b'\0')
        print(needle, 'is at', hex(address))
        targets[address] = needle

    for target, at in refs_to(data, targets):
        print(targets[target], 'is loaded at', hex(at))


def refs(path, addresses):
    _, data = image(path)
    targets = {int(a, 16): a for a in addresses}

    for target, at in refs_to(data, targets):
        print(hex(target), 'is loaded at', hex(at))


def callers(path, address):
    _, data = image(path)
    target = int(address, 16)

    for i in range(len(data) - 5):
        if data[i] in (0xe8, 0xe9):
            displacement = struct.unpack('<i', data[i + 1:i + 5])[0]

            if i + 5 + displacement == target:
                print(hex(i))


def disassemble(path, address, length):
    import capstone

    _, data = image(path)
    start = int(address, 16)
    disassembler = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_64)

    for instruction in disassembler.disasm(data[start:start + int(length, 16)], start):
        print('%x: %s %s' % (instruction.address, instruction.mnemonic, instruction.op_str))


if __name__ == '__main__':
    command, path, arguments = sys.argv[1], sys.argv[2], sys.argv[3:]

    if command == 'strings':
        strings(path, *arguments)
    elif command == 'xref':
        xref(path, arguments)
    elif command == 'refs':
        refs(path, arguments)
    elif command == 'callers':
        callers(path, arguments[0])
    elif command == 'disassemble':
        disassemble(path, *arguments)
    else:
        print('usage: engine.py strings|xref|refs|callers|disassemble <exe> ...')
