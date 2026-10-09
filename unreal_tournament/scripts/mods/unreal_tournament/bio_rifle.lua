local mod = get_mod("unreal_tournament")

-- Bio Rifle: replaces the Drakegun's (Bardin) actions in place, like the other weapons do.
--   LMB: a glob of goo, lobbed. It bursts where it lands and adds to the burning puddle there.
--   RMB (held): charges a bigger glob, fired on release. The bigger the charge, the more goo is in it.
--               (UT2004: XWeapons/BioRifle, BioGlob.)
-- Puddles are made of goo: every glob that lands adds its goo to the puddle under it (a puddle grows as it
-- gets more goo). A puddle bursts into small globs, thrown out in a short arc, that make puddles of their own
-- where they land, when it gets too much goo or when something steps into it. The charged glob landing counts
-- as stepping: it bursts the puddle it lands in, or makes, however much goo there is.
-- Overheating takes the place of ammo: the Drakegun's own.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local effects = mod.effects
local with_valid_positions = utils.with_valid_positions
local register_damage_profile = utils.register_damage_profile
local register_explosion_template = utils.register_explosion_template
local make_flat = utils.make_flat
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for

local TEMPLATE_NAME = "drakegun_template_1"

local CONFIG = {
	-- Primary
	fire_interval = 0.45, -- seconds between globs when the button is held
	glob_speed = 3500, -- m/s * 100
	-- The game's gravity settings: "bolts" is a gentle arc, "drakegun" drops a shot by 16 m over 40 m at the
	-- speed the globs used to have
	glob_gravity_settings = "bolts",
	glob_max_flight = 4, -- seconds until a glob that hit nothing bursts
	glob_fizzle_time = 1.5, -- seconds a glob stays after it has hit something, for its trail to fade out
	glob_end_delay = 0.5, -- seconds after the hit that the glob's effects are told to end
	glob_direct_damage = 8, -- in UT2004's units, 45 is the shock rifle's beam: what the glob does to what it hits
	glob_damage = 10, -- what the burst of the glob does (in the radius, to what the glob hit too)
	glob_burst_radius = 1.5, -- m
	-- Puddles. A glob is 1 goo. A puddle's radius is that of a glob's puddle for its first goo and grows with
	-- the square root of it (its area goes with the goo), up to puddle_radius_max. It lasts a glob's time and a
	-- little more for every goo more, and every glob that lands in it starts the time again. A glob lands in a
	-- puddle if it is closer to its center than the radius and puddle_merge_margin.
	glob_puddle_radius = 1.2, -- m
	glob_puddle_duration = 4, -- seconds
	puddle_radius_max = 4, -- m
	puddle_duration_per_goo = 1, -- seconds
	puddle_duration_max = 8, -- seconds
	puddle_merge_margin = 0.5, -- m
	puddle_merge_height = 1.5, -- m
	-- A puddle holds less goo than burst_goo: with that much it bursts (it bursts too when something steps into it).
	-- The small globs it throws have child_goo_min goo each and take the goo it has, less burst_goo_loss and the goo
	-- that stays (burst_goo_left, at most burst_goo_left_max: the globs it throws can land back in it, and burst it
	-- again): the bursts, if they come after each other, die out.
	burst_goo = 7,
	step_burst_goo = 3, -- a puddle with less goo than this is walked through (the alt fire still bursts it)
	burst_goo_loss = 0.2,
	burst_goo_left = 0.2, -- the share of its goo that a puddle that bursts keeps
	burst_goo_left_max = 1.5,
	child_goo_min = 1,
	-- The weapon's overheating explosion throws overheat_glob_count small globs from the player, each with a random
	-- amount of goo from child_goo_min to child_goo_max (the goo is the scale of the projectile, 0 to 1, between
	-- the two).
	overheat_glob_count = 20,
	child_goo_max = 3,
	big_puddle_goo = 3, -- a puddle with this much goo looks like the charged glob's (charged_puddle_effect)
	-- Charged: the charge level (0 to 1) goes from the primary's numbers to these. The goo of the glob goes from
	-- charged_goo_min, at the charge where it can first be fired (min_fire_time), to charged_goo, at a full charge
	-- (it bursts the puddle it lands in whatever the goo), by the same curve as the heat of the charge
	-- (charge_heat_curve). The power of a puddle's burst goes with the goo it had: from the primary's glob_damage to
	-- charged_glob_damage and the radius from glob_burst_radius to charged_burst_radius, at charged_goo.
	charge_time = 2, -- seconds to a full charge
	min_fire_time = 0.3, -- seconds into the charge that the glob can be fired: that is the bottom of the goo
	charged_glob_speed = 3000,
	charged_goo_min = 3,
	charged_goo = 15,
	charged_glob_damage = 70,
	charged_burst_radius = 4,
	puddle_burst_effect_scale = 3, -- the size of the burst of a puddle, relative to that of a glob's, at its least and at its most
	puddle_burst_effect_scale_max = 7,
	child_count_max = 14,
	child_speed_min = 800, -- m/s * 100
	child_speed_max = 1200,
	child_gravity = -30, -- the game's own: -9.82 for a thrown thing, -5 for the globs. Short arc: up, and down fast.
	child_angle_min = 50, -- degrees up from the ground
	child_angle_max = 75,
	child_start_height = 0.4, -- m above the burst
	child_max_flight = 3, -- seconds until a small glob that hit nothing bursts
	child_damage = 12,
	child_burst_radius = 1, -- m
	-- The puddle burns (a damage over time of the game's), and looks like the ground the fire grenade leaves: the
	-- effect is put along the ground in the radius of the puddle, each of its particles being this share of it.
	-- The puddle burns whoever stands in it for as long as it lasts: it puts a burn on them every
	-- puddle_damage_interval seconds, a burn that ticks every puddle_tick_interval seconds and lasts a little
	-- longer than the interval, so that it never goes out while they are inside. (The game's own
	-- burning_dot_1tick is a single tick of 0.07 of the standard power level, once.)
	puddle_dot = "ut_bio_puddle_dot",
	puddle_damage_interval = 1, -- seconds
	puddle_tick_interval = 0.5, -- seconds
	puddle_tick_damage = 6, -- in UT2004's units, per tick
	puddle_effect = "fx/wpnfx_lamp_oil_remains", -- the game's burning lamp oil
	charged_puddle_effect = "fx/wpnfx_fire_grenade_impact_remains_remap", -- the fire grenade's ground in another color
	-- The effect is one fire emitter, scaled to the radius of the puddle (the game's own area effect puts a fixed emitter at
	-- the center and adds more of them in rings as the radius grows). This is the radius of the effect at its own size.
	puddle_effect_natural_radius = 2, -- m
	-- Overheating, in the Drakegun's own units (it overheats at 30): a glob is this much, a full charge is
	-- this much by the time it is full (the shot that follows costs nothing more). Balanced against the
	-- Shock Rifle's, whose beam is 4 every 0.7 seconds (5.7 a second, a combo is 12 more): a glob every 0.45
	-- seconds is 5.6 a second. (The game takes the heat off again 1.3 a second, from 0.25 seconds after the last
	-- of it.)
	glob_overcharge = 2.5,
	charged_overcharge = 15,
	-- How front-loaded the heat of the charge is: 1 is even, the higher the more of it comes at the start
	charge_heat_curve = 2,
	charge_heat_interval = 0.2, -- seconds between the additions of heat while charging
	-- The multipliers of the damage and the stagger per armor type: unarmored, armored, monsters, players, berserkers,
	-- super armor (the game's own for these explosions are 0 against super armor, which is what chaos warriors have:
	-- they would take nothing; the damage is low to begin with, so super armor takes it whole, stagger half)
	armor_attack = {1, 0.8, 1.5, 1, 1, 1},
	armor_impact = {1, 0.8, 1, 1, 1, 0.5},
	-- A burn ticks at the game's default power level (195), what the weapons' profiles are measured against is about 500
	burn_reference_power_level = 500,
	-- The sounds, events of the game's: the Sienna's fireball and geiser for the shots (the shots' have to be
	-- in the game's NetworkLookup of sound events, the others are not sent), the fire grenade's explosion and
	-- the fireball's hit for the bursts and the impacts
	fire_sound = "player_combat_weapon_staff_fireball_fire",
	charged_fire_sound = "player_combat_weapon_staff_geiser_fire",
	burst_sound = "fireball_big_hit",
	charged_burst_sound = "player_combat_weapon_fire_grenade_explosion",
	charged_impact_sound = "player_combat_weapon_fire_grenade_explosion",
	-- The look of the burst: these effects are played together, each that is loaded for the weapon's character
	-- (the others are skipped)
	burst_effects = {
		{
			name = "fx/wpnfx_flamethrower_hit_01",
			scale = 2.5,
			offset = 0,
		},
	},
	-- The impact: the charged glob, when it hits an enemy, sets off a blast of its own on top of the burst. It is
	-- as big as the glob is charged. (The primary has none: a direct hit is the burst.)
	impact_radius = 3, -- m (the smallest the charged one's gets)
	charged_impact_damage = 20,
	charged_impact_radius = 8,
	impact_effects = {
		{
			name = "fx/wpnfx_flamethrower_hit_01",
			scale = 4,
			offset = 0.5,
		},
	},
}

local overcharge_values = PlayerUnitStatusSettings.overcharge_values

overcharge_values.ut_bio_glob = CONFIG.glob_overcharge
-- (added every charge_heat_interval seconds while charging, together they are charged_overcharge)
local CHARGE_STEP = CONFIG.charge_heat_interval / CONFIG.charge_time -- the charge (0 to 1) between two additions
overcharge_values.ut_bio_charging = CONFIG.charged_overcharge * CHARGE_STEP

-- The heat of the charge goes up fast at first and slows down: the heat made by the time the charge is c (0 to 1)
-- is charged_overcharge * (1 - (1 - c)^charge_heat_curve). The game adds the same amount every time, so each
-- addition is scaled to what the curve makes in the step it ends. (The charge the player has is kept here by the
-- charge action.)
local charge_levels = {}

local function charge_heat_progress(charge_level)
	return 1 - (1 - math.clamp(charge_level, 0, 1)) ^ CONFIG.charge_heat_curve
end

mod.charge_update_callbacks.bio = function (self)
	charge_levels[self.owner_unit] = self.charge_level
end

mod.overcharge_callbacks.ut_bio_charging = function (self, overcharge_amount)
	local level = charge_levels[self.unit] or 0

	-- (once the charge is full the game adds next to nothing, that is left alone)
	if level < 1 then
		overcharge_amount = overcharge_amount * (charge_heat_progress(level) - charge_heat_progress(level - CHARGE_STEP)) / CHARGE_STEP
	end

	return overcharge_amount
end

local function set_armor_modifiers(profile)
	utils.set_armor_modifiers(profile, CONFIG.armor_attack, CONFIG.armor_impact, true)
end

-- Damage profiles: the direct hit of a glob does glob_direct_damage and staggers, and it is the part of the hit
-- that headshots count for (a burst has no hit zone). The rest of the damage is the burst.
register_damage_profile("ut_bio_glob", "staff_fireball", function (profile)
	make_flat(profile, attack_power_for(CONFIG.glob_direct_damage), impact_power_for(CONFIG.glob_direct_damage))
	set_armor_modifiers(profile)

	profile.cleave_distribution = {
		attack = 0.01,
		impact = 0.01,
	}
end)

-- The burn of the puddle: the game's burning dot with a power of its own (see burn_reference_power_level).

register_damage_profile(CONFIG.puddle_dot, "burning_dot", function (profile)
	profile.default_target.power_distribution = {
		attack = attack_power_for(CONFIG.puddle_tick_damage) * CONFIG.burn_reference_power_level / DefaultPowerLevel,
		impact = 0,
	}
end)

BuffTemplates[CONFIG.puddle_dot] = {
	buffs = {
		{
			apply_buff_func = "start_dot_damage",
			damage_profile = CONFIG.puddle_dot,
			damage_type = "burninating",
			duration = CONFIG.puddle_damage_interval * 1.2,
			max_stacks = 1,
			name = CONFIG.puddle_dot,
			refresh_durations = true,
			time_between_dot_damages = CONFIG.puddle_tick_interval,
			update_func = "apply_dot_damage",
			update_start_delay = CONFIG.puddle_tick_interval,
			perks = {
				require("scripts/unit_extensions/default_player_unit/buffs/settings/buff_perk_names").burning,
			},
		},
	},
}

DotTypeLookup[CONFIG.puddle_dot] = "burning_dot"
utils.register_network_lookup("buff_templates", CONFIG.puddle_dot)

local function burst_profiles(name, damage)
	local function modify(profile)
		make_flat(profile, attack_power_for(damage), impact_power_for(damage))
		set_armor_modifiers(profile)
	end

	register_damage_profile(name, "fireball_charged_explosion", modify)
	register_damage_profile(name .. "_glance", "fireball_charged_explosion_glance", modify)
end

burst_profiles("ut_bio_burst", CONFIG.glob_damage)
burst_profiles("ut_bio_charged_burst", CONFIG.charged_glob_damage)
burst_profiles("ut_bio_child_burst", CONFIG.child_damage)
burst_profiles("ut_bio_charged_impact", CONFIG.charged_impact_damage)

-- Explosion templates. The burst of a glob is only the blast, the goo it brings goes to the puddle (see Puddles
-- below). The burst of a puddle with too much goo, ut_bio_charged_burst, has a radius (and a power) that goes
-- with the goo it had: it is made with the goo as the scale of the explosion, 0 to 1.
local function burst_template(burst_profile_name, sound_event_name, radius_min, radius_max)
	return {
		explosion = {
			alert_enemies = true,
			alert_enemies_radius = 10,
			attacker_power_level_offset = 1,
			damage_profile = burst_profile_name,
			damage_profile_glance = burst_profile_name .. "_glance",
			max_damage_radius_max = radius_max * 0.4,
			max_damage_radius_min = radius_min * 0.4,
			radius_max = radius_max,
			radius_min = radius_min,
			sound_event_name = sound_event_name,
			use_attacker_power_level = true,
		},
	}
end

register_explosion_template("ut_bio_burst", burst_template("ut_bio_burst", CONFIG.burst_sound, CONFIG.glob_burst_radius, CONFIG.glob_burst_radius))
register_explosion_template("ut_bio_charged_burst", burst_template("ut_bio_charged_burst", CONFIG.charged_burst_sound, CONFIG.glob_burst_radius, CONFIG.charged_burst_radius))
register_explosion_template("ut_bio_child_burst", burst_template("ut_bio_child_burst", CONFIG.burst_sound, CONFIG.child_burst_radius, CONFIG.child_burst_radius))

-- What the charged glob bursts with: nothing, it has the goo to burst the puddle it makes (a template is what
-- tells the globs' bursts apart)
register_explosion_template("ut_bio_charged_glob", {})

-- The puddle: the area that burns whoever is in it. Its radius and duration are those of the puddle that is made.
-- It has no look of its own, the puddle's fire is played by the mod (see the visuals below).
register_explosion_template("ut_bio_puddle", {
	aoe = {
		area_damage_template = "explosion_template_aoe",
		attack_template = "fire_grenade_dot",
		damage_interval = CONFIG.puddle_damage_interval,
		dot_template_name = CONFIG.puddle_dot,
		duration = CONFIG.glob_puddle_duration,
		radius = CONFIG.glob_puddle_radius,
	},
})

-- The impact: only the blast, the burst that goes with it leaves the puddle. Its radius goes with the charge
-- like the charged burst's does.
local function impact_template(profile_name, sound_event_name, radius_min, radius_max)
	return {
		explosion = {
			alert_enemies = true,
			alert_enemies_radius = 10,
			attacker_power_level_offset = 1,
			damage_profile = profile_name,
			damage_profile_glance = profile_name .. "_glance",
			max_damage_radius_max = radius_max * 0.5,
			max_damage_radius_min = radius_min * 0.5,
			radius_max = radius_max,
			radius_min = radius_min,
			sound_event_name = sound_event_name,
			use_attacker_power_level = true,
		},
	}
end

register_explosion_template("ut_bio_charged_impact", impact_template("ut_bio_charged_impact", CONFIG.charged_impact_sound, CONFIG.impact_radius, CONFIG.charged_impact_radius))

-- The look of the burst and of the impact, on every peer (the explosion's callback is run for everyone who sees it)
local function play_effects(effect_list, world, position)
	for _, effect in ipairs(effect_list) do
		effects.play(world, effect.name, position + Vector3(0, 0, effect.offset), effect.scale)
	end
end

local function play_burst_effects(world, position)
	play_effects(CONFIG.burst_effects, world, position)
end

local function play_impact_effects(world, position)
	play_effects(CONFIG.impact_effects, world, position)
end

mod.explosion_callbacks.ut_bio_burst = play_burst_effects
mod.explosion_callbacks.ut_bio_charged_burst = play_burst_effects
mod.explosion_callbacks.ut_bio_charged_impact = play_impact_effects

-- Weapon template
-- The glob is a projectile of the game's, the bolt of the drakefire pistols. (The small fireball of the Sienna
-- stops being drawn when it is not close, the bolt is made to be seen from afar.) The charged glob is the Sienna's
-- charged fireball, which is big enough to be seen.

local PROJECTILE_UNIT_TEMPLATES = {
	"drake_pistol_shot",
	"fireball_charged",
}

-- The small globs are an action of the weapon of their own (a projectile takes its settings from its action by
-- name, and the name is sent over the network, so it is registered)
local CHILD_ACTION_NAME = "action_one"
local CHILD_SUB_ACTION = "ut_bio_child"
local CHILD_GRAVITY_SETTINGS = "ut_bio_child"

ProjectileGravitySettings[CHILD_GRAVITY_SETTINGS] = CONFIG.child_gravity
utils.register_network_lookup("projectile_gravity_settings", CHILD_GRAVITY_SETTINGS)

utils.register_network_lookup("sub_actions", CHILD_SUB_ACTION)

local function enter_function(attacker_unit, input_extension)
	input_extension:clear_input_buffer()

	return input_extension:reset_release_input()
end

local function build_projectile_info(projectile_name)
	local projectile_info = table.clone(Projectiles[projectile_name])

	projectile_info.gravity_settings = CONFIG.glob_gravity_settings
	projectile_info.life_time = CONFIG.glob_max_flight + 1
	projectile_info.unit_life_time = CONFIG.glob_max_flight + 1

	return projectile_info
end

local function build_glob_action()
	local projectile_info = build_projectile_info("brace_of_drake_pistols_shot")

	return {
		alert_sound_range_fire = 12,
		alert_sound_range_hit = 2,
		anim_end_event = "attack_finished",
		anim_event = "attack_shoot",
		apply_recoil = true,
		charge_value = "light_attack",
		fire_sound_event = CONFIG.fire_sound,
		fire_sound_on_husk = true,
		fire_time = 0.15,
		kind = "charged_projectile",
		overcharge_type = "ut_bio_glob",
		ut_bio_glob = true,
		ut_aoe_callback = "ut_bio_glob",
		ut_bio_goo = 1,
		ut_hit_enemy_callback = "ut_bio_glob",
		speed = CONFIG.glob_speed,
		total_time = CONFIG.fire_interval,
		allowed_chain_actions = {
			{
				action = "action_wield",
				input = "action_wield",
				start_time = 0.2,
				sub_action = "default",
			},
			{
				action = "action_one",
				input = "action_one_hold",
				start_time = CONFIG.fire_interval,
				sub_action = "default",
			},
			{
				action = "action_two",
				input = "action_two_hold",
				start_time = CONFIG.fire_interval,
				sub_action = "default",
			},
			{
				action = "weapon_reload",
				input = "weapon_reload",
				start_time = 0.3,
				sub_action = "default",
			},
		},
		enter_function = enter_function,
		projectile_info = projectile_info,
		impact_data = {
			aoe = ExplosionTemplates.ut_bio_burst,
			damage_profile = "ut_bio_glob",
		},
		-- a glob that hasn't hit anything bursts when its time is up
		timed_data = {
			aoe = ExplosionTemplates.ut_bio_burst,
			life_time = CONFIG.glob_max_flight,
		},
		recoil_settings = {
			climb_duration = 0.1,
			horizontal_climb = 0,
			restore_duration = 0.2,
			vertical_climb = -0.5,
			climb_function = math.easeInCubic,
			restore_function = math.ease_out_quad,
		},
	}
end

local function build_charged_action()
	-- The Sienna's charged fireball as the game has it (its unit grows with the charge by itself), only the
	-- arc of its flight is the globs'
	local projectile_info = table.clone(Projectiles.fireball_charged)

	projectile_info.gravity_settings = CONFIG.glob_gravity_settings

	return {
		alert_sound_range_fire = 12,
		alert_sound_range_hit = 2,
		anim_end_event = "attack_finished",
		anim_event = "attack_shoot_charged",
		apply_recoil = true,
		charge_value = "light_attack",
		fire_sound_event = CONFIG.charged_fire_sound,
		fire_sound_on_husk = true,
		fire_time = 0.15,
		kind = "charged_projectile",
		speed = CONFIG.charged_glob_speed,
		throw_up_this_much_in_target_direction = 0.1,
		ut_bio_glob = true,
		ut_bio_impact_template = "ut_bio_charged_impact",
		ut_hit_enemy_callback = "ut_bio_glob",
		ut_aoe_callback = "ut_bio_glob",
		-- (the goo of the glob goes with its charge, see goo_of)
		ut_bio_goo_by_charge = true,
		ut_bio_bursts_puddle = true,
		-- (the damage of an uncharged glob is the primary's, the full charge's is the charged one's)
		scale_power_level = CONFIG.glob_damage / CONFIG.charged_glob_damage,
		total_time = 0.8,
		allowed_chain_actions = {
			{
				action = "action_wield",
				input = "action_wield",
				start_time = 0.2,
				sub_action = "default",
			},
			{
				action = "action_one",
				input = "action_one",
				release_required = "action_two_hold",
				start_time = 0.8,
				sub_action = "default",
			},
			{
				action = "action_two",
				input = "action_two_hold",
				start_time = 0.8,
				sub_action = "default",
			},
			{
				action = "weapon_reload",
				input = "weapon_reload",
				start_time = 0.3,
				sub_action = "default",
			},
		},
		enter_function = enter_function,
		projectile_info = projectile_info,
		impact_data = {
			aoe = ExplosionTemplates.ut_bio_charged_glob,
			damage_profile = "ut_bio_glob",
		},
		timed_data = {
			aoe = ExplosionTemplates.ut_bio_charged_glob,
			life_time = CONFIG.glob_max_flight,
		},
		recoil_settings = {
			climb_duration = 0.2,
			horizontal_climb = 0,
			restore_duration = 0.2,
			vertical_climb = -1,
			climb_function = math.easeInCubic,
			restore_function = math.ease_out_quad,
		},
	}
end

local function build_child_action()
	local projectile_info = build_projectile_info("brace_of_drake_pistols_shot")

	-- a short arc: the globs are fast, and fall quickly
	projectile_info.gravity_settings = CHILD_GRAVITY_SETTINGS
	projectile_info.life_time = CONFIG.child_max_flight + 1
	projectile_info.unit_life_time = CONFIG.child_max_flight + 1

	return {
		kind = "charged_projectile",
		ut_aoe_callback = "ut_bio_glob",
		ut_bio_glob = true,
		ut_bio_goo_range = {
			CONFIG.child_goo_min,
			CONFIG.child_goo_max,
		},
		speed = CONFIG.child_speed_min,
		total_time = 1,
		allowed_chain_actions = {},
		projectile_info = projectile_info,
		impact_data = {
			aoe = ExplosionTemplates.ut_bio_child_burst,
			damage_profile = "ut_bio_glob",
		},
		timed_data = {
			aoe = ExplosionTemplates.ut_bio_child_burst,
			life_time = CONFIG.child_max_flight,
		},
	}
end

-- After a projectile has hit something the game keeps its unit for a short time before taking it away, so that its
-- trail can fade out. For the globs the unit is kept glob_fizzle_time seconds instead.
-- The game also tells the unit that the projectile has ended the moment it hits, which ends its effects
-- at once. For the globs that signal is held back and sent glob_end_delay seconds later.
local delayed_ends = {} -- the projectile's unit: when to tell it that it has ended

mod:hook(PlayerProjectileUnitExtension, "stop", function (func, self, ...)
	local action = self._current_action

	if not action or not action.ut_bio_glob or self._stop_impacts then
		return func(self, ...)
	end

	local projectile_unit = self._projectile_unit
	local flow_event = Unit.flow_event

	Unit.flow_event = function (unit, event_name, ...)
		if unit == projectile_unit and event_name == "lua_projectile_end" then
			delayed_ends[projectile_unit] = Managers.time:time("game") + CONFIG.glob_end_delay

			return
		end

		return flow_event(unit, event_name, ...)
	end

	-- (the call mustn't leave the function replaced)
	local ok, error_message = pcall(func, self, ...)

	Unit.flow_event = flow_event

	if not ok then
		error(error_message, 0)
	end
end)

local function update_delayed_ends(t)
	for projectile_unit, end_t in pairs(delayed_ends) do
		if t >= end_t then
			delayed_ends[projectile_unit] = nil

			if Unit.alive(projectile_unit) then
				Unit.flow_event(projectile_unit, "lua_projectile_end")
			end
		end
	end
end

-- The way out of the wall, floor or ceiling a glob hits is told to the glob before its burst is made (the game
-- gives the burst only the place)
for _, function_name in ipairs({
	"hit_level_unit",
	"hit_non_level_unit",
}) do
	mod:hook(PlayerProjectileUnitExtension, function_name, function (func, self, impact_data, hit_unit, hit_position, hit_direction, hit_normal, ...)
		local action = self._current_action

		if action and action.ut_aoe_callback == "ut_bio_glob" and hit_normal then
			self._ut_bio_hit_normal = Vector3Box(hit_normal)
		end

		return func(self, impact_data, hit_unit, hit_position, hit_direction, hit_normal, ...)
	end)
end

-- Smaller globs are thrown out of a puddle that bursts, or out of the player when the weapon overheats, in a
-- small arc, in random directions. They are projectiles of the weapon's own action (CHILD_SUB_ACTION), spawned like
-- a shot is: away from the surface the puddle is on, up from a floor, down from a ceiling, out from a wall.
-- shot: { owner_unit, item_name, item_template_name, is_critical_strike }. With random_goo each glob has a random
-- amount of goo (child_goo_min to child_goo_max), without it child_goo_min.
local function throw_children(shot, position, normal, count, power_level, random_goo)
	local start = position + normal * CONFIG.child_start_height
	local helper_axis = math.abs(normal.z) < 0.9 and Vector3.up() or Vector3.right()
	local tangent_a = Vector3.normalize(Vector3.cross(normal, helper_axis))
	local tangent_b = Vector3.cross(normal, tangent_a)

	for _ = 1, count do
		local around = math.random() * math.pi * 2
		local elevation = math.degrees_to_radians(CONFIG.child_angle_min + math.random() * (CONFIG.child_angle_max - CONFIG.child_angle_min))
		local speed = CONFIG.child_speed_min + math.random() * (CONFIG.child_speed_max - CONFIG.child_speed_min)
		-- (the elevation is from the surface, toward the way out of it)
		local along = tangent_a * math.cos(around) + tangent_b * math.sin(around)
		local direction = along * math.cos(elevation) + normal * math.sin(elevation)
		-- the game's projectiles are given a flat direction and the angle up (or down) from it
		local flat = Vector3.flat(direction)
		local target_vector

		if Vector3.length(flat) > 0.01 then
			target_vector = Vector3.normalize(flat)
		else
			target_vector = Vector3(math.cos(around), math.sin(around), 0)
		end

		local angle = math.radians_to_degrees(math.asin(math.clamp(direction.z, -1, 1)))

		-- (the goo of the small glob is its scale, from child_goo_min at 0 to child_goo_max at 100)
		local goo_scale = random_goo and math.floor(math.random() * 100 + 0.5) or 0

		ActionUtils.spawn_player_projectile(shot.owner_unit, start, Quaternion.look(direction), goo_scale, angle, target_vector, speed, shot.item_name, shot.item_template_name, CHILD_ACTION_NAME, CHILD_SUB_ACTION, shot.is_critical_strike, power_level)
	end
end

-- Puddles. Where a glob bursts it adds its goo to the puddle there (or makes one), and a puddle with too much
-- goo bursts into small globs. The puddles are kept here by the game that has the enemies, the host's, where
-- the areas that burn are made. A puddle's area (area damage unit) is made again with every goo that is added,
-- for the radius it has then (the old one stops, its effects fade on their own).
local puddles = {} -- { id, position, normal (Vector3Boxes), goo, expires = the time it dries up, unit = its area }
local next_puddle_id = 0

local function puddle_radius(goo)
	return math.min(CONFIG.glob_puddle_radius * math.sqrt(goo), CONFIG.puddle_radius_max)
end

local function puddle_duration(goo)
	return math.min(CONFIG.glob_puddle_duration + (goo - 1) * CONFIG.puddle_duration_per_goo, CONFIG.puddle_duration_max)
end

local function remove_puddle_area(puddle)
	if puddle.unit and Unit.alive(puddle.unit) then
		Managers.state.unit_spawner:mark_for_deletion(puddle.unit)
	end

	puddle.unit = nil
end

-- Whoever is in the puddle: the players (and bots) and the enemies in its radius, as a set. Stepping into a puddle
-- is being in it when it wasn't a moment ago (what was in it when it was made or grew isn't stepping in).
local query_units = {}

local function units_inside(puddle)
	local inside = {}
	local position = puddle.position:unbox()
	local radius = puddle_radius(puddle.goo)
	local side = Managers.state.side:get_side_from_name("heroes")

	if not side then
		return inside
	end

	for _, unit in ipairs(side.PLAYER_AND_BOT_UNITS) do
		if Unit.alive(unit) and HEALTH_ALIVE[unit] and Vector3.distance(Unit.world_position(unit, 0), position) < radius then
			inside[unit] = true
		end
	end

	local num_units = AiUtils.broadphase_query(position, radius, query_units, side.enemy_broadphase_categories)

	for i = 1, num_units do
		local unit = query_units[i]

		if HEALTH_ALIVE[unit] then
			inside[unit] = true
		end
	end

	return inside
end

-- The fire of a puddle, on every machine: the host plays it and tells the others (the game's own look of an area can't
-- be told to the others, and doesn't grow with the area). It is one effect, scaled to the radius, that is played again
-- when the puddle grows.
local visuals = {} -- { [the id of the puddle] = { effect, expires } }

local function stop_visual(id)
	local visual = visuals[id]

	if visual then
		visuals[id] = nil

		effects.stop(visual.effect)
	end
end

local function show_visual(id, world, position, radius, charged, duration)
	stop_visual(id)

	local effect = effects.start(world, charged and CONFIG.charged_puddle_effect or CONFIG.puddle_effect, position, radius / CONFIG.puddle_effect_natural_radius)

	if effect then
		visuals[id] = {
			effect = effect,
			expires = Managers.time:time("game") + duration,
		}
	end
end

local function update_visuals(t)
	for id, visual in pairs(visuals) do
		if t >= visual.expires then
			stop_visual(id)
		end
	end
end

local function clear_visuals()
	for id, visual in pairs(visuals) do
		effects.destroy(visual.effect)

		visuals[id] = nil
	end
end

mod:network_register("ut_bio_puddle_look", function (_, id, x, y, z, radius, charged, duration)
	show_visual(id, Managers.world:world("level_world"), Vector3(x, y, z), radius, charged, duration)
end)

mod:network_register("ut_bio_puddle_end", function (_, id)
	stop_visual(id)
end)

local function end_puddle_visual(puddle)
	stop_visual(puddle.id)
	mod:network_send("ut_bio_puddle_end", "others", puddle.id)
end

-- The area of the puddle for the goo it has. puddle.context is what the glob that made the puddle was:
-- { world, owner_unit, item_name, item_template_name, is_critical_strike, base_power }
local function make_puddle_area(puddle, t)
	remove_puddle_area(puddle)

	local context = puddle.context
	local radius = puddle_radius(puddle.goo)
	local position = puddle.position:unbox()
	local duration = math.max(puddle.expires - t, 1)
	local charged = puddle.goo >= CONFIG.big_puddle_goo

	puddle.unit = DamageUtils.create_aoe(context.world, context.owner_unit, position, context.item_name, ExplosionTemplates.ut_bio_puddle, radius, duration)
	puddle.inside = units_inside(puddle)

	show_visual(puddle.id, context.world, position, radius, charged, duration)
	mod:network_send("ut_bio_puddle_look", "others", puddle.id, position.x, position.y, position.z, radius, charged, duration)
end

local function play_puddle_burst_effects(world, position, goo_scale)
	for _, effect in ipairs(CONFIG.burst_effects) do
		effects.play(world, effect.name, position + Vector3(0, 0, 0.5), math.lerp(CONFIG.puddle_burst_effect_scale, CONFIG.puddle_burst_effect_scale_max, goo_scale))
	end
end

-- (the burst is seen by everyone: the host tells the others)
mod:network_register("ut_bio_puddle_burst", function (_, x, y, z, goo_scale)
	play_puddle_burst_effects(Managers.world:world("level_world"), Vector3(x, y, z), goo_scale)
end)

-- The burst of a puddle: a blast that is as big as the goo was, and the small globs
-- (with final, the puddle is gone after it, nothing of it stays)
local function burst_puddle(puddle, t, final)
	remove_puddle_area(puddle)

	local context = puddle.context
	local goo_scale = math.clamp(puddle.goo / CONFIG.charged_goo, 0, 1)
	local position = puddle.position:unbox()
	local power_level = context.base_power * math.max(CONFIG.glob_damage / CONFIG.charged_glob_damage, goo_scale)

	with_valid_positions(DamageUtils.create_explosion, context.world, context.owner_unit, position, Quaternion.identity(), ExplosionTemplates.ut_bio_charged_burst, goo_scale, context.item_name, true, false, context.owner_unit, power_level, context.is_critical_strike, context.owner_unit)

	play_puddle_burst_effects(context.world, position, goo_scale)
	mod:network_send("ut_bio_puddle_burst", "others", position.x, position.y, position.z, goo_scale)

	local kept_goo = final and 0 or math.min(puddle.goo * CONFIG.burst_goo_left, CONFIG.burst_goo_left_max)
	local count = math.clamp(math.floor((puddle.goo * (1 - CONFIG.burst_goo_loss) - kept_goo) / CONFIG.child_goo_min), 0, CONFIG.child_count_max)

	throw_children(context, position, puddle.normal:unbox(), count, context.base_power)

	if final then
		end_puddle_visual(puddle)

		return
	end

	-- some of the puddle stays where it was
	puddle.goo = kept_goo
	puddle.expires = t + puddle_duration(puddle.goo)

	make_puddle_area(puddle, t)
end

local function goo_of(self)
	local action = self._current_action

	if action.ut_bio_goo_by_charge then
		-- (the goo goes from charged_goo_min at the charge where the glob can first be fired, not from zero)
		local first_charge = CONFIG.min_fire_time / CONFIG.charge_time
		local progress = math.clamp(((self.scale or 1) - first_charge) / (1 - first_charge), 0, 1)

		return math.lerp(CONFIG.charged_goo_min, CONFIG.charged_goo, charge_heat_progress(progress))
	end

	if action.ut_bio_goo_range then
		return math.lerp(action.ut_bio_goo_range[1], action.ut_bio_goo_range[2], math.clamp(self.scale or 0, 0, 1))
	end

	return action.ut_bio_goo or 1
end

-- Adds goo to the puddles (on the host). context is what the glob that makes the puddle was, see make_puddle_area.
local function add_goo_to_puddles(context, position, normal, goo, bursts_puddle)
	local t = Managers.time:time("game")

	-- the puddle the glob lands in: the nearest one that it is inside of (and that hasn't gone out, see update_puddles)
	local puddle
	local nearest = math.huge

	for _, other in ipairs(puddles) do
		local offset = other.position:unbox() - position
		local distance = Vector3.length(Vector3.flat(offset))

		if t < other.expires and distance < puddle_radius(other.goo) + CONFIG.puddle_merge_margin and math.abs(offset.z) < CONFIG.puddle_merge_height and distance < nearest then
			puddle = other
			nearest = distance
		end
	end

	if puddle then
		puddle.goo = puddle.goo + goo
	else
		next_puddle_id = next_puddle_id + 1

		puddle = {
			context = context,
			goo = goo,
			id = next_puddle_id,
			normal = Vector3Box(normal),
			position = Vector3Box(position),
		}
		puddles[#puddles + 1] = puddle
	end

	puddle.expires = t + puddle_duration(puddle.goo)

	-- A puddle bursts when it has too much goo, and when something steps into it: the glob of the alt fire is
	-- that, it bursts the puddle it lands in however much goo there is.
	if puddle.goo >= CONFIG.burst_goo or bursts_puddle then
		burst_puddle(puddle, t)
	else
		make_puddle_area(puddle, t)
	end
end

-- The puddles belong to the host (it has the enemies and makes the areas that burn). A glob of the host adds its goo
-- there; the glob of a client bursts on the client's machine, which tells the host.
mod:network_register("ut_bio_goo", function (_, owner_go_id, item_name, is_critical_strike, base_power, x, y, z, normal_x, normal_y, normal_z, goo, bursts_puddle)
	mod:echo("bio goo received: host %s, owner %s, goo %s", tostring(Managers.player.is_server), tostring(owner_go_id), tostring(goo))

	if not Managers.player.is_server then
		return
	end

	local owner_unit = Managers.state.unit_storage:unit(owner_go_id)

	if not owner_unit or not Unit.alive(owner_unit) then
		mod:echo("bio goo: no owner unit")

		return
	end

	local context = {
		base_power = base_power,
		is_critical_strike = is_critical_strike,
		item_name = item_name,
		item_template_name = TEMPLATE_NAME,
		owner_unit = owner_unit,
		world = Managers.world:world("level_world"),
	}

	add_goo_to_puddles(context, Vector3(x, y, z), Vector3(normal_x, normal_y, normal_z), goo, bursts_puddle)
end)

local function add_goo(self, position)
	local normal_box = self._ut_bio_hit_normal
	local normal = normal_box and normal_box:unbox() or Vector3.up()
	local goo = goo_of(self)
	local bursts_puddle = self._current_action.ut_bio_bursts_puddle or false
	-- (the power of the glob, the power it would have had uncharged)
	local base_power = self.power_level / math.max(self._current_action.scale_power_level or 1, self.charge_level or 0)

	if not self._is_server then
		mod:echo("bio goo sent: goo %s", tostring(goo))
		mod:network_send("ut_bio_goo", "others", Managers.state.unit_storage:go_id(self._owner_unit), self.item_name, self._is_critical_strike or false, base_power, position.x, position.y, position.z, normal.x, normal.y, normal.z, goo, bursts_puddle)

		return
	end

	add_goo_to_puddles({
		base_power = base_power,
		is_critical_strike = self._is_critical_strike,
		item_name = self.item_name,
		item_template_name = self.action_lookup_data.item_template_name,
		owner_unit = self._owner_unit,
		world = self._world,
	}, position, normal, goo, bursts_puddle)
end

-- Whatever steps into a puddle bursts it
local function update_puddles(t)
	if not Managers.player.is_server then
		return
	end

	for i = #puddles, 1, -1 do
		local puddle = puddles[i]

		if not Unit.alive(puddle.context.owner_unit) then
			-- (the player's unit is gone, a hero was changed or the level left: nothing can be made for it, the game
			-- breaks on a projectile that has no owner)
			remove_puddle_area(puddle)
			end_puddle_visual(puddle)
			table.remove(puddles, i)
		elseif t >= puddle.expires then
			-- a puddle that goes out with nothing stepped into it bursts (and is gone), unless it is too small
			table.remove(puddles, i)

			if puddle.goo >= CONFIG.step_burst_goo then
				burst_puddle(puddle, t, true)
			end
		elseif puddle.inside then
			local inside = units_inside(puddle)
			local stepped_in = false

			for unit in pairs(inside) do
				if not puddle.inside[unit] then
					stepped_in = true

					break
				end
			end

			puddle.inside = inside

			if stepped_in and puddle.goo >= CONFIG.step_burst_goo then
				burst_puddle(puddle, t)
			end
		end
	end
end

-- The bursts of the globs add their goo (the impact of a glob on an enemy, which also goes through do_aoe, is not
-- one, and neither is the burst of a puddle)
local GOO_BURSTS = {
	[ExplosionTemplates.ut_bio_burst] = true,
	[ExplosionTemplates.ut_bio_charged_glob] = true,
	[ExplosionTemplates.ut_bio_child_burst] = true,
}

mod.aoe_callbacks.ut_bio_glob = function (self, aoe_data, position)
	if not GOO_BURSTS[aoe_data] or self._ut_bio_goo_added then
		return
	end

	self._ut_bio_goo_added = true

	add_goo(self, position)
end

-- A glob that hits an enemy sets off the impact (once, however many it hits on its way)
mod.hit_enemy_callbacks.ut_bio_glob = function (func, self, is_owner, impact_data, hit_unit, hit_position, ...)
	func(self, impact_data, hit_unit, hit_position, ...)

	-- (only the projectile of the player who fired: the other peers get the impact from the network)
	if not is_owner then
		return
	end

	local template_name = self._current_action.ut_bio_impact_template

	if template_name and not self._ut_bio_impact then
		self._ut_bio_impact = true

		self:do_aoe(ExplosionTemplates[template_name], hit_position)
	end
end

mod:hook_safe(PlayerProjectileUnitExtension, "mark_for_deletion", function (self)
	local action = self._current_action

	if action and action.ut_bio_glob and self._deletion_time and not self._ut_bio_fizzle then
		self._ut_bio_fizzle = true
		self._deletion_time = Managers.time:time("game") + CONFIG.glob_fizzle_time
	end
end)

-- The template is shared game state: it is patched in place, what is touched is saved to be put
-- back on disable, and when the mod is unloaded (a reload would take the patched template for the original).
local saved = {}

local function restore_drakegun()
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

	-- Already applied by a previous load of this mod, start over from the original
	restore_drakegun()

	local actions = template.actions
	local original = {
		action_one_default = actions.action_one.default,
		action_one_shoot_charged = actions.action_one.shoot_charged,
		action_two_default = actions.action_two.default,
		required_projectile_unit_templates = {},
	}

	template.required_projectile_unit_templates = template.required_projectile_unit_templates or {}

	for _, name in ipairs(PROJECTILE_UNIT_TEMPLATES) do
		original.required_projectile_unit_templates[name] = template.required_projectile_unit_templates[name]
		template.required_projectile_unit_templates[name] = true
	end

	saved.original = original

	local glob = build_glob_action()
	local charged = build_charged_action()

	utils.set_lookup_data(glob, TEMPLATE_NAME, "action_one", "default")
	utils.set_lookup_data(charged, TEMPLATE_NAME, "action_one", "shoot_charged")

	local child = build_child_action()

	utils.set_lookup_data(child, TEMPLATE_NAME, CHILD_ACTION_NAME, CHILD_SUB_ACTION)

	actions[CHILD_ACTION_NAME][CHILD_SUB_ACTION] = child

	actions.action_one.default = glob
	actions.action_one.shoot_charged = charged

	-- the charge: the glob is fired when the button is let go (and when the primary is pressed, the game's own chain)
	local charge = table.clone(original.action_two_default)

	charge.charge_time = CONFIG.charge_time
	-- (the release the glob waits for has to be one after the charge started)
	charge.enter_function = enter_function
	-- the charge makes the weapon hot as it goes
	charge.overcharge_interval = CONFIG.charge_heat_interval
	charge.ut_charge_callback = "bio"
	charge.overcharge_type = "ut_bio_charging"
	-- (Kept from the Drakegun's own charge, remove_overcharge_on_interrupt: a full charge adds almost no more heat, so
	-- it can be held at full without overheating, and some of the heat is taken back if the charge is cancelled.)
	charge.allowed_chain_actions[#charge.allowed_chain_actions + 1] = {
		action = "action_one",
		auto_chain = true,
		release_required = "action_two_hold",
		start_time = CONFIG.min_fire_time,
		sub_action = "shoot_charged",
	}
	actions.action_two.default = charge
end

-- The mod holds its own references to the units of the globs while the weapon is enabled
local packages = utils.package_holder("unreal_tournament_bio")

local function enable_bio_rifle()
	packages.load_projectile_units(PROJECTILE_UNIT_TEMPLATES)
	apply_bio_rifle()
end

-- (the weapon can be switched off in the settings: the drakegun is then the game's own again, the weapon the player
-- holds changes when it is wielded again)
local function disable_bio_rifle()
	restore_drakegun()
	packages.unload()
end

utils.register_weapon("bio_rifle", enable_bio_rifle, disable_bio_rifle)

-- The overheating explosion of the weapon (the game's own is kept, and hurts the player) throws small globs, with
-- random amounts of goo, out of the player. (It is told by the hook in hooks.lua.)
mod.overheat_callbacks[TEMPLATE_NAME] = function (state, item_data)
	if not utils.is_weapon_enabled("bio_rifle") then
		return
	end

	local unit = state.unit
	local shot = {
		is_critical_strike = false,
		item_name = item_data.name,
		item_template_name = TEMPLATE_NAME,
		owner_unit = unit,
	}

	throw_children(shot, Unit.world_position(unit, 0) + Vector3(0, 0, 1.5), Vector3.up(), CONFIG.overheat_glob_count, CONFIG.burn_reference_power_level, true)
end

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	-- (there is no game time outside of a level)
	local t = Managers.time:time("game")

	if not t then
		return
	end

	update_delayed_ends(t)
	update_puddles(t)
	update_visuals(t)
end

local function clear_all()
	table.clear(delayed_ends)
	table.clear(puddles)
	table.clear(charge_levels)
	clear_visuals()
end

mod.unload_callbacks[#mod.unload_callbacks + 1] = clear_all
mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = clear_all
