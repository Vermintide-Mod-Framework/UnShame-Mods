import sys, os, struct, zlib, math, re

# Converts the first person model of a UT2004 weapon (a skeletal mesh and its animations, exported with UModel) to what this mod
# uses: one geometry for each material of each bone (the mesh is split by the bone that has most of a vertex: UT's weapons are
# rigid per bone), a node for each of those bones, a bsi, a unit, materials, textures, and the animations as Lua, with the pose
# of each bone for each frame.
# Usage: convert_weapon.py <weapon> <umodel export dir>      (weapons are in WEAPONS below)
# Needs the UModel export of the mesh, its animations and its textures (see README.md).

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))

# psk: the mesh, psa: the animations (UModel exports, relative to the export dir). materials: for each material of the mesh (in
# its order) the texture (a tga, relative to the export dir) and the kind ('opaque', 'alpha': see MATERIAL_KINDS). scale: meters a UT
# unit of the mesh is. animations: (name in the psa, name here). locators: bones with no mesh whose place is wanted (muzzle).
# skip_materials: materials (by index) whose faces are left out. A texture 'solid:rrggbb' is a plain color.
WEAPONS = {
    'flak': {
        'psk': 'Weapons/SkeletalMesh/Flak_1st.psk',
        'psa': 'Weapons/MeshAnimation/Flak_1st.psa',
        'materials': [('WeaponSkins/Texture/FlakTex0.tga', 'opaque'), ('WeaponSkins/Texture/FlakTex1.tga', 'opaque'),
                      ('WeaponSkins/Texture/FlakTex0.tga', 'opaque')],
        'scale': 0.0125,
        'animations': [('Pickup', 'Pickup'), ('Idle', 'Idle'), ('Fire', 'Fire'), ('AltFire', 'AltFire')],
        'locators': ['Bone_Flash'],
        # (UT's flak has no specular: its materials are plain textures)
        'roughness': 0.9,
        'unit': 'units/ut/flak/flak_cannon',
        'lua': 'scripts/mods/unreal_tournament/flak/skin_animations.lua',
    },
}

# ---------------------------------------------------------------- quaternions (x, y, z, w) and vectors
def qmul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)

def qconj(a):
    return (-a[0], -a[1], -a[2], a[3])

def rotate(q, v):
    return qmul(qmul(q, (v[0], v[1], v[2], 0)), qconj(q))[:3]

def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])

def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])

def to_model(v):  # psk (x forward, y left, z up) -> the model's (right, forward, up)
    return (-v[1], v[0], v[2])

def q_to_model(q):  # the same turn, in the model's axes (the vector part is turned by the change of axes)
    return to_model(q[:3]) + (q[3],)

def fmt(values):
    return ' '.join(('%.6f' % v).rstrip('0').rstrip('.') if round(v, 6) != 0 else '0' for v in values)

def chunks(path):
    d = open(path, 'rb').read()
    pos = 0
    ch = {}
    while pos + 32 <= len(d):
        cid = d[pos:pos + 20].split(b'\0')[0].decode('latin1')
        t, s, c = struct.unpack('<iii', d[pos + 20:pos + 32])
        ch[cid] = (s, c, d[pos + 32:pos + 32 + s * c])
        pos += 32 + s * c
    return ch

# ---------------------------------------------------------------- tga -> png
def read_tga(path):
    d = open(path, 'rb').read()
    idlen, cmtype, imgtype = d[0], d[1], d[2]
    w, h = struct.unpack('<HH', d[12:16])
    bpp, desc = d[16], d[17]
    bp = bpp // 8
    p = 18 + idlen
    px = bytearray()
    if imgtype == 2:
        px = bytearray(d[p:p + w * h * bp])
    else:
        while len(px) < w * h * bp:
            head = d[p]
            p += 1
            n = (head & 0x7f) + 1
            if head & 0x80:
                px += d[p:p + bp] * n
                p += bp
            else:
                px += d[p:p + n * bp]
                p += n * bp
    rows = []
    for y in range(h):
        sy = y if desc & 0x20 else h - 1 - y
        out = bytearray()
        for x in range(w):
            o = (sy * w + x) * bp
            out += bytes((px[o + 2], px[o + 1], px[o], px[o + 3] if bp == 4 else 255))
        rows.append(bytes(out))
    return w, h, rows

def write_png(path, w, h, rows):
    def chunk(tag, body):
        c = struct.pack('>I', len(body)) + tag + body
        return c + struct.pack('>I', zlib.crc32(tag + body) & 0xffffffff)
    raw = b''.join(b'\0' + r for r in rows)
    open(path, 'wb').write(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)) +
                           chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))

