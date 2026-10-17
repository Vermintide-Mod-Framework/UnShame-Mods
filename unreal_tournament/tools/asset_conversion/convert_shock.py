# Converts the UT2004 Shock Rifle (NewWeapons2004.ShockRifle). It was the first weapon, made before convert_weapon.py, and has units of
# its own in units/ut/shock, with its own names for the materials (m_body and m_power):
#   shock_rifle  the first person model: a geometry for each material, and the muzzle's node
#   pickup       the pickup (NewWeaponPickups.ShockPickupSM)
#   the body's texture (ShockRifleTex0) and its first and third person materials
#   scripts/mods/unreal_tournament/shock/skin_animations.lua: the root bone of the animations, as Lua
# The chamber (m_power) is a shader graph, made by make_chamber_material.py.
# Usage: convert_shock.py <export dir>
import struct, os, sys, subprocess
from formats import read_chunks as chunks, read_tga, write_png
from quat import qmul, qconj, rotate
from resources import texture_text
from convert_weapon import material_text

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
EXPORT = sys.argv[1]
UNITS = 'units/ut/shock'

# The meshes: (the export, the unit, the prefix of its geometries, its scale, the materials of m_body and m_power)
MESHES = [
    ('NewWeapons2004/SkeletalMesh/ShockRifle.psk', 'shock_rifle', 'g_shock', 0.0125, ('shock_rifle_fp_body', 'shock_rifle_fp_power')),
    ('NewWeaponPickups/StaticMesh/ShockPickupSM.pskx', 'pickup', 'g_pickup', 0.011, ('shock_rifle_body', 'shock_rifle_power')),
]

# ---------------------------------------------------------------- the meshes and their units
def unit_text(prefix, materials):
    text = 'materials = {\n\tm_body = "%s/%s"\n\tm_power = "%s/%s"\n}\nrenderables = {\n' % (UNITS, materials[0], UNITS, materials[1])

    for i in range(2):
        text += ('\t%s_%d = {\n\t\talways_keep = false\n\t\tculling = "disabled"\n\t\tgenerate_uv_unwrap = false\n\t\toccluder = false\n'
                 '\t\tshadow_caster = false\n\t\tsurface_queries = false\n\t\tviewport_visible = true\n\t}\n') % (prefix, i)

    return text + '}\n'

for psk_path, unit, prefix, scale, materials in MESHES:
    subprocess.check_call([sys.executable, os.path.join(os.path.dirname(__file__), 'psk2bsi.py'), EXPORT + '/' + psk_path,
                           '%s/%s/%s.bsi' % (REPO, UNITS, unit), prefix, 'm_body,m_power', str(scale)])
    open('%s/%s/%s.unit' % (REPO, UNITS, unit), 'w', newline='\n').write(unit_text(prefix, materials))

# ---------------------------------------------------------------- the body's texture and materials
texture = UNITS + '/shock_body_df'
w, h, rows = read_tga(EXPORT + '/UT2004Weapons/Texture/ShockRifleTex0.tga')
write_png('%s/%s.png' % (REPO, texture), w, h, rows)
open('%s/%s.texture' % (REPO, texture), 'w', newline='\n').write(texture_text(texture))
open('%s/%s/shock_rifle_fp_body.material' % (REPO, UNITS), 'w', newline='\n').write(
    material_text('opaque', texture, first_person=True, roughness=0.9))
open('%s/%s/shock_rifle_body.material' % (REPO, UNITS), 'w', newline='\n').write(material_text('opaque', texture, roughness=0.9, world=True))

# ---------------------------------------------------------------- animation keys
psk = chunks(EXPORT + '/NewWeapons2004/SkeletalMesh/ShockRifle.psk')
psa = chunks(EXPORT + '/NewWeapons2004/MeshAnimation/ShockRifle.psa')
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

lines = ['-- The animations of the UT2004 Shock Rifle (NewWeapons2004.ShockRifle): the pose of its root bone in each frame, relative to its mesh. A frame is',
         '-- a rotation of the mesh (x, y, z, w) and a move of it in UT units (right, forward, up).',
         "-- Generated from the psa by tools/asset_conversion/convert_shock.py: don't edit it by hand.", 'return {']
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
