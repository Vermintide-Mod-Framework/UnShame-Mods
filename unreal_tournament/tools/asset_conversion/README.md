# Converting UT2004 assets for this mod

Local tools that produced `units/ut/*`, `ui/ut/*`, `wwise/unreal_tournament/*`, `texture_categories/ut.texture_category` and the
`skin_animations*.lua` files of the weapons. They are run by hand, not by the build.

## Setup

- **UModel** (UE Viewer, gildor.org) exports the game's files. `export.py` runs it for every package the scripts read, into one folder:

      export.py <UT2004 dir> <export dir> [<path of umodel_64.exe>]

  Each package is in a folder of its own name there (`<export dir>/<package>/<class>/<object>`), and every script that reads the game's
  files takes that folder as its argument. A script that needs another package has it added to `PACKAGES` in `export.py`. The classes'
  default properties (view offsets, fire rates, spreads) are not in UModel's exports: they are read from the source of UT2004
  (cloned from https://github.com/Deaod/UT2004, `<package>/<Class>.uc`).
- **Python 3.** The scripts need no packages. (The tools in `../game_data` are for reading the game's own files, and have a few.)

## The tools

| Script | Makes | From |
|---|---|---|
What each script makes, and the tables in it that say what it converts, are in its header. Most take the export folder as their argument.

**The export**

| Script | Makes |
|---|---|
| `export.py <UT2004 dir> <export dir> [umodel]` | the export folder, from the packages in `PACKAGES` |

**Weapons**

| Script | Makes |
|---|---|
| `convert_weapon.py <weapon> <export dir>` | a first person model: its unit, materials and textures, and its animations as Lua. The weapons are in `WEAPONS` |
| `convert_static.py <name> <export dir>` | a static mesh as a unit: the pickups, the third person meshes and the projectiles. The meshes are in `STATICS` |
| `make_anim_assets.py <export dir>` | the animations of the UT2004 Shock Rifle, which came before `convert_weapon.py` |
| `make_chamber_material.py <export dir>` | the Shock Rifle's chamber, as a shader graph |
| `make_sniper_screen.py <export dir>` | the Lightning Gun's screen texture, written into the export folder for `convert_weapon.py` |
| `make_bank.py <weapon> <export dir>` | a sound bank in `wwise/unreal_tournament`. The banks are in `WEAPONS` |
| `render_icon.py in.bsi out.png size yaw pitch roll textures [fill [mirror]]` | an inventory icon from a converted pickup (see Icons) |

**Effects**

| Script | Makes |
|---|---|
| `make_fx_assets.py <export dir>` | effect textures as UT has them, each with its `fx_` material, the quad the particles are drawn on, and the material they all derive from |
| `make_weapon_fx.py <export dir>` | effect textures of the later weapons, with sheets of tiles cut into a texture for each tile |
| `make_lightning_assets.py <export dir>` | the Lightning Gun's effect textures, and its scope as gui materials |
| `make_sniper_scope.py <export dir>` | the Sniper Rifle's scope, as a gui material |
| `make_flak_flash.py <export dir> [name]` | the texture of a first person muzzle flash drawn on `flak_flash_mesh` |
| `split_flak_trail.py <export dir>`, `split_smoke.py <export dir>`, `split_explosion.py <export dir>`, `split_spark.py` | textures cut from UT's sheets, or generated where UT's look wrong here |
| `make_fx_meshes.py <export dir>` | the meshes of the effects, and the light |
| `make_goop_mesh.py <export dir>` | the Bio Rifle's glob: a unit for each frame of its animations |
| `make_decal_unit.py` | the box that the Bio Rifle's splat is projected from |
| `make_combo_materials.py` | the effects' shader graphs, for what UT pans or combines: the combo, the dark sphere, the goop, the shield |

**Checks and pieces**

| Script | Makes |
|---|---|
| `preview_weapon.py <weapon> <export dir> out.png [inspect numbers]` | a picture of a first person weapon, placed the way `weapon_skin.lua` does (see Checks) |
| `psk2bsi.py in.psk out.bsi prefix materials [scale]` | a psk or pskx as a `.bsi` mesh. `convert_static.py` runs it |
| `tga2png.py in.tga out.png [tint]` | a tga as a png, with an optional tint |
| `formats.py`, `quat.py`, `resources.py` | nothing: what the scripts share (TGA, PNG, psk and psa; quaternions; the text of `.texture` files and effect materials) |

### Order

- `make_fx_assets.py` writes UT's textures as they are, and the `split_*.py` scripts replace some of them. Run the splits again after it.
- `make_sniper_screen.py` before `convert_weapon.py sniper`, which reads the screen it writes.
- `make_combo_materials.py` after `convert_weapon.py bio`: it replaces the material of the goop in the Bio Rifle's tank with a shader graph.

### Weapons

1. **Export** with `export.py`, after adding the weapon's packages to its `PACKAGES` if they are not there.
2. `convert_weapon.py <weapon> <dir>` writes the unit and `skin_animations.lua`, and `convert_static.py <name> <dir>` the pickup and the
   projectiles. The UT2004 Shock Rifle came first, from `NewWeapons2004` (`ShockRifle`, its psk and psa, with `psk2bsi.py`, `tga2png.py` and
   `make_anim_assets.py`), and has its own units in `units/ut/shock`.
3. The effects, the sounds and the icon of the weapon: the scripts above.
4. The weapon's skin is `scripts/mods/unreal_tournament/<weapon>/skin.lua`, which places the model, plays the animations, and draws the effects.

The UT2003 Shock Rifle (the weapon's second skin: UT2004 keeps it as `ShockRifle.bUseOldWeaponMesh`) is `Weapons.ShockRifle_1st`, with
the animations in the same package, `WeaponStaticMesh.ShockRiflePickup` as its pickup (the third person) and `WeaponSkins.ShockTex0` as its
texture. Its mesh's third material is the red laser sight (UT draws it additively with a panning texture), made as a see through red. Where it is
drawn is `ShockRifle.uc`'s `OldPlayerViewOffset` and `OldPlayerViewPivot`.

### Icons

`render_icon.py in.bsi out.png size yaw pitch roll body.png[,power.png] [fill [mirror]]` renders a converted mesh (a pickup's bsi, with the textures
of its geometries in order) into an icon with a transparent background. `fill` is how much of the picture the mesh takes up (0.92 if it is
not given: the item's frame covers the edges of an icon, the Flak Cannon's is 0.72). The icons are made with the pickup of each weapon, for
instance `pickup.bsi out.png 256 -70 0 35 <texture>` for the Flak Cannon and the UT2003 Shock Rifle, and `20 0 35` for the UT2004 Shock
Rifle. The Bio Rifle's is rendered from the side with its orange band, pointing up and to the left, and mirrored (`256 -70 0 -35 <textures> 0.74 mirror`)
so that it points up and to the right as the others do. Each icon's `.texture` and `.material` (a gui material that `items.lua` registers in the UI's renderers) are next to it in `ui/ut`, in a
package of their own (`resource_packages/unreal_tournament/icons`) that is listed in `unreal_tournament.mod` (the game only loads the
packages that are) and that the mod keeps a handle to, so that it stays loaded when the mod is reloaded: the renderers hold the material
locked, and the game fails when it is unloaded.

### Checks

- `preview_weapon.py` draws a weapon the way the game places it, with the idle pose of its animations, the view offset and pivot of UT's class,
  and (with the numbers) an inspect pose: `right forward up roll pitch yaw` and where it turns about, `inspect_pose_*` and `inspect_pivot_*`
  of the skin. It agrees with the game to within a few pixels. Only the root bone is posed (the rest of the model is in its reference pose),
  and the lighting is a simple shading. The weapons it knows are in its `WEAPONS`.

## What was found

- UModel's psk is right handed (x forward, y left, z up): the model's (right, forward, up) is (-y, x, z). The psk's
  front faces are clockwise, the SDK's counter-clockwise: the triangle order is (w0, w2, w1). The bsi's V is up.
- The mesh is single sided, only the side the player sees (the left one) has faces. Seen from other sides (the back of the Flak Cannon, its
  muzzle) the model has holes.
- UT never draws the mesh in its reference pose: the root bone of the animation moves all of it. Rotation convention of
  the psa: the rotation of the mesh is `q_animation * conj(q_reference)`, unconjugated (Pickup comes up from below,
  PutDown goes down, Fire kicks back).
- UT draws the weapon at `DrawScale` 0.7, `PlayerViewOffset * 90 / DisplayFOV`, `PlayerViewPivot`, with a horizontal
  field of view of about 86.5 (fitted against pixels of a screenshot of UT2004 with small weapons off, from the position of four features of the Shock Rifle's mesh: the
  radar, the two buttons and the label). `weapon_skin.lua` places the models with it.
- The standard SDK material needs `use_color_map = 1` for its color map to be used, and the key of the texture is
  `color_map`.
- The first person materials are the SDK's standard material with the custom field of view of the weapons on
  (`units/ut/weapon_standard.material` and `weapon_standard_transparent.material`: the field of view is also what keeps the outlines of other
  players from being drawn over a weapon), and in decal group 3, so that the decals of the ground are not drawn on the weapons. The
  chamber and the effects are unlit transparent materials, which the decals do not touch.
- UT's weapons are rigid per bone: the converted model is one geometry for each material of each bone, with a node for each bone, and the
  animations are the pose of each bone for each frame, which `weapon_skin.lua` sets every frame.
- UT's particle emitters cannot be exported. The effects are rebuilt from their textures and meshes, and drawn by `skin_particles.lua`.
- The sound banks are written by hand from the objects of a bank that works (the sounds are PCM, with no parent and the output bus that the
  game's sounds use, an event is played by an action). The version number in their header is the one that Fatshark's `.wwise_bank` files have.
  The documented way is to make them in Wwise 2018.1 and run two tools on the result (see the VMF documentation, "sound").
