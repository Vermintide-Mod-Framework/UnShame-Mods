local mod = get_mod("unreal_tournament")

-- Minigun skin: how UT2004's Minigun looks and sounds.
--
-- weapon_skin.lua does the model, its placement and animations, the bob and the third person. This file does what is the Minigun's own:
-- the barrels that turn (Minigun.UpdateRoll), the muzzle flash, the shells, the tracers, and the sounds of the winding and the fire.
-- The gameplay is in minigun.lua. This file only draws it, and is told what happens through the hook tables in hooks.lua.
--
-- The assets were made with tools/asset_conversion (convert_weapon.py minigun, convert_static.py minigun_pickup, make_weapon_fx.py and
-- make_bank.py minigun).

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local animations = mod:dofile("scripts/mods/unreal_tournament/minigun/skin_animations")
local particles = mod.skin_particles

local CONFIG = {
	meters_per_uu = 0.02, -- meters in one Unreal unit of the world (a player is 88 units high)
	-- The first person flash (MinigunMuzFlash1st): a few star-shaped bursts at the muzzle for every round, turned at random, each lasting
	-- 0.1 to 0.15 seconds and growing as it goes
	flash_count = 3,
	flash_size = 110, -- UT units
	flash_growth = 260, -- UT units a second
	flash_life = 0.12,
	flash_intensity = 1.2,
	-- The third person flash (NewMinigunMFlash): four flames in a row along the barrel, each smaller and further out
	flame_offsets = {8, 16, 24, 32}, -- UT units from the muzzle
	flame_sizes = {17, 12, 7, 4}, -- UT units
	flame_life = 0.1,
	-- NewTracer: a streak of 40 by 10 units that flies at 10000 units a second to where the round hit, less the pullback, and is
	-- there only if that is farther than the minimum. A tracer is made every tracer_interval seconds, for the primary and the alt fire.
	tracer_speed = 10000, -- UT units a second
	tracer_length = 40,
	tracer_width = 10,
	tracer_pullback = 50,
	tracer_min_distance = 0,
	tracer_interval = 0.12,
	tracer_alt_interval = 0.18,
	tracer_intensity = 1.6,
	-- ShellSpewer: the shells fly out of the gun's ejector and fall. Mass 2: they fall like the game's own, at gravity.
	shell_speed = {200, 250}, -- UT units a second
	shell_life = {0.5, 1},
	shell_size = 0.14, -- meters, as large as UT's shells look in the player's view
	shell_gravity = 9.8, -- meters per second squared
	-- The winding sound plays while the barrels turn at less than full speed. The fire sound loops, so it is started again when its
	-- length is over, and stopped when the shots stop.
	fire_loop_seconds = 0.98,
	alt_loop_seconds = 1.1,
	wind_loop_seconds = 0.72,
	stop_after = 0.18, -- seconds without a round after which the fire sound is stopped
	-- Minigun.GearRatio and GearOffset: the gear turns this many times as far as the barrels, and the other way
	gear_ratio = -2.37,
	-- The barrels and the gear turn about axes along the mesh's own right (the mesh lies sideways, and the pivot's yaw turns it to the
	-- front). Each axis goes through this point of the mesh (forward, up, in the mesh's units).
	barrel_pivot = { 0, 8.8 },
	gear_pivot = { 17.85, 10.87 },
	inspect_pose_speed = 5,
	inspect_sway = 5,
	inspect_sway_speed = 1.8,
}

local UNIT = CONFIG.meters_per_uu

local minigun = mod.minigun

local TEMPLATES = {
	{
		id = "minigun",
		setting_id = "minigun",
	},
	{
		id = "minigun_wh",
		setting_id = "minigun_wh",
	},
}

local TEMPLATE_NAMES = {}
local skin_apis = {}

for _, variant in ipairs(TEMPLATES) do
	TEMPLATE_NAMES[mod.items.weapons[variant.setting_id].template] = true
end

-- The indexes, in the animations' list of bones, of the barrels, the gear and the muzzle
local BARREL_BONE, GEAR_BONE

for index, name in ipairs(animations.bones) do
	if name == "b_bone_barrels" then
		BARREL_BONE = index
	elseif name == "b_bone_gear" then
		GEAR_BONE = index
	end
end

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

