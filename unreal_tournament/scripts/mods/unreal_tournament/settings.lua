local mod = get_mod("unreal_tournament")

-- The mod's options as they apply on this machine (mod.option). In a game, every machine plays by the host's options, so that everyone
-- has the same movement, barriers, gameplay and rewards; only the Announcer, which voices the player's own rewards to them, is each
-- player's own. The host sends its options to each player who joins, and to everyone when one changes.
--   mod.option(setting_id): whether the option is on here. An option under another (its sub_widgets in unreal_tournament_data.lua) is on
--       only while the one above it is on too.
--   mod.option_changed_callbacks[i] = function (): runs when the options that apply here may have changed (the player's own, or the
--       host's that came in).

-- The options that are each player's own
local OWN = {
	announcer = true,
}

-- Each option's default and the option above it, read from the options' definition
local defaults = {}
local parents = {}

local function read_widgets(widgets, parent)
	for _, widget in ipairs(widgets or {}) do
		defaults[widget.setting_id] = widget.default_value
		parents[widget.setting_id] = parent

		read_widgets(widget.sub_widgets, widget.setting_id)
	end
end

read_widgets(mod:dofile("scripts/mods/unreal_tournament/unreal_tournament_data").options.widgets)

mod.option_changed_callbacks = {}

local function call_option_changed()
	for _, callback in ipairs(mod.option_changed_callbacks) do
		callback()
	end
end

-- The host's options, as it sent them, and the host that sent them
local host_options = {}
local host_peer

local function is_server()
	local network_manager = Managers.state.network

	return network_manager == nil or network_manager.is_server
end

local function current_host()
	local network_manager = Managers.state.network

	return network_manager and network_manager.game_session_host and network_manager:game_session_host()
end

local function own_value(setting_id)
	local value = mod:get(setting_id)

	if value == nil then
		value = defaults[setting_id]
	end

	return value == true
end

-- The option itself, without the one above it: the player's own, or the host's in a game that another hosts
local function value_of(setting_id)
	if OWN[setting_id] or is_server() or host_peer == nil or host_peer ~= current_host() or host_options[setting_id] == nil then
		return own_value(setting_id)
	end

	return host_options[setting_id] == true
end

function mod.option(setting_id)
	local parent = parents[setting_id]

	return value_of(setting_id) and (parent == nil or mod.option(parent))
end

-- The options the host sends: all but each player's own
local function shared_options()
	local options = {}

	for setting_id in pairs(defaults) do
		if not OWN[setting_id] then
			options[setting_id] = own_value(setting_id)
		end
	end

	return options
end

mod:network_register("ut_options", function (sender, options)
	if is_server() or type(options) ~= "table" then
		return
	end

	host_options = options
	host_peer = sender

	call_option_changed()
end)

-- A player who joins gets the host's options
mod.user_joined_callbacks[#mod.user_joined_callbacks + 1] = function (player)
	if is_server() and Managers.state.network then
		mod:network_send("ut_options", player.peer_id, shared_options())
	end
end

-- A change of the host's options goes to everyone, and any change may change what applies here
mod.setting_changed_callbacks[#mod.setting_changed_callbacks + 1] = function (setting_id)
	if not OWN[setting_id] and is_server() and Managers.state.network then
		mod:network_send("ut_options", "others", shared_options())
	end

	call_option_changed()
end
