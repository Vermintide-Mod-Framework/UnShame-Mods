local mod = get_mod("red_moon_inn")

-- The inn takes the keep's place. The keep's level settings, and those of the keeps the game loads during events,
-- load the inn's level instead. The game's checks for the keep use the settings' keys, so they keep working.
-- The keep's packages stay as they are: the game unloads a level's packages by the list in its settings, so changing
-- the list while the level is loaded would unload packages that were never loaded.
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

-- The key of the host's lobby data that says whether the host uses the inn
local LOBBY_KEY = "red_moon_inn"

-- How long the host waits for a joining player's game to say it loads the inn. A player without the mod never says it.
-- VMF learns which mods a player has once they are in the game, and the answer comes right after that.
local CONFIRM_TIME = 10

-- The keeps' own levels, kept when the mod is reloaded, when the settings may already have the inn
local keep_levels = mod:persistent_table("keep_levels")

for _, key in ipairs(KEEP_KEYS) do
	local settings = LevelSettings[key]

	if settings and not keep_levels[key] then
		keep_levels[key] = settings.level_name
	end
end

local function use_inn(use)
	for key, keep_level in pairs(keep_levels) do
		LevelSettings[key].level_name = use and INN_LEVEL or keep_level
	end
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

-- The level is chosen when the loading screen starts spawning it
mod:hook(StateLoading, "_try_next_state", function (func, self, ...)
	if not self._async_level_spawner then
		use_inn(loads_inn())
	end

	return func(self, ...)
end)

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

	if keep_levels[level_key] and Managers.player.is_server and Managers.state.game_mode then
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

mod.on_enabled = function (initial_call)
	use_inn(loads_inn())

	if not initial_call then
		update_lobby_data(true)
		tell_host()
		reload_keep()
	end
end

mod.on_disabled = function (initial_call)
	use_inn(false)

	if not initial_call then
		update_lobby_data(false)
		tell_host()
		reload_keep()
	end
end