-- Each template has a skin of its own, and a character holds the weapon of one of them
local function first_person_api()
	for _, api in ipairs(skin_apis) do
		if api.state() then
			return api
		end
	end
end

local function third_person_muzzle(character)
	for _, api in ipairs(skin_apis) do
		local muzzle = api.third_person.muzzle_position(character)

		if muzzle then
			return muzzle, api
		end
	end
end

-- Turns the pose of a bone about an axis along the mesh's own right through a point, by an angle in radians
local function turn_bone(pose, bone, angle, pivot)
	local o = (bone - 1) * 7
	local sin_half, cos_half = math.sin(angle / 2), math.cos(angle / 2)
	local x, y, z, w = pose[o + 1], pose[o + 2], pose[o + 3], pose[o + 4]

	pose[o + 1] = cos_half * x + sin_half * w
	pose[o + 2] = cos_half * y - sin_half * z
	pose[o + 3] = cos_half * z + sin_half * y
	pose[o + 4] = cos_half * w - sin_half * x

	local cos_angle, sin_angle = math.cos(angle), math.sin(angle)
	local py, pz = pose[o + 6] - pivot[1], pose[o + 7] - pivot[2]

	pose[o + 6] = py * cos_angle - pz * sin_angle + pivot[1]
	pose[o + 7] = py * sin_angle + pz * cos_angle + pivot[2]
end

-- The first person flash of a round, at the muzzle of the model in the player's own view
local function first_person_flash(follow, scale)
	for _ = 1, CONFIG.flash_count do
		particles.sprite({
			attenuation = 0,
			color = {
				1,
				1,
				1,
			},
			follow = follow,
			growth = CONFIG.flash_growth * scale,
			intensity = CONFIG.flash_intensity,
			life = CONFIG.flash_life,
			size = CONFIG.flash_size * scale,
			spin = (math.random() * 2 - 1) * 0.3,
			texture = "minigun_burst_" .. math.random(0, 3),
		})
	end
end

-- The flash in the hand of a character: flames in a row along the way the round goes
local function third_person_flash(muzzle, direction, scale)
	for i, offset in ipairs(CONFIG.flame_offsets) do
		particles.sprite({
			attenuation = 0,
			color = {
				1,
				1,
				1,
			},
			life = CONFIG.flame_life,
			position = muzzle + direction * (offset * scale),
			size = CONFIG.flame_sizes[i] * scale,
			spin = (math.random() * 2 - 1) * 0.3,
			texture = "minigun_flame_" .. math.random(0, 15),
		})
	end
end

-- A tracer: a streak that flies from the muzzle to where the round hit
local last_tracer_time = {}
local last_remote_sound = {}

local function tracer(owner_unit, start, end_position, interval)
	local now = Managers.time:time("game")

	if last_tracer_time[owner_unit] and now - last_tracer_time[owner_unit] < interval then
		return
	end

	last_tracer_time[owner_unit] = now

	local along = end_position - start
	local distance = Vector3.length(along)
	local direction = along * (1 / math.max(distance, 0.001))
	local reach = distance - CONFIG.tracer_pullback * UNIT

	if reach <= CONFIG.tracer_min_distance * UNIT then
		return
	end

	local speed = CONFIG.tracer_speed * UNIT
	local length = CONFIG.tracer_length * UNIT
	local origin = Vector3Box(start)
	local direction_box = Vector3Box(direction)
	local life = reach / speed

	particles.beam({
		attenuation = 0.9,
		color = {
			1,
			0.8,
			0.5,
		},
		intensity = CONFIG.tracer_intensity,
		life = life,
		size = CONFIG.tracer_width * UNIT,
		texture = "tracer_shot",
		track = function ()
			-- The streak's head has gone this far along the path
			local head = math.min(reach, speed * (Managers.time:time("game") - now))
			local tail = math.max(0, head - length)

			local unboxed = direction_box:unbox()

			return origin:unbox() + unboxed * tail, origin:unbox() + unboxed * head
		end,
	})
end

