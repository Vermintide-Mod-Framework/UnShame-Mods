import sys, os, subprocess

# Exports the UT2004 packages that the other scripts read into one folder, with UModel. Each package is in a folder of its own name:
# <export dir>/<package>/<class>/<object>.
# Usage: export.py <UT2004 dir> <export dir> [umodel]      (umodel is the path of umodel_64.exe, if it is not on the PATH)

PACKAGES = [
    # the first person models, their animations and textures, and the pickups
    'Weapons', 'NewWeapons2004', 'SniperAnims', 'WeaponSkins', 'UT2004Weapons', 'NewSniperRifle', 'WeaponStaticMesh', 'NewWeaponPickups',
    'NewWeaponStatic',
    # the effects: textures, meshes and the classes with their emitters
    'XEffects', 'XEffectMat', 'XWeapons_rc', 'XGameShaders', 'XGameTextures', 'ExplosionTex', 'EmitterTextures', 'ParticleMeshes',
    'AW-2004Explosions', 'AW-2004Particles', 'EpicParticles', 'WarEffectsTextures', 'DeployableTex',
    # the sphere of the Shock Rifle's combo (TexPropSphere)
    'Editor',
    # the sounds (GameSounds: the adrenaline combos')
    'WeaponSounds', 'NewWeaponSounds', 'AnnouncerMale2K4', 'GameSounds',
    # the HUD's pictures (the Assault Rifle's grenades)
    'HudContent',
]

def main():
    game, out = sys.argv[1], os.path.abspath(sys.argv[2])
    umodel = sys.argv[3] if len(sys.argv) > 3 else 'umodel_64'
    os.makedirs(out, exist_ok=True)

    for package in PACKAGES:
        print('exporting', package)
        subprocess.run([umodel, '-path=' + game, '-game=ut2', '-export', '-sounds', '-out=' + out, package], check=True,
                       stdout=subprocess.DEVNULL)

main()
