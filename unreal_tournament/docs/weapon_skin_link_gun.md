# Link Gun skin

Setting: Weapons > Weapon Skins (`link_gun`). Template `staff_life` (the Deepwood Staff). Code: `link/skin.lua`; the gameplay stays in `link/link_gun.lua`.

## What UT2004 has
- `NewWeapons2004.FatLinkGun`: DisplayFOV 60, PlayerViewOffset (-5,-3,0), PlayerViewPivot yaw 500, BobDamping 1.575. Muzzle bone `b_bone_flasha`. Animations Pickup / Idle / Fire / AltFire.
- Primary: `LinkProjectile` (green plasma bolt, `LinkMuzFlash`). Secondary: `LinkBeamEffect` (beam texture; gold while linked to a teammate or a vehicle).
- Sounds: fire, beam loop, linked, select.

## What the skin does
- First person: model, animations, bob, sounds as the other skins (`weapon_skin.lua`). Third person: pickup mesh in the left hand node.
- Bolts: the staff's thorns are hidden and followed by a green sprite plus glow; the game's own projectile effects are suppressed (`mod.init_flow_event_filters.link`). Fire animation, flash and sound on the shot (own shot) or the flash and 3D sound (other players').
- Beam: `link_gun.lua` calls `mod.link_beam_callbacks.start_position` for the muzzle and `.draw` for the curve; the skin draws the beam texture on each stretch of it (yellow when linked), a flare at its end, and plays the beam sound. The old sprites are not drawn while the skin is on.
- Alt fire starts the AltFire animation (`mod.charge_start_callbacks`).

## Tuning
`/skin link_gun set <key> <value>` for the first person, `/skin link_gun 3p <key> <value>` for the hand (guessed values: yaw 90, grip (-21, 0, -30), muzzle (54, 0, 3), `meters_per_unit` 0.012, scale 0.6).
