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
	-- The first person flash (MinigunMuzFlash1st): 5 meshes (MinigunMuzFlash1stMesh) at the muzzle for every round (mNumPerFlash),
	-- turned at random about the barrel, each lasting 0.1 to 0.15 seconds. A mesh's scale starts at 0.05 to 0.08 and grows by 3 a second
	-- (mSizeRange, mGrowthRate), times the emitter's DrawScale of 0.9. It brightens until 0.2 of its life and dims after (mAttenKa).
	flash_count = 5,
	flash_scale = {0.05, 0.08},
	flash_growth = 3, -- scale a second
	flash_draw_scale = 0.9,
	flash_life = {0.1, 0.15},
	flash_attenuation = 0.2,
	-- How xEmitter scales a mesh particle by its size is in UT's engine, not its scripts. The numbers above drew the flash twice as
	-- wide as pictures of UT2004 show it, so they are multiplied by this (fitted to those pictures).
	flash_fit = 0.5,
	flash_intensity = 1,
	-- The third person flash (NewMinigunMFlash): four flames in a row along the barrel, each smaller and further out
	flame_offsets = {8, 16, 24, 32}, -- UT units from the muzzle
	flame_sizes = {17, 12, 7, 4}, -- UT units
	flame_life = 0.1,
	-- NewTracer: a sprite along its velocity that flies at 10000 units a second to where the round hit, less the pullback, and is
	-- there only if that is farther than the minimum. It is 10 units wide and 20 long times 0.002 of its speed (ScaleSizeXByVelocity),
	-- grows to that in its first 0.03 s (SizeScale), and keeps its brightness. Its colour is the texture's times (1, 0.8, 0.5).
	-- A tracer is made every tracer_interval seconds, for the primary and the alt fire.
	tracer_speed = 10000, -- UT units a second
	tracer_length = 400,
	tracer_width = 10,
	tracer_grow_time = 0.03,
	tracer_color = { 1, 0.8, 0.5 },
	tracer_pullback = 50,
	tracer_min_distance = 0,
	tracer_interval = 0.12,
	tracer_alt_interval = 0.18,
	-- Minigun.EffectOffset: where the tracers start in the player's view (right, forward, up, UT units from the eye)
	effect_offset = {18, 100, -16},
	tracer_intensity = 1,
	-- ShellSpewer: the shells (the ShellCasing mesh, at a scale of mSizeRange 10 times DrawScale 0.05) fly out of the gun's ejector at
	-- 200 to 250 units a second and fall, for 0.5 to 1 s, turning as they go
	shell_speed = {200, 250}, -- UT units a second
	shell_life = {0.5, 1},
	shell_scale = 0.5,
	shell_gravity = 950, -- UT units a second squared (PhysicsVolume's)
	shell_spin = 12, -- radians a second, at most, each way
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

local UNIT = utils.UT_UNIT

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

-- UT's attenuation: brightens until ka of the life and dims from there
local function attenuation(fraction, ka)
	if fraction < ka then
		return fraction / ka
	end

	return (1 - fraction) / (1 - ka)
end

-- The first person flash of a round, at the muzzle of the model in the player's own view. UT attaches it to the weapon, so it is drawn
-- with the weapon. Here it has the material that draws with the model's field of view (fx_weapon_*), at the muzzle of the model as it
-- is placed for that, so it is among the model's parts and in front of the barrels, not hidden by them as a particle of the world is.
-- world_unit is the meters of a UT unit there. The texture is a sheet of 4 that UT picks from at random (mRandTextures); a mesh here
-- has one of them for its whole life, where UT also steps through them (mTileAnimation).
-- The emitter has room for 5 meshes (mMaxParticles), as many as a round makes, so the meshes of a round take the places of the last
-- round's: those end when the next round's start.
local flash_round = 0

local function first_person_flash(follow, world_unit)
	local _, camera_rotation = utils.camera_pose()

	if not camera_rotation then
		return
	end

	flash_round = flash_round + 1

	local round = flash_round

	-- (the mesh is made at 0.02 m per UT unit)
	local factor = world_unit / UNIT * CONFIG.flash_draw_scale * CONFIG.flash_fit

	for _ = 1, CONFIG.flash_count do
		local tile = math.random(0, 3)
		local life = random_between(CONFIG.flash_life)
		local start = random_between(CONFIG.flash_scale)

		particles.mesh({
			-- FB_Brighten: the texture holds the hue and its alpha the strength (make_weapon_fx.py), so it is blended, not added
			additive = 0,
			brightness = function (fraction)
				return CONFIG.flash_intensity * attenuation(fraction, CONFIG.flash_attenuation)
			end,
			color = {
				1,
				1,
				1,
			},
			follow = function ()
				return flash_round == round and follow() or nil
			end,
			life = life,
			material = "units/ut/fx/fx_weapon_minigun_burst_" .. tile,
			rotation = camera_rotation,
			scale = function (fraction)
				return (start + CONFIG.flash_growth * fraction * life) * factor
			end,
			spin = 0,
			angle = math.random() * 360,
			spin_axis = Vector3(0, 1, 0),
			unit = "units/ut/fx/minigun_flash_mesh",
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
		color = CONFIG.tracer_color,
		fade_in = 0,
		fade_out = life,
		intensity = CONFIG.tracer_intensity,
		life = life,
		size = CONFIG.tracer_width * UNIT,
		texture = "tracer_shot",
		track = function ()
			-- The sprite's middle flies along the path, and it grows to its length in its first moment (SizeScale)
			local age = Managers.time:time("game") - now
			local middle = speed * age
			local half = length / 2 * math.min(1, age / CONFIG.tracer_grow_time)
			local unboxed = direction_box:unbox()

			return origin:unbox() + unboxed * (middle - half), origin:unbox() + unboxed * math.min(reach, middle + half)
		end,
	})
end

-- A shell leaves the ejector and falls: UT's ShellCasing mesh. ShellSpewer is attached to the weapon, so like the flash it is drawn with
-- the model's field of view, in the space of the model in the player's view, where a UT unit is world_unit meters. It is placed from the
-- ejector, which moves with the model, by how far it has flown.
local function shell(ejector, right, up, world_unit)
	local velocity = Vector3Box(right * random_between(CONFIG.shell_speed) + up * (random_between(CONFIG.shell_speed) * 0.6) + random_direction() * 30)
	local flown = Vector3Box(Vector3.zero())
	local up_box = Vector3Box(up)
	local last = Managers.time:time("game")
	local _, camera_rotation = utils.camera_pose()

	particles.mesh({
		additive = 0,
		brightness = function ()
			return 1
		end,
		color = {
			1,
			1,
			1,
		},
		follow = function ()
			local start = ejector()

			if not start then
				return nil
			end

			local now = Managers.time:time("game")
			local dt = now - last
			local v = velocity:unbox() - up_box:unbox() * (CONFIG.shell_gravity * dt)

			last = now
			velocity:store(v)
			flown:store(flown:unbox() + v * dt)

			return start + flown:unbox() * world_unit
		end,
		life = random_between(CONFIG.shell_life),
		material = "units/ut/fx/fx_weapon_shell_casing",
		rotation = camera_rotation or Quaternion.identity(),
		scale = function ()
			return CONFIG.shell_scale * world_unit / UNIT
		end,
		spin = random_between({-CONFIG.shell_spin, CONFIG.shell_spin}) / (math.pi * 2),
		spin_axis = random_direction(),
		unit = "units/ut/fx/shell_casing_mesh",
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

			-- The meters of a UT unit of the world where the model is: its own unit, without its DrawScale
			local world_unit = (api.state() and api.state().unit_scale or UNIT) / api.draw_scale()

			first_person_flash(function ()
				return api.state() and api.muzzle_model_position() or nil
			end, world_unit)

			-- MinigunAttachment.GetTracerStart: in the player's own view the tracer starts at Weapon.GetEffectStart, EffectOffset from
			-- the eye (in a view of 90 degrees across)
			local camera_position, camera_rotation = utils.camera_pose()
			local player = Managers.player:local_player()

			if camera_position and player then
				local offset = CONFIG.effect_offset
				-- (UT's view of 90 degrees across at 16 by 9 is 0.5625 of a tangent up and down)
				local scale = math.tan(Managers.state.camera:fov(player.viewport_name) / 2) / 0.5625
				local ray = Quaternion.forward(camera_rotation) + Quaternion.right(camera_rotation) * (offset[1] / offset[2] * scale) + Quaternion.up(camera_rotation) * (offset[3] / offset[2] * scale)

				tracer(owner_unit, camera_position + ray * (offset[2] * UNIT), end_position, interval)
			end

			-- The shells fly out of the ejector to the right of the gun
			if camera_rotation then
				shell(function ()
					return api.state() and api.muzzle_model_position("b_bone_caseejector") or nil
				end, Quaternion.right(camera_rotation), Quaternion.up(camera_rotation), world_unit)
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
		select_speed = 1.3636, -- Weapon's default SelectAnimRate
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
