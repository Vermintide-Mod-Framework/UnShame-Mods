local mod = get_mod("unreal_tournament")

-- Shield Gun skin: how UT2004's Shield Gun looks and sounds.
--
-- weapon_skin.lua does the model, its placement and animations, the bob and the third person. This file does what is the Shield Gun's
-- own: the animations of the charge, the punch and the shield, and their sounds. The gameplay is in shield_gun.lua, which tells this file
-- what happens through mod.shield.
--
-- The assets were made with tools/asset_conversion (convert_weapon.py shield, convert_static.py shield_pickup, render_icon.py and
-- make_bank.py shield_gun).

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local animations = mod:dofile("scripts/mods/unreal_tournament/shield/skin_animations")

local CONFIG = {
	inspect_pose_speed = 5,
	inspect_sway = 5,
	inspect_sway_speed = 1.8,
}

local shield = mod.shield

local VARIANTS = {
	"shield_gun",
	"shield_gun_dr",
	"shield_gun_bw",
	"shield_gun_wh",
	"shield_gun_we",
	"shield_gun_priest",
}

local skin_apis = {}

-- Whether the player's own character is blocking, which is the shield being up
local function local_player_blocking()
	local player = Managers.player and Managers.player:local_player()
	local unit = player and player.player_unit
	local status_extension = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "status_system")

	return status_extension and status_extension:is_blocking() or false
end

-- The animations follow what the gun does (ShieldFire and ShieldAltFire): the charge plays Charge over FullyChargedTime and then loops
-- Charged (PlayPreFire, ShieldGun.AnimEnd), the punch plays Fire, and the shield loops Shield while it is up.
local function update_state(api, skin)
	local charging = shield.charge_started ~= nil
	local blocking = local_player_blocking()

	if charging and skin.seen_charge ~= shield.charge_started then
		skin.seen_charge = shield.charge_started
		skin.charged = false

		api.play("Charge", shield.fully_charged_time)
		api.stop_sound(skin.charge_sound)

		skin.charge_sound = api.play_sound("ut_shield_charge")
	elseif charging and not skin.charged and skin.animation == "Charge" and skin.time >= api.animation_duration("Charge") then
		skin.charged = true

		api.play("Charged", nil, true)
	end

	if shield.last_punch and skin.seen_punch ~= shield.last_punch then
		skin.seen_punch = shield.last_punch

		api.stop_sound(skin.charge_sound)

		skin.charge_sound = nil

		api.play("Fire")
		api.play_sound("ut_shield_fire")
	end

	if blocking ~= skin.blocking then
		skin.blocking = blocking

		if blocking then
			api.play("Shield", nil, true)

			skin.shield_sound = api.play_sound("ut_shield_up")
		else
			api.stop_sound(skin.shield_sound)

			skin.shield_sound = nil

			if not charging then
				api.play("Idle")
			end
		end
	end
end

local function new_skin(setting_id)
	local definition = mod.items.weapons[setting_id]
	local api

	api = mod.weapon_skin.new({
		id = setting_id,
		name = "shield gun",
		template = definition.template,
		unit_name = "units/ut/shield/shield_gun",
		animations = animations,
		muzzle_node = "b_bone_flash",
		-- model_meters_per_unit is the meters per UT unit at which the model was converted (tools/asset_conversion/convert_weapon.py).
		-- meters_per_unit is the distance scale: the meters of forward in the view that one UT unit of the model takes up.
		model_meters_per_unit = 0.0125,
		meters_per_unit = 0.01,
		-- ShieldGun.uc
		display_fov = 60,
		draw_scale = 0.4,
		select_speed = 1.3636, -- Weapon's default SelectAnimRate
		offset_forward = 2,
		offset_right = -0.7,
		offset_up = -2.7,
		pivot_pitch = 500 / 65536 * 360,
		pivot_yaw = 500 / 65536 * 360,
		bob_damping = 2.2,
		-- The inspect pose turns the gun to show its side, like the other weapons. These numbers are a guess.
		inspect_pose_right = -2,
		inspect_pose_forward = 4,
		inspect_pose_up = 0,
		inspect_pose_roll = 10,
		inspect_pose_pitch = 4,
		inspect_pose_yaw = 55,
		inspect_turn_start = 0.35,
		inspect_pivot_right = 0,
		inspect_pivot_forward = 20,
		inspect_pivot_up = 0,
		-- WeaponStaticMesh.ShieldGunPickup. The game links a melee weapon to the right hand's node.
		third_person = {
			id = setting_id,
			template = definition.template,
			unit_name = "units/ut/shield/pickup",
			hand_node = "j_rightweaponattach",
			meters_per_unit = 0.01,
			scale = 0.5,
			grip_right = 0,
			grip_forward = 0,
			grip_up = 0,
			yaw = -60,
			pitch = 0,
			roll = 0,
			follow_game_unit = 1,
			follow_calibrate_seconds = 1,
			muzzle_right = 0,
			muzzle_forward = 30,
			muzzle_up = 0,
			menu_yaw = 180,
		},
		on_create = function ()
			api.play_sound("ut_shield_select")
		end,
		on_update = function (skin, dt)
			skin.inspect_pose = (skin.inspect_pose or 0) + ((skin.inspecting and 1 or 0) - (skin.inspect_pose or 0)) * math.min(1, CONFIG.inspect_pose_speed * dt)
			skin.inspect_time = skin.inspecting and (skin.inspect_time or 0) + dt or 0
			skin.extra_yaw = skin.inspect_pose * CONFIG.inspect_sway * math.sin(skin.inspect_time * CONFIG.inspect_sway_speed)

			update_state(api, skin)
		end,
		on_destroy = function (skin)
			api.stop_sound(skin.charge_sound)
			api.stop_sound(skin.shield_sound)
		end,
	})

	skin_apis[#skin_apis + 1] = api

	return api
end

for _, setting_id in ipairs(VARIANTS) do
	new_skin(setting_id)
end

-- Inspecting is the game's own action, held with the key
mod.inspect_callbacks.shield_skin = function (action, started)
	for _, api in ipairs(skin_apis) do
		local skin = api.state()

		if skin and utils.is_local_player_unit(action.owner_unit) then
			skin.inspecting = started
		end
	end
end

-- The melee weapon's own swings are not played on the player's own first person unit: their sounds are in the animations. The skin's
-- model plays UT's.
for template_name in pairs(shield.template_names) do
	mod.first_person_animation_filters[template_name] = function (event)
		return string.find(event, "attack", 1, true) ~= nil
	end
end
