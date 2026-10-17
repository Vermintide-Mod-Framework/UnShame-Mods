import sys, os, math, struct, subprocess, tempfile

# Converts static meshes of UT2004 (the pickups of the weapons, the meshes of the projectiles, and the third person meshes of the weapons in
# their reference pose), exported with UModel as pskx or psk, to units: a bsi (psk2bsi.py), a unit, a material and a texture.
# Usage: convert_static.py <name> <umodel export dir>      (the meshes are in STATICS below)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.dirname(__file__))
from convert_weapon import material_text
from formats import read_tga, write_png, chunk_offsets
from resources import texture_text

# pskx: the mesh; materials: the texture (tga) and kind of each material of it; roughness: of the materials, one for all or
# { index = roughness } (0.9 if not given: matte, as UT's weapon bodies are plain textures with no specular; only what shines in UT
# has less, such as the Bio Rifle's glass); scale: meters a UT unit of the mesh is as it is drawn; culling: of the unit's meshes
# ("disabled" if not given, so that the engine doesn't cull them by their distance: small ones vanished at a distance)
# (the DrawScale of its actor is in it: a pickup of the weapon in the hand is 0.011, 0.02 meters a unit and 0.55)
STATICS = {
    'flak_pickup': {
        'pskx': 'WeaponStaticMesh/StaticMesh/FlakCannonPickup.pskx',
        'materials': [('WeaponSkins/Texture/Flak3rdperson.tga', 'opaque')],
        'scale': 0.011,
        'unit': 'units/ut/flak/pickup',
    },
    # The Flak Cannon's third person mesh (FlakAttachment's Weapons.Flak_3rd, at xWeaponAttachment's DrawScale 0.4), with the pickup's
    # material, which has the same texture (Flak3rdperson)
    'flak_3rd': {
        'pskx': 'Weapons/SkeletalMesh/Flak_3rd.psk',
        'materials': [('units/ut/flak/pickup_m0', 'existing')],
        'scale': 0.02 * 0.4,
        'unit': 'units/ut/flak/third_person',
    },
    'shock2003_pickup': {
        'pskx': 'WeaponStaticMesh/StaticMesh/ShockRiflePickup.pskx',
        'materials': [('WeaponSkins/Texture/ShockTex0.tga', 'opaque')],
        'scale': 0.011,
        'unit': 'units/ut/shock2003/pickup',
    },
    'flak_chunk': {
        'pskx': 'WeaponStaticMesh/StaticMesh/FlakChunk.pskx',
        'materials': [('WeaponSkins/Texture/FlakChunkTex.tga', 'opaque')],
        'scale': 0.28,
        'unit': 'units/ut/flak/chunk',
        'culling': 'disabled',
    },
    'link_pickup': {
        'pskx': 'WeaponStaticMesh/StaticMesh/LinkGunPickup.pskx',
        'materials': [('WeaponSkins/Texture/LinkTex0.tga', 'opaque')],
        'scale': 0.012,
        'unit': 'units/ut/link/pickup',
    },
    'bio_pickup': {
        'pskx': 'WeaponStaticMesh/StaticMesh/BioRiflePickup.pskx',
        'materials': [('WeaponSkins/Texture/BioRifleTex0.tga', 'opaque'), ('WeaponSkins/Texture/BioRifleGlass0.tga', 'alpha', 0.5)],
        # (the glass of the tank shines, as the first person's does: WeaponSkins.BioRifleGlassRef has a specular map and a reflection)
        'roughness': {0: 0.9, 1: 0.12},
        'scale': 0.012,
        'unit': 'units/ut/bio/pickup',
    },
    'rocket_pickup': {
        'pskx': 'WeaponStaticMesh/StaticMesh/RocketLauncherPickup.pskx',
        'materials': [('WeaponSkins/Texture/RocketTex0.tga', 'opaque')],
        'scale': 0.009,
        'unit': 'units/ut/rocket/pickup',
    },
    'sniper_pickup': {
        'pskx': 'WeaponStaticMesh/StaticMesh/SniperRiflePickup.pskx',
        'materials': [('WeaponSkins/Texture/SniperTex0.tga', 'opaque')],
        'scale': 0.009,
        'unit': 'units/ut/lightning/pickup',
    },
    'minigun_pickup': {
        'pskx': 'WeaponStaticMesh/StaticMesh/MinigunPickup.pskx',
        'materials': [('WeaponSkins/Texture/MinigunTex0.tga', 'opaque')],
        'scale': 0.01,
        'unit': 'units/ut/minigun/pickup',
    },
    # The Minigun's third person mesh (MinigunAttachment's Weapons.Minigun_3rd, at xWeaponAttachment's DrawScale 0.4), with the pickup's
    # material, which has the same texture (MinigunTex0). parts: the barrels, which UT turns by their bone (MinigunAttachment.UpdateRoll),
    # are a geometry of their own (see psk2bsi.py), so that the skin can turn them too.
    'minigun_3rd': {
        'pskx': 'Weapons/SkeletalMesh/Minigun_3rd.psk',
        'materials': [('units/ut/minigun/pickup_m0', 'existing')],
        'parts': {'Bone Barrels': 'barrels'},
        'scale': 0.02 * 0.4,
        'unit': 'units/ut/minigun/third_person',
    },
    'shield_pickup': {
        'pskx': 'WeaponStaticMesh/StaticMesh/ShieldGunPickup.pskx',
        'materials': [('WeaponSkins/Texture/ShieldTex0.tga', 'opaque')],
        'scale': 0.01,
        'unit': 'units/ut/shield/pickup',
    },
    # The third person: the mesh of the weapon's attachment class (ShieldAttachment), which UT draws in a player's hand at
    # xWeaponAttachment's DrawScale 0.4. It is a skeletal mesh, taken in its reference pose.
    'shield_3rd': {
        'pskx': 'Weapons/SkeletalMesh/ShieldGun_3rd.psk',
        'materials': [('WeaponSkins/Texture/ShieldTex0.tga', 'opaque')],
        'scale': 0.02 * 0.4,
        # (UT's ShieldTex0 is a plain texture, with no specular: matte, as the other weapons' bodies)
        'roughness': 0.9,
        'unit': 'units/ut/shield/third_person',
        # UT's mesh puts the same part of the texture on both sides of the gun, flipped on one side, so the writing there reads backwards on
        # that side (in UT too, where it is seen less). This mod departs from UT for its two big labels: see reflect_labels. Each is the
        # middle of its writing in pixels of the texture, the angle the writing runs at (degrees, clockwise from the right), and how far
        # the label reaches along the writing and across it.
        'labels': [
            (310, 201, 0, 36, 22),  # 16V
            (255, 888, -45, 50, 24),  # 316V
        ],
    },
    # The Shock Rifle's third person: ShockAttachment's mesh (NewWeapons2004.NewShockRifle_3rd at xWeaponAttachment's DrawScale 0.4). Its
    # materials are the pickup's: the body (ShockRifleTex0) and the chamber, the gel and glass of make_chamber_material.py (UT's
    # PurpleShockFinal has the same graph as the first person's ShockPowerFinal, with a constant colour in place of ShockControl).
    'shock_3rd': {
        'pskx': 'NewWeapons2004/SkeletalMesh/NewShockRifle_3rd.psk',
        'materials': [('units/ut/shock/shock_rifle_body', 'existing'), ('units/ut/shock/shock_rifle_power', 'existing')],
        'scale': 0.02 * 0.4,
        'unit': 'units/ut/shock/third_person',
    },
    # UT2003's Shock Rifle third person (Weapons.ShockRifle_3rd, its ShockAttachment's mesh before UT2004's), for the UT2003 look, with the
    # UT2003 pickup's material (ShockTex0)
    'shock2003_3rd': {
        'pskx': 'Weapons/SkeletalMesh/ShockRifle_3rd.psk',
        'materials': [('units/ut/shock2003/pickup_m0', 'existing')],
        'scale': 0.02 * 0.4,
        'unit': 'units/ut/shock2003/third_person',
    },
    # The Sniper Rifle (UTClassic): its third person mesh (ClassicSniperAttachment, NewWeapons2004.Sniper3rd at DrawScale 0.16) and its
    # pickup (NewWeaponStatic.newsniperpickup), which the icon is made from
    'classic_sniper_3rd': {
        'pskx': 'NewWeapons2004/SkeletalMesh/Sniper3rd.psk',
        'materials': [('newsniperrifle/Texture/Sniper1.tga', 'opaque')],
        'scale': 0.02 * 0.16,
        'roughness': 0.9,
        'unit': 'units/ut/sniper/third_person',
    },
    'classic_sniper_pickup': {
        'pskx': 'NewWeaponStatic/StaticMesh/newsniperpickup.pskx',
        'materials': [('newsniperrifle/Texture/Sniper1.tga', 'opaque')],
        'scale': 0.02 * 0.21,
        'roughness': 0.9,
        'unit': 'units/ut/sniper/pickup',
    },
    'assault_pickup': {
        'pskx': 'NewWeaponPickups/StaticMesh/AssaultPickupSM.pskx',
        'materials': [('UT2004Weapons/Texture/AssaultRifleTex0.tga', 'opaque')],
        'scale': 0.01,
        'unit': 'units/ut/assault/pickup',
    },
    'assault_grenade': {
        'pskx': 'WeaponStaticMesh/StaticMesh/GrenadeMesh.pskx',
        'materials': [('WeaponSkins/Texture/GrenadeTex.tga', 'opaque')],
        'scale': 0.06,
        'unit': 'units/ut/assault/grenade',
        'culling': 'disabled',
    },
    'redeemer_pickup': {
        'pskx': 'WeaponStaticMesh/StaticMesh/RedeemerPickup.pskx',
        'materials': [('WeaponSkins/Texture/RedeemerTex0.tga', 'opaque'), ('WeaponSkins/Texture/Rmissle.tga', 'opaque')],
        'scale': 0.018,
        'unit': 'units/ut/redeemer/pickup',
    },
    'redeemer_missile': {
        'pskx': 'WeaponStaticMesh/StaticMesh/RedeemerMissile.pskx',
        'materials': [('WeaponSkins/Texture/RDMR_Missile.tga', 'opaque'), ('WeaponSkins/Texture/RDMR_Missile.tga', 'opaque')],
        'scale': 0.04,
        'unit': 'units/ut/redeemer/missile',
        'culling': 'disabled',
    },
    'rocket_proj': {
        'pskx': 'WeaponStaticMesh/StaticMesh/RocketProj.pskx',
        'materials': [('WeaponSkins/Texture/RocketShellTex.tga', 'opaque')],
        'scale': 0.02,
        'unit': 'units/ut/rocket/projectile',
        'culling': 'disabled',
    },
    'flak_shell': {
        'pskx': 'WeaponStaticMesh/StaticMesh/FlakShell.pskx',
        'materials': [('WeaponSkins/Texture/FlakSlugTex.tga', 'opaque')],
        'scale': 0.16,
        'unit': 'units/ut/flak/shell',
        'culling': 'disabled',
    },
}

