local mod = get_mod("unreal_tournament")

-- Link Gun skin: how UT2004's Link Gun looks and sounds, on each hero's copy.
--
-- weapon_skin.lua does the model, its placement and animations, the bob and the third person. This file does what is the Link Gun's own:
-- the flashes, the bolts in flight and where they hit, the beam and the sounds. The gameplay is in link_gun.lua, which keeps the links
-- and the beams (mod.link_new) that this file draws.
--
-- The model, its animations, the textures and the sounds are the old Link Gun's (link/), made with tools/asset_conversion.

local utils = mod.utils
local animations = mod:dofile("scripts/mods/unreal_tournament/link/skin_animations")
local animations_2003 = mod:dofile("scripts/mods/unreal_tournament/link_new/skin_animations_2003")
local particles = mod.skin_particles
local link = mod.link_new

local UNIT = utils.UT_UNIT

local VARIANTS = { "link_new", "link_new_dr", "link_new_wh", "link_new_bw", "link_new_we" }

local TEMPLATE_NAMES = {}
local skin_apis = {}

for _, setting_id in ipairs(VARIANTS) do
	TEMPLATE_NAMES[mod.items.weapons[setting_id].template] = true
end

local CONFIG = {
	-- LinkMuzFlashProj1st, the flash of a bolt: green, or gold with links
	muzzle_size = 45,
	muzzle_growth = 100,
	muzzle_life = 0.1,
	-- LinkAltFire.FireAnimRate: the Fire animation plays at this much of its speed
	fire_animation_rate = 0.75,
	-- LinkProjectile: a green plasma bolt, gold with links (LinkAdjust). Here it is sprites that follow the game's projectile.
	bolt_size = 40,
	bolt_glow_size = 70,
	bolt_color = { 0.5, 1, 0.4 },
	linked_color = { 1, 0.85, 0.3 },
	-- Bolts of another player that start less than this far apart (in seconds) belong to the same shot
	shot_gap = 0.1,
}

