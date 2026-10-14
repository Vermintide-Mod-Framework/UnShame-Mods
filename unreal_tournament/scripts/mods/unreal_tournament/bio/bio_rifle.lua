local mod = get_mod("unreal_tournament")

-- Bio Rifle: a copy of Bardin's Masterwork Pistol with fire modes of its own. It follows UT2004's XWeapons/BioRifle, BioFire,
-- BioChargedFire and BioGlob.
--   LMB: lobs one glob of goop. It costs 1 ammo, and a glob can be fired every 0.33 seconds.
--   RMB (held): loads goop, 1 ammo at once and then 1 more every 0.25 seconds, up to 10. Releasing RMB fires one big glob, which has
--               as much goop as was loaded.
-- A glob that hits a player, a bot or an enemy while it flies explodes there. A glob that hits a surface sticks to it. Its goop level
-- is cut down to 2, 3 or 4, chosen at random for each glob, and what is above that is thrown off as small globs of 1 goop each. A
-- stuck glob explodes by itself after 2.25 seconds. It explodes 0.15 seconds after something steps into it, and 0.1 seconds after
-- an explosion of a rocket, a flak shell, a shock ball, a shock combo or another glob reaches it. A glob on a ceiling drips instead
-- of exploding: it falls after about 2.2 seconds and explodes where it lands. A glob that lands in a stuck glob joins it, up to a
-- level of 5, and what is above that is thrown off as small globs. An explosion does 20 + 19 damage for each level of goop, and it is
-- as wide as the level's square root times the radius of a level 1 glob.
-- The ammo is the clip, so there is no reload.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local with_valid_positions = utils.with_valid_positions
local register_damage_profile = utils.register_damage_profile
local register_explosion_template = utils.register_explosion_template
local make_flat = utils.make_flat
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for

mod.items.register("bio_rifle", {
	key = "ut_bio_rifle",
	template = "ut_bio_rifle_template",
	base_item = "dr_steam_pistol",
	deus_copy = "deus_dr_steam_pistol",
	name = "UT2004 Bio Rifle",
	type_name = "Bio Rifle",
	-- This is UT2004's description, shortened.
	description = "The GES Bio Rifle is one of the most controversial weapons in the Tournament, loved by some and loathed by others. It peppers an area with small globs of Biosludge, or launches one large glob at the target.",
	keywords = { "weapon_keyword_rapid_fire", "weapon_keyword_crowd_control", "weapon_keyword_charged_attack" },
	icon = "ut_bio_rifle_icon",
	icon_package = "resource_packages/unreal_tournament/icons",
	icon_materials = "ui/ut/bio_rifle_icon",
})

local TEMPLATE_NAME = mod.items.weapons.bio_rifle.template

local CONFIG = {
	-- Sizes and distances use UT's 0.02 m for each Unreal unit (uu). Speeds are 0.75 of that, so the globs are slower, and the gravity
	-- is lowered to match, which keeps the drop of a glob over a distance the same as in UT.
	meters_per_uu = 0.02,
	speed_scale = 0.75,
	gravity = -10.7, -- m/s^2, UT's 950 uu/s^2 (19 m/s^2) times speed_scale squared
	-- BioAmmo.MaxAmmo. All of it is the clip, so there is no reload.
	max_ammo = 50,
	-- BioFire: FireRate and the speed of BioGlob (Speed 2000 uu/s)
	fire_interval = 0.33,
	glob_speed_uu = 2000,
	-- Where a glob starts, measured from the camera: forward, to the right and down. UT's ProjSpawnOffset is 20, 9 and -6 uu. The
	-- pistol is drawn further out here, so the offsets are larger, to start the glob at the muzzle.
	start_forward = 0.8, -- m
	start_right = 0.25, -- m
	start_down = 0.15, -- m
	-- BioChargedFire: GoopUpRate, MaxGoopLoad and FireRate
	goop_up_rate = 0.25, -- seconds between two units of goop
	max_goop_load = 10,
	charged_fire_interval = 0.33,
	-- The release of the button fires the glob once this long has passed since the charge started.
	release_delay = 0.05, -- seconds
	-- BioGlob
	max_goop_level = 5, -- the level a glob that has landed can grow to
	base_damage = 20, -- BaseDamage
	level_damage = 19, -- Damage, which is added for each level of goop
	-- UT's damage is scaled down as the Rocket Launcher's and the Flak Cannon's explosions are (UT's 90 is 60 here), because the game's enemies
	-- are not UT's players.
	damage_scale = 60 / 90,
	-- DamageRadius is 120 uu. It is reduced to 80 uu here, the way the other weapons' explosions are, because a glob explodes a lot.
	blast_radius_uu = 80,
	-- The damage is the same up to this share of the radius and then falls off linearly to 0 at the radius. UT's falls off from the
	-- edge of the victim's body.
	blast_full_damage_share = 0.15,
	-- MomentumTransfer is 40000. Halved when the glob explodes in the air. Scaled by the volume of the glob, which is the square root of
	-- its level. This is the speed in m/s that the player who fired the glob is thrown at when it explodes at their feet.
	jump_speed = 4.6,
	-- The explosion hurts the player who fired the glob, as in UT. This is the share of the glob's damage that they take at the center.
	self_damage_share = 0.75,
	-- BioGlob.GloblingSpeed is 200 uu/s, plus up to 150 uu/s more. SplashGlobs multiplies it by (the surface's normal plus a random
	-- direction times 0.8).
	globling_speed_uu = { 200, 350 },
	globling_random_share = 0.8,
	-- How much of the speed of the glob that landed, reflected off the surface, a small glob takes with it
	globling_inherit_share = 0.1,
	-- BioGlob.RestTime, TouchDetonationDelay and DripTime. The delay of an explosion that is set off by an explosion is 0.1 seconds in
	-- BioGlob.TakeDamage.
	rest_time = 2.25,
	touch_detonation_delay = 0.15,
	drip_time = 1.8,
	detonation_delay = 0.1,
	-- A glob that drips starts with the gravity times 0.2 as its speed (190 uu/s).
	drip_speed_uu = 190,
	-- The glob's Hit animation plays when it lands. A glob on a ceiling starts to drip when the animation ends. The animation is 18 frames
	-- (BioRifle_rc.uc) at the frame rate of 30 a second, which the skin assumes (see goop_frame_rate in bio/skin.lua).
	hit_animation_time = 0.6,
	-- The collision of a glob that has landed is a cylinder, GoopVolume * 10 uu across. The collision of a glob in the air is 2 uu.
	collision_uu = 10,
	flying_collision_uu = 2,
	-- The height of the surface normal's down component above which a glob is on a ceiling (SurfaceNormal dot (0, 0, -1) > 0.7)
	ceiling_dot = 0.7,
	-- A glob that lands also leaves a splat on the surface (BioDecal), which stays for 6 seconds.
	-- The size of a character, for the globs that wait for someone to step in. UT's collision is 17 uu in radius and 88 uu high.
	pawn_radius_uu = 17,
	pawn_height_uu = 88,
	-- A glob that is still flying after this many seconds disappears. UT's LifeSpan is 20.
	max_flight = 8,
	-- The most globs that can wait on the surfaces at once. The oldest explodes when there are more.
	max_stuck = 40,
	-- A critical hit and the armor of an enemy do not exist in UT. These are how much of the damage and the stagger each armor type
	-- takes: unarmored, armored, monsters, players, berserkers and super armor. The game's own multipliers for explosions are 0 against
	-- super armor (chaos warriors), which would make them take nothing. The Bio Rifle is for denying an area and for swarms. Its many
	-- small hits do less against armor, so that it does not stand in for the weapons that pierce it.
	armor_attack = {1, 0.8, 1.5, 1, 1, 0.5},
	armor_impact = {1, 0.8, 1, 1, 1, 0.5},
	-- The game's sound event of the Sienna's fireball. The skin plays UT's sound instead.
	fire_sound = "player_combat_weapon_staff_fireball_fire",
}