TEXTURE_TEMPLATE = '''common = {
	input = {
		filename = "%s"
	}
	output = {
		apply_processing = true
		category = "texture_categories/ut"
		cut_alpha_threshold = 0.5
		enable_cut_alpha_threshold = false
		format = "DXT5"
		mipmap_filter = "kaiser"
		mipmap_filter_wrap_mode = "mirror"
		mipmap_keep_original = false
		mipmap_num_smallest_steps_to_discard = 0
		resident_mips = 0
		srgb = true
		streamable = false
	}
}
win32 = {
	output = {
		mipmap_num_largest_steps_to_discard = 0
	}
}
'''

# (the weapons are lit by the level, as the game's own are: brighter in the sun and dark in the shade)
WEAPONS['rocket'] = {
    'psk': 'Weapons/SkeletalMesh/RocketLauncher_1st.psk',
    'psa': 'Weapons/MeshAnimation/RocketLauncher_1st.psa',
    'materials': [('WeaponSkins/Texture/RocketTex0.tga', 'opaque')],
    'scale': 0.0125,
    'animations': [('Pickup', 'Pickup'), ('Idle', 'Idle'), ('Fire', 'Fire'), ('AltFire', 'AltFire'), ('load', 'Load')],
    'locators': ['Bone_Flash'],
    'stretch': ('Bone_rod', 'Bone_weapon', 'bone_feed'),
    'roughness': 0.9,
    'unit': 'units/ut/rocket/rocket_launcher',
    'lua': 'scripts/mods/unreal_tournament/rocket/skin_animations.lua',
}

WEAPONS['bio'] = {
    # UT's body has no specular and only the glass of the tank shines (WeaponSkins.BioRifleGlassRef has a specular map and a reflection)
    'roughness': {0: 0.9, 1: 0.12},
    # the plunger's housing and the strip of goop in the tank are skinned to the weapon and to the plunger, and are stretched between them
    'stretch': [('Bone_housing', 'Bone_weapon', 'Bone_Plunger', (0,)), ('Bone_goop', 'Bone_weapon', 'Bone_Plunger', (2,))],
    'psk': 'Weapons/SkeletalMesh/BioRifle_1st.psk',
    'psa': 'Weapons/MeshAnimation/BioRifle_1st.psa',
    # the body, the glass of the tank, and what is in the tank (the bubbles)
    'materials': [('WeaponSkins/Texture/BioRifleTex0.tga', 'opaque'), ('WeaponSkins/Texture/BioRifleGlass0.tga', 'alpha', 0.5),
                  ('WeaponSkins/Texture/BRInnerBubbles.tga', 'alpha', 0.8)],
    'scale': 0.0125,
    'animations': [('Select', 'Pickup'), ('Idle', 'Idle'), ('Fire', 'Fire'), ('AltFire', 'AltFire'), ('HOLD', 'Hold')],
    'locators': ['Bone_Flash'],
    'unit': 'units/ut/bio/bio_rifle',
    'lua': 'scripts/mods/unreal_tournament/bio/skin_animations.lua',
}

WEAPONS['link'] = {
    # UT's body and glowing parts have no specular, and the glass (LinkGlassShader) is a reflection
    'roughness': {0: 0.9, 1: 0.9, 2: 0.12},
    'psk': 'NewWeapons2004/SkeletalMesh/FatLinkGun.psk',
    'psa': 'NewWeapons2004/MeshAnimation/LinkGun.psa',
    # the body, the glowing parts (the shader pans the green power texture over it), the glass
    'materials': [('UT2004Weapons/Texture/FatLinkGunTex0.tga', 'opaque'), ('UT2004Weapons/Texture/LinkPowerGreen.tga', 'alpha', 0.7),
                  ('UT2004Weapons/Texture/LinkPowerGreen.tga', 'alpha', 0.25)],
    'scale': 0.0125,
    'animations': [('Select', 'Pickup'), ('Idle', 'Idle'), ('Fire', 'Fire'), ('AltFire', 'AltFire')],
    'locators': ['bone flashA'],
    'unit': 'units/ut/link/link_gun',
    'lua': 'scripts/mods/unreal_tournament/link/skin_animations.lua',
}

# The Lightning Gun (Weapons.Sniper_1st). Its screen is SniperScreen1C, made by make_sniper_screen.py.
WEAPONS['sniper'] = {
    'psk': 'Weapons/SkeletalMesh/Sniper_1st.psk',
    'psa': 'Weapons/MeshAnimation/Sniper_1st.psa',
    # the body, the screen on its side (the scope's readout), and the second screen
    'materials': [('WeaponSkins/Texture/SniperTex0.tga', 'opaque'), ('WeaponSkins/Texture/SniperScreen1C.tga', 'opaque'),
                  ('WeaponSkins/Texture/SniperScreen2.tga', 'opaque')],
    'scale': 0.0125,
    'animations': [('Pickup', 'Pickup'), ('Idle', 'Idle'), ('Fire', 'Fire')],
    'locators': ['Bone_Flash'],
    'roughness': 0.9,
    'unit': 'units/ut/lightning/lightning_gun',
    'lua': 'scripts/mods/unreal_tournament/lightning/skin_animations.lua',
}

