# Checklist for a weapon

Everything a weapon needs, from what the Shock Rifle, the Flak Cannon and the Rocket Launcher needed. Go through it for each new or converted
weapon. `TODO.md` says which weapons are left; this says what each one needs.

## 1. Read UT2004 first

- Read the weapon's classes (`gh api repos/Deaod/UT2004/contents/<package>/<Class>.uc`, or the local copy): the weapon, each fire mode, the
  projectile, the pickup, the ammo, the damage types, the explosion and effect classes.
- Write down: fire rates, ammo per fire, hold and load times, spread (style and amount), projectile speed, gravity, lifetime, damage,
  splash radius and full-damage radius, momentum, self damage, which modes lock out each other, what happens with no ammo, what the bots do.
- Check the sounds, textures, meshes and animations each class uses.

## 2. The item

- [ ] `items.register`: a copy of the base item and template; the base weapon is left as the game has it.
- [ ] Name ("UT2004 <name>"), type name (UT's own name), UT's flavor text cut to the length of the others.
- [ ] Careers: the base weapon's (`can_wield`). A career that equips an item it is not locked to crashes the game.
- [ ] Deus and other copies of the base item (`deus_copy`) if the base has them.
- [ ] Keywords, checked against how it plays.
- [ ] Stat chart (`weapon_diagram`) and the information graphic.
- [ ] Icon (`render_icon.py`, the pickup, fill 0.72), its material and package.
- [ ] No setting and no checkbox: enabled and disabled with the mod. Localization strings only for what is shown.
- [ ] What the item patches in the game's template is saved and put back (on disable, on unload).
- [ ] Old cached item tables do not break the UI after a reload (the tab screen keeps loadouts: `retire_icon`).

## 3. Gameplay

- [ ] Fire modes with UT's rates; the next shot and the other mode wait for the fire rate (chain `start_time` and `total_time` of every action
      that can follow, for both modes). Check what UT locks out: a press while the other mode is waiting is dropped.
- [ ] Holding, loading, releasing, auto-fire (hold time), what a release does, what a second button does meanwhile.
- [ ] Ammo: maximum, what a pickup gives, all of it the clip (no reload), `ammo_immediately_available`, the game's reload when the weapon is
      wielded made harmless, `/loaded`, what happens at 0.
- [ ] Damage profile: power level, armor modifiers (compare the game's armor-piercing weapons), cleave, stagger, headshots, shields, critical
      strikes. Check the ratio between the weapons' damage against UT's.
- [ ] Anything not from the pellets or the weapon in question is not scaled as theirs is.
- [ ] Projectile: start position and rotation (UT's offsets, the camera static at the moment of the shot, no random roll from the game's
      spread), speed, gravity, lifetime, radius, what it hits, whether other projectiles set it off.
- [ ] Explosions: radius, full-damage radius, falloff, self damage, momentum and jumping, ragdoll throw as UT's `xPawn`, what it sets off.
- [ ] Special rules: lock-on, homing, bouncing, linking, goo, combos. Each as UT does it.
- [ ] Buffs and the game's systems it touches (overcharge, ammo buffs, criticals, careers' abilities) behave.
- [ ] Bots: `attack_meta_data`, their shooting (ranges, ally clearance, when they hold or fire), `<weapon>/bots.lua`.
- [ ] Multiplayer: the host's path and the client's path both work; each peer sees the projectiles, the explosion and the effects; what the
      game does not send (a shot's start, a state) is made to be.
- [ ] Death, a knockdown, switching weapons, a level change and a mod reload in the middle of any of it leave nothing behind.

## 4. First person

- [ ] Model, materials, textures and animations converted (`convert_weapon.py`), checked with `preview_weapon.py` before the placement is set.
- [ ] Placement as UT draws it (offset, scale, field of view), the game's arms and unit hidden.
- [ ] Animations: Select, Idle (not too fast), Fire, AltFire, load, PutDown; the rates match the fire rates and the load times.
- [ ] The animations' ammo cases: nothing loaded at 0 ammo, nothing loaded after the last shot, loading when ammo comes back, the last
      round being the one in the barrel, loads cut short by a shot or by aiming.
- [ ] Parts that move by code: barrels, pistons, stretched parts, hidden parts (`node_scales`, `on_pose`).
- [ ] Inspect pose: the whole gun not exposed, no sliding at the start, the sway.
- [ ] The game's animation events that carry the base weapon's flash, sounds or particles are filtered (`first_person_animation_filters`),
      and its flow events (`init_flow_event_filters`).
- [ ] HUD: the crosshair, the ammo number, the pips, with UT's colors.
- [ ] Weapon bob and the rest of how UT moves the weapon.

## 5. Effects

- [ ] Muzzle flash, trail, flare, smoke, glow, beams, explosion: as UT's (read the emitters; the textures and meshes are exported, the emitters
      cannot be).
