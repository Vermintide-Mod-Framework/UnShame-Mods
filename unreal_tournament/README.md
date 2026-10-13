# Unreal Tournament Weapons & Movement

A Vermintide 2 mod (Vermintide Mod Framework) that brings Unreal Tournament 2004 to the game: weapons, movement, an announcer and gameplay
options. This is the guide for working on it.

What the mod contains at the moment is in the code. `TODO.md` is what is not done.

## Where things are

- `scripts/mods/unreal_tournament/` is the code. `unreal_tournament.lua` is the entry: it holds the lists of callbacks that the framework calls
  and loads the other files, in the order that matters. The settings are in `unreal_tournament_data.lua` and their texts in
  `unreal_tournament_localization.lua`.
- Code that more than one weapon needs is in the files at the top of that folder: the shared hooks and tables of callbacks (`hooks.lua`), the item
  registration (`items.lua`), helpers (`utils.lua`), the first person and third person models (`weapon_skin*.lua`, `menu_preview.lua`) and UT's
  effects (`skin_particles.lua`, `effects.lua`).
- Each weapon has a folder of its own: the gameplay, the look (`skin.lua`) and the animations of its model.
- `units/ut`, `ui/ut`, `wwise` and `texture_categories` are the assets, made by `tools/asset_conversion`. `resource_packages` says what is loaded.
- `tools/` has the tools for converting UT2004's assets (`asset_conversion`) and for reading the game's own files (`game_data`).

## How it fits together

- **Enabling.** The framework calls `mod.on_enabled`, `on_disabled`, `on_setting_changed`, `on_update`, `on_unload` and others. Each runs a list
  of callbacks that the files add their functions to (`unreal_tournament.lua` has the lists).
- **Templates are made again on every load.** `items.register` copies a base item and its weapon template, so a load never finds a patched
  template. A weapon's code changes the copy's actions. A weapon that can be switched off puts them back.
- **One hook per function.** The framework lets a mod hook a function once. Hooks that weapons share are in `hooks.lua`, which keeps tables of
  callbacks by name that a weapon adds an entry to (each table is documented where it is defined).
- **Projectiles** are the game's, as sub actions whose names are registered in the network lookups (`utils.register_network_lookup`). The
  weapon's callbacks tell the projectile's extension what is special about it. A weapon's skin draws what UT has at the game's unit, which is hidden.
- **Skins.** `weapon_skin.new(...)` makes the first person model: the game's own unit is hidden, the mod's model is shown and posed every frame
  from the Lua animation tables. Its third person holds the mesh in the hand of every character that wields the weapon, and in the hero and item
  screens.
- **Effects** are sprites, beams and meshes drawn by `skin_particles.lua`, because UT's emitters cannot be exported. The game's own effects are
  only played if they are loaded (`effects.is_available`).
- **A career that equips an item it is not locked to crashes the game**, so an item of its own is locked to the careers of the weapon it is a
  copy of (`can_wield`).
- **Units that are alive when the mod's package is unloaded crash the game**, so everything the mod spawns is destroyed on level exit and on
  unload.

## Working on it

- **Build** from the `mods` folder: `../vmb.exe build unreal_tournament -f . --rc ../vmb-rc`. The output has the compile errors: read it. A build
  with a Lua error still writes files, and a broken commit is easy to push.
- **Build number.** `unreal_tournament.lua` echoes `Unreal Tournament loaded (build N)` when the mod loads. N is the number of commits plus one,
  so a commit carries its own number, and a screenshot says which build it is.
- **Test in game.** The mod can be reloaded in game without a restart. The game's logs are in `%APPDATA%\Fatshark\Vermintide 2\console_logs` and
  its crash dumps in `crash_dumps`.
- **Chat commands** for development are defined with `mod:command` in the code: changing a skin's numbers while playing, the speed of the game,
  and others.
- **Placing a model** (idle, inspect, third person) can be checked without the game: `tools/asset_conversion/preview_weapon.py`.
- **Commit** each change, with the build number, and push.

## Adding a weapon

1. Convert its assets (`tools/asset_conversion/README.md`): the first person model, the pickup (the third person), the effects, the sounds, the icon.
2. The weapon's gameplay file registers the item (`items.register`), builds its template, its damage profiles and explosion templates
   (`utils.register_damage_profile`, `utils.register_explosion_template`), and is enabled with the mod or with a setting
   (`utils.register_weapon`).
3. Its `skin.lua` calls `mod.weapon_skin.new` with the model's placement from UT's class (`PlayerViewOffset`, `PlayerViewPivot`, `DisplayFOV`), the
   animations, the third person, and the effects.
4. Add its files to the package and to the list of files loaded in `unreal_tournament.lua`.

## Where things were learned

The game's source (`Vermintide-2-Source-Code`) is the reference for what the game does, and UT2004's source (`Deaod/UT2004` on GitHub) for what UT
does. The framework's documentation is at vmf-docs.verminti.de. What was found out about the formats is in the READMEs of `tools/`.
