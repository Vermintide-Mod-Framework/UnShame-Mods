local mod = get_mod("unreal_tournament")

-- Redeemer skin: how UT2004's Redeemer looks and sounds.
--
-- weapon_skin.lua does the model, its placement and animations, the bob and the third person. This file does what is the Redeemer's own:
-- the missile, its trail and light and sound, and the blast. The gameplay is in redeemer.lua.
--
-- The assets were made with tools/asset_conversion (convert_weapon.py redeemer, convert_static.py redeemer_pickup and redeemer_missile,
-- make_weapon_fx.py, render_icon.py and make_bank.py redeemer).

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local animations = mod:dofile("scripts/mods/unreal_tournament/redeemer/skin_animations")
local particles = mod.skin_particles

local SETTING_ID = "redeemer"
local TEMPLATE_NAME = mod.items.weapons[SETTING_ID].template

local CONFIG = {
	meters_per_uu = 0.02,
	-- RedeemerProjectile.RotationRate: the missile turns about its length by 50000 of 65536 a second
	missile_turns_per_second = 50000 / 65536,
	-- The missile's flight sound (AmbientSound redeemer_flight) is played again when it ends
	flight_sound_seconds = 1.318,
	-- RedeemerProjectile's light: LightHue 28 (orange), LightRadius 6
	light_color = { 1, 0.6, 0.2 },
	light_intensity = 2,
	light_falloff = 6,
	-- NewRedeemerTrail, at 40 units behind the missile. Its flames: 7 at a time that each last 0.1 s, 10 to 30 units across and growing
	-- from a quarter of it, thrown back at 500 units a second, one of the 16 pictures of Part_explode2.
	trail_back = 40,
	flame_rate = 70, -- a second (MaxParticles 7 over a life of 0.1 s)
	flame_life = 0.1,
	flame_size = { 10, 30 },
	flame_speed = 500,
	-- Its smoke: 200 a second from 16 units behind it, 1 to 1.5 s each, 25 units across (from a tenth of it, full at half its life),
	-- white fading to grey, blended, one of the 16 pictures of MuchSmoke1
	smoke_rate = 200,
	smoke_back = 16,
	smoke_life = { 1, 1.5 },
	smoke_size = 25,
	inspect_pose_speed = 5,
	inspect_sway = 5,
	inspect_sway_speed = 1.8,
}

local UNIT = CONFIG.meters_per_uu

local skin_api

local function random_between(range)
	return range[1] + (range[2] - range[1]) * math.random()
end

-- The missiles in flight, on every machine
local missiles = {}

local function destroy_missile(missile)
	if Unit.alive(missile.unit) then
		World.destroy_unit(missile.world, missile.unit)
	end
end

local function clear_missiles()
	for _, missile in ipairs(missiles) do
		destroy_missile(missile)
	end

	table.clear(missiles)
end

local function trail(missile, position, direction, dt)
	missile.flame_time = missile.flame_time + dt
	missile.smoke_time = missile.smoke_time + dt

	local back = position - direction * (CONFIG.trail_back * UNIT)

	while missile.flame_time >= 1 / CONFIG.flame_rate do
		missile.flame_time = missile.flame_time - 1 / CONFIG.flame_rate

		local size = random_between(CONFIG.flame_size) * UNIT

		particles.sprite({
			attenuation = 0.5,
			color = { 1, 1, 1 },
			growth = size * 0.75 / CONFIG.flame_life,
			life = CONFIG.flame_life,
			position = back,
			size = size * 0.25,
			spin = (math.random() * 2 - 1) * 0.5,
			texture = "redeemer_flame_" .. math.random(0, 15),
			velocity = -direction * (CONFIG.flame_speed * UNIT),
		})
	end

	while missile.smoke_time >= 1 / CONFIG.smoke_rate do
		missile.smoke_time = missile.smoke_time - 1 / CONFIG.smoke_rate

		local life = random_between(CONFIG.smoke_life)
		local size = CONFIG.smoke_size * UNIT

		particles.sprite({
			additive = 0,
			attenuation = 0.05,
			color = { 1, 1, 1 },
			growth = size * 0.9 / (life * 0.5),
			life = life,
			position = position - direction * ((CONFIG.trail_back + CONFIG.smoke_back) * UNIT),
			size = size * 0.1,
			spin = (math.random() * 2 - 1) * 0.1,
			texture = "redeemer_smoke_" .. math.random(0, 15),
		})
	end
end

local function update_missiles(dt)
	for index = #missiles, 1, -1 do
		local missile = missiles[index]
		local game_unit = missile.game_unit

		if not Unit.alive(game_unit) or missile.projectile._stop_impacts or not Unit.alive(missile.unit) then
			destroy_missile(missile)
			table.remove(missiles, index)
		else
			local position = Unit.world_position(game_unit, 0)
			local moved = position - missile.previous:unbox()

			missile.previous:store(position)
			missile.time = missile.time + dt
			missile.sound_time = missile.sound_time - dt

			if Vector3.length(moved) > 0.0001 then
				missile.direction:store(Vector3.normalize(moved))
			end

			local direction = missile.direction:unbox()
			local turn = Quaternion.axis_angle(Vector3(0, 1, 0), missile.time * CONFIG.missile_turns_per_second * 2 * math.pi)

			Unit.set_local_position(missile.unit, 0, position)
			Unit.set_local_rotation(missile.unit, 0, Quaternion.multiply(Quaternion.look(direction, Vector3.up()), turn))
			trail(missile, position, direction, dt)

			if missile.sound_time <= 0 then
				missile.sound_time = CONFIG.flight_sound_seconds

				skin_api.play_sound_at("ut_redeemer_flight_3d", position)
			end
		end
	end
