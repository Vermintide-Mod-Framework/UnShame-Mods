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
	-- BioGlob has DrawScale 1.2 of its mesh. The blob and its glow are sprites that follow the glob and are as big as the glob's
	-- scale, and bigger for a charged glob.
	glob_size = 30,
	glob_glow_size = 55,
	glob_color = {
		0.55,
		1,
		0.35,
	},
	-- GoopSmoke is 10 slow green puffs, 20 to 30 units wide, lasting 1 to 2 s. GoopSparks is 10 sparks 4 units wide, lasting 0.5 to
	-- 0.8 s, moving 80 to 240 units a second.
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
	burst_spark_life = {
		0.5,
		0.8,
	},
	burst_spark_speed = {
		80,
		240,
	},
	-- BioDecal is the splat that a landing glob leaves on the surface. It is the same size for every glob, and it lasts 6 seconds
	-- (LifeSpan). The size is the width in meters, and it is a guess.
	splat_color = {
		0.45,
		1,
		0.3,
	},
	splat_size = 1.2,
	splat_life = 6,
	-- A glob that has landed is drawn as a blob, as big as a glob in the air times this much.
	landed_size_scale = 0.8,
	-- Globs of another player that start less than this far apart (in seconds) belong to the same shot
	shot_gap = 0.1,
}

local UNIT = CONFIG.meters_per_uu

local skin_api

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

-- Adds a glob on every machine: a green blob and its glow follow the game's unit. They are as big as the glob (a charged glob is as
-- big as its charge).
local function add_glob(projectile, scale)
	local game_unit = projectile._projectile_unit

	Unit.set_unit_visibility(game_unit, false)

	local function follow()
		if Unit.alive(game_unit) and not projectile._stop_impacts then
			return Unit.world_position(game_unit, 0)
		end
	end

	particles.sprite({
		color = CONFIG.glob_color,
		fade_in = 0,
		follow = follow,
		life = 20,
		size = CONFIG.glob_size * scale * UNIT,
		spin = 0.15,
		texture = "bio_goop",
	})
	particles.sprite({
		color = CONFIG.glob_color,
		fade_in = 0,
		follow = follow,
		intensity = 0.5,
		life = 20,
		size = CONFIG.glob_glow_size * scale * UNIT,
		texture = "muzzle_white",
	})
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

-- Shows the splash of a glob: GoopSmoke and GoopSparks, as many as the size calls for.
local function splash(position, scale)
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
			position = position,
			size = random_between(CONFIG.burst_puff_size) * UNIT * scale,
			spin = (math.random() * 2 - 1) * 0.4,
			texture = "smoke",
			velocity = random_direction() * speed,
		})
	end

	for _ = 1, sparks do
		local speed = random_between(CONFIG.burst_spark_speed) * UNIT

		particles.sprite({
			attenuation = 0,
			color = CONFIG.glob_color,
			drag = 2,
			growth = -3 * UNIT,
			life = random_between(CONFIG.burst_spark_life),
			position = position,
			size = CONFIG.burst_spark_size * UNIT * scale,
			texture = "link_spark_green",
			velocity = random_direction() * speed,
		})
	end
end

-- A glob explodes: the splash is as big as the glob's volume.
local function blast_effect(world, position, rotation, scale)
	local volume = mod.bio_goop.volume_of_level(mod.bio_goop.level_of_scale(scale))

	splash(position, volume)
	skin_api.play_sound_at("ut_bio_splat_3d", position)
end

mod.skin_explosion_callbacks.ut_bio_blast = blast_effect
mod.skin_explosion_callbacks.ut_bio_blast_air = blast_effect

-- Draws a glob that has landed: a blob on the surface, as big as the glob's volume. It is drawn until the glob is gone or changes.
local function show_landed(id)
	local entry = landed[id]
	local token = {}
	local volume = mod.bio_goop.volume_of_level(entry.level)

	entry.token = token

	particles.sprite({
		color = CONFIG.glob_color,
		fade_in = 0,
		follow = function ()
			if landed[id] and landed[id].token == token then
				return entry.position:unbox() + entry.normal:unbox() * (0.08 * volume)
			end
		end,
		life = 20,
		size = CONFIG.glob_size * volume * CONFIG.landed_size_scale * UNIT,
		spin = 0.15,
		texture = "bio_goop",
	})
end

-- A glob lands. The splat stays where it is for its own time, and the blob stays until the glob is gone.
mod.goop_visual_callbacks.land = function (id, position, normal, level)
	local center = Vector3Box(position + normal * 0.03)

	landed[id] = {
		level = level,
		normal = Vector3Box(normal),
		position = Vector3Box(position),
	}

	show_landed(id)
	skin_api.play_sound_at("ut_bio_splat2_3d", position)

	particles.disc({
		color = CONFIG.splat_color,
		fade_in = 0.1,
		fade_out = 1.5,
		follow = function ()
			return center:unbox()
		end,
		intensity = 0.9,
		life = CONFIG.splat_life,
		normal = normal,
		size = CONFIG.splat_size,
		spin = 0.02,
		texture = "bio_splat",
	})
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