-- A shell leaves the ejector and falls. It is a sprite that is moved every frame.
local function shell(position, right, up)
	local velocity = Vector3Box(right * (random_between(CONFIG.shell_speed) * UNIT) + up * (random_between(CONFIG.shell_speed) * 0.6 * UNIT) + random_direction() * (30 * UNIT))
	local place = Vector3Box(position)
	local last = Managers.time:time("game")

	particles.sprite({
		attenuation = 0.9,
		color = {
			1,
			1,
			1,
		},
		follow = function ()
			local now = Managers.time:time("game")
			local dt = now - last
			local v = velocity:unbox() + Vector3(0, 0, -CONFIG.shell_gravity * dt)

			last = now
			velocity:store(v)
			place:store(place:unbox() + v * dt)

			return place:unbox()
		end,
		life = random_between(CONFIG.shell_life),
		size = CONFIG.shell_size,
		spin = (math.random() * 2 - 1) * 2,
		texture = "shell_casing",
	})
end

-- The sound of the fire, the winding and the end of it, which loop or are started again
local sound = {
	fire_id = nil,
	fire_mode = nil,
	fire_started = -math.huge,
	wind_started = -math.huge,
	last_round = -math.huge,
}

local function stop_fire_sound(api)
	api.stop_sound(sound.fire_id)

	sound.fire_id = nil
	sound.fire_mode = nil
end

local function update_sounds(api, dt)
	local now = Managers.time:time("game")
	local firing = now - sound.last_round < CONFIG.stop_after

	if sound.fire_id and not firing then
		stop_fire_sound(api)
	end

	-- The winding plays while the barrels turn and no round has left yet (the wind up), and when they slow down
	if minigun.spin > 0 and not firing and now - sound.wind_started >= CONFIG.wind_loop_seconds then
		sound.wind_started = now

		api.play_sound("ut_minigun_wind")
	end
end

local function round_sound(api, mode)
	local now = Managers.time:time("game")

	sound.last_round = now

	local seconds = mode == "alt" and CONFIG.alt_loop_seconds or CONFIG.fire_loop_seconds

	if sound.fire_mode ~= mode or now - sound.fire_started >= seconds then
		if sound.fire_mode ~= mode then
			stop_fire_sound(api)
		end

		sound.fire_started = now
		sound.fire_mode = mode
		sound.fire_id = api.play_sound(mode == "alt" and "ut_minigun_alt_fire" or "ut_minigun_fire")
	end
end

-- A round by any player, on every machine
mod.minigun_shot_callbacks.minigun_skin = function (owner_unit, mode, end_position, hit_normal)
	if not skin_apis[1] then
		return
	end

	local interval = mode == "alt" and CONFIG.tracer_alt_interval or CONFIG.tracer_interval

	if utils.is_local_player_unit(owner_unit) then
		local api = first_person_api()

		if api and not api.third_person.shows_weapon(owner_unit) then
			round_sound(api, mode)
			first_person_flash(function ()
				return api.state() and api.muzzle_position() or nil
			end, api.state() and api.state().unit_scale or UNIT)

			local muzzle = api.muzzle_position()

			if muzzle then
				tracer(owner_unit, muzzle, end_position, interval)
			end

			-- The shells fly out of the ejector to the right of the gun
			local ejector = api.muzzle_position("b_bone_caseejector")
			local _, camera_rotation = utils.camera_pose()

			if ejector and camera_rotation then
				shell(ejector, Quaternion.right(camera_rotation), Quaternion.up(camera_rotation))
			end

			return
		end
	end

	local muzzle, api = third_person_muzzle(owner_unit)

	if not muzzle then
		return
	end

	local direction = Vector3.normalize(end_position - muzzle)

	third_person_flash(muzzle, direction, api.third_person.meters_per_unit_of(owner_unit))
	tracer(owner_unit, muzzle, end_position, interval)

	if not utils.is_local_player_unit(owner_unit) then
		-- The others hear the gun from where it is, once for each time its sound would start again
		local now = Managers.time:time("game")
		local last = last_remote_sound[owner_unit] or -math.huge

		if now - last >= CONFIG.fire_loop_seconds then
			last_remote_sound[owner_unit] = now

			api.play_sound_at(mode == "alt" and "ut_minigun_alt_fire_3d" or "ut_minigun_fire_3d", muzzle)
		end
	end
end

