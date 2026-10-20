# Weapon status

## Bases and careers

Which careers get which weapon, and which game weapon each one is copied from (`items.register` with `base_item`).

Each weapon is made for one hero, from the base that reaches the most of that hero's careers. The game does the same: its weapons are
items per hero (`es_`, `dr_`, `wh_`, `we_`, `bw_`), and an item's `can_wield` lists careers of that hero. A career of another hero
needs its own copy from a base of that hero, because the animations, units and attachments are made for the base's careers.

- Shock Rifle: the Beam Staff (`bw_skullstaff_beam`), for the Pyromancer, Battle Wizard, Unchained and Necromancer.
- Bio Rifle: the Masterwork Pistol (`dr_steam_pistol`, from the cog DLC), for the Engineer, Ranger and Ironbreaker.
- Flak Cannon: the Blunderbuss (`es_blunderbuss`), for the Mercenary, Huntsman and Foot Knight.
- Rocket Launcher: the Repeating Crossbow (`wh_crossbow_repeater`), for the Zealot, Bounty Hunter and Captain.
- Link Gun: the Deepwood Staff (`we_life_staff`, from the woods DLC), for the Sister of the Thorn. A Link Gun for everyone is on the
  TODO list.
- Shield Gun: a melee base for each hero, for everyone but the Warrior Priest (see below).
- Lightning Gun: the Deepwood Staff (`we_life_staff`, from the woods DLC), for all four of Kerillian's careers.
- Sniper Rifle (UT2004's classic one): the Handguns (`es_handgun`, `dr_handgun`), for the Mercenary, Huntsman, Foot Knight, Ironbreaker
  and Ranger.
- Assault Rifle (akimbo), in the melee slot: the Brace of Pistols (`wh_brace_of_pistols`), for the Zealot, Bounty Hunter and Captain,
  and the Drakefire Pistols (`dr_drake_pistol`), for the Ironbreaker, Ranger and Engineer.
- Minigun: the repeaters (`es_repeating_handgun`, `wh_repeating_pistols`), for the Mercenary, Huntsman, Foot Knight, Zealot, Bounty
  Hunter and Captain.
- Redeemer: not an item. It is the Bounty Hunter's career ability (Locked and Loaded) while he holds the Rocket Launcher, on his career
  pistol (`victor_bountyhunter_career_skill_weapon`).

The careers with few weapons:

- Slayer: the Shield Gun only. He has the game's Throwing Axes.
- Grail Knight: the Shield Gun only. No ranged item of the game lists him.
- Warrior Priest: none yet. No ranged item lists him, and his third person body has only his own weapons' animations. His Shield Gun
  is on the TODO list.
- Engineer: the Bio Rifle and the Shield Gun. His only ranged weapon in the game is the steam pistol.
- Ranger: the Bio Rifle, the Sniper Rifle and the Shield Gun.

Why the bases are what they are:

- Shield Gun. A melee base for each hero, so five registrations: Kruber's Bastard Sword (lake), Bardin's Cog Hammer (cog), Sienna's
  Ghost Scythe (shovel), Victor's Billhook (scorpion) and Kerillian's Spear (none). The Billhook doesn't reach the Warrior Priest,
  who has none. The Thornsister had no melee item in the item list.
- Assault Rifle. UT2004's rifle has a dual mode (`bDualMode`), and this one is always akimbo. The skins place one model in the first
  person view and one on the character, so a pair needs a second model for the other hand, in both. Bardin's only dual-wield
  weapon is the Drakefire Pistols, which only the Ironbreaker has, so his copy widens `can_wield` to the Ranger and the Engineer (the
  Engineer has the pistols in Versus, and Bardin's careers share one third person body). The characters play each base's alt attack
  stance and the shot from it: the Brace of Pistols' aim and fast shot, the Drakefire Pistols' charge and charged shot. It is in the
  melee slot, a gun beside the ranged weapon: for the game a melee weapon (its buff type, traits and bots) with a ranged weapon's properties, with endless
  rounds, counted grenades and no block.
- Lightning Gun. The Deepwood Staff's item lists only the Sister of the Thorn, but all four of Kerillian's careers share one third
  person body (`way_watcher`), which has the staff's animations, so the copy lists all four. Heat belongs to the career, not the weapon
  (`OverchargeData[career]`): the other three careers have none, which would overheat them as Sienna does, so they get the Sister's.
- Sniper Rifle. Kruber's handgun and Bardin's handgun are separate templates (`handgun_template_1` and `handgun_template_2`), so it
  is two registrations. The Engineer has no handgun.
- Redeemer. In VT2 the ranged slot fills again from every ammo box, which would give a one-shot nuke back far too often. A career
  ability comes back on a cooldown (160 s for the Redeemer, the game's longest is 140), and the Bounty Hunter's is a single shot from a
  pistol he draws for it, which the game already fires as a projectile. Holding the Rocket Launcher turns it into the Redeemer, so the
  game's ability is left as it is otherwise. UT's guided missile (its alt fire) is not made.
- The Necromancer can carry any staff in the game, but the local item list shows only her own staff. So the staff weapons name her
  in `can_wield` themselves (the Shock Rifle does).
- `items.register` copies the whole base item and clears its `required_dlc`, so a weapon of the mod does not need the DLC of its base
  (the DLCs above are only where the bases come from). The game loads every DLC's scripts and packages for everyone, so cloning a
  base does not need the DLC either. A career that is itself a DLC career is still locked by its own DLC.
- A career that equips an item it is not listed for crashes the game (see `CLAUDE.md`), so widening `can_wield` needs the first
  person and third person animations of that career to exist for the base.

Not planned:

- Impact Hammer: out of scope.
- Versus: out of scope. The weapons are for the heroes' careers; the Versus careers (the Skaven players, and the heroes' Versus-only
  weapons such as the Engineer's Trollhammer Torpedo) are not given any.
- Not in the plan so far: Translocator, Ion Painter, Mine Layer, AVRiL, Grenade Launcher and the Bombing Run ball launcher.

## Checklist

What to look at for each weapon of the mod, one thing a line, and what was found for each weapon that was ported. `ok`: checked in the game,
against UT2004 where there is something to compare with. `no`: wrong or missing, with what. `-`: not checked yet. `n/a`: does not apply.

| Line | Lightning Gun | Minigun | Shield Gun | Redeemer | Assault Rifle | Sniper Rifle | Shock Rifle | Flak Cannon | Bio Rifle | Rocket Launcher |
|---|---|---|---|---|---|---|---|---|---|---|
| **Item and menus** | | | | | | | | | | |
| Name in the inventory | ok | ok | ok | n/a (not an item: the Bounty Hunter's ability) | ok | ok | ok | ok | ok | ok |
| Icon in the inventory | ok (points up-right) | ok (points up-right) | ok (points up-right) | n/a | ok (points up-right) | ok | ok (points up-right; the UT2003 and Instagib illusions have their own) | ok (points up-right) | ok | ok |
| Description | ok (UT's, shortened) | ok (UT's, without its last words) | ok (UT's, shortened) | n/a (not an item) | ok (UT's, shortened) | ok | ok (UT's, shortened) | ok (UT's, shortened) | ok | ok |
| Keywords | ok | ok (rapid fire, high damage, crowd control) | ok (high damage, charged attack, armour piercing) | n/a | ok | ok (high damage, sniper, headshotting) | ok (sniper, crowd control, and the mod's own: Combo) | ok (high damage, crowd control, versatile) | ok | ok |
| Stat chart | ok (a guess) | ok (the rounds barely stagger and stop at the first enemy; the alt goes through most armour) | ok (the punch's cleave as tank blows: 3 for the bash, 4 for a charged punch; heavy damage 6) | n/a | ok | ok (against the Lightning Gun's: armour piercing 6, cleave 1, speed 3, stagger 4, damage 6) | ok (the beam as the light attack, the ball as the heavy one) | ok | ok | ok |
| Which careers can equip it | ok (the Deepwood Staff's copy for all four of Kerillian's careers; tests for each) | ok (repeating handgun and repeater pistol items; tests for each) | ok (five items: a melee weapon of each hero; the Warrior Priest's was taken out and is on the TODO list; tests for each) | ok (the Bounty Hunter's ability while he holds the Rocket Launcher, and the game's ability without it; tests) | ok (the Brace of Pistols: Zealot, Bounty Hunter, Captain; tests for each) | ok (Kruber's and Bardin's handguns; tests for each) | ok (the Beam Staff's careers and the Necromancer; tests: the Battle Wizard) | ok (the Blunderbuss's careers; tests: the Mercenary) | ok | ok |
| Chaos Wastes copy | ok | ok | ok (each copy has its base's Chaos Wastes weapon) | n/a | ok | ok | ok (the Beam Staff's Chaos Wastes weapon) | ok (the Blunderbuss's Chaos Wastes weapon) | ok | ok |
| Crafting | ok | ok | ok | n/a | ok | ok | ok | ok | ok | ok |
| Hero screen: model and its place | ok (in the left hand, pointing ahead, on the Waystalker) | ok (UT's third person mesh, Minigun_3rd, at a player's DrawScale 0.4, in each hero's grip) | ok (UT's third person mesh at a player's DrawScale 0.4, in each hero's pose and grip, set in the game) | n/a | ok | ok | ok | ok (UT's third person mesh, Flak_3rd, at a player's DrawScale 0.4, held as the Blunderbuss; set in the game) | ok | ok |
| Item screen: model and its turn | ok | ok | ok | n/a | ok | ok | ok | ok | ok | ok |
| Tab screen after a mod reload | ok (the icon shows from the next level: a game limit) | ok | ok | n/a | ok | ok | ok | ok | ok | ok |
| Equipping and switching weapons | ok | ok (tests: it can be put away while it fires) | ok | n/a | ok | ok | ok | ok | ok | ok |
| Base weapon when the mod is disabled | ok | ok (the template goes back to the base weapon's) | ok (the template goes back to the base weapon's) | n/a | ok | ok | ok (the template goes back to the Beam Staff's) | ok (the template goes back to the Blunderbuss's) | ok | ok |
| **First person** | | | | | | | | | | |
| Position and size against UT | ok (blend with UT) | ok (side by side) | ok (the same size; UT's is about 15 px higher and a little more tilted, and the offline render agrees with the game) | ok | ok (side by side with UT's two rifles; the left one is UT's mesh mirrored, as RenderDualOverlay draws it) | ok | ok (UT's view offset and pivot; the field of view was fitted against a picture of UT's Shock Rifle) | ok | ok | ok |
| Pickup animation | ok (UT's SelectAnimRate 1.25, side by side with UT) | ok (SelectAnimRate 1.3636) | ok (SelectAnimRate 1.3636) | ok | ok (SelectAnimRate 1.3636, both rifles) | ok | ok | ok | ok | ok |
| Idle animation speed | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| Fire animation of each mode | ok (Fire at UT's FireAnimRate 1.25, frames side by side with UT 25 ms apart; zoom has none) | ok (FireLoop, looped at FireLoopAnimRate 9 and 3 while a mode fires, as MinigunFire's FireLoop state) | ok (Charge over 2.5 s, Charged loop, Fire, Shield loop) | ok | ok | ok | ok (Fire at 1, AltFire at ShockProjFire's 1.5) | ok | ok | ok |
| Animation length against the fire rate | ok | ok (the loop plays for as long as the mode fires) | ok | ok | ok | ok | ok | ok | ok | ok |
| Parts that move by code | ok (the screen's texture scrolls) | ok (the barrels and the gear turn as Minigun.UpdateRoll, winding up and down at each mode's WindUpTime) | ok | ok | ok | ok | ok (the chamber's gel flows as ShockPowerShader's, and its glow comes back after a shot) | ok | ok | ok |
| Inspect pose | ok (set in the game; the overheat lockout tips the gun up) | ok | ok (set in the game) | ok | ok | ok (set in the game, turned away from the camera) | ok (UT has none: brought in, turned to show its side, swaying) | ok | ok | ok |
| Inspect: first second of movement | ok | ok | ok | ok | ok | ok (it turns as it moves in, not about its middle) | ok | ok | ok | ok |
| Vanilla model or arms showing | ok | ok | ok (the base weapon's units are hidden every frame, in the inspect too) | ok | ok (the pistols and their ammo units are hidden) | ok | ok | ok | ok | ok |
| Vanilla flash or particles showing | ok (the handgun's orange tracer is dropped) | ok (the repeater's tracer is dropped) | ok | ok | ok | ok | ok (the staff's fireball, explosion and beam trail are not made) | ok | ok | ok |
| Crosshair | ok (the game's crosshair stays on while zoomed, over the scope; the scope side by side with UT: lens, ring, arrows, bar, under the HUD, shows right after a mod reload) | ok (the game's, with the repeater's spread for both copies) | ok | ok | ok | ok (the scope side by side with UT: brackets, ring, darkened edges) | ok | ok | ok | ok |
| Ammo number | ok (the overcharge bar, white between its thresholds and above them) | ok | ok (the charge is a bar on the ammo counter in UT's green; the game's own bar still shows a wizard's overcharge) | ok | ok (no rounds to count, they are endless; the grenade's charge bar, white, below the ranged weapon's counter, and the grenades left as icons, as long as the bar at 8) | ok | ok (the overcharge bar in ShockControl's purple) | ok | ok | ok |
| Bob and sway | ok | ok (BobDamping 2.25) | ok | ok | ok | ok | ok | ok | ok | ok |
| **Firing** | | | | | | | | | | |
| Fire rate of each mode | ok (tests: 1.6 s) | ok (tests: 15 and 5 rounds a second, after 0.27 and 0.15 s of wind up) | ok (FireRate 0.6 after a punch) | ok | ok (tests: rounds at 0.088 s; grenades at 0.5 s + the charge) | ok (tests: 1.33 s) | ok (tests: the beam's 0.7 s; the ball's 0.6 s) | ok (tests: the chunks' 0.89 s; the shell's 1.11 s) | ok | ok |
| Second mode right after the first | ok (tests: the zoom button right after a shot zooms in, and the next press zooms out) | ok (tests: the barrels stop and wind up again for the other mode, as Minigun.StartFire) | ok (tests: the shield goes up within 0.3 s of a punch) | n/a (one shot) | ok | ok | ok (tests: the ball waits for the beam's fire rate) | ok (tests: the shell waits for the chunks' 0.89 s) | ok | ok |
| First mode right after the second | ok (tests: a shot right after the zoom waits for its fire time) | ok (tests: the same) | ok (tests: a punch right after the shield is let down) | n/a | ok | ok | ok (tests: the beam waits for the ball's 0.6 s) | ok (tests: the chunks wait for the shell's 1.11 s) | ok | ok |
| Hold, release and auto-fire | ok (tests: holding the button repeats the shot every 1.6 s) | ok (tests: holding fires, letting go stops the rounds; a hit on the player doesn't stop them) | ok (tests: punch on release, auto punch with an enemy in reach) | ok | ok (grenade charges while held, thrown on release, from each rifle in turn) | ok (tests: holding the button repeats the shot) | ok (tests: holding fire repeats the beam at its fire rate) | ok (tests: holding primary fire repeats it at its fire rate) | ok | ok |
| Where shots start | ok (the bolt from the flare at EffectOffset; zoomed, from below the view) | ok (the rounds from the eye; the tracers from EffectOffset) | ok (the punch's cone and ray start at the eye, where the crosshair is) | ok | ok | ok (tests: the hit is on the target aimed at) | ok (tests: the ball starts 8 UT units to the right of the eye, level with it: ProjSpawnOffset) | ok (tests: chunks 25 UT units ahead of the eye, 5 right and 6 down; the shell 25, 9 and 12 down: ProjSpawnOffset) | ok | ok |
| Shots start in the same place each time | ok | ok | n/a | ok | ok | ok | ok (tests) | ok (tests) | ok | ok |
| Shots in a line | n/a | n/a | n/a | ok | ok | ok (tests: the bullet stops at the first enemy) | ok | ok | ok | ok |
| Spread | n/a (none, as UT's) | ok (UT's: 0.08 and 0.03 of the aim's length, at random) | n/a (the punch hits what is in its cone) | ok | ok (UT's: 0.02, 0.02 more a round up to 0.12, back after 0.5 s) | n/a (none, as UT's) | n/a (none, as UT's) | ok (4 degrees, tighter than UT's 7.7) | n/a (none, as UT's) | ok |
| Rapid shots | n/a | ok | n/a | ok | ok | n/a | ok | ok | ok | ok |
| **Damage** | | | | | | | | | | |
| Normal enemies | ok (tests: a bolt hurts an enemy; an arc does half its damage to an enemy near the one hit) | ok (tests: a round hurts an enemy and stops at the first one; an alt round does twice a primary's, UT's 15 against 7.5) | ok (tests: punches kill rats in a horde, a punch while moving fast does more damage, a punch never hits the player who punches); 40 to 150 by the charge, reaching 122 UT units (the bash 162); it gets through enemies as the game's lighter tank blows do | ok | ok | ok (UT's 60 a shot; tests: a shot hurts a Chaos marauder) | ok (tests: a beam hurts what it hits and stops at the first enemy; a ball explodes on what it hits and hurts it) | ok (tests: chunks hurt an enemy; a shell hurts an enemy) | ok | ok |
| Armored enemies | ok (tests: 1 against a Stormvermin, 0.6 against a Chaos warrior) | ok (tests: primary rounds 0.5 against a Stormvermin and 0.3 against a Chaos warrior; alt rounds 0.9 and 0.6) | ok (tests: a punch hurts a Chaos warrior) | ok | ok (the rounds 0.5 against armor and none against super armor, critical hits too; the grenades 1 and 0.5) | ok (tests: 0.8 against a Stormvermin, 0.6 against a Chaos warrior, whose body is super armour) | ok (tests: 0.5 of the damage against a Chaos warrior, whose body is super armour) | ok (tests: chunks 0.7 against a Stormvermin and 0.5 against a Chaos warrior; the shell 1 and 0.5) | ok | ok |
| Monsters | ok (tests: 1.2 against a rat ogre, taken down to 0.45 by the game's boss_damage_reduction) | ok (tests: 1 against a rat ogre, taken down to 0.45 by the game's boss_damage_reduction) | ok (tests: a punch hurts a rat ogre) | ok | ok | ok (tests: 1.5 against a rat ogre, taken down to 0.45 by the game's boss_damage_reduction) | ok (tests: 1.5 of the damage against a rat ogre, taken down to 0.45 by the game's boss_damage_reduction) | ok (tests: chunks 1 and the shell 1.5 against a rat ogre, taken down to 0.45 by the game's boss_damage_reduction) | ok | ok |
| Shields | ok (the bolt breaks shields) | ok (the rounds break shields, as the repeater's) | ok (a punch from the first third of the charge glances off a shield, one charged past it breaks the shield, and an unbreakable one stops both; tests for each) | ok | ok | ok | ok | ok | ok | ok |
| Headshots | ok (tests: double damage, SniperFire.HeadShotDamageMult) | ok (tests: the game's usual bonus, 1.4 times; UT gives one only to its sniper weapons) | ok | ok | ok | ok (tests: double damage) | ok | ok | ok | ok |
| Crits | ok (the same armour multipliers as any other hit) | ok (the same armour multipliers as any other hit) | ok (the punch is a melee hit, with the game's melee crits) | ok | ok | ok (the handgun's armour multipliers; tests: a critical shot hurts a Chaos warrior) | ok | ok | ok | ok |
| Damage against the other UT weapons | ok | ok | ok (the shield reflects the Shock Rifle's beam and ball and the Link Gun's bolts, by UT's rules; tests: a bot's beam and ball, from shield to shield, back and forth at most 3 times for the beam) | ok | ok | ok (0.93 attack power a shot and 0.70 a second, with the Lightning Gun's 1.09 and 0.68) | ok (tests: a beam into a ball makes a combo, which hurts much more than a beam; the Shield Gun's shield reflects the beam and the ball) | ok | ok | ok |
| Self damage | n/a | n/a | ok (tests: a full punch at the floor hurts the player 26.5, UT's 8 + 0.3 of the damage, halved as the Rocket Launcher's; none when the punch hits an enemy or a thing) | ok (from the outermost wave, scaled as the Rocket Launcher's) | ok (the grenade's, reduced as the Rocket Launcher's) | n/a | ok (tests: a ball at the feet hurts the player; the combo hurts its shooter, 100 at the middle) | ok (tests: a shell at the feet hurts the player, at most 45; a chunk that has bounced, 8) | ok | ok |
| Explosion radius | n/a | n/a | n/a | ok (six waves growing over 1.3 s, tests; scaled down as the Rocket Launcher's) | ok (150 units, scaled as the Rocket Launcher's) | n/a | ok (tests: the ball's 90 UT units: it hurts an enemy 1.2 m away and not one 2.6 m away; the combo's 190, smaller than UT's 150 and 275) | ok (tests: the shell's 150 UT units, smaller than UT's 220: nothing 3.8 m away is hurt) | ok | ok |
| Explosion falloff | n/a | n/a | n/a | ok | ok | n/a | ok (tests: full damage within 0.5 m, then less and less to the radius) | ok (tests: full damage within 0.5 m, then less and less to the radius) | ok | ok |
| Momentum | ok | n/a (UT's is 0) | ok | ok | ok | ok | ok | ok | ok | ok |
| Weapon jumping | n/a | n/a | ok in the game: a full punch at the floor throws the player up and back, with 0.6 of the momentum, as UT's own momentum is | ok | ok | n/a | ok (tests: a ball at the feet throws the player up) | ok (tests: a shell at the feet throws the player up) | ok | ok |
| Ragdolls | ok | ok | ok | ok | ok | ok | ok (the combo pulls what it killed back to its middle, as UT's) | ok (what the chunks kill is thrown, harder up close) | ok | ok |
| Banners and barrels | ok | ok | ok (tests: punches destroy a standard) | ok | ok | ok | ok (the combo hurts standards) | ok | ok | ok |
| **Projectiles** | | | | | | | | | | |
| Speed | n/a (the bolt hits at once) | n/a | n/a | ok | ok (850 to 1600 units a second by the charge) | n/a (the bullet hits at once) | ok (tests: a ball flies straight at 15 m/s) | ok (chunks 35 m/s, between UT's 2500 units a second as sizes (50) and as run speeds (23); the shell 24 m/s) | ok | ok |
| Gravity | n/a | n/a | n/a | ok | ok (UT's, simulated by the mod) | n/a | ok (none, as UT's; tests) | ok (chunks none until they bounce, as UT's; the shell -17 m/s/s) | ok | ok |
| Lifetime | n/a | n/a | n/a | ok | ok (2 s timer; tests) | n/a | ok (tests: a ball that hits nothing is gone after UT's 10 s) | ok (chunks 2.7 s, the shell 6 s) | ok | ok |
| Hit size | n/a | n/a | n/a | ok | ok | n/a | ok (0.2 m) | ok (chunks 0.08 m, the shell 0.2 m) | ok | ok |
| Draw distance | n/a | n/a | n/a | ok | ok | n/a | ok | ok | ok | ok |
| Hitting other projectiles | n/a | n/a | ok (the right button is the base weapon's block, made a shield block, with stamina in place of UT's shield ammo. From its front it stops shots and explosions, reflects sorcerers' magic missiles, throws back gutter runners' pounces and stops lifeleeches' grabs; tests: an exploding barrel, a pounce, a grab) | ok | ok | n/a | ok (tests: a beam into a ball makes a combo) | ok | ok | ok |
| Lock-on, homing, bounce, link, goo, combo | n/a | n/a | n/a | n/a | ok (bounce: 0.5 into the wall, 0.8 along it, stops below 20) | n/a | ok (combo: UT's, costs 3 beams of overcharge more; tests) | ok (bounce: tests: chunks bounce off the ground; a shell throws chunks) | ok | ok |
| **Ammo** | | | | | | | | | | |
| Max ammo | ok (40) | ok (300, all in the clip; tests) | n/a (no ammo: the shield takes stamina) | n/a (one missile each time the ability is used; the cooldown is 160 s, tests) | ok (endless rounds, as a melee weapon has no ammo; 8 grenades; tests) | ok (30; tests) | n/a (no ammo: a beam or a ball costs half a Beam Staff shot of overcharge; tests: overheating sets off a combo at the player) | ok (tests: 20, all in the clip) | ok | ok |
| Pickup amount | n/a (heat, no ammo) | ok | n/a | n/a (a cooldown, no ammo) | ok (an ammo box fills the grenades; tests) | ok | n/a | ok | ok | ok |
| Reload between shots | n/a | ok (none; tests) | n/a | n/a | ok | ok (none; tests) | n/a | ok (none: tests) | ok | ok |
| Chamber at 0 ammo | n/a | ok (tests: with no ammo nothing is fired) | n/a | n/a | n/a (endless rounds) | ok | n/a | ok (tests: with no ammo left nothing is fired) | ok | ok |
| Chamber at the last round | n/a | ok | n/a | n/a | ok | ok | n/a | ok | ok | ok |
| Load animation when ammo comes back | n/a | n/a | n/a | n/a | n/a (no reload) | n/a (no reload) | n/a | ok | ok | ok |
| Load sound when ammo comes back | n/a | n/a | n/a | n/a | n/a | n/a | n/a | ok | ok | ok |
| Shot during a load animation | n/a | n/a | n/a | n/a | ok | n/a | n/a | ok | ok | ok |
| Multi-load at 1, 2 and 3 rounds | n/a | n/a | n/a | n/a | ok | n/a | n/a | n/a | n/a | ok |
| `/allammo` | n/a | ok | n/a | n/a (`/recharge` fills the ability) | ok (fills the grenades) | ok | n/a | ok | ok | ok |
| **Effects** | | | | | | | | | | |
| Muzzle flash | ok (white disk with a blue rim, size, place and fade side by side with UT; it reads its texture linearly, as UT adds it) | ok (MinigunMuzFlash1st: UT's mesh with the tile of Minigun_burst its UVs use, blended as FB_Brighten; a round adds 5 as there is room for, and each fades as it grows; NewMinigunMFlash in third person, at world size) | ok: ShieldCharge's green lines while charging, dim as UT's, turning about the gun; ForceRingA's rings on a punch, made smaller, dimmer and faster to be closer to UT's faint arc. The shield while it is up, and ShieldSparks when it stops something | ok | ok (AssaultMuzFlash1st: the Minigun's flash at DrawScale 1.2, read as srgb and faded in gamma space as UT draws it) | ok (in first person a flash that grows and fades in steps; in third person MinigunFlashMesh's growing meshes) | ok (ShockMuzFlash) | ok | ok | ok |
| Projectile model | n/a | ok (the shells: UT's ShellCasing mesh, lit, thrown into the world from the ejector in both views) | n/a | ok (RedeemerMissile, turning, with its light and flight sound) | ok (UT's grenade mesh, spinning) | n/a | ok (ShockBall) | ok | ok | ok |
| Trail | ok (the bolt starts in the flare and has UT's width, brightness and fade; its zigzags are drawn out along it, with a line through them, and the arcs are single long zigzags, set against pictures of UT) | ok (NewTracer: short yellow streaks, 400 by 10 units from EffectOffset, colour 1, 0.8, 0.5. A tracer lasts as long as it takes to reach the hit at 10000 units a second, so near a wall it is gone in a frame, as in UT) | n/a | ok (NewRedeemerTrail: flames and smoke) | ok | ok | ok (ShockBeamEffect and its coil) | ok | ok | ok |
| Flare | ok (where the bolt hits, whole, not cut by the wall; the arcs' sparks burst out along what each arc hit, as many as UT's, bright at the head; UT's are thinner) | n/a | n/a | ok | ok | ok | ok | ok | ok | ok |
| Smoke | n/a | ok (MinigunMuzzleSmoke at EffectOffset, an emitter for each mode; the alt's holds 15 puffs) | n/a | ok | ok (GrenadeSmokeTrail's puffs, blended, with ScaleGlow in their colour) | ok (ClassicSniperSmoke, against pictures of UT) | n/a | ok | ok | ok |
| Explosion shape | n/a | n/a | n/a | ok (RedeemerExplosion's ten emitters with UT's numbers (puffs, flares, streaks, ring and spheres) and IonCore; the same sequence as UT's over 2 s) | ok (NewExplosionB: three fireballs of exp1_frames, larger and spread within the sphere, no flash; BExplosion3 at the rocket's volume) | n/a | ok (ShockExplosion and ShockCombo, with the combo's sphere and vortex) | ok | ok | ok |
| Explosion brightness | n/a | n/a | n/a | ok | ok | n/a | ok | ok | ok | ok |
| Explosion size | n/a | n/a | n/a | ok | ok | n/a | ok | ok | ok | ok |
| Impact marks | ok (none, as UT's) | ok (the game's impacts, with xHeavyWallHitEffect's sparks on the surfaces UT shows them on, and the alt fire's ExploWallHit) | ok | ok | ok | ok | ok | ok | ok | ok |
| Vanilla effects playing on top | ok | ok (the game's impacts are kept on purpose) | ok | ok | ok | ok (the handgun's third person flash and sound are not played; tests) | ok | ok | ok | ok |
| **Sounds** | | | | | | | | | | |
| Fire | ok (sound plays) | ok (NewMinigunFire, a loop from the first round until the button is let go; the winding while the barrels turn without it) | ok (BShieldGunFire) | ok | ok | ok | ok | ok | ok | ok |
| Alt fire | ok (the zoom: BZoomIn1 and BZoomOut1, which LightningZoomIn and LightningZoomOut play as they are) | ok (minialtfireb, a loop) | ok (BShield1 while the shield is up) | n/a (the guided missile, RedeemerGuidedFire, is not made: the ability has one shot) | ok (NewGrenadeShoot and the load sound) | ok (the zoom: the zoom-in sound starts again every frame the view narrows, the zoom-out sound when the button is let go and when the zoom ends) | ok | ok | ok | ok |
| Select | ok (sound plays) | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| Load | ok (the charge-up after a shot, at the pitch of 1.1 that SniperFire.PlayFiring gives it) | n/a | ok (the charge sound) | n/a | ok | n/a | n/a | ok | ok | ok |
| Explosion | n/a | n/a | n/a | ok | ok (BExplosion3) | n/a | ok | ok | ok | ok |
| Lock beep | n/a | n/a | n/a | n/a | ok | n/a | n/a | n/a | n/a | ok |
| Volumes | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| Vanilla sounds playing on top | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| What others hear of a shot | ok (the shot and the bolt's impact in 3D) | ok (the fire loops in 3D, on the character) | ok (the punch in 3D; another player raising the shield is heard with UT's regeneration sound, which UT plays for the others) | ok | ok | ok | ok | ok | ok | ok |
| What others hear of a load | n/a | n/a | ok (the charge loop in 3D) | n/a | ok | n/a | n/a | ok | ok | ok |
| Loops after unwielding | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| Loops after death | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| Loops after the level ends | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| **Third person** | | | | | | | | | | |
| Size | ok (UT's Sniper_3rd at a player's DrawScale 0.4, made 0.85 of it for Kerillian) | ok (UT's Minigun_3rd at a player's DrawScale 0.4) | ok (UT's ShieldGun_3rd at a player's DrawScale 0.4) | ok (UT's Redeemer_3rd at RedeemerAttachment's DrawScale 0.6, made 0.96 of it in the game) | ok | ok | ok | ok | ok | ok |
| Position in the hand | ok (set in the game) | ok (each hero's grip, set in the game) | ok (each hero's grip, set in the game) | ok (alongside the left arm, set in the game) | ok | ok (each hero's grip, set in the game) | ok | ok | ok | ok |
| Angle | ok (set in the game) | ok (the same) | ok (the same) | ok | ok | ok (set in the game) | ok | ok | ok | ok |
| Vanilla model showing | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| Muzzle flash position | ok (the bolt and its flare from the muzzle; the charge's sparks behind the tip, LightningCharge3rd; the shot's light, WeaponLight) | ok (locked to the gun's muzzle) | ok (the charge's sparks, the punch's rings and the shield at the end of the gun) | ok | ok | ok (at the muzzle, set in the game) | ok | ok | ok | ok |
| Shot animation for others | ok (none, as UT's characters only hold the gun; the vent's is kept) | ok (Kruber the repeater's rapid fire; Saltzpyre holds the repeater pistol's aim while he fires) | ok (each hero's pose and push; the punches have no animation for Sienna and Kerillian, whose push is their staff's shot) | ok | ok | ok (the handgun's; after a zoomed shot the character aims again at 0.5 s, set in the game) | ok | ok | ok | ok |
| Fade near the camera | ok (the charge's sparks fade with the character) | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| Outline | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| Bots holding it | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| Your character in the third person view | ok (/freecamera) | ok (the third person flash, barrels, shells and sounds) | ok (the first person effects are hidden in it, and the third person ones show) | ok | ok | ok (/freecamera: the zoom stays in, but the view is not zoomed) | ok | ok | ok | ok |
| **Multiplayer** | | | | | | | | | | |
| As host | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| As client | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| Others seeing projectiles | ok (the bolts and the arcs) | ok (the tracers, hits and shells) | n/a | ok | ok | ok | ok | ok | ok | ok |
| Others seeing explosions | n/a | n/a | n/a | ok | ok | ok | ok | ok | ok | ok |
| Damage on the client | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| Ammo on the client | ok (the heat) | ok | n/a | n/a | ok (the grenades) | ok | n/a | ok | ok | ok |
| **Bots** | | | | | | | | | | |
| Bots using it | ok (they aim at the head and vent above the threshold too; tests: lightning_bots) | ok (a bot holds the button once it has fired, as with Bardin's rotary gun; tests: minigun_bots) | ok (tests: a bot fights rats with it; a heavy attack charges until an enemy is in reach, as UT's bots do, and a light one is a quick punch) | ok | ? (its melee weapon: a bot holds fire at an enemy within 5 m and doesn't defend or throw grenades; tests: assault_bots) | ok | ok (tests: a bot shoots a special past the player, and a boss it can't reach; bosses within its reach a bot fights in melee, as the game's bots do; it fires the ball at elites, bosses and crowds: bots.lua) | ok (tests: a bot shoots a special past the player, and fires shells at a boss it can't reach; they fire the shell at elites, bosses and crowds: bots.lua) | ok | ok |
| Range they shoot from | ok (up to 60 m) | ok (up to 25 m) | ok (tests: a bot punches only with an enemy within the punch's reach) | ok | ok | ok | ok (tests: a special 17 m away) | ok (tests: a special 17 m away) | ok | ok |
| Allies in the way | ok (tests: a bot never hurts the player) | ok (a bot doesn't shoot past an ally) | ok (tests: a bot fighting rats around the player never hurts them) | ok | ok | ok | ok (tests: a bot shooting past the player never hurts them) | ok (tests: a bot shooting past the player never hurts them) | ok | ok |
| Look and sound of their shots | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| **Stability** | | | | | | | | | | |
| Mod reload with it wielded | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| Level change while firing | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| Dying with it | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| Revive with it | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| Knockdown | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| Ledge hang | ok (the gun is hidden in third person while hanging, as the game hides its own) | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| Switching away mid-animation | ok | ok (tests: put away while it fires, the rounds stop) | ok (tests: putting it away while it charges doesn't punch) | ok | ok | ok | ok | ok | ok | ok |
| Switching back mid-animation | ok | ok | ok (tests: taken out again, it charges and punches) | ok | ok | ok | ok | ok | ok | ok |
| Errors in the console log | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
| Crash dumps | ok | ok | ok | ok | ok | ok | ok | ok | ok | ok |
