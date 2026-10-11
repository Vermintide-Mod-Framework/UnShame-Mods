# Weapon Skins: the UT2004 Flak Cannon

Status: plan, then built in the order below. Branch `ut-weapon-skins`, local only, never pushed. The Shock Rifle's plan is
`weapon_skins_plan.md`; this one also covers the groundwork the four weapons after it share (section 1).

The Flak Cannon replaces Kruber's Blunderbuss (`blunderbuss_template_1`, `flak_cannon.lua`): LMB is the spread of flak chunks
(`ActionShotgun._shoot`), RMB the lobbed shell (`charged_projectile`). The skin is the same setting, **Weapon Skins**, and
changes only what is seen and heard.

## 1. Groundwork for all four weapons

What the Shock Rifle's skin does is mostly not about the Shock Rifle: it spawns a model in the first person unit, places it as
UT places it, plays animations, hides the game's weapon, bobs, holds the pickup mesh in the hand of every character, and plays
sounds. That moves out of `shock_rifle_skin.lua` into **`weapon_skin.lua`**, a factory (`mod.weapon_skin.new(definition)`, the
precedent is `mod.skin_particles`) that each weapon's skin file calls with what is its own:

| The definition says | Used for |
|---|---|
| setting id, template name, unit, animations (name, rate, frames of bone poses), bones | what is wielded and what plays |
| UT's `DisplayFOV`, `PlayerViewOffset`, `PlayerViewPivot` (pitch, yaw, roll), `DrawScale`, `BobDamping`, scale of the mesh | where the model is (`Pawn.CalcDrawOffset`) |
| the pickup mesh, grip, scale | the third person |
| `on_create`, `on_update`, `on_destroy` | what is the weapon's own (the Shock Rifle's chamber, a pump) |

and it returns what the weapon's file needs: `play(name, duration)`, `muzzle_position()`, `shows_weapon(unit)`, the sound
functions, the hook tables. The Shock Rifle's skin is rewritten on it (no change in what it does).

**Skeletal animation.** UT's weapons are skeletal (the Flak Cannon has 34 bones: hammer, barrel, hydraulics, teeth, coil), where
the Shock Rifle's is one rigid piece. The converter (`psk2bsi.py`) splits the mesh by the bone that has most of each vertex into
one geometry per (material, bone), each under a node of its own, and a node for the bones that have no mesh (the muzzle
flash). The animation keys become, for each bone, its pose against the root bone's move (`inverse(root) * bone`, in the mesh's
space), one row of seven numbers per frame; the root bone's own move is what `place` does already. Playing an animation sets
each node's pose (`Unit.set_local_pose`). Bones with no mesh are kept for where the muzzle is.

**Placement.** `PlayerViewPivot` has yaw and roll (the Flak Cannon's mesh lies sideways and is turned 92.7 degrees by its
yaw): the rotation is `Rz(-yaw) * Rx(pitch) * Ry(-roll)` in this game's axes (UT is left handed with Y right). The field of view
is UT's horizontal one for `DisplayFOV` at this aspect: `2 * atan(tan(DisplayFOV / 2) * 1.345)`, the factor that the
Shock Rifle's fit (86.5 degrees for 70) gives. A command, `/skin <weapon> <name> <value>`, sets a number of a definition while
playing (the placement can't be fitted without the game).

**Tools.** `psk2bsi.py` (bones), `make_anim_assets.py` (a weapon is a table of names: meshes, textures, animations),
`make_bank.py` (a list of sounds for each weapon, one bank each), `make_fx_assets.py` (textures of the effects of each weapon).
Epic's assets stay local.

## 2. The Flak Cannon

**What UT2004 has** (`XWeapons/FlakCannon.uc`, `FlakFire`, `FlakAltFire`, `FlakChunk`, `FlakShell`, `XEffects/Flak*`):
- First person: `Weapons.Flak_1st` with `WeaponSkins.FlakTex0` and `FlakTex1`, `DisplayFOV` 60, `PlayerViewOffset` (-7, 8, 0),
  `PlayerViewPivot` yaw 16884 roll 200, `BobDamping` 1.4. Animations: Pickup, Idle, Fire, AltFire (PutDown is not made, the
  game has none).
- Fire: `FlakMuzFlash1st` (a mesh with the `flakflashfinal` shader, `DrawScale` 2.2, growing 7 a second) on the bone `Bone_Flash`.
- Chunks: the mesh `WeaponStaticMesh.FlakChunk` (`DrawScale` 14, alpha) with `FlakTrail` (additive sprites, 60 a second, 0.1 s,
  size 2 to 3) behind it; they bounce, with the sounds `Impact1` to `Impact7`.
- Shell: `WeaponStaticMesh.FlakShell` (`DrawScale` 8, `NewFlakSkin`), `FlakShellTrail` (smoke, sizes 20 to 35, growing 15),
  `FlakGlow` (a gold sprite, 0.25), the loop `BFlakCannonProjectile`. It explodes as `FlakExplosion` (5 smoke puffs,
  91 to 161, `fexpt`) and `FlashExplosion` (150, growing 500, 0.25 s) with `BExplosion1`, and the decal `ShockAltDecal`.
- Sounds: `WeaponSounds.FlakCannon.FlakCannonFire`, `FlakCannonAltFire`, `SwitchToFlakCannon`.
- Third person: `WeaponStaticMesh.FlakCannonPickup` (`DrawScale` 0.55) and `FlakMuzFlash3rd`.

**Where each comes in here:**

| UT | Here |
|---|---|
| Pickup | wield callback, `wield_cooldown` long |
| Fire | the shot of `ActionShotgun._shoot` (the shot is the moment of the sound too: `fire_sound_event` of the action, taken over by `hud_sound_callbacks`), muzzle flash on the flash bone, the game's chunk trail off |
| AltFire | the start of the shell's action; muzzle flash; the shell's own effects as the shot |
| Chunk, shell | the game's projectile units stay (they are the gameplay), their visuals are not started (`init_flow_event_filters`, as the Shock Rifle's ball) and UT's are drawn at them: a mesh of the chunk or sprites with the trail, the shell mesh with its glow and the smoke |
| Explosion | `skin_explosion_callbacks` for `ut_flak_shell_explosion`: flash, smoke, sound; the game's own sound and effect of the template off while the skin is on |
| Chunk hits and bounces | the impact sounds of UT at the bounce (`ProjectileScriptUnitLocomotionExtension.bounce`) |
| Third person | the pickup mesh in the hand with the muzzle flash |

**Order of work:** (1) the groundwork above and the Shock Rifle on it; (2) the Flak Cannon's assets; (3) its skin: first
person, shots, sounds; (4) projectiles and explosion; (5) third person; each ends with a build and a local commit.

## 3. Risks

- Skeletal pieces by the strongest bone: UT's weapons are rigid per bone (a hammer, a barrel) except where a vertex is shared;
  those join one of the pieces and show a seam.
- The placement of a mesh turned by yaw and roll is not checked against UT's own picture, only against the source's numbers
  (the tuning command is for that).
- The Flak Cannon's own sounds (`FlakCannonFire` is a sound group) may be several variants: the first is used.