def reflect_labels(psk, rows, labels, material, folder):
    """The faces of the mesh that show its first material's texture flipped are given the material of that index, and the texture for them is
    a copy in which each label is reflected in place, back to front along its writing, so that the writing reads the right way on them too.
    Only the texture's own pixels are moved. Returns the changed psk (written in the folder) and the copy's rows."""
    data = bytearray(open(psk, 'rb').read())
    chunks = chunk_offsets(data)
    size, count, start = chunks['VTXW0000']
    uvs = [struct.unpack_from('<2f', data, start + i * size + 4) for i in range(count)]
    face_chunk = 'FACE0000' if 'FACE0000' in chunks else 'FACE3200'
    size, count, start = chunks[face_chunk]
    flipped = 0
    for i in range(count):
        at = start + i * size
        corners = struct.unpack_from('<3H' if face_chunk == 'FACE0000' else '<3I', data, at)
        material_at = at + (6 if face_chunk == 'FACE0000' else 12)
        (u0, v0), (u1, v1), (u2, v2) = [uvs[c] for c in corners]
        # A face shows the texture the right way round when its corners, in the psk's order, go round the texture one way, and flipped when they
        # go round it the other way (the psk's v runs down the texture, and psk2bsi turns the mesh without mirroring it)
        if data[material_at] == 0 and (u1 - u0) * (v2 - v0) - (u2 - u0) * (v1 - v0) < 0:
            data[material_at] = material
            flipped += 1
    print('faces that show the texture flipped', flipped)

    copy = [bytearray(row) for row in rows]
    for x, y, angle, along, across in labels:
        f = (math.cos(math.radians(angle)), math.sin(math.radians(angle)))
        s = (-f[1], f[0])
        reach = int(along + across) + 1
        # Each pixel of the label takes the pixel at the same place from the label's other end
        for py in range(y - reach, y + reach + 1):
            for px in range(x - reach, x + reach + 1):
                a = (px - x) * f[0] + (py - y) * f[1]
                b = (px - x) * s[0] + (py - y) * s[1]
                if abs(a) <= along and abs(b) <= across:
                    sx, sy = round(x - a * f[0] + b * s[0]), round(y - a * f[1] + b * s[1])
                    copy[py][px * 4:px * 4 + 4] = rows[sy][sx * 4:sx * 4 + 4]
    path = os.path.join(folder, os.path.basename(psk))
    open(path, 'wb').write(data)
    return path, [bytes(row) for row in copy]

