local mod = get_mod("red_moon_inn")

-- The inn is a hub level of its own, a copy of the keep's settings with the inn's level. While the mod is on, the host
-- loads it wherever the game would load the keep, or one of the keeps it loads during events. The game checks for the
-- keep by its settings' hub_level, so those checks keep working.
--
-- Clients load the level the host tells them to. Every player needs the mod, which adds the inn's key to the game's
-- lookups; with the mod turned off, a client still has them. The lobby browser leaves out lobbies whose level it doesn't
-- know, so players without the mod don't see a host in the inn.

local INN_KEY = "red_moon_inn"
local INN_LEVEL = "levels/red_moon_inn/red_moon_inn/world"

-- The keep, and the keeps with the decorations of events
local KEEP_KEYS = {
	inn_level = true,
	inn_level_celebrate = true,
	inn_level_halloween = true,
	inn_level_skulls = true,
	inn_level_sonnstill = true,
}

-- The keep's occlusion data (tomes) hides parts of the inn. The keep's other packages are needed: its level package
-- also has the menus' preview levels, the keep's dialogue and the handbook.
local TOME_PACKAGES = "^resource_packages/levels/tomes/"

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

local function without_tomes(packages)
	local kept = {}

	for _, package in ipairs(packages) do
		if not package:find(TOME_PACKAGES) then
			kept[#kept + 1] = package
		end
	end

	return kept
end

local settings = table.clone(LevelSettings.inn_level)
settings.level_name = INN_LEVEL
settings.level_id = INN_KEY
settings.packages = without_tomes(LevelSettings.inn_level.packages)
LevelSettings[INN_KEY] = settings

add_to_lookup(NetworkLookup.level_keys, INN_KEY)
add_to_lookup(NetworkLookup.mission_ids, INN_KEY)

-- The dialogue system loads its files by the level's key: the inn has the keep's. Some lines are kept out of the keep
-- by a rule on the current level's key. The dialogue settings are only loaded with the dialogue system.
mod:hook("DialogueSystem", "init", function (func, self, ...)
	DialogueSettings.level_specific_load_files[INN_KEY] = DialogueSettings.level_specific_load_files.inn_level
	DialogueSettings.blocked_auto_load_files[INN_KEY] = true

	func(self, ...)

	if self._global_context.current_level == INN_KEY then
		self._global_context.current_level = "inn_level"
	end
end)

local function redirect(level_key)
	return KEEP_KEYS[level_key] and INN_KEY or level_key
end

-- Every level the host loads next is set here
mod:hook("LevelTransitionHandler", "apply_defaults_to_level_data", function (func, self, level_key, ...)
	return func(self, redirect(level_key), ...)
end)

-- The keep the game starts in, and the one it loads when no level is given
mod:hook("AdventureMechanism", "get_starting_level", function (func, ...)
	return redirect(func(...))
end)

-- Turning the mod on or off in the keep loads the other one. Only the host can. With no level given, the game loads
-- the keep it starts in, which the hook above makes the inn while the mod is on.
local function swap_keep()
	local handler = Managers.level_transition_handler
	local level_key = handler and handler:get_current_level_key()

	if (KEEP_KEYS[level_key] or level_key == INN_KEY) and Managers.player.is_server and Managers.state.game_mode then
		handler:set_next_level()
		handler:promote_next_level_data()
	end
end

mod.on_enabled = function (initial_call)
	if not initial_call then
		swap_keep()
	end
end

mod.on_disabled = function (initial_call)
	if not initial_call then
		swap_keep()
	end
end