local function new_skin(variant)
	local definition = mod.items.weapons[variant.setting_id]
	local api

	api = mod.weapon_skin.new({
		id = variant.id,
		name = "minigun",
		template = definition.template,
		unit_name = "units/ut/minigun/minigun",
		animations = animations,
		muzzle_node = "b_bone_flash",
		-- model_meters_per_unit is the meters per UT unit at which the model was converted (tools/asset_conversion/convert_weapon.py).
		-- meters_per_unit is the distance scale: the meters of forward in the view that one UT unit of the model takes up.
		model_meters_per_unit = 0.0125,
		meters_per_unit = 0.01,
		-- Minigun.uc
		display_fov = 60,
		draw_scale = 0.4,
		offset_forward = 2,
		offset_right = -1,
		offset_up = 0,
		pivot_yaw = 500 / 65536 * 360,
		bob_damping = 2.25,
		-- The inspect pose turns the gun to show its side, like the other weapons. These numbers are a guess.
		inspect_pose_right = -2,
		inspect_pose_forward = 4,
		inspect_pose_up = 0,
		inspect_pose_roll = 10,
		inspect_pose_pitch = 4,
		inspect_pose_yaw = 55,
		inspect_turn_start = 0.35,
		inspect_pivot_right = 0,
		inspect_pivot_forward = 30,
		inspect_pivot_up = 0,
		-- WeaponStaticMesh.MinigunPickup (DrawScale 0.5). Its barrels run along the mesh's own +Y, and the grip is under its middle.
		third_person = {
			id = variant.id,
			template = definition.template,
			unit_name = "units/ut/minigun/pickup",
			-- The game links the repeating gun and the crossbow to the left hand's node
			hand_node = "j_leftweaponattach",
			meters_per_unit = 0.01,
			scale = 0.5,
			grip_right = 0,
			grip_forward = -10,
			grip_up = -10,
			yaw = -60,
			pitch = 0,
			roll = 0,
			follow_game_unit = 1,
			follow_calibrate_seconds = 1,
			muzzle_right = 0,
			muzzle_forward = 85,
			muzzle_up = 0,
			menu_yaw = 180,
		},
		on_create = function ()
			api.play_sound("ut_minigun_select")
		end,
		on_update = function (skin, dt)
			skin.inspect_pose = (skin.inspect_pose or 0) + ((skin.inspecting and 1 or 0) - (skin.inspect_pose or 0)) * math.min(1, CONFIG.inspect_pose_speed * dt)
			skin.inspect_time = skin.inspecting and (skin.inspect_time or 0) + dt or 0
			skin.extra_yaw = skin.inspect_pose * CONFIG.inspect_sway * math.sin(skin.inspect_time * CONFIG.inspect_sway_speed)

			-- The barrels turn by how fast they are going (Minigun.UpdateRoll)
			skin.barrel_angle = ((skin.barrel_angle or 0) + minigun.turns_per_second * 360 * dt) % 360

			update_sounds(api, dt)
		end,
		on_pose = function (skin, pose)
			local angle = math.rad(skin.barrel_angle or 0)

			if angle == 0 then
				return
			end

			turn_bone(pose, BARREL_BONE, angle, CONFIG.barrel_pivot)
			turn_bone(pose, GEAR_BONE, angle * CONFIG.gear_ratio, CONFIG.gear_pivot)
		end,
		on_level_exit = function ()
			table.clear(last_tracer_time)
			table.clear(last_remote_sound)
			sound.fire_id = nil
		end,
	})

	skin_apis[#skin_apis + 1] = api

	return api
end

for _, variant in ipairs(TEMPLATES) do
	new_skin(variant)
end

-- Inspecting is the game's own action, held with the key
mod.inspect_callbacks.minigun_skin = function (action, started)
	for _, api in ipairs(skin_apis) do
		local skin = api.state()

		if skin and utils.is_local_player_unit(action.owner_unit) then
			skin.inspecting = started
		end
	end
end

-- The repeating gun's own shot animations and sounds are not played on the player's own first person unit. The skin's model plays UT's.
for template_name in pairs(TEMPLATE_NAMES) do
	mod.first_person_animation_filters[template_name] = function (event)
		return string.find(event, "attack_shoot", 1, true) ~= nil or string.find(event, "reload", 1, true) ~= nil
	end

	-- The reload animation is not played on the characters, because the weapon has no reload.
	mod.third_person_animation_filters[template_name] = function (event)
		return string.find(event, "reload", 1, true) ~= nil
	end
end
