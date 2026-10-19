import sys, os

# Makes the effect textures of the Minigun, Shield Gun, Assault Rifle and Redeemer from the UModel export (export.py): each as
# units/ut/fx/<name>.png and .texture, with the material fx_<name> that adds its colour to the screen (the same as make_fx_assets.py
# makes). A sheet of tiles (a texture with columns and rows of pictures, which UT's emitters pick from) is cut into one texture for each
# tile, named <name>_0, <name>_1 and so on from the top left.
# The effects that UT adds to the screen are read linearly (units/ut/fx/particle_linear, see make_lightning_assets.py): the values of the
# texture are added as they are. The shell casing is blended, not added, so it keeps the srgb read.
# Usage: make_weapon_fx.py <export dir>

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
EXPORT = sys.argv[1]

sys.path.insert(0, os.path.dirname(__file__))
from formats import read_tga, write_png
from resources import texture_text, particle_material_text

# name: (the tga, columns, rows). A texture that is not a sheet has 1 and 1.
TEXTURES = {
    # The Minigun (MinigunMuzFlash1st, MinigunFlash, NewMinigunMFlash, NewTracer, ShellSpewer). minigun_flash_3rd is MinigunFlashFinal's
    # texture, which the Rocket Launcher's third person flash (RocketMuzFlash3rd) draws on its mesh.
    'minigun_burst': ('XGameShaders/Texture/Minigun_burst.tga', 2, 2),
    'minigun_flash_3rd': ('XGameShaders/Texture/minigunflash.tga', 1, 1),
    'minigun_flame': ('AW-2004Explosions/Texture/Part_explode2s.tga', 4, 4),
    'tracer_shot': ('AW-2004Particles/Texture/TracerShot.tga', 1, 1),
    'shell_casing': ('XEffects/Texture/ShellCasingTex.tga', 1, 1),
    # (the smoke at the muzzle in the player's view: MinigunMuzzleSmoke's SmokeTex, a sheet of 16 puffs (pclSmoke's tiles), blended by
    # its alpha: STY_Alpha)
    'muzzle_smoke': ('XEffects/Texture/SmokeTex.tga', 4, 4),
    # (where its rounds hit a wall: pclImpactSmoke's puffs and SmallExplosion's fire, a RocketExplosion)
    'impact_smoke': ('XEffects/Texture/EmitSmoke_t.tga', 4, 4),
    'small_explosion': ('XEffects/Texture/Rexpt.tga', 1, 1),
    # The Shield Gun (ShieldEffect's Shield3rdFB: its material is units/ut/fx/fx_shield, made by make_combo_materials.py)
    'shield_elec': ('XEffectMat/Texture/shield_elec_green_a.tga', 1, 1),
    # (ShieldRip3rdFB, the shield as it stops something: its lines and the fade of its rim)
    'shield_rip_elec': ('XEffectMat/Texture/shield_elec_green_rip_a.tga', 1, 1),
    'shield_edge': ('XEffectMat/Texture/edgegrad.tga', 1, 1),
    # (ForceRingA's rings of the punch and ShieldCharge's sparks of the charge)
    'force_ring': ('XEffectMat/Texture/shock_ring_b.tga', 1, 1),
    'shield_charge_spark': ('XEffects/Texture/FlakTrailTex.tga', 1, 1),
    # The Redeemer (NewRedeemerTrail's flames and smoke, RedeemerExplosion's puffs and the gradient of its ring and sphere)
    'redeemer_flame': ('AW-2004Explosions/Texture/Part_explode2.tga', 4, 4),
    'redeemer_smoke': ('AW-2004Particles/Texture/MuchSmoke1.tga', 4, 4),
    'smoke_puff': ('EpicParticles/Texture/Smokepuff.tga', 1, 1),
    'smoke_puff2': ('EpicParticles/Texture/Smokepuff2.tga', 1, 1),
    'flame_gradient': ('EpicParticles/Texture/FlameGradient.tga', 1, 1),
    'burn_flare': ('EpicParticles/Texture/BurnFlare1.tga', 1, 1),
    'soft_flare': ('EpicParticles/Texture/SoftFlare.tga', 1, 1),
    'white_streak': ('EpicParticles/Texture/WhiteStreak01aw.tga', 1, 1),
    # The Sniper Rifle's smoke (ClassicSniperSmoke: a frame of SmokeReOrdered at random, blended by its alpha)
    'sniper_smoke': ('ExplosionTex/Texture/SmokeReOrdered.tga', 4, 4),
    # (the textures of the Redeemer blast's spheres and ring, whose materials make_combo_materials.py makes: fx_ion_sphere and fx_flame_ring)
    'ion_burn': ('EpicParticles/Texture/IonBurn.tga', 1, 1),
    'grad_falloff': ('EpicParticles/Texture/Grad_Falloff.tga', 1, 1),
}

# (the ones UT blends by their alpha, not adds: PTDS_AlphaBlend)
SRGB = ('shell_casing', 'redeemer_smoke', 'smoke_puff', 'muzzle_smoke', 'sniper_smoke')

# The textures whose colour is made white, with their alpha kept: the Sniper Rifle's smoke showed the dark grey around the puffs as dark
# spots, where pictures of UT show an even light haze
WHITE = ('sniper_smoke',)

