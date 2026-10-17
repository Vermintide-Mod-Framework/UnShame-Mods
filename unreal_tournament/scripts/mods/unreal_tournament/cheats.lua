local mod = get_mod("unreal_tournament")

-- UT's console commands that are done with the game's own mechanics: /suicide, /addbots, /killbots, /hud and /freecamera. The other
-- commands are with what they belong to: /slomo, /god and /allammo in hooks.lua, /fly, /ghost and /walk in movement.lua.

local function local_player_and_unit()
	local player = Managers.player:local_player_safe()
	local unit = player and player.player_unit

	if unit and Unit.alive(unit) then
		return player, unit
	end

	return player, nil
end

-- UT's "suicide" (PlayerController.Suicide): the player dies at once. The host is asked to kill the character with the request the game
-- sends when a player falls into a kill zone (PlayerUnitHealthExtension.entered_kill_volume), with the game's damage type for a forced
-- kill.
mod:command("suicide", "- you die at once (UT's suicide)", function ()
	local _, unit = local_player_and_unit()
	local unit_id = unit and Managers.state.unit_storage:go_id(unit)

	if unit_id then
		Managers.state.network.network_transmit:send_rpc_server("rpc_request_insta_kill", unit_id, NetworkLookup.damage_types.forced)
	end
end)

-- UT's "addbots" and "killbots" (DeathMatch.AddBots and KillBots): the hero bots. The game adds bots to the party's empty slots, up to
-- its cap on the number of bots, and removes bots above it (GameModeAdventure._handle_bots). These set that cap (mod.bot_cap, which
-- gameplay.lua gives the game), so the game adds or removes them. Only the host has bots. The cap lasts until the level is left, as UT's
-- last until the match ends.
-- Returns whether the command can be used, and the number of bots it was given
local function bot_command(command, argument)
	local number = argument and tonumber(argument)

	if argument and (not number or number ~= math.floor(number) or number < 1) then
		mod:echo("%s: a whole number of bots", command)

		return false
	end

	if not Managers.player.is_server then
		mod:echo("%s: only the host has bots", command)

		return false
	end

	return true, number
end

mod:command("addbots", "[number] - adds that many hero bots (1), as there are empty places (UT's addbots)", function (argument)
	local ok, number = bot_command("addbots", argument)

	if ok then
		mod.bot_cap = math.min(#Managers.player:bots() + (number or 1), Managers.party:get_party(1).num_slots)
	end
end)

mod:command("killbots", "[number] - removes that many hero bots, or all of them (UT's killbots)", function (argument)
	local ok, number = bot_command("killbots", argument)

	if ok then
		mod.bot_cap = number and math.max(#Managers.player:bots() - number, 0) or 0
	end
end)

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	mod.bot_cap = nil
end

-- UT's "togglescreenshotmode" (PlayerController.ToggleScreenShotMode): the HUD, the crosshair and the weapon are hidden, or shown again.
-- The HUD goes with the game's photo mode, which is what hides it while emoting (the HUD's "emote_photomode" group shows nothing, and the
-- outlines are hidden too, as UT hides its team beacons). The arms and the weapon go with the game's own switch for the first person
-- units, which the weapon skins follow. A new character (after dying, or in the next level) is hidden too.
local hud_hidden = false
local hud_unit

local function set_photomode(enabled)
	local game_mode = Managers.state.game_mode and Managers.state.game_mode:game_mode()

	if game_mode then
		game_mode:set_photomode_enabled(enabled)
	end
end

local function show_first_person_units(unit, show)
	local first_person_extension = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "first_person_system")

	if first_person_extension and first_person_extension:first_person_units_visible() ~= show then
		first_person_extension:toggle_first_person_units_visibility("ut_hud")
	end
end

mod:command("hud", "- hides the HUD, the crosshair and the weapon, or shows them again (UT's togglescreenshotmode)", function ()
	local _, unit = local_player_and_unit()

	hud_hidden = not hud_hidden

	set_photomode(hud_hidden)
	show_first_person_units(unit, not hud_hidden)

	hud_unit = hud_hidden and unit or nil
end)

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	if not hud_hidden then
		return
	end

	local _, unit = local_player_and_unit()

	if unit and unit ~= hud_unit then
		hud_unit = unit

		set_photomode(true)
		show_first_person_units(unit, false)
	end
end

-- UT's "freecamera" (CheatManager.FreeCamera): the camera is behind the character and the mouse turns it around them, while the
-- character keeps facing the way they did, and moves and shoots that way. The camera is the game's emote camera (the third person
-- follow camera with allow_camera_movement, which turns with the look input itself, and the "emotes" node), at the distance an emote
-- settles at. The character's own turning is taken away, and the game's changes of camera back to the first person view are turned
-- into this camera, as the game does for its third person debug mode (CharacterStateHelper.change_camera_state).
local free_camera_unit

local FREE_CAMERA_PARAMS = {
	allow_camera_movement = true,
	camera_node = "emotes",
	force_state_change = true,
	override_node_name = "camera_attach",
}

-- (PlayerCharacterStateEmote: its zoom goes to 0.7, and the camera's variable is 1 minus that)
local FREE_CAMERA_ZOOM = 0.3

local function start_free_camera(player, unit)
	local params = table.clone(FREE_CAMERA_PARAMS)

	params.override_follow_unit = unit

	Managers.state.entity:system("camera_system"):external_state_change(player, "follow_third_person", params)
	Managers.state.camera:set_variable(player.viewport_name, "emote_zoom", FREE_CAMERA_ZOOM)
	ScriptUnit.extension(unit, "first_person_system"):set_first_person_mode(false)
end

mod:command("freecamera", "- the camera goes behind you, and the mouse turns it around you, or back (UT's freecamera)", function ()
	local player, unit = local_player_and_unit()

	if not unit then
		return
	end

	if free_camera_unit then
		free_camera_unit = nil

		CharacterStateHelper.change_camera_state(player, "follow")
		ScriptUnit.extension(unit, "first_person_system"):set_first_person_mode(true)
	else
		free_camera_unit = unit

		start_free_camera(player, unit)
	end
end)

-- The free camera is the character's. It ends with that character (a death, a new level).
mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	if free_camera_unit then
		local _, unit = local_player_and_unit()

		if unit ~= free_camera_unit then
			free_camera_unit = nil
		end
	end
end

mod:hook(CharacterStateHelper, "change_camera_state", function (func, player, state, params)
	local unit = player and player.player_unit

	if state == "follow" and unit and unit == free_camera_unit then
		return start_free_camera(player, unit)
	end

	return func(player, state, params)
end)

mod:hook(PlayerUnitFirstPerson, "set_first_person_mode", function (func, self, active, ...)
	if self.unit == free_camera_unit then
		active = false
	end

	return func(self, active, ...)
end)

mod:hook(PlayerUnitFirstPerson, "set_look_delta", function (func, self, look_delta, ...)
	if self.unit == free_camera_unit then
		look_delta = Vector3.zero()
	end

	return func(self, look_delta, ...)
end)