- [ ] The game's own effect of the base weapon is not played (the projectile's, the hit's, the explosion's) unless it is added on purpose.
- [ ] Brightness, size, transparency, draw distance, lifetime compared with screenshots of UT.
- [ ] Effects are only played if they are loaded (`effects.is_available`); the units are cleared on level exit and on unload.
- [ ] Impacts, decals, the sounds of surfaces.

## 6. Third person

- [ ] The mesh in the hand: grip, scale, yaw, pitch, roll, following the game's unit (`follow_game_unit`) or not.
- [ ] The base weapon's model hidden, for every character that holds it: the player, other players, bots.
- [ ] The muzzle position (flashes and shots from the hand's model).
- [ ] The materials are the world ones (`world_standard`, jitter transparency: the weapon fades when the camera is close, with the outline
      that the characters have).
- [ ] The shot animation of other players is played, with the base weapon's sounds muted (`sound_event_filters`) and the reload and other
      events that do not fit filtered (`third_person_animation_filters`).
- [ ] Other players' sounds: UT's own, 3D, from where they are, for the shot, the load, the explosion.
- [ ] The hero screen, the item screen and the previewers show the model (`menu_yaw`) in the same place as the world.
- [ ] What the game shows of the player's own character in third person view.

## 7. Sounds

- [ ] The bank (`make_bank.py`): fire, alt fire, select, load, lock, explosions, projectile loops; 2D for the player, 3D for the others, volumes
      and reach set; each event is in the bank and the metadata.
- [ ] The game's sounds of the base weapon taken over or muted: HUD events (`take_over_sound`), unit flow events, animation sounds, husk sounds,
      beam loops.
- [ ] Loops stop when they should (the weapon is put away, the player dies, the level ends).
- [ ] Sounds of loading and of pickups at the right moment of the animation.

## 8. Crash and stability

- [ ] No unit of the mod alive when its package is unloaded; the visuals are cleared with the level and with the mod.
- [ ] Projectile units are only spawned if loaded.
- [ ] Vectors given to the engine are not boxed (`utils.as_vector`).
- [ ] One `mod:hook` per game function: a shared hook in `hooks.lua` with a table of callbacks.
- [ ] Nothing is done to units that are dead or not yet made; every table of state is cleared.
- [ ] A mod reload with the weapon wielded, then Tab, the hero screen and the inventory.

## 9. Test

- [ ] Alone, as the host, as a client, with bots, with other players watching (third person, sounds, projectiles).
- [ ] Each mode, each combination of the modes, quickly in a row, at 0, 1, 2 and 3 rounds, with a pickup in the middle.
- [ ] Switching weapons and wielding again in the middle of each animation.
- [ ] Inspect, the hero screen, the item screen, the tab screen after a reload.
- [ ] Dying and being revived with it, a level change, a mod reload.
- [ ] A look at the game's console log and crash dumps afterwards.

## 10. Done

- [ ] The base weapon is as the game has it when the weapon is off.
- [ ] `TODO.md` updated, the README says how it works (not what it has), the localization is complete.
- [ ] Comments are short and plain, and each one was read cold.
- [ ] Build number bumped, built, the output read, committed and pushed.
