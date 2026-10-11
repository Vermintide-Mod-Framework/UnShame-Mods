local mod = get_mod("unreal_tournament")

-- Shock Rifle: replaces the Beam Staff's (Sienna) actions in place.
--   LMB: instant hitscan beam
--   RMB: slow, straight-flying shock ball that explodes on impact
--   Hitting the ball with the beam detonates it in a large "shock combo" explosion

local TEMPLATE_NAME = "staff_blast_beam_template_1"

local CONFIG = {
	-- The multipliers of the damage and the stagger per armor type: unarmored, armored, monsters, players, berserkers,
	-- super armor (the game's own for beams is 0 against super armor, which is what chaos warriors have, it would do
	-- next to nothing to them)
	armor_attack = {1, 0.8, 1.5, 1, 1, 0.5},
	armor_impact = {1, 0.8, 1, 1, 1, 0.5},
	-- Beam
	beam_fire_rate = 0.7, -- UT2004 ShockBeamFire.FireRate
	beam_fire_time = 0, -- delay between pressing fire and the shot
	beam_range = 60, -- length of the beam when it doesn't hit anything
	-- Ball
	ball_speed = 1750, -- throw_trajectory divides by 100, so this is 17.5 m/s (walking is ~4-5 m/s): faster than a running dodge jump, as in UT
	ball_radius = 0.2, -- impact sphere, how easily the ball hits things (unrelated to the beam hitting it)
	ball_visual_scale = 3, -- size multiplier of the projectile unit
	ball_charge_level = 0.99, -- drives the projectile scale; kept under 1 to avoid "full charge" procs
	ball_lifetime = 10, -- UT2004 ShockProjectile.LifeSpan
	ball_fire_rate = 0.6, -- UT2004 ShockProjFire.FireRate
	ball_fire_time = 0, -- the ball leaves as the button is pressed (ShockProjFire has no PreFireTime), like the beam
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
	-- Combo: the blast (the skin draws it) is followed by everything that died being pulled back to the
	-- center, like in UT. Only effects the game already ships can be used, they are skipped if the game
	-- hasn't loaded them.
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

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local effects = mod.effects
local register_damage_profile = utils.register_damage_profile
local register_explosion_template = utils.register_explosion_template

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
-- utils.lua.

local make_flat = utils.make_flat

local function set_armor_modifiers(profile)
	utils.set_armor_modifiers(profile, CONFIG.armor_attack, CONFIG.armor_impact)
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
		-- (no effect and no sound of its own: the skin draws and plays them, see skin_explosion_callbacks)
		-- the shooter is hurt separately, see ball_self_damage
		ignore_attacker_unit = true,
		max_damage_radius = CONFIG.explosion_full_damage_radius,
		radius = CONFIG.ball_explosion_radius_uu * CONFIG.meters_per_uu,
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
		ut_init_callback = "shock_ball",
		ut_init_flow_event_filter = "shock_ball",
		allowed_chain_actions = allowed_chain_actions(fire_chain_entries("action_two", "action_one", BALL_TO_BALL, BALL_TO_BEAM), 0.3, 0.3),
		enter_function = function (attacker_unit, input_extension, remaining_time, weapon_extension)
			input_extension:clear_input_buffer()

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


-- The staff template is shared game state, so it is patched in place and every
-- touched value is saved to be put back on disable, and when the mod is unloaded (a reload would
-- mistake the patched template for the vanilla one).

local saved = {}
local ATTACK_META_DATA_FIELDS = {
	"can_charge_shot",
	"charged_attack_action_name",
	"fire_input",
	"max_range",
}

local function restore_beam_staff()
	local original = saved.original
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not original or not template then
		return
	end

	local actions = template.actions

	actions.action_one = original.action_one
	actions.action_two = original.action_two

	for _, field in ipairs(ATTACK_META_DATA_FIELDS) do
		template.attack_meta_data[field] = original.attack_meta_data[field]
	end

	template.tooltip_compare = original.tooltip_compare
	template.tooltip_detail = original.tooltip_detail
	template.required_projectile_unit_templates.fireball_charged = original.ball_projectile_units_required

	saved.original = nil
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
		attack_meta_data = {},
		tooltip_compare = template.tooltip_compare,
		tooltip_detail = template.tooltip_detail,
		ball_projectile_units_required = template.required_projectile_unit_templates.fireball_charged,
	}

	for _, field in ipairs(ATTACK_META_DATA_FIELDS) do
		original.attack_meta_data[field] = attack_meta_data[field]
	end

	saved.original = original

	-- Only the two fire modes are replaced, everything else (wield, inspect, reload,
	-- career actions) and changes other mods made to it stay untouched
	actions.action_one = {
		default = build_beam_action(),
	}
	actions.action_two = {
		default = build_ball_action(),
	}

	utils.set_actions_lookup_data({
		action_one = actions.action_one,
		action_two = actions.action_two,
	}, TEMPLATE_NAME)

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