# The Sniper Rifle (UTClassic.ClassicSniperRifle: SniperAnims.SniperRifle_1st, with its textures in NewSniperRifle). Its second
# material is the back of the scope. It has three fire animations, which the shot picks from at random (ClassicSniperFire.FireAnims).
WEAPONS['classic_sniper'] = {
    'psk': 'SniperAnims/SkeletalMesh/SniperRifle_1st.psk',
    'psa': 'SniperAnims/MeshAnimation/SniperRifleAnims.psa',
    'materials': [('newsniperrifle/Texture/NewSniper1.tga', 'opaque'), ('newsniperrifle/Texture/sniper2.tga', 'opaque')],
    'scale': 0.0125,
    'animations': [('Pickup', 'Pickup'), ('Idle', 'Idle'), ('Fire1', 'Fire1'), ('Fire2', 'Fire2'), ('fire3', 'Fire3'), ('PutDown', 'PutDown')],
    'locators': ['Dummy01'],
    'roughness': 0.9,
    'unit': 'units/ut/sniper/sniper_rifle',
    'lua': 'scripts/mods/unreal_tournament/sniper/skin_animations.lua',
}

# The Minigun (Weapons.Minigun_1st). Its barrels and gear are turned by code (Minigun.UpdateRoll).
WEAPONS['minigun'] = {
    'psk': 'Weapons/SkeletalMesh/Minigun_1st.psk',
    'psa': 'Weapons/MeshAnimation/Minigun_1st.psa',
    'materials': [('WeaponSkins/Texture/MinigunTex0.tga', 'opaque')],
    'scale': 0.0125,
    'animations': [('Select', 'Pickup'), ('Idle', 'Idle'), ('Fire', 'Fire'), ('FireLoop', 'FireLoop'), ('FireEnd', 'FireEnd')],
    'locators': ['Bone Flash', 'Bone_CaseEjector'],
    'roughness': 0.9,
    'unit': 'units/ut/minigun/minigun',
    'lua': 'scripts/mods/unreal_tournament/minigun/skin_animations.lua',
}

# The Shield Gun (Weapons.ShieldGun_1st)
WEAPONS['shield'] = {
    'psk': 'Weapons/SkeletalMesh/ShieldGun_1st.psk',
    'psa': 'Weapons/MeshAnimation/ShieldGun_1st.psa',
    'materials': [('WeaponSkins/Texture/ShieldTex0.tga', 'opaque')],
    'scale': 0.0125,
    'animations': [('Select', 'Pickup'), ('Idle', 'Idle'), ('Charge', 'Charge'), ('Charged', 'Charged'), ('Fire', 'Fire'), ('Shield', 'Shield')],
    'locators': ['Bone_Flash'],
    'roughness': 0.9,
    'unit': 'units/ut/shield/shield_gun',
    'lua': 'scripts/mods/unreal_tournament/shield/skin_animations.lua',
}

# The Assault Rifle (NewWeapons2004.AssaultRifle, UT2004's own; the old one of UT2003 is Weapons.AssaultRifle_1st)
WEAPONS['assault'] = {
    'psk': 'NewWeapons2004/SkeletalMesh/AssaultRifle.psk',
    'psa': 'NewWeapons2004/MeshAnimation/AssaultRifle.psa',
    'materials': [('UT2004Weapons/Texture/AssaultRifleTex0.tga', 'opaque')],
    'scale': 0.0125,
    'animations': [('Select', 'Pickup'), ('Idle', 'Idle'), ('Fire', 'Fire'), ('AltFire', 'AltFire')],
    'locators': ['Bone_Flash a', 'Bone_Flash b'],
    'roughness': 0.9,
    'unit': 'units/ut/assault/assault_rifle',
    'mirror_unit': 'units/ut/assault/assault_rifle_left',
    'lua': 'scripts/mods/unreal_tournament/assault/skin_animations.lua',
}

# The Redeemer (Weapons.Redeemer_1st)
WEAPONS['redeemer'] = {
    'psk': 'Weapons/SkeletalMesh/Redeemer_1st.psk',
    'psa': 'Weapons/MeshAnimation/Redeemer_1st.psa',
    'materials': [('WeaponSkins/Texture/RedeemerTex0.tga', 'opaque')],
    'scale': 0.0125,
    'animations': [('Pickup', 'Pickup'), ('Idle', 'Idle'), ('Fire', 'Fire')],
    'locators': ['Bone_Flash'],
    'roughness': 0.9,
    'unit': 'units/ut/redeemer/redeemer',
    'lua': 'scripts/mods/unreal_tournament/redeemer/skin_animations.lua',
}

