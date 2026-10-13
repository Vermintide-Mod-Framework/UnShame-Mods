local mod = get_mod("unreal_tournament")

-- Bio Rifle skin: how UT2004's Bio Rifle looks and sounds.
--
-- weapon_skin.lua does the model, its placement and animations, the bob and the third person. This file does what is the Bio Rifle's own:
-- the flash, the globs in flight, their splash, the puddles and the sounds. The gameplay is in bio_rifle.lua. This file only draws it, and
-- is told what happens through the hook tables in hooks.lua.
--
-- The game's units of the globs still fly, since they are the gameplay. Their own effects are dropped, and UT's are drawn at them: a green
-- blob (sprites of the GoopMesh texture), the splash (GoopSmoke and GoopSparks) and the puddle (the splat of BioDecal).
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
	-- BioDecal is the splat that the puddle is (DrawScale 0.65 of its texture). Its size is the puddle's radius, and it lasts as long as
	-- the puddle.
	puddle_color = {
		0.45,
		1,
		0.3,
	},
	puddle_color_charged = {
		0.7,
		1,
		0.3,
	},
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

-- The puddles that are shown, as a token for each id. A puddle that ends or is shown again gets a new token, and the sprite of the old
-- one stops by itself when it asks for its place and finds a different token.
local puddles = {}

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
		-- The game links the Drakegun to the left hand's node (AttachmentNodeLinking.drakegun).
		hand_node = "j_leftweaponattach",
		meters_per_unit = 0.012,
		scale = 0.6,
		grip_right = 14,
		grip_forward = 0,
		grip_up = -20,
		yaw = -90,
		pitch = 0,
		roll = 0,
		-- In the world the rifle follows the Drakegun's unit, which the arms animate.
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
		table.clear(puddles)
	end,
	on_level_exit = function ()
		table.clear(puddles)
		table.clear(last_remote_shot)
	end,
})

local third_person = skin_api.third_person

-- Handles a shot of the player: plays the animation and shows the flash. The sound is taken over below.
mod.charged_projectile_start_callbacks.bio_skin = function (action, new_action)
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

-- The shots use the game's sound events of the Sienna's fireball and geiser. The skin plays UT's sound instead.
skin_api.take_over_sound("player_combat_weapon_staff_fireball_fire", "ut_bio_fire")
skin_api.take_over_sound("player_combat_weapon_staff_geiser_fire", "ut_bio_fire")

-- The Drakegun's own shot animations are not played. The skin's model plays UT's.
mod.first_person_animation_filters[TEMPLATE_NAME] = function (event)
	return event == "attack_shoot" or event == "attack_shoot_charged"
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

mod.skin_init_callbacks.bio = function (projectile)
	local owner_unit = projectile._owner_unit

	add_glob(projectile, math.max(projectile.scale or 1, 1))

	if not utils.is_local_player_unit(owner_unit) then
		remote_shot(owner_unit)
	end
end

-- The globs that come out of a bursting puddle are smaller.
mod.skin_init_callbacks.bio_child = function (projectile)
	add_glob(projectile, 0.6)
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

local function burst_effect(scale, sound)
	return function (world, position)
		splash(position, scale)
		skin_api.play_sound_at(sound, position)
	end
end

mod.skin_explosion_callbacks.ut_bio_burst = burst_effect(1, "ut_bio_splat_3d")
mod.skin_explosion_callbacks.ut_bio_child_burst = burst_effect(0.6, "ut_bio_splat2_3d")
mod.skin_explosion_callbacks.ut_bio_charged_burst = burst_effect(1.8, "ut_bio_splat_3d")
mod.skin_explosion_callbacks.ut_bio_charged_impact = burst_effect(2.2, "ut_bio_splat2_3d")

-- Puddles: the splat lies on the ground for as long as the puddle lasts, and is as wide as the puddle's radius.
mod.puddle_visual_callbacks.show = function (id, position, radius, charged, duration)
	local token = {}
	local place = Vector3Box(position + Vector3(0, 0, 0.03))

	puddles[id] = token

	particles.disc({
		color = charged and CONFIG.puddle_color_charged or CONFIG.puddle_color,
		fade_in = 0.15,
		fade_out = math.max(duration - 0.6, 0.2),
		follow = function ()
			if puddles[id] == token then
				return place:unbox()
			end
		end,
		intensity = 0.9,
		life = duration,
		normal = Vector3.up(),
		size = radius * 2,
		spin = 0.02,
		texture = "bio_splat",
	})
end

mod.puddle_visual_callbacks.stop = function (id)
	puddles[id] = nil
end

-- A bursting puddle shows a splash as big as its goo.
mod.puddle_visual_callbacks.burst = function (position, goo_scale)
	splash(position + Vector3(0, 0, 0.3), 1 + 1.2 * goo_scale)
	skin_api.play_sound_at("ut_bio_splat_3d", position)
end