end

-- The missile's flow events would start the game's own effects on its unit, so they are dropped
mod.init_flow_event_filters.redeemer = function (event_name)
	return event_name == "lua_projectile_init" or event_name == "lua_trail" or event_name == "vfx_critical_strike"
end

-- Each missile is UT's mesh, drawn at the game's unit, which is not shown
mod.skin_init_callbacks.redeemer = function (projectile)
	local world = Managers.world:world("level_world")
	local game_unit = projectile._projectile_unit
	local position = Unit.world_position(game_unit, 0)

	Unit.set_unit_visibility(game_unit, false)

	local missile = {
		direction = Vector3Box(Vector3.forward()),
		flame_time = 0,
		game_unit = game_unit,
		previous = Vector3Box(position),
		projectile = projectile,
		smoke_time = 0,
		sound_time = 0,
		time = 0,
		unit = World.spawn_unit(world, "units/ut/redeemer/missile", position),
		world = world,
	}

	missiles[#missiles + 1] = missile

	particles.light({
		brightness = function ()
			return 1
		end,
		color = CONFIG.light_color,
		falloff = CONFIG.light_falloff,
		follow = function ()
			if Unit.alive(game_unit) and not projectile._stop_impacts then
				return Unit.world_position(game_unit, 0)
			end
		end,
		intensity = CONFIG.light_intensity,
		life = 30,
	})

	if not utils.is_local_player_unit(projectile._owner_unit) then
		local hand = skin_api.third_person.muzzle_position(projectile._owner_unit)

		skin_api.play_sound_at("ut_redeemer_fire_3d", hand or position)
	end
end

skin_api = mod.weapon_skin.new({
	id = SETTING_ID,
	name = "redeemer",
	template = TEMPLATE_NAME,
	unit_name = "units/ut/redeemer/redeemer",
	animations = animations,
	muzzle_node = "b_bone_flash",
	-- model_meters_per_unit is the meters per UT unit at which the model was converted (tools/asset_conversion/convert_weapon.py).
	-- meters_per_unit is the distance scale: the meters of forward in the view that one UT unit of the model takes up.
	model_meters_per_unit = 0.0125,
	meters_per_unit = 0.01,
	-- Redeemer.uc
	display_fov = 60,
	draw_scale = 1.2,
	select_speed = 0.667, -- SelectAnimRate
	offset_forward = 14,
	offset_right = 0,
	offset_up = -28,
	pivot_pitch = 1000 / 65536 * 360,
	pivot_yaw = -400 / 65536 * 360,
	bob_damping = 1.4,
	-- The inspect pose turns the launcher to show its side, like the other weapons. These numbers are a guess.
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
	-- WeaponStaticMesh.RedeemerPickup. The game links the Trollhammer Torpedo to the right hand's node.
	third_person = {
		id = SETTING_ID,
		template = TEMPLATE_NAME,
		unit_name = "units/ut/redeemer/pickup",
		hand_node = "j_rightweaponattach",
		meters_per_unit = 0.018,
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
		muzzle_forward = 40,
		muzzle_up = 0,
		menu_yaw = 180,
	},
	on_create = function ()
		skin_api.play_sound("ut_redeemer_select")
	end,
	on_update = function (skin, dt)
		skin.inspect_pose = (skin.inspect_pose or 0) + ((skin.inspecting and 1 or 0) - (skin.inspect_pose or 0)) * math.min(1, CONFIG.inspect_pose_speed * dt)
		skin.inspect_time = skin.inspecting and (skin.inspect_time or 0) + dt or 0
		skin.extra_yaw = skin.inspect_pose * CONFIG.inspect_sway * math.sin(skin.inspect_time * CONFIG.inspect_sway_speed)
	end,
	on_update_always = update_missiles,
	on_level_exit = clear_missiles,
	on_give_back = clear_missiles,
})

mod.unload_callbacks[#mod.unload_callbacks + 1] = clear_missiles

-- The shot of the player: the animation and the sound
mod:hook_safe(ActionGrenadeThrower, "client_owner_start_action", function (self, new_action)
	if new_action.ut_redeemer and utils.is_local_player_unit(self.owner_unit) and skin_api.state() then
		skin_api.play("Fire")
		skin_api.play_sound("ut_redeemer_fire")
	end
end)

-- Inspecting is the game's own action, held with the key
mod.inspect_callbacks.redeemer_skin = function (action, started)
	local skin = skin_api.state()

	if skin and utils.is_local_player_unit(action.owner_unit) then
		skin.inspecting = started
	end
end

-- The Trollhammer's own shot animations are not played on the player's own first person unit: the skin's model plays UT's
mod.first_person_animation_filters[TEMPLATE_NAME] = function (event)
	return string.find(event, "attack_shoot", 1, true) ~= nil or string.find(event, "reload", 1, true) ~= nil
end

mod.third_person_animation_filters[TEMPLATE_NAME] = function (event)
	return string.find(event, "reload", 1, true) ~= nil
end

-- The blast, on every machine, for the first wave (the others are only damage)
mod.skin_explosion_callbacks[mod.redeemer.wave_names[1]] = function (world, position)
	skin_api.play_sound_at("ut_redeemer_explosion_3d", position)
end