-- The balls of every player count, the shooter's and those of the others. The system keeps a list of the projectiles that this
-- machine made (the shooter's); the others' are copies of units that are on their machines, and are found among the extensions of
-- the copies.
local function find_ball_hit_by_beam(physics_world, origin, direction)
	local projectile_system = Managers.state.entity:system("projectile_system")
	local wall_distance = CONFIG.combo_max_range
	local wall_hit, _, hit_distance = PhysicsWorld.immediate_raycast(physics_world, origin, direction, CONFIG.combo_max_range, "closest", "collision_filter", "filter_player_ray_projectile_static_only")

	if wall_hit and hit_distance then
		wall_distance = hit_distance
	end

	local best_unit, best_distance

	local function consider(projectile_unit, extension)
		local action = Unit.alive(projectile_unit) and extension._current_action

		-- (a ball that has hit something has its impacts stopped, the field is the same on the unit and on its copy)
		if action and action.ut_shock_ball and not extension._stop_impacts then
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

	for _, projectiles in pairs(projectile_system.player_projectile_units) do
		for projectile_unit, _ in pairs(projectiles) do
			local extension = Unit.alive(projectile_unit) and ScriptUnit.has_extension(projectile_unit, "projectile_system")

			if extension then
				consider(projectile_unit, extension)
			end
		end
	end

	for projectile_unit, extension in pairs(Managers.state.entity:get_entities("PlayerProjectileHuskExtension")) do
		consider(projectile_unit, extension)
	end

	return best_unit
end

local function apply_combo_self_damage(owner_unit, position, item_name)
	utils.apply_explosion_self_damage(owner_unit, position, item_name, ExplosionTemplates.ut_shock_combo_explosion.explosion, CONFIG.combo_self_damage)
end

-- The ball's own explosion hurts the shooter. (The do_aoe of the ball is also what makes the combo go off:
-- that one is told apart by the explosion it is given.)
mod.aoe_callbacks.shock_ball = function (self, aoe_data, position)
	if aoe_data ~= ExplosionTemplates.ut_shock_ball_explosion or self._ut_shock_ball_exploded then
		return
	end

	self._ut_shock_ball_exploded = true

	utils.apply_explosion_self_damage(self._owner_unit, position, self.item_name, ExplosionTemplates.ut_shock_ball_explosion.explosion, CONFIG.ball_self_damage)
end

