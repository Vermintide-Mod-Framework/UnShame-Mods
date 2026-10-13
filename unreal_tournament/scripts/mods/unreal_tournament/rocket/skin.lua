local mod = get_mod("unreal_tournament")

-- Rocket Launcher skin: the Rocket Launcher always looks and sounds like UT2004's, in the player's own first person view and in the hand
-- of every character. The model (Weapons.RocketLauncher_1st, skeletal: the barrel turns as a rocket is loaded), its placement and
-- animations, the bob and the third person are weapon_skin.lua's; this file is what is the Rocket Launcher's: the flash, the rocket as it
-- flies (its mesh turning, its corona and its smoke), the explosion, and the sounds. The gameplay is rocket_launcher.lua's, this only
-- draws it differently, and is told what happens through the hook tables of hooks.lua.
--
-- The game's own unit of the rocket (the crossbow's bolt) is what flies (it is the gameplay), its effects are not started and what UT has is
-- drawn at it. The shot sound of the crossbow is made by its animation, which is not played on the player's own first person unit.
--
-- The assets were made with unreal_tournament/tools/asset_conversion.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local animations = mod:dofile("scripts/mods/unreal_tournament/rocket/skin_animations")
local particles = mod.skin_particles

local TEMPLATE_NAME = mod.items.weapons.rocket_launcher.template
local SETTING_ID = "rocket_launcher"

local CONFIG = {
	meters_per_uu = 0.02, -- the Unreal unit of the world, in meters (a player is 88 units high)
	-- RocketMuzFlash1st: a flash of 0.15 s (meshes; here a sprite)
	muzzle_size = 70,
	muzzle_growth = 80,
	muzzle_life = 0.15,
	-- RocketProj: the mesh turns (RotationRate roll 50000 of 65536 to the turn, a second)
	rocket_turns_per_second = 50000 / 65536,
	-- RocketCorona (a flare along the flight: 1.2 times the 64 units of the texture, 0.7 by 0.35 of that, pulsing between 0.9 and 1.5)
	corona_size = 70,
	corona_pulse_seconds = 0.2,
	-- RocketTrailSmoke (wisps, 90 a second, 1.25 s, 15 to 20 units, growing 13 a second, rising a little)
	smoke_interval = 0.025,
	smoke_life = 1.25,
	smoke_size = {
		15,
		20,
	},
	smoke_growth = 13,
	smoke_rise = 0.3, -- m/s
	smoke_color = {
		0.9,
		0.85,
		0.85,
	},
	rocket_sound_seconds = 1.87, -- how long the loop of the rocket (RocketLauncherProjectile) is
	-- The explosion (NewExplosionA: fire, 3 sprites of 50 to 70 units, 0.4 to 0.6 s, and smoke; ExplosionCrap: debris)
	explosion_flash_size = 150,
	explosion_flash_growth = 500,
	explosion_flash_life = 0.25,
	explosion_fire_count = 3,
	explosion_fire_size = {
		90,
		140,
	},
	explosion_fire_growth = 120,
	explosion_fire_life = {
		0.4,
		0.6,
	},
	explosion_fire_spread = 24, -- units
	explosion_smoke_count = 5,
	explosion_smoke_size = {
		70,
		110,
	},
	explosion_smoke_life = {
		0.9,
		1.6,
	},
	explosion_smoke_spread = 40,
	explosion_smoke_rise = 0.5,
	-- Another shot of another player: more than this far apart in time is another shot
	shot_gap = 0.25,
}

local UNIT = CONFIG.meters_per_uu

local skin_api

