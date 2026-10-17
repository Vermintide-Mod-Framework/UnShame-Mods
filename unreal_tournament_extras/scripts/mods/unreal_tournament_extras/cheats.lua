local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- UT's console commands as chat commands, done with the game's own mechanics, and /skin for the weapon skins.

local function local_player_and_unit()
	local player = Managers.player:local_player_safe()
	local unit = player and player.player_unit

	if unit and Unit.alive(unit) then
		return player, unit
	end

	return player, nil
end

-- UT's "slomo": the game runs at that speed. Below 1 slows it down, above 1 speeds it up, 1 is normal.
mod:command("slomo", "<number> - the speed of the game: below 1 slower, above 1 faster, 1 is normal", function (scale)
	local number = tonumber(scale)

	if not number or number < 0 then
		mod:echo("slomo: a number, 1 is normal")

		return
	end

	Managers.time:set_global_time_scale(number)
	mod:echo("slomo: %g", number)
end)

-- UT's cheat "god" (CheatManager.God): the player who uses it takes no damage, until they use it again. The damage is the host's to
-- give, so the player's machine tells the host, which marks the character's health as invincible (the game's own flag, which
-- PlayerUnitHealthExtension.add_damage looks at). A new character (after dying, or in the next level) is marked again.
local god_mode = false
local god_unit

mod:network_register("ut_god", function (_, go_id, enabled)
	local unit = Managers.player.is_server and Managers.state.unit_storage:unit(go_id)
	local health_extension = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "health_system")

	if health_extension then
		health_extension.is_invincible = enabled
	end
end)

local function send_god_mode(unit)
	local go_id = Managers.state.unit_storage:go_id(unit)

	if go_id then
		mod:network_send("ut_god", "all", go_id, god_mode)
	end
end

mod:command("god", "- you take no damage, or take it again (UT's god)", function ()
	local _, unit = local_player_and_unit()

	god_mode = not god_mode

	if unit then
		god_unit = unit

		send_god_mode(unit)
	end

	mod:echo(god_mode and "God mode on" or "God mode off")
end)

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	if not god_mode then
		return
	end

	local _, unit = local_player_and_unit()

	if unit and unit ~= god_unit and Managers.state.unit_storage:go_id(unit) then
		god_unit = unit

		send_god_mode(unit)
	end
end

-- UT's cheat "allammo" (CheatManager.AllAmmo): fills the ranged weapon's ammo, or sets it to the amount given
mod:command("allammo", "[amount] - fills the ammo of the ranged weapon, or sets it to that (a whole number)", function (amount)
	local number = tonumber(amount)

	if amount and (not number or number ~= math.floor(number) or number < 0) then
		mod:echo("allammo: a whole number, or nothing to fill it")

		return
	end

	local _, unit = local_player_and_unit()
	local inventory_extension = unit and ScriptUnit.has_extension(unit, "inventory_system")
	local slot_data = inventory_extension and inventory_extension:get_slot_data("slot_ranged")
	local ammo_extension = slot_data and GearUtils.get_ammo_extension(slot_data.right_unit_1p, slot_data.left_unit_1p)

	if not ammo_extension then
		mod:echo("allammo: no ranged weapon with ammo")

		return
	end

	if number then
		-- The clip holds what it can, and the rest is in reserve
		local total = math.min(number, ammo_extension:max_ammo())
		local in_clip = math.min(total, ammo_extension:clip_size())

		ammo_extension._shots_fired = 0
		ammo_extension._current_ammo = in_clip
		ammo_extension._available_ammo = total - in_clip
		ammo_extension:_update_anim_ammo()
	else
		ammo_extension:add_ammo()
	end

	mod:echo("allammo: %d", ammo_extension:total_remaining_ammo())
end)

-- UT's cheats "fly", "ghost" and "walk": the flight is the Unreal Tournament mod's (movement.lua, mod.flight)
mod:command("fly", "- you fly the way you look, with no gravity, until /walk (UT's fly)", function ()
	if ut.flight.start(false) then
		mod:echo("You feel much lighter")
	end
end)

mod:command("ghost", "- you fly the way you look, through walls, until /walk (UT's ghost)", function ()
	if ut.flight.start(true) then
		mod:echo("You feel ethereal")
	end
end)

mod:command("walk", "- ends /fly and /ghost", function ()
	ut.flight.stop()
end)

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
-- its cap on the number of bots, and removes bots above it (GameModeAdventure._handle_bots). These set that cap for the call that handles
-- the bots, so the game adds or removes them. Only the host has bots. The cap lasts until the level is left, as UT's last until the match
-- ends.
local bot_cap

for _, game_mode_name in ipairs({
	"GameModeAdventure",
	"GameModeDeus",
	"GameModeWeave",
}) do
	local game_mode = rawget(_G, game_mode_name)

	if game_mode then
		mod:hook(game_mode, "_handle_bots", function (func, self, ...)
			local cap = script_data.cap_num_bots

			if bot_cap then
				script_data.cap_num_bots = bot_cap
			end

			func(self, ...)

			script_data.cap_num_bots = cap
		end)
	end
end

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
		bot_cap = math.min(#Managers.player:bots() + (number or 1), Managers.party:get_party(1).num_slots)
	end
end)

mod:command("killbots", "[number] - removes that many hero bots, or all of them (UT's killbots)", function (argument)
	local ok, number = bot_command("killbots", argument)

	if ok then
		bot_cap = number and math.max(#Managers.player:bots() - number, 0) or 0
	end
end)

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	bot_cap = nil
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

-- The character being turned to the camera (see below), while the inspection starts
local turning_unit

mod:hook(CharacterStateHelper, "change_camera_state", function (func, player, state, params)
	local unit = player and player.player_unit

	-- (the inspection's own camera is not used: the free camera stays)
	if unit and unit == turning_unit then
		return
	end

	if state == "follow" and unit and unit == free_camera_unit then
		return start_free_camera(player, unit)
	end

	return func(player, state, params)
end)

-- With the free camera, the game's inspect key turns the character to face the way the camera looks, with the game's own turn to a
-- rotation (PlayerUnitFirstPerson.force_look_rotation). Their pitch stays as it was.
mod:hook(PlayerCharacterStateInspecting, "on_enter", function (func, self, unit, ...)
	if unit ~= free_camera_unit then
		return func(self, unit, ...)
	end

	turning_unit = unit

	local ok, error_message = pcall(func, self, unit, ...)

	turning_unit = nil

	if not ok then
		error(error_message, 0)
	end

	local first_person_extension = self.first_person_extension
	local camera_rotation = Managers.state.camera:camera_rotation(self.player.viewport_name)
	local yaw = Quaternion(Vector3.up(), Quaternion.yaw(camera_rotation))
	local pitch = Quaternion(Vector3.right(), Quaternion.pitch(first_person_extension:current_rotation()))

	first_person_extension:force_look_rotation(Quaternion.multiply(yaw, pitch))
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

-- The weapon skins' development commands (weapon_skin.lua's command of each skin)
mod:command("skin", "<weapon> debug | report | play <animation> | set <number> <value> | 3p <number> <value> - the weapon skins", function (id, ...)
	local skins = ut.weapon_skin.skins
	local skin = id and skins[id]

	if skin then
		skin.command(...)
	else
		local names = {}

		for name in pairs(skins) do
			names[#names + 1] = name
		end

		table.sort(names)
		mod:echo("skin: one of %s", table.concat(names, ", "))
	end
end)
