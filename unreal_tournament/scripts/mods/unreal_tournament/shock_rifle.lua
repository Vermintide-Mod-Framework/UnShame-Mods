local mod = get_mod("unreal_tournament")

-- Shock Rifle: replaces the Beam Staff's (Sienna) actions in place.
--   LMB: instant hitscan beam
--   RMB: slow, straight-flying shock ball that explodes on impact
--   Hitting the ball with the beam detonates it in a large "shock combo" explosion

local TEMPLATE_NAME = "staff_blast_beam_template_1"

local CONFIG = {
	-- Idle pose: the raised pose of the beam staff's continuous beam (without its zoom) is used
	-- as the default pose. Set idle_pose_event to nil to keep the regular staff pose.
	idle_pose_event = "attack_shoot_beam_start",
	idle_pose_delay = 0.4, -- seconds after wielding before the pose is entered
	-- The pose animation shakes, so once the pose is reached it is played at this speed
	-- (1 = normal) to turn the shaking into slow, natural looking movement
	idle_pose_speed = 0.15,
	idle_pose_slow_delay = 0.35, -- seconds the raise animation gets to play at normal speed
	idle_pose_wield_slow_delay = 3, -- same, after wielding (the raise is slower there)
	-- The shot animations blend back to the regular idle pose when they finish, so the raised
	-- pose is re-entered this many seconds after a shot instead of when the action ends
	-- (beam_fire_rate / ball_fire_rate). Tune to the length of the shot animations.
	beam_pose_return_time = 0.35,
	ball_pose_return_time = 0.5,
	-- Beam
	beam_fire_rate = 0.7, -- UT2004 ShockBeamFire.FireRate
	beam_fire_time = 0, -- delay between pressing fire and the shot
	beam_range = 60, -- trail length when the beam doesn't hit anything
	trail_effect = "fx/wpnfx_staff_beam_trail_remap",
	trail_duration = 0.45,
	trail_width = 0.3,
	-- Ball
	ball_speed = 1400, -- throw_trajectory divides by 100, so this is 14 m/s (walking is ~4-5 m/s)
	ball_radius = 0.2, -- impact sphere, how easily the ball hits things (unrelated to the beam hitting it)
	ball_visual_scale = 3, -- size multiplier of the projectile unit
	ball_charge_level = 0.99, -- drives the projectile scale; kept under 1 to avoid "full charge" procs
	ball_lifetime = 5,
	ball_fire_rate = 0.6, -- UT2004 ShockProjFire.FireRate
	ball_fire_time = 0.27,
	-- Combo
	combo_pick_radius = 0.6, -- how close the beam has to pass to the ball's center
	combo_max_range = 100,
	-- Damage, relative values taken from UT2004 (XWeapons/ShockBeamFire.uc, ShockProjectile.uc):
	-- beam 45, ball splash 45 (radius 150 uu), combo 200 (radius 275 uu).
	-- The beam and the ball's splash are given the same damage, the combo is 200 / 45 times that.
	beam_attack_power = 0.7, -- multiplier on the weapon's power level, this is what sets the damage
	beam_impact_power = 0.3, -- same for stagger
	combo_damage_multiplier = 200 / 45,
	meters_per_uu = 0.02, -- Unreal unit to meters (a UT2004 player is ~88 uu / 1.8 m)
	ball_explosion_radius_uu = 150,
	combo_explosion_radius_uu = 275,
	explosion_full_damage_radius = 0.5, -- damage falls off linearly from here to the radius
	-- Friendly fire is scaled to nothing on lower difficulties, so damage to yourself from the
	-- combo is applied separately: this much at the center, falling off like the explosion
	combo_self_damage = 100,
	-- The ball's own explosion hurts the shooter as well, in the same way (half of the ball's damage in UT's
	-- numbers, like the combo's is half of its damage)
	ball_self_damage = 18,
	-- Combo visuals: the blast first throws out a ring, then everything that died gets pulled
	-- back to the center, like in UT. Only effects the game already ships can be used, they are
	-- skipped if the game hasn't loaded them.
	-- The fire explosion at the center of the blast. Effects can only be made bigger or smaller
	-- through the scale, they can't be sped up.
	combo_fire_sphere_effect = "fx/wpnfx_staff_geiser_fire_large",
	combo_fire_sphere_scale = 0.25, -- size relative to the effect's normal size
	combo_flash_effect = "fx/wpnfx_fireball_charged_impact_remap", -- played with the fire explosion
	-- The shockwave is the horizontal ring effect played three times in perpendicular
	-- orientations to make a shell, with another effect played on top of it
	combo_shockwave_extra_effect = "fx/brw_adept_skill_03",
	-- Vertical offsets in meters (+ up, - down) of each part from the center of the explosion.
	-- The shockwave effects were made to be played at a character's feet and have a height of
	-- their own, which put the shockwave above the explosion.
	combo_flash_offset = 0,
	combo_fire_sphere_offset = 0,
	combo_shockwave_extra_offset = -1,
	-- The implosion rings: particle effects can't be played backwards and their scale can't be
	-- changed while they play, so the implosion is a series of rings, each created smaller than
	-- the last, spread over implosion_duration. The scales are relative to the effect's normal size.
	implosion_ring_count = 4,
	implosion_ring_start_scale = 1.5,
	implosion_ring_end_scale = 0.3,
	combo_ring_effect = "fx/chr_kruber_shockwave",
	combo_ring_offset = -1, -- meters, moves the rings up (+) or down (-) from the center
	-- Bodies are thrown away from the blast first: whatever has died (and started to ragdoll) in
	-- the first implosion_delay seconds gets thrown once, then everything is pulled back in.
	implosion_blast_speed = 14, -- m/s, a little less for bodies far from the center
	implosion_blast_up = 5, -- m/s added upwards
	implosion_delay = 0.6, -- seconds after the blast before bodies start being pulled in
	implosion_duration = 0.6,
	-- The pull is a gravity: it speeds the bodies up toward the center (their own speed is kept), they go through
	-- it and fly off on the other side when the pull ends. It softens close to the center so there is no
	-- sudden stop or kick.
	implosion_pull = 90, -- m/s^2
	implosion_pull_softening = 1, -- m, the pull is weaker than this close to the center
	implosion_max_speed = 30, -- m/s
	-- Overcharge: the regular shots cost this much of what the staff's own shots do, and the
	-- combo costs this many shots' worth of the beam on top of the beam shot that set it off
	-- (UT2004 ShockProjectile.ComboAmmoCost = 3, on top of the beam's own 1 ammo).
	overcharge_scale = 0.5,
	combo_overcharge_multiplier = 3,
	-- Overheating the weapon sets off a combo at the player (the shooter isn't hurt by it, the game's overheating
	-- explosion does that). It has no shot to take a power level from, so it is given one.
	overheat_combo_height = 1, -- m above the player
	overheat_combo_power_level = 500,
}

-- Overcharge costs, derived from the staff's own values
local overcharge_values = PlayerUnitStatusSettings.overcharge_values

overcharge_values.ut_shock_beam = overcharge_values.beam_staff_sniper * CONFIG.overcharge_scale
overcharge_values.ut_shock_ball = overcharge_values.ut_shock_beam

-- Gravity of 0 is already defined by the game (used by the drake pistols), reusing it avoids
-- having to extend NetworkLookup.projectile_gravity_settings
local BALL_GRAVITY_SETTINGS = "drake_pistols"

-- Registration of new named data (must exist on every peer in the same order,
-- everyone in the game needs the mod)

local registration = mod:dofile("scripts/mods/unreal_tournament/registration")
local register_damage_profile = registration.register_damage_profile
local register_explosion_template = registration.register_explosion_template

-- Spread: the beam is hitscan and should hit exactly where the crosshair is

local function zero_numbers(tbl)
	for key, value in pairs(tbl) do
		if type(value) == "table" then
			zero_numbers(value)
		elseif type(value) == "number" then
			tbl[key] = 0
		end
	end
end

SpreadTemplates.ut_shock_beam = table.clone(SpreadTemplates.handgun)

zero_numbers(SpreadTemplates.ut_shock_beam)

-- Damage profiles
-- The beam and the explosions share the armor modifiers and only differ in the power factor, see
-- registration.lua.

local make_flat = registration.make_flat

-- The multipliers of the damage and the stagger per armor type: unarmored, armored, monsters, players,
-- berserkers, super armor (the game's own for beams is 0 against super armor, which is what chaos warriors
-- have, it would do next to nothing to them)
local ARMOR_ATTACK = {
	1,
	0.8,
	1.5,
	1,
	1,
	0.5,
}
local ARMOR_IMPACT = {
	1,
	0.8,
	1,
	1,
	1,
	0.5,
}

local function set_armor_modifiers(profile)
	profile.armor_modifier.attack = table.clone(ARMOR_ATTACK)
	profile.armor_modifier.impact = table.clone(ARMOR_IMPACT)
end

local function register_explosion_damage_profiles(name, damage_multiplier)
	local function modify(profile)
		make_flat(profile, CONFIG.beam_attack_power * damage_multiplier, CONFIG.beam_impact_power * damage_multiplier)
		set_armor_modifiers(profile)
	end

	register_damage_profile(name, "fireball_charged_explosion", modify)
	register_damage_profile(name .. "_glance", "fireball_charged_explosion_glance", modify)
end

register_damage_profile("ut_shock_beam", "beam_shot", function (profile)
	make_flat(profile, CONFIG.beam_attack_power, CONFIG.beam_impact_power)
	set_armor_modifiers(profile)
end)
-- The ball's direct hit deals no damage of its own: like in UT the damage is the explosion,
-- which is at full strength for whatever the ball hits. The direct hit only staggers.
register_damage_profile("ut_shock_ball", "staff_fireball", function (profile)
	make_flat(profile, 0, CONFIG.beam_impact_power)

	-- Keep the cleave tiny so the ball detonates on the first enemy it hits
	profile.cleave_distribution = {
		attack = 0.01,
		impact = 0.01,
	}
end)
register_explosion_damage_profiles("ut_shock_ball_explosion", 1)
register_explosion_damage_profiles("ut_shock_combo_explosion", CONFIG.combo_damage_multiplier)

-- Explosion templates
-- Plain `radius` is used (not radius_min/radius_max) because the explosion would otherwise
-- depend on the projectile's scale. attacker_power_level_offset = 1 makes the power level
-- independent of it as well.

register_explosion_template("ut_shock_ball_explosion", {
	-- shields don't block the explosion (see the hook of create_explosion)
	ut_penetrates_shields = true,
	explosion = {
		alert_enemies = true,
		alert_enemies_radius = 10,
		attacker_power_level_offset = 1,
		damage_profile = "ut_shock_ball_explosion",
		damage_profile_glance = "ut_shock_ball_explosion_glance",
		effect_name = "fx/wpnfx_fireball_charged_impact_remap",
		-- the shooter is hurt separately, see ball_self_damage
		ignore_attacker_unit = true,
		max_damage_radius = CONFIG.explosion_full_damage_radius,
		radius = CONFIG.ball_explosion_radius_uu * CONFIG.meters_per_uu,
		sound_event_name = "fireball_big_hit",
		use_attacker_power_level = true,
	},
})
register_explosion_template("ut_shock_combo_explosion", {
	ut_penetrates_shields = true,
	explosion = {
		alert_enemies = true,
		alert_enemies_radius = 30,
		attacker_power_level_offset = 1,
		damage_profile = "ut_shock_combo_explosion",
		damage_profile_glance = "ut_shock_combo_explosion_glance",
		-- The shooter is handled separately, see apply_combo_self_damage
		ignore_attacker_unit = true,
		max_damage_radius = CONFIG.explosion_full_damage_radius,
		radius = CONFIG.combo_explosion_radius_uu * CONFIG.meters_per_uu,
		sound_event_name = "fireball_big_hit",
		use_attacker_power_level = true,
		camera_effect = {
			far_distance = 25,
			far_scale = 0.15,
			near_distance = 6,
			near_scale = 0.75,
			shake_name = "frag_grenade_explosion",
		},
	},
})

-- Weapon template

-- Delayed pose events: the animation event is only sent while is_valid() still holds,
-- so nothing is sent if the weapon was swapped or another action started in the meantime
local pending_poses = {}

local function schedule(delay, is_valid, callback)
	pending_poses[#pending_poses + 1] = {
		callback = callback,
		is_valid = is_valid,
		time_left = delay,
	}
end

-- attack_speed is the animation speed variable the weapon animations are played with,
-- every action sets it again when it starts
local function set_animation_speed(first_person_extension, speed)
	first_person_extension:animation_set_variable("attack_speed", speed)
end

local function slow_down_idle_pose(first_person_extension, is_valid, delay)
	schedule(delay or CONFIG.idle_pose_slow_delay, is_valid, function ()
		set_animation_speed(first_person_extension, CONFIG.idle_pose_speed)
	end)
end

local function enter_idle_pose(first_person_extension, unit_1p, is_valid, slow_delay)
	Unit.animation_event(unit_1p, CONFIG.idle_pose_event)
	slow_down_idle_pose(first_person_extension, is_valid, slow_delay)
end

-- Re-enters the pose after a shot, unless another action has started in the meantime
local function schedule_pose_return(weapon_extension, action, delay)
	if not CONFIG.idle_pose_event then
		return
	end

	local function is_valid()
		return weapon_extension.current_action_settings == action
	end

	schedule(delay, is_valid, function ()
		enter_idle_pose(weapon_extension.first_person_extension, weapon_extension.first_person_unit, function ()
			local current_action = weapon_extension.current_action_settings

			return current_action == action or current_action == nil
		end)
	end)
end

-- Refire logic of UT2004 (WeaponFire / Weapon.StartFire / Weapon.ReadyToFire):
--   * Each mode fires again FireRate seconds after its previous shot.
--   * A mode that starts after the other one fired waits for the other's cooldown too
--     (NextFireTime = max(own, other's)), "preventing rapidly alternating fire modes".
--   * While one fire button is held the other mode can't fire (both are bModeExclusive).
--   * Holding fire repeats the shot.
-- The shot happens fire_time seconds into an action, so the delays below are measured from
-- the start of the action to make the time between the shots exact.
local BEAM_TO_BEAM = CONFIG.beam_fire_rate
local BEAM_TO_BALL = math.max(CONFIG.beam_fire_time + CONFIG.beam_fire_rate - CONFIG.ball_fire_time, 0)
local BALL_TO_BALL = CONFIG.ball_fire_rate
local BALL_TO_BEAM = math.max(CONFIG.ball_fire_time + CONFIG.ball_fire_rate - CONFIG.beam_fire_time, 0)
local BEAM_TOTAL_TIME = math.max(BEAM_TO_BEAM, BEAM_TO_BALL)
local BALL_TOTAL_TIME = math.max(BALL_TO_BALL, BALL_TO_BEAM)

local function fire_chain_entries(own_action, other_action, own_delay, other_delay)
	local own_hold = own_action .. "_hold"
	local other_hold = other_action .. "_hold"

	return {
		{
			action = own_action,
			input = own_action,
			start_time = own_delay,
			sub_action = "default",
		},
		{
			action = own_action,
			input = own_hold,
			start_time = own_delay,
			sub_action = "default",
		},
		{
			action = other_action,
			blocking_input = own_hold,
			input = other_action,
			start_time = other_delay,
			sub_action = "default",
		},
		{
			action = other_action,
			blocking_input = own_hold,
			input = other_hold,
			start_time = other_delay,
			sub_action = "default",
		},
	}
end

local function allowed_chain_actions(fire_entries, wield_start_time, reload_start_time)
	local entries = {
		{
			action = "action_wield",
			input = "action_wield",
			start_time = wield_start_time,
			sub_action = "default",
		},
		{
			action = "weapon_reload",
			input = "weapon_reload",
			start_time = reload_start_time,
			sub_action = "default",
		},
	}

	for i = 1, #fire_entries do
		entries[#entries + 1] = fire_entries[i]
	end

	return entries
end

local function build_beam_action()
	local action

	action = {
		alert_sound_range_fire = 12,
		anim_event = "attack_shoot_beam_spark",
		charge_value = "light_attack",
		damage_profile = "ut_shock_beam",
		damage_window_end = 0,
		damage_window_start = 0.1,
		fire_sound_event = "weapon_staff_fire_beam_end_shot",
		fire_time = CONFIG.beam_fire_time,
		headshot_multiplier = 2,
		hit_effect = "fireball_impact",
		is_spell = true,
		kind = "handgun",
		overcharge_type = "ut_shock_beam",
		reset_aim_on_attack = true,
		spread_template_override = "ut_shock_beam",
		total_time = BEAM_TOTAL_TIME,
		ut_shock_beam = true,
		allowed_chain_actions = allowed_chain_actions(fire_chain_entries("action_one", "action_two", BEAM_TO_BEAM, BEAM_TO_BALL), 0.2, 0.2),
		enter_function = function (attacker_unit, input_extension, remaining_time, weapon_extension)
			input_extension:clear_input_buffer()
			table.clear(pending_poses)
			schedule_pose_return(weapon_extension, action, CONFIG.beam_pose_return_time)

			return input_extension:reset_release_input()
		end,
	}

	return action
end

local function build_ball_action()
	-- The charged fireball unit is built to be scaled up (times_bigger, driven by the charge level)
	local projectile_info = table.clone(Projectiles.fireball_charged)

	projectile_info.gravity_settings = BALL_GRAVITY_SETTINGS
	projectile_info.radius = CONFIG.ball_radius
	projectile_info.times_bigger = CONFIG.ball_visual_scale
	projectile_info.unit_life_time = CONFIG.ball_lifetime

	local action

	action = {
		alert_sound_range_fire = 12,
		alert_sound_range_hit = 2,
		anim_event = "attack_shoot_fireball",
		apply_recoil = true,
		charge_value = "light_attack",
		fire_sound_event = "player_combat_weapon_staff_fireball_fire",
		fire_sound_event_parameter = "drakegun_charge_fire",
		fire_sound_on_husk = true,
		fire_time = CONFIG.ball_fire_time,
		forced_charge_level = CONFIG.ball_charge_level,
		hit_effect = "fireball_impact",
		is_spell = true,
		kind = "charged_projectile",
		overcharge_type = "ut_shock_ball",
		speed = CONFIG.ball_speed,
		total_time = BALL_TOTAL_TIME,
		ut_shock_ball = true,
		ut_aoe_callback = "shock_ball",
		allowed_chain_actions = allowed_chain_actions(fire_chain_entries("action_two", "action_one", BALL_TO_BALL, BALL_TO_BEAM), 0.3, 0.3),
		enter_function = function (attacker_unit, input_extension, remaining_time, weapon_extension)
			input_extension:clear_input_buffer()
			table.clear(pending_poses)
			schedule_pose_return(weapon_extension, action, CONFIG.ball_pose_return_time)

			return input_extension:reset_release_input()
		end,
		projectile_info = projectile_info,
		impact_data = {
			damage_profile = "ut_shock_ball",
			aoe = ExplosionTemplates.ut_shock_ball_explosion,
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

	return action
end

local function set_lookup_data(actions)
	for action_name, sub_actions in pairs(actions) do
		for sub_action_name, sub_action in pairs(sub_actions) do
			sub_action.lookup_data = {
				item_template_name = TEMPLATE_NAME,
				action_name = action_name,
				sub_action_name = sub_action_name,
			}
		end
	end
end

-- The staff template is shared game state, so it is patched in place and every
-- touched value is saved to be put back on disable. The saved values live in a persistent
-- table so that a mod reload doesn't mistake the patched template for the vanilla one.

local persistent = mod:persistent_table("shock_rifle")
local ATTACK_META_DATA_FIELDS = {
	"can_charge_shot",
	"charged_attack_action_name",
	"fire_input",
	"max_range",
}

local function restore_beam_staff()
	local original = persistent.original
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not original or not template then
		return
	end

	local actions = template.actions

	actions.action_one = original.action_one
	actions.action_two = original.action_two
	actions.weapon_reload.default.anim_end_event = original.reload_anim_end_event
	actions.weapon_reload.default.finish_function = original.reload_finish_function
	actions.weapon_reload.default.enter_function = original.reload_enter_function

	for _, field in ipairs(ATTACK_META_DATA_FIELDS) do
		template.attack_meta_data[field] = original.attack_meta_data[field]
	end

	template.tooltip_compare = original.tooltip_compare
	template.tooltip_detail = original.tooltip_detail
	template.required_projectile_unit_templates.fireball_charged = original.ball_projectile_units_required

	persistent.original = nil
end

local function apply_shock_rifle()
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not template then
		return
	end

	-- Already applied by a previous load of this mod, start over from the vanilla values
	restore_beam_staff()

	local actions = template.actions
	local attack_meta_data = template.attack_meta_data
	local original = {
		action_one = actions.action_one,
		action_two = actions.action_two,
		reload_anim_end_event = actions.weapon_reload.default.anim_end_event,
		reload_finish_function = actions.weapon_reload.default.finish_function,
		reload_enter_function = actions.weapon_reload.default.enter_function,
		attack_meta_data = {},
		tooltip_compare = template.tooltip_compare,
		tooltip_detail = template.tooltip_detail,
		ball_projectile_units_required = template.required_projectile_unit_templates.fireball_charged,
	}

	for _, field in ipairs(ATTACK_META_DATA_FIELDS) do
		original.attack_meta_data[field] = attack_meta_data[field]
	end

	persistent.original = original

	-- Only the two fire modes are replaced, everything else (wield, inspect, reload,
	-- career actions) and changes other mods made to it stay untouched
	actions.action_one = {
		default = build_beam_action(),
	}
	actions.action_two = {
		default = build_ball_action(),
	}

	set_lookup_data({
		action_one = actions.action_one,
		action_two = actions.action_two,
	})

	-- The vent/reload action also returns to the raised pose when it ends (its end event is
	-- skipped when it is interrupted, see its anim_end_event_condition_func)
	actions.weapon_reload.default.anim_end_event = CONFIG.idle_pose_event or original.reload_anim_end_event
	-- Venting right after wielding: the raise to the pose would play over the heat release
	actions.weapon_reload.default.enter_function = function (...)
		table.clear(pending_poses)

		if original.reload_enter_function then
			return original.reload_enter_function(...)
		end
	end
	actions.weapon_reload.default.finish_function = function (owner_unit, reason, weapon_extension)
		if original.reload_finish_function then
			original.reload_finish_function(owner_unit, reason, weapon_extension)
		end

		if CONFIG.idle_pose_event and reason ~= "new_interupting_action" then
			slow_down_idle_pose(weapon_extension.first_person_extension, function ()
				return weapon_extension.current_action_settings == nil
			end)
		end
	end

	-- The bot AI and tooltips reference the removed charged/blast sub actions
	attack_meta_data.can_charge_shot = false
	attack_meta_data.charged_attack_action_name = nil
	attack_meta_data.fire_input = "fire"
	attack_meta_data.max_range = 50

	template.tooltip_compare = {
		light = {
			action_name = "action_one",
			sub_action_name = "default",
		},
		heavy = {
			action_name = "action_two",
			sub_action_name = "default",
		},
	}
	template.tooltip_detail = template.tooltip_compare

	-- The ball's projectile unit has to be loaded when the staff is wielded
	template.required_projectile_unit_templates.fireball_charged = false
end

-- Shock combo: a beam passing through a live shock ball detonates it

local function find_ball_hit_by_beam(physics_world, owner_unit, origin, direction)
	local projectile_system = Managers.state.entity:system("projectile_system")
	local owner_projectiles = projectile_system.player_projectile_units[owner_unit]

	if not owner_projectiles then
		return nil
	end

	local wall_distance = CONFIG.combo_max_range
	local wall_hit, _, hit_distance = PhysicsWorld.immediate_raycast(physics_world, origin, direction, CONFIG.combo_max_range, "closest", "collision_filter", "filter_player_ray_projectile_static_only")

	if wall_hit and hit_distance then
		wall_distance = hit_distance
	end

	local best_unit, best_distance

	for projectile_unit, _ in pairs(owner_projectiles) do
		local extension = Unit.alive(projectile_unit) and ScriptUnit.has_extension(projectile_unit, "projectile_system")
		local action = extension and extension._current_action

		if action and action.ut_shock_ball and not extension:are_impacts_stopped() then
			local ball_position = POSITION_LOOKUP[projectile_unit]
			local to_ball = ball_position - origin
			local along = Vector3.dot(to_ball, direction)

			if along > 0 and along < wall_distance then
				local closest_point = origin + direction * along
				local miss_distance = Vector3.length(ball_position - closest_point)

				if miss_distance <= CONFIG.combo_pick_radius and (not best_distance or along < best_distance) then
					best_unit = projectile_unit
					best_distance = along
				end
			end
		end
	end

	return best_unit
end

local function apply_combo_self_damage(owner_unit, position, item_name)
	registration.apply_explosion_self_damage(owner_unit, position, item_name, ExplosionTemplates.ut_shock_combo_explosion.explosion, CONFIG.combo_self_damage)
end

-- The ball's own explosion hurts the shooter. (The do_aoe of the ball is also what makes the combo go off:
-- that one is told apart by the explosion it is given.)
mod.aoe_callbacks = mod.aoe_callbacks or {}
mod.aoe_callbacks.shock_ball = function (self, aoe_data, position)
	if aoe_data ~= ExplosionTemplates.ut_shock_ball_explosion or self._ut_shock_ball_exploded then
		return
	end

	self._ut_shock_ball_exploded = true

	registration.apply_explosion_self_damage(self._owner_unit, position, self.item_name, ExplosionTemplates.ut_shock_ball_explosion.explosion, CONFIG.ball_self_damage)
end

local function detonate_ball(projectile_unit, owner_unit)
	local extension = ScriptUnit.extension(projectile_unit, "projectile_system")
	local position = POSITION_LOOKUP[projectile_unit]

	-- network_sync makes the explosion go through the area damage system, which also applies damage on the server
	extension:do_aoe(ExplosionTemplates.ut_shock_combo_explosion, position, true)
	apply_combo_self_damage(owner_unit, position, extension.item_name)

	local overcharge_extension = ScriptUnit.extension(owner_unit, "overcharge_system")

	overcharge_extension:add_charge(overcharge_values.ut_shock_beam * CONFIG.combo_overcharge_multiplier)
	extension:stop()
end

local PACKAGE_REFERENCE_NAME = "unreal_tournament"

-- Combo implosion: after the blast, ragdolls of whatever died get pulled toward the center, and go past it.
-- This runs on every peer (create_explosion is called on all of them for networked explosions),
-- ragdoll physics is simulated locally on each.

local implosions = {}

local function is_effect_available(effect_name)
	local ok, available = pcall(Application.can_get, "particles", effect_name)

	return ok and available
end

local function create_effect(world, effect_name, position, rotation)
	if is_effect_available(effect_name) then
		World.create_particles(world, effect_name, position, rotation or Quaternion.identity())
	end
end

-- Particle effects are scaled by linking them to a unit with a scale, so effects that need
-- a size get an invisible helper unit.
local FX_UNIT_NAME = "units/hub_elements/empty"

local function spawn_fx_unit(position, scale)
	local unit = Managers.state.unit_spawner:spawn_local_unit(FX_UNIT_NAME, position, Quaternion.identity())

	Unit.set_local_scale(unit, 0, Vector3(scale, scale, scale))

	return unit
end

local function delete_fx_unit(unit)
	if unit and Unit.alive(unit) then
		Managers.state.unit_spawner:mark_for_deletion(unit)
	end
end

-- policy: what happens to the effect when the unit is deleted, "stop" (stops spawning, the
-- particles already out fade on their own) or "destroy"
local function link_effect(world, effect_name, unit, rotation, policy)
	local effect_id = World.create_particles(world, effect_name, POSITION_LOOKUP[unit])

	World.link_particles(world, effect_id, unit, 0, Matrix4x4.from_quaternion(rotation), policy)

	return effect_id
end

-- Scaled effects are destroyed after a while, in case they would never end
local timed_effects = {}
local TIMED_EFFECT_LIFETIME = 3

local function create_timed_effect(world, effect_name, position, scale, rotation)
	local unit = spawn_fx_unit(position, scale)

	timed_effects[#timed_effects + 1] = {
		age = 0,
		effect_id = link_effect(world, effect_name, unit, rotation or Quaternion.identity(), "stop"),
		unit = unit,
		world = world,
	}
end

local function destroy_timed_effect(effect)
	-- the effect or the world may already be gone
	pcall(World.destroy_particles, effect.world, effect.effect_id)
	delete_fx_unit(effect.unit)
end

local function update_timed_effects(dt)
	for i = #timed_effects, 1, -1 do
		local effect = timed_effects[i]

		effect.age = effect.age + dt

		if effect.age >= TIMED_EFFECT_LIFETIME then
			destroy_timed_effect(effect)
			table.remove(timed_effects, i)
		end
	end
end

local function clear_timed_effects()
	for i = #timed_effects, 1, -1 do
		destroy_timed_effect(timed_effects[i])

		timed_effects[i] = nil
	end
end

local function create_fire_sphere(world, position)
	local effect_name = CONFIG.combo_fire_sphere_effect

	if effect_name and is_effect_available(effect_name) then
		create_timed_effect(world, effect_name, position + Vector3(0, 0, CONFIG.combo_fire_sphere_offset), CONFIG.combo_fire_sphere_scale)
	end
end

-- Vectors and quaternions are temporary objects and can't be kept around between frames,
-- so the ring orientations are created when needed
local function ring_rotations()
	return {
		Quaternion.identity(),
		Quaternion.axis_angle(Vector3(1, 0, 0), math.pi / 2),
		Quaternion.axis_angle(Vector3(0, 1, 0), math.pi / 2),
	}
end

local function create_ring_shell(world, position)
	if not CONFIG.combo_ring_effect then
		return
	end

	local ring_position = position + Vector3(0, 0, CONFIG.combo_ring_offset)
	local rotations = ring_rotations()

	for i = 1, #rotations do
		create_effect(world, CONFIG.combo_ring_effect, ring_position, rotations[i])
	end
end

-- One ring of the implosion, at the given scale. The effects are created with their scale
-- already set, see create_timed_effect.
local function create_implosion_ring(world, position, scale)
	if not CONFIG.combo_ring_effect or not is_effect_available(CONFIG.combo_ring_effect) then
		return
	end

	local ring_position = position + Vector3(0, 0, CONFIG.combo_ring_offset)
	local rotations = ring_rotations()

	for i = 1, #rotations do
		create_timed_effect(world, CONFIG.combo_ring_effect, ring_position, scale, rotations[i])
	end
end

local function units_in_radius(world, position, radius)
	local physics_world = World.physics_world(world)
	local actors, num_actors = PhysicsWorld.immediate_overlap(physics_world, "shape", "sphere", "position", position, "size", radius, "collision_filter", "filter_explosion_overlap")
	local units = {}

	for i = 1, num_actors do
		local unit = Actor.unit(actors[i])
		local breed = unit and Unit.alive(unit) and AiUtils.unit_breed(unit)

		if breed and not breed.is_player then
			units[unit] = true
		end
	end

	return units
end

local function start_implosion(world, position)
	local radius = ExplosionTemplates.ut_shock_combo_explosion.explosion.radius

	if CONFIG.combo_flash_effect then
		create_effect(world, CONFIG.combo_flash_effect, position + Vector3(0, 0, CONFIG.combo_flash_offset))
	end

	create_fire_sphere(world, position)
	create_ring_shell(world, position)

	if CONFIG.combo_shockwave_extra_effect then
		create_effect(world, CONFIG.combo_shockwave_extra_effect, position + Vector3(0, 0, CONFIG.combo_shockwave_extra_offset))
	end

	implosions[#implosions + 1] = {
		position = Vector3Box(position),
		blasted = {},
		-- the way each body was from the center when it was first pulled, and if it has been past it
		pulled = {},
		radius = radius,
		rings_created = 0,
		start_t = Managers.time:time("game"),
		units = units_in_radius(world, position, radius),
		world = world,
	}
end

-- Where a ragdoll is (its first dynamic actor), nil if it isn't one yet
local function ragdoll_position(unit)
	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		if actor and Actor.is_dynamic(actor) then
			return Actor.position(actor)
		end
	end
end

local function pull_ragdoll(unit, center, dt)
	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		-- animation driven (not yet ragdolled) actors aren't dynamic
		if actor and Actor.is_dynamic(actor) then
			local offset = center - Actor.position(actor)
			local distance = Vector3.length(offset)
			local pull = offset * (CONFIG.implosion_pull / math.max(distance, CONFIG.implosion_pull_softening))
			local velocity = Actor.velocity(actor) + pull * dt
			local speed = Vector3.length(velocity)

			if speed > CONFIG.implosion_max_speed then
				velocity = velocity * (CONFIG.implosion_max_speed / speed)
			end

			Actor.set_velocity(actor, velocity)
		end
	end
end

-- Throws a ragdoll away from the center, returns true once it was (the ragdoll has to have
-- started, before that its actors are driven by animation)
local function blast_ragdoll(unit, center, radius)
	local thrown = false

	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		if actor and Actor.is_dynamic(actor) then
			local offset = Actor.position(actor) - center
			local distance = Vector3.length(offset)
			local direction = distance > 0.01 and offset * (1 / distance) or Vector3.up()
			local speed = CONFIG.implosion_blast_speed * math.lerp(1, 0.5, math.clamp(distance / radius, 0, 1))

			Actor.set_velocity(actor, direction * speed + Vector3(0, 0, CONFIG.implosion_blast_up))

			thrown = true
		end
	end

	return thrown
end

local function clear_implosions()
	for i = #implosions, 1, -1 do
		implosions[i] = nil
	end
end

local function update_implosions(dt)
	local t = Managers.time:time("game")
	local ring_count = CONFIG.implosion_ring_count
	local ring_interval = CONFIG.implosion_duration / ring_count

	for i = #implosions, 1, -1 do
		local implosion = implosions[i]
		local age = t - implosion.start_t
		local center = implosion.position:unbox()

		if age >= CONFIG.implosion_delay + CONFIG.implosion_duration then
			table.remove(implosions, i)
		elseif age < CONFIG.implosion_delay then
			-- blast phase: the damage has been applied, throw out what died
			for unit in pairs(implosion.units) do
				if not Unit.alive(unit) then
					implosion.units[unit] = nil
				elseif not HEALTH_ALIVE[unit] and not implosion.blasted[unit] and blast_ragdoll(unit, center, implosion.radius) then
					implosion.blasted[unit] = true
				end
			end
		elseif age >= CONFIG.implosion_delay then
			-- rings, each smaller than the last, spread over the duration
			local rings_due = math.min(math.floor((age - CONFIG.implosion_delay) / ring_interval) + 1, ring_count)

			while implosion.rings_created < rings_due do
				local progress = ring_count > 1 and implosion.rings_created / (ring_count - 1) or 1

				create_implosion_ring(implosion.world, center, math.lerp(CONFIG.implosion_ring_start_scale, CONFIG.implosion_ring_end_scale, progress))

				implosion.rings_created = implosion.rings_created + 1
			end

			for unit in pairs(implosion.units) do
				if not Unit.alive(unit) then
					implosion.units[unit] = nil
				elseif not HEALTH_ALIVE[unit] then
					-- A body that has gone past the center is let go, it is not pulled back
					local body_position = ragdoll_position(unit)

					if body_position then
						local offset = body_position - center
						local state = implosion.pulled[unit]

						if not state then
							local distance = Vector3.length(offset)

							state = {
								direction = Vector3Box(distance > 0.01 and offset * (1 / distance) or Vector3.up()),
							}
							implosion.pulled[unit] = state
						end

						if not state.passed and Vector3.dot(offset, state.direction:unbox()) < 0 then
							state.passed = true
						end

						if not state.passed then
							pull_ragdoll(unit, center, dt)
						end
					end
				end
			end
		end
	end
end

-- Explosions of the weapons are run by their names, on every peer (one hook for all of them)
mod.explosion_callbacks = mod.explosion_callbacks or {}
mod.explosion_callbacks.ut_shock_combo_explosion = function (world, impact_position)
	start_implosion(world, impact_position)
end

-- Explosions that go through shields: the game asks AiUtils.attack_is_shield_blocked for every enemy in
-- an explosion, which is answered "not blocked" while the explosion of such a template is being made.
local penetrating_explosion = false

mod:hook(AiUtils, "attack_is_shield_blocked", function (func, ...)
	if penetrating_explosion then
		return false
	end

	return func(...)
end)

mod:hook(DamageUtils, "create_explosion", function (func, world, attacker_unit, impact_position, rotation, explosion_template, ...)
	penetrating_explosion = not not explosion_template.ut_penetrates_shields

	-- (an error mustn't leave the flag set)
	local ok, error_message = pcall(func, world, attacker_unit, impact_position, rotation, explosion_template, ...)

	penetrating_explosion = false

	if not ok then
		error(error_message, 0)
	end

	local callback = mod.explosion_callbacks[explosion_template.name]

	if callback then
		callback(world, impact_position, rotation)
	end
end)

-- Beam trail: the staff's own beam particle, stretched from the muzzle to the hit point
-- and shrunk to nothing over trail_duration

local trails = {}

local function destroy_trail(trail)
	-- the world may already be gone (level transition)
	pcall(World.destroy_particles, trail.world, trail.effect_id)
end

local function spawn_trail(action, origin, direction)
	local world = action.world
	local physics_world = action.physics_world
	local result = PhysicsWorld.immediate_raycast_actors(physics_world, origin, direction, "static_collision_filter", "filter_player_ray_projectile_static_only", "dynamic_collision_filter", "filter_player_ray_projectile_ai_only", "dynamic_collision_filter", "filter_player_ray_projectile_hitbox_only")
	local end_position = result and result[#result][1] or origin + direction * CONFIG.beam_range
	local weapon_unit = action.weapon_unit
	local muzzle_position = Unit.world_position(weapon_unit, Unit.node(weapon_unit, "fx_muzzle"))
	local trail_direction = Vector3.normalize(muzzle_position - end_position)
	local effect_id = World.create_particles(world, CONFIG.trail_effect, end_position, Quaternion.look(trail_direction))
	local length_variable_id = World.find_particles_variable(world, CONFIG.trail_effect, "trail_length")

	trails[#trails + 1] = {
		age = 0,
		distance = Vector3.distance(muzzle_position, end_position),
		effect_id = effect_id,
		length_variable_id = length_variable_id,
		world = world,
	}
end

local function update_pending_poses(dt)
	for i = #pending_poses, 1, -1 do
		local pending = pending_poses[i]

		pending.time_left = pending.time_left - dt

		if pending.time_left <= 0 then
			table.remove(pending_poses, i)

			if pending.is_valid() then
				pending.callback()
			end
		end
	end
end

mod.update = function (dt)
	update_pending_poses(dt)
	update_implosions(dt)
	update_timed_effects(dt)

	for i = #trails, 1, -1 do
		local trail = trails[i]

		trail.age = trail.age + dt

		local fade = 1 - trail.age / CONFIG.trail_duration

		if fade <= 0 then
			destroy_trail(trail)
			table.remove(trails, i)
		else
			pcall(World.set_particles_variable, trail.world, trail.effect_id, trail.length_variable_id, Vector3(CONFIG.trail_width * fade * fade, trail.distance, 0))
		end
	end
end

local function clear_trails()
	for i = #trails, 1, -1 do
		destroy_trail(trails[i])

		trails[i] = nil
	end
end

-- The weapon's package list is built when the staff's packages are loaded, which may be
-- before this mod patched the template, and spawning an unloaded projectile unit crashes
-- the game. So the mod holds its own reference to the ball's unit while enabled.

local function load_ball_package()
	if persistent.ball_package or not Managers.package then
		return
	end

	local package_name = ProjectileUnits.fireball_charged.projectile_unit_name

	Managers.package:load(package_name, PACKAGE_REFERENCE_NAME)

	persistent.ball_package = package_name
end

local function unload_ball_package()
	local package_name = persistent.ball_package

	if not package_name then
		return
	end

	persistent.ball_package = nil

	if Managers.package then
		pcall(Managers.package.unload, Managers.package, package_name, PACKAGE_REFERENCE_NAME)
	end
end

-- The weapon can be switched off in the settings: the staff is then the game's own again (the weapon the
-- player holds changes when it is wielded again)
local function is_shock_rifle_enabled()
	return mod:get("ut_weapons") ~= false and mod:get("shock_rifle") ~= false
end

-- The overheating explosion of a weapon (the game's own hurts the player, and is kept) is told to the weapon's
-- callback in mod.overheat_callbacks, by its template: a function can be hooked once. The shock rifle's is the combo:
-- the whole of it, the blast and the pulling in of what died.
mod.overheat_callbacks = mod.overheat_callbacks or {}

mod:hook_safe(PlayerCharacterStateOverchargeExploding, "explode", function (self)
	if self.inside_inn then
		return
	end

	local inventory_extension = self.inventory_extension
	local slot_name = inventory_extension:get_wielded_slot_name()
	local slot_data = slot_name and inventory_extension:get_slot_data(slot_name)
	local item_data = slot_data and slot_data.item_data
	local callback = item_data and mod.overheat_callbacks[item_data.template]

	if callback then
		callback(self, item_data)
	end
end)

mod.overheat_callbacks[TEMPLATE_NAME] = function (state, item_data)
	if not is_shock_rifle_enabled() then
		return
	end

	local unit = state.unit
	local position = Unit.world_position(unit, 0) + Vector3(0, 0, CONFIG.overheat_combo_height)

	-- (through the area damage system, which also tells the other peers and applies the damage on the server)
	Managers.state.entity:system("area_damage_system"):create_explosion(unit, position, Quaternion.identity(), "ut_shock_combo_explosion", 1, item_data.name, CONFIG.overheat_combo_power_level, false, unit)
end

local function enable_shock_rifle()
	load_ball_package()
	apply_shock_rifle()
end

local function disable_shock_rifle()
	restore_beam_staff()
	clear_trails()
	table.clear(pending_poses)
	clear_implosions()
	clear_timed_effects()
	unload_ball_package()
end

mod.on_enabled = function ()
	if is_shock_rifle_enabled() then
		enable_shock_rifle()
	end
end

mod.on_disabled = function ()
	disable_shock_rifle()
end

mod.on_setting_changed = function (setting_id)
	if setting_id == "shock_rifle" or setting_id == "ut_weapons" then
		if is_shock_rifle_enabled() then
			enable_shock_rifle()
		else
			disable_shock_rifle()
		end
	end
end

mod.on_unload = function ()
	-- A mod reload keeps the patched template, the next load re-applies it
	clear_trails()
	clear_implosions()
	clear_timed_effects()
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	clear_trails()
	clear_implosions()
	clear_timed_effects()
end

mod.wield_callbacks.shock = function (self, equipment, slot_data, unit_1p)
	if not CONFIG.idle_pose_event or not slot_data then
		return
	end

	local first_person_extension = self.first_person_extension

	-- The slowed down animation speed must not leak into other weapons
	if first_person_extension then
		set_animation_speed(first_person_extension, 1)
	end

	local item_template = BackendUtils.get_item_template(slot_data.item_data)

	if item_template.name ~= TEMPLATE_NAME or not is_shock_rifle_enabled() then
		return
	end

	local function is_valid()
		return equipment.wielded == slot_data.item_data
	end

	table.clear(pending_poses)
	schedule(CONFIG.idle_pose_delay, is_valid, function ()
		enter_idle_pose(first_person_extension, unit_1p, is_valid, CONFIG.idle_pose_wield_slow_delay)
	end)
end

mod:hook_safe(ActionHandgun, "client_owner_start_action", function (self, new_action)
	self._ut_combo_checked = not new_action.ut_shock_beam
end)

mod:hook_safe(ActionHandgun, "client_owner_post_update", function (self)
	if self._ut_combo_checked or self.state == "waiting_to_shoot" then
		return
	end

	self._ut_combo_checked = true

	local owner_unit = self.owner_unit
	local first_person_extension = ScriptUnit.extension(owner_unit, "first_person_system")
	local origin, rotation = first_person_extension:get_projectile_start_position_rotation()
	local direction = Quaternion.forward(rotation)

	spawn_trail(self, origin, direction)

	local ball_unit = find_ball_hit_by_beam(self.physics_world, owner_unit, origin, direction)

	if ball_unit then
		detonate_ball(ball_unit, owner_unit)
	end
end)
