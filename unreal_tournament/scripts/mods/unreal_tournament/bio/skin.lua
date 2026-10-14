local mod = get_mod("unreal_tournament")

-- Bio Rifle skin: how UT2004's Bio Rifle looks and sounds.
--
-- weapon_skin.lua does the model, its placement and animations, the bob and the third person. This file does what is the Bio Rifle's own:
-- the flash, the globs in flight, their splash, the globs that have landed and the sounds. The gameplay is in bio_rifle.lua. This file only draws it, and
-- is told what happens through the hook tables in hooks.lua.
--
-- The game's units of the globs still fly, since they are the gameplay. Their own effects are dropped, and UT's are drawn at them: a green
-- blob (sprites of the GoopMesh texture), the splash (GoopSmoke and GoopSparks) and the splat (BioDecal) that a landing glob leaves.
--
-- The assets were made with tools/asset_conversion.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local animations = mod:dofile("scripts/mods/unreal_tournament/bio/skin_animations")
local particles = mod.skin_particles

local TEMPLATE_NAME = mod.items.weapons.bio_rifle.template
local SETTING_ID = "bio_rifle"

local CONFIG = {
	meters_per_uu = 0.02, -- meters in one Unreal unit of the world (a player is 88 units high)
	-- BioMuzFlash1st is a flash that lasts 0.1 to 0.15 s, at 0.6 to 0.8 of a mesh. Here it is a sprite.
	muzzle_size = 50,
	muzzle_growth = 120,
	muzzle_life = 0.12,
	muzzle_color = {
		0.5,
		1,
		0.3,
	},
	-- The glob is UT's own mesh, GoopMesh, made by tools/asset_conversion/make_goop_mesh.py. Every frame of its animations is a unit of
	-- its own (units/ut/fx/goop/f<number of the frame>). Its material is the panning goop texture (fx_goop). The mesh is scaled by the
	-- glob's volume. The
	-- animations (XWeapons_rc/BioRifle_rc.uc) are Flying (frames 3 to 13, looped), Hit (20 to 37), Drip (40 to 78) and Slide (83 to
	-- 121). The frame rate is 30 a second. It is not in the source, but the Drip animation, 39 frames at the 0.66 speed that BioGlob
	-- plays it at, then takes 2 seconds, which is DripTime.
	goop_unit_format = "units/ut/fx/goop/f%d",
	goop_material = "units/ut/fx/fx_goop",
	goop_frame_rate = 30,
	-- The light of a glob of volume 1 (the light is steady, and bigger for a bigger glob). Its color is UT's LightHue 82, a pale green.
	light_color = { 0.3, 1, 0.3 },
	light_falloff = 0.7, -- m
	light_intensity = 0.2,
	-- The goop is see through and glows. UT draws it as FB_Translucent, which adds its color to the screen. goop_additive is how much of it is added
	-- (1) and how much is blended by goop_opacity (0). The color of the texture is made brighter by goop_brightness.
	goop_opacity = 0.8,
	goop_additive = 0.5,
	goop_brightness = 1.3,
	goop_animations = {
		drip = { start = 40, count = 39, speed = 0.66 },
		flying = { start = 3, count = 11 },
		hit = { start = 20, count = 18 },
		slide = { start = 83, count = 39 },
	},
	glob_color = {
		0.55,
		1,
		0.35,
	},
	-- GoopSmoke is 10 slow green puffs, 20 to 30 units wide, lasting 1 to 2 s. GoopSparks is 10 sparks 4 units wide, lasting 0.5 to
	-- 0.8 s, moving 80 to 240 units a second.
	-- Both are made along the rotation of the glob (the way a landed glob faces, or the way a flying one goes), spread by a deviation
	-- (mDirDev) of this much on each axis. The puffs start within mPosDev of the glob, 8 units on each axis.
	burst_puff_direction_spread = 0.25,
	burst_spark_direction_spread = 0.8,
	burst_puff_position_spread = 8,
	burst_puffs = 6,
	burst_puff_size = {
		20,
		30,
	},
	burst_puff_life = {
		1,
		2,
	},
	burst_puff_speed = {
		20,
		80,
	},
	burst_puff_color = {
		0.1,
		0.55,
		0.1,
	},
	burst_sparks = 8,
	burst_spark_size = 6,
	-- GoopSparks have an air resistance of 2. A streak is this many seconds of the spark's speed long.
	burst_spark_drag = 2,
	burst_spark_length = 0.06,
	burst_spark_life = {
		0.5,
		0.8,
	},
	burst_spark_speed = {
		80,
		240,
	},
	-- BioDecal is the splat that a landing glob leaves on the surface. It is the same size for every glob, and it lasts 6 seconds
	-- (LifeSpan).
	-- The decal's box is this wide and this deep, in meters (the game's blood decals are 2.5 wide and 1 deep). It is a guess.
	splat_unit = "units/ut/fx/decal_bio",
	splat_size = 1.2,
	splat_depth = 1,
	splat_life = 6,
	splat_pool_size = 30,
	-- BioGlob.AnimEnd picks the animation of a glob that has landed from the way its surface faces (the surface normal dotted with straight
	-- down): above ceiling_dot it is a ceiling and the glob drips, above wall_dot it is a wall and the glob slides.
	ceiling_dot = 0.7,
	wall_dot = -0.5,
	-- Globs of another player that start less than this far apart (in seconds) belong to the same shot
	shot_gap = 0.1,
}

