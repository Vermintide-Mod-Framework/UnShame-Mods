local mod = get_mod("red_moon_inn")

-- The inn takes the keep's place. The keep's level settings, and those of the keeps the game loads during events,
-- load the inn's level instead. The game's checks for the keep use the settings' keys, so they keep working.
-- The keep's packages stay as they are: the game unloads a level's packages by the list in its settings, so changing
-- the list while the level is loaded would unload packages that were never loaded.

local INN_LEVEL = "levels/red_moon_inn/red_moon_inn/world"

-- The keep, and the keeps with the decorations of events
local KEEP_KEYS = {
	"inn_level",
	"inn_level_celebrate",
	"inn_level_halloween",
	"inn_level_skulls",
	"inn_level_sonnstill",
}

-- The keeps' own levels, kept when the mod is reloaded, when the settings may already have the inn
local keep_levels = mod:persistent_table("keep_levels")

for _, key in ipairs(KEEP_KEYS) do
	local settings = LevelSettings[key]

	if settings and not keep_levels[key] then
		keep_levels[key] = settings.level_name
	end
end

local function use_inn(enabled)
	for key, keep_level in pairs(keep_levels) do
		LevelSettings[key].level_name = enabled and INN_LEVEL or keep_level
	end
end

-- Loads the level again when the mod is turned on or off in the keep. Only the host can.
local function reload_keep()
	local level_key = Managers.level_transition_handler and Managers.level_transition_handler:get_current_level_key()

	if keep_levels[level_key] and Managers.player.is_server and Managers.state.game_mode then
		Managers.state.game_mode:retry_level()
	end
end

mod.on_enabled = function (initial_call)
	use_inn(true)

	if not initial_call then
		reload_keep()
	end
end

mod.on_disabled = function (initial_call)
	use_inn(false)

	if not initial_call then
		reload_keep()
	end
end
