# Red Moon Inn: plan

The inn replaces the keep. What the keep has comes from the Modding Tools Content's source of the keep,
`levels/inn/world.level`: its units, their script data, and the flow they need.

## 1. The inn in place of the keep

- The keep is `LevelSettings.inn_level`, whose `level_name` is `levels/inn/world`. The mod points it and its `packages` at the
  inn. The game's checks for the keep use the key `inn_level`, so they keep working.
- During events the game loads another key instead: `inn_level_celebrate`, `inn_level_halloween`, `inn_level_skulls`,
  `inn_level_sonnstill`. These get the same override.
- Coming back from the Chaos Wastes and Versus hubs loads `hub_level` of the event, or `inn_level`, so it comes back to the inn.
- Turning the mod on or off in the keep loads the level again. Only the host can do that.
- Everyone in the lobby needs the mod: players match the level's units by their index in the level, so a player without it
  would be in another level. Players joining without the mod, and a client turning it off, have to be handled.
- The level's name, image and loading screen are fields of the same settings.

## 2. Hero rooms

Custom code. Vermintide 2 still has Vermintide 1's `RoomHandler`, `RoomManagerServer` and `RoomManagerClient`, unused.

- The four room anchors, as units with `room_id` script data.
- Which hero is in which room, sent to the other players with VMF's network messages.
- A room changes when its player changes hero in the keep.
- Players spawn in their room.
- Each room's shell (Vermintide 1's unit `cdbe953451525322`) isn't in Vermintide 2, so the rooms have no walls yet.

## 3. Keep interactables

Each one that opens a menu moves the camera to a preset: the keep has a `menu_interaction_camera` unit for each.

1. The map: an interaction where Vermintide 1's map is, keeping its map prop.
2. Inventory: the armory box opens equipment.
3. Ammo and potions, no bombs: the keep's `pickup_spawner` units.
4. The forge: Vermintide 2's forge is separate units (`forge_anvil_01_tier_03`, the fireplace, vice, coal box and bucket),
   so only the anvil can be placed. Which unit has the forge's interaction is still to be found.
5. - The Emporium of Wonders: `interactable_store_trigger` (`store_access`).
   - Okri's challenges: `achievment_interactable` (`achievement_access`).
   - Rewards: `interactive_loot_piedestal` (`loot_access`).
   - The handbook: `interactive_tutorial` (`handbook_access`).
   - Hero selection: `gameplay_prestige_skull_01` and an `interactable_generic_02` beside it (`characters_access`).
6. The Bridge of Shadows: outside the front door, so that the dome covers the space between the inner and outer door and the
   pylon isn't seen.
7. Lohner: his interactions, keeping Vermintide 1's model and animations. The keep uses the same unit, `chr_inkeeper`.
8. Olesya: her tally where the bounty board was, the weave select book on the table beside it, the athanor
   (`keep_vom_magic_forge`) where the shrine was. The weave portal is placed as the Bridge of Shadows is.
9. The dwarf lodestone: `lodestone_difficulty_interactable` (`difficulty_selection_access`). Where it goes is still to be
   decided.
10. Talents: the keep's table in the courtyard (`talents_interactable`, `talents_access`, which opens the talents in the hero
    menu) in place of the inn's table on the far side.

Left out: the training dummies, which the menu opens.

To decide: the cosmetics (`interactive_cosmetic`, `cosmetics_access`).

## 4. Chaos Wastes and Versus in the cellar

Each is an interaction that starts a vote and loads its hub:

- Chaos Wastes: the keep's `keep_gamemode_door_02`, with `deus_door_transition`.
- Versus: the keep's `gameplay_empire_lever_01`, with `carousel_door_transition`.

A ladder goes up to the door that can't be reached.

## 5. Cosmetics

1. Completion banners: Vermintide 2's banners (`difficulty_banner_vt2_tier_*`, `difficulty_banner_vt1_remaster_tier_*`)
   where Vermintide 1's were.
2. Trophy displays on the walls, where the pieces Vermintide 2 doesn't have were (see `missing.txt`).
3. Paintings: a few of the main hall's in the hero rooms. The keep's paintings are slots of `KeepDecorationSystem`, and what a
   player hangs is saved for each slot, so how slots are named has to be checked.

## Also needed

- Spawn points: the keep has 16 `coop_spawnpoint` units, the inn 4. They are used when coming back from a mission and when
  changing hero.
- The names of places on the HUD (`location_keep_*`), which come from volumes.
- The keep's flow: its `networked_boolean` units and its music events.
- Sound: ambience, music and reverb. Vermintide 1's inn music isn't in Vermintide 2.
- Vermintide 1's flow that wasn't converted: 9 triggers and 8 stories.
- Building the mod: the level only compiles in ToolCenter for now. vmb's build fails on what only the Content has
  (`global.script_flow_nodes`, the `cubemap_probes` texture category).

## Order

1. The inn in place of the keep, with everyone needing the mod.
2. The keep's interactables.
3. The level's name, image and loading screen.
4. Cosmetics.
5. Chaos Wastes and Versus.
6. Hero rooms.