-- LinkBeamEffect (an xEmitter of PT_Beam) and its LinkBeamChild: a beam of points every regen_dist UT units from the muzzle to where it
-- ends, which leaves the muzzle along the aim and bends to the end (mBendStrength), and waves across itself (mWaveFrequency,
-- mWaveAmplitude, mWaveShift), in a plane that spins about it (mSpinRange). The wave dies down while the beam is on an enemy or links an
-- ally, and grows while the gun moves. It is green, gold with links, and blue while it links an ally (LinkColor: the team colors are red
-- and blue, and the heroes are one team, as UT's blue). Each link makes it wider and its wave faster, and there is one child more, up
-- to four. The numbers are UT units, and the turns are UT's (65536 to a whole turn).
local BEAM = {
	regen_dist = 65,
	child_regen_dist = 75,
	size = 11,
	color = 240 / 255,
	child_color = 180 / 255,
	wave_frequency = 0.06, -- radians a unit along the beam
	wave_amplitude = 8,
	max_amplitude = 16,
	wave_shift = 100000, -- the wave's travel, turns a second
	spin = 45000, -- turns a second
	-- How far along the beam its bend reaches, as a share of its length. mBendStrength is 3, and how the engine uses it isn't in the
	-- scripts: the bend reaches a third of the way (a choice, to be checked against UT).
	bend_share = 1 / 3,
	max_children = 4,
	-- A linked beam ends this far short of the ally (LinkBeamEffect.Tick: EndEffect - BeamDir * 30)
	linked_end_back = 30,
	-- LinkFire.LinkScale: the size of everything by the links, up to 5
	link_scale = { 0, 0.5, 0.9, 1.2, 1.4, 1.5 },
}

-- LinkSparks, where the beam ends: line particles that fly back along the aim from what it hits, or on along the beam from its end in the
-- air, 40 a second. LinkMuzFlashBeam3rd, at the muzzle of the mesh in a character's hand while it beams: 12 a second, 50 to 60 units,
-- 0.25 s. LinkMuzFlashBeam1st, at the muzzle of the player's own model: one of 24 units for every hit. LinkProtSphere, on an ally who is
-- linked: discs, 12 a second, 35 units (20 for the player's own view of themself), 0.25 s.
local SPARKS = {
	rate = 40,
	life = 0.5,
	speed = { 175, 225 },
	direction_deviation = 0.75,
	position_deviation = 8,
	size = { 8, 12 },
	color = 150 / 255,
	attenuation = 0.1,
}

-- LinkProjSparks (yellow with links: LinkProjSparksYellow), where a bolt ends: 8 line particles off the surface, spread wide
local BOLT_SPARKS = {
	count = 8,
	life = 0.5,
	speed = { 100, 175 },
	direction_deviation = 1.5,
	position_deviation = 10,
	size = { 8, 12 },
	color = 150 / 255,
	attenuation = 0.1,
}

-- A line particle (PT_Line) is a streak along the way it moves, as long as the spark is fast (mSpawnVecB.Z seconds of its speed), and
-- falls (its mMassRange; as fast as the Bio Rifle's sparks fall)
local SPARK_STREAK_SECONDS = 0.06
local SPARK_GRAVITY = 10.7 -- m/s^2

local FLASH_3RD = { rate = 12, life = 0.25, size = { 50, 60 }, color = 180 / 255 }
local FLASH_1ST = { life = 0.25, size = 24, color = 200 / 255, interval = 0.12 }
local SPHERE = { rate = 12, life = 0.25, size = 35, own_size = 20, color = 180 / 255 }

-- How the third person mesh sits in each hero's hand: the hand the game links the base weapon to, and the point of the mesh in the hand
-- (UT units) and its turn. They are a start, to be set in the game.
--   follow_game_unit 2: the mesh turns with the base weapon's unit, which the arms animate (the guns). 3: with the hand's node, turned
--   by yaw, pitch and roll (the Deepwood Staff, as the Lightning Gun's). nil: level, the way the character faces (the Beam Staff, as the
--   Shock Rifle's).
local GRIPS = {
	link_new = { hand_node = "j_leftweaponattach", right = 0, forward = 0, up = 0, yaw = 0, pitch = 0, roll = 0, follow = 2 },
	link_new_dr = { hand_node = "j_leftweaponattach", right = 0, forward = 0, up = 0, yaw = 0, pitch = 0, roll = 0, follow = 2 },
	link_new_wh = { hand_node = "j_leftweaponattach", right = 0, forward = 0, up = 0, yaw = 0, pitch = 0, roll = 0, follow = 2 },
	link_new_bw = { hand_node = "j_rightweaponattach", right = 0, forward = 5, up = 4, yaw = 0, pitch = 0, roll = 0, follow = nil },
	link_new_we = { hand_node = "j_leftweaponattach", right = -4, forward = -4, up = 0, yaw = -110, pitch = 0, roll = -25, follow = 3 },
}

-- A random direction within a cone about a direction, as xEmitter's mDirDev: a share of each axis across it
local function deviate(direction, across)
	local side = Vector3.normalize(Vector3.cross(direction, Vector3.up()))

	if Vector3.length(side) < 0.1 then
		side = Vector3.right()
	end

	local up = Vector3.cross(side, direction)

	return Vector3.normalize(direction + side * (math.random() * 2 - 1) * across + up * (math.random() * 2 - 1) * across)
end

local function random_between(range)
	return range[1] + (range[2] - range[1]) * math.random()
end

-- Throws a spark from a place along a way. The texture has two parts (tools/asset_conversion/split_spark.py): the body is a streak from
-- the tail to the head, and the head is a glow at the front. spec: the SPARKS or BOLT_SPARKS numbers. texture: link_spark_green or
-- link_spark_yellow. scale: how much bigger, faster and longer lived it is (for the links).
local function throw_spark(spec, position, way, texture, size_scale, speed_scale, life_scale)
	local offset = Vector3(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1) * (spec.position_deviation * UNIT)
	local origin = Vector3Box(position + offset)
	local velocity = Vector3Box(deviate(way, spec.direction_deviation) * (random_between(spec.speed) * speed_scale * UNIT))
	local width = random_between(spec.size) * size_scale * UNIT
	local life = spec.life * life_scale
	local started = Application.time_since_launch()
	local color = { spec.color, spec.color, spec.color }

	-- Returns where the spark's head is, and where its tail is
	local function spark()
		local age = Application.time_since_launch() - started
		local moving = velocity:unbox() + Vector3(0, 0, -SPARK_GRAVITY * age)
		local head = origin:unbox() + velocity:unbox() * age + Vector3(0, 0, -0.5 * SPARK_GRAVITY * age * age)
		local speed = Vector3.length(moving)
		local heading = speed > 0.001 and moving * (1 / speed) or Vector3.up()
		local length = math.max(width, speed * SPARK_STREAK_SECONDS)

		return head, head - heading * length
	end

	particles.beam({
		attenuation = spec.attenuation,
		color = color,
		life = life,
		size = width,
		texture = texture .. "_body",
		track = function ()
			local head, tail = spark()

			return tail, head
		end,
	})
	particles.sprite({
		angle = 0,
		attenuation = spec.attenuation,
		color = color,
		follow = function ()
			return (spark())
		end,
		life = life,
		size = width,
		texture = texture .. "_head",
	})
end

-- The skin whose model the player sees now
local function first_person_api()
	return mod.weapon_skin.shown_skin(skin_apis)
end

-- The skin of the mesh in a character's hand, and where its barrel ends
local function held_muzzle(character)
	return mod.weapon_skin.held_muzzle(skin_apis, character)
end

-- Where a character's shots and beam start: the end of the barrel of the model in the player's own view, or of the mesh in the hand
local function muzzle_of(character)
	local api = first_person_api()

	if utils.is_local_player_unit(character) and api and not api.third_person.shows_weapon(character) then
		return api.muzzle_position(), api.state() and api.state().unit_scale
	end

	local muzzle, holder = held_muzzle(character)

	return muzzle, holder and holder.third_person.meters_per_unit
end

local function color_of(character)
	return link.links_of(character) > 0 and CONFIG.linked_color or CONFIG.bolt_color
end

local function muzzle_flash(character)
	local _, scale = muzzle_of(character)

	if not scale then
		return
	end

	local gold = link.links_of(character) > 0

	particles.sprite({
		color = { 1, 1, 1 },
		follow = function ()
			return (muzzle_of(character))
		end,
		growth = CONFIG.muzzle_growth * scale,
		life = CONFIG.muzzle_life,
		size = CONFIG.muzzle_size * scale,
		spin = (math.random() * 2 - 1) * 0.2,
		texture = gold and "link_muz_yellow" or "link_muz_green",
	})
end

-- The third person of a look: UT2004's mesh, or UT2003's (Weapons.LinkGun_3rd, convert_static.py link2003_3rd), which runs along its
-- forward from its grip too
local function third_person_of(setting_id, unit_name, muzzle_forward, muzzle_up)
	local definition = mod.items.weapons[setting_id]
	local grip = GRIPS[setting_id]

	return {
		id = setting_id,
		template = definition.template,
		unit_name = unit_name,
		hand_node = grip.hand_node,
		meters_per_unit = 0.02 * 0.4,
		scale = 1,
		grip_right = grip.right,
		grip_forward = grip.forward,
		grip_up = grip.up,
		yaw = grip.yaw,
		pitch = grip.pitch,
		roll = grip.roll,
		follow_game_unit = grip.follow,
		muzzle_right = 0,
		muzzle_forward = muzzle_forward,
		muzzle_up = muzzle_up,
		menu_yaw = -90,
	}
end

local function new_skin(setting_id)
	local definition = mod.items.weapons[setting_id]
	local api

	api = mod.weapon_skin.new({
		id = setting_id,
		name = "link",
		template = definition.template,
		unit_name = "units/ut/link/link_gun",
		animations = animations,
		muzzle_node = "b_bone_flasha",
		-- model_meters_per_unit is the meters per UT unit at which the model was converted (tools/asset_conversion/convert_weapon.py).
		-- meters_per_unit is the distance scale: the meters of forward in the view that one UT unit of the model takes up.
		model_meters_per_unit = 0.0125,
		meters_per_unit = 0.01,
		-- LinkGun.uc: DisplayFOV, PlayerViewOffset and PlayerViewPivot
		display_fov = 60,
		draw_scale = 1,
		offset_forward = -5,
		offset_right = -3,
		offset_up = 0,
		pivot_yaw = 500 / 65536 * 360,
		bob_damping = 1.575,
		-- UT's third person mesh (LinkAttachment's NewLinkGun_3rd) at UT's size in a player's hand (DrawScale 0.4). Its origin is by its
		-- grip, and its barrel runs along its forward to the muzzle (its upper flash bone).
		third_person = third_person_of(setting_id, "units/ut/link/third_person", 75.5, 8.9),
		looks = {
			-- These come from LinkGun.uc with bUseOldWeaponMesh: OldMesh, OldPlayerViewOffset and OldPlayerViewPivot. Weapon.RenderOverlays
			-- draws it at OldDrawScale, which is 1.
			[definition.key .. "_skin_2003"] = {
				unit_name = "units/ut/link2003/link_gun",
				animations = animations_2003,
				muzzle_node = "b_bone_flasha",
				draw_scale = 1,
				offset_forward = -2,
				offset_right = -2,
				offset_up = -3,
				pivot_yaw = 500 / 65536 * 360,
				third_person = third_person_of(setting_id, "units/ut/link2003/third_person", 99.2, 2.5),
			},
		},
		on_create = function ()
			api.play_sound("ut_link_select")
		end,
	})

	skin_apis[#skin_apis + 1] = api
end

for _, setting_id in ipairs(VARIANTS) do
	new_skin(setting_id)
end

-- The bolts

-- These flow events would start the game's effects on the projectile, so they are dropped
mod.init_flow_event_filters.link_new = function (event_name)
	return event_name == "lua_projectile_init" or event_name == "lua_trail" or event_name == "vfx_critical_strike"
end

-- The bolts in flight, each { unit = the game's projectile, extension, position and way (boxes: where it is, and the way it flies),
-- color, sound }
local bolts = {}

-- A shot by another player, as seen on this machine: the flash and the sound come from the mesh in their hand, once for the bolt of a shot
local remote_shots = utils.shot_grouping(CONFIG.shot_gap)

-- Adds a bolt on every machine: a green blob and its glow follow the game's projectile, gold with links (LinkAdjust), and its hum
-- (LinkProjectile's AmbientSound). For the player's own shot this also plays the animation, the flash and the sound. For another
-- player's it plays the flash and the sound from their mesh.
mod.skin_init_callbacks.link_new_bolt = function (projectile)
	local game_unit = projectile._projectile_unit
	local owner_unit = projectile._owner_unit
	local links = projectile._current_action and projectile._current_action.ut_link_new_links or 0
	local color = links > 0 and CONFIG.linked_color or CONFIG.bolt_color

	Unit.set_unit_visibility(game_unit, false)

	local bolt = {
		unit = game_unit,
		extension = projectile,
		position = Vector3Box(Unit.world_position(game_unit, 0)),
		way = Vector3Box(Quaternion.forward(Unit.world_rotation(game_unit, 0))),
		color = color,
		sound = utils.play_on_unit("ut_link_projectile_3d", game_unit),
	}

	bolts[#bolts + 1] = bolt

	local function follow()
		if Unit.alive(game_unit) and not projectile._stop_impacts then
			return Unit.world_position(game_unit, 0)
		end
	end

	particles.sprite({
		color = color,
		fade_in = 0,
		follow = follow,
		life = 10,
		size = CONFIG.bolt_size * UNIT,
		spin = 0.2,
		texture = links > 0 and "link_muz_yellow" or "link_muz_green",
	})
	particles.sprite({
		color = color,
		fade_in = 0,
		follow = follow,
		intensity = 0.5,
		life = 10,
		size = CONFIG.bolt_glow_size * UNIT,
		texture = "muzzle_white",
	})

	-- (a bolt that a shield reflected is not a shot)
	if projectile._ut_reflected_by then
		return
	end

	if utils.is_local_player_unit(owner_unit) then
		local api = first_person_api()

		if api then
			if not api.third_person.shows_weapon(owner_unit) then
				api.play("Fire", api.animation_duration("Fire") / CONFIG.fire_animation_rate)
			end

			api.play_sound(links > 0 and "ut_link_linked" or "ut_link_fire")
		end

		muzzle_flash(owner_unit)
	elseif remote_shots.is_new_shot(owner_unit) then
		local muzzle, holder = held_muzzle(owner_unit)

		if muzzle then
			muzzle_flash(owner_unit)
			holder.play_sound_at("ut_link_fire_3d", muzzle)
		end
	end
end

-- Follows the bolts, and puts sparks where one ends (LinkProjectile.Explode: LinkProjSparks, yellow with links)
local function update_bolts()
	for i = #bolts, 1, -1 do
		local bolt = bolts[i]
		local alive = Unit.alive(bolt.unit) and not bolt.extension._stop_impacts

		if alive then
			local position = Unit.world_position(bolt.unit, 0)
			local moved = position - bolt.position:unbox()

			if Vector3.length(moved) > 0.001 then
				bolt.way:store(Vector3.normalize(moved))
			end

			bolt.position:store(position)
		else
			-- (UT throws them along the normal of what the bolt hit: here back the way the bolt came)
			local texture = bolt.color == CONFIG.bolt_color and "link_spark_green" or "link_spark_yellow"

			for _ = 1, BOLT_SPARKS.count do
				throw_spark(BOLT_SPARKS, bolt.position:unbox(), -bolt.way:unbox(), texture, 1, 1, 1)
			end

			if bolt.sound and Managers.world:has_world("level_world") then
				utils.stop_sound(bolt.sound)
			end

			table.remove(bolts, i)
		end
	end
end

-- The beams

-- The sound of each beam that is drawn, by its character: { the player's own (an id of the skin's play_sound) or another's on their
-- character (a handle of utils.play_on_unit), api }
local beam_sounds = {}

local function stop_beam_sound(character)
	local entry = beam_sounds[character]

	beam_sounds[character] = nil

	if not entry or not Managers.world:has_world("level_world") then
		return
	end

	if entry.id then
		entry.api.stop_sound(entry.id)
	else
		utils.stop_sound(entry.handle)
	end
end

-- The look of each beam that is drawn, by its character: the wave's amplitude (UT units), phase and spin (radians), where the beam started
-- and the way it aimed a frame ago, the beam's lines (the beam and its children: their points and segments), and the time carried over
-- to the next spark, flash and disc
local visuals = {}

local function turns_to_radians(turns)
	return turns / 65536 * 2 * math.pi
end

-- The beam's color: the texture and the textures of its flashes and sparks
local function colors_of(linking, links)
	if linking then
		return "link_beam_blue", "link_muz_blue", nil
	elseif links > 0 then
		return "link_beam_yellow", "link_muz_yellow", "link_spark_yellow"
	end

	return "link_beam_green", "link_muz_green", "link_spark_green"
end

-- Keeps a line's segments: one particle for each stretch between two of its points, which follows those points every frame and ends
-- when the line has fewer points, or when its look changes (version)
local function draw_line(visual, line, texture, size, color)
	if line.texture ~= texture or line.size ~= size then
		line.texture = texture
		line.size = size
		line.version = (line.version or 0) + 1
		line.made = 0
	end

	line.made = math.min(line.made, line.count - 1)

	for i = line.made + 1, line.count - 1 do
		local version = line.version

		particles.beam({
			color = { color, color, color },
			fade_in = 0,
			life = math.huge,
			size = size,
			texture = texture,
			track = function ()
				if visual.alive and line.version == version and i < line.count then
					return line.points[i]:unbox(), line.points[i + 1]:unbox()
				end
			end,
		})
	end

	line.made = math.max(line.made, line.count - 1)
end

-- Puts a line's points along the beam: from the start along the bend to the end, every regen_dist, moved across by the wave. lock_end
-- holds the end still (mWaveLockEnd), and the start always is.
local function place_line(line, start, control, finish, length, regen_dist, amplitude, phase, wave_axis, lock_end)
	local count = math.max(2, math.ceil(length / (regen_dist * UNIT)) + 1)

	line.points = line.points or {}
	line.count = count

	for i = 1, count do
		local share = (i - 1) / (count - 1)
		local along = (1 - share) * (1 - share) * start + 2 * share * (1 - share) * control + share * share * finish
		local envelope = lock_end and math.sin(math.pi * share) or math.sin(math.pi * share * 0.5)
		local wave = amplitude * UNIT * envelope * math.sin(BEAM.wave_frequency * share * length / UNIT + phase)
		local point = along + wave_axis * wave

		if line.points[i] then
			line.points[i]:store(point)
		else
			line.points[i] = Vector3Box(point)
		end
	end
end

-- Draws one character's beam for a frame (LinkBeamEffect.Tick)
local function draw_beam(character, beam, dt)
	local start, scale = muzzle_of(character)

	if not start then
		return
	end

	scale = scale or UNIT

	local visual = visuals[character]

	if not visual then
		visual = {
			alive = true,
			amplitude = BEAM.wave_amplitude,
			phase = 0,
			spin = 0,
			previous_start = Vector3Box(start),
			previous_aim = Vector3Box(beam.aim:unbox()),
			lines = {},
			spark_time = 0,
			flash_time = 0,
			sphere_time = 0,
		}
		visuals[character] = visual
	end

	local links = link.links_of(character)
	local link_scale = BEAM.link_scale[math.min(links, 5) + 1]
	local linking = link.locked[character] ~= nil
	local locked_on = beam.hit == 2
	local aim = beam.aim:unbox()
	local finish = beam.end_position:unbox()
	local beam_direction = Vector3.normalize(finish - start)

	if linking then
		finish = finish - beam_direction * (BEAM.linked_end_back * UNIT)
	end

	-- The wave dies down on an enemy or a link, and otherwise grows with how much the gun moves and turns, and dies down slowly
	if locked_on or linking then
		visual.amplitude = math.max(0, visual.amplitude - (visual.amplitude + 5) * 4 * dt)
	else
		local moved = (start - visual.previous_start:unbox()) / UNIT
		local location_change = Vector3.length(Vector3(Vector3.x(moved), Vector3.y(moved), Vector3.z(moved) * 5))
		local rotation_change = Vector3.length(aim - visual.previous_aim:unbox())
		local wiggle = math.max(location_change * 0.02, rotation_change * 4)

		visual.amplitude = math.max(1, visual.amplitude - visual.amplitude * dt)
		visual.amplitude = math.min(BEAM.max_amplitude, visual.amplitude + wiggle)
	end

	visual.previous_start:store(start)
	visual.previous_aim:store(aim)
	visual.phase = visual.phase + turns_to_radians(BEAM.wave_shift * (link_scale * 0.6 + 1)) * dt
	visual.spin = visual.spin + turns_to_radians(BEAM.spin) * dt

	-- The plane of the wave, about the beam
	local chord = finish - start
	local length = Vector3.length(chord)
	local side = Vector3.cross(beam_direction, Vector3.up())

	if Vector3.length(side) < 0.1 then
		side = Vector3.right()
	end

	side = Vector3.normalize(side)

	local up = Vector3.cross(side, beam_direction)
	local wave_axis = side * math.cos(visual.spin) + up * math.sin(visual.spin)
	local control = start + aim * (length * BEAM.bend_share)
	local beam_texture, flash_texture, spark_texture = colors_of(linking, links)

	-- The beam, and its children, each thinner, with a wider wave of their own
	local children = math.min(links + 1, BEAM.max_children)
	local main = visual.lines[1] or {}

	visual.lines[1] = main

	place_line(main, start, control, finish, length, BEAM.regen_dist, visual.amplitude, visual.phase, wave_axis, locked_on or linking)
	draw_line(visual, main, beam_texture, BEAM.size * (link_scale * 0.6 + 1) * UNIT, BEAM.color)

	for c = 1, BEAM.max_children do
		local line = visual.lines[c + 1] or {}

		visual.lines[c + 1] = line

		if c <= children then
			local amplitude = c * 4 + visual.amplitude * ((BEAM.max_amplitude - c * 4) / BEAM.max_amplitude)

			place_line(line, start, control, finish, length, BEAM.child_regen_dist, amplitude, visual.phase * 0.6, wave_axis, linking)
			draw_line(visual, line, beam_texture, (2 + 4 * (children - c + 1)) * UNIT, BEAM.child_color)
		else
			line.count = 0
			line.made = 0
		end
	end

	-- The sparks where it ends, but not on a link: back toward the shooter from what it hits, or on from its end in the air
	if spark_texture then
		visual.spark_time = visual.spark_time + dt * SPARKS.rate * (link_scale + 1)

		local spark_place = finish - beam_direction * (10 * UNIT)
		local spark_way = beam.hit > 0 and -aim or beam_direction

		while visual.spark_time >= 1 do
			visual.spark_time = visual.spark_time - 1

			throw_spark(SPARKS, spark_place, spark_way, spark_texture, link_scale + 1, link_scale * 0.7 + 1, link_scale + 1)
		end
	end

	-- The flash at the muzzle: the mesh's in a character's hand, or the player's own model's for every hit
	local first_person = utils.is_local_player_unit(character) and first_person_api() and not first_person_api().third_person.shows_weapon(character)
	local flash_scale = link_scale * 0.5 + 1
	local function follow_muzzle()
		return visual.alive and (muzzle_of(character)) or nil
	end

	if first_person then
		visual.flash_time = visual.flash_time - dt

		if visual.flash_time <= 0 then
			visual.flash_time = visual.flash_time + FLASH_1ST.interval

			particles.sprite({
				attenuation = 0,
				color = { FLASH_1ST.color, FLASH_1ST.color, FLASH_1ST.color },
				follow = follow_muzzle,
				life = FLASH_1ST.life,
				size = FLASH_1ST.size * flash_scale * scale,
				spin = (math.random() * 2 - 1) * 0.3,
				texture = flash_texture,
			})
		end
	else
		visual.flash_time = visual.flash_time + dt * FLASH_3RD.rate

		while visual.flash_time >= 1 do
			visual.flash_time = visual.flash_time - 1

			particles.sprite({
				color = { FLASH_3RD.color, FLASH_3RD.color, FLASH_3RD.color },
				follow = follow_muzzle,
				life = FLASH_3RD.life,
				size = random_between(FLASH_3RD.size) * flash_scale * scale,
				spin = (math.random() * 2 - 1) * 0.3,
				texture = flash_texture,
			})
		end
	end

	-- The sphere on an ally who is linked
	local target = link.locked[character]

	if target then
		visual.sphere_time = visual.sphere_time + dt * SPHERE.rate

		local size = utils.is_local_player_unit(target) and SPHERE.own_size or SPHERE.size

		while visual.sphere_time >= 1 do
			visual.sphere_time = visual.sphere_time - 1

			particles.sprite({
				color = { SPHERE.color, SPHERE.color, SPHERE.color },
				follow = function ()
					return visual.alive and beam.end_position:unbox() or nil
				end,
				life = SPHERE.life,
				size = size * UNIT,
				spin = (math.random() * 2 - 1) * 0.3,
				texture = "link_muz_blue",
			})
		end
	end
end

-- Draws each beam, and loops its sound (LinkFire's BeamSounds) while it is drawn
local function draw_beams(dt)
	for character, beam in pairs(link.beams) do
		if Unit.alive(character) then
			draw_beam(character, beam, dt)

			if not beam_sounds[character] then
				local api = first_person_api()

				if utils.is_local_player_unit(character) and api then
					beam_sounds[character] = { id = api.play_sound("ut_link_beam"), api = api }
				else
					beam_sounds[character] = { handle = utils.play_on_unit("ut_link_beam_3d", character) }
				end
			end
		end
	end

	for character, visual in pairs(visuals) do
		if not link.beams[character] then
			visual.alive = false
			visuals[character] = nil
		end
	end

	for character in pairs(beam_sounds) do
		if not link.beams[character] then
			stop_beam_sound(character)
		end
	end
end

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	if not Managers.world:has_world("level_world") then
		return
	end

	update_bolts()
	draw_beams(dt)
end

local function clear()
	for character in pairs(beam_sounds) do
		stop_beam_sound(character)
	end

	for _, visual in pairs(visuals) do
		visual.alive = false
	end

	table.clear(visuals)

	for _, bolt in ipairs(bolts) do
		if bolt.sound and Managers.world:has_world("level_world") then
			utils.stop_sound(bolt.sound)
		end
	end

	table.clear(bolts)
	remote_shots.clear()
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = clear
mod.disabled_callbacks[#mod.disabled_callbacks + 1] = clear
mod.unload_callbacks[#mod.unload_callbacks + 1] = clear

-- The base's own shot, reload and zoom animations are not played on the player's own first person unit: the skin's model plays UT's.
-- The characters' shot animation would have the base's unit play its shot sound and flash: the skin plays UT's.
for template_name in pairs(TEMPLATE_NAMES) do
	mod.first_person_animation_filters[template_name] = function (event)
		local actions = Weapons[template_name] and Weapons[template_name].actions
		local shot = actions and actions.action_one and actions.action_one.default

		return shot ~= nil and (event == shot.anim_event or event == shot.anim_event_last_ammo) or string.find(event, "reload", 1, true) ~= nil or string.find(event, "zoom", 1, true) ~= nil
	end

	mod.third_person_animation_filters[template_name] = function (event)
		return string.find(event, "reload", 1, true) ~= nil
	end

	mod.third_person_weapons_hidden_from_flow[template_name] = true
end
