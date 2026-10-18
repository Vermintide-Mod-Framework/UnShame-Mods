local mod = get_mod("unreal_tournament")

-- Assault Rifle skin: how UT2004's Assault Rifle looks and sounds, two at a time.
--
-- weapon_skin.lua does the models, their placement and animations, the bob and the third person. There are two skins of the weapon: the
-- rifle in the right hand, and the one in the left, which is the same model mirrored (AssaultRifle.RenderDualOverlay draws the weapon a
-- second time with its mesh, offset, yaw and roll turned to the other side). Both play the same animations, as UT's are one weapon drawn
-- twice. This file does what is the rifle's own: the flash of the rounds, the grenades in flight, and the sounds. The gameplay is in
-- assault_rifle.lua.
--
-- The assets were made with tools/asset_conversion (convert_weapon.py assault, convert_static.py assault_pickup and assault_grenade,
-- render_icon.py and make_bank.py assault_rifle).

local utils = mod.utils
local animations = mod:dofile("scripts/mods/unreal_tournament/assault/skin_animations")

local SETTING_ID = "assault_rifle"
local TEMPLATE_NAME = mod.items.weapons[SETTING_ID].template
local assault = mod.assault

local CONFIG = {
	-- AssaultMuzFlash1st: the Minigun's flash at DrawScale 1.2 (see minigun/muzzle_flash.lua)
	flash_draw_scale = 1.2,
	-- Grenade: RandSpin(25000). It spins about a random axis at 25000 of UT's rotation units a second, where 65536 is a full turn.
	grenade_spin = 25000 / 65536,
	-- A bounce faster than this plays the impact sound (Grenade.HitWall)
	bounce_sound_speed = 250, -- UT units a second
	inspect_pose_speed = 5,
	inspect_sway = 5,
	inspect_sway_speed = 1.8,
}

local UNIT = utils.UT_UNIT

local skin_apis = {}

-- The flash of a round at the muzzle of a rifle in the player's view (see the Minigun's skin)
local function flash(api)
	local skin = api.state()

	if not skin then
		return
	end

	mod.minigun_muzzle_flash(api, function ()
		return api.state() == skin and api.muzzle_model_position() or nil
	end, (skin.unit_scale or UNIT) / api.draw_scale(), CONFIG.flash_draw_scale)
end

-- Plays an animation on both rifles
local function play_both(name, duration)
	for _, api in ipairs(skin_apis) do
		if api.state() then
			api.play(name, duration)
		end
	end
end

-- Called for each round. If the player on this machine fired it, both rifles play the fire animation, flash and sound. Otherwise the
-- sound plays at the shooter's muzzle.
mod.assault_round_callbacks.assault_skin = function (owner_unit)
	local right = skin_apis[1]

	if not right then
		return
	end

	if utils.is_local_player_unit(owner_unit) and right.state() then
		play_both("Fire")
		right.play_sound("ut_assault_fire")

		for _, api in ipairs(skin_apis) do
			flash(api)
		end

		return
	end

	local hand = right.third_person.muzzle_position(owner_unit)

	if hand then
		right.play_sound_at("ut_assault_fire_3d", hand)
	end
end

-- The grenade models, by grenade id. Every machine spawns one for each grenade in flight and spins it as it flies.
local grenade_units = {}

local function destroy_grenade_unit(id)
	local entry = grenade_units[id]

	if entry and Unit.alive(entry.unit) then
		World.destroy_unit(entry.world, entry.unit)
	end

	grenade_units[id] = nil
end

mod.assault_grenade_callbacks.assault_skin = function (grenade)
	local api = skin_apis[1]
	local world = Managers.world:world("level_world")

	grenade_units[grenade.id] = {
		axis = Vector3Box(Vector3.normalize(Vector3(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5))),
		grenade = grenade,
		unit = World.spawn_unit(world, "units/ut/assault/grenade", grenade.position:unbox()),
		world = world,
	}

	if utils.is_local_player_unit(grenade.owner_unit) and api.state() then
		play_both("AltFire", api.animation_duration("AltFire") / 0.5)
		api.play_sound("ut_assault_alt_fire")
		api.play_sound("ut_assault_grenade_load")
	else
		api.play_sound_at("ut_assault_alt_fire_3d", grenade.position:unbox())
	end
end

mod.assault_bounce_callbacks.assault_skin = function (grenade, position, speed)
	if speed > CONFIG.bounce_sound_speed then
		skin_apis[1].play_sound_at("ut_assault_grenade_bounce_3d", position)
	end
end

local function update_grenades()
	for id, entry in pairs(grenade_units) do
		local grenade = entry.grenade

		if grenade.exploded or not Unit.alive(entry.unit) then
			destroy_grenade_unit(id)
		else
			local spin = grenade.stopped and 0 or grenade.age * CONFIG.grenade_spin * 2 * math.pi

			Unit.set_local_position(entry.unit, 0, grenade.position:unbox())
			Unit.set_local_rotation(entry.unit, 0, Quaternion.axis_angle(entry.axis:unbox(), spin))
			World.update_unit(entry.world, entry.unit)
		end
	end