# The textures that UT draws with FB_Brighten, or as STY_Translucent, which is the same: c + d * (1 - c). They are read as they are, and
# their materials are derived from fx_particle_brighten_graph and fx_particle_weapon_brighten_graph (make_combo_materials.py).
BRIGHTEN = ('minigun_burst', 'impact_smoke', 'minigun_flash_3rd')

# The textures that are kept as they are, alpha and all, for a material of their own that reads it (the shield's fx_shield and the
# Redeemer blast's fx_ion_sphere and fx_flame_ring, made by make_combo_materials.py, which do FB_Brighten themselves and use the alpha)
KEEP_ALPHA = ('shield_elec', 'shield_rip_elec', 'shield_edge', 'ion_burn', 'grad_falloff')

# The textures that only those materials draw, so they have no particle material of their own (FlameGradient is the Redeemer ring's)
COMBO_ONLY = KEEP_ALPHA + ('flame_gradient',)

# The textures that are turned a quarter, because they are drawn on a beam, which lays v along its length (TracerShot is a streak along
# u, the way NewTracer's sprite moves: PTDU_Right)
TURNED = ('tracer_shot', 'shield_charge_spark', 'white_streak')

# The textures of which only the top half is used: FlakTrailTex is a streak above a dot, and a line particle (PT_Line) is the streak
TOP_HALF = ('shield_charge_spark',)

# The effects that UT draws with the weapon in the player's view (attached to it) also get fx_weapon_<name>, which draws with the
# weapon model's field of view (units/ut/fx/particle_weapon_linear, or particle_weapon for an srgb one), so they are among the model's
# parts. The Minigun's flash and shells are attached to the weapon (MinigunFire.InitEffects, Minigun.PostBeginPlay), and its smoke is
# drawn with the weapon's field of view (WeaponFire.DrawMuzzleFlash).
WEAPON = ('minigun_burst', 'shell_casing', 'muzzle_smoke', 'force_ring', 'shield_charge_spark')

def write(name, width, height, rows, linear, weapon=False, brighten=False, keep_alpha=False):
    if keep_alpha:
        pass
    elif linear:
        # UT's additive styles leave out the texture's alpha, while the particle material multiplies the colour by it, so it is made
        # opaque here
        rows = [bytes(255 if i % 4 == 3 else v for i, v in enumerate(row)) for row in rows]
    write_png('%s/units/ut/fx/%s.png' % (REPO, name), width, height, rows)
    open('%s/units/ut/fx/%s.texture' % (REPO, name), 'w', newline='\n').write(texture_text('units/ut/fx/' + name, not linear))
    if name in COMBO_ONLY:
        return
    if brighten:
        parent, weapon_parent = 'fx_particle_brighten_graph', 'fx_particle_weapon_brighten_graph'
    else:
        parent, weapon_parent = ('particle_linear', 'particle_weapon_linear') if linear else ('particle', 'particle_weapon')
    open('%s/units/ut/fx/fx_%s.material' % (REPO, name), 'w', newline='\n').write(particle_material_text(name, parent))
    if weapon:
        open('%s/units/ut/fx/fx_weapon_%s.material' % (REPO, name), 'w', newline='\n').write(particle_material_text(name, weapon_parent))

for name, (tga, columns, rows_count) in TEXTURES.items():
    width, height, rows = read_tga('%s/%s' % (EXPORT, tga))

    if name in WHITE:
        rows = [bytes(v if i % 4 == 3 else 255 for i, v in enumerate(row)) for row in rows]

    if name in TOP_HALF:
        rows = rows[:height // 2]
        height = len(rows)

    if name in TURNED:
        rows = [b''.join(rows[y][x * 4:x * 4 + 4] for y in range(height)) for x in range(width)]
        width, height = height, width

    if columns == 1 and rows_count == 1:
        write(name, width, height, rows, name not in SRGB, name in WEAPON, name in BRIGHTEN, name in KEEP_ALPHA)
        print('texture', name, width, height)

        continue

    tile_width, tile_height = width // columns, height // rows_count

    for index in range(columns * rows_count):
        column, row = index % columns, index // columns
        # (a row from read_tga is four bytes for each pixel)
        tile = [line[4 * column * tile_width:4 * (column + 1) * tile_width] for line in rows[row * tile_height:(row + 1) * tile_height]]

        write('%s_%d' % (name, index), tile_width, tile_height, tile, name not in SRGB, name in WEAPON, name in BRIGHTEN, name in KEEP_ALPHA)

    print('sheet', name, columns * rows_count, 'tiles of', tile_width, tile_height)

# The shell casing is also drawn lit (fx_shell_casing_lit): ShellSpewer's meshes are lit by the level (its Style is UT's default,
# STY_Normal), which makes them dark grey. Unlit, the texture was drawn at full brightness. The parent is the SDK's standard
# material, not world_standard, which fades out near the camera, where the player's own shells are.
LIT_MATERIAL = '''material_contexts = {
	surface_material = ""
}
parent_material = "core/stingray_renderer/shader_import/standard"
textures = {
	color_map = "units/ut/fx/%s"
}
variables = {
	use_color_map = {
		type = "scalar"
		value = 1
	}
	roughness = {
		type = "scalar"
		value = 0.9
	}
}
'''

for name in ('shell_casing',):
    open('%s/units/ut/fx/fx_%s_lit.material' % (REPO, name), 'w', newline='\n').write(LIT_MATERIAL % name)
    print('lit material', name)