# UT2003's Shock Rifle (the model UT2004 keeps in Weapons.ukx).
WEAPONS['shock2003'] = {
    'psk': 'Weapons/SkeletalMesh/ShockRifle_1st.psk',
    'psa': 'Weapons/MeshAnimation/ShockRifle_1st.psa',
    # (the third is the red laser sight, which UT draws additively with a panning texture: here a faint red, unlit, with the mod's particle material that has the custom FOV of first person weapons, units/ut/fx/particle_weapon, a copy of particle with that option on)
    'materials': [('WeaponSkins/Texture/ShockTex0.tga', 'opaque'), ('WeaponSkins/Texture/ShockTex0.tga', 'opaque'),
                  ('solid:5c1410', 'additive')],
    'scale': 0.0125,
    # (the laser sight starts further back than it was converted)
    'shift': {2: (0, -15, 0)},
    'animations': [('Pickup', 'Pickup'), ('Idle', 'Idle'), ('Fire', 'Fire'), ('AltFire', 'AltFire')],
    'locators': ['Bone_flash01'],
    'unit': 'units/ut/shock2003/shock_rifle',
    'lua': 'scripts/mods/unreal_tournament/shock/skin_animations_2003.lua',
}

MATERIAL_TEMPLATES = {
    'additive': '''material_contexts = {
	surface_material = ""
}
parent_material = "units/ut/fx/particle_weapon"
textures = {
	texture_map = "%s"
}
variables = {
}
''',
    'opaque': '''material_contexts = {
	surface_material = ""
}
parent_material = "core/stingray_renderer/shader_import/standard"
textures = {
	color_map = "%s"
}
variables = {
	use_color_map = {
		type = "scalar"
		value = 1
	}
}
''',
    'alpha': '''material_contexts = {
	surface_material = ""
}
parent_material = "core/stingray_renderer/shader_import/standard_transparent"
textures = {
	color_map = "%s"
}
variables = {
	use_color_map = {
		type = "scalar"
		value = 1
	}
}
''',
}

def material_text(kind, texture, opacity=None, first_person=False, roughness=None, world=False):
    text = MATERIAL_TEMPLATES[kind] % texture

    if world:
        # (the material of a third person weapon fades out when the camera is close, as the game's characters do: units/ut/world_standard.material
        # and world_standard_transparent.material are the SDK's standard materials with the jitter transparency option on)
        text = text.replace('core/stingray_renderer/shader_import/standard', 'units/ut/world_standard')

    if first_person:
        # (the material of a first person weapon is drawn with the game's custom FOV for weapons, as the game's own are, which is also what keeps
        # the outlines of other players from being drawn over it: units/ut/weapon_standard.material and weapon_standard_transparent.material
        # are the SDK's standard materials with that option on)
        text = text.replace('core/stingray_renderer/shader_import/standard', 'units/ut/weapon_standard')

    if opacity is not None:
        # (a see through material: how much of it there is)
        text = text.rstrip('\n').rstrip('}') + '\topacity = {\n\t\ttype = "scalar"\n\t\tvalue = %s\n\t}\n}\n' % opacity

    if roughness is not None:
        # (the standard material's roughness is 0.33: shiny, which lights a small face at an angle in a color that is not its own)
        text = text.rstrip('\n').rstrip('}') + '\troughness = {\n\t\ttype = "scalar"\n\t\tvalue = %s\n\t}\n}\n' % roughness

    return text

