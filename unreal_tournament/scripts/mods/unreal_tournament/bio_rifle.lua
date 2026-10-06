local mod = get_mod("unreal_tournament")

-- Bio Rifle: replaces the Drakegun's (Bardin) actions in place, like the other weapons do.
--   LMB: a glob of goo, lobbed. It bursts where it lands and leaves a burning puddle.
--   RMB (held): charges a bigger glob, fired on release. The bigger the charge, the bigger the burst and the
--               puddle. (UT2004: XWeapons/BioRifle, BioGlob.)
-- Overheating takes the place of ammo: the Drakegun's own.

local registration = mod:dofile("scripts/mods/unreal_tournament/registration")
local effects = mod:dofile("scripts/mods/unreal_tournament/effects")
local register_damage_profile = registration.register_damage_profile
local register_explosion_template = registration.register_explosion_template
local make_flat = registration.make_flat
local attack_power_for = registration.attack_power_for
local impact_power_for = registration.impact_power_for

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
	glob_damage = 25, -- in UT2004's units, 45 is the shock rifle's beam
	glob_burst_radius = 1.5, -- m
	glob_puddle_radius = 1.2, -- m
	glob_puddle_duration = 4, -- seconds
	-- Charged: the charge level (0 to 1) goes from the primary's numbers to these. The big glob leaves the
	-- puddle of a regular one (glob_puddle_radius, glob_puddle_duration) and, when it bursts, throws smaller
	-- globs in a small arc to random directions, each of which makes a puddle where it lands. The more charge,
	-- the more of them.
	charge_time = 2, -- seconds to a full charge
	charged_glob_speed = 3000,
	charged_glob_damage = 70,
	charged_burst_radius = 4,
	child_count_min = 2,
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
	child_puddle_radius = 1, -- m
	child_puddle_duration = 4, -- seconds
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
	puddle_effect_radius_share = 0.35,
	puddle_effect_spacing = 0.9, -- m between the particles
	-- Overheating, in the Drakegun's own units (it overheats at 30): a glob is this much, a full charge is
	-- this much by the time it is full (the shot that follows doesn't add any). Balanced against the Shock
	-- Rifle's, whose beam is 4 every 0.7 seconds (5.7 a second, a combo is 12 more): a glob every 0.45 seconds
	-- is 7.8 a second, a bit more for the burst and the puddle it brings, and the charge is 5.5 a second.
	glob_overcharge = 3.5,
	charged_overcharge = 11,
	-- The sounds, events of the game's: the Sienna's fireball and geiser for the shots (the shots' have to be
	-- in the game's NetworkLookup of sound events, the others are not sent), the fire grenade's explosion and
	-- the fireball's hit for the bursts and the impacts
	fire_sound = "player_combat_weapon_staff_fireball_fire",
	charged_fire_sound = "player_combat_weapon_staff_geiser_fire",
	burst_sound = "fireball_big_hit",
	charged_burst_sound = "player_combat_weapon_fire_grenade_explosion",
	impact_sound = "fireball_big_hit",
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
	-- The impact: a glob that hits an enemy sets off a blast of its own on top of the burst (the burst's
	-- radius and the puddle are the same). The charged glob's is as big as it is charged.
	impact_damage = 15,
	impact_radius = 3, -- m
	charged_impact_damage = 40,
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
-- (added every CHARGE_HEAT_INTERVAL seconds while charging, together they are charged_overcharge)
local CHARGE_HEAT_INTERVAL = 0.2
overcharge_values.ut_bio_charging = CONFIG.charged_overcharge * CHARGE_HEAT_INTERVAL / CONFIG.charge_time

-- Damage profiles: the direct hit of a glob only staggers, its damage is the burst (like the shock ball)
register_damage_profile("ut_bio_glob", "staff_fireball", function (profile)
	make_flat(profile, 0, impact_power_for(CONFIG.glob_damage))

	profile.cleave_distribution = {
		attack = 0.01,
		impact = 0.01,
	}
end)

-- The burn of the puddle: the game's burning dot with a power of its own. A burn ticks at the game's default
-- power level (195, what the weapons' profiles are measured against is about 500).
local BURN_REFERENCE_POWER_LEVEL = 500

register_damage_profile(CONFIG.puddle_dot, "burning_dot", function (profile)
	profile.default_target.power_distribution = {
		attack = attack_power_for(CONFIG.puddle_tick_damage) * BURN_REFERENCE_POWER_LEVEL / DefaultPowerLevel,
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
registration.register_network_lookup("buff_templates", CONFIG.puddle_dot)

local function burst_profiles(name, damage)
	local function modify(profile)
		make_flat(profile, attack_power_for(damage), impact_power_for(damage))
	end

	register_damage_profile(name, "fireball_charged_explosion", modify)
	register_damage_profile(name .. "_glance", "fireball_charged_explosion_glance", modify)
end

burst_profiles("ut_bio_burst", CONFIG.glob_damage)
burst_profiles("ut_bio_charged_burst", CONFIG.charged_glob_damage)
burst_profiles("ut_bio_child_burst", CONFIG.child_damage)
burst_profiles("ut_bio_impact", CONFIG.impact_damage)
burst_profiles("ut_bio_charged_impact", CONFIG.charged_impact_damage)

-- Explosion templates: the burst, and the puddle it leaves (the aoe of the template). The charged one has a
-- radius that goes with the charge level (the scale of the projectile).
local function burst_template(burst_profile_name, sound_event_name, puddle_effect, radius_min, radius_max, puddle_radius, puddle_duration)
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
		aoe = {
			area_damage_template = "explosion_template_aoe",
			attack_template = "fire_grenade_dot",
			damage_interval = CONFIG.puddle_damage_interval,
			dot_template_name = CONFIG.puddle_dot,
			duration = puddle_duration,
			radius = puddle_radius,
			nav_mesh_effect = {
				particle_name = puddle_effect,
				particle_radius = puddle_radius * CONFIG.puddle_effect_radius_share,
				particle_spacing = CONFIG.puddle_effect_spacing,
			},
		},
	}
end

register_explosion_template("ut_bio_burst", burst_template("ut_bio_burst", CONFIG.burst_sound, CONFIG.puddle_effect, CONFIG.glob_burst_radius, CONFIG.glob_burst_radius, CONFIG.glob_puddle_radius, CONFIG.glob_puddle_duration))
register_explosion_template("ut_bio_charged_burst", burst_template("ut_bio_charged_burst", CONFIG.charged_burst_sound, CONFIG.charged_puddle_effect, CONFIG.glob_burst_radius, CONFIG.charged_burst_radius, CONFIG.glob_puddle_radius, CONFIG.glob_puddle_duration))
register_explosion_template("ut_bio_child_burst", burst_template("ut_bio_child_burst", CONFIG.burst_sound, CONFIG.puddle_effect, CONFIG.child_burst_radius, CONFIG.child_burst_radius, CONFIG.child_puddle_radius, CONFIG.child_puddle_duration))

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

register_explosion_template("ut_bio_impact", impact_template("ut_bio_impact", CONFIG.impact_sound, CONFIG.impact_radius, CONFIG.impact_radius))
register_explosion_template("ut_bio_charged_impact", impact_template("ut_bio_charged_impact", CONFIG.charged_impact_sound, CONFIG.impact_radius, CONFIG.charged_impact_radius))

-- The look of the burst and of the impact, on every peer (the explosion's callback is run for everyone who sees it)
mod.explosion_callbacks = mod.explosion_callbacks or {}

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
mod.explosion_callbacks.ut_bio_impact = play_impact_effects
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
registration.register_network_lookup("projectile_gravity_settings", CHILD_GRAVITY_SETTINGS)

registration.register_network_lookup("sub_actions", CHILD_SUB_ACTION)

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
		ut_bio_impact_template = "ut_bio_impact",
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
		ut_aoe_callback = "ut_bio_charged",
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
			aoe = ExplosionTemplates.ut_bio_charged_burst,
			damage_profile = "ut_bio_glob",
		},
		timed_data = {
			aoe = ExplosionTemplates.ut_bio_charged_burst,
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
		ut_bio_glob = true,
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

-- After a projectile has hit something the game keeps its unit for a short time (0.3 seconds) before taking it
-- away, so that its trail can fade out. That is cut short for the trail of the globs, the unit is kept
-- glob_fizzle_time seconds.
-- The game also tells the unit that the projectile has ended the moment it hits, which ends its effects
-- at once. For the globs that signal is held back and sent glob_end_delay seconds later.
local GAME_DELETION_GRACE = 0.3
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

-- The way out of the wall, floor or ceiling the charged glob hits is told to the glob before its burst is made
-- (the game gives the burst only the place)
for _, function_name in ipairs({
	"hit_level_unit",
	"hit_non_level_unit",
}) do
	mod:hook(PlayerProjectileUnitExtension, function_name, function (func, self, impact_data, hit_unit, hit_position, hit_direction, hit_normal, ...)
		local action = self._current_action

		if action and action.ut_aoe_callback == "ut_bio_charged" and hit_normal then
			self._ut_bio_hit_normal = Vector3Box(hit_normal)
		end

		return func(self, impact_data, hit_unit, hit_position, hit_direction, hit_normal, ...)
	end)
end

-- When the charged glob bursts, smaller globs are thrown out of it in a small arc, in random directions. They
-- are projectiles of the weapon's own action (CHILD_SUB_ACTION), spawned like a shot is: the more the glob was
-- charged, the more of them. (The burst is told apart from the impact of the glob on an enemy, which also goes
-- through do_aoe, by its template.)
mod.aoe_callbacks = mod.aoe_callbacks or {}
mod.aoe_callbacks.ut_bio_charged = function (self, aoe_data, position)
	if aoe_data ~= ExplosionTemplates.ut_bio_charged_burst or self._ut_bio_children then
		return
	end

	self._ut_bio_children = true

	local charge = math.clamp(self.scale or 1, 0, 1)
	local count = math.floor(math.lerp(CONFIG.child_count_min, CONFIG.child_count_max, charge) + 0.5)
	-- Away from the surface the glob burst on: up from a floor, down from a ceiling, out from a wall (up when it
	-- burst in the air or on an enemy)
	local normal_box = self._ut_bio_hit_normal
	local normal = normal_box and normal_box:unbox() or Vector3.up()
	local start = position + normal * CONFIG.child_start_height
	local lookup_data = self.action_lookup_data
	local helper_axis = math.abs(normal.z) < 0.9 and Vector3.up() or Vector3.right()
	local tangent_a = Vector3.normalize(Vector3.cross(normal, helper_axis))
	local tangent_b = Vector3.cross(normal, tangent_a)
	-- (the power the glob would have uncharged: the small globs have their own damage)
	local power_level = self.power_level / math.max(self._current_action.scale_power_level or 1, self.charge_level or 0)

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

		ActionUtils.spawn_player_projectile(self._owner_unit, start, Quaternion.look(direction), 100, angle, target_vector, speed, self.item_name, lookup_data.item_template_name, CHILD_ACTION_NAME, CHILD_SUB_ACTION, self._is_critical_strike, power_level)
	end
end

-- A glob that hits an enemy sets off the impact (once, however many it hits on its way)
mod.hit_enemy_callbacks = mod.hit_enemy_callbacks or {}
mod.hit_enemy_callbacks.ut_bio_glob = function (self, hit_unit, hit_position)
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
		self._deletion_time = self._deletion_time - GAME_DELETION_GRACE + CONFIG.glob_fizzle_time
	end
end)

-- The template is shared game state: it is patched in place, what is touched is saved to be put
-- back on disable. The saved values are in a persistent table, so that a mod reload doesn't take
-- the patched template for the original.
local persistent = mod:persistent_table("bio_rifle")

local function restore_drakegun()
	local original = persistent.original
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

	persistent.original = nil
end

local function set_lookup_data(action, action_name, sub_action_name)
	action.lookup_data = {
		item_template_name = TEMPLATE_NAME,
		action_name = action_name,
		sub_action_name = sub_action_name,
	}
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

	persistent.original = original

	local glob = build_glob_action()
	local charged = build_charged_action()

	set_lookup_data(glob, "action_one", "default")
	set_lookup_data(charged, "action_one", "shoot_charged")

	local child = build_child_action()

	set_lookup_data(child, CHILD_ACTION_NAME, CHILD_SUB_ACTION)

	actions[CHILD_ACTION_NAME][CHILD_SUB_ACTION] = child

	actions.action_one.default = glob
	actions.action_one.shoot_charged = charged

	-- the charge: the glob is fired when the button is let go (and still when the primary is pressed)
	local charge = table.clone(original.action_two_default)

	charge.charge_time = CONFIG.charge_time
	-- (the release the glob waits for has to be one after the charge started)
	charge.enter_function = enter_function
	-- the charge makes the weapon hot as it goes, the shot itself doesn't
	charge.overcharge_interval = CHARGE_HEAT_INTERVAL
	charge.overcharge_type = "ut_bio_charging"
	charge.allowed_chain_actions[#charge.allowed_chain_actions + 1] = {
		action = "action_one",
		auto_chain = true,
		release_required = "action_two_hold",
		start_time = 0.3,
		sub_action = "shoot_charged",
	}
	actions.action_two.default = charge
end

-- Projectile units are only loaded with the characters that use them (a projectile that is spawned unloaded
-- crashes the game), so the mod holds its own references to the units of the globs while enabled.
local PACKAGE_REFERENCE_NAME = "unreal_tournament_bio"

local function load_projectile_packages()
	persistent.packages = persistent.packages or {}

	if not Managers.package then
		return
	end

	for _, name in ipairs(PROJECTILE_UNIT_TEMPLATES) do
		local package_name = ProjectileUnits[name].projectile_unit_name

		if not persistent.packages[package_name] then
			Managers.package:load(package_name, PACKAGE_REFERENCE_NAME)

			persistent.packages[package_name] = true
		end
	end
end

local function unload_projectile_packages()
	for package_name in pairs(persistent.packages or {}) do
		persistent.packages[package_name] = nil

		if Managers.package then
			pcall(Managers.package.unload, Managers.package, package_name, PACKAGE_REFERENCE_NAME)
		end
	end
end

-- The weapon can be switched off in the settings: the drakegun is then the game's own again (the weapon the
-- player holds changes when it is wielded again)
local function is_bio_rifle_enabled()
	return mod:get("ut_weapons") ~= false and mod:get("bio_rifle") ~= false
end

local previous_on_enabled = mod.on_enabled
local previous_on_disabled = mod.on_disabled
local previous_on_setting_changed = mod.on_setting_changed
local previous_update = mod.update
local previous_on_unload = mod.on_unload

mod.on_enabled = function (...)
	if previous_on_enabled then
		previous_on_enabled(...)
	end

	if is_bio_rifle_enabled() then
		load_projectile_packages()
		apply_bio_rifle()
	end
end

mod.on_disabled = function (...)
	if previous_on_disabled then
		previous_on_disabled(...)
	end

	restore_drakegun()
	unload_projectile_packages()
end

mod.on_setting_changed = function (setting_id, ...)
	if previous_on_setting_changed then
		previous_on_setting_changed(setting_id, ...)
	end

	if setting_id == "bio_rifle" or setting_id == "ut_weapons" then
		if is_bio_rifle_enabled() then
			load_projectile_packages()
			apply_bio_rifle()
		else
			restore_drakegun()
			unload_projectile_packages()
		end
	end
end

mod.update = function (dt, ...)
	if previous_update then
		previous_update(dt, ...)
	end

	update_delayed_ends(Managers.time:time("game"))
	effects.update(dt)
end

mod.on_unload = function (...)
	if previous_on_unload then
		previous_on_unload(...)
	end

	table.clear(delayed_ends)
	effects.clear()
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(delayed_ends)
	effects.clear()
end
