import sys, os, subprocess

# Converts static meshes of UT2004 (the pickups of the weapons, which are the third person, and the meshes of the projectiles), exported
# with UModel as pskx, to units: a bsi (psk2bsi.py), a unit, a material and a texture.
# Usage: convert_static.py <name> <umodel export dir>      (the meshes are in STATICS below)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.dirname(__file__))
from convert_weapon import read_tga, write_png, TEXTURE_TEMPLATE, material_text

# pskx: the mesh; materials: the texture (tga) and kind of each material of it; scale: meters a UT unit of the mesh is as it is drawn
# (the DrawScale of its actor is in it: a pickup of the weapon in the hand is 0.011, 0.02 meters a unit and 0.55)
STATICS = {
    'flak_pickup': {
        'pskx': 'WeaponStaticMesh/StaticMesh/FlakCannonPickup.pskx',
        'materials': [('WeaponSkins/Texture/Flak3rdperson.tga', 'opaque')],
        'scale': 0.011,
        'unit': 'units/ut/flak/pickup',
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
        'scale': 0.012,
        'unit': 'units/ut/bio/pickup',
    },
    'rocket_pickup': {
        'pskx': 'WeaponStaticMesh/StaticMesh/RocketLauncherPickup.pskx',
        'materials': [('WeaponSkins/Texture/RocketTex0.tga', 'opaque')],
        'scale': 0.009,
        'unit': 'units/ut/rocket/pickup',
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

def main():
    name, export = sys.argv[1], sys.argv[2]
    cfg = STATICS[name]
    unit_dir = os.path.dirname(cfg['unit'])
    unit_base = os.path.basename(cfg['unit'])
    os.makedirs(REPO + '/' + unit_dir, exist_ok=True)
    geometry = 'g_' + unit_base
    mat_names = ['m_%d' % i for i in range(len(cfg['materials']))]
    subprocess.check_call([sys.executable, '-I', os.path.join(os.path.dirname(__file__), 'psk2bsi.py'), export + '/' + cfg['pskx'],
                           '%s/%s.bsi' % (REPO, cfg['unit']), geometry, ','.join(mat_names), str(cfg['scale'])])
    # (the geometries psk2bsi made are named <prefix>_<index of the material>)
    unit_text = 'materials = {\n'
    for i in range(len(cfg['materials'])):
        unit_text += '\tm_%d = "%s/%s_m%d"\n' % (i, unit_dir, unit_base, i)
    unit_text += '}\nrenderables = {\n'
    for i in range(len(cfg['materials'])):
        unit_text += ('\t%s_%d = {\n\t\talways_keep = false\n\t\tculling = "%s"\n\t\tgenerate_uv_unwrap = false\n\t\toccluder = false\n'
                      '\t\tshadow_caster = false\n\t\tsurface_queries = false\n\t\tviewport_visible = true\n\t}\n') % (geometry, i, cfg.get('culling', 'bounding_volume'))
    unit_text += '}\n'
    open('%s/%s.unit' % (REPO, cfg['unit']), 'w', newline='\n').write(unit_text)
    for i, material in enumerate(cfg['materials']):
        tga, kind = material[:2]
        opacity = material[2] if len(material) > 2 else None
        texture = '%s/%s_%s' % (unit_dir, unit_base, os.path.splitext(os.path.basename(tga))[0].lower())
        w, h, rows = read_tga(export + '/' + tga)
        write_png('%s/%s.png' % (REPO, texture), w, h, rows)
        open('%s/%s.texture' % (REPO, texture), 'w', newline='\n').write(TEXTURE_TEMPLATE % texture)
        open('%s/%s/%s_m%d.material' % (REPO, unit_dir, unit_base, i), 'w', newline='\n').write(material_text(kind, texture, opacity, world=name.endswith('_pickup')))

main()
