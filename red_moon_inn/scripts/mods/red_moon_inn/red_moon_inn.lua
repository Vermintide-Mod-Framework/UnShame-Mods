local mod = get_mod("red_moon_inn")

-- The inn takes the keep's place. The keep's level settings, and those of the keeps the game loads during events,
-- load the inn's level and its packages instead. The game's checks for the keep use the settings' keys, so they keep
-- working.
--
-- The settings only change right before the loading screen loads a level. The game finds the level it is in by the
-- name in the settings, and unloads a level's packages by the list in them, so they have to stay as they were for as
-- long as that level is loaded.
--
-- In multiplayer the host decides. Every game picks the keep's level from its own settings when it loads it, so the host
-- puts whether it uses the inn in its lobby's data, and a client loads the inn only when the host does. The host removes
-- players whose game doesn't load the inn: those without the mod, or with it turned off.

local INN_LEVEL = "levels/red_moon_inn/red_moon_inn/world"

-- The keep, and the keeps with the decorations of events
local KEEP_KEYS = {
	"inn_level",
	"inn_level_celebrate",
	"inn_level_halloween",
	"inn_level_skulls",
	"inn_level_sonnstill",
}

-- The keep's packages the inn needs too. The others are the keep's level, its occlusion data (tome) and the event
-- decorations: the keep's occlusion data hides parts of the inn.
local INN_PACKAGES = {
	["resource_packages/levels/inn_dependencies"] = true,
}

-- The key of the host's lobby data that says whether the host uses the inn
local LOBBY_KEY = "red_moon_inn"

-- How long the host waits for a joining player's game to say it loads the inn. A player without the mod never says it.
-- VMF learns which mods a player has once they are in the game, and the answer comes right after that.
local CONFIRM_TIME = 10

-- The keeps' own settings, and whether the settings have the inn now. Kept when the mod is reloaded.
local keep = mod:persistent_table("keep")
keep.levels = keep.levels or {}
keep.packages = keep.packages or {}

for _, key in ipairs(KEEP_KEYS) do
	local settings = LevelSettings[key]

	if settings and not keep.levels[key] then
		keep.levels[key] = settings.level_name
		keep.packages[key] = settings.packages
	end
end

local function inn_packages(packages)
	local kept = {}

	for _, package in ipairs(packages) do
		if INN_PACKAGES[package] then
			kept[#kept + 1] = package
		end
	end

	return kept
end

-- Gives the keeps' settings the inn or the keep. If a keep is loaded, its packages are released first, by the list
-- they were loaded by. Only called when no level is in the world.
local function use_inn(use)
	if keep.uses_inn == use then
		return
	end

	local handler = Managers.level_transition_handler

	if handler and keep.levels[handler._currently_loaded_level_key] then
		handler:release_level_resources()
	end

	for key, level_name in pairs(keep.levels) do
		LevelSettings[key].level_name = use and INN_LEVEL or level_name
		LevelSettings[key].packages = use and inn_packages(keep.packages[key]) or keep.packages[key]
	end

	keep.uses_inn = use
end

-- The lobby of the game this one is in, as host or client
local function session_lobby()
	return Managers.lobby and Managers.lobby:query_lobby("matchmaking_session_lobby")
end

-- Only the host's lobby can be given data
local function is_client_lobby(lobby)
	return lobby and not lobby.set_lobby_data and lobby.lobby_data
end

-- Whether this game loads the inn: as a client, when the host does; otherwise, when the mod is on
local function loads_inn()
	if not mod:is_enabled() then
		return false
	end

	local lobby = session_lobby()

	if is_client_lobby(lobby) then
		return lobby:lobby_data(LOBBY_KEY) == "true"
	end

	return true
end

-- Right before the loading screen loads the level. A client is in the host's lobby by then.
mod:hook(LevelTransitionHandler, "load_current_level", function (func, self, ...)
	use_inn(loads_inn())

	return func(self, ...)
end)

-- The hook above is off while the mod is off, and this runs anyway. The previous level's world is gone by then.
mod.on_game_state_changed = function (status, state_name)
	if status == "enter" and state_name == "StateLoading" and not mod:is_enabled() then
		use_inn(false)
	end
end

-- The host's lobby data says whether it uses the inn, each time the game sets it
mod:hook(LobbyHost, "set_lobby_data", function (func, self, lobby_data_table)
	lobby_data_table[LOBBY_KEY] = mod:is_enabled() and "true" or "false"

	return func(self, lobby_data_table)
end)

local function update_lobby_data(use)
	local lobby = session_lobby()

	if lobby and lobby.set_lobby_data then
		local lobby_data_table = lobby:get_stored_lobby_data() or {}

		lobby_data_table[LOBBY_KEY] = use and "true" or "false"
		lobby:set_lobby_data(lobby_data_table)
	end
end

-- Loads the level again when the mod is turned on or off in the keep. Only the host can.
local function reload_keep()
	local level_key = Managers.level_transition_handler and Managers.level_transition_handler:get_current_level_key()

	if keep.levels[level_key] and Managers.player.is_server and Managers.state.game_mode then
		Managers.state.game_mode:retry_level()
	end
end

-- Players' answers, on the host: whether each one's game loads the inn, and how long the host has waited for it
local loads_inn_by_peer = {}
local waited_by_peer = {}

mod:network_register("loads_inn", function (sender, loads)
	loads_inn_by_peer[sender] = loads
end)

-- Tells the host whether this game loads the inn
local function tell_host()
	local lobby = session_lobby()

	if is_client_lobby(lobby) then
		mod:network_send("loads_inn", lobby:lobby_host(), mod:is_enabled())
	end
end

mod.on_user_joined = function (player)
	local lobby = session_lobby()

	if is_client_lobby(lobby) and player.peer_id == lobby:lobby_host() then
		tell_host()
	end
end

-- VMF runs this while the mod is off too. The host only removes players while it uses the inn.
mod.update = function (dt)
	local network_server = Managers.state.network and Managers.state.network.network_server

	if not mod:is_enabled() or not Managers.player or not Managers.player.is_server or not network_server then
		return
	end

	local present = {}

	for _, player in pairs(Managers.player:human_players()) do
		local peer_id = player.peer_id

		if player.remote then
			present[peer_id] = true

			if loads_inn_by_peer[peer_id] ~= true then
				waited_by_peer[peer_id] = (waited_by_peer[peer_id] or 0) + dt

				if loads_inn_by_peer[peer_id] == false or waited_by_peer[peer_id] > CONFIRM_TIME then
					mod:echo(mod:localize("player_removed", player:name()))
					network_server:kick_peer(peer_id)
					loads_inn_by_peer[peer_id] = nil
					waited_by_peer[peer_id] = nil
				end
			end
		end
	end

	-- Players who left
	for peer_id in pairs(waited_by_peer) do
		if not present[peer_id] then
			waited_by_peer[peer_id] = nil
			loads_inn_by_peer[peer_id] = nil
		end
	end
end

-- When the game starts, no level is loaded yet. Afterwards the settings change when the next level loads. A mod
-- reloaded in a level leaves them to the next level too.
local function no_level_loaded()
	return not (Managers.state and Managers.state.game_mode)
end

mod.on_enabled = function (initial_call)
	if initial_call then
		if no_level_loaded() then
			use_inn(loads_inn())
		end
	else
		update_lobby_data(true)
		tell_host()
		reload_keep()
	end
end

mod.on_disabled = function (initial_call)
	if initial_call then
		if no_level_loaded() then
			use_inn(false)
		end
	else
		update_lobby_data(false)
		tell_host()
		reload_keep()
	end
end
