# Makes the animations of the UT2004 Shock Rifle's model (its chamber is a shader graph, see make_chamber_material.py) as Lua:
# scripts/mods/unreal_tournament/shock/skin_animations.lua
# Usage: make_anim_assets.py <scratch dir>      (the dir has umodel/out3, the export of NewWeapons2004's ShockRifle, see README.md)
import struct, math, zlib, os, sys
from formats import read_chunks as chunks
from quat import qmul, qconj, rotate

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SCRATCH = sys.argv[1]
OUT = SCRATCH + '/umodel/out3'

# ---------------------------------------------------------------- animation keys
psk = chunks(OUT + '/NewWeapons2004/SkeletalMesh/ShockRifle.psk')
psa = chunks(OUT + '/NewWeapons2004/MeshAnimation/ShockRifle.psa')
s, c, b = psk['REFSKELT']
q_ref = struct.unpack_from('<4f', b, 76)
p_ref = struct.unpack_from('<3f', b, 92)
s, c, b = psa['ANIMINFO']
anims = []
for i in range(c):
    o = i * s
    name = b[o:o + 64].split(b'\0')[0].decode()
    tb, ri, kc, kq, kr, tt, rate, sb, first, num = struct.unpack_from('<4i3f3i', b, o + 128)
    anims.append((name, rate, first, num))
key_size, _, keys = psa['ANIMKEYS']

def to_model(v):  # psk (x forward, y left, z up) -> the model's (right, forward, up)
    return (-v[1], v[0], v[2])

def fmt(values):
    return ', '.join(('%.6f' % v).rstrip('0').rstrip('.') for v in values)

lines = ['-- The root bone of the animations of the UT2004 Shock Rifle (NewWeapons2004.ShockRifle), against its mesh, as a',
         '-- rotation of the mesh (x, y, z, w) and a move of it in UT units (right, forward, up): one row of the frames each.',
         '-- Made from the psa by make_anim_assets.py, never to be committed.', 'return {']
for name, rate, first, num in anims:
    if name == 'PutDown':
        continue  # the game has no animation of putting a weapon down
    lines.append('\t%s = {' % name)
    lines.append('\t\trate = %g,' % rate)
    lines.append('\t\tframes = {')
    for f in range(num):
        o = (first + f) * 2 * key_size
        p_a = struct.unpack_from('<3f', keys, o)
        q_a = struct.unpack_from('<4f', keys, o + 12)
        rd = qmul(q_a, qconj(q_ref))
        rp = rotate(rd, p_ref)
        move = tuple(p_a[i] - rp[i] for i in range(3))
        rx, ry, rz = to_model(rd[:3])
        mx, my, mz = to_model(move)
        lines.append('\t\t\t{ %s },' % fmt((rx, ry, rz, rd[3], mx, my, mz)))
    lines.append('\t\t},')
    lines.append('\t},')
lines.append('}')
open(REPO + '/scripts/mods/unreal_tournament/shock/skin_animations.lua', 'w', newline='\n').write('\n'.join(lines) + '\n')
print('animations', [(a[0], a[3]) for a in anims])
