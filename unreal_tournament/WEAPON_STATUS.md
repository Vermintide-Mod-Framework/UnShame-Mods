# Weapon status

`WEAPON_CHECKLIST.md` for each weapon of the mod that was ported with it: what was found for each line. `ok`: checked in the game, against
UT2004 where there is something to compare with. `no`: wrong or missing, with what. `-`: not checked yet. `n/a`: does not apply.

| Line | Lightning Gun | Minigun |
|---|---|---|
| **Item and menus** | | |
| Name in the inventory | ok | ok |
| Icon in the inventory | ok (points up-right) | ok (points up-right) |
| Description | ok (UT's, shortened) | ok |
| Keywords | ok | ok |
| Stat chart | ok (a guess) | ok (a guess) |
| Which careers can equip it | ok (two items: Kruber's handgun and Bardin's) | ok (repeating handgun and repeating crossbow items) |
| Chaos Wastes copy | - | - |
| Crafting | - | - |
| Hero screen: model and its place | ok (held, size 0.5) | - |
| Item screen: model and its turn | - | - |
| Tab screen after a mod reload | no: the icon shows after the next level (game limit) | - |
| Equipping and switching weapons | ok | ok |
| Base weapon when the mod is disabled | - | - |
| **First person** | | |
| Position and size against UT | ok (blend with UT) | ok (side by side) |
| Pickup animation | ok (UT's SelectAnimRate 1.25, side by side with UT) | ok (SelectAnimRate 1.3636) |
| Idle animation speed | - | - |
| Fire animation of each mode | ok (Fire at UT's FireAnimRate 1.25, frames side by side with UT 25 ms apart; zoom has none) | - |
| Animation length against the fire rate | - | - |
| Parts that move by code | - | - |
| Inspect pose | - | - |
| Inspect: first second of movement | - | - |
| Vanilla model or arms showing | - | - |
| Vanilla flash or particles showing | ok (the handgun's orange tracer is dropped) | ok (the same) |
| Crosshair | ok (hidden while zoomed; the scope side by side with UT: lens, ring, arrows, bar, under the HUD, shows right after a mod reload) | - |
| Ammo number | - | - |
| Bob and sway | - | - |
| **Firing** | | |
| Fire rate of each mode | ok (tests: 1.6 s) | ok (tests) |
| Second mode right after the first | - | - |
| First mode right after the second | - | - |
| Hold, release and auto-fire | - | - |
| Where shots start | - | - |
| Shots start in the same place each time | - | - |
| Shots in a line | - | - |
| Spread | - | - |
| Rapid shots | - | - |
| **Damage** | | |
| Normal enemies | no: open. The test "damages an enemy" fails: a marauder spawned in the Keep has 0 health before it is hit, so the test can't measure damage there (the bolt does end on it) | no: the same |
| Armored enemies | - | - |
| Monsters | - | - |
| Shields | - | - |
| Headshots | - | - |
| Crits | - | - |
| Damage against the other UT weapons | - | - |
| Self damage | - | - |
| Explosion radius | - | - |
| Explosion falloff | - | - |
| Momentum | - | - |
| Weapon jumping | - | - |
| Ragdolls | - | - |
| Banners and barrels | - | - |
| **Projectiles** | | |
| Speed | - | - |
| Gravity | - | - |
| Lifetime | - | - |
| Hit size | - | - |
| Draw distance | - | - |
| Hitting other projectiles | - | - |
| Lock-on, homing, bounce, link, goo, combo | - | - |
| **Ammo** | | |
| Max ammo | ok (40) | ok (300) |
| Pickup amount | - | - |
| Reload between shots | - | - |
| Chamber at 0 ammo | - | - |
| Chamber at the last round | - | - |
| Load animation when ammo comes back | - | - |
| Load sound when ammo comes back | - | - |
| Shot during a load animation | - | - |
| Multi-load at 1, 2 and 3 rounds | - | - |
| `/loaded` | - | - |
| **Effects** | | |
| Muzzle flash | ok (white disk with a blue rim, size, place and fade side by side with UT; it reads its texture linearly, as UT adds it) | no: faint next to UT (see the Lightning Gun) |
| Projectile model | - | - |
| Trail | no: the bolt starts in the flare and has UT's width, brightness and fade, but its streak repeats the texture's zigzag evenly where UT's is ragged and branches (PT_Branch is in UT's engine, not its scripts). The arcs are the same. | no: the tracer is not seen |
| Flare | ok (where the bolt hits, whole, not cut by the wall; the arcs' sparks burst out along what each arc hit, as many as UT's, bright at the head; UT's are thinner) | - |
| Smoke | - | - |
| Explosion shape | - | - |
| Explosion brightness | - | - |
| Explosion size | - | - |
| Impact marks | - | - |
| Vanilla effects playing on top | - | - |
| **Sounds** | | |
| Fire | ok (sound plays) | ok |
| Alt fire | ok (the zoom: BZoomIn1 and BZoomOut1, which LightningZoomIn and LightningZoomOut play as they are) | - |
| Select | ok (sound plays) | ok |
| Load | - | - |
| Explosion | - | - |
| Lock beep | - | - |
| Volumes | - | - |
| Vanilla sounds playing on top | - | - |
| What others hear of a shot | - | - |
| What others hear of a load | - | - |
| Loops after unwielding | - | - |
| Loops after death | - | - |
| Loops after the level ends | - | - |
| **Third person** | | |
| Size | - | - |
| Position in the hand | - | - |
| Angle | - | - |
| Vanilla model showing | - | - |
| Muzzle flash position | - | - |
| Shot animation for others | - | - |
| Fade near the camera | - | - |
| Outline | - | - |
| Bots holding it | - | - |
| Your character in the third person view | - | - |
| **Multiplayer** | | |
| As host | ok | ok |
| As client | - | - |
| Others seeing projectiles | - | - |
| Others seeing explosions | - | - |
| Damage on the client | - | - |
| Ammo on the client | - | - |
| **Bots** | | |
| Bots using it | - | - |
| Range they shoot from | - | - |
| Allies in the way | - | - |
| Look and sound of their shots | - | - |
| **Stability** | | |
| Mod reload with it wielded | - | - |
| Level change while firing | - | - |
| Dying with it | - | - |
| Revive with it | - | - |
| Knockdown | - | - |
| Ledge hang | - | - |
| Switching away mid-animation | - | - |
| Switching back mid-animation | - | - |
| Errors in the console log | ok | ok |
| Crash dumps | ok | ok |
