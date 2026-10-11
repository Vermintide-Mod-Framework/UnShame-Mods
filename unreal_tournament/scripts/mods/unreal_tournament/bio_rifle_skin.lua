local mod = get_mod("unreal_tournament")

-- Bio Rifle skin (the Weapon Skins setting): the Bio Rifle is UT2004's, in the player's own first person view and in the hand of every
-- character. The model (Weapons.BioRifle_1st: the tank, the plunger that moves as it is charged), its placement and animations, the bob
-- and the third person are weapon_skin.lua's; this file is what is the Bio Rifle's: the flash, the globs as they fly, their splash, the
-- puddles, and the sounds. The gameplay is bio_rifle.lua's, this only draws it differently, and is told what happens through the hook
-- tables of hooks.lua.
--
-- The game's own units of the globs are what flies (they are the gameplay), their effects are not started and what UT has is drawn at
-- them (a green blob, ShockProjectile-like: GoopMesh with the goop shader, here sprites of its texture); the burst is GoopSmoke and
-- GoopSparks, the puddle is the splat of BioDecal (the game's own look of a puddle is a fire).
--
-- The assets were made with unreal_tournament/tools/asset_conversion.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local animations = mod:dofile("scripts/mods/unreal_tournament/bio_rifle_skin_animations")
local particles = mod.skin_particles

local TEMPLATE_NAME = "drakegun_template_1"
local SETTING_ID = "bio_rifle"

local CONFIG = {
	meters_per_uu = 0.02, -- the Unreal unit of the world, in meters (a player is 88 units high)
	-- BioMuzFlash1st: a flash of 0.1 to 0.15 s, 0.6 to 0.8 of a mesh (here a sprite)
	muzzle_size = 50,
	muzzle_growth = 120,
	muzzle_life = 0.12,
	muzzle_color = {
		0.5,
		1,
		0.3,
	},
	-- BioGlob: DrawScale 1.2 of its mesh; the blob and its glow are sprites that follow it, as big as the glob's scale (a charged one is more)
	glob_size = 30,
	glob_glow_size = 55,
	glob_color = {
		0.55,
		1,
		0.35,
	},
	-- GoopSmoke (10 puffs of 20 to 30 units, 1 to 2 s, green, slow) and GoopSparks (10 sparks of 4 units, 0.5 to 0.8 s, 80 to 240 units a second)
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
	-- BioDecal: the splat that the puddle is (DrawScale 0.65 of its texture), the size of the puddle's radius; it lasts the puddle's time
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
	-- A shot that another player's machine sees: more than this far apart in time is another shot
	shot_gap = 0.1,
}

local UNIT = CONFIG.meters_per_uu

local skin_api

-- What the game's own sounds of the bursts are taken away for while the skin is on (the skin plays its own): { template, key, what it was }
local explosion_overrides = {
	{ "ut_bio_burst", "sound_event_name" },
	{ "ut_bio_charged_burst", "sound_event_name" },
	{ "ut_bio_child_burst", "sound_event_name" },
	{ "ut_bio_charged_impact", "sound_event_name" },
}

local function apply_template_overrides()
	local enabled = skin_api.enabled()

	for _, override in ipairs(explosion_overrides) do
		local explosion = ExplosionTemplates[override[1]].explosion
		local key = override[2]

		if enabled and explosion[key] then
			override[3] = explosion[key]
			explosion[key] = nil
		elseif not enabled and override[3] then
			explosion[key] = override[3]
			override[3] = nil
		end
	end
end

local function give_back_overrides()
	for _, override in ipairs(explosion_overrides) do
		if override[3] then
			ExplosionTemplates[override[1]].explosion[override[2]] = override[3]
			override[3] = nil
		end
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

-- The puddles that are shown, by id: the token of the one that is (a puddle that ends, or is shown again, is another token, and the sprite
-- of the old one stops by itself as it asks for its place)
local puddles = {}

-- A flash at the muzzle (where the character holds the mesh, or the model of the player's own view)
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

-- A shot that another player's machine sees: the flash and the sound from the end of the barrel of the mesh in their hand, once for the
-- globs of a shot that come together
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
	-- WeaponStaticMesh.BioRiflePickup (DrawScale 0.6): its nozzle is along the mesh's own +Y and the tank is behind it
	third_person = {
		id = SETTING_ID,
		template = TEMPLATE_NAME,
		unit_name = "units/ut/bio/pickup",
		-- (the game links the Drakegun to the left hand's node, AttachmentNodeLinking.drakegun)
		hand_node = "j_leftweaponattach",
		meters_per_unit = 0.012,
		scale = 0.6,
		grip_right = 14,
		grip_forward = 0,
		grip_up = -20,
		yaw = -90,
		pitch = 0,
		roll = 0,
		muzzle_right = -30,
		muzzle_forward = 0,
		muzzle_up = -10,
	},
	on_create = function ()
		skin_api.play_sound("ut_bio_select")
	end,
	on_refresh = apply_template_overrides,
	on_give_back = function ()
		give_back_overrides()
		table.clear(puddles)
	end,
	on_level_exit = function ()
		table.clear(puddles)
		table.clear(last_remote_shot)
	end,
})

local third_person = skin_api.third_person

-- A shot of the player: the animation, the flash (the sound is taken over below)
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

-- Charging for the big glob: the plunger is drawn back (UT's AltFire), and the sound of the power up
mod.charge_start_callbacks.bio_skin = function (action, new_action)
	local skin = skin_api.state()

	if skin and new_action.ut_charge_callback == "bio" and utils.is_local_player_unit(action.owner_unit) then
		skin_api.play("AltFire")
		skin_api.play_sound("ut_bio_charge")
	end
end

-- The shots' sounds are the game's events of the Sienna's fireball and geiser: the skin plays UT's
skin_api.take_over_sound("player_combat_weapon_staff_fireball_fire", "ut_bio_fire")
skin_api.take_over_sound("player_combat_weapon_staff_geiser_fire", "ut_bio_fire")

-- The shot animations of the Drakegun's first person unit are not played while the skin is on (the model of the skin plays UT's)
mod.first_person_animation_filters[TEMPLATE_NAME] = function (event)
	return skin_api.enabled() and (event == "attack_shoot" or event == "attack_shoot_charged")
end

-- The flow events of the game's units of the globs start their effects as they are made: not while the skin is on
mod.init_flow_event_filters.bio = function (event_name)
	return skin_api.enabled() and (event_name == "lua_projectile_init" or event_name == "lua_trail" or event_name == "vfx_critical_strike")
end

-- A glob (on every machine): a green blob and its glow follow the game's unit, as big as it is (a charged one is the scale of its charge)
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
	if not skin_api.enabled() then
		return
	end

	local owner_unit = projectile._owner_unit

	add_glob(projectile, math.max(projectile.scale or 1, 1))

	if not utils.is_local_player_unit(owner_unit) then
		remote_shot(owner_unit)
	end
end

-- (the globs of a puddle that bursts are smaller)
mod.skin_init_callbacks.bio_child = function (projectile)
	if skin_api.enabled() then
		add_glob(projectile, 0.6)
	end
end

-- The splash of a glob: GoopSmoke and GoopSparks, as many as the size says
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
		if not skin_api.enabled() then
			return
		end

		splash(position, scale)
		skin_api.play_sound_at(sound, position)
	end
end

mod.skin_explosion_callbacks.ut_bio_burst = burst_effect(1, "ut_bio_splat_3d")
mod.skin_explosion_callbacks.ut_bio_child_burst = burst_effect(0.6, "ut_bio_splat2_3d")
mod.skin_explosion_callbacks.ut_bio_charged_burst = burst_effect(1.8, "ut_bio_splat_3d")
mod.skin_explosion_callbacks.ut_bio_charged_impact = burst_effect(2.2, "ut_bio_splat2_3d")

-- The puddles: the splat lies on the ground for as long as the puddle lasts, as wide as its radius
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

-- A puddle that bursts: the splash, as big as the goo
mod.puddle_visual_callbacks.burst = function (position, goo_scale)
	splash(position + Vector3(0, 0, 0.3), 1 + 1.2 * goo_scale)
	skin_api.play_sound_at("ut_bio_splat_3d", position)
end
