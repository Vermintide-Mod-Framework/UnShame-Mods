# Weapon Skins: the UT2004 Shock Rifle

Status: waiting for sign-off. Branch `ut-weapon-skins`, local only, never pushed.

## 1. What it is

A setting, **Weapon Skins**, under **Weapons** (a sub widget of `ut_weapons`, off by default). With it on, the Shock Rifle
looks and sounds like UT2004's. The gameplay stays what `shock_rifle.lua` does today (it replaces the Beam Staff's actions
in place): this is a cosmetic layer over it. Only the Shock Rifle. The other four weapons come after, with what is learned.

What is covered:

| Part | UT2004 source of it |
|---|---|
| First person model, placed where UT draws it | `NewWeapons2004.ShockRifle` mesh, `ShockRifle.uc` (view offset, pivot, DrawScale) |
| Its animations: Pickup, Idle, Fire, AltFire, PutDown | `NewWeapons2004.ShockRifle` animation set (done: `asset_test_animations.lua`) |
| The chamber: flowing gel, glow that comes back after a shot | `ShockPowerShader` chain, `ShockRifle.RenderOverlays` (done as a test) |
| Muzzle flashes, first and third person | `ShockBeamMuzFlash`, `ShockProjMuzFlash`, `*3rd`, `ShockMuzFlash*` |
| The beam: coil, impact flare, ring, scorch, core | `ShockBeamEffect`, `ShockBeamCoil`, `ShockImpact*`, `ShockExplosionCore` |
| The shock ball, its explosion | `ShockBall`, `ShockProjSparkles`, `ShockProjElec`, `ShockExplosion*`, `ShockAltExplosion`, decals |
| The combo | `ShockCombo`, `ShockComboCore/ExpRing/Flare/Flash/Sparkles/SphereDark/Vortex/Wiggles`, `ShockComboFire` sound |
| Sounds | `WeaponSounds.ShockRifle.*` and `NewWeaponSounds` (fire, alt fire, combo, switch to, impacts, pickup) |
| Third person (the other players, and yours in a third person view) | the pickup mesh `NewWeaponPickups.ShockPickupSM` (DrawScale 0.55), per your note |

Not in scope: the other weapons, any gameplay change, the HUD and the crosshair of UT.

## 2. Ground rules

- The assets are Epic's. They stay on this branch, local. Nothing is pushed or uploaded from it; no version bumps.
- I can't run the game. Every step has a check I can do without it (compile, the engine calls checked against the game's
  own Lua in `Vermintide-2-Source-Code`, offline renders, chat output you can read back), and a short list of what to look
  at in game, with the screenshots I would want.
- No guessing at numbers: where UT's source or data has them, they are taken from there (as the placement and the idle
  pose were). Tuning numbers go in `CONFIG`, as in the other files.
- Everything I touch in the game goes through the mod's own shared hook tables (`hooks.lua`): a function is hooked once.

## 3. Design

**Setting.** `weapon_skins` checkbox, in `unreal_tournament_data.lua`, localized like the others, read with
`mod:get("weapon_skins")` through `utils.is_weapon_enabled`-style helper. Changing it live creates or removes the skin
(`mod.setting_changed_callbacks`).

**Assets** are in a package of their own, loaded with `utils.package_holder` only while the setting is on and the Shock
Rifle is enabled, so nothing is loaded when off. (Decision D1 below: where that package lives.)