local UNIT = CONFIG.meters_per_uu

local skin_api

local function random_between(range)
	return range[1] + (range[2] - range[1]) * math.random()
end

-- The globs that have landed, as { position, normal (boxes), level, token } for each id. A glob that is gone or has changed gets a new
-- token, and the sprite of the old one stops by itself when it asks for its place and finds a different token.
local landed = {}

-- Shows a flash at the muzzle, either of the mesh in the character's hand or of the model in the player's own view.
local function muzzle_flash(follow, scale)
	particles.sprite({
		color = CONFIG.muzzle_color,
		follow = follow,
		growth = CONFIG.muzzle_growth * scale,
		life = CONFIG.muzzle_life,
		size = CONFIG.muzzle_size * scale,
		spin = (math.random() * 2 - 1) * 0.2,
		texture = "muzzle_white",
	})
end

-- A shot by another player, as seen on this machine: the flash and the sound come from the end of the barrel of the mesh in their
-- hand. They play once for all the globs of a shot that start together.
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
		skin_api.play_sound_at("ut_bio_fire_3d", muzzle)
	end
end

skin_api = mod.weapon_skin.new({
	id = SETTING_ID,
	name = "bio",
	template = TEMPLATE_NAME,
	unit_name = "units/ut/bio/bio_rifle",
	animations = animations,
	muzzle_node = "b_bone_flash",
	model_meters_per_unit = 0.0125,
	meters_per_unit = 0.01,
	-- BioRifle.uc
	display_fov = 60,
	draw_scale = 1,
	offset_forward = 7,
	offset_right = 3,
	offset_up = 0,
	bob_damping = 2.2,
	-- WeaponStaticMesh.BioRiflePickup (DrawScale 0.6). Its nozzle runs along the mesh's own +Y, and the tank is behind it.
	third_person = {
		id = SETTING_ID,
		template = TEMPLATE_NAME,
		unit_name = "units/ut/bio/pickup",
		-- The game links the Masterwork Pistol to the right hand's node (AttachmentNodeLinking.steam_pistol).
		hand_node = "j_rightweaponattach",
		meters_per_unit = 0.012,
		scale = 0.6,
		grip_right = 14,
		grip_forward = 0,
		grip_up = -20,
		yaw = -90,
		pitch = 0,
		roll = 0,
		-- In the world the rifle follows the pistol's unit, which the arms animate.
		follow_game_unit = 1,
		follow_calibrate_seconds = 1,
		muzzle_right = -30,
		muzzle_forward = 0,
		muzzle_up = -10,
		menu_yaw = 0,
	},
	on_create = function ()
		skin_api.play_sound("ut_bio_select")
	end,
	on_give_back = function ()
		table.clear(landed)
	end,
	on_level_exit = function ()
		table.clear(landed)
		table.clear(last_remote_shot)
	end,
})

local third_person = skin_api.third_person

-- Handles a shot of the player: plays the animation and shows the flash. The sound is taken over below.
mod.crossbow_start_callbacks.bio_skin = function (action, new_action)
	local skin = skin_api.state()
	local owner_unit = action.owner_unit

	if not skin or not new_action.ut_bio_glob or not utils.is_local_player_unit(owner_unit) then
		return
	end

	local in_third_person = third_person.shows_weapon(owner_unit)

	skin_api.play("Fire")
	muzzle_flash(function ()
		if in_third_person then
			return third_person.muzzle_position(owner_unit)
		end

		return skin_api.state() == skin and skin_api.muzzle_position() or nil
	end, in_third_person and third_person.meters_per_unit or skin.unit_scale)