end

local function clear_grenades()
	for id in pairs(grenade_units) do
		destroy_grenade_unit(id)
	end
end

-- The grenade's explosion plays the Rocket Launcher's explosion and sound. UT's grenade explosion (NewExplosionB) looks much like the
-- rocket's (NewExplosionA).
mod.skin_explosion_callbacks[assault.explosion] = function (world, position, rotation, scale)
	local rocket = mod.skin_explosion_callbacks.ut_rocket_explosion

	if rocket then
		rocket(world, position, rotation, scale)
	end
end

local function new_skin(id, mirror)
	local api

	api = mod.weapon_skin.new({
		id = id,
		name = mirror and "assault rifle (left)" or "assault rifle",
		template = TEMPLATE_NAME,
		unit_name = mirror and "units/ut/assault/assault_rifle_left" or "units/ut/assault/assault_rifle",
		animations = animations,
		muzzle_node = "b_bone_flash_a",
		-- model_meters_per_unit is the meters per UT unit at which the model was converted (tools/asset_conversion/convert_weapon.py).
		-- meters_per_unit is the distance scale: the meters of forward in the view that one UT unit of the model takes up.
		model_meters_per_unit = 0.0125,
		meters_per_unit = 0.01,
		mirror = mirror,
		-- AssaultRifle.uc
		display_fov = 70,
		draw_scale = 0.8,
		select_speed = 1.3636, -- Weapon's default SelectAnimRate
		offset_forward = 4,
		offset_right = 5.5,
		offset_up = -6,
		pivot_pitch = 400 / 65536 * 360,
		bob_damping = 1.7,
		-- The inspect pose turns the rifle to show its side, like the other weapons. These numbers are a guess.
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
		-- UT's third person mesh of the weapon (AssaultAttachment's NewWeapons2004.NewAssaultRifle_3rd) at UT's size in a player's hand
		-- (DrawScale 0.4). There is one in each hand, where the game puts the brace of pistols (AttachmentNodeLinking). Its origin is by its
		-- grip, and its barrel runs along its forward, as the pickup's did, so it is turned as the pickup was. The muzzle is the rifle's
		-- Bone_Flash (Bone_Flash02, below it, is the grenade launcher's). The grip is a start, to be set in the game.
		third_person = {
			id = id,
			template = TEMPLATE_NAME,
			unit_name = "units/ut/assault/third_person",
			hand_node = mirror and "j_leftweaponattach" or "j_rightweaponattach",
			meters_per_unit = 0.02 * 0.4,
			scale = 1,
			grip_right = 0,
			grip_forward = 0,
			grip_up = 0,
			yaw = -90,
			pitch = 0,
			roll = 0,
			follow_game_unit = 1,
			follow_calibrate_seconds = 1,
			muzzle_right = 0,
			muzzle_forward = 49.3,
			muzzle_up = 17.9,
			menu_yaw = 180,
		},
		on_create = function ()
			if not mirror then
				api.play_sound("ut_assault_select")
			end
		end,
		on_update = function (skin, dt)
			skin.inspect_pose = (skin.inspect_pose or 0) + ((skin.inspecting and 1 or 0) - (skin.inspect_pose or 0)) * math.min(1, CONFIG.inspect_pose_speed * dt)
			skin.inspect_time = skin.inspecting and (skin.inspect_time or 0) + dt or 0
			skin.extra_yaw = skin.inspect_pose * CONFIG.inspect_sway * math.sin(skin.inspect_time * CONFIG.inspect_sway_speed)
		end,
		on_update_always = not mirror and update_grenades or nil,
		on_level_exit = not mirror and clear_grenades or nil,
		on_give_back = not mirror and clear_grenades or nil,
	})

	skin_apis[#skin_apis + 1] = api

	return api
end

new_skin(SETTING_ID, false)
new_skin(SETTING_ID .. "_left", true)

mod.unload_callbacks[#mod.unload_callbacks + 1] = clear_grenades

-- Inspecting is the game's own action, held with the key
mod.inspect_callbacks.assault_skin = function (action, started)
	for _, api in ipairs(skin_apis) do
		local skin = api.state()

		if skin and utils.is_local_player_unit(action.owner_unit) then
			skin.inspecting = started
		end
	end
end

-- The first person unit does not play the pistols' shot and reload animations. The skin's models play UT's animations instead.
mod.first_person_animation_filters[TEMPLATE_NAME] = function (event)
	return string.find(event, "attack", 1, true) ~= nil or string.find(event, "reload", 1, true) ~= nil or event == "lock_target"
end

mod.third_person_animation_filters[TEMPLATE_NAME] = function (event)
	return string.find(event, "reload", 1, true) ~= nil
end