**One file**, `shock_rifle_skin.lua`, owns the skin; `shock_rifle.lua` stays the gameplay and only tells it what happens,
through callback tables added to `hooks.lua` (`mod.unwield_callbacks` is the one that doesn't exist yet) and a small
`mod.shock_skin_events` table for what only the Shock Rifle knows (a beam shot, a ball launch, a combo).

**First person.**
- The unit is spawned in the level world and linked to the root node of the player's first person unit, as the game's
  own weapons are. Placement is what `asset_test.lua` does now (UT's projection fitted to a screenshot of UT2004).
- The game's weapon and arms are hidden with `fp:hide_weapons(reason)` and the arms attachment's visibility, as the Halo
  mashup does it; restored on unwield, death, level exit, setting off. The skin is shown when the game would show its
  weapon: wielded, first person mode, no other hide reason (inspecting, cutscenes, disabled by a monster, knocked down,
  hanging off a ledge, and the interactions that take the arms).
- The animation player is `asset_test.lua`'s (frames interpolated, back to Idle), plus a short cross fade when one
  sequence follows another, since UT blends them.

**Events to animations** (the left column is where it is found in `shock_rifle.lua` / the game):

| Event | Where | Skin does |
|---|---|---|
| Wield | `mod.wield_callbacks` | Pickup, select sound, then Idle |
| Unwield | new `mod.unwield_callbacks` (hook before `SimpleInventoryExtension._wield_slot`) | PutDown, short, while the next weapon comes up; or cut (D4) |
| Beam shot | `build_beam_action` (`attack_shoot_beam_spark`, `fire_sound_event`) | Fire, muzzle flash, fire sound, glow to zero |
| Ball launch | `build_ball_action` (`attack_shoot_fireball`) | AltFire, muzzle flash, alt fire sound, glow to zero |
| The glow back | `beam_fire_rate` / `ball_fire_rate` (0.7 / 0.6) | opacity of the chamber with the time to the next shot, as `RenderOverlays` |
| Combo | `detonate_ball`, the combo effect functions | UT's combo effect, combo sound |
| Beam hit, ball explosion | `spawn_trail`, the ball's `do_aoe` callback | impact flare, ring, scorch, core; explosion effects, decals |
| Vent / overheat / explosion | the weapon's vent action, `mod.overheat_callbacks` | no UT equivalent: the glow flickers and goes dark while venting, the existing effects stay |
| Hang off a ledge, stagger, push, sprint | `mod.ledge_hang_callbacks`, the game's states | hidden or held as the game does it; the push gets a short bump of the gun |

**Effects** can't be game particle systems (no particle editor in the SDK). They are made as the Halo mashup makes its
own: units with a quad, a transparent material and a flipbook, moved and faded from Lua, plus the coil as a mesh. This
needs an additive material (D6 spike) and converts the UT textures and the static meshes of XEffects. The beam, impact,
ball and combo each get a small module with UT's numbers (lifetimes, sizes, colors, velocities) read from the `.uc`
files; the game's own effects stay for when the setting is off.

**Third person.** The pickup static mesh is linked to the character's right-hand weapon node in place of the staff's third
person unit (`show_third_person_inventory(false)` for the staff, as `SimpleInventoryExtension` does it), at an orientation
and offset tuned with a harness like `/shock`, and the 3p muzzle flash on the node of its tip. What each player sees is by
their own setting: a player with it off sees the staff. Which weapon a character holds is known from the item template
the game already replicates, so no new message for that; the shots need the existing `ut_shock_trail` message to
carry the flash.

**Sounds.** UT2004's, converted from its `.uax`. Spike in D2: the game plays Wwise events from banks, and the SDK
compiles `wwise_bank`, `wwise_stream` and `wwise_dep` resources, but nothing in it makes a bank from a wav. The route to
try first is a bank built by hand from the structure of one of the game's own banks (an event, a play action, a sound
object, the media); the one that doesn't need that is Audiokinetic's authoring tool, which needs an account and a
license acceptance only you can give.

## 4. Phases

Each ends with a build, a local commit, and a short report with what to look at.

**0. Foundation.** The setting and its strings; the skin file with lifecycle (create, destroy, setting changes, level exit,
death, destroyed first person unit); the split of the assets into their own package, loaded by the setting; the new
hook tables. The `asset_test.lua` harness becomes a development-only command of the skin. Every engine call the skin uses is
checked against the game's Lua first (`Unit.set_material`, `Mesh.material`, `Material.set_scalar`, `World.link_unit`,
`Quaternion.lerp`, `Application.resolution` and the others are all used by the game itself; the list gets written out).
*Done when:* option off, the game is as before; on, the gun appears when the Shock Rifle is wielded and goes when it isn't.

**1. First person, complete.** Visibility rules; Pickup, Idle, Fire, AltFire (PutDown by D4) tied to the real events; the
chamber glow tied to the real fire rates; the vent. Bob and sway of UT (`Pawn.CalcDrawOffset`, `WeaponBob`) if the
placement holds; the sprint and push. *Check in game:* wield, fire both modes, vent, switch weapons, sprint, die, change
level, toggle the setting while wielding, a second wield after all of those.

**2. Effects.** The additive material, the billboard layer, the muzzle flashes, the beam, the impacts, the ball and its
explosion, the combo. First the effects of the shooter's own machine, then the same on the others' (they already get the
trail and the combo from the existing messages). *Check:* a screenshot of each next to UT2004's.

**3. Sounds.** The spike of D2, then the conversion of the sounds, then their events tied to the same events as above
(the game's own sound for the shot is turned off by the setting, not layered).

**4. Third person.** The pickup mesh on the hand, its tuning, the 3p flash and beam; own third person view and another
player (a bot can hold the weapon as well: they wield the staff through the same function). *Check:* screenshots from the
side, and the weapon swapping between the staff and the skin as a character wields.

**5. Polish and the rest of the events.** Stagger, knockdown, grabbed, ledge, interactions, the inspect view, the equipment
menus (the item's preview in the keep stays the staff's: noted), the performance of the flipbook, the memory of the package,
the dev command, notes in the file headers like the other weapons have. Remove what is only for the tests.

## 5. Risks

- **Sounds** (D2): may not be possible without the authoring tool. Then the setting keeps the game's sounds for the shots
  and I say so.
- **Additive effects** need a material I haven't made: the SDK has one graph with a blend that I'd copy. If it can't be
  done, effects get alpha blended and look flatter.
- **Hiding the arms** has the game showing them again at times (I re-hide every frame, which works for the test), and the
  interactions that use them look wrong with them hidden.
- **Remote players with a different setting or without the mod** see the staff; an unmatched skin is never shown.
- **The skin is never tested by me in game.** What I can't check, I make visible: a chat line for every state change in a
  development mode.

## 6. Decisions I need from you

- **D1. Where the assets live.** Recommended: a second, local-only mod, `unreal_tournament_skins`, that holds the Epic
  assets, never uploaded; the main mod's Weapon Skins setting only works when it is installed. The alternative is the
  assets in the main mod's bundle, as on this branch now: simpler, and a `vmb upload` would publish them.
- **D2. Sounds.** OK to time-box the hand-built bank (a short spike, kept only if it plays in game), and to stop and ask you
  about the authoring tool only if it doesn't?
- **D3. Third person** from the pickup mesh, tuned by screenshots: OK?
- **D4. PutDown** on switching: a short one that overlaps the next weapon coming up, or none?
- **D5. Default** of Weapon Skins: off.
- **D6. Effects** made in Lua with my own units, not particles: OK?
