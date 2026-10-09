local mod = get_mod("unreal_tournament")

-- Flak Cannon: replaces the Blunderbuss (Kruber's) actions in place, like the Shock Rifle does with
-- the beam staff. The numbers are from UT2004 (XWeapons/FlakFire, FlakAltFire, FlakChunk, FlakShell).
--   LMB: a tight spread of flak chunks. They bounce off walls.
--   RMB: a lobbed shell that explodes when it hits something and throws flak chunks in all directions.
-- Ammo, reload, recoil and the sounds of the shot are the blunderbuss's own.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local effects = mod.effects
local register_damage_profile = utils.register_damage_profile
local register_explosion_template = utils.register_explosion_template
local register_network_lookup = utils.register_network_lookup
local make_flat = utils.make_flat
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for

local TEMPLATE_NAME = "blunderbuss_template_1"

local CONFIG = {
	meters_per_uu = 0.02, -- Unreal unit to meters
	-- The blunderbuss's own ammo (16, with 1 in the clip) and reload time (1.5 s) are changed by these factors
	ammo_multiplier = 1.33,
	reload_time_multiplier = 0.75,
	-- Flak chunk
	chunk_count = 9, -- FlakFire.ProjPerFire
	chunk_spread_degrees = 4, -- "tight", FlakFire.Spread is about 7.7 degrees
	-- FlakChunk.Speed is 2500 uu/s, which is 50 m/s with the unit conversion for sizes and 23 m/s in
	-- proportion to the run speed. Both felt wrong, this is in between. (The action's unit is m/s * 100.)
	chunk_speed = 3500,
	chunk_lifetime = 2.7, -- seconds
	chunk_radius = 0.08, -- m, how easily a chunk hits things
	chunk_gravity_settings = "spark", -- the game's gravity setting with the least gravity (-0.5)
	chunk_bounce_speed_scale = 0.65, -- the speed a chunk keeps after bouncing
	-- UT2004: 25% of the chunks bounce twice, 50% once and 25% not at all. This many bounces more
	-- than that for every chunk. A chunk also goes through enemies, every enemy it goes through
	-- uses up one of its bounces, and the other way round: a chunk has this many in all.
	-- The multipliers of a chunk per armor type (unarmored, armored, monsters, players, berserkers, super armor)
	chunk_armor_attack = {1, 1.25, 1.5, 1, 1, 0.5},
	chunk_armor_impact = {1, 1, 1, 1, 1, 0.25},
	chunk_bounces = 2, -- the most bounces a chunk has in UT2004
	chunk_extra_bounces = 2,
	chunk_damage = 11, -- in UT2004's units, 45 is the shock rifle's beam. UT has 13 with a 90 explosion, 8.7 was it scaled with the explosion's 60
	-- UT2004: after its first second a chunk loses 5 damage per second of its 13, but not below 5
	-- (FlakChunk.DamageAtten). The same share of chunk_damage here, with a slower loss: it begins later, is slower
	-- and stops higher.
	chunk_ut_damage = 13,
	chunk_damage_decay = 2, -- per second (UT: 5)
	chunk_damage_decay_delay = 1.5, -- seconds (UT: 1)
	chunk_damage_min = 8, -- (UT: 5)
	-- Knockback of a chunk: how hard it staggers what it hits, (the beam's impact power is 0.3, a
	-- shotgun pellet's is 0.3 up close and 0.15 far away). It falls off with the distance between the
	-- player and the target, from the near value up to the start, to the far value from the end.
	chunk_knockback_near = 1.2,
	chunk_knockback_far = 0.05,
	-- Multiplies how far a staggered enemy is pushed back (1 is what the game's shotguns do). Strong
	-- hits (up close) get the whole of it, weak ones (far away) get less because their stagger is weaker.
	chunk_stagger_distance_modifier = 6,
	chunk_knockback_falloff_start = 2, -- m
	chunk_knockback_falloff_end = 12, -- m
	-- The ragdoll of what a chunk killed is thrown (the game's own push of a dying body is small).
	-- Every chunk that hit adds its speed, so point blank all of them together send the body flying.
	-- Falls off with the distance between the player and the target like the knockback.
	chunk_ragdoll_speed_near = 25, -- m/s per chunk
	chunk_ragdoll_speed_far = 3, -- m/s per chunk
	chunk_ragdoll_max_speed = 180, -- m/s
	chunk_ragdoll_up = 0.35, -- upwards speed, as a share of the horizontal speed
	chunk_ragdoll_window = 1.5, -- seconds a body has to start ragdolling after it was hit
	-- Shell
	shell_speed = 2400, -- FlakShell.Speed 1200 uu/s = 24 m/s
	shell_lob_degrees = 5.3, -- how far up the shell is tossed from the aim (UT's FlakShell.TossZ 225 uu/s is 10.6, this is half)
	shell_lifetime = 6,
	shell_radius = 0.2, -- m
	shell_damage = 60, -- the damage of the explosion
	-- The multipliers of the explosion's damage and stagger per armor type: unarmored, armored, monsters, players,
	-- berserkers, super armor
	shell_armor_attack = {
		1,
		1,
		1.5,
		1,
		1,
		0.5,
	},
	shell_armor_impact = {
		1,
		1,
		1,
		1,
		1,
		0.5,
	},
	shell_explosion_radius_uu = 150, -- FlakShell: 220, it was reduced
	-- The explosion hurts the player who fired the shell: this much at the center, falling off like
	-- the explosion's damage does (the combo of the shock rifle, which is twice the damage, is 100)
	shell_self_damage = 45,
	shell_explosion_full_damage_radius = 0.5, -- damage falls off linearly from here to the radius
	shell_chunk_count = 6,
	shell_chunk_cone_degrees = 88, -- the chunks go up to this far from the direction of the shell, in yaw and pitch
	shell_chunk_start_offset = 0.2, -- m back from the explosion, so the chunks start in front of the wall
	-- The visual of the explosion: these effects are played together, each that is loaded for the
	-- weapon's character (the others are skipped). Some effects ignore the scale.
	shell_explosion_effects = {
		{
			name = "fx/wpnfx_frag_grenade_impact",
			scale = 1,
			offset = 0,
		},
		{
			name = "fx/wpnfx_fireball_charged_impact_remap",
			scale = 0.8,
			offset = 0.1,
		},
		{
			name = "fx/wpnfx_barrel_explosion",
			scale = 0.5,
			offset = 0,
		},
	},
}

-- The projectiles of the weapon are sub actions of its two actions, the names go over the network.
-- The chunks belong to the primary action, the shell to the secondary one.
local CHUNK_ACTION_NAME = "action_one"
local SHELL_ACTION_NAME = "action_two"
local CHUNK_ACTIONS = {} -- the chunk that bounces n times is CHUNK_ACTIONS[n + 1]

for bounces = 0, CONFIG.chunk_bounces + CONFIG.chunk_extra_bounces do
	CHUNK_ACTIONS[bounces + 1] = "ut_flak_chunk_" .. bounces
end
local SHELL_ACTION = "ut_flak_shell"

for _, name in ipairs(CHUNK_ACTIONS) do
	register_network_lookup("sub_actions", name)
end

register_network_lookup("sub_actions", SHELL_ACTION)

-- Damage profiles
-- A chunk stops at the first enemy it hits, the direct hit of the shell only staggers: its damage is the
-- explosion, which is at full strength for whatever the shell hits (like in UT).

register_damage_profile("ut_flak_chunk", "staff_fireball", function (profile)
	make_flat(profile, attack_power_for(CONFIG.chunk_damage), impact_power_for(CONFIG.chunk_damage))

	-- armor piercing: armored enemies take more damage than unarmored ones (critical hits too)
	utils.set_armor_modifiers(profile, CONFIG.chunk_armor_attack, CONFIG.chunk_armor_impact, true)

	-- knockback that falls off: the damage is the same at any distance, the impact is not. This is
	-- how the game does the falloff of shotguns, with the shotgun's way of staggering.
	local target = profile.default_target
	local attack_power = attack_power_for(CONFIG.chunk_damage)

	target.attack_template = "shot_shotgun"
	target.stagger_distance_modifier = CONFIG.chunk_stagger_distance_modifier
	target.power_distribution_near = {
		attack = attack_power,
		impact = CONFIG.chunk_knockback_near,
	}
	target.power_distribution_far = {
		attack = attack_power,
		impact = CONFIG.chunk_knockback_far,
	}
	target.range_modifier_settings = {
		dropoff_end = CONFIG.chunk_knockback_falloff_end,
		dropoff_start = CONFIG.chunk_knockback_falloff_start,
	}

	profile.cleave_distribution = {
		attack = 0.01,
		impact = 0.01,
	}
end)
register_damage_profile("ut_flak_shell", "staff_fireball", function (profile)
	make_flat(profile, 0, impact_power_for(CONFIG.chunk_damage))

	profile.cleave_distribution = {
		attack = 0.01,
		impact = 0.01,
	}
end)

local function modify_explosion_profile(profile)
	make_flat(profile, attack_power_for(CONFIG.shell_damage), impact_power_for(CONFIG.shell_damage))

	-- the game's own multipliers for this are 0 against super armor (chaos warriors), the explosion would do
	-- nothing to them
	profile.armor_modifier.attack = table.clone(CONFIG.shell_armor_attack)
	profile.armor_modifier.impact = table.clone(CONFIG.shell_armor_impact)
end

register_damage_profile("ut_flak_shell_explosion", "fireball_charged_explosion", modify_explosion_profile)
register_damage_profile("ut_flak_shell_explosion_glance", "fireball_charged_explosion_glance", modify_explosion_profile)

-- The effect of the explosion is played by the code below, only if the game has it loaded
register_explosion_template("ut_flak_shell_explosion", {
	explosion = {
		alert_enemies = true,
		alert_enemies_radius = 15,
		attacker_power_level_offset = 1,
		damage_profile = "ut_flak_shell_explosion",
		damage_profile_glance = "ut_flak_shell_explosion_glance",
		-- the shooter is hurt separately, see shell_self_damage
		ignore_attacker_unit = true,
		max_damage_radius = CONFIG.shell_explosion_full_damage_radius,
		radius = CONFIG.shell_explosion_radius_uu * CONFIG.meters_per_uu,
		sound_event_name = "fireball_big_hit",
		use_attacker_power_level = true,
		camera_effect = {
			far_distance = 20,
			far_scale = 0.1,
			near_distance = 5,
			near_scale = 0.5,
			shake_name = "frag_grenade_explosion",
		},
	},
})

-- Weapon template

local function build_chunk_action(max_bounces)
	local projectile_info = table.clone(Projectiles.brace_of_drake_pistols_shot)

	projectile_info.gravity_settings = CONFIG.chunk_gravity_settings
	projectile_info.radius = CONFIG.chunk_radius
	projectile_info.unit_life_time = CONFIG.chunk_lifetime

	return {
		hit_effect = "shotgun_bullet_impact",
		kind = "charged_projectile",
		ut_flak_chunk = true,
		ut_hit_enemy_callback = "ut_flak_chunk",
		ut_init_callback = "ut_flak_chunk",
		projectile_info = projectile_info,
		impact_data = {
			bounce_on_level_units = true,
			damage_profile = "ut_flak_chunk",
			max_bounces = max_bounces,
		},
	}
end

local function build_shell_action()
	-- The game's frag bomb, it spins as it flies. (The other grenade unit is the fire bomb,
	-- "grenade_fire".)
	local projectile_info = table.clone(Projectiles.grenade)

	projectile_info.gravity_settings = "fireball"
	projectile_info.life_time = CONFIG.shell_lifetime
	projectile_info.radius = CONFIG.shell_radius
	projectile_info.show_warning_icon = nil
	projectile_info.unit_life_time = CONFIG.shell_lifetime

	-- The effect where the shell lands is a bullet impact of the game's, the blunderbuss's own ones
	-- are loaded ("shotgun_bullet_impact" is the small one, "bullet_critical_impact" the big one). (The fireball's
	-- belongs to Sienna's packages, which aren't loaded for the blunderbuss, and playing an
	-- effect that isn't loaded crashes the game. The explosion effects that are loaded for
	-- Kruber are all too big, and they can't be scaled.)
	return {
		hit_effect = "bullet_critical_impact",
		kind = "charged_projectile",
		ut_aoe_callback = "ut_flak_shell",
		ut_flak_shell = true,
		projectile_info = projectile_info,
		impact_data = {
			aoe = ExplosionTemplates.ut_flak_shell_explosion,
			damage_profile = "ut_flak_shell",
		},
	}
end

-- The secondary fire is the blunderbuss's own shot (ammo, recoil, animation) with the shell
-- fired instead of pellets
local function build_shell_launcher(primary)
	local action = table.clone(primary)

	action.damage_profile = "ut_flak_shell"
	action.shot_count = 1
	action.ut_flak_chunks = nil
	action.ut_flak_shell = true

	-- the shell can be fired as soon as the primary shot can be
	for _, chain in ipairs(action.allowed_chain_actions) do
		if chain.action == "action_two" then
			chain.start_time = 0.75
		end
	end

	return action
end

-- The template is shared game state: it is patched in place, what is touched is saved to be put
-- back on disable, and when the mod is unloaded (a reload would take the patched template for the original).
local saved = {}

local PROJECTILE_UNIT_TEMPLATES = {
	"drake_pistol_shot",
	"grenade",
}

local function restore_blunderbuss()
	local original = saved.original
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not original or not template then
		return
	end

	local actions = template.actions

	actions.action_one.default = original.action_one_default
	actions.action_two.default = original.action_two_default

	for _, name in ipairs(CHUNK_ACTIONS) do
		actions[CHUNK_ACTION_NAME][name] = nil
	end

	actions[SHELL_ACTION_NAME][SHELL_ACTION] = nil

	for _, name in ipairs(PROJECTILE_UNIT_TEMPLATES) do
		template.required_projectile_unit_templates[name] = original.required_projectile_unit_templates[name]
	end

	-- (a patch from before the ammo was changed has none saved)
	for key, value in pairs(original.ammo_data or {}) do
		template.ammo_data[key] = value
	end

	saved.original = nil
end

local function apply_flak_cannon()
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not template then
		return
	end

	-- Already applied by a previous load of this mod, start over from the original
	restore_blunderbuss()

	local actions = template.actions
	local original = {
		action_one_default = actions.action_one.default,
		action_two_default = actions.action_two.default,
		required_projectile_unit_templates = {},
		ammo_data = {
			max_ammo = template.ammo_data.max_ammo,
			reload_time = template.ammo_data.reload_time,
		},
	}

	for _, name in ipairs(PROJECTILE_UNIT_TEMPLATES) do
		original.required_projectile_unit_templates[name] = template.required_projectile_unit_templates[name]
	end

	saved.original = original

	template.ammo_data.max_ammo = math.floor(original.ammo_data.max_ammo * CONFIG.ammo_multiplier + 0.5)
	template.ammo_data.reload_time = original.ammo_data.reload_time * CONFIG.reload_time_multiplier

	local primary = table.clone(original.action_one_default)

	primary.shot_count = CONFIG.chunk_count
	primary.ut_flak_chunks = true

	actions.action_one.default = primary
	actions.action_two.default = build_shell_launcher(original.action_one_default)

	for bounces = 0, #CHUNK_ACTIONS - 1 do
		actions[CHUNK_ACTION_NAME][CHUNK_ACTIONS[bounces + 1]] = build_chunk_action(bounces)
	end

	actions[SHELL_ACTION_NAME][SHELL_ACTION] = build_shell_action()

	utils.set_actions_lookup_data({
		action_one = actions.action_one,
		action_two = actions.action_two,
	}, TEMPLATE_NAME)

	-- the projectile units have to be loaded when the weapon is wielded
	for _, name in ipairs(PROJECTILE_UNIT_TEMPLATES) do
		template.required_projectile_unit_templates[name] = false
	end
end

-- Spawning a projectile
-- The data of the shot a projectile comes from (the weapon's action or the shell's extension)

local function spawn_projectile(shot, position, rotation, action_name, sub_action_name, speed, scale)
	local direction = Quaternion.forward(rotation)

	ActionUtils.spawn_player_projectile(shot.owner_unit, position, rotation, scale, ActionUtils.pitch_from_rotation(rotation), Vector3.normalize(Vector3.flat(direction)), speed, shot.item_name, shot.item_template_name, action_name, sub_action_name, shot.is_critical_strike, shot.power_level)
end

-- UT2004: a quarter of the chunks bounce twice, half of them once (plus the extra bounces)
local function random_chunk_action()
	local roll = math.random()
	local bounces = roll > 0.75 and 2 or roll > 0.25 and 1 or 0

	return CHUNK_ACTIONS[bounces + CONFIG.chunk_extra_bounces + 1]
end

-- A random direction inside a cone of the angle (radians) around the rotation
local function spread_rotation(rotation, max_angle)
	local angle = math.random() * 2 * math.pi
	local radius = math.sqrt(math.random()) * max_angle
	local yaw = Quaternion.axis_angle(Vector3.up(), radius * math.cos(angle))
	local pitch = Quaternion.axis_angle(Vector3.right(), radius * math.sin(angle))

	return Quaternion.multiply(rotation, Quaternion.multiply(yaw, pitch))
end

-- UT2004's FlakShell: yaw and pitch are each randomly off by up to the cone
local function burst_rotation(rotation, cone)
	local yaw = Quaternion.axis_angle(Vector3.up(), (math.random() * 2 - 1) * cone)
	local pitch = Quaternion.axis_angle(Vector3.right(), (math.random() * 2 - 1) * cone)

	return Quaternion.multiply(rotation, Quaternion.multiply(yaw, pitch))
end

-- The shots
-- ActionShotgun fires pellets as hitscan, these actions fire projectiles instead and keep the rest of
-- the shot (ammo, reload, recoil, sound).
mod:hook(ActionShotgun, "_shoot", function (func, self, num_shots_total, num_shots_this_frame)
	local action = self.current_action

	if not action.ut_flak_chunks and not action.ut_flak_shell then
		return func(self, num_shots_total, num_shots_this_frame)
	end

	local lookup_data = action.lookup_data
	local shot = {
		is_critical_strike = self._is_critical_strike,
		item_name = self.item_name,
		item_template_name = lookup_data.item_template_name,
		owner_unit = self.owner_unit,
		power_level = self.power_level,
	}
	local position = self._fire_position:unbox()
	local rotation = self._fire_rotation:unbox()

	for _ = 1, num_shots_this_frame do
		self._shots_fired = self._shots_fired + 1

		if action.ut_flak_chunks then
			spawn_projectile(shot, position, spread_rotation(rotation, math.degrees_to_radians(CONFIG.chunk_spread_degrees)), CHUNK_ACTION_NAME, random_chunk_action(), CONFIG.chunk_speed)
		else
			local lobbed_rotation = Quaternion.multiply(rotation, Quaternion.axis_angle(Vector3.right(), math.degrees_to_radians(CONFIG.shell_lob_degrees)))

			spawn_projectile(shot, position, lobbed_rotation, SHELL_ACTION_NAME, SHELL_ACTION, CONFIG.shell_speed)
		end
	end
end)

-- The faster reload in the third person: the game speeds up the first person reload only (a variable of the first person
-- animation) and tells the others to play the reload at its normal speed. The reload event is sent again with the speed
-- the game's own third person weapon animations take, "attack_speed".
mod:hook(GenericAmmoUserExtension, "start_reload_animation", function (func, self, reload_time)
	local original = saved.original

	if not original or utils.wielded_template_name(self.owner_unit) ~= TEMPLATE_NAME then
		return func(self, reload_time)
	end

	-- (the event the game is about to play, picked the same way as it picks it)
	local reload_event = self._reload_event

	if self.reloaded_from_zero_ammo then
		reload_event = self._no_ammo_reload_event or reload_event
	elseif self._ammo_per_clip - self._current_ammo == 1 or self._available_ammo == 1 then
		reload_event = self._last_reload_event
	end

	reload_event = self._override_reload_anim or reload_event

	func(self, reload_time)

	if reload_event then
		Managers.state.network:anim_event_with_variable_float(self.owner_unit, reload_event, "attack_speed", original.ammo_data.reload_time / reload_time)
	end
end)

-- The explosion of the shell: the chunks. This runs where the shell's impact is handled, which is
-- on the machine of the player who fired it.
mod.aoe_callbacks.ut_flak_shell = function (self, aoe_data, position)
	if self._ut_flak_exploded then
		return
	end

	self._ut_flak_exploded = true

	local velocity = self.locomotion_extension:current_velocity()
	local direction = Vector3.length(velocity) > 0.001 and Vector3.normalize(velocity) or Vector3.up()
	local rotation = Quaternion.look(direction)
	local start = position - direction * CONFIG.shell_chunk_start_offset
	local lookup_data = self.action_lookup_data
	local shot = {
		is_critical_strike = self._is_critical_strike,
		item_name = self.item_name,
		item_template_name = lookup_data.item_template_name,
		owner_unit = self._owner_unit,
		power_level = self.power_level,
	}

	utils.apply_explosion_self_damage(self._owner_unit, position, self.item_name, ExplosionTemplates.ut_flak_shell_explosion.explosion, CONFIG.shell_self_damage)

	for _ = 1, CONFIG.shell_chunk_count do
		spawn_projectile(shot, start, burst_rotation(rotation, math.degrees_to_radians(CONFIG.shell_chunk_cone_degrees)), CHUNK_ACTION_NAME, random_chunk_action(), CONFIG.chunk_speed)
	end
end

-- The look of the explosion, on every peer: the explosion's callback is run for everyone who sees it
mod.explosion_callbacks.ut_flak_shell_explosion = function (world, position)
	for _, effect in ipairs(CONFIG.shell_explosion_effects) do
		effects.play(world, effect.name, position + Vector3(0, 0, effect.offset), effect.scale)
	end
end

-- A chunk keeps part of its speed when it bounces, and a bounce uses up one of the enemies it can go
-- through
mod:hook_safe(ProjectileScriptUnitLocomotionExtension, "bounce", function (self)
	local extension = ScriptUnit.has_extension(self.unit, "projectile_system")
	local action = extension and extension._current_action

	if action and action.ut_flak_chunk then
		self.speed = self.speed * CONFIG.chunk_bounce_speed_scale
		extension._num_additional_penetrations = math.max(extension._num_additional_penetrations - 1, 0)
	end
end)

-- What stops a chunk: the targets the game itself stops projectiles on, armor (armored and monster
-- armor, like the game does it) and an enemy that blocks with a shield
local function stops_chunk(self, hit_unit, hit_direction)
	local breed = AiUtils.unit_breed(hit_unit)

	if not breed then
		return false
	end

	if breed.armor_category == 2 or breed.armor_category == 3 then
		return true
	end

	return not not AiUtils.attack_is_shield_blocked(hit_unit, self._owner_unit, nil, hit_direction)
end

-- Ragdolls thrown by chunks: the hits are collected per target, and once the target has died and
-- its ragdoll has started (before that the actors are driven by animation) the body is thrown once,
-- with the speed of all the chunks that hit it. Runs on every peer, the physics of ragdolls is local.
local ragdoll_throws = {}

local function ragdoll_speed_at(distance)
	local fraction = math.clamp((distance - CONFIG.chunk_knockback_falloff_start) / (CONFIG.chunk_knockback_falloff_end - CONFIG.chunk_knockback_falloff_start), 0, 1)

	return math.lerp(CONFIG.chunk_ragdoll_speed_near, CONFIG.chunk_ragdoll_speed_far, fraction)
end

local function add_ragdoll_throw(hit_unit, owner_unit, hit_position, hit_direction)
	local owner_position = POSITION_LOOKUP[owner_unit]

	if not owner_position then
		return
	end

	local throw = ragdoll_throws[hit_unit]

	if not throw then
		throw = {
			t = Managers.time:time("game"),
			velocity = Vector3Box(0, 0, 0),
		}
		ragdoll_throws[hit_unit] = throw
	end

	local flat_direction = Vector3.normalize(Vector3.flat(hit_direction))

	throw.velocity:store(throw.velocity:unbox() + flat_direction * ragdoll_speed_at(Vector3.length(hit_position - owner_position)))
end

-- Returns true once the body has been thrown
local function throw_ragdoll(unit, velocity)
	local thrown = false

	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		if actor and Actor.is_dynamic(actor) then
			Actor.set_velocity(actor, velocity)

			thrown = true
		end
	end

	return thrown
end

local function update_ragdoll_throws()
	local t = Managers.time:time("game")

	for unit, throw in pairs(ragdoll_throws) do
		if not Unit.alive(unit) or t - throw.t > CONFIG.chunk_ragdoll_window then
			ragdoll_throws[unit] = nil
		elseif not HEALTH_ALIVE[unit] then
			local velocity = throw.velocity:unbox()
			local speed = Vector3.length(velocity)

			if speed > 0 then
				velocity = velocity * (math.min(speed, CONFIG.chunk_ragdoll_max_speed) / speed)
				velocity = velocity + Vector3(0, 0, Vector3.length(velocity) * CONFIG.chunk_ragdoll_up)
			end

			if throw_ragdoll(unit, velocity) then
				ragdoll_throws[unit] = nil
			end
		end
	end
end

-- Bounces and enemies gone through share one number per chunk: the game's projectile counts the
-- bounces (impact_data.max_bounces) and the enemies it goes through (_num_additional_penetrations)
-- separately. The chunk goes through as many enemies as it bounces, and going through an enemy is
-- counted as a bounce. Players who didn't fire the chunk have the same code for it.
mod.init_callbacks.ut_flak_chunk = function (self)
	self._num_additional_penetrations = self._current_action.impact_data.max_bounces
	self._ut_flak_spawn_t = Managers.time:time("game")
end

mod.hit_enemy_callbacks.ut_flak_chunk = function (func, self, is_owner, impact_data, hit_unit, hit_position, hit_direction, ...)
	-- armor stops a chunk (after it did its damage): the game stops a projectile that has
	-- nothing left to go through
	if stops_chunk(self, hit_unit, hit_direction) then
		self._num_additional_penetrations = 0
	end

	local penetrations_before = self._num_additional_penetrations

	-- the damage (and the knockback) of a chunk decays with its age. The power level is what
	-- the game reads for a hit, so it is scaled for the duration of it.
	local power_level = self.power_level
	local spawn_t = self._ut_flak_spawn_t

	if power_level and spawn_t then
		local age = Managers.time:time("game") - spawn_t
		local damage = math.max(CONFIG.chunk_damage_min, CONFIG.chunk_ut_damage - CONFIG.chunk_damage_decay * math.max(0, age - CONFIG.chunk_damage_decay_delay))

		self.power_level = power_level * damage / CONFIG.chunk_ut_damage
	end

	func(self, impact_data, hit_unit, hit_position, hit_direction, ...)

	self.power_level = power_level

	if not AiUtils.attack_is_shield_blocked(hit_unit, self._owner_unit, nil, hit_direction) then
		add_ragdoll_throw(hit_unit, self._owner_unit, hit_position, hit_direction)
	end

	if self._num_additional_penetrations < penetrations_before then
		self._num_bounces = self._num_bounces + penetrations_before - self._num_additional_penetrations
	end
end

-- The mod holds its own references to the units of the projectiles while the weapon is enabled
local packages = utils.package_holder("unreal_tournament_flak")

local function enable_flak_cannon()
	packages.load_projectile_units(PROJECTILE_UNIT_TEMPLATES)
	apply_flak_cannon()
end

-- (the weapon can be switched off in the settings: the blunderbuss is then the game's own again, the weapon the player
-- holds changes when it is wielded again)
local function disable_flak_cannon()
	restore_blunderbuss()
	packages.unload()
end

utils.register_weapon("flak_cannon", enable_flak_cannon, disable_flak_cannon)

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	update_ragdoll_throws()
end

mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
	table.clear(ragdoll_throws)
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(ragdoll_throws)
end