def roughness_of(cfg, index):
    roughness = cfg.get('roughness', 0.9)

    return roughness.get(index, 0.9) if isinstance(roughness, dict) else roughness

def main():
    name, export = sys.argv[1], sys.argv[2]
    cfg = STATICS[name]
    unit_dir = os.path.dirname(cfg['unit'])
    unit_base = os.path.basename(cfg['unit'])
    os.makedirs(REPO + '/' + unit_dir, exist_ok=True)
    geometry = 'g_' + unit_base
    # (each material: its tga, its kind, its opacity, and the name and rows of its texture when they are not the tga's)
    materials = [(m[0], m[1], m[2] if len(m) > 2 else None, None, None) for m in cfg['materials']]
    psk = export + '/' + cfg['pskx']
    folder = tempfile.TemporaryDirectory()
    if cfg.get('labels'):
        tga, kind, opacity = materials[0][:3]
        w, h, rows = read_tga(export + '/' + tga)
        psk, rows = reflect_labels(psk, rows, cfg['labels'], len(materials), folder.name)
        materials.append((tga, kind, opacity, os.path.splitext(os.path.basename(tga))[0].lower() + '_reflected_labels', rows))
    mat_names = ['m_%d' % i for i in range(len(materials))]
    parts = cfg.get('parts', {})
    subprocess.check_call([sys.executable, os.path.join(os.path.dirname(__file__), 'psk2bsi.py'), psk,
                           '%s/%s.bsi' % (REPO, cfg['unit']), geometry, ','.join(mat_names), str(cfg['scale'])]
                          + ([','.join('%s=%s' % entry for entry in parts.items())] if parts else []))
    # (the geometries psk2bsi made are named <prefix>_<index of the material>, and <prefix>_<index>_<part> for the parts)
    unit_text = 'materials = {\n'
    for i, (tga, kind) in enumerate(m[:2] for m in materials):
        # (a material of the kind 'existing' is one the mod has already, named in place of the tga, and nothing is made for it)
        unit_text += '\tm_%d = "%s"\n' % (i, tga if kind == 'existing' else '%s/%s_m%d' % (unit_dir, unit_base, i))
    unit_text += '}\nrenderables = {\n'
    for i in range(len(materials)):
        for suffix in [''] + ['_' + part for part in parts.values()]:
            unit_text += ('\t%s_%d%s = {\n\t\talways_keep = false\n\t\tculling = "%s"\n\t\tgenerate_uv_unwrap = false\n\t\toccluder = false\n'
                          '\t\tshadow_caster = false\n\t\tsurface_queries = false\n\t\tviewport_visible = true\n\t}\n') % (geometry, i, suffix, cfg.get('culling', 'disabled'))
    unit_text += '}\n'
    open('%s/%s.unit' % (REPO, cfg['unit']), 'w', newline='\n').write(unit_text)
    for i, (tga, kind, opacity, texture_name, rows) in enumerate(materials):
        if kind == 'existing':
            continue
        texture = '%s/%s_%s' % (unit_dir, unit_base, texture_name or os.path.splitext(os.path.basename(tga))[0].lower())
        if rows is None:
            w, h, rows = read_tga(export + '/' + tga)
        write_png('%s/%s.png' % (REPO, texture), w, h, rows)
        open('%s/%s.texture' % (REPO, texture), 'w', newline='\n').write(texture_text(texture))
        open('%s/%s/%s_m%d.material' % (REPO, unit_dir, unit_base, i), 'w', newline='\n').write(material_text(kind, texture, opacity, roughness=roughness_of(cfg, i), world=name.endswith(('_pickup', '_3rd'))))

main()
