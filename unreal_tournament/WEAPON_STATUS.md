# Weapon status

`WEAPON_CHECKLIST.md` for each weapon of the mod that was ported with it: what was found for each line. `ok`: checked in the game, against
UT2004 where there is something to compare with. `no`: wrong or missing, with what. `-`: not checked yet. `n/a`: does not apply.

| Line | Lightning Gun | Minigun | Shield Gun | Redeemer | Assault Rifle | Sniper Rifle | Shock Rifle | Flak Cannon |
|---|---|---|---|---|---|---|---|---|
| **Item and menus** | | | | | | | | |
| Name in the inventory | ok | ok | ok | ok | ok | - | ok | ok |
| Icon in the inventory | ok (points up-right) | ok (points up-right) | ok (points up-right) | ok (points up-right) | ok (points up-right) | - | ok (points up-right; the UT2003 and Instagib illusions have their own) | ok (points up-right) |
| Description | ok (UT's, shortened) | ok (UT's, without its last words) | ok (UT's, shortened) | - | ok (UT's, shortened) | - | ok (UT's, shortened) | ok (UT's, shortened) |
| Keywords | ok | ok (rapid fire, high damage, crowd control) | ok (high damage, charged attack, armour piercing) | - | - | - | ok (sniper, crowd control, and the mod's own: Combo) | ok (high damage, crowd control, versatile) |
| Stat chart | ok (a guess) | ok (the rounds barely stagger and stop at the first enemy; the alt goes through armour as the repeater does) | ok (the punch's cleave as tank blows: 3 for the bash, 4 for a charged punch; heavy damage 6) | - | - | - | ok (the beam as the light attack, the ball as the heavy one) | ok |
| Which careers can equip it | ok (the Deepwood Staff's copy for all four of Kerillian's careers; tests for each) | ok (repeating handgun and repeater pistol items; tests for each) | ok (five items: a melee weapon of each hero; the Warrior Priest's was taken out and is on the TODO list; tests for each) | ok (Ironbreaker, the Trollhammer's) | ok (the Brace of Pistols: Zealot, Bounty Hunter, Captain; tests for each) | ok (Kruber's and Bardin's handguns; tests for each) | ok (the Beam Staff's careers and the Necromancer; tests: the Battle Wizard) | ok (the Blunderbuss's careers; tests: the Mercenary) |
| Chaos Wastes copy | - | ok | - (each copy has its base's Chaos Wastes weapon) | - | - | - | - (the Beam Staff's Chaos Wastes weapon) | - (the Blunderbuss's Chaos Wastes weapon) |
| Crafting | - | ok | - | - | - | - | - | - |
| Hero screen: model and its place | ok (in the left hand, pointing ahead, on the Waystalker) | ok (UT's third person mesh, Minigun_3rd, at a player's DrawScale 0.4, in each hero's grip) | ok (UT's third person mesh at a player's DrawScale 0.4, in each hero's pose and grip, set in the game) | - | - | - | ok | ok (UT's third person mesh, Flak_3rd, at a player's DrawScale 0.4, held as the Blunderbuss; set in the game) |
| Item screen: model and its turn | - | ok | ok | - | - | - | ok | ok |
| Tab screen after a mod reload | no: the icon shows after the next level (game limit) | ok | ok | - | - | - | ok | ok |
| Equipping and switching weapons | ok | ok (tests: it can be put away while it fires) | ok | - | ok | - | ok | ok |
| Base weapon when the mod is disabled | - | ok (the template goes back to the base weapon's) | - (the template goes back to the base weapon's) | - | - | - | - (the template goes back to the Beam Staff's) | - (the template goes back to the Blunderbuss's) |
| **First person** | | | | | | | | |
| Position and size against UT | ok (blend with UT) | ok (side by side) | close: same size, UT's about 15 px higher and a little more tilted (the offline render agrees with the game) | ok (side by side; the Trollhammer's torpedo is hidden) | ok (side by side with UT's two rifles; the left one is UT's mesh mirrored, as RenderDualOverlay draws it) | - | ok (UT's view offset and pivot; the field of view was fitted against a picture of UT's Shock Rifle) | ok |
| Pickup animation | ok (UT's SelectAnimRate 1.25, side by side with UT) | ok (SelectAnimRate 1.3636) | ok (SelectAnimRate 1.3636) | - | ok (SelectAnimRate 1.3636, both rifles) | - | ok | ok |
| Idle animation speed | - | ok | ok | - | - | - | ok | ok |
| Fire animation of each mode | ok (Fire at UT's FireAnimRate 1.25, frames side by side with UT 25 ms apart; zoom has none) | ok (FireLoop, looped at FireLoopAnimRate 9 and 3 while a mode fires, as MinigunFire's FireLoop state) | ok (Charge over 2.5 s, Charged loop, Fire, Shield loop) | - | - | - | ok (Fire at 1, AltFire at ShockProjFire's 1.5) | ok |
| Animation length against the fire rate | - | ok (the loop plays for as long as the mode fires) | ok | - | - | - | ok | ok |
| Parts that move by code | - | ok (the barrels and the gear turn as Minigun.UpdateRoll, winding up and down at each mode's WindUpTime) | ok | - | - | - | ok (the chamber's gel flows as ShockPowerShader's, and its glow comes back after a shot) | ok |
| Inspect pose | - | ok | ok (set in the game) | - | - | - | ok (UT has none: brought in, turned to show its side, swaying) | ok |
| Inspect: first second of movement | - | ok | ok | - | - | - | ok | ok |
| Vanilla model or arms showing | - | ok | ok (the base weapon's units are hidden every frame, in the inspect too) | - | ok (the pistols and their ammo units are hidden) | - | ok | ok |
| Vanilla flash or particles showing | ok (the handgun's orange tracer is dropped) | ok (the repeater's tracer is dropped) | ok | - | - | - | ok (the staff's fireball, explosion and beam trail are not made) | ok |
| Crosshair | ok (the game's crosshair stays on while zoomed, over the scope; the scope side by side with UT: lens, ring, arrows, bar, under the HUD, shows right after a mod reload) | ok (the game's, with the repeater's spread for both copies) | ok | - | - | ok (the scope side by side with UT: brackets, ring, darkened edges) | ok | ok |
| Ammo number | - | ok | ok (the charge is a bar on the ammo counter in UT's green; the game's own bar still shows a wizard's overcharge) | - | no: the rounds are the clip; the grenade count (8) is not drawn | - | ok (the overcharge bar in ShockControl's purple) | ok |
| Bob and sway | - | ok (BobDamping 2.25) | ok | - | - | - | ok | ok |
| **Firing** | | | | | | | | |
| Fire rate of each mode | ok (tests: 1.6 s) | ok (tests: 15 and 5 rounds a second, after 0.27 and 0.15 s of wind up) | ok (FireRate 0.6 after a punch) | - | ok (tests: rounds at 0.088 s; grenades at 0.5 s + the charge) | ok (tests: 1.33 s) | ok (tests: the beam's 0.7 s; the ball's 0.6 s) | ok (tests: the chunks' 0.89 s; the shell's 1.11 s) |
| Second mode right after the first | - | ok (tests: the barrels stop and wind up again for the other mode, as Minigun.StartFire) | ok (tests: the shield goes up within 0.3 s of a punch) | - | - | - | ok (tests: the ball waits for the beam's fire rate) | ok (tests: the shell waits for the chunks' 0.89 s) |
| First mode right after the second | - | ok (tests: the same) | ok (tests: a punch right after the shield is let down) | - | - | - | ok (tests: the beam waits for the ball's 0.6 s) | ok (tests: the chunks wait for the shell's 1.11 s) |
| Hold, release and auto-fire | - | ok (tests: holding fires, letting go stops the rounds; a hit on the player doesn't stop them) | ok (tests: punch on release, auto punch with an enemy in reach) | - | ok (grenade charges while held, thrown on release, from each rifle in turn) | ok (tests: holding the button repeats the shot) | ok (tests: holding fire repeats the beam at its fire rate) | ok (tests: holding primary fire repeats it at its fire rate) |
| Where shots start | - | ok (the rounds from the eye; the tracers from EffectOffset) | ok (the punch's cone and ray start at the eye, where the crosshair is) | - | - | ok (tests: the hit is on the target aimed at) | ok (tests: the ball starts 8 UT units to the right of the eye, level with it: ProjSpawnOffset) | ok (tests: chunks 25 UT units ahead of the eye, 5 right and 6 down; the shell 25, 9 and 12 down: ProjSpawnOffset) |
| Shots start in the same place each time | - | ok | n/a | - | - | - | ok (tests) | ok (tests) |
| Shots in a line | - | n/a | n/a | - | - | - | - | - |
| Spread | - | ok (UT's: 0.08 and 0.03 of the aim's length, at random) | n/a (the punch hits what is in its cone) | - | ok (UT's: 0.02, 0.02 more a round up to 0.12, back after 0.5 s) | - | n/a (none, as UT's) | - (4 degrees, tighter than UT's 7.7) |
| Rapid shots | - | ok | n/a | - | - | - | - | - |
| **Damage** | | | | | | | | |
| Normal enemies | no: open. The test "damages an enemy" fails: a marauder spawned in the Keep has 0 health before it is hit, so the test can't measure damage there (the bolt does end on it) | ok (tests: a round hurts an enemy and stops at the first one; an alt round does twice a primary's, UT's 15 against 7.5) | ok (tests: punches kill rats in a horde, a punch while moving fast does more damage, a punch never hits the player who punches); 40 to 150 by the charge, reaching 122 UT units (the bash 162); it gets through enemies as the game's lighter tank blows do | - | - | - | ok (tests: a beam hurts what it hits and stops at the first enemy; a ball explodes on what it hits and hurts it) | ok (tests: chunks hurt an enemy; a shell hurts an enemy) |
| Armored enemies | - | ok (tests: primary rounds 0.5 against a Stormvermin and 0.3 against a Chaos warrior; alt rounds 0.8 and 0.5) | ok (tests: a punch hurts a Chaos warrior) | - | - | - | ok (tests: 0.5 of the damage against a Chaos warrior, whose body is super armour) | ok (tests: chunks 0.7 against a Stormvermin and 0.5 against a Chaos warrior; the shell 1 and 0.5) |
| Monsters | - | ok (tests: 1 against a rat ogre, taken down to 0.45 by the game's boss_damage_reduction) | ok (tests: a punch hurts a rat ogre) | - | - | - | ok (tests: 1.5 of the damage against a rat ogre, taken down to 0.45 by the game's boss_damage_reduction) | ok (tests: chunks 1 and the shell 1.5 against a rat ogre, taken down to 0.45 by the game's boss_damage_reduction) |
| Shields | - | ok (the rounds break shields, as the repeater's) | ok (a punch from the first third of the charge glances off a shield, one charged past it breaks the shield, and an unbreakable one stops both; tests for each) | - | - | - | - | - |
| Headshots | - | ok (tests: the game's usual bonus, 1.4 times; UT gives one only to its sniper weapons) | - | - | - | ok (tests: double damage) | - | - |
| Crits | - | ok (the same armour multipliers as any other hit) | - (the punch is a melee hit, with the game's melee crits) | - | - | - | - | - |
| Damage against the other UT weapons | - | ok | ok (the shield reflects the Shock Rifle's beam and ball and the Link Gun's bolts, by UT's rules; tests: a bot's beam and ball, from shield to shield, back and forth at most 3 times for the beam) | - | - | - | ok (tests: a beam into a ball makes a combo, which hurts much more than a beam; the Shield Gun's shield reflects the beam and the ball) | - |
| Self damage | - | n/a | ok (tests: a full punch at the floor hurts the player 26.5, UT's 8 + 0.3 of the damage, halved as the Rocket Launcher's; none when the punch hits an enemy or a thing) | ok (from the outermost wave, scaled as the Rocket Launcher's) | ok (the grenade's, reduced as the Rocket Launcher's) | - | ok (tests: a ball at the feet hurts the player; the combo hurts its shooter, 100 at the middle) | ok (tests: a shell at the feet hurts the player, at most 45; a chunk that has bounced, 8) |
| Explosion radius | - | n/a | n/a | ok (six waves growing over 1.3 s, tests; scaled down as the Rocket Launcher's) | ok (150 units, scaled as the Rocket Launcher's) | - | ok (tests: the ball's 90 UT units: it hurts an enemy 1.2 m away and not one 2.6 m away; the combo's 190, smaller than UT's 150 and 275) | ok (tests: the shell's 150 UT units, smaller than UT's 220: nothing 3.8 m away is hurt) |
| Explosion falloff | - | n/a | n/a | - | - | - | ok (tests: full damage within 0.5 m, then less and less to the radius) | ok (tests: full damage within 0.5 m, then less and less to the radius) |
| Momentum | - | n/a (UT's is 0) | - | - | - | - | - | - |
| Weapon jumping | - | n/a | ok in the game: a full punch at the floor throws the player up and back, with 0.6 of the momentum, as UT's own momentum is | - | - | - | ok (tests: a ball at the feet throws the player up) | ok (tests: a shell at the feet throws the player up) |
| Ragdolls | - | ok | - | - | - | - | - (the combo pulls what it killed back to its middle, as UT's) | - (what the chunks kill is thrown, harder up close) |
| Banners and barrels | - | ok | ok (tests: punches destroy a standard) | - | - | - | - (the combo hurts standards) | - |
| **Projectiles** | | | | | | | | |
| Speed | - | n/a | n/a | - | ok (850 to 1600 units a second by the charge) | - | ok (tests: a ball flies straight at 15 m/s) | - (chunks 35 m/s, between UT's 2500 units a second as sizes (50) and as run speeds (23); the shell 24 m/s) |
| Gravity | - | n/a | n/a | - | ok (UT's, simulated by the mod) | - | ok (none, as UT's; tests) | - (chunks none until they bounce, as UT's; the shell -17 m/s/s) |
| Lifetime | - | n/a | n/a | - | ok (2 s timer; tests) | - | ok (tests: a ball that hits nothing is gone after UT's 10 s) | - (chunks 2.7 s, the shell 6 s) |
| Hit size | - | n/a | n/a | - | - | - | - (0.2 m) | - (chunks 0.08 m, the shell 0.2 m) |
| Draw distance | - | n/a | n/a | - | - | - | - | - |
| Hitting other projectiles | - | n/a | ok (the right button is the base weapon's block, made a shield block, with stamina in place of UT's shield ammo. From its front it stops shots and explosions, reflects sorcerers' magic missiles, throws back gutter runners' pounces and stops lifeleeches' grabs; tests: an exploding barrel, a pounce, a grab) | - | - | - | ok (tests: a beam into a ball makes a combo) | - |
| Lock-on, homing, bounce, link, goo, combo | - | n/a | n/a | - | ok (bounce: 0.5 into the wall, 0.8 along it, stops below 20) | - | ok (combo: UT's, costs 3 beams of overcharge more; tests) | ok (bounce: tests: chunks bounce off the ground; a shell throws chunks) |
| **Ammo** | | | | | | | | |
| Max ammo | ok (40) | ok (300, all in the clip; tests) | n/a (no ammo: the shield takes stamina) | ok (1, tests) | ok (200 rounds, 8 grenades; tests) | ok (35; tests) | n/a (no ammo: a beam or a ball costs half a Beam Staff shot of overcharge; tests: overheating sets off a combo at the player) | ok (tests: 20, all in the clip) |
| Pickup amount | - | ok | n/a | - | - | - | n/a | - |
| Reload between shots | - | ok (none; tests) | n/a | - | - | ok (none; tests) | n/a | ok (none: tests) |
| Chamber at 0 ammo | - | ok (tests: with no ammo nothing is fired) | n/a | - | - | - | n/a | ok (tests: with no ammo left nothing is fired) |
| Chamber at the last round | - | ok | n/a | - | - | - | n/a | ok |
| Load animation when ammo comes back | - | n/a | n/a | - | - | - | n/a | ok |
| Load sound when ammo comes back | - | n/a | n/a | - | - | - | n/a | ok |
| Shot during a load animation | - | n/a | n/a | - | - | - | n/a | - |
| Multi-load at 1, 2 and 3 rounds | - | n/a | n/a | - | - | - | n/a | n/a |
| `/allammo` | - | ok | n/a | - | - | - | n/a | - |
| **Effects** | | | | | | | | |
| Muzzle flash | ok (white disk with a blue rim, size, place and fade side by side with UT; it reads its texture linearly, as UT adds it) | ok (MinigunMuzFlash1st: UT's mesh with the tile of Minigun_burst its UVs use, blended as FB_Brighten; a round adds 5 as there is room for, and each fades as it grows; NewMinigunMFlash in third person, at world size) | ok: ShieldCharge's green lines while charging, dim as UT's, turning about the gun; ForceRingA's rings on a punch, made smaller, dimmer and faster to be closer to UT's faint arc. The shield while it is up, and ShieldSparks when it stops something | - | close: AssaultMuzFlash1st is the Minigun's flash at DrawScale 1.2, so it has the Minigun's colour difference | - | ok (ShockMuzFlash) | ok |
| Projectile model | - | ok (the shells: UT's ShellCasing mesh, lit, thrown into the world from the ejector in both views) | n/a | ok (RedeemerMissile, turning, with its light and flight sound) | ok (UT's grenade mesh, spinning) | - | ok (ShockBall) | ok |
| Trail | no: the bolt starts in the flare and has UT's width, brightness and fade, but its streak repeats the texture's zigzag evenly where UT's is ragged and branches (PT_Branch is in UT's engine, not its scripts). The arcs are the same. | ok (NewTracer: short yellow streaks, 400 by 10 units from EffectOffset, colour 1, 0.8, 0.5. A tracer lasts as long as it takes to reach the hit at 10000 units a second, so near a wall it is gone in a frame, as in UT) | n/a | ok (NewRedeemerTrail: flames and smoke) | - | - | ok (ShockBeamEffect and its coil) | ok |
| Flare | ok (where the bolt hits, whole, not cut by the wall; the arcs' sparks burst out along what each arc hit, as many as UT's, bright at the head; UT's are thinner) | n/a | n/a | - | - | - | ok | ok |
| Smoke | - | ok (MinigunMuzzleSmoke at EffectOffset, an emitter for each mode; the alt's holds 15 puffs) | n/a | - | no: GrenadeSmokeTrail is not made | - | n/a | ok |
| Explosion shape | - | n/a | n/a | close: RedeemerExplosion's ten emitters with UT's numbers (puffs, flares, streaks, ring and spheres) and IonCore; the same sequence as UT's over 2 s | no: the Rocket Launcher's NewExplosionA in place of NewExplosionB | - | ok (ShockExplosion and ShockCombo, with the combo's sphere and vortex) | ok |
| Explosion brightness | - | n/a | n/a | - | - | - | ok | ok |
| Explosion size | - | n/a | n/a | - | - | - | ok | ok |
| Impact marks | - | ok (the game's impacts, with xHeavyWallHitEffect's sparks on the surfaces UT shows them on, and the alt fire's ExploWallHit) | ok | - | - | - | ok | ok |
| Vanilla effects playing on top | - | ok (the game's impacts are kept on purpose) | ok | - | - | - | ok | ok |
| **Sounds** | | | | | | | | |
| Fire | ok (sound plays) | ok (NewMinigunFire, a loop from the first round until the button is let go; the winding while the barrels turn without it) | ok (BShieldGunFire) | - | ok | - | ok | ok |
| Alt fire | ok (the zoom: BZoomIn1 and BZoomOut1, which LightningZoomIn and LightningZoomOut play as they are) | ok (minialtfireb, a loop) | ok (BShield1 while the shield is up) | no: the guided missile (RedeemerGuidedFire) is not made; the right button is the Trollhammer's block | ok (NewGrenadeShoot and the load sound) | - | ok | ok |
| Select | ok (sound plays) | ok | ok | - | ok | - | ok | ok |
| Load | ok (the charge-up after a shot, at the pitch of 1.1 that SniperFire.PlayFiring gives it) | n/a | ok (the charge sound) | - | - | - | n/a | ok |
| Explosion | - | n/a | n/a | - | ok (BExplosion3) | - | ok | ok |
| Lock beep | - | n/a | n/a | - | - | - | n/a | n/a |
| Volumes | - | ok | ok | - | - | - | ok | ok |
| Vanilla sounds playing on top | - | ok | ok | - | - | - | ok | ok |
| What others hear of a shot | - | ok (the fire loops in 3D, on the character) | ok (the punch in 3D; another player raising the shield is heard with UT's regeneration sound, which UT plays for the others) | - | - | - | ok | ok |
| What others hear of a load | - | n/a | ok (the charge loop in 3D) | - | - | - | n/a | ok |
| Loops after unwielding | - | ok | ok | - | - | - | ok | ok |
| Loops after death | - | ok | ok | - | - | - | ok | ok |
| Loops after the level ends | - | ok | ok | - | - | - | ok | ok |
| **Third person** | | | | | | | | |
| Size | - | ok (UT's Minigun_3rd at a player's DrawScale 0.4) | ok (UT's ShieldGun_3rd at a player's DrawScale 0.4) | - | - | - | ok | ok |
| Position in the hand | - | ok (each hero's grip, set in the game) | ok (each hero's grip, set in the game) | - | - | - | ok | ok |
| Angle | - | ok (the same) | ok (the same) | - | - | - | ok | ok |
| Vanilla model showing | - | ok | ok | - | - | - | ok | ok |
| Muzzle flash position | - | ok (locked to the gun's muzzle) | ok (the charge's sparks, the punch's rings and the shield at the end of the gun) | - | - | - | ok | ok |
| Shot animation for others | - | ok (Kruber the repeater's rapid fire; Saltzpyre holds the repeater pistol's aim while he fires) | ok (each hero's pose and push; the punches have no animation for Sienna and Kerillian, whose push is their staff's shot) | - | - | - | ok | ok |
| Fade near the camera | - | ok | ok | - | - | - | ok | ok |
| Outline | - | ok | ok | - | - | - | ok | ok |
| Bots holding it | - | ok | ok | - | - | - | ok | ok |
| Your character in the third person view | open: /ut_3p (the game's third_person_mode) shows the weapon in the hand but puts the camera at the head, where the character is faded out, so it can't be compared with UT yet. The charge sparks no longer show in it. | ok (the third person flash, barrels, shells and sounds) | ok (the first person effects are hidden in it, and the third person ones show) | - | - | - | ok | ok |
| **Multiplayer** | | | | | | | | |
| As host | ok | ok | ok | - | - | - | ok | ok |
| As client | - | ok | ok | - | - | - | ok | ok |
| Others seeing projectiles | - | ok (the tracers, hits and shells) | n/a | - | - | - | ok | ok |
| Others seeing explosions | - | n/a | n/a | - | - | - | ok | ok |
| Damage on the client | - | ok | ok | - | - | - | ok | ok |
| Ammo on the client | - | ok | n/a | - | - | - | n/a | ok |
| **Bots** | | | | | | | | |
| Bots using it | - | ok (a bot holds the button once it has fired, as with Bardin's rotary gun; tests: minigun_bots) | ok (tests: a bot fights rats with it; a heavy attack charges until an enemy is in reach, as UT's bots do, and a light one is a quick punch) | - | - | - | ok (tests: a bot shoots a special past the player, and a boss it can't reach; bosses within its reach a bot fights in melee, as the game's bots do; it fires the ball at elites, bosses and crowds: bots.lua) | ok (tests: a bot shoots a special past the player, and fires shells at a boss it can't reach; they fire the shell at elites, bosses and crowds: bots.lua) |
| Range they shoot from | - | ok (up to 25 m) | ok (tests: a bot punches only with an enemy within the punch's reach) | - | - | - | ok (tests: a special 17 m away) | ok (tests: a special 17 m away) |
| Allies in the way | - | ok (a bot doesn't shoot past an ally) | ok (tests: a bot fighting rats around the player never hurts them) | - | - | - | ok (tests: a bot shooting past the player never hurts them) | ok (tests: a bot shooting past the player never hurts them) |
| Look and sound of their shots | - | ok | ok | - | - | - | ok | ok |
| **Stability** | | | | | | | | |
| Mod reload with it wielded | - | ok | - | - | - | - | - | - |
| Level change while firing | - | ok | - | - | - | - | - | - |
| Dying with it | - | ok | - | - | - | - | - | - |
| Revive with it | - | ok | - | - | - | - | - | - |
| Knockdown | - | ok | - | - | - | - | - | - |
| Ledge hang | - | ok | - | - | - | - | - | - |
| Switching away mid-animation | - | ok (tests: put away while it fires, the rounds stop) | ok (tests: putting it away while it charges doesn't punch) | - | - | - | - | - |
| Switching back mid-animation | - | ok | ok (tests: taken out again, it charges and punches) | - | - | - | - | - |
| Errors in the console log | ok | ok | - | - | - | - | - | - |
| Crash dumps | ok | ok | - | - | - | - | - | - |
