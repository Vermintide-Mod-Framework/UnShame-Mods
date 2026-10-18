local mod = get_mod("unreal_tournament")

-- Minigun skin: how UT2004's Minigun looks and sounds.
--
-- weapon_skin.lua does the model, its placement and animations, the bob and the third person. This file does what is the Minigun's own:
-- the barrels that turn (Minigun.UpdateRoll), the muzzle flash, the shells, the tracers, the hits on walls, and the sounds of the winding
-- and the fire.
-- The gameplay is in minigun.lua. This file only draws it, and is told what happens through the hook tables in hooks.lua.
--
-- The assets were made with tools/asset_conversion (convert_weapon.py minigun, convert_static.py minigun_pickup and minigun_3rd,
-- make_weapon_fx.py and make_bank.py minigun).

local utils = mod.utils
local animations = mod:dofile("scripts/mods/unreal_tournament/minigun/skin_animations")
local particles = mod.skin_particles

local CONFIG = {
	-- The first person flash's DrawScale (MinigunMuzFlash1st, see muzzle_flash.lua)
	flash_draw_scale = 0.9,
	-- The weapon's light (xWeaponAttachment.WeaponLight): every round turns it on for 0.15 s, at the gun in a character's hand (the held
	-- mesh's origin). In the player's own view UT lights the first person gun's light instead, which doesn't light that gun, as UT draws it
	-- apart. A light here would light the gun the player holds, so there is none in that view (as for the Shock Rifle). LightHue 30 of
	-- 255 and LightSaturation 150 (0 is all colour, 255 is white) are a pale orange, and LightRadius 5 is in steps of 25 units: 2.5 m.
	-- It pulses (LT_Pulse): Unreal's engine multiplies its brightness by 0.6 + 0.39 * sin(a turn every LightPeriod / 35 seconds), so it
	-- flickers between a fifth and all of it, 35 / 3 times a second.
	light_color = { 1, 0.85, 0.6 },
	light_intensity = 1.5,
	light_falloff = 2.5, -- meters
	light_life = 0.15,
	light_period = 3, -- LightPeriod
	-- The smoke at the muzzle in the player's own view (MinigunMuzzleSmoke): a round sets it to 30 puffs a second, and the rate falls
	-- towards none by its own amount a second (Lerp(dt) in MuzzleSmoke.Tick) and stops below 1. A puff lasts 0.6 to 1.2 s, starts 15 to 20
	-- units across and grows by 4 a second, is a grey of 70 to 113 out of 255, and is blended by the texture's alpha (STY_Alpha). It
	-- rises slowly (its mass is -0.15 to -0.25, which xEmitter turns into a rise in its engine, not its scripts), and fades from the start,
	-- so the puffs stay together by the muzzle and thin out as they rise (both set in the game: rising by that much of the zone's gravity
	-- sent them up in a long column, and fading only from a fifth of their life kept the column thick).
	smoke_rate = 30, -- puffs a second
	-- How many puffs each mode's smoke holds at a time (mMaxParticles: MinigunAltMuzzleSmoke holds half as many)
	smoke_max = {
		primary = 30,
		alt = 15,
	},
	smoke_life = { 0.6, 1.2 },
	smoke_size = { 15, 20 }, -- UT units across
	smoke_growth = 4, -- UT units across, a second
	smoke_grey = { 70 / 255, 113 / 255 },
	smoke_rise = { 15, 30 }, -- UT units a second
	smoke_attenuation = 0,
	-- SmokeTex is a sheet of puffs (pclSmoke's mNumTileColumns and mNumTileRows, 4 by 4), and each puff is one of them (mRandTextures)
	smoke_tiles = 16,
	-- The third person flash (NewMinigunMFlash): four flames in a row along the barrel, each smaller and further out, the last two up to 8
	-- units further at random (StartLocationOffset and StartLocationRange). The emitter is attached to the gun but not scaled by its
	-- DrawScale, so these are UT units of the world. A UE2 sprite's size (StartSizeRange) is its radius: it is drawn twice as wide.
	flame_offsets = {8, 16, 24, 32}, -- UT units from the muzzle
	flame_offset_ranges = {0, 0, 8, 8}, -- UT units
	flame_sizes = {{15, 20}, {10, 15}, {5, 10}, {2.5, 5}}, -- UT units
	flame_life = 0.1,
	-- NewTracer: a sprite along its velocity that flies at 10000 units a second to where the round hit, less the pullback, and is
	-- there only if that is farther than the minimum. Its size is 10 across and 20 along times 0.002 of its speed (ScaleSizeXByVelocity),
	-- and as a UE2 sprite's size is its radius, it is drawn 20 units wide and 800 long. It grows to that in its first 0.03 s (SizeScale),
	-- and keeps its brightness. Its colour is the texture's times (1, 0.8, 0.5). A tracer is made every tracer_interval seconds, for the
	-- primary and the alt fire.
	tracer_speed = 10000, -- UT units a second
	tracer_length = 800,
	tracer_width = 20,
	tracer_grow_time = 0.03,
	tracer_color = { 1, 0.8, 0.5 },
	tracer_pullback = 50,
	tracer_min_distance = 0,
	tracer_interval = 0.12,
	tracer_alt_interval = 0.18,
	-- Minigun.EffectOffset: where the tracers start in the player's view (right, forward, up, UT units from the eye)
	effect_offset = {18, 100, -16},
	tracer_intensity = 1,
	-- ShellSpewer: the shells (the ShellCasing mesh, 8.6 units long) fly out of the gun's ejector and fall, for 0.5 to 1 s, turning as
	-- they go. They go the way the ejector bone points, out to the right and up, and each is off that by a random share of
	-- shell_deviation: up to half its speed more or less outwards, up to 0.6 of it forward or back along the gun (mDirDev's 0.5 and 0.6),
	-- and some of it up or down. The ones that go back soon pass the eye, so most of those that are seen go forward. ShellSpewer's
	-- mSpeedRange (200 to 250) and the 0.2 of mDirDev up and down looked too even next to UT, so those are wider (set in the game).
	shell_speed = {100, 300}, -- UT units a second
	shell_up = 0.8, -- of the speed
	shell_deviation = {0.5, 0.6, 1}, -- out, along the gun, up
	shell_life = {0.5, 1},
	-- The shell's size: mSizeRange 10 times DrawScale 0.05
	shell_scale = 0.5,
	shell_gravity = 950, -- UT units a second squared (PhysicsVolume's)
	-- How much of its speed a shell loses in a second (xEmitter's mAirResistance, which ShellSpewer leaves at 0.4)
	shell_air_resistance = 0.4,
	shell_spin = 12, -- radians a second, at most, each way
	-- The fire and the winding are UT's AmbientSounds (MinigunFire.PlayAmbientSound), which loop: the bank's sounds loop, and each is
	-- started once and stopped. The winding plays while the barrels turn and the fire doesn't (they wind up and down). The fire starts
	-- with a mode's first round: the player's own stops when that mode's button is let go, and the others' (whose buttons aren't known
	-- here) once there has been no round for this long, which is longer than the time between the mode's rounds (1/15 s and 1/5 s).
	stop_after = {
		primary = 0.18,
		alt = 0.3,
	}, -- seconds
	-- While a mode fires, the gun loops its FireLoop animation, which shakes it, at this many times its own speed (FireLoopAnimRate). It
	-- starts and stops with the fire sound, as both start and stop with MinigunFire's FireLoop state.
	fire_loop_rate = {
		primary = 9,
		alt = 3,
	},
	-- MinigunFire's view shake, which each round starts for the player who fires (WeaponFire.ShakeView, see view_shake.lua): a turn of
	-- 50 of 65536 each way on every axis, at 10000 a second, and an offset of 1 unit on every axis, at 1000 a second, both for 2
	shake_turn = { 50, 50, 50 }, -- pitch, yaw, roll
	shake_turn_rate = { 10000, 10000, 10000 },
	shake_turn_time = 2,
	shake_offset = { 1, 1, 1 }, -- UT units: forward, right, up
	shake_offset_rate = { 1000, 1000, 1000 },
	shake_offset_time = 2,
	-- Minigun.GearRatio and GearOffset: the gear turns this many times as far as the barrels, and the other way
	gear_ratio = -2.37,
	-- The barrels and the gear turn about axes along the mesh's own right (the mesh lies sideways, and the pivot's yaw turns it to the
	-- front). Each axis goes through this point of the mesh (forward, up, in the mesh's units).
	barrel_pivot = { 0, 8.8 },
	gear_pivot = { 17.85, 10.87 },
	-- Where a round hits a wall (see mod.hit_effects): how far from the viewer the others' hits are drawn, how often the primary fire's
	-- leave a puff of dust, and the impact sounds (xHeavyWallHitEffect's, of which the Sniper Rifle's bank has six of the ten)
	hit_effect_distance = 2000, -- UT units
	hit_smoke_chance = 0.5,
	impact_sounds = {
		"ut_sniper_impact_1_3d",
		"ut_sniper_impact_2_3d",
		"ut_sniper_impact_3_3d",
		"ut_sniper_impact_4_3d",
		"ut_sniper_impact_5_3d",
		"ut_sniper_impact_6_3d",
	},
	-- Which way the barrels turn, in first and third person: 1 or -1. -1 is the way UT's turn (checked in the game).
	barrel_direction = -1,
	-- The third person mesh's barrels are a geometry of their own (convert_static.py minigun_3rd). They turn about the barrel bone's place
	-- (right, forward, up, in the mesh's UT units) at these turns a second while rounds come, and stop this long after the last round
	-- (MinigunAttachment.UpdateRoll and UpdateRollTime). The shells fly from the ejector bone, on the gun's right.
	third_person_barrels = "g_third_person_0_barrels",
	third_person_barrel_pivot = { -2.76, 46.24, 8.16 },
	third_person_barrel_turns = {
		primary = 3,
		alt = 1,
	},
	third_person_roll_stop = 0.2, -- seconds
	third_person_ejector = { 6.6, 38.3, 12.7 },
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

-- How each hero holds the mesh in third person (see weapon_skin_third_person.lua), in the pose of the base weapon. The mesh is turned as
-- the game's weapon in the hand is, which the game animates with the arms.
local GRIPS = {
	-- The repeating handgun's pose: the game links the gun to the right hand, and the left holds its front. The mesh is linked to the
	-- left hand's node, moved back and to the left from the mesh's origin, and tipped up so that the gun's line runs through the right
	-- hand too (set in the game).
	minigun = {
		hand_node = "j_leftweaponattach",
		grip_right = -15,
		grip_forward = 60,
		grip_up = 0,
		yaw = 0,
		pitch = 9.9,
		roll = 0,
	},
	-- The repeater pistol's pose: the game links the pistol to the right hand, and the left is free. The mesh is linked to the right
	-- hand's node, at the point of it where Kruber's right hand is.
	minigun_wh = {
		hand_node = "j_rightweaponattach",
		grip_right = -5.9,
		grip_forward = 13.2,
		grip_up = -0.2,
		yaw = 0,
		pitch = 0,
		roll = 0,
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

local random_between = utils.random_between
local random_direction = utils.random_direction

local function first_person_api()
	return mod.weapon_skin.shown_skin(skin_apis)
end

local function third_person_muzzle(character)
	return mod.weapon_skin.held_muzzle(skin_apis, character)
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

-- The flash in the hand of a character: flames in a row along the barrels, in UT units of the world. They move with the gun, as UT's
-- emitter is attached to the muzzle and its flames are placed relative to it (PTCS_Relative).
local function third_person_flash(owner_unit, api)
	local scale = UNIT

	for i, offset in ipairs(CONFIG.flame_offsets) do
		local distance = (offset + math.random() * CONFIG.flame_offset_ranges[i]) * scale

		particles.sprite({
			attenuation = 0,
			color = {
				1,
				1,
				1,
			},
			follow = function ()
				local muzzle = api.third_person.muzzle_position(owner_unit)

				return muzzle and muzzle + Quaternion.forward(api.third_person.muzzle_rotation(owner_unit)) * distance or nil
			end,
			life = CONFIG.flame_life,
			size = 2 * random_between(CONFIG.flame_sizes[i]) * scale,
			spin = (math.random() * 2 - 1) * 0.3,
			texture = "minigun_flame_" .. math.random(0, 15),
		})
	end
end

-- The weapon's light: each character's gun has one, which a round turns on for light_life, or keeps on, at the place follow returns
local light_rounds = setmetatable({}, {
	__mode = "k",
})

local function weapon_light(owner_unit, follow)
	local round = (light_rounds[owner_unit] or 0) + 1

	light_rounds[owner_unit] = round

	particles.light({
		brightness = function ()
			return 0.6 + 0.39 * math.sin(2 * math.pi * Managers.time:time("game") * 35 / CONFIG.light_period)
		end,
		color = CONFIG.light_color,
		falloff = CONFIG.light_falloff,
		follow = function ()
			if light_rounds[owner_unit] == round then
				return follow()
			end
		end,
		intensity = CONFIG.light_intensity,
		life = CONFIG.light_life,
	})
end

-- The smoke at the muzzle in the player's own view. Each mode has its own emitter (WeaponFire.SmokeEmitterClass): how many puffs a
-- second it makes now, the part of a puff it owes, and when each of its puffs ends.
local smoke = {
	primary = {
		rate = 0,
		owed = 0,
		ends = {},
	},
	alt = {
		rate = 0,
		owed = 0,
		ends = {},
	},
}

local function clear_smoke()
	for _, emitter in pairs(smoke) do
		emitter.rate = 0
		emitter.owed = 0
		table.clear(emitter.ends)
	end
end

-- Where the smoke starts: Weapon.GetEffectStart, EffectOffset from the eye in the weapon's view (WeaponFire.DrawMuzzleFlash moves the
-- smoke emitter there). It moves with the bob and the view shake, but not with the gun's animation, as the barrels' muzzle does.
local function smoke_start(api)
	local offset = CONFIG.effect_offset
	local first_person_unit, point = api.view_point_in_view(offset[2], offset[1], offset[3])

	if not first_person_unit then
		return nil
	end

	local camera_node = utils.camera_node(first_person_unit)

	return Unit.world_position(first_person_unit, camera_node) + Quaternion.rotate(Unit.world_rotation(first_person_unit, camera_node), point)
end

-- Makes the puffs of smoke of one mode's emitter that are due, in the space of the model in the player's view (where a UT unit is
-- world_unit meters), drawn with its field of view. A puff that is due while the emitter has as many as it can hold isn't made. The rate
-- falls as MuzzleSmoke's does.
local function update_smoke_emitter(api, mode, world_unit, dt)
	local emitter = smoke[mode]

	if emitter.rate <= 0 then
		return
	end

	local now = Managers.time:time("game")
	local ends = emitter.ends

	for i = #ends, 1, -1 do
		if ends[i] <= now then
			table.remove(ends, i)
		end
	end

	emitter.owed = emitter.owed + emitter.rate * dt

	local muzzle = smoke_start(api)

	while emitter.owed >= 1 and muzzle do
		local life = random_between(CONFIG.smoke_life)
		local grey = random_between(CONFIG.smoke_grey)
		local rise = random_between(CONFIG.smoke_rise)

		emitter.owed = emitter.owed - 1

		if #ends < CONFIG.smoke_max[mode] then
			ends[#ends + 1] = now + life

			particles.sprite({
				additive = 0,
				attenuation = CONFIG.smoke_attenuation,
				color = { grey, grey, grey },
				growth = CONFIG.smoke_growth * world_unit,
				life = life,
				material = "units/ut/fx/fx_weapon_muzzle_smoke_" .. math.random(0, CONFIG.smoke_tiles - 1),
				position = muzzle,
				size = random_between(CONFIG.smoke_size) * world_unit,
				velocity = Vector3(0, 0, rise * world_unit),
			})
		end
	end

	emitter.rate = emitter.rate - emitter.rate * math.min(1, dt)

	if emitter.rate < 1 then
		emitter.rate = 0
		emitter.owed = 0
	end
end

local function update_smoke(api, world_unit, dt)
	update_smoke_emitter(api, "primary", world_unit, dt)
	update_smoke_emitter(api, "alt", world_unit, dt)
end

-- A tracer: a streak that flies from the muzzle to where the round hit
local last_tracer_time = {}
-- How the barrels of the mesh in each character's hand turn: { angle in degrees, turns a second, time of the last round }
local rolls = {}

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

-- A shell leaves the ejector and falls: UT's ShellCasing mesh. It is placed from ejector, which returns where it started, by how far it
-- has flown, where a UT unit is world_unit meters. rotation is how it starts out turned. It is drawn with the camera's field of view, in
-- both views: ShellSpewer is attached to the weapon's bone, but UT doesn't draw it with the weapon (Weapon.RenderOverlays), and its shells
-- stay in the world once they are out. They are lit by the level, as UT's are.
local function shell(ejector, right, forward, up, world_unit, rotation)
	local deviation = CONFIG.shell_deviation
	local out = 1 + random_between({-deviation[1], deviation[1]})
	local along = random_between({-deviation[2], deviation[2]})
	local rise = CONFIG.shell_up + random_between({-deviation[3], deviation[3]})
	local velocity = Vector3Box((right * out + forward * along + up * rise) * random_between(CONFIG.shell_speed))
	local flown = Vector3Box(Vector3.zero())
	local up_box = Vector3Box(up)
	local last = Managers.time:time("game")

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
			local v = velocity:unbox() * math.max(0, 1 - CONFIG.shell_air_resistance * dt) - up_box:unbox() * (CONFIG.shell_gravity * dt)

			last = now
			velocity:store(v)
			flown:store(flown:unbox() + v * dt)

			return start + flown:unbox() * world_unit
		end,
		life = random_between(CONFIG.shell_life),
		material = "units/ut/fx/fx_shell_casing_lit",
		rotation = rotation,
		scale = function ()
			return CONFIG.shell_scale * world_unit / UNIT
		end,
		spin = random_between({-CONFIG.shell_spin, CONFIG.shell_spin}) / (math.pi * 2),
		spin_axis = random_direction(),
		unit = "units/ut/fx/shell_casing_mesh",
	})
end

-- The player's own fire and winding, which loop until they are stopped
local sound = {
	fire_id = nil,
	fire_mode = nil,
	wind_id = nil,
}

local function stop_fire_sound(api)
	api.stop_sound(sound.fire_id)

	sound.fire_id = nil
	sound.fire_mode = nil
end

-- Stops the fire and the winding at once, when the gun is put away (when the level ends its world can be gone, and its sounds with it)
local function stop_sounds(api)
	if Managers.world:has_world("level_world") then
		stop_fire_sound(api)
		api.stop_sound(sound.wind_id)
	end

	sound.fire_id = nil
	sound.fire_mode = nil
	sound.wind_id = nil
end

local function update_sounds(api, dt)
	-- The fire stops as soon as its mode's button is let go (to stop, or to switch: the other mode's fire starts with its own first round)
	if sound.fire_id and not minigun.held[sound.fire_mode] then
		stop_fire_sound(api)

		-- (and the gun goes back to its idle animation: MinigunFire's FireLoop.EndState)
		api.play("Idle")
	end

	-- The winding plays while the barrels turn and the fire doesn't: as they wind up, and as they slow down
	local winding = minigun.spin > 0 and not sound.fire_id

	if winding and not sound.wind_id then
		sound.wind_id = api.play_sound("ut_minigun_wind")
	elseif not winding and sound.wind_id then
		api.stop_sound(sound.wind_id)

		sound.wind_id = nil
	end
end

local function round_sound(api, mode)
	if sound.fire_mode ~= mode then
		stop_fire_sound(api)

		sound.fire_mode = mode
		sound.fire_id = api.play_sound(mode == "alt" and "ut_minigun_alt_fire" or "ut_minigun_fire")

		if api.state() then
			api.play("FireLoop", api.animation_duration("FireLoop") / CONFIG.fire_loop_rate[mode], true)
		end
	end
end

-- The fire heard from the characters (the others', and the player's own in a third person view): { handle (utils.play_on_unit), mode, time
-- of the last round } for each
local remote_fire = {}

local function remote_round_sound(owner_unit, mode)
	local fire = remote_fire[owner_unit]

	if not fire or fire.mode ~= mode then
		utils.stop_sound(fire and fire.handle)

		fire = {
			handle = utils.play_on_unit(mode == "alt" and "ut_minigun_alt_fire_3d" or "ut_minigun_fire_3d", owner_unit),
			mode = mode,
		}
		remote_fire[owner_unit] = fire
	end

	fire.last = Managers.time:time("game")
end

-- Stops the characters' fire once their rounds stop, or they are gone
local function update_remote_sounds(now)
	for owner_unit, fire in pairs(remote_fire) do
		if not Unit.alive(owner_unit) or now - fire.last >= CONFIG.stop_after[fire.mode] then
			if Managers.world:has_world("level_world") then
				utils.stop_sound(fire.handle)
			end

			remote_fire[owner_unit] = nil
		end
	end
end

-- A round by any player, on every machine
mod.minigun_shot_callbacks.minigun_skin = function (owner_unit, mode, end_position, hit_normal, hit_level, heavy_wall)
	if not skin_apis[1] then
		return
	end

	local interval = mode == "alt" and CONFIG.tracer_alt_interval or CONFIG.tracer_interval

	-- Where a round hits a wall, as MinigunAttachment.ThirdPersonEffects: the primary fire's sparks and, half the time, a puff of dust
	-- (xHeavyWallHitEffect, only on the surfaces where UT makes it: see heavy_wall), and the alt fire's small explosion in dust
	-- (ExploWallHit), with one of the impact sounds. UT draws the others' hits only near the viewer. The game's own impact of the round
	-- is there too, and is all there is on the other surfaces.
	if hit_level and (mode == "alt" or heavy_wall) then
		local camera_position = utils.camera_pose()
		local near = utils.is_local_player_unit(owner_unit) or camera_position and Vector3.distance(camera_position, end_position) < CONFIG.hit_effect_distance * UNIT

		if near then
			if mode == "alt" then
				mod.hit_effects.impact_smoke(end_position, hit_normal)
				mod.hit_effects.small_explosion(end_position, hit_normal)
			else
				if math.random() < CONFIG.hit_smoke_chance then
					mod.hit_effects.impact_smoke(end_position, hit_normal)
				end

				mod.hit_effects.wall_sparks(end_position, hit_normal)
			end

			skin_apis[1].play_sound_at(CONFIG.impact_sounds[math.random(#CONFIG.impact_sounds)], end_position)
		end
	end

	if utils.is_local_player_unit(owner_unit) then
		mod.view_shake.start(CONFIG.shake_offset, CONFIG.shake_offset_rate, CONFIG.shake_offset_time)
		mod.view_shake.start_rotation(CONFIG.shake_turn, CONFIG.shake_turn_rate, CONFIG.shake_turn_time)

		local api = first_person_api()

		if api and not api.third_person.shows_weapon(owner_unit) then
			round_sound(api, mode)

			-- The meters of a UT unit of the world where the model is: its own unit, without its DrawScale
			local world_unit = (api.state() and api.state().unit_scale or UNIT) / api.draw_scale()

			mod.minigun_muzzle_flash("minigun", function ()
				return api.state() and api.muzzle_model_position() or nil
			end, world_unit, CONFIG.flash_draw_scale, function ()
				if api.state() then
					return api.model_point_in_view()
				end
			end)

			-- The mode's smoke, which the round keeps going
			smoke[mode].rate = CONFIG.smoke_rate

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

			-- The shells fly out of the ejector to the right of the gun, from where the ejector is seen, at UT's distance from the eye
			local ejector = api.model_point_in_world("b_bone_caseejector")

			if camera_rotation and ejector then
				local start = Vector3Box(ejector)

				shell(function ()
					return start:unbox()
				end, Quaternion.right(camera_rotation), Quaternion.forward(camera_rotation), Quaternion.up(camera_rotation), UNIT,
					camera_rotation)
			end

			return
		end
	end

	local muzzle, api = third_person_muzzle(owner_unit)

	if not muzzle then
		return
	end

	third_person_flash(owner_unit, api)
	weapon_light(owner_unit, function ()
		return api.third_person.point_position(owner_unit, 0, 0, 0)
	end)
	tracer(owner_unit, muzzle, end_position, interval)

	-- The barrels turn while rounds come, at the speed of the mode
	local roll = rolls[owner_unit] or {
		angle = 0,
	}

	rolls[owner_unit] = roll
	roll.turns = CONFIG.third_person_barrel_turns[mode]
	roll.last = Managers.time:time("game")

	-- The shells fly out of the ejector to the gun's right
	local rotation = api.third_person.muzzle_rotation(owner_unit)
	local ejector = CONFIG.third_person_ejector

	shell(function ()
		return api.third_person.point_position(owner_unit, ejector[1], ejector[2], ejector[3])
	end, Quaternion.right(rotation), Quaternion.forward(rotation), Quaternion.up(rotation), UNIT, rotation)

	-- The gun is heard from where its holder is: the others', and the player's own in a third person view
	remote_round_sound(owner_unit, mode)
end

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	if next(remote_fire) and Managers.time:has_timer("game") then
		update_remote_sounds(Managers.time:time("game"))
	end
end

-- Turns the barrels of the meshes in the characters' hands about the barrel bone, and stops them a moment after the last round
mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	if not next(rolls) or not Managers.time:has_timer("game") then
		return
	end

	local now = Managers.time:time("game")

	for character, roll in pairs(rolls) do
		if not Unit.alive(character) then
			rolls[character] = nil
		else
			if now - roll.last > CONFIG.third_person_roll_stop then
				roll.turns = 0
			end

			roll.angle = (roll.angle + CONFIG.barrel_direction * roll.turns * 360 * dt) % 360

			for _, api in ipairs(skin_apis) do
				local unit, config = api.third_person.held_mesh(character)

				if unit and Unit.has_node(unit, CONFIG.third_person_barrels) then
					local node = Unit.node(unit, CONFIG.third_person_barrels)
					local pivot = Vector3(unpack(CONFIG.third_person_barrel_pivot)) * config.meters_per_unit
					local rotation = Quaternion.axis_angle(Vector3.forward(), math.rad(roll.angle))

					Unit.set_local_rotation(unit, node, rotation)
					Unit.set_local_position(unit, node, pivot - Quaternion.rotate(rotation, pivot))
				end
			end
		end
	end
end

local function new_skin(variant)
	local definition = mod.items.weapons[variant.setting_id]
	local grip = GRIPS[variant.setting_id]
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
		-- UT's third person mesh of the weapon (MinigunAttachment's Weapons.Minigun_3rd) at UT's size in a player's hand (DrawScale 0.4).
		-- Its origin is at its back, and its barrels run along its forward, to the muzzle (the mesh's flash bone). How each hero holds it
		-- is in GRIPS.
		third_person = {
			id = variant.id,
			template = definition.template,
			unit_name = "units/ut/minigun/third_person",
			hand_node = grip.hand_node,
			meters_per_unit = 0.02 * 0.4,
			scale = 1,
			grip_right = grip.grip_right,
			grip_forward = grip.grip_forward,
			grip_up = grip.grip_up,
			yaw = grip.yaw,
			pitch = grip.pitch,
			roll = grip.roll,
			follow_game_unit = 2,
			follow_calibrate_seconds = 1,
			muzzle_right = -2.8,
			muzzle_forward = 147,
			muzzle_up = 14.7,
			menu_yaw = -90,
		},
		on_create = function ()
			api.play_sound("ut_minigun_select")
		end,
		-- (the gun is put away, or the level ends: its update no longer runs to stop the loops)
		on_destroy = function ()
			stop_sounds(api)
		end,
		on_update = function (skin, dt)
			skin.inspect_pose = (skin.inspect_pose or 0) + ((skin.inspecting and 1 or 0) - (skin.inspect_pose or 0)) * math.min(1, CONFIG.inspect_pose_speed * dt)
			skin.inspect_time = skin.inspecting and (skin.inspect_time or 0) + dt or 0
			skin.extra_yaw = skin.inspect_pose * CONFIG.inspect_sway * math.sin(skin.inspect_time * CONFIG.inspect_sway_speed)

			-- The barrels turn by how fast they are going (Minigun.UpdateRoll), the way UT's do
			skin.barrel_angle = ((skin.barrel_angle or 0) + CONFIG.barrel_direction * minigun.turns_per_second * 360 * dt) % 360

			update_sounds(api, dt)
			update_smoke(api, (skin.unit_scale or UNIT) / api.draw_scale(), dt)
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
			table.clear(remote_fire)
			table.clear(rolls)
			table.clear(light_rounds)
			clear_smoke()
			sound.fire_id = nil
			sound.fire_mode = nil
			sound.wind_id = nil
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