local UNIT = CONFIG.meters_per_uu

-- The goop level of a glob is carried by the scale of its projectile. The scale goes from 0 to 1, and 0 is a level 1 glob. The blast
-- radius of a level is the radius of level 1 times the level's square root, so the scale is made to follow the square root.
local ROOT_MAX = math.sqrt(CONFIG.max_goop_load)

local function scale_of_level(level)
	return (math.sqrt(level) - 1) / (ROOT_MAX - 1)
end

local function level_of_scale(scale)
	local root = 1 + math.clamp(scale or 0, 0, 1) * (ROOT_MAX - 1)

	return math.clamp(math.floor(root * root + 0.5), 1, CONFIG.max_goop_load)
end

-- The scale is sent as a whole number from 0 to 100.
local function scale_to_send(level)
	return math.floor(scale_of_level(level) * 100 + 0.5)
end

-- What the skin needs to know about a glob
mod.bio_goop = {
	level_of_scale = level_of_scale,
	volume_of_level = function (level)
		return math.sqrt(level)
	end,
}

-- The damage of a glob of the level, in the units that the damage profiles use (UT's scaled by damage_scale).
local function blast_damage(level)
	return (CONFIG.base_damage + CONFIG.level_damage * level) * CONFIG.damage_scale
end

local REFERENCE_DAMAGE = blast_damage(CONFIG.max_goop_load)

-- The power level of a glob is the weapon's power level times this. The damage profiles are made for the biggest glob.
local function power_ratio(level)
	return blast_damage(level) / REFERENCE_DAMAGE
end

local function blast_radius(level)
	return CONFIG.blast_radius_uu * UNIT * math.sqrt(level)
end

local function glob_radius(level)
	return CONFIG.collision_uu * UNIT * math.sqrt(level)
end

-- The speed for the action or the projectile, in the unit that the game uses: m/s * 100
local function action_speed(speed_uu)
	return speed_uu * UNIT * CONFIG.speed_scale * 100
end

-- A charged glob is slower the more goop it has (BioGlob.AdjustSpeed).
local function charged_speed_uu(level)
	return CONFIG.glob_speed_uu * (0.4 + level) / (1.4 * level)
end

local GRAVITY_SETTINGS = "ut_bio_glob"

ProjectileGravitySettings[GRAVITY_SETTINGS] = CONFIG.gravity

utils.register_network_lookup("projectile_gravity_settings", GRAVITY_SETTINGS)

-- The globs that come off a landing glob, and the glob that drips, are an action of the weapon of their own. A projectile takes its
-- settings from its action by name, and the name is sent over the network, so it is registered.
local CHILD_ACTION_NAME = "action_one"
local CHILD_SUB_ACTION = "ut_bio_child"

utils.register_network_lookup("sub_actions", CHILD_SUB_ACTION)

-- A glob goes where the crosshair is. It has no spread.
local SPREAD_TEMPLATE = "ut_bio"

utils.zero_spread_template(SPREAD_TEMPLATE, "brace_of_pistols")

local function set_armor_modifiers(profile)
	utils.set_armor_modifiers(profile, CONFIG.armor_attack, CONFIG.armor_impact, true)
end

-- Damage profiles. The direct hit of a glob only staggers (UT has no damage from the hit itself, all of the damage is the explosion), and
-- does 1 damage so that it is not shown as blocked by armor.
register_damage_profile("ut_bio_glob", "staff_fireball", function (profile)
	make_flat(profile, utils.STAGGER_HIT_ATTACK_POWER, impact_power_for(CONFIG.level_damage * CONFIG.damage_scale))
	set_armor_modifiers(profile)

	profile.cleave_distribution = {
		attack = 0.01,
		impact = 0.01,
	}
end)

local function blast_profiles(name, damage)
	local function modify(profile)
		make_flat(profile, attack_power_for(damage), impact_power_for(damage))
		set_armor_modifiers(profile)
	end

	register_damage_profile(name, "fireball_charged_explosion", modify)
	register_damage_profile(name .. "_glance", "fireball_charged_explosion_glance", modify)
end

blast_profiles("ut_bio_blast", REFERENCE_DAMAGE)

-- Explosion templates. The scale of the explosion goes from 0 for a level 1 glob to 1 for a level 10 glob. The damage comes from the
-- power level that the explosion is made with (see power_ratio). The one in the air has half the momentum, so it throws the player
-- who fired it less (see blast_effects). The shooter is hurt separately.
local function blast_template(name)
	register_explosion_template(name, {
		explosion = {
			alert_enemies = true,
			alert_enemies_radius = 10,
			attacker_power_level_offset = 1,
			damage_profile = "ut_bio_blast",
			damage_profile_glance = "ut_bio_blast_glance",
			ignore_attacker_unit = true,
			max_damage_radius_max = blast_radius(CONFIG.max_goop_load) * CONFIG.blast_full_damage_share,
			max_damage_radius_min = blast_radius(1) * CONFIG.blast_full_damage_share,
			radius_max = blast_radius(CONFIG.max_goop_load),
			radius_min = blast_radius(1),
			use_attacker_power_level = true,
		},
	})
end

blast_template("ut_bio_blast")
blast_template("ut_bio_blast_air")

-- A glob that lands or runs out of time does nothing by itself. The mod handles the landing.
register_explosion_template("ut_bio_landing", {})

-- The Weapon template
-- The glob is one of the game's projectiles, the bolt of the drakefire pistols.
local PROJECTILE_UNIT_TEMPLATES = {
	"drake_pistol_shot",
}

local function enter_function(attacker_unit, input_extension)
	input_extension:clear_input_buffer()

	return input_extension:reset_release_input()
end

local function build_projectile_info()
	local projectile_info = table.clone(Projectiles.brace_of_drake_pistols_shot)

	projectile_info.gravity_settings = GRAVITY_SETTINGS
	projectile_info.life_time = CONFIG.max_flight + 1
	projectile_info.unit_life_time = CONFIG.max_flight + 1

	return projectile_info
end

-- The actions that can follow a shot. Either fire mode can be used once the fire rate has passed, and the button can be held.
local function fire_chain_actions(interval)
	return {
		{
			action = "action_wield",
			input = "action_wield",
			start_time = 0.2,
			sub_action = "default",
		},
		{
			action = "action_one",
			input = "action_one",
			start_time = interval,
			sub_action = "default",
		},
		{
			action = "action_one",
			input = "action_one_hold",
			start_time = interval,
			sub_action = "default",
		},
		{
			action = "action_two",
			input = "action_two_hold",
			start_time = interval,
			sub_action = "default",
		},
		{
			action = "weapon_reload",
			input = "weapon_reload",
			start_time = 0.3,
			sub_action = "default",
		},
	}
end

-- The fields that every glob's action has, whether the player fires it or it comes off a landed glob
local function glob_fields()
	return {
		kind = "crossbow",
		projectile_info = build_projectile_info(),
		speed = action_speed(CONFIG.glob_speed_uu),
		spread_template_override = SPREAD_TEMPLATE,
		ut_aoe_callback = "ut_bio_glob",
		ut_bio_glob = true,
		ut_hit_enemy_callback = "ut_bio_glob",
		ut_init_flow_event_filter = "bio",
		impact_data = {
			aoe = ExplosionTemplates.ut_bio_landing,
			damage_profile = "ut_bio_glob",
		},
		timed_data = {
			aoe = ExplosionTemplates.ut_bio_landing,
			life_time = CONFIG.max_flight,
		},
	}
end

-- The shot of a player: LMB fires a small glob, and releasing RMB fires the big one.
local function build_shot_action(charged)
	local interval = charged and CONFIG.charged_fire_interval or CONFIG.fire_interval
	local action = glob_fields()

	action.alert_sound_range_fire = 12
	action.alert_sound_range_hit = 2
	action.allowed_chain_actions = fire_chain_actions(interval)
	-- The ammo of the big glob was used while it was loaded.
	action.ammo_usage = charged and 0 or 1
	action.anim_event = "attack_shoot"
	action.anim_event_last_ammo = "attack_shoot"
	action.enter_function = enter_function
	action.fire_sound_event = CONFIG.fire_sound
	action.fire_time = 0
	action.total_time = interval
	action.ut_bio_charged = charged or nil
	action.ut_bio_shot = true
	action.ut_skin_init_callback = "bio"

	return action
end

-- The globs that come off a landed glob. They are not fired by the player.
local function build_child_action()
	local action = glob_fields()

	action.allowed_chain_actions = {}
	action.ammo_usage = 0
	action.total_time = 1
	action.ut_skin_init_callback = "bio"

	return action
end

-- The charge. The goop is loaded by the callbacks below. Releasing the button fires the big glob.
local function build_charge_action()
	return {
		allowed_chain_actions = {
			{
				action = "action_wield",
				input = "action_wield",
				start_time = 0,
				sub_action = "default",
			},
			{
				action = "action_one",
				auto_chain = true,
				release_required = "action_two_hold",
				start_time = CONFIG.release_delay,
				sub_action = "shoot_charged",
			},
		},
		charge_time = CONFIG.goop_up_rate * CONFIG.max_goop_load,
		-- The charge needs ammo to start, like UT's ModeHoldFire.
		condition_func = function (unit, input_extension, ammo_extension)
			return not ammo_extension or ammo_extension:total_remaining_ammo() > 0
		end,
		enter_function = enter_function,
		hold_input = "action_two_hold",
		kind = "charge",
		minimum_hold_time = 0.05,
		total_time = math.huge,
		ut_charge_callback = "bio",
		zoom_condition_function = function ()
			return false
		end,
	}
end

-- The template is shared game state, so it is patched in place. What is changed is saved, and it is put back when the mod is disabled
-- or unloaded.
local saved = {}

local AMMO_FIELDS = {
	"ammo_immediately_available",
	"ammo_per_clip",
	"ammo_per_reload",
	"max_ammo",
	"play_reload_anim_on_wield_reload",
	"reload_time",
	"should_update_anim_ammo",
}

local function restore_pistol()
	local original = saved.original
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not original or not template then
		return
	end

	local actions = template.actions

	actions.action_one.default = original.action_one_default
	actions.action_one.shoot_charged = original.action_one_shoot_charged
	actions[CHILD_ACTION_NAME][CHILD_SUB_ACTION] = nil
	actions.action_two.default = original.action_two_default
	template.default_spread_template = original.default_spread_template

	for _, field in ipairs(AMMO_FIELDS) do
		template.ammo_data[field] = original.ammo_data[field]
	end

	for _, name in ipairs(PROJECTILE_UNIT_TEMPLATES) do
		template.required_projectile_unit_templates[name] = original.required_projectile_unit_templates[name]
	end

	saved.original = nil
end

local function apply_bio_rifle()
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not template then
		return
	end

	-- The stat chart, from 0 to 7, set by hand against the Rocket Launcher's (its rocket is 60 damage and 6 on the chart) and the Flak Cannon's
	-- (its chunk and its shell). The small glob is the light attack (26 damage), and the big glob is the heavy one (140). The goop does a
	-- fifth less against armor, which puts its armor piercing between the chunk's and the shell's.
	template.weapon_diagram = {
		light_attack = {
			[DamageTypes.ARMOR_PIERCING] = 2,
			[DamageTypes.CLEAVE] = 4,
			[DamageTypes.SPEED] = 5,
			[DamageTypes.STAGGER] = 3,
			[DamageTypes.DAMAGE] = 3,
		},
		heavy_attack = {
			[DamageTypes.ARMOR_PIERCING] = 4,
			[DamageTypes.CLEAVE] = 6,
			[DamageTypes.SPEED] = 2,
			[DamageTypes.STAGGER] = 6,
			[DamageTypes.DAMAGE] = 6,
		},
	}

	local actions = template.actions
	local original = {
		action_one_default = actions.action_one.default,
		action_one_shoot_charged = actions.action_one.shoot_charged,
		action_two_default = actions.action_two.default,
		ammo_data = {},
		default_spread_template = template.default_spread_template,
		required_projectile_unit_templates = {},
	}

	for _, field in ipairs(AMMO_FIELDS) do
		original.ammo_data[field] = template.ammo_data[field]
	end

	template.required_projectile_unit_templates = template.required_projectile_unit_templates or {}

	for _, name in ipairs(PROJECTILE_UNIT_TEMPLATES) do
		original.required_projectile_unit_templates[name] = template.required_projectile_unit_templates[name]
		template.required_projectile_unit_templates[name] = true
	end

	saved.original = original

	-- All the ammo is the clip, and picked up ammo is added to it, so there is no reload between shots. The pistol's ammo counter is
	-- for six rounds, so it is not updated.
	template.ammo_data.max_ammo = CONFIG.max_ammo
	template.ammo_data.ammo_per_clip = CONFIG.max_ammo
	template.ammo_data.ammo_per_reload = CONFIG.max_ammo
	template.ammo_data.ammo_immediately_available = true
	template.ammo_data.play_reload_anim_on_wield_reload = false
	template.ammo_data.should_update_anim_ammo = false
	-- Nothing should need a reload, but the game may still start one when the weapon is wielded, so the reload is made short.
	template.ammo_data.reload_time = 0.2
	template.default_spread_template = SPREAD_TEMPLATE

	local primary = build_shot_action(false)
	local charged = build_shot_action(true)
	local child = build_child_action()

	utils.set_lookup_data(primary, TEMPLATE_NAME, "action_one", "default")
	utils.set_lookup_data(charged, TEMPLATE_NAME, "action_one", "shoot_charged")
	utils.set_lookup_data(child, TEMPLATE_NAME, CHILD_ACTION_NAME, CHILD_SUB_ACTION)

	actions.action_one.default = primary
	actions.action_one.shoot_charged = charged
	actions[CHILD_ACTION_NAME][CHILD_SUB_ACTION] = child

	local charge = build_charge_action()

	utils.set_lookup_data(charge, TEMPLATE_NAME, "action_two", "default")

	actions.action_two.default = charge
end

-- The mod holds its own references to the units of the globs while the weapon is enabled.
local packages = utils.package_holder("unreal_tournament_bio")

-- Loading goop
-- The goop that each player has loaded: { load, timer, done }. It is read when the big glob is fired.
local goop_loads = setmetatable({}, {
	__mode = "k",
})

-- Used by the skin: how long a full load takes, and whether a player's load is done (full, or the ammo ran out).
mod.bio_goop.load_time = CONFIG.goop_up_rate * CONFIG.max_goop_load
mod.bio_goop.max_load = CONFIG.max_goop_load
mod.bio_goop.load_amount = function (owner_unit)
	local state = goop_loads[owner_unit]

	return state and state.load or 0
end
mod.bio_goop.is_load_done = function (owner_unit)
	local state = goop_loads[owner_unit]

	return state ~= nil and state.done
end

-- Loads one more unit of goop. It takes 1 ammo, and nothing is loaded if there is none. The loading is done when the load is full or
-- the ammo is gone.
local function add_goop(action, state)
	local ammo_extension = action.ammo_extension

	if ammo_extension and ammo_extension:ammo_count() > 0 then
		state.load = state.load + 1

		ammo_extension:use_ammo(1)
	end

	if state.load >= CONFIG.max_goop_load or not ammo_extension or ammo_extension:ammo_count() <= 0 then
		state.done = true
	end
end

-- BioChargedFire.Hold: one unit of goop at once, and then one every GoopUpRate seconds.
mod.charge_start_callbacks.bio = function (action, new_action, t, chain_action_data, power_level)
	if new_action.ut_charge_callback ~= "bio" then
		return
	end

	local state = {
		done = false,
		load = 0,
		-- The power level of the charge, which a glob that is released by switching weapons is fired with.
		power_level = power_level,
		timer = 0,
	}

	goop_loads[action.owner_unit] = state

	add_goop(action, state)
end

mod.charge_update_callbacks.bio = function (action, dt)
	local state = goop_loads[action.owner_unit]

	if not state or state.done then
		return
	end

	state.timer = state.timer + dt

	while state.timer >= CONFIG.goop_up_rate and not state.done do
		state.timer = state.timer - CONFIG.goop_up_rate

		add_goop(action, state)
	end
end

-- Returns how much goop the player has loaded, at least 1, and empties the load.
local function take_goop_load(owner_unit)
	local state = goop_loads[owner_unit]
	local load = state and state.load or 0

	if state then
		state.load = 0
	end

	return math.clamp(load, 1, CONFIG.max_goop_load)
end

-- Switching to another weapon while the goop is loading releases it: the glob is fired as if the button was let go, as it would not be
-- used otherwise (the ammo for it was used as it was loaded). The reason for a release is a new action (the shot's), so this is only for
-- the weapon being switched.
local release_load

mod.charge_finish_callbacks.bio = function (action, reason)
	if reason == "weapon_wielded" and action.current_action and action.current_action.ut_charge_callback == "bio" then
		release_load(action)
	end
end

-- Starting a glob
-- Returns where a glob starts: in front of the camera, to its right and below it. A glob that would start behind a wall starts at
-- the wall instead, because ProjectileFire.DoFireEffect traces to it.
local function start_position(position, rotation)
	position = utils.as_vector(position)

	-- The game's spread rolls the rotation of a shot by a random angle about the way it points, whatever the spread numbers are. So
	-- right and up are taken from the way it points alone. Otherwise the offset would turn about the aim from shot to shot.
	local level = Quaternion.look(Quaternion.forward(rotation), Vector3.up())
	local offset = Quaternion.forward(level) * CONFIG.start_forward + Quaternion.right(level) * CONFIG.start_right - Quaternion.up(level) * CONFIG.start_down
	local distance = Vector3.length(offset)
	local direction = offset * (1 / distance)
	local physics_world = World.get_data(Managers.world:world("level_world"), "physics_world")
	local hit, _, hit_distance = PhysicsWorld.immediate_raycast(physics_world, position, direction, distance, "closest", "collision_filter", "filter_ai_line_of_sight_check")

	if hit then
		return position + direction * math.max(hit_distance - 0.05, 0)
	end

	return position + offset
end

-- A shot of the player starts at UT's offset, and the big glob has the goop that was loaded. Its scale carries the level, its speed
-- depends on the level, and its power level is the share of the biggest glob's.
mod.spawn_projectile_callbacks[TEMPLATE_NAME] = function (func, owner_unit, position, rotation, scale, angle, target_vector, speed, item_name, item_template_name, action_name, sub_action_name, is_critical_strike, power_level, ...)
	local template = rawget(Weapons, item_template_name)
	local sub_actions = template and template.actions[action_name]
	local action = sub_actions and sub_actions[sub_action_name]

	if action and action.ut_bio_shot then
		local level = action.ut_bio_charged and take_goop_load(owner_unit) or 1

		position = start_position(position, rotation)
		scale = scale_to_send(level)
		speed = action_speed(action.ut_bio_charged and charged_speed_uu(level) or CONFIG.glob_speed_uu)
		power_level = power_level * power_ratio(level)
	end

	return func(owner_unit, position, rotation, scale, angle, target_vector, speed, item_name, item_template_name, action_name, sub_action_name, is_critical_strike, power_level, ...)
end

-- Fires the glob of the goop that is loaded, from where the player looks. It is the shot of the charged action, which the spawn
-- callback above gives the loaded goop, the start position and the speed.
release_load = function (action)
	local owner_unit = action.owner_unit
	local state = goop_loads[owner_unit]
	local template = rawget(Weapons, TEMPLATE_NAME)
	local shot = template and template.actions.action_one.shoot_charged

	if not state or state.load <= 0 or not state.power_level or not shot then
		return
	end

	local first_person_extension = action.first_person_extension
	local rotation = first_person_extension:current_rotation()
	local position = first_person_extension:current_position()
	local angle = ActionUtils.pitch_from_rotation(rotation)
	local target_vector = Vector3.normalize(Vector3.flat(Quaternion.forward(rotation)))
	local lookup_data = shot.lookup_data

	ActionUtils.spawn_player_projectile(owner_unit, position, rotation, 0, angle, target_vector, shot.speed, action.item_name, lookup_data.item_template_name, lookup_data.action_name, lookup_data.sub_action_name, false, state.power_level)
end

-- Spawns a glob of the given level, moving at the given velocity (in m/s). It is used for the small globs and for the glob that drips.
local function spawn_glob(context, position, velocity, level)
	local speed = Vector3.length(velocity)
	local direction = speed > 0.001 and velocity * (1 / speed) or Vector3.down()
	local flat = Vector3.flat(direction)
	local target_vector = Vector3.length(flat) > 0.01 and Vector3.normalize(flat) or Vector3(0, 1, 0)
	local angle = math.radians_to_degrees(math.asin(math.clamp(Vector3.z(direction), -1, 1)))
	-- A rotation that looks straight up or down needs another vector to say which way is up.
	local up = math.abs(Vector3.z(direction)) > 0.99 and Vector3(0, 1, 0) or Vector3.up()

	ActionUtils.spawn_player_projectile(context.owner_unit, position, Quaternion.look(direction, up), scale_to_send(level), angle, target_vector, speed * 100, context.item_name, TEMPLATE_NAME, CHILD_ACTION_NAME, CHILD_SUB_ACTION, context.is_critical_strike, context.base_power * power_ratio(level))
end

local function random_direction()
	local direction = Vector3(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1)

	if Vector3.length(direction) < 0.001 or Vector3.length(direction) > 1 then
		return random_direction()
	end

	return Vector3.normalize(direction)
end

-- Globs that have landed
-- Only the host keeps these. It has the enemies, and it makes the explosions. Each is { id, context, position, normal (boxes), level,
-- rand3, expire, drips, inside }. The context is who fired it: { owner_unit, item_name, is_critical_strike, base_power }, where the
-- base power is the power of a level 10 glob.
local stuck = {}
local next_glob_id = 0

local function visuals()
	return mod.goop_visual_callbacks
end

mod:network_register("ut_bio_land", function (_, id, x, y, z, normal_x, normal_y, normal_z, level)
	visuals().land(id, Vector3(x, y, z), Vector3(normal_x, normal_y, normal_z), level)
end)

mod:network_register("ut_bio_merge", function (_, id, level)
	visuals().merge(id, level)
end)

mod:network_register("ut_bio_end", function (_, id)
	visuals().stop(id)
end)

local function end_visual(glob)
	visuals().stop(glob.id)
	mod:network_send("ut_bio_end", "others", glob.id)
end

-- Returns when a glob that has been hit or has landed explodes or drips: a glob on a ceiling drips when its animation ends and
-- DripTime has passed, and any other glob explodes after RestTime.
local function rest_end_time(glob, t)
	if glob.ceiling then
		return t + CONFIG.hit_animation_time + CONFIG.drip_time
	end

	return t + CONFIG.rest_time
end

local function blow_up(glob)
	local context = glob.context
	local normal = glob.normal:unbox()
	local position = glob.position:unbox() + normal * 0.1
	-- The explosion looks the way the surface faces, as UT's glob does when it has landed (its effects are made along its rotation).
	local up = math.abs(Vector3.z(normal)) > 0.99 and Vector3(0, 1, 0) or Vector3.up()

	local area_damage_system = Managers.state.entity:system("area_damage_system")

	-- The game looks at where units are, and the mod's update runs before the positions are current (see utils.with_valid_positions).
	with_valid_positions(area_damage_system.create_explosion, area_damage_system, context.owner_unit, position, Quaternion.look(normal, up), "ut_bio_blast", scale_of_level(glob.level), context.item_name, context.base_power * power_ratio(glob.level), context.is_critical_strike, context.owner_unit)
	end_visual(glob)
end

-- A glob on a ceiling falls, as a glob of the same level.
local function drip(glob)
	local context = glob.context
	local position = glob.position:unbox() + glob.normal:unbox() * 0.1
	local speed = CONFIG.drip_speed_uu * UNIT * CONFIG.speed_scale

	spawn_glob(context, position, Vector3(0, 0, -speed), glob.level)
	end_visual(glob)
end

-- BioGlob.SplashGlobs: small globs fly off the surface. They start a little off it, and fly away from it in random directions. The
-- glob that landed gives them a tenth of its velocity, reflected.
local function splash_globs(context, position, normal, landing_velocity, count, volume)
	local start = position + normal * (volume * (CONFIG.flying_collision_uu + 4) * UNIT)
	local reflected = landing_velocity and (landing_velocity - normal * (Vector3.dot(landing_velocity, normal) * 2)) * CONFIG.globling_inherit_share or Vector3.zero()

	for _ = 1, count do
		local speed_uu = CONFIG.globling_speed_uu[1] + math.random() * (CONFIG.globling_speed_uu[2] - CONFIG.globling_speed_uu[1])
		local velocity = speed_uu * UNIT * CONFIG.speed_scale * (normal + random_direction() * CONFIG.globling_random_share) + reflected

		spawn_glob(context, start, velocity, 1)
	end
end

local function is_ceiling(normal)
	return Vector3.dot(normal, Vector3.down()) > CONFIG.ceiling_dot
end

-- BioGlob.MergeWithGlob (in the state OnGround): a glob that lands in another adds its goop. What is above the biggest level is
-- thrown off as small globs.
local function merge(glob, level, t)
	local new_level = glob.level + level

	if new_level > CONFIG.max_goop_level then
		glob.rand3 = (glob.rand3 + 1) % 3

		local extra = glob.rand3

		splash_globs(glob.context, glob.position:unbox(), glob.normal:unbox(), nil, new_level - CONFIG.max_goop_level + extra, math.sqrt(glob.level))

		new_level = CONFIG.max_goop_level - extra
	end

	glob.level = new_level
	glob.drips = glob.ceiling
	glob.expire = rest_end_time(glob, t)

	visuals().merge(glob.id, glob.level)
	mod:network_send("ut_bio_merge", "others", glob.id, glob.level)
end

-- Returns the glob that has landed that a glob landing at this position joins, if there is one: the nearest whose collision it
-- touches.
local function glob_to_join(position)
	local nearest, nearest_distance

	for _, glob in ipairs(stuck) do
		local distance = Vector3.distance(glob.position:unbox(), position)

		if distance <= glob_radius(glob.level) + CONFIG.flying_collision_uu * UNIT and (not nearest_distance or distance < nearest_distance) then
			nearest = glob
			nearest_distance = distance
		end
	end

	return nearest
end

-- BioGlob.Landed: a glob lands on a surface. It joins a glob that is there, or it sticks. A glob that is bigger than its core size
-- throws off the rest as small globs. landing_velocity is the glob's velocity as it hit, in m/s.
local function land(context, position, normal, landing_velocity, level, t)
	local joined = glob_to_join(position)

	if joined then
		merge(joined, level, t)

		return
	end

	local rand3 = math.random(0, 2)
	local core = rand3 + CONFIG.max_goop_level - 3

	if level > core then
		splash_globs(context, position, normal, landing_velocity, level - core, math.sqrt(level))

		level = core
	end

	if #stuck >= CONFIG.max_stuck then
		stuck[1].expire = 0
		stuck[1].drips = false
	end

	next_glob_id = next_glob_id + 1

	local glob = {
		ceiling = is_ceiling(normal),
		context = context,
		id = next_glob_id,
		inside = {},
		level = level,
		normal = Vector3Box(normal),
		position = Vector3Box(position),
		rand3 = rand3,
	}

	glob.drips = glob.ceiling
	glob.expire = rest_end_time(glob, t)
	stuck[#stuck + 1] = glob

	visuals().land(glob.id, position, normal, level)
	mod:network_send("ut_bio_land", "others", glob.id, position.x, position.y, position.z, normal.x, normal.y, normal.z, level)
end

-- A player, a bot or an enemy that touches a glob that has landed makes it explode soon. This returns the units that are inside the
-- glob's collision, as a set.
local query_units = {}

local function units_touching(glob)
	local touching = {}
	local position = glob.position:unbox()
	local side = Managers.state.side:get_side_from_name("heroes")

	if not side then
		return touching
	end

	local pawn_radius = CONFIG.pawn_radius_uu * UNIT
	local pawn_height = CONFIG.pawn_height_uu * UNIT
	local radius = glob_radius(glob.level)

	local function consider(unit)
		local offset = position - Unit.world_position(unit, 0)

		if Vector3.length(Vector3.flat(offset)) <= radius + pawn_radius and Vector3.z(offset) >= -radius and Vector3.z(offset) <= pawn_height + radius then
			touching[unit] = true
		end
	end

	for _, unit in ipairs(side.PLAYER_AND_BOT_UNITS) do
		if Unit.alive(unit) and HEALTH_ALIVE[unit] then
			consider(unit)
		end
	end

	local count = AiUtils.broadphase_query(position, radius + pawn_radius + 1, query_units, side.enemy_broadphase_categories)

	for i = 1, count do
		local unit = query_units[i]

		if HEALTH_ALIVE[unit] then
			consider(unit)
		end
	end

	return touching
end

-- BioGlob.TakeDamage: a glob that something detonates explodes in 0.1 seconds. It does not drip any more.
local function detonate(glob, t)
	glob.drips = false
	glob.expire = t + CONFIG.detonation_delay
end

local function update_globs(t)
	for i = #stuck, 1, -1 do
		local glob = stuck[i]

		if not Unit.alive(glob.context.owner_unit) then
			-- The player's unit is gone, because a hero was changed or the level was left. Nothing can be made for it, because the game
			-- breaks on an explosion that has no attacker.
			table.remove(stuck, i)
			end_visual(glob)
		else
			-- BioGlob.OnGround.ProcessTouch: a pawn that steps in sets the explosion for 0.15 seconds from now.
			local touching = units_touching(glob)

			for unit in pairs(touching) do
				if not glob.inside[unit] then
					glob.drips = false
					glob.expire = t + CONFIG.touch_detonation_delay
				end
			end

			glob.inside = touching

			if t >= glob.expire then
				table.remove(stuck, i)

				if glob.drips then
					drip(glob)
				else
					blow_up(glob)
				end
			end
		end
	end
end

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	if not Managers.player or not Managers.player.is_server or #stuck == 0 then
		return
	end

	local t = Managers.time:time("game")

	if t then
		update_globs(t)
	end
end

-- What detonates a glob: the explosions of the rocket, the flak shell, the shock ball, the shock combo and a glob (they all have
-- bDetonatesGoop in UT). A glob that the explosion reaches explodes in 0.1 seconds.
local DETONATORS = {
	ut_bio_blast = true,
	ut_bio_blast_air = true,
	ut_flak_shell_explosion = true,
	ut_rocket_explosion = true,
	ut_shock_ball_explosion = true,
	ut_shock_combo_explosion = true,
}

mod.any_explosion_callbacks.bio = function (explosion_template, position, scale)
	if not DETONATORS[explosion_template.name] or #stuck == 0 or not Managers.player.is_server then
		return
	end

	local explosion = explosion_template.explosion
	local radius = explosion and (explosion.radius or math.lerp(explosion.radius_min, explosion.radius_max, scale or 0))
	local t = Managers.time:time("game")

	if not radius or not t then
		return
	end

	for _, glob in ipairs(stuck) do
		if Vector3.distance(glob.position:unbox(), position) <= radius + glob_radius(glob.level) then
			detonate(glob, t)
		end
	end
end

-- Globs that hit something
-- A glob lands on the machine of the player who fired it. The host handles it. For another player, this tells the host.
mod:network_register("ut_bio_goo", function (_, owner_go_id, item_name, is_critical_strike, base_power, x, y, z, normal_x, normal_y, normal_z, velocity_x, velocity_y, velocity_z, level)
	if not Managers.player.is_server then
		return
	end

	local owner_unit = Managers.state.unit_storage:unit(owner_go_id)
	local t = Managers.time:time("game")

	if not owner_unit or not Unit.alive(owner_unit) or not t then
		return
	end

	land({
		base_power = base_power,
		is_critical_strike = is_critical_strike,
		item_name = item_name,
		owner_unit = owner_unit,
	}, Vector3(x, y, z), Vector3(normal_x, normal_y, normal_z), Vector3(velocity_x, velocity_y, velocity_z), level, t)
end)

-- The way out of the wall, floor or ceiling that a glob hits is stored on the glob before it lands, because the game gives the
-- landing only the place.
for _, function_name in ipairs({
	"hit_level_unit",
	"hit_non_level_unit",
}) do
	mod:hook(PlayerProjectileUnitExtension, function_name, function (func, self, impact_data, hit_unit, hit_position, hit_direction, hit_normal, ...)
		local action = self._current_action

		if action and action.ut_bio_glob and hit_normal then
			self._ut_bio_hit_normal = Vector3Box(hit_normal)
			self._ut_bio_hit_direction = Vector3Box(hit_direction)
		end

		return func(self, impact_data, hit_unit, hit_position, hit_direction, hit_normal, ...)
	end)
end

-- A glob that hit a surface lands, once.
mod.aoe_callbacks.ut_bio_glob = function (self, aoe_data, position)
	local normal_box = self._ut_bio_hit_normal

	if not normal_box or self._ut_bio_done then
		return
	end

	self._ut_bio_done = true

	local level = level_of_scale(self.scale)
	local normal = normal_box:unbox()
	local direction = self._ut_bio_hit_direction:unbox()
	local speed = (self.locomotion_extension.speed or 0) / 100
	local base_power = self.power_level / power_ratio(level)
	local velocity = direction * speed

	if self._is_server then
		local t = Managers.time:time("game")

		if t then
			land({
				base_power = base_power,
				is_critical_strike = self._is_critical_strike,
				item_name = self.item_name,
				owner_unit = self._owner_unit,
			}, position, normal, velocity, level, t)
		end
	else
		mod:network_send("ut_bio_goo", "others", Managers.state.unit_storage:go_id(self._owner_unit), self.item_name, self._is_critical_strike or false, base_power, position.x, position.y, position.z, normal.x, normal.y, normal.z, velocity.x, velocity.y, velocity.z, level)
	end
end

-- A glob that hits a player, a bot or an enemy explodes there, in the air (BioGlob.Flying.ProcessTouch). The explosion goes through
-- the area damage system, which applies the damage on the host and makes the explosion on every machine.
mod.hit_enemy_callbacks.ut_bio_glob = function (func, self, is_owner, impact_data, hit_unit, hit_position, ...)
	func(self, impact_data, hit_unit, hit_position, ...)

	if is_owner and not self._ut_bio_done then
		self._ut_bio_done = true

		self:do_aoe(ExplosionTemplates.ut_bio_blast_air, hit_position, true)
	end
end

-- Explosions
-- The explosion of a glob hurts and throws the player who fired it, as in UT. It runs on every machine, and the player's own machine
-- does it. before.attacker_unit is the player.
for _, template_name in ipairs({ "ut_bio_blast", "ut_bio_blast_air" }) do
	local in_air = template_name == "ut_bio_blast_air"

	mod.explosion_before_callbacks[template_name] = function (world, position, attacker_unit)
		return {
			attacker_unit = attacker_unit,
		}
	end

	mod.explosion_callbacks[template_name] = function (world, position, rotation, before, scale)
		local owner_unit = before and before.attacker_unit

		if not owner_unit or not utils.is_local_player_unit(owner_unit) then
			return
		end

		local level = level_of_scale(scale)
		local radius = blast_radius(level)
		local explosion = {
			max_damage_radius = radius * CONFIG.blast_full_damage_share,
			radius = radius,
		}

		utils.apply_explosion_self_damage(owner_unit, position, mod.items.weapons.bio_rifle.key, explosion, blast_damage(level) * CONFIG.self_damage_share)
		utils.apply_explosion_self_push(owner_unit, position, explosion, CONFIG.jump_speed * math.sqrt(level) * (in_air and 0.5 or 1))
	end
end

local function enable_bio_rifle()
	packages.load_projectile_units(PROJECTILE_UNIT_TEMPLATES)
	apply_bio_rifle()
end

mod.enabled_callbacks[#mod.enabled_callbacks + 1] = enable_bio_rifle
mod.disabled_callbacks[#mod.disabled_callbacks + 1] = restore_pistol
mod.unload_callbacks[#mod.unload_callbacks + 1] = restore_pistol

-- The globs are cleared when the mod is unloaded and when a level is left.
local function clear_all()
	for _, glob in ipairs(stuck) do
		if visuals().stop then
			visuals().stop(glob.id)
		end
	end

	table.clear(stuck)
	table.clear(goop_loads)
end

mod.unload_callbacks[#mod.unload_callbacks + 1] = clear_all
mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = clear_all
