# Weapon Skins: the UT2004 Rocket Launcher

Status: plan, then built in the order below. Branch `ut-weapon-skins`, local only, never pushed. The groundwork (`weapon_skin.lua`,
skeletal animation, the converters, a bank for each weapon) is in `weapon_skin_flak_cannon.md`; this weapon is built on it.

The Rocket Launcher replaces the Witch Hunter's Repeating Crossbow (`repeating_crossbow_template_1`, `rocket_launcher.lua`): LMB is a
rocket (`ActionCrossbow`), RMB held loads rockets (`ActionAim`, one more every `load_interval`), LMB while loading makes the salvo a
spiral, release fires the salvo (`ActionCrossbow`, `ut_rocket_salvo`), and there are lock-on and a pip crosshair. The skin changes
only what is seen and heard.

## 1. What UT2004 has

(`XWeapons/RocketLauncher.uc`, `RocketFire`, `RocketMultiFire`, `RocketProj`, `XEffects/Rocket*`, `NewExplosionA`, `ExplosionCrap`)
- First person: `Weapons.RocketLauncher_1st` (10 bones: the weapon, the barrel (it turns as a rocket is loaded), the chamber, the shell,
  the feed, the flash), `RocketTex0`, `DisplayFOV` 60, `PlayerViewOffset` (0, 8, 0), `PlayerViewPivot` yaw 500 roll 1000, `BobDamping`
  1.5. Animations: Pickup, Idle, Fire (primary), AltFire (the volley), load (a rocket loaded: the barrel turns). PutDown is not made.
- The flash: `RocketMuzFlash1st`/`3rd` (meshes with a flash shader, 0.15 s) on `Bone_Flash`.
- The rocket: the mesh `WeaponStaticMesh.RocketProj` (24 units long, `RocketShellTex`), turning on its roll (50000 a second), with
  `RocketTrailSmoke` (wisp smoke, 90 a second, 1.25 s, 15 to 20 units growing 13, rising a little), `RocketCorona` (a flare sprite,
  `RocketFlare`, 1.2 times the texture, stretched along its flight 0.7 to 0.35, pulsing between 0.9 and 1.5) and the light; the loop
  `RocketLauncherProjectile`.
- The explosion: `NewExplosionA` (a sprite sheet of fire, 3 sprites of 50 to 70 units, 0.4 to 0.6 s; smoke), `ExplosionCrap` (150
  chunks of debris), `RocketMark` (a scorch), the sound `BExplosion3`.
- Sounds: `RocketLauncherFire`, `BRocketLauncherLoad` (a rocket loaded), `SwitchToRocketLauncher`.
- Third person: `WeaponStaticMesh.RocketLauncherPickup` (`DrawScale` 0.45).

## 2. Where each comes in here

| UT | Here |
|---|---|
| Pickup, select sound | wield, as the others |
| Fire | the primary shot: `ActionCrossbow.client_owner_start_action` (new hook table `mod.crossbow_start_callbacks`); the flash on the flash bone |
| load | each rocket loaded while aiming (`update_loading`, new `mod.rocket_load_callbacks`): the animation (the barrel turns), the load sound |
| AltFire | the salvo's start (the same hook, `ut_rocket_salvo`) |
| The shots' sound | `attack_shoot` of the crossbow is an animation event that makes the sound: not played on the player's own first person unit (`mod.first_person_animation_filters`, as the Flak Cannon), UT's is played |
| Aiming | `ActionAim` start and finish move to hook tables (`mod.aim_start_callbacks`, `mod.aim_finish_callbacks`: `rocket_launcher.lua` hooks them, and a function can be hooked once); the first person model is not zoomed |
| The rocket | the game's bolt unit stays (it is the gameplay), its flow events are held back (`ut_init_flow_event_filter`) and UT's rocket is drawn at it: the mesh (turning), the corona, the smoke trail, the loop sound; a spiral's rockets each |
| The explosion | `skin_explosion_callbacks` for `ut_rocket_explosion`: a flash, a fire star, smoke, debris sprites, `BExplosion3`; the game's own effects and sound of the template off while the skin is on |
| Third person | the pickup mesh in the hand, a flash and sounds for the others |

Not done: the sprite sheet of `NewExplosionA` (its frames are made of the flash and fire sprites of the effects the skins share), the
scorch decal, the dynamic light.

## 3. Order of work

(1) the hook tables and the weapon's definition: model, animations, third person, sounds of the shots and the load; (2) the rocket, its
trail and its explosion; each ends with a build and a local commit.

## 4. Risks

- The crosshair pips and the lock-on are the game's HUD and stay as they are.
- The rotating barrel is a node pose, per frame, like the rest.
- The spiral's rockets are many units at once: the visuals are the same code for each.