-- The ball of another player is a copy on this machine: the combo is the shooter's (it goes through the area damage system, which
-- applies the damage on the server, with the shooter as who does it), and the player whose ball it is is told to end it on their
-- machine, where it flies.
mod:network_register("ut_shock_ball_stop", function (_, ball_go_id)
	local ball_unit = Managers.state.unit_storage:unit(ball_go_id)
	local extension = ball_unit and Unit.alive(ball_unit) and ScriptUnit.has_extension(ball_unit, "projectile_system")

	-- (only the unit that is theirs: the copies can't be told to)
	if extension and extension.are_impacts_stopped then
		extension:stop()
	end
end)

local function detonate_ball(projectile_unit, shooter_unit)
	local extension = ScriptUnit.extension(projectile_unit, "projectile_system")
	local position = POSITION_LOOKUP[projectile_unit]
	local ball_owner_unit = extension._owner_unit

	if ball_owner_unit == shooter_unit then
		-- network_sync makes the explosion go through the area damage system, which also applies damage on the server
		extension:do_aoe(ExplosionTemplates.ut_shock_combo_explosion, position, true)
	else
		local rotation = Unit.local_rotation(projectile_unit, 0)

		Managers.state.entity:system("area_damage_system"):create_explosion(shooter_unit, position, rotation, ExplosionTemplates.ut_shock_combo_explosion.name, extension.scale, extension.item_name, extension.power_level, extension._is_critical_strike, shooter_unit)

		local ball_owner = Managers.player:owner(ball_owner_unit)

		if ball_owner then
			mod:network_send("ut_shock_ball_stop", ball_owner.peer_id, Managers.state.unit_storage:go_id(projectile_unit))
		end
	end

	apply_combo_self_damage(shooter_unit, position, extension.item_name)

	local overcharge_extension = ScriptUnit.extension(shooter_unit, "overcharge_system")

	overcharge_extension:add_charge(overcharge_values.ut_shock_beam * CONFIG.combo_overcharge_multiplier)
	extension:stop()
end

-- Combo implosion: after the blast, ragdolls of whatever died get pulled toward the center, and go past it.
-- This runs on every peer (create_explosion is called on all of them for networked explosions),
-- ragdoll physics is simulated locally on each.

local implosions = {}

-- Vectors and quaternions are temporary objects and can't be kept around between frames,
-- so the ring orientations are created when needed
local function ring_rotations()
	return {
		Quaternion.identity(),
		Quaternion.axis_angle(Vector3(1, 0, 0), math.pi / 2),
		Quaternion.axis_angle(Vector3(0, 1, 0), math.pi / 2),
	}
end

-- One ring of the implosion, at the given scale. The effects are created with their scale
-- already set, see effects.play.
local function create_implosion_ring(world, position, scale)
	if not CONFIG.combo_ring_effect then
		return
	end

	local ring_position = position + Vector3(0, 0, CONFIG.combo_ring_offset)
	local rotations = ring_rotations()

	for i = 1, #rotations do
		effects.play(world, CONFIG.combo_ring_effect, ring_position, scale, rotations[i])
	end
end

local function start_implosion(world, position)
	local radius = ExplosionTemplates.ut_shock_combo_explosion.explosion.radius

	-- (the skin draws the explosion, see skin_explosion_callbacks)
	implosions[#implosions + 1] = {
		position = Vector3Box(position),
		blasted = {},
		-- the way each body was from the center when it was first pulled, and if it has been past it
		pulled = {},
		radius = radius,
		rings_created = 0,
		start_t = Managers.time:time("game"),
		units = utils.units_in_radius(world, position, radius),
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
				elseif not HEALTH_ALIVE[unit] and not implosion.blasted[unit] and utils.blast_ragdoll(unit, center, implosion.radius, CONFIG.implosion_blast_speed, CONFIG.implosion_blast_up) then
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
-- The enemies that are alive in the combo as it goes off: the combo's damage is instant (and it is the host that applies it), so those of
-- them that are not alive after it were killed by it
mod.explosion_before_callbacks.ut_shock_combo_explosion = function (world, impact_position, attacker_unit)
	local alive = {}

	for unit in pairs(utils.units_in_radius(world, impact_position, ExplosionTemplates.ut_shock_combo_explosion.explosion.radius)) do
		if HEALTH_ALIVE[unit] then
			alive[#alive + 1] = unit
		end
	end

	return {
		alive = alive,
		attacker_unit = attacker_unit,
	}
end

mod.explosion_callbacks.ut_shock_combo_explosion = function (world, impact_position, _, before)
	start_implosion(world, impact_position)

	local killed = {}

	for _, unit in ipairs(before.alive) do
		if not HEALTH_ALIVE[unit] then
			killed[#killed + 1] = unit
		end
	end

	for _, callback in pairs(mod.shock_combo_callbacks) do
		callback(before.attacker_unit, killed)
	end
end

-- The beam of the player who fires (the skin draws it, see shock_beam_callbacks): where it ends is told to the other players, who see it
-- from the staff of the player's character
local function spawn_trail(action, origin, direction)
	local physics_world = action.physics_world
	local result = PhysicsWorld.immediate_raycast_actors(physics_world, origin, direction, "static_collision_filter", "filter_player_ray_projectile_static_only", "dynamic_collision_filter", "filter_player_ray_projectile_ai_only", "dynamic_collision_filter", "filter_player_ray_projectile_hitbox_only")
	local hit

	-- (the last of the hits that is not the shooter's own: the beam starts at their head, whose hitbox is in the hits, and a shot into the
	-- sky would end there)
	for i = #(result or {}), 1, -1 do
		if Actor.unit(result[i][4]) ~= action.owner_unit then
			hit = result[i]

			break
		end
	end
	local end_position = hit and hit[1] or origin + direction * CONFIG.beam_range
	-- (the way the surface it hits faces: the vector of no length when it hits nothing)
	local hit_normal = hit and hit[3] or Vector3.zero()
	local weapon_unit = action.weapon_unit
	local muzzle_position = Unit.world_position(weapon_unit, Unit.node(weapon_unit, "fx_muzzle"))

	for _, callback in pairs(mod.shock_beam_callbacks) do
		callback(action.owner_unit, muzzle_position, end_position, hit_normal)
	end

	mod:network_send("ut_shock_trail", "others", Managers.state.unit_storage:go_id(action.owner_unit), end_position.x, end_position.y, end_position.z, hit_normal.x, hit_normal.y, hit_normal.z)
end

mod:network_register("ut_shock_trail", function (_, owner_go_id, x, y, z, normal_x, normal_y, normal_z)
	local unit = Managers.state.unit_storage:unit(owner_go_id)
	local inventory_extension = unit and ScriptUnit.has_extension(unit, "inventory_system")
	local equipment = inventory_extension and inventory_extension:equipment()
	-- (the staff is the right hand's unit, the left hand's is the effect of the fireball: the game's own beam looks for it the same way)
	local weapon_unit = equipment and (equipment.right_hand_wielded_unit_3p or equipment.left_hand_wielded_unit_3p)

	if not weapon_unit or not Unit.alive(weapon_unit) then
		return
	end

	local muzzle_position = Unit.world_position(weapon_unit, Unit.node(weapon_unit, "fx_muzzle"))

	for _, callback in pairs(mod.shock_beam_callbacks) do
		callback(unit, muzzle_position, Vector3(x, y, z), Vector3(normal_x, normal_y, normal_z))
	end
end)

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	update_implosions(dt)
end

-- The weapon's package list is built when the staff's packages are loaded, which may be
-- before this mod patched the template, and spawning an unloaded projectile unit crashes
-- the game. So the mod holds its own reference to the ball's unit while enabled.

local packages = utils.package_holder("unreal_tournament")

-- The overheating explosion (the game's own hurts the player, and is kept): the combo, the whole of it, the blast and
-- the pulling in of what died.
mod.overheat_callbacks[TEMPLATE_NAME] = function (state, item_data)
	if not utils.is_weapon_enabled("shock_rifle") then
		return
	end

	local unit = state.unit
	local position = Unit.world_position(unit, 0) + Vector3(0, 0, CONFIG.overheat_combo_height)

	-- (through the area damage system, which also tells the other peers and applies the damage on the server)
	Managers.state.entity:system("area_damage_system"):create_explosion(unit, position, Quaternion.identity(), "ut_shock_combo_explosion", 1, item_data.name, CONFIG.overheat_combo_power_level, false, unit)
end

-- The weapon's package list is built when the staff's packages are loaded, which may be before this mod patched the
-- template, and spawning an unloaded projectile unit crashes the game. So the mod holds its own reference to the
-- ball's unit while enabled.
local function enable_shock_rifle()
	packages.load_projectile_units({"fireball_charged"})
	apply_shock_rifle()
end

-- (the weapon can be switched off in the settings: the staff is then the game's own again, the weapon the player
-- holds changes when it is wielded again)
local function disable_shock_rifle()
	restore_beam_staff()
	clear_implosions()
	packages.unload()
end

utils.register_weapon("shock_rifle", enable_shock_rifle, disable_shock_rifle)

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	clear_implosions()
end

mod.handgun_start_callbacks.shock = function (self, new_action)
	self._ut_combo_checked = not new_action.ut_shock_beam
end

mod.handgun_update_callbacks.shock = function (self)
	if self._ut_combo_checked or self.state == "waiting_to_shoot" then
		return
	end

	self._ut_combo_checked = true

	local owner_unit = self.owner_unit
	local first_person_extension = ScriptUnit.extension(owner_unit, "first_person_system")
	local origin, rotation = first_person_extension:get_projectile_start_position_rotation()
	local direction = Quaternion.forward(rotation)

	spawn_trail(self, origin, direction)

	local ball_unit = find_ball_hit_by_beam(self.physics_world, origin, direction)

	if ball_unit then
		detonate_ball(ball_unit, owner_unit)
	end
end