end

-- Charging the big glob draws the plunger back (UT's AltFire) and plays the power-up sound.
mod.charge_start_callbacks.bio_skin = function (action, new_action)
	local skin = skin_api.state()

	if skin and new_action.ut_charge_callback == "bio" and utils.is_local_player_unit(action.owner_unit) then
		skin_api.play("AltFire")
		skin_api.play_sound("ut_bio_charge")
	end
end

-- The shots use the game's sound event of the Sienna's fireball. The skin plays UT's sound instead.
skin_api.take_over_sound("player_combat_weapon_staff_fireball_fire", "ut_bio_fire")

-- The pistol's own animations of shooting and charging are not played. The skin's model plays UT's.
local MUTED_ANIMATIONS = {
	attack_charge = true,
	attack_shoot = true,
	attack_shoot_fast = true,
	attack_shoot_fast_last = true,
	attack_shoot_last = true,
	lock_target = true,
}

mod.first_person_animation_filters[TEMPLATE_NAME] = function (event)
	return MUTED_ANIMATIONS[event] == true
end

-- The pistol's unit plays its own sounds for these. The game's names for them are the pistol's.
local MUTED_SOUNDS = {
	Play_wpn_engineer_pistol_charge = true,
	Play_wpn_engineer_pistol_charge_stop = true,
	Play_wpn_engineer_pistol_last_bullet = true,
	player_combat_weapon_steampistol_fire = true,
	player_combat_weapon_steampistol_fire_fast = true,
}

mod.sound_event_filters[TEMPLATE_NAME] = function (event_name)
	return MUTED_SOUNDS[event_name] == true
end

-- These flow events would start the game's effects on the globs, so they are dropped.
mod.init_flow_event_filters.bio = function (event_name)
	return (event_name == "lua_projectile_init" or event_name == "lua_trail" or event_name == "vfx_critical_strike")
end

-- Returns the unit of the frame that an animation shows after it has played for this long. A looped animation starts over, and any
-- other holds its last frame.
local function goop_frame(animation_name, age, looped)
	local animation = CONFIG.goop_animations[animation_name]
	local frame = math.floor(age * CONFIG.goop_frame_rate * (animation.speed or 1))

	if looped then
		frame = frame % animation.count
	else
		frame = math.min(frame, animation.count - 1)
	end

	return CONFIG.goop_unit_format:format(animation.start + frame)
end

local GOOP_LIFE = 20

-- UT lights up what is around a glob: BioGlob has a steady light, whose brightness and radius grow with its level (SetGoopLevel).
local function goop_light(volume, follow)
	particles.light({
		brightness = function ()
			return 1
		end,
		color = CONFIG.light_color,
		falloff = CONFIG.light_falloff * volume,
		follow = follow,
		intensity = CONFIG.light_intensity * volume,
		life = GOOP_LIFE,
	})
end

-- Shows the goop's mesh. It is the unit of a frame, scaled by the glob's volume, with its material that pans. frame(age) names the unit
-- to show for the time since it started. follow keeps it where it is and ends it when it returns nothing.
local function goop_mesh(volume, rotation, follow, frame)
	particles.mesh({
		additive = CONFIG.goop_additive,
		angle = 0,
		brightness = function ()
			return 1
		end,
		color = {
			CONFIG.goop_brightness,
			CONFIG.goop_brightness,
			CONFIG.goop_brightness,
		},
		follow = follow,
		frame = function (fraction)
			return frame(fraction * GOOP_LIFE)
		end,
		intensity = CONFIG.goop_opacity,
		life = GOOP_LIFE,
		material = CONFIG.goop_material,
		rotation = rotation,
		scale = function ()
			return volume
		end,
		unit = frame(0),
	})
end

-- Adds a glob in the air on every machine. It is UT's mesh, playing its Flying animation, and it follows the game's unit. It is as big as
-- the glob's volume.
local function add_glob(projectile, volume)
	local game_unit = projectile._projectile_unit

	Unit.set_unit_visibility(game_unit, false)

	local function follow()
		if Unit.alive(game_unit) and not projectile._stop_impacts then
			return Unit.world_position(game_unit, 0)
		end
	end

	goop_light(volume, follow)
	goop_mesh(volume, Quaternion.identity(), follow, function (age)
		return goop_frame("flying", age, true)
	end)
end

-- A glob is as big as its volume, which is the square root of its goop level. The small globs that come off a landed glob, and the
-- glob that drips, are only drawn for the player who fired a shot. The other players hear and see the shot once.
mod.skin_init_callbacks.bio = function (projectile)
	local owner_unit = projectile._owner_unit
	local action = projectile._current_action

	add_glob(projectile, mod.bio_goop.volume_of_level(mod.bio_goop.level_of_scale(projectile.scale)))

	if action and action.ut_bio_shot and not utils.is_local_player_unit(owner_unit) then
		remote_shot(owner_unit)
	end
end

-- Returns a random vector in a box of the given half size on each axis.
local function random_box(spread)
	return Vector3((math.random() * 2 - 1) * spread, (math.random() * 2 - 1) * spread, (math.random() * 2 - 1) * spread)
end

-- Returns a direction that is the given one, deviated by up to the spread on each axis (xEmitter's mDirDev).
local function deviated(direction, spread)
	return Vector3.normalize(direction + random_box(spread))
end

-- Shows the splash of a glob: GoopSmoke and GoopSparks, as many as the size calls for. They go the way the glob was pointed, which is the
-- way the surface faces for a glob that landed.
local function splash(position, scale, direction)
	local puffs = math.max(2, math.floor(CONFIG.burst_puffs * scale + 0.5))
	local sparks = math.max(2, math.floor(CONFIG.burst_sparks * scale + 0.5))

	for _ = 1, puffs do
		local speed = random_between(CONFIG.burst_puff_speed) * UNIT

		particles.sprite({
			attenuation = 0.1,
			color = CONFIG.burst_puff_color,
			drag = 1.1,
			growth = 10 * UNIT,
			intensity = 1.4,
			life = random_between(CONFIG.burst_puff_life),
			position = position + random_box(CONFIG.burst_puff_position_spread * UNIT),
			size = random_between(CONFIG.burst_puff_size) * UNIT * scale,
			spin = (math.random() * 2 - 1) * 0.4,
			texture = "smoke",
			velocity = deviated(direction, CONFIG.burst_puff_direction_spread) * speed,
		})
	end

	-- GoopSparks are lines (PT_Line): each is a streak along the way the spark moves, as long as the spark is fast, with a glow at its
	-- front. The texture of a spark has both (see tools/asset_conversion/split_spark.py): the body is a beam from the tail to the head, and
	-- the head is a sprite at the head. The position of a spark is its start plus its velocity, which the air slows (drag), so it is worked
	-- out from how long the spark has been going.
	for _ = 1, sparks do
		local origin = Vector3Box(position)
		local start_velocity = deviated(direction, CONFIG.burst_spark_direction_spread) * (random_between(CONFIG.burst_spark_speed) * UNIT)
		local velocity_box = Vector3Box(start_velocity)
		local started = Application.time_since_launch()
		local drag = CONFIG.burst_spark_drag
		local width = CONFIG.burst_spark_size * UNIT * scale
		local life = random_between(CONFIG.burst_spark_life)

		-- Returns where the spark's head is, and where its tail is.
		local function spark()
			local age = Application.time_since_launch() - started
			local velocity = velocity_box:unbox()
			local speed = Vector3.length(velocity)
			local head = origin:unbox() + velocity * ((1 - math.exp(-drag * age)) / drag)
			local heading = speed > 0.001 and velocity * (1 / speed) or Vector3.up()
			local length = math.max(width, speed * math.exp(-drag * age) * CONFIG.burst_spark_length)

			return head, head - heading * length
		end

		particles.beam({
			attenuation = 0,
			color = CONFIG.glob_color,
			growth = -3 * UNIT,
			life = life,
			size = width,
			texture = "link_spark_green_body",
			track = function ()
				local head, tail = spark()

				return tail, head
			end,
		})
		particles.sprite({
			angle = 0,
			attenuation = 0,
			color = CONFIG.glob_color,
			follow = function ()
				return (spark())
			end,
			growth = -3 * UNIT,
			life = life,
			size = width,
			texture = "link_spark_green_head",
		})
	end
end

-- A glob explodes: the splash is as big as the glob's volume.
local function blast_effect(world, position, rotation, scale)
	local volume = mod.bio_goop.volume_of_level(mod.bio_goop.level_of_scale(scale))

	splash(position, volume, Quaternion.forward(rotation))
	skin_api.play_sound_at("ut_bio_splat_3d", position)
end

mod.skin_explosion_callbacks.ut_bio_blast = blast_effect
mod.skin_explosion_callbacks.ut_bio_blast_air = blast_effect

-- Returns a rotation that turns the goop's mesh to lie on a surface: its z axis is the way the surface faces, and its x axis (the way it
-- slides) is as close to straight up as the surface allows. The mesh is made with UT's x axis along this game's y.
local function surface_rotation(normal)
	local up = Vector3.up()
	local along = up - normal * Vector3.dot(up, normal)

	if Vector3.length(along) < 0.1 then
		along = Vector3.forward() - normal * Vector3.dot(Vector3.forward(), normal)
	end

	return Quaternion.look(Vector3.normalize(along), normal)
end

-- Draws a glob that has landed: UT's mesh on the surface, as big as the glob's volume. It plays Hit, and then Drip on a ceiling, Slide on
-- a wall, or nothing on a floor (BioGlob.AnimEnd). It is drawn until the glob is gone or changes.
local function show_landed(id)
	local entry = landed[id]
	local token = {}
	local normal = entry.normal:unbox()
	local dot = Vector3.dot(normal, Vector3.down())
	local after_hit = dot > CONFIG.ceiling_dot and "drip" or dot > CONFIG.wall_dot and "slide" or nil
	local hit_time = CONFIG.goop_animations.hit.count / CONFIG.goop_frame_rate

	entry.token = token

	local volume = mod.bio_goop.volume_of_level(entry.level)

	goop_light(volume, function ()
		if landed[id] and landed[id].token == token then
			return entry.position:unbox() + entry.normal:unbox() * (0.2 * volume)
		end
	end)
	goop_mesh(volume, surface_rotation(normal), function ()
		if landed[id] and landed[id].token == token then
			return entry.position:unbox()
		end
	end, function (age)
		if age < hit_time or not after_hit then
			return goop_frame("hit", age, false)
		end

		return goop_frame(after_hit, age - hit_time, false)
	end)
end

-- The splat is a projected decal of the game's own decal manager, like the game's blood: the manager draws it onto the surfaces under
-- its box, so it follows walls, corners and floors. The decal's unit has a pool of its own in DecalSettings.
local DECAL_POOL = "ut_bio"

DecalSettings[DECAL_POOL] = {
	life_time = CONFIG.splat_life,
	pool_size = CONFIG.splat_pool_size,
	units = {
		CONFIG.splat_unit,
	},
}

-- A manager that was made before the mod was loaded, or reloaded, does not have the pool, so it is added to it.
mod:hook_safe(DecalManager, "init", function (self)
	self._ut_bio_pool = true
end)

-- Puts a splat on the surface at a position, turned at random about the way the surface faces.
local function add_splat(position, normal)
	local manager = Managers.state and Managers.state.decal

	if not manager then
		return
	end

	if not manager._ut_bio_pool then
		EngineOptimizedManagers.decal_manager_add_setting(manager._decal_system, DECAL_POOL, CONFIG.splat_life, CONFIG.splat_pool_size, CONFIG.splat_unit)

		manager._ut_bio_pool = true
	end

	local side = Vector3.cross(normal, Vector3.up())

	if Vector3.length(side) < 0.1 then
		side = Vector3.cross(normal, Vector3.right())
	end

	side = Vector3.normalize(side)

	local tangent = Quaternion.rotate(Quaternion.axis_angle(normal, math.random() * math.pi * 2), side)

	-- As the game's blood decals are placed: the rotation looks along the tangent with the normal up, and the extents are the width, the
	-- length and the depth. (The unit is made for it, see tools/asset_conversion/make_decal_unit.py.)
	manager:add_projection_decal(CONFIG.splat_unit, nil, nil, position, Quaternion.look(tangent, normal), Vector3(CONFIG.splat_size, CONFIG.splat_size, CONFIG.splat_depth), normal)
end

-- A glob lands. The splat stays where it is for its own time, and the blob stays until the glob is gone.
mod.goop_visual_callbacks.land = function (id, position, normal, level)
	landed[id] = {
		level = level,
		normal = Vector3Box(normal),
		position = Vector3Box(position),
	}

	show_landed(id)
	skin_api.play_sound_at("ut_bio_splat2_3d", position)
	add_splat(position, normal)
end

-- Another glob lands in a glob that is there. It is drawn again at the size it has now.
mod.goop_visual_callbacks.merge = function (id, level)
	local entry = landed[id]

	if entry then
		entry.level = level

		show_landed(id)
		skin_api.play_sound_at("ut_bio_splat2_3d", entry.position:unbox())
	end
end

mod.goop_visual_callbacks.stop = function (id)
	landed[id] = nil
end
