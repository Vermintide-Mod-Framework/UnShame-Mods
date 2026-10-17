# Weapon status

`WEAPON_CHECKLIST.md` for each weapon of the mod that was ported with it: what was found for each line. `ok`: checked in the game, against
UT2004 where there is something to compare with. `no`: wrong or missing, with what. `-`: not checked yet. `n/a`: does not apply.

| Line | Lightning Gun | Minigun | Shield Gun | Redeemer | Assault Rifle | Sniper Rifle |
|---|---|---|---|---|---|---|
| **Item and menus** | | | | | | |
| Name in the inventory | ok | ok | ok | ok | ok | - |
| Icon in the inventory | ok (points up-right) | ok (points up-right) | ok (points up-right) | ok (points up-right) | ok (points up-right) | - |
| Description | ok (UT's, shortened) | ok | ok (UT's, shortened) | - | ok (UT's, shortened) | - |
| Keywords | ok | ok | ok (high damage, charged attack, armour piercing) | - | - | - |
| Stat chart | ok (a guess) | ok (a guess) | ok (the punch's cleave as tank blows: 3 for the bash, 4 for a charged punch; heavy damage 6) | - | - | - |
| Which careers can equip it | ok (the Deepwood Staff's copy for all four of Kerillian's careers; tests for each) | ok (repeating handgun and repeating crossbow items) | ok (five items: a melee weapon of each hero; the Warrior Priest's was taken out and is on the TODO list; tests for each) | ok (Ironbreaker, the Trollhammer's) | ok (the Brace of Pistols: Zealot, Bounty Hunter, Captain; tests for each) | ok (Kruber's and Bardin's handguns; tests for each) |
| Chaos Wastes copy | - | - | - (each copy has its base's Chaos Wastes weapon) | - | - | - |
| Crafting | - | - | - | - | - | - |
| Hero screen: model and its place | ok (in the left hand, pointing ahead, on the Waystalker) | - | ok (UT's third person mesh at a player's DrawScale 0.4, in each hero's pose and grip, set in the game) | - | - | - |
| Item screen: model and its turn | - | - | ok | - | - | - |
| Tab screen after a mod reload | no: the icon shows after the next level (game limit) | - | ok | - | - | - |
| Equipping and switching weapons | ok | ok | ok | - | ok | - |
| Base weapon when the mod is disabled | - | - | - (the template goes back to the base weapon's) | - | - | - |
| **First person** | | | | | | |
| Position and size against UT | ok (blend with UT) | ok (side by side) | close: same size, UT's about 15 px higher and a little more tilted (the offline render agrees with the game) | ok (side by side; the Trollhammer's torpedo is hidden) | ok (side by side with UT's two rifles; the left one is UT's mesh mirrored, as RenderDualOverlay draws it) | - |
| Pickup animation | ok (UT's SelectAnimRate 1.25, side by side with UT) | ok (SelectAnimRate 1.3636) | ok (SelectAnimRate 1.3636) | - | ok (SelectAnimRate 1.3636, both rifles) | - |
| Idle animation speed | - | - | ok | - | - | - |
| Fire animation of each mode | ok (Fire at UT's FireAnimRate 1.25, frames side by side with UT 25 ms apart; zoom has none) | - | ok (Charge over 2.5 s, Charged loop, Fire, Shield loop) | - | - | - |
| Animation length against the fire rate | - | - | ok | - | - | - |
| Parts that move by code | - | - | ok | - | - | - |
| Inspect pose | - | - | ok (set in the game) | - | - | - |
| Inspect: first second of movement | - | - | ok | - | - | - |
| Vanilla model or arms showing | - | - | ok (the base weapon's units are hidden every frame, in the inspect too) | - | ok (the pistols and their ammo units are hidden) | - |
| Vanilla flash or particles showing | ok (the handgun's orange tracer is dropped) | ok (the same) | ok | - | - | - |
| Crosshair | ok (the game's crosshair stays on while zoomed, over the scope; the scope side by side with UT: lens, ring, arrows, bar, under the HUD, shows right after a mod reload) | - | ok | - | - | ok (the scope side by side with UT: brackets, ring, darkened edges) |
| Ammo number | - | - | ok (the charge is a bar on the ammo counter in UT's green; the game's own bar still shows a wizard's overcharge) | - | no: the rounds are the clip; the grenade count (8) is not drawn | - |
| Bob and sway | - | - | ok | - | - | - |
| **Firing** | | | | | | |
| Fire rate of each mode | ok (tests: 1.6 s) | ok (tests) | ok (FireRate 0.6 after a punch) | - | ok (tests: rounds at 0.088 s; grenades at 0.5 s + the charge) | ok (tests: 1.33 s) |
| Second mode right after the first | - | - | ok (tests: the shield goes up within 0.3 s of a punch) | - | - | - |
| First mode right after the second | - | - | ok (tests: a punch right after the shield is let down) | - | - | - |
| Hold, release and auto-fire | - | - | ok (tests: punch on release, auto punch with an enemy in reach) | - | ok (grenade charges while held, thrown on release, from each rifle in turn) | ok (tests: holding the button repeats the shot) |
| Where shots start | - | - | ok (the punch's cone and ray start at the eye, where the crosshair is) | - | - | ok (tests: the hit is on the target aimed at) |
| Shots start in the same place each time | - | - | n/a | - | - | - |
| Shots in a line | - | - | n/a | - | - | - |
| Spread | - | - | n/a (the punch hits what is in its cone) | - | ok (UT's: 0.02, 0.02 more a round up to 0.12, back after 0.5 s) | - |
| Rapid shots | - | - | n/a | - | - | - |
| **Damage** | | | | | | |
| Normal enemies | no: open. The test "damages an enemy" fails: a marauder spawned in the Keep has 0 health before it is hit, so the test can't measure damage there (the bolt does end on it) | no: the same | ok (tests: punches kill rats in a horde, a punch while moving fast does more damage, a punch never hits the player who punches); 40 to 150 by the charge, reaching 122 UT units (the bash 162); it gets through enemies as the game's lighter tank blows do | - | - | - |
| Armored enemies | - | - | ok (tests: a punch hurts a Chaos warrior) | - | - | - |
| Monsters | - | - | ok (tests: a punch hurts a rat ogre) | - | - | - |
| Shields | - | - | ok (a punch from the first third of the charge glances off a shield, one charged past it breaks the shield, and an unbreakable one stops both; tests for each) | - | - | - |
| Headshots | - | - | - | - | - | ok (tests: double damage) |
| Crits | - | - | - (the punch is a melee hit, with the game's melee crits) | - | - | - |
| Damage against the other UT weapons | - | - | ok (the shield reflects the Shock Rifle's beam and ball and the Link Gun's bolts, by UT's rules; tests: a bot's beam and ball, from shield to shield, back and forth at most 3 times for the beam) | - | - | - |
| Self damage | - | - | ok (tests: a full punch at the floor hurts the player 26.5, UT's 8 + 0.3 of the damage, halved as the Rocket Launcher's; none when the punch hits an enemy or a thing) | ok (from the outermost wave, scaled as the Rocket Launcher's) | ok (the grenade's, reduced as the Rocket Launcher's) | - |
| Explosion radius | - | - | n/a | ok (six waves growing over 1.3 s, tests; scaled down as the Rocket Launcher's) | ok (150 units, scaled as the Rocket Launcher's) | - |
| Explosion falloff | - | - | n/a | - | - | - |
| Momentum | - | - | - | - | - | - |
| Weapon jumping | - | - | ok in the game: a full punch at the floor throws the player up and back, with 0.6 of the momentum, as UT's own momentum is | - | - | - |
| Ragdolls | - | - | - | - | - | - |
| Banners and barrels | - | - | ok (tests: punches destroy a standard) | - | - | - |
| **Projectiles** | | | | | | |
| Speed | - | - | n/a | - | ok (850 to 1600 units a second by the charge) | - |
| Gravity | - | - | n/a | - | ok (UT's, simulated by the mod) | - |
| Lifetime | - | - | n/a | - | ok (2 s timer; tests) | - |
| Hit size | - | - | n/a | - | - | - |
| Draw distance | - | - | n/a | - | - | - |
| Hitting other projectiles | - | - | ok (the right button is the base weapon's block, made a shield block, with stamina in place of UT's shield ammo. From its front it stops shots and explosions, reflects sorcerers' magic missiles, throws back gutter runners' pounces and stops lifeleeches' grabs; tests: an exploding barrel, a pounce, a grab) | - | - | - |
| Lock-on, homing, bounce, link, goo, combo | - | - | n/a | - | ok (bounce: 0.5 into the wall, 0.8 along it, stops below 20) | - |
| **Ammo** | | | | | | |
| Max ammo | ok (40) | ok (300) | n/a (no ammo: the shield takes stamina) | ok (1, tests) | ok (200 rounds, 8 grenades; tests) | ok (35; tests) |
| Pickup amount | - | - | n/a | - | - | - |
| Reload between shots | - | - | n/a | - | - | ok (none; tests) |
| Chamber at 0 ammo | - | - | n/a | - | - | - |
| Chamber at the last round | - | - | n/a | - | - | - |
| Load animation when ammo comes back | - | - | n/a | - | - | - |
| Load sound when ammo comes back | - | - | n/a | - | - | - |
| Shot during a load animation | - | - | n/a | - | - | - |
| Multi-load at 1, 2 and 3 rounds | - | - | n/a | - | - | - |
| `/allammo` | - | - | n/a | - | - | - |
| **Effects** | | | | | | |
| Muzzle flash | ok (white disk with a blue rim, size, place and fade side by side with UT; it reads its texture linearly, as UT adds it) | no: close. UT's mesh with the tile of Minigun_burst its UVs use, blended as FB_Brighten (c + d(1 - c)), 5 a round that replace the last round's. Place and size match pictures of UT; ours is a more saturated orange where UT's is paler. | ok: ShieldCharge's green lines while charging, dim as UT's, turning about the gun; ForceRingA's rings on a punch, made smaller, dimmer and faster to be closer to UT's faint arc. The shield while it is up, and ShieldSparks when it stops something | - | close: AssaultMuzFlash1st is the Minigun's flash at DrawScale 1.2, so it has the Minigun's colour difference | - |
| Projectile model | - | ok (the shells are UT's ShellCasing mesh, drawn with the gun) | n/a | ok (RedeemerMissile, turning, with its light and flight sound) | ok (UT's grenade mesh, spinning) | - |
| Trail | no: the bolt starts in the flare and has UT's width, brightness and fade, but its streak repeats the texture's zigzag evenly where UT's is ragged and branches (PT_Branch is in UT's engine, not its scripts). The arcs are the same. | ok (NewTracer: short yellow streaks, 400 by 10 units from EffectOffset, colour 1, 0.8, 0.5. A tracer lasts as long as it takes to reach the hit at 10000 units a second, so near a wall it is gone in a frame, as in UT) | n/a | ok (NewRedeemerTrail: flames and smoke) | - | - |
| Flare | ok (where the bolt hits, whole, not cut by the wall; the arcs' sparks burst out along what each arc hit, as many as UT's, bright at the head; UT's are thinner) | - | n/a | - | - | - |
| Smoke | - | - | n/a | - | no: GrenadeSmokeTrail is not made | - |
| Explosion shape | - | - | n/a | close: RedeemerExplosion's ten emitters with UT's numbers (puffs, flares, streaks, ring and spheres) and IonCore; the same sequence as UT's over 2 s | no: the Rocket Launcher's NewExplosionA in place of NewExplosionB | - |
| Explosion brightness | - | - | n/a | - | - | - |
| Explosion size | - | - | n/a | - | - | - |
| Impact marks | - | - | ok | - | - | - |
| Vanilla effects playing on top | - | - | ok | - | - | - |
| **Sounds** | | | | | | |
| Fire | ok (sound plays) | ok | ok (BShieldGunFire) | - | ok | - |
| Alt fire | ok (the zoom: BZoomIn1 and BZoomOut1, which LightningZoomIn and LightningZoomOut play as they are) | - | ok (BShield1 while the shield is up) | no: the guided missile (RedeemerGuidedFire) is not made; the right button is the Trollhammer's block | ok (NewGrenadeShoot and the load sound) | - |
| Select | ok (sound plays) | ok | ok | - | ok | - |
| Load | ok (the charge-up after a shot, at the pitch of 1.1 that SniperFire.PlayFiring gives it) | - | ok (the charge sound) | - | - | - |
| Explosion | - | - | n/a | - | ok (BExplosion3) | - |
| Lock beep | - | - | n/a | - | - | - |
| Volumes | - | - | ok | - | - | - |
| Vanilla sounds playing on top | - | - | ok | - | - | - |
| What others hear of a shot | - | - | ok (the punch in 3D; another player raising the shield is heard with UT's regeneration sound, which UT plays for the others) | - | - | - |
| What others hear of a load | - | - | ok (the charge loop in 3D) | - | - | - |
| Loops after unwielding | - | - | ok | - | - | - |
| Loops after death | - | - | ok | - | - | - |
| Loops after the level ends | - | - | ok | - | - | - |
| **Third person** | | | | | | |
| Size | - | - | ok (UT's ShieldGun_3rd at a player's DrawScale 0.4) | - | - | - |
| Position in the hand | - | - | ok (each hero's grip, set in the game) | - | - | - |
| Angle | - | - | ok (the same) | - | - | - |
| Vanilla model showing | - | - | ok | - | - | - |
| Muzzle flash position | - | - | ok (the charge's sparks, the punch's rings and the shield at the end of the gun) | - | - | - |
| Shot animation for others | - | - | ok (each hero's pose and push; the punches have no animation for Sienna and Kerillian, whose push is their staff's shot) | - | - | - |
| Fade near the camera | - | - | ok | - | - | - |
| Outline | - | - | ok | - | - | - |
| Bots holding it | - | - | ok | - | - | - |
| Your character in the third person view | open: /ut_3p (the game's third_person_mode) shows the weapon in the hand but puts the camera at the head, where the character is faded out, so it can't be compared with UT yet. The charge sparks no longer show in it. | - | ok (the first person effects are hidden in it, and the third person ones show) | - | - | - |
| **Multiplayer** | | | | | | |
| As host | ok | ok | ok | - | - | - |
| As client | - | - | ok | - | - | - |
| Others seeing projectiles | - | - | n/a | - | - | - |
| Others seeing explosions | - | - | n/a | - | - | - |
| Damage on the client | - | - | ok | - | - | - |
| Ammo on the client | - | - | n/a | - | - | - |
| **Bots** | | | | | | |
| Bots using it | - | - | ok (tests: a bot fights rats with it; a heavy attack charges until an enemy is in reach, as UT's bots do, and a light one is a quick punch) | - | - | - |
| Range they shoot from | - | - | ok (tests: a bot punches only with an enemy within the punch's reach) | - | - | - |
| Allies in the way | - | - | ok (tests: a bot fighting rats around the player never hurts them) | - | - | - |
| Look and sound of their shots | - | - | ok | - | - | - |
| **Stability** | | | | | | |
| Mod reload with it wielded | - | - | - | - | - | - |
| Level change while firing | - | - | - | - | - | - |
| Dying with it | - | - | - | - | - | - |
| Revive with it | - | - | - | - | - | - |
| Knockdown | - | - | - | - | - | - |
| Ledge hang | - | - | - | - | - | - |
| Switching away mid-animation | - | - | ok (tests: putting it away while it charges doesn't punch) | - | - | - |
| Switching back mid-animation | - | - | ok (tests: taken out again, it charges and punches) | - | - | - |
| Errors in the console log | ok | ok | - | - | - | - |
| Crash dumps | ok | ok | - | - | - | - |
