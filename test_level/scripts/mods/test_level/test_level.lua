local mod = get_mod("test_level")

-- Adds the mod's level to the game, and a chat command that starts it.
-- The game builds its tables of levels from LevelSettings when it boots, before mods load,
-- so the level is added to each of those tables here as well.

local LEVEL_KEY = "test_level"

-- The level's resources are in the mod's own package, which the mod manager loads with the mod,
-- so the level has no packages of its own for the level transition to load.
local LEVEL_SETTINGS = {
	display_name = "level_test_level",
	level_name = "levels/test_level/world",
	packages = {},
	level_particle_effects = {},
	level_screen_effects = {},
	knocked_down_setting = "knocked_down",
	player_aux_bus_name = "environment_reverb_outside",
	source_aux_bus_name = "environment_reverb_outside_source",
	environment_state = "exterior",
	ambient_sound_event = "silent_default_world_sound",
	locations = {},
	level_image = "level_image_any",
	loading_ui_package_name = "loading_screen_1",
	no_terror_events = true,
}

-- Adds a name to the end of a network lookup, which is a list with each name's index stored under the name too.
-- Every player has the mod, so every player gives the level the same index.
local function add_to_lookup(lookup, name)
	if rawget(lookup, name) then
		return
	end

	local index = #lookup + 1
	lookup[index] = name
	lookup[name] = index
end

-- The statistics the game keeps for each level (statistics_definitions.lua, for UnlockableLevels), as { group, name }.
local STATISTICS = {}

-- Adds the level's statistics. They have no database_name, so they are never sent to the backend, which doesn't know them.
-- The game reads their saved value when a level ends (LevelUnlockUtils.completed_level_difficulty_index), and only
-- statistics with a database_name get one, so they are given a saved value of 0 here.
local function add_statistics(level_key)
	local player = StatisticsDefinitions.player

	local function add(group, name)
		player[group][name] = { value = 0, persistent_value = 0, persistent_value_mirror = 0, name = name }
		STATISTICS[#STATISTICS + 1] = { group, name }
	end

	add("completed_levels", level_key)
	add("played_levels_quickplay", level_key)
	add("played_levels_weekly_event", level_key)
	add("collected_grimoires", level_key)
	add("collected_tomes", level_key)
	add("collected_dice", level_key)
	add("collected_painting_scraps", level_key)

	for _, hero in ipairs({ "bright_wizard", "wood_elf", "empire_soldier", "witch_hunter", "dwarf_ranger" }) do
		add("completed_levels_" .. hero, level_key)
	end

	local difficulty_name = level_key .. "_difficulty_completed"
	LevelDifficultyDBNames[level_key] = difficulty_name
	add("completed_levels_difficulty", difficulty_name)
end

-- Creates the level's statistics in a player's statistics. A statistic that doesn't exist yet is read from its
-- definition, which gives no saved value without a database_name, so they are created when the player is registered.
local function create_statistics(statistics_db, stats_id)
	for _, path in ipairs(STATISTICS) do
		statistics_db:_get_or_create_stat(stats_id, 0, path[1], path[2])
	end
end

LevelSettings[LEVEL_KEY] = LEVEL_SETTINGS
add_to_lookup(NetworkLookup.level_keys, LEVEL_KEY)
add_to_lookup(NetworkLookup.mission_ids, LEVEL_KEY)
add_statistics(LEVEL_KEY)

mod:hook_safe(StatisticsDatabase, "register", function (self, id, category)
	if category == "player" then
		create_statistics(self, id)
	end
end)

-- Players registered before the mod loaded
local statistics_db = Managers.player and Managers.player:statistics_db()
if statistics_db then
	for stats_id in pairs(statistics_db.statistics) do
		create_statistics(statistics_db, stats_id)
	end
end

mod:command("test_level", "- starts the test level", function ()
	Managers.mechanism:debug_load_level(LEVEL_KEY, 0)
end)