def main():
    name, export = sys.argv[1], sys.argv[2]
    cfg = WEAPONS[name]
    scale = cfg['scale']
    unit_dir = os.path.dirname(cfg['unit'])
    os.makedirs(REPO + '/' + unit_dir, exist_ok=True)
    unit_base = os.path.basename(cfg['unit'])

    psk = chunks(export + '/' + cfg['psk'])
    psa = chunks(export + '/' + cfg['psa'])

    ps, pc, pb = psk['PNTS0000']
    points = [struct.unpack_from('<3f', pb, i * ps) for i in range(pc)]
    ws, wc, wb = psk['VTXW0000']
    wedges = []
    for i in range(wc):
        pi = struct.unpack_from('<H', wb, i * ws)[0] if ws == 16 else struct.unpack_from('<I', wb, i * ws)[0]
        u, v = struct.unpack_from('<2f', wb, i * ws + 4)
        wedges.append((pi, u, v))
    fkey = 'FACE0000' if 'FACE0000' in psk else 'FACE3200'
    fs, fc, fb = psk[fkey]
    faces = []
    for i in range(fc):
        if fkey == 'FACE0000':
            w0, w1, w2 = struct.unpack_from('<3H', fb, i * fs)
            mat = fb[i * fs + 6]
        else:
            w0, w1, w2 = struct.unpack_from('<3I', fb, i * fs)
            mat = fb[i * fs + 12]
        if mat not in cfg.get('skip_materials', ()):
            faces.append((w0, w1, w2, mat))
    # shift: { material: (x, y, z) in the psk's units } moves the points of that material's faces (none are shared with other materials)
    moved = {}
    for w0, w1, w2, mat in faces:
        if mat in cfg.get('shift', {}):
            for w in (w0, w1, w2):
                moved[wedges[w][0]] = cfg['shift'][mat]
    for pi, delta in moved.items():
        points[pi] = tuple(points[pi][k] + delta[k] for k in range(3))
    ms, mc, mb = psk['MATT0000']
    psk_materials = [mb[i * ms:i * ms + 64].split(b'\0')[0].decode('latin1') for i in range(mc)]
    assert len(cfg['materials']) >= mc, 'a texture for each of %s' % psk_materials

    # bones: name, parent, local rotation and position as stored
    bs, bc, bb = psk['REFSKELT']
    bone_names, parents, ref_q, ref_p = [], [], [], []
    for i in range(bc):
        o = i * bs
        bone_names.append(bb[o:o + 64].split(b'\0')[0].decode('latin1'))
        parents.append(struct.unpack_from('<i', bb, o + 72)[0] if i > 0 else -1)
        ref_q.append(struct.unpack_from('<4f', bb, o + 76))
        ref_p.append(struct.unpack_from('<3f', bb, o + 92))

    # the strongest bone of each point
    rs, rc, rb = psk['RAWWEIGHTS']
    best = {}
    for i in range(rc):
        weight, point, bone = struct.unpack_from('<fii', rb, i * rs)
        if point not in best or weight > best[point][0]:
            best[point] = (weight, bone)
    point_bone = [best[i][1] if i in best else 0 for i in range(pc)]

    # which way the stored rotations are to be read: the one that puts each bone where its own points are
    def world_bones(conj_root, conj_children, q_list, p_list):
        wq, wp = [], []
        for i in range(bc):
            q = q_list[i]
            if (i == 0 and conj_root) or (i > 0 and conj_children):
                q = qconj(q)
            if parents[i] < 0:
                wq.append(q)
                wp.append(p_list[i])
            else:
                pq, pp = wq[parents[i]], wp[parents[i]]
                wq.append(qmul(pq, q))
                wp.append(add(pp, rotate(pq, p_list[i])))
        return wq, wp

    centers = {}
    for i, p in enumerate(points):
        centers.setdefault(point_bone[i], []).append(p)
    best_error, convention = None, None
    for conj_root in (0, 1):
        for conj_children in (0, 1):
            wq, wp = world_bones(conj_root, conj_children, ref_q, ref_p)
            error = 0
            for b, plist in centers.items():
                c = tuple(sum(p[k] for p in plist) / len(plist) for k in range(3))
                error += math.sqrt(sum((c[k] - wp[b][k]) ** 2 for k in range(3))) * len(plist)
            print('convention conj_root', conj_root, 'conj_children', conj_children, 'error', round(error / pc, 1))
            # (when the rotations of the children make no difference to where they are, they are read as stored, as the importers of
            # the format read them)
            if best_error is None or error < best_error - 0.5 * pc:
                best_error, convention = error, (conj_root, conj_children)
    print('using', convention)
    bind_q, bind_p = world_bones(convention[0], convention[1], ref_q, ref_p)

    # geometry: a piece for each (bone, material), a face goes with the bone most of its points have
    # A 'stretch' is a part between two bones that is stretched as one of them moves away from the other (UT skins the points of the rod
    # of the Rocket Launcher's piston to two bones). It is a piece of its own, on a bone that is added, which the skin scales.
    # cfg['stretch'] is (the name of the added bone, one bone, the bone that moves), or a list of them. A fourth item is the materials the
    # part is of: there can be one part for each material between the same two bones.
    stretches = cfg.get('stretch') or []
    if stretches and not isinstance(stretches[0], tuple):
        stretches = [stretches]
    stretch_defs = []
    stretch_source = {}
    for entry in stretches:
        pair = set(bone_names.index(n) for n in entry[1:3])
        stretch_defs.append((len(bone_names), pair, entry[3] if len(entry) > 3 else None))
        stretch_source[len(bone_names)] = bone_names.index(entry[2])
        bone_names.append(entry[0])
    pieces = {}
    for w0, w1, w2, mat in faces:
        votes = [point_bone[wedges[w][0]] for w in (w0, w1, w2)]
        bone = max(set(votes), key=votes.count)
        for stretch_bone, pair, materials in stretch_defs:
            if set(votes) == pair and (materials is None or mat in materials):
                bone = stretch_bone
        pieces.setdefault((bone, mat), []).append((w0, w2, w1))  # the psk's front faces are clockwise
    used_bones = sorted(set(b for b, m in pieces))

    P = [(-p[1] * scale, p[0] * scale, p[2] * scale) for p in points]
    normals = [[0.0, 0.0, 0.0] for _ in P]
    for tris in pieces.values():
        for a, b, c in tris:
            pa, pb_, pc_ = wedges[a][0], wedges[b][0], wedges[c][0]
            e1, e2 = sub(P[pb_], P[pa]), sub(P[pc_], P[pa])
            n = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
            for pi in (pa, pb_, pc_):
                for k in range(3):
                    normals[pi][k] += n[k]
    def norm(a):
        l = math.sqrt(a[0] ** 2 + a[1] ** 2 + a[2] ** 2) or 1.0
        return (a[0] / l, a[1] / l, a[2] / l)
    normals = [norm(n) for n in normals]

    def sjson_node_name(i):
        # (lower case: a geometry with a capital in its name is dropped from the unit by the compiler, and the units that have none are the ones
        # that were all in lower case; the node names are in lower case with them)
        return 'b_' + re.sub(r'[^A-Za-z0-9_]', '_', bone_names[i]).lower()

    def fl(values):
        return ' '.join(str(int(v)) if float(v).is_integer() else repr(float('%.7g' % v)) for v in values)

    def il(values):
        return ' '.join(str(v) for v in values)

    def stream(sname, ctype, stride, values, size):
        return ('\t\t\t{\n\t\t\t\tchannels = [ {\n\t\t\t\t\t\tindex = 0\n\t\t\t\t\t\tname = "%s"\n\t\t\t\t\t\ttype = "%s"\n\t\t\t\t\t} ]\n'
                '\t\t\t\tdata = [ %s ]\n\t\t\t\tsize = %d\n\t\t\t\tstride = %d\n\t\t\t}') % (sname, ctype, values, size, stride)

    # The unit, and with 'mirror_unit' a copy of it mirrored from left to right (for a weapon held in each hand, as UT draws its second
    # Assault Rifle): its points and normals go to the other side, and its triangles are turned the other way round, so that their
    # front faces stay the ones that are drawn. Both use the same materials.
    variants = [(cfg['unit'], False)] + ([(cfg['mirror_unit'], True)] if cfg.get('mirror_unit') else [])
    unmirrored_P, unmirrored_normals, unmirrored_pieces = P, normals, pieces
    for unit_path, mirrored in variants:
        if mirrored:
            P = [(-x, y, z) for x, y, z in unmirrored_P]
            normals = [(-x, y, z) for x, y, z in unmirrored_normals]
            pieces = {key: [(a, c, b) for a, b, c in tris] for key, tris in unmirrored_pieces.items()}
        else:
            P, normals, pieces = unmirrored_P, unmirrored_normals, unmirrored_pieces
        shared = [
            stream('POSITION', 'CT_FLOAT3', 12, fl([c for p in P for c in p]), len(P)),
            stream('NORMAL', 'CT_FLOAT3', 12, fl([c for n in normals for c in n]), len(normals)),
            stream('TEXCOORD', 'CT_FLOAT2', 8, fl([x for pi, u, v in wedges for x in (u, 1.0 - v)]), len(wedges)),
        ]
        identity = '1 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1'
        geometries, nodes, renderables = [], {}, []
        for (bone, mat), tris in sorted(pieces.items()):
            gname = 'g_%s_%d' % (sjson_node_name(bone)[2:], mat)
            pos_idx, uv_idx, bin_data, tan_data = [], [], [], []
            for a, b, c in tris:
                pa, pb_, pc_ = wedges[a][0], wedges[b][0], wedges[c][0]
                pos_idx += [pa, pb_, pc_]
                uv_idx += [a, b, c]
                e1, e2 = sub(P[pb_], P[pa]), sub(P[pc_], P[pa])
                du1, dv1 = wedges[b][1] - wedges[a][1], wedges[b][2] - wedges[a][2]
                du2, dv2 = wedges[c][1] - wedges[a][1], wedges[c][2] - wedges[a][2]
                det = du1 * dv2 - du2 * dv1
                if abs(det) < 1e-12:
                    t, bn = (1.0, 0.0, 0.0), (0.0, 1.0, 0.0)
                else:
                    r = 1.0 / det
                    t = norm(tuple((e1[k] * dv2 - e2[k] * dv1) * r for k in range(3)))
                    bn = norm(tuple((e2[k] * du1 - e1[k] * du2) * r for k in range(3)))
                for _ in range(3):
                    tan_data += list(t)
                    bin_data += list(bn)
            n_idx = len(pos_idx)
            seq = list(range(n_idx))
            streams = shared + [stream('BINORMAL', 'CT_FLOAT3', 12, fl(bin_data), n_idx), stream('TANGENT', 'CT_FLOAT3', 12, fl(tan_data), n_idx)]
            index_streams = [pos_idx, pos_idx, uv_idx, seq, seq]
            geometries.append(
                '\t%s = {\n\t\tindices = {\n\t\t\tsize = %d\n\t\t\tstreams = [ %s ]\n\t\t\ttype = "TRIANGLE_LIST"\n\t\t}\n'
                '\t\tmaterials = [\n\t\t\t{\n\t\t\t\tname = "m_%d"\n\t\t\t\tprimitives = [ %s ]\n\t\t\t} ]\n'
                '\t\tsmoothing = [ %s ]\n\t\tstreams = [\n%s ]\n\t}\n'
                % (gname, n_idx, ' '.join('[ %s ]' % il(s) for s in index_streams), mat, il(range(len(tris))), il([1] * len(tris)), '\n'.join(streams)))
            nodes.setdefault(bone, []).append(gname)
            renderables.append(gname)
            print('geometry', gname, 'triangles', len(tris))

        # a node for each bone that has a mesh (the pieces hang off it) and for each locator
        locator_bones = [bone_names.index(n) for n in cfg['locators']]
        node_text = []
        for bone in used_bones:
            node_text.append('\t\t\t%s = {\n\t\t\t\tgeometries = [ %s ]\n\t\t\t\tlocal = [ %s ]\n\t\t\t\tparent = "root"\n\t\t\t}\n'
                             % (sjson_node_name(bone), ' '.join('"%s"' % g for g in nodes[bone]), identity))
        for bone in locator_bones:
            node_text.append('\t\t\t%s = {\n\t\t\t\tlocal = [ %s ]\n\t\t\t\tparent = "root"\n\t\t\t}\n' % (sjson_node_name(bone), identity))
        text = ('\ngeometries = {\n%s}\nnodes = {\n\troot = {\n\t\tchildren = {\n%s\t\t}\n\t\tlocal = [ %s ]\n\t}\n}\nsource_path = "convert_weapon"\n'
                % (''.join(geometries), ''.join(node_text), identity))
        raw = text.encode('latin1')
        open('%s/%s.bsi' % (REPO, unit_path), 'wb').write(b'bsiz' + struct.pack('<I', len(raw)) + zlib.compress(raw))
        print('wrote', unit_path + '.bsi', len(raw), 'bytes raw')

        # the unit, the materials and the textures
        used_materials = sorted(set(m for b, m in pieces))
        unit_text = 'materials = {\n' + ''.join('\tm_%d = "%s/%s_m%d"\n' % (m, unit_dir, unit_base, m) for m in used_materials) + '}\nrenderables = {\n'
        # (the renderables of a unit are the nodes that have geometry, by the name of the node: the geometries of a node are its pieces)
        for g in [sjson_node_name(b) for b in used_bones]:
            unit_text += ('\t%s = {\n\t\talways_keep = false\n\t\tculling = "disabled"\n\t\tgenerate_uv_unwrap = false\n\t\toccluder = false\n'
                          '\t\tshadow_caster = false\n\t\tsurface_queries = false\n\t\tviewport_visible = true\n\t}\n') % g
        unit_text += '}\n'
        open('%s/%s.unit' % (REPO, unit_path), 'w', newline='\n').write(unit_text)
    P, normals, pieces = unmirrored_P, unmirrored_normals, unmirrored_pieces
    done_textures = {}
    for m in used_materials:
        tga, kind = cfg['materials'][m][:2]
        opacity = cfg['materials'][m][2] if len(cfg['materials'][m]) > 2 else None
        tname = os.path.splitext(os.path.basename(tga))[0].lower().replace(':', '_')
        texture = '%s/%s_%s' % (unit_dir, unit_base, tname)
        if texture not in done_textures:
            if tga.startswith('solid:'):
                color = bytes(int(tga[6 + 2 * i:8 + 2 * i], 16) for i in range(3)) + bytes([255])
                w, h, rows = 4, 4, [color * 4] * 4
            else:
                w, h, rows = read_tga(export + '/' + tga)
            write_png('%s/%s.png' % (REPO, texture), w, h, rows)
            open('%s/%s.texture' % (REPO, texture), 'w', newline='\n').write(TEXTURE_TEMPLATE % texture)
            done_textures[texture] = True
        open('%s/%s/%s_m%d.material' % (REPO, unit_dir, unit_base, m), 'w', newline='\n').write(material_text(kind, texture, opacity, first_person=True, roughness=cfg['roughness'].get(m) if isinstance(cfg.get('roughness'), dict) else cfg.get('roughness')))

    # the animations: the pose of each bone (the root's move first: it is how the whole mesh is moved) against the mesh in its
    # reference pose, in the model's axes and UT units
    pis, pic, pib = psa['ANIMINFO']
    anims = {}
    for i in range(pic):
        o = i * pis
        aname = pib[o:o + 64].split(b'\0')[0].decode()
        tb, ri, kc, kq, kr, tt, rate, sbn, first, num = struct.unpack_from('<4i3f3i', pib, o + 128)
        anims[aname] = (rate, first, num)
    ks, _, keys = psa['ANIMKEYS']
    abs_, abc, abb = psa['BONENAMES']
    anim_bones = [abb[i * abs_:i * abs_ + 64].split(b'\0')[0].decode('latin1') for i in range(abc)]
    bone_index_in_anim = {bone_names.index(n): i for i, n in enumerate(anim_bones)}
    animated = [0] + [b for b in used_bones + locator_bones if b != 0]
    animated = list(dict.fromkeys(animated))
    lines = ['-- The animations of a UT2004 weapon: the pose of each bone in each frame, made by convert_weapon.py from its psa, never to',
             '-- be committed. A pose is a rotation (x, y, z, w) and a move (right, forward, up in UT units) of what hangs off the bone',
             '-- against the mesh in its reference pose. The first bone is the root: its move is the move of the whole mesh.',
             'return {', '\tbones = {']
    for b in animated:
        lines.append('\t\t"%s",' % (sjson_node_name(b) if b != 0 else 'root'))
    lines.append('\t},')
    lines.append('\tanimations = {')
    n_key_bones = abc

    def pose_frame(frame, conj_children):
        # the keys of a frame are stored for every bone of the animation one after the other
        frame_base = frame * n_key_bones
        wq, wp = [], []
        for b in range(bc):
            if b in bone_index_in_anim:
                o = (frame_base + bone_index_in_anim[b]) * ks
                p_a = struct.unpack_from('<3f', keys, o)
                q_a = struct.unpack_from('<4f', keys, o + 12)
            else:
                # (a bone that the animation doesn't have stays as it is in the mesh)
                p_a, q_a = ref_p[b], ref_q[b]
            if (b == 0 and convention[0]) or (b > 0 and conj_children):
                q_a = qconj(q_a)
            if parents[b] < 0:
                wq.append(q_a)
                wp.append(p_a)
            else:
                wq.append(qmul(wq[parents[b]], q_a))
                wp.append(add(wp[parents[b]], rotate(wq[parents[b]], p_a)))
        skin_q, skin_p = [], []
        for b in range(bc):
            q_s = qmul(wq[b], qconj(bind_q[b]))
            skin_q.append(q_s)
            skin_p.append(sub(wp[b], rotate(q_s, bind_p[b])))
        root_inverse = qconj(skin_q[0])
        poses = []
        for b in animated:
            # (a stretch has the pose of the bone that moves, which the skin reads as how far to stretch it)
            source = stretch_source.get(b, b)
            if b == 0:
                q, p = skin_q[0], skin_p[0]
            else:
                # against the root's move (the root is placed by the skin as a whole)
                q = qmul(root_inverse, skin_q[source])
                p = rotate(root_inverse, sub(skin_p[source], skin_p[0]))
            if b in locator_bones:
                # a node of a bone with no mesh is at the bone, not at the origin of the mesh
                p = add(p, rotate(q, bind_p[b]))
            poses.append((b, (q, p)))
        return poses

    # how the children's rotations of the animation are read: the way that keeps the pieces of the Idle animation, where nothing
    # but the weapon sways, nearest to the weapon (a bone that moves a lot in it is read wrong)
    idle_rate, idle_first, idle_num = anims['Idle']
    best_motion, conj_children_anim = None, 0
    for conj_children in (0, 1):
        motion = 0
        for f in range(idle_num):
            for b, (q, p) in pose_frame(idle_first + f, conj_children):
                if b != 0 and b not in locator_bones:
                    motion += math.sqrt(p[0] ** 2 + p[1] ** 2 + p[2] ** 2)
        print('children conjugated', conj_children, 'motion in Idle', round(motion, 1))
        if best_motion is None or motion < best_motion - 1:
            best_motion, conj_children_anim = motion, conj_children
    for aname, new_name in cfg['animations']:
        rate, first, num = anims[aname]
        lines.append('\t\t%s = {' % new_name)
        lines.append('\t\t\trate = %g,' % rate)
        lines.append('\t\t\tframes = {')
        for f in range(num):
            row = []
            for b, (q, p) in pose_frame(first + f, conj_children_anim):
                row.extend(q_to_model(q) + to_model(p))
            lines.append('\t\t\t\t{ %s },' % ', '.join(fmt([v]) for v in row))
        lines.append('\t\t\t},')
        lines.append('\t\t},')
        print('animation', new_name, num, 'frames', 'rate', rate)
    lines.append('\t},')
    lines.append('}')
    open('%s/%s' % (REPO, cfg['lua']), 'w', newline='\n').write('\n'.join(lines) + '\n')

if __name__ == '__main__':
    main()
