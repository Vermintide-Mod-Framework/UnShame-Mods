# Weapon Skins: the UT2004 Bio Rifle

Status: built (the plan and what was built are the same). Branch `ut-weapon-skins`, local only, never pushed. The groundwork is in
`weapon_skin_flak_cannon.md`.

The Bio Rifle replaces Bardin's Drakegun (`drakegun_template_1`, `bio_rifle.lua`): LMB is a glob (`charged_projectile`), RMB held
charges a bigger one (`charge`, then `charged_projectile` on release), globs leave puddles of goo that burn and burst into small globs.

## What UT2004 has

(`XWeapons/BioRifle.uc`, `BioFire`, `BioChargedFire`, `BioGlob`, `XEffects/BioMuzFlash1st`, `GoopSmoke`, `GoopSparks`, `BioDecal`)
- First person: `Weapons.BioRifle_1st` (3 bones: the weapon, the plunger, the flash; the tank has glass and bubbles), `DisplayFOV` 60,
  `PlayerViewOffset` (7, 3, 0), `BobDamping` 2.2. Animations: Select, Idle, Fire, AltFire (the plunger drawn back while charging), HOLD.
- The glob: `XWeapons_rc.GoopMesh` (a vertex mesh) with the goop shader, `DrawScale` 1.2, growing with its goo level; the loop is none; the
  light is green.
- The splash: `GoopSmoke` (10 puffs, 20 to 30 units, 1 to 2 s, green) and `GoopSparks` (10 sparks of 4 units, 80 to 240 units a second); the
  puddle is the splat `BioDecal` (`xbiosplat`, DrawScale 0.65).
- Sounds: `BioRifleFire`, `BioRiflePowerUp` (charging), `SwitchToBioRifle` (UT2004's is the Flak Cannon's), `BioRifleGoo1` and `2`.
- Third person: `WeaponStaticMesh.BioRiflePickup` (`DrawScale` 0.6).

## Where each comes in here

| UT | Here |
|---|---|
| Fire | the glob's shot (`charged_projectile_start_callbacks`, `ut_bio_glob`), the flash, UT's fire sound for the game's `fire_sound_event`s (the Sienna's fireball and geiser: `take_over_sound`, which now allows more than one skin to look at an event) |
| AltFire | the start of the charge (`charge_start_callbacks`, `ut_charge_callback = "bio"`), and the power up sound |
| The glob | the game's bolt unit stays; its flow events are held back (`ut_init_flow_event_filter`), a green blob and glow follow it, as big as its scale |
| The splash | `skin_explosion_callbacks` for the bursts and the impact: smoke and sparks, the game's own effect and sound off while the skin is on |
| The puddle | `mod.puddle_visual_callbacks` (`show`, `stop`, `burst`; `bio_rifle.lua` calls them instead of the fire when the skin is on): the splat lies on the ground for the puddle's time, as wide as its radius |
| Third person | the pickup mesh at the left hand's node (the game links the Drakegun there), a flash and sounds for the others |

Not done: the vertex mesh of the glob (a blob of sprites is drawn), the dynamic light, the decals of the burst on walls.
