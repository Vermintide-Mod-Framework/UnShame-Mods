# Weapon status

`WEAPON_CHECKLIST.md` for each weapon of the mod that was ported with it: what was found for each line. `ok`: checked in the game, against
UT2004 where there is something to compare with. `no`: wrong or missing, with what. `-`: not checked yet. `n/a`: does not apply.

| Line | Lightning Gun | Minigun | Shield Gun |
|---|---|---|---|
| **Item and menus** | | | |
| Name in the inventory | ok | ok | ok |
| Icon in the inventory | ok (points up-right) | ok (points up-right) | ok (points up-right) |
| Description | ok (UT's, shortened) | ok | ok (UT's, shortened) |
| Keywords | ok | ok | - |
| Stat chart | ok (a guess) | ok (a guess) | - |
| Which careers can equip it | ok (two items: Kruber's handgun and Bardin's) | ok (repeating handgun and repeating crossbow items) | ok (six items: a melee weapon of each hero; tests for each) |
| Chaos Wastes copy | - | - | - |
| Crafting | - | - | - |
| Hero screen: model and its place | ok (held, size 0.5) | - | - |
| Item screen: model and its turn | - | - | - |
| Tab screen after a mod reload | no: the icon shows after the next level (game limit) | - | - |
| Equipping and switching weapons | ok | ok | ok |
| Base weapon when the mod is disabled | - | - | - |
| **First person** | | | |
| Position and size against UT | ok (blend with UT) | ok (side by side) | close: same size, UT's about 15 px higher and a little more tilted (the offline render agrees with the game) |
| Pickup animation | ok (UT's SelectAnimRate 1.25, side by side with UT) | ok (SelectAnimRate 1.3636) | ok (SelectAnimRate 1.3636) |
| Idle animation speed | - | - | - |
| Fire animation of each mode | ok (Fire at UT's FireAnimRate 1.25, frames side by side with UT 25 ms apart; zoom has none) | - | ok (Charge over 2.5 s, Charged loop, Fire, Shield loop) |
| Animation length against the fire rate | - | - | - |
| Parts that move by code | - | - | - |
| Inspect pose | - | - | - |
| Inspect: first second of movement | - | - | - |
| Vanilla model or arms showing | - | - | - |
| Vanilla flash or particles showing | ok (the handgun's orange tracer is dropped) | ok (the same) | - |
| Crosshair | ok (hidden while zoomed; the scope side by side with UT: lens, ring, arrows, bar, under the HUD, shows right after a mod reload) | - | - |
| Ammo number | - | - | - |
| Bob and sway | - | - | - |
| **Firing** | | | |
| Fire rate of each mode | ok (tests: 1.6 s) | ok (tests) | ok (FireRate 0.6 after a punch) |
| Second mode right after the first | - | - | - |
| First mode right after the second | - | - | - |
| Hold, release and auto-fire | - | - | ok (tests: punch on release, auto punch with an enemy in reach) |
| Where shots start | - | - | - |
| Shots start in the same place each time | - | - | - |
| Shots in a line | - | - | - |
| Spread | - | - | - |
| Rapid shots | - | - | - |
| **Damage** | | | |
| Normal enemies | no: open. The test "damages an enemy" fails: a marauder spawned in the Keep has 0 health before it is hit, so the test can't measure damage there (the bolt does end on it) | no: the same | open: no test of the damage (marauders in the Keep have 0 health); 40 to 150 by the charge, one target in 112 units |
| Armored enemies | - | - | - |
| Monsters | - | - | - |
| Shields | - | - | open: the right button is the base weapon's block (stamina) instead of UT's shield ammo; the shield is drawn while it is up, close to UT's |
| Headshots | - | - | - |
| Crits | - | - | - |
| Damage against the other UT weapons | - | - | - |
| Self damage | - | - | - |
| Explosion radius | - | - | - |
| Explosion falloff | - | - | - |
| Momentum | - | - | - |
| Weapon jumping | - | - | open: the shield jump off a wall is made (UT's momentum, scaled by the jumps) but not checked in the game. Its self damage (8 + 0.3 of the damage) is left out |
| Ragdolls | - | - | - |
| Banners and barrels | - | - | - |
| **Projectiles** | | | |
| Speed | - | - | - |
| Gravity | - | - | - |
| Lifetime | - | - | - |
| Hit size | - | - | - |
| Draw distance | - | - | - |
| Hitting other projectiles | - | - | - |
| Lock-on, homing, bounce, link, goo, combo | - | - | - |
| **Ammo** | | | |
| Max ammo | ok (40) | ok (300) | - |
| Pickup amount | - | - | - |
| Reload between shots | - | - | - |
| Chamber at 0 ammo | - | - | - |
| Chamber at the last round | - | - | - |
| Load animation when ammo comes back | - | - | - |
| Load sound when ammo comes back | - | - | - |
| Shot during a load animation | - | - | - |
| Multi-load at 1, 2 and 3 rounds | - | - | - |
| `/loaded` | - | - | - |
| **Effects** | | | |
| Muzzle flash | ok (white disk with a blue rim, size, place and fade side by side with UT; it reads its texture linearly, as UT adds it) | no: close. UT's mesh with the tile of Minigun_burst its UVs use, blended as FB_Brighten (c + d(1 - c)), 5 a round that replace the last round's. Place and size match pictures of UT; ours is a more saturated orange where UT's is paler. | no: the ForceRingA rings of the punch and the ShieldCharge sparks are not drawn yet |
| Projectile model | - | ok (the shells are UT's ShellCasing mesh, drawn with the gun) | - |
| Trail | no: the bolt starts in the flare and has UT's width, brightness and fade, but its streak repeats the texture's zigzag evenly where UT's is ragged and branches (PT_Branch is in UT's engine, not its scripts). The arcs are the same. | ok (NewTracer: short yellow streaks, 400 by 10 units from EffectOffset, colour 1, 0.8, 0.5. A tracer lasts as long as it takes to reach the hit at 10000 units a second, so near a wall it is gone in a frame, as in UT) | - |
| Flare | ok (where the bolt hits, whole, not cut by the wall; the arcs' sparks burst out along what each arc hit, as many as UT's, bright at the head; UT's are thinner) | - | - |
| Smoke | - | - | - |
| Explosion shape | - | - | - |
| Explosion brightness | - | - | - |
| Explosion size | - | - | - |
| Impact marks | - | - | - |
| Vanilla effects playing on top | - | - | - |
| **Sounds** | | | |
| Fire | ok (sound plays) | ok | ok (BShieldGunFire) |
| Alt fire | ok (the zoom: BZoomIn1 and BZoomOut1, which LightningZoomIn and LightningZoomOut play as they are) | - | ok (BShield1 while the shield is up) |
| Select | ok (sound plays) | ok | ok |
| Load | ok (the charge-up after a shot, at the pitch of 1.1 that SniperFire.PlayFiring gives it) | - | ok (the charge sound) |
| Explosion | - | - | - |
| Lock beep | - | - | - |
| Volumes | - | - | - |
| Vanilla sounds playing on top | - | - | - |
| What others hear of a shot | - | - | - |
| What others hear of a load | - | - | - |
| Loops after unwielding | - | - | - |
| Loops after death | - | - | - |
| Loops after the level ends | - | - | - |
| **Third person** | | | |
| Size | - | - | - |
| Position in the hand | - | - | - |
| Angle | - | - | - |
| Vanilla model showing | - | - | - |
| Muzzle flash position | - | - | - |
| Shot animation for others | - | - | - |
| Fade near the camera | - | - | - |
| Outline | - | - | - |
| Bots holding it | - | - | - |
| Your character in the third person view | open: /ut_3p (the game's third_person_mode) shows the weapon in the hand but puts the camera at the head, where the character is faded out, so it can't be compared with UT yet. The charge sparks no longer show in it. | - | - |
| **Multiplayer** | | | |
| As host | ok | ok | - |
| As client | - | - | - |
| Others seeing projectiles | - | - | - |
| Others seeing explosions | - | - | - |
| Damage on the client | - | - | - |
| Ammo on the client | - | - | - |
| **Bots** | | | |
| Bots using it | - | - | - |
| Range they shoot from | - | - | - |
| Allies in the way | - | - | - |
| Look and sound of their shots | - | - | - |
| **Stability** | | | |
| Mod reload with it wielded | - | - | - |
| Level change while firing | - | - | - |
| Dying with it | - | - | - |
| Revive with it | - | - | - |
| Knockdown | - | - | - |
| Ledge hang | - | - | - |
| Switching away mid-animation | - | - | - |
| Switching back mid-animation | - | - | - |
| Errors in the console log | ok | ok | - |
| Crash dumps | ok | ok | - |