-- What flies: { unit = the mesh, game_unit = the projectile's, projectile = its extension, ... }
local visuals = {}

local function random_between(range)
	return range[1] + (range[2] - range[1]) * math.random()
end

local function random_direction()
	local direction = Vector3(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1)

	if Vector3.length(direction) < 0.001 then
		return Vector3.up()
	end

	return Vector3.normalize(direction)
end

local function destroy_visual(visual)
	if Unit.alive(visual.unit) then
		World.destroy_unit(visual.world, visual.unit)
	end
end

-- All of them go with the level, and with the mod (a unit of the mod's package that is alive when the package is unloaded crashes the game)
local function clear_visuals()
	for i = #visuals, 1, -1 do
		destroy_visual(visuals[i])
	end

	table.clear(visuals)
end

local function update_visuals(dt)
	for i = #visuals, 1, -1 do
		local visual = visuals[i]
		local game_unit = visual.game_unit

		if not Unit.alive(game_unit) or visual.projectile._stop_impacts or not Unit.alive(visual.unit) then
			destroy_visual(visual)
			table.remove(visuals, i)
		else
			local position = Unit.world_position(game_unit, 0)
			local previous = visual.previous:unbox()
			local moved = position - previous

			visual.previous:store(position)
			visual.time = visual.time + dt
			visual.smoke_time = visual.smoke_time - dt
			visual.sound_time = visual.sound_time - dt

			if Vector3.length(moved) > 0.0001 then
				visual.direction:store(Vector3.normalize(moved))
			end

			-- (turning about its length as it flies)
			local direction = visual.direction:unbox()
			local turn = Quaternion.axis_angle(Vector3(0, 1, 0), visual.time * CONFIG.rocket_turns_per_second * 2 * math.pi)

			Unit.set_local_position(visual.unit, 0, position)
			Unit.set_local_rotation(visual.unit, 0, Quaternion.multiply(Quaternion.look(direction, Vector3.up()), turn))

			while visual.smoke_time <= 0 do
				visual.smoke_time = visual.smoke_time + CONFIG.smoke_interval

				particles.sprite({
					additive = 0,
					color = CONFIG.smoke_color,
					growth = CONFIG.smoke_growth * UNIT,
					intensity = 0.6,
					life = CONFIG.smoke_life,
					position = position,
					size = random_between(CONFIG.smoke_size) * UNIT,
					spin = (math.random() * 2 - 1) * 0.3,
					texture = "smoke",
					velocity = Vector3(0, 0, CONFIG.smoke_rise),
				})
			end

			if visual.sound_time <= 0 then
				visual.sound_time = CONFIG.rocket_sound_seconds

				skin_api.play_sound_at("ut_rocket_projectile_3d", position)
			end
		end
	end
end

-- The mesh of a rocket, drawn at the game's unit (the unit itself is not shown), and its corona
local function add_visual(projectile)
	local world = Managers.world:world("level_world")
	local game_unit = projectile._projectile_unit
	local position = Unit.world_position(game_unit, 0)
	local unit = World.spawn_unit(world, "units/ut/rocket/projectile", position)

	Unit.set_unit_visibility(game_unit, false)

	local visual = {
		direction = Vector3Box(Vector3.forward()),
		game_unit = game_unit,
		previous = Vector3Box(position),
		projectile = projectile,
		smoke_time = 0,
		sound_time = 0,
		time = 0,
		unit = unit,
		world = world,
	}

	visuals[#visuals + 1] = visual

	particles.sprite({
		color = {
			1,
			0.85,
			0.6,
		},
		fade_in = 0,
		follow = function ()
			if Unit.alive(game_unit) and not projectile._stop_impacts then
				return Unit.world_position(game_unit, 0)
			end
		end,
		life = 8,
		size = CONFIG.corona_size * UNIT,
		texture = "rocket_flare",
	})

	return visual
end

-- A flash at the muzzle (where the character holds the mesh, or the model of the player's own view)
local function muzzle_flash(follow, scale)
	particles.sprite({
		color = {
			1,
			0.9,
			0.7,
		},
		follow = follow,
		growth = CONFIG.muzzle_growth * scale,
		life = CONFIG.muzzle_life,
		size = CONFIG.muzzle_size * scale,
		spin = (math.random() * 2 - 1) * 0.2,
		texture = "rocket_muzzle",
	})
end

-- A shot that another player's machine sees: the flash and the sound from the end of the barrel of the mesh in their hand, once for the
-- rockets of a shot that come together
local last_remote_shot = {}

local function remote_shot(owner_unit)
	local now = Managers.time:time("game")

	if last_remote_shot[owner_unit] and now - last_remote_shot[owner_unit] < CONFIG.shot_gap then
		return
	end

	last_remote_shot[owner_unit] = now

	local muzzle = skin_api.third_person.muzzle_position(owner_unit)

	muzzle_flash(function ()
		return skin_api.third_person.muzzle_position(owner_unit)
	end, skin_api.third_person.meters_per_unit)

	if muzzle then
		skin_api.play_sound_at("ut_rocket_fire_3d", muzzle)
	end
end

skin_api = mod.weapon_skin.new({
	id = SETTING_ID,
	-- There is no setting for this: the skin is always on.
	always = true,
	name = "rocket",
	template = TEMPLATE_NAME,
	unit_name = "units/ut/rocket/rocket_launcher",
	animations = animations,
	muzzle_node = "b_bone_flash",
	model_meters_per_unit = 0.0125,
	meters_per_unit = 0.01,
	-- RocketLauncher.uc: the model is turned a little (the pivot's yaw 500 and roll 1000 of 65536 to the turn)
	display_fov = 60,
	draw_scale = 1,
	offset_forward = 0,
	offset_right = 8,
	offset_up = 0,
	pivot_yaw = 500 / 65536 * 360,
	pivot_roll = 1000 / 65536 * 360,
	bob_damping = 1.5,
	-- WeaponStaticMesh.RocketLauncherPickup (DrawScale 0.45): its barrels are along the mesh's own -Y, and the grip is under the back of it
	third_person = {
		id = SETTING_ID,
		always = true,
		template = TEMPLATE_NAME,
		unit_name = "units/ut/rocket/pickup",
		-- (the game links the crossbow, the blunderbuss and the Drakegun to the left hand's node, AttachmentNodeLinking.repeating_crossbow)
		hand_node = "j_leftweaponattach",
		meters_per_unit = 0.009,
		scale = 0.5,
		grip_right = -55,
		grip_forward = 0,
		grip_up = -15,
		yaw = 90,
		pitch = 0,
		roll = 0,
		-- In the world the launcher moves with the game's crossbow, which the game animates with the arms (see the Flak Cannon)
		follow_game_unit = 1,
		follow_calibrate_seconds = 1,
		muzzle_right = 68,
		muzzle_forward = 0,
		muzzle_up = 8,
		menu_yaw = 0,
	},
	on_create = function ()
		skin_api.play_sound("ut_rocket_select")
	end,
	on_give_back = clear_visuals,
	on_update_always = update_visuals,
	on_level_exit = function ()
		clear_visuals()
		table.clear(last_remote_shot)
	end,
})

local third_person = skin_api.third_person

-- A shot of the player: the animation, the flash and the sound
local function shot(action, new_action)
	local skin = skin_api.state()
	local owner_unit = action.owner_unit

	if not skin or not utils.is_local_player_unit(owner_unit) then
		return
	end

	local in_third_person = third_person.shows_weapon(owner_unit)

	skin_api.play(new_action.ut_rocket_salvo and "AltFire" or "Fire")
	skin_api.play_sound(new_action.ut_rocket_salvo and "ut_rocket_alt_fire" or "ut_rocket_fire")
	muzzle_flash(function ()
		if in_third_person then
			return third_person.muzzle_position(owner_unit)
		end

		return skin_api.state() == skin and skin_api.muzzle_position() or nil
	end, in_third_person and third_person.meters_per_unit or skin.unit_scale)
end

mod.crossbow_start_callbacks.rocket_skin = function (action, new_action)
	if new_action.ut_rocket or new_action.ut_rocket_salvo then
		shot(action, new_action)
	end
end

-- Another rocket is loaded: the barrel turns, and the sound
mod.rocket_load_callbacks.rocket_skin = function (owner_unit)
	local skin = skin_api.state()

	if skin and utils.is_local_player_unit(owner_unit) then
		skin_api.play("Load")
		skin_api.play_sound("ut_rocket_load")
	end
end

-- The shot sounds of the crossbow are in its animation: the animations of the shots are not played on the player's own first person unit
-- (the model of the skin plays UT's)
mod.first_person_animation_filters[TEMPLATE_NAME] = function (event)
	return event == "attack_shoot" or event == "attack_shoot_last"
end

-- The flow events of the game's unit of the rocket start its effects as it is made: they are not started
mod.init_flow_event_filters.rocket = function (event_name)
	return event_name == "lua_projectile_init" or event_name == "lua_trail" or event_name == "vfx_critical_strike"
end

-- A rocket (on every machine): the mesh, the corona, the smoke
mod.skin_init_callbacks.rocket = function (projectile)
	local owner_unit = projectile._owner_unit

	add_visual(projectile)

	if not utils.is_local_player_unit(owner_unit) then
		remote_shot(owner_unit)
	end
end

-- The explosion of a rocket, on every machine: the game's own effects of it are not made
mod.skin_explosion_callbacks.ut_rocket_explosion = function (world, position)
	skin_api.play_sound_at("ut_rocket_explosion_3d", position)

	particles.sprite({
		attenuation = 0,
		color = {
			1,
			1,
			1,
		},
		growth = CONFIG.explosion_flash_growth * UNIT,
		life = CONFIG.explosion_flash_life,
		position = position,
		size = CONFIG.explosion_flash_size * UNIT,
		spin = (math.random() * 2 - 1) * 0.12,
		texture = "explosion_flash",
	})

	for _ = 1, CONFIG.explosion_fire_count do
		particles.sprite({
			attenuation = 0.2,
			color = {
				1,
				0.75,
				0.4,
			},
			growth = CONFIG.explosion_fire_growth * UNIT,
			life = random_between(CONFIG.explosion_fire_life),
			position = position + random_direction() * (CONFIG.explosion_fire_spread * UNIT),
			size = random_between(CONFIG.explosion_fire_size) * UNIT,
			spin = (math.random() * 2 - 1) * 0.4,
			texture = "flak_muzzle",
		})
	end

	for _ = 1, CONFIG.explosion_smoke_count do
		particles.sprite({
			additive = 0,
			attenuation = 0.2,
			color = {
				0.45,
				0.4,
				0.38,
			},
			growth = 10 * UNIT,
			intensity = 0.9,
			life = random_between(CONFIG.explosion_smoke_life),
			position = position + random_direction() * (CONFIG.explosion_smoke_spread * UNIT),
			size = random_between(CONFIG.explosion_smoke_size) * UNIT,
			spin = (math.random() * 2 - 1) * 0.5,
			texture = "smoke",
			velocity = Vector3(0, 0, CONFIG.explosion_smoke_rise),
		})
	end
end
