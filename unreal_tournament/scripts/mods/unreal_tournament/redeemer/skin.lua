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

local UNIT = utils.UT_UNIT

local skin_api

local random_between = utils.random_between

-- The missiles in flight, on every machine
local missiles = {}

-- The way the last missile flew, for where the blast is
local last_direction = Vector3Box(Vector3.forward())

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

			last_direction:store(direction)

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

-- The blast (RedeemerExplosion and IonCore), on every machine, for the first wave (the others are only damage). It is UT's emitters, each
-- with its numbers: the particles' sizes and colours follow the keys of their SizeScale and ColorScale over their lives, and the puffs
-- move by their start velocity times the keys of their VelocityScale. Sizes and places are in UT units.

-- The value of keys { { time, value }, ... } at a time, in a line between the keys. A value is a number or a list of numbers.
local function keyed(keys, time)
	local before, after = keys[1], keys[#keys]

	for index = 1, #keys - 1 do
		if time >= keys[index][1] and time <= keys[index + 1][1] then
			before, after = keys[index], keys[index + 1]

			break
		end
	end

	local span = after[1] - before[1]
	local share = span > 0 and math.clamp((time - before[1]) / span, 0, 1) or 0

	if type(before[2]) == "number" then
		return before[2] + (after[2] - before[2]) * share
	end

	local value = {}

	for index = 1, #before[2] do
		value[index] = before[2][index] + (after[2][index] - before[2][index]) * share
	end

	return value
end

local function color255(r, g, b)
	return { r / 255, g / 255, b / 255 }
end

local BLACK = { 0, 0, 0 }

-- The fade of an emitter's particle: in over fade_in seconds (FadeInEndTime), out from fade_out (FadeOutStartTime)
local function fade(age, life, fade_in, fade_out)
	local value = 1

	if fade_in and age < fade_in then
		value = age / fade_in
	end

	if fade_out and age > fade_out then
		value = value * math.max(0, (life - age) / (life - fade_out))
	end

	return value
end

-- A point on a sphere's surface (StartLocationShape PTLS_Sphere, or MeshSpawning on the sphere mesh), as an offset in UT units
local function on_sphere(radius, scale_z)
	local z = math.random() * 2 - 1
	local angle = math.random() * 2 * math.pi
	local across = math.sqrt(1 - z * z)

	return { across * math.cos(angle) * radius, across * math.sin(angle) * radius, z * radius * (scale_z or 1) }
end

-- The puffs of fire and smoke (SpriteEmitter0 to 3). Each starts on a sphere about the center, with a velocity of up to 1 unit a second
-- up or down and radial (towards the center or away from it), which VelocityScale multiplies: nothing for half their life, then thousands
-- of units a second, so they rush in or out while they grow from 10 units to hundreds.
local PUFFS = {
	{ count = 40, delay = 0, radius = 64, scale_z = 2, offset_z = -64, radial = { -1, -1 }, texture = "smoke_puff2", velocity = { 3000, 3000, 1000 }, revolution = 0.2,
		colors = { { 0, BLACK }, { 0.33, BLACK }, { 0.66, color255(255, 51, 15) }, { 1, BLACK } }, sizes = { { 0, 10 }, { 0.5, 10 }, { 0.8, 160 }, { 1, 250 } } },
	{ count = 60, delay = 0.05, radius = { 64, 128 }, radial = { 1, 1 }, texture = "smoke_puff2", velocity = { -3000, -3000, -1000 }, revolution = 0.2,
		colors = { { 0, BLACK }, { 0.33, BLACK }, { 0.66, color255(255, 128, 0) }, { 1, BLACK } }, sizes = { { 0, 10 }, { 0.5, 10 }, { 0.8, 160 }, { 1, 250 } } },
	{ count = 150, delay = 0.1, radius = 128, radial = { -1, -0.8 }, texture = "smoke_puff", blended = true, velocity = { 3000, 3000, 1000 }, velocity_end = { 300, 300, 100 },
		revolution = 0.1, revolution_start = 10, colors = { { 0, color255(60, 60, 60) }, { 1, color255(80, 80, 80) } },
		alphas = { { 0, 0 }, { 0.33, 100 / 255 }, { 0.66, 1 }, { 1, 0 } }, sizes = { { 0, 10 }, { 0.5, 10 }, { 0.8, 160 }, { 1, 500 } } },
	{ count = 50, delay = 0.05, radius = { 64, 128 }, radial = { -1, -1 }, texture = "smoke_puff2", velocity = { 2000, 2000, 500 }, revolution = 0.2,
		colors = { { 0, BLACK }, { 0.33, BLACK }, { 0.66, color255(255, 51, 15) }, { 1, BLACK } }, sizes = { { 0, 10 }, { 0.5, 10 }, { 0.8, 160 }, { 1, 250 } } },
}
local PUFF_LIFE = 2
local PUFF_FADE_IN = 0.1

local function puffs(center)
	for _, emitter in ipairs(PUFFS) do
		for _ = 1, emitter.count do
			local radius = type(emitter.radius) == "table" and random_between(emitter.radius) or emitter.radius
			local start = on_sphere(radius, emitter.scale_z)
			local distance = math.max(math.sqrt(start[1] ^ 2 + start[2] ^ 2 + start[3] ^ 2), 0.001)
			local radial = random_between(emitter.radial)
			local up = math.random() * 2 - 1
			-- (the start velocity: radial, plus up or down)
			local base = { start[1] / distance * radial, start[2] / distance * radial, start[3] / distance * radial + up }
			local place = { start[1], start[2], start[3] + (emitter.offset_z or 0) }
			local revolution = emitter.revolution * (math.random() * 2 - 1)
			local born = Managers.time:time("game") + emitter.delay
			local last = born
			local center_box = Vector3Box(center)
			local velocity_keys = { { 0, { 0, 0, 0 } }, { 0.5, { 0, 0, 0 } }, { 0.7, emitter.velocity }, { 1, emitter.velocity_end or { 0, 0, 0 } } }

			particles.sprite({
				additive = emitter.blended and 0 or 1,
				brightness = function (fraction)
					local value = fade(fraction * PUFF_LIFE, PUFF_LIFE, PUFF_FADE_IN)

					return emitter.alphas and value * keyed(emitter.alphas, fraction) or value
				end,
				color_by = function (fraction)
					return keyed(emitter.colors, fraction)
				end,
				delay = emitter.delay,
				follow = function ()
					local now = Managers.time:time("game")
					local dt = math.max(0, now - math.max(last, born))
					local fraction = math.clamp((now - born) / PUFF_LIFE, 0, 1)
					local scale = keyed(velocity_keys, fraction)

					last = now

					for axis = 1, 3 do
						place[axis] = place[axis] + base[axis] * scale[axis] * dt
					end

					-- (UseRevolution: it turns about the center's up axis)
					local turn = revolution * (emitter.revolution_start and emitter.revolution_start * (1 - fraction) or 1) * 2 * math.pi * dt
					local x, y = place[1], place[2]

					place[1] = x * math.cos(turn) - y * math.sin(turn)
					place[2] = x * math.sin(turn) + y * math.cos(turn)

					return center_box:unbox() + Vector3(place[1], place[2], place[3]) * UNIT
				end,
				life = PUFF_LIFE,
				size_by = function (fraction)
					return keyed(emitter.sizes, fraction) * UNIT
				end,
				spin = 0,
				texture = emitter.texture,
			})
		end
	end
end

-- The flares: BurnFlare1 at once (SpriteEmitter5), SoftFlare after 0.8 s (SpriteEmitter4), and IonCore's shock_core for its 1 s
local function flares(center)
	for _ = 1, 2 do
		particles.sprite({
			brightness = function (fraction)
				return fade(fraction, 1, 0.1, 0.9)
			end,
			color_by = function (fraction)
				return keyed({ { 0, color255(255, 172, 111) }, { 1, color255(234, 100, 55) } }, fraction)
			end,
			life = 1,
			position = center,
			size_by = function (fraction)
				return 100 * keyed({ { 0, 1 }, { 0.7, 15 }, { 1, 1 } }, fraction) * UNIT
			end,
			texture = "burn_flare",
		})
		particles.sprite({
			brightness = function ()
				return 1
			end,
			color_by = function (fraction)
				return keyed({ { 0, color255(158, 30, 16) }, { 0.6, color255(255, 174, 64) }, { 0.8, color255(187, 121, 23) }, { 1, BLACK } }, fraction)
			end,
			delay = 0.8,
			life = 1.25,
			position = center,
			size_by = function (fraction)
				return 200 * keyed({ { 0, 0.2 }, { 0.8, 10 }, { 1, 1 } }, fraction) * UNIT
			end,
			texture = "soft_flare",
		})
	end

	particles.sprite({
		brightness = function ()
			return 1
		end,
		color = { 1, 1, 1 },
		life = 1,
		position = center,
		size = 300 * UNIT,
		texture = "shock_core",
	})
end

-- The streaks (SpriteEmitter6): 10 over the first 0.1 s, on a sphere of 256 units, flying out at 200 units a second, 80 long and 40
-- wide along the way they fly, yellow to red
local function streaks(center)
	for index = 1, 10 do
		local start = on_sphere(256)
		local direction = Vector3Box(Vector3.normalize(Vector3(start[1], start[2], start[3])))
		local born = Managers.time:time("game") + (index - 1) / 100
		local center_box = Vector3Box(center)

		particles.beam({
			brightness = function (fraction)
				return fade(fraction * 0.8, 0.8, 0.2, 0.6)
			end,
			color_by = function (fraction)
				return keyed({ { 0, color255(255, 255, 0) }, { 1, color255(253, 32, 0) } }, fraction)
			end,
			delay = (index - 1) / 100,
			life = 0.8,
			size = 40 * UNIT,
			texture = "white_streak",
			track = function ()
				local age = math.max(0, Managers.time:time("game") - born)
				local middle = center_box:unbox() + direction:unbox() * ((256 + 200 * age) * UNIT)

				return middle - direction:unbox() * (40 * UNIT), middle + direction:unbox() * (40 * UNIT)
			end,
		})
	end
end

-- The ring and the spheres (MeshEmitter0 to 2), with FlameGradient. The meshes are made at the size of UT's (0.02 m a unit), so their
-- scale is UT's.
local function shells(center)
	local ring_turn = Quaternion.multiply(Quaternion.axis_angle(Vector3(0, 0, 1), math.random() * 2 * math.pi), Quaternion.axis_angle(Vector3(1, 0, 0), math.random() * 2 * math.pi))

	-- The ring: after 1 s, for 1 s, from 0.1 to 12.5 times its size, turned at random, orange to yellow to nothing
	particles.mesh({
		brightness = function (fraction)
			return fade(fraction, 1, 0.1)
		end,
		color = { 1, 1, 1 },
		color_by = function (fraction)
			return keyed({ { 0, BLACK }, { 0.3, color255(197, 137, 56) }, { 0.6, color255(186, 177, 7) }, { 1, BLACK } }, fraction)
		end,
		delay = 1,
		life = 1,
		material = "units/ut/fx/fx_flame_gradient",
		position = center,
		rotation = ring_turn,
		scale = function (fraction)
			return 0.5 * keyed({ { 0, 0.2 }, { 1, 25 } }, fraction)
		end,
		unit = "units/ut/fx/explosion_ring",
	})

	-- The bright sphere: after 1.2 s, for 1 s, from 0.2 to 25 times its size (0.8 of it up and down), 0.7 of white, fading from 0.75 s
	particles.mesh({
		brightness = function (fraction)
			return 0.7 * fade(fraction, 1, nil, 0.75)
		end,
		color = { 1, 1, 1 },
		delay = 1.2,
		life = 1,
		material = "units/ut/fx/fx_flame_gradient",
		position = center,
		rotation = Quaternion.identity(),
		scale = function (fraction)
			local size = keyed({ { 0, 0.2 }, { 1, 25 } }, fraction)

			return Vector3(size, size, size * 0.8)
		end,
		unit = "units/ut/fx/explosion_sphere",
	})

	-- The blended sphere: after 1.5 s, for 0.75 s, from 0.16 to 14.4 times its size, turning, white that fades out (PTDS_AlphaBlend)
	particles.mesh({
		additive = 0,
		brightness = function (fraction)
			return fade(fraction * 0.75, 0.75, 0.1) * keyed({ { 0, 0 }, { 0.3, 1 }, { 0.6, 0.5 }, { 1, 0 } }, fraction)
		end,
		color = { 1, 1, 1 },
		delay = 1.5,
		life = 0.75,
		material = "units/ut/fx/fx_flame_gradient",
		position = center,
		rotation = Quaternion.identity(),
		scale = function (fraction)
			return 0.8 * keyed({ { 0, 0.2 }, { 1, 18 } }, fraction)
		end,
		spin = random_between({ 0, 1 }),
		spin_axis = Vector3.normalize(Vector3(math.random(), math.random(), math.random())),
		unit = "units/ut/fx/explosion_sphere",
	})
end

mod.skin_explosion_callbacks[mod.redeemer.wave_names[1]] = function (world, position)
	-- RedeemerProjectile.BlowUp: the blast is 100 units back along the missile's flight
	local center = position - last_direction:unbox() * (100 * UNIT)

	skin_api.play_sound_at("ut_redeemer_explosion_3d", position)
	puffs(center)
	flares(center)
	streaks(center)
	shells(center)
end
