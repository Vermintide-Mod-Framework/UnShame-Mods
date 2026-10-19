local mod = get_mod("unreal_tournament")

-- Assault Rifle: a copy of the Brace of Pistols with its attacks replaced, held two at a time as UT's is once a second one is picked up
-- (bDualMode). The numbers come from UT2004 (XWeapons/AssaultRifle, AssaultFire, AssaultGrenade, Grenade and their ammo).
--   Left button: rounds that hit at once, 7 damage each, at the fire rate of two rifles (FireRate 0.16 times 0.55). The spread starts at
--       0.02 and grows by 0.02 a round, up to 0.12, and goes back once the button is let go for half a second.
--   Right button: held, it charges the grenade launcher; let go, it lobs a grenade that bounces off walls, and goes off two seconds
--       after it first touches something, or at once on an enemy. The longer it is held (up to a second), the further it goes.
-- The grenades are not the game's projectiles, because those don't bounce as UT's grenade does. A game projectile bounces at the speed
-- it was fired at, a set number of times, and its fuse starts when it is fired. UT's grenade loses speed at each bounce, comes to rest,
-- and goes off 2 seconds after it first touches something. So the shooter's machine sends the throw, each machine flies the grenade
-- itself, and the shooter's machine makes the explosion.
-- skin.lua draws the rifles, the flashes and the grenades. This file is the gameplay.

local utils = mod.utils
local register_damage_profile = utils.register_damage_profile
local register_explosion_template = utils.register_explosion_template
local make_flat = utils.make_flat
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for

local DESCRIPTION = "Inexpensive and easily produced, the AR770 provides a lightweight 5.56mm combat solution that is most effective against unarmored foes. The optional M355 Grenade Launcher provides the punch that makes this weapon effective against heavily armored enemies."

local SETTING_ID = "assault_rifle"
local ITEM_KEY = "ut_assault_rifle"
local TEMPLATE_NAME = "ut_assault_rifle_template"

mod.items.register(SETTING_ID, {
	key = ITEM_KEY,
	template = TEMPLATE_NAME,
	base_item = "wh_brace_of_pistols",
	deus_copy = "deus_wh_brace_of_pistols",
	name = "UT2004 Assault Rifle",
	type_name = "Assault Rifle",
	description = DESCRIPTION,
	keywords = { "weapon_keyword_rapid_fire", "weapon_keyword_crowd_control", "weapon_keyword_versatile" },
	icon = "ut_assault_rifle_icon",
	icon_package = "resource_packages/unreal_tournament/icons",
	icon_materials = "ui/ut/assault_rifle_icon",
})

local CONFIG = {
	-- AssaultAmmo.MaxAmmo. All the ammo is the clip, so there is no reload.
	max_ammo = 200,
	-- AssaultFire: DamageMin and DamageMax 7, FireRate 0.16, which bDualMode makes 0.55 of it
	damage = 7,
	fire_rate = 0.16 * 0.55,
	-- AssaultFire.ModeDoFire: the spread
	spread = 0.02,
	spread_step = 0.02,
	spread_max = 0.12,
	spread_reset = 0.5, -- seconds without a round
	-- GrenadeAmmo.MaxAmmo. The grenades are counted here, and a pickup of ammo fills them.
	max_grenades = 8,
	-- AssaultGrenade: the speed is mHoldSpeedMin plus mHoldSpeedGainPerSec for each second held, up to mHoldSpeedMax, plus the player's
	-- speed forward. FireRate is mWaitTime + 1 / (mDrumRotationsPerSec * 8). ProjSpawnOffset: where it starts (forward, right, down).
	grenade_speed_min = 850,
	grenade_speed_max = 1600,
	grenade_speed_gain = 750, -- a second held
	grenade_fire_rate = 0.5 + 1 / (0.4 * 8),
	grenade_offset = { 25, 10, -7 },
	-- Grenade: it falls (PHYS_Falling, the zone's 950 units a second squared), bounces with DampenFactor 0.5 of its speed into the wall and
	-- DampenFactorParallel 0.8 along it, stops below 20 units a second, and goes off ExplodeTimer after it first touches something.
	grenade_gravity = 950,
	dampen = 0.5,
	dampen_parallel = 0.8,
	stop_speed = 20,
	explode_timer = 2,
	max_life = 10, -- seconds, in case it never touches anything
	grenade_radius = 3, -- UT units (the mesh at DrawScale 3)
	-- Grenade.Damage 70 and Projectile.DamageRadius 220. The Rocket Launcher's are reduced from UT's (90 to 60, and 220 units to 150), and
	-- these are reduced in the same way.
	grenade_damage = 70 * 60 / 90,
	grenade_radius_uu = 150,
	grenade_full_damage_radius = 0.5,
	-- The explosion hurts the player who threw it, reduced as the Rocket Launcher's self damage is (45 for its 60), and throws them
	-- (MomentumTransfer 75000, as the Flak Cannon's shell)
	grenade_self_damage = 70 * 60 / 90 * 45 / 60,
	grenade_jump_speed = 8.5,
	-- The multipliers of the damage and the stagger for each armor type: unarmored, armored, monsters, players, berserkers and super armor.
	-- The rounds are poor against armor, as UT's description says, and the grenades are not.
	bullet_armor_attack = { 1, 0.5, 1, 1, 1, 0.3 },
	bullet_armor_impact = { 1, 1, 1, 1, 1, 0.5 },
	grenade_armor_attack = { 1, 1, 1.5, 1, 1, 0.5 },
	grenade_armor_impact = { 1, 1, 1, 1, 1, 0.5 },
	bot_max_range = 25,
	chain_margin = 0.05,
	recoil_climb = 0.08,
	-- The characters fire both modes in the pistols' alt attack's stance, as actions that chain into each other, as the pistols' do
	-- (their aim, lock_target, and their fast shot, attack_shoot_fast): the first round or the grenade's charge takes the stance, the
	-- rounds after it keep it, and the throw plays the shot. Once the rounds stop, or the grenade's shot has played (throw_time), an
	-- action that holds the stance follows, and leaves it (attack_finished) this long after, unless the rifle fires again (set in the
	-- game).
	stance_linger = 0.5, -- s
	-- (after a grenade, from its throw: the time until the next grenade can be thrown, and half a second more)
	stance_linger_alt = 0.5 + 1 / (0.4 * 8) + 0.5, -- s
	throw_time = 0.4, -- s
}

local UNIT = utils.UT_UNIT

-- Damage

register_damage_profile("ut_assault_bullet", "shot_repeating", function (profile)
	make_flat(profile, attack_power_for(CONFIG.damage), impact_power_for(CONFIG.damage), "shot_shotgun")

	profile.cleave_distribution = {
		attack = 0.01,
		impact = 0.01,
	}
	utils.set_armor_modifiers(profile, CONFIG.bullet_armor_attack, CONFIG.bullet_armor_impact)
end)

local function grenade_profile(profile)
	make_flat(profile, attack_power_for(CONFIG.grenade_damage), impact_power_for(CONFIG.grenade_damage))
	utils.set_armor_modifiers(profile, CONFIG.grenade_armor_attack, CONFIG.grenade_armor_impact)
end

register_damage_profile("ut_assault_grenade", "fireball_charged_explosion", grenade_profile)
register_damage_profile("ut_assault_grenade_glance", "fireball_charged_explosion_glance", grenade_profile)

local EXPLOSION = "ut_assault_grenade_explosion"

register_explosion_template(EXPLOSION, {
	explosion = {
		alert_enemies = true,
		alert_enemies_radius = 15,
		attacker_power_level_offset = 1,
		damage_profile = "ut_assault_grenade",
		damage_profile_glance = "ut_assault_grenade_glance",
		-- The thrower is hurt separately (see grenade_self_damage)
		ignore_attacker_unit = true,
		max_damage_radius = CONFIG.grenade_full_damage_radius,
		radius = CONFIG.grenade_radius_uu * UNIT,
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

mod.explosion_push_speeds[EXPLOSION] = function ()
	return CONFIG.grenade_jump_speed
end

-- The rifle's state: the grenades in flight, and the player's grenade count and timing. The skin reads the explosion's name from it, and
-- the tests the grenade count.
mod.assault = {
	explosion = EXPLOSION,
	grenades = {}, -- the grenades in flight, on every machine: { id, owner_unit, position, velocity, ... }
	grenade_count = CONFIG.max_grenades, -- the player's own
	max_grenades = CONFIG.max_grenades,
	charge_started = nil, -- when the player started holding the grenade button, for the charge bar
	last_grenade = nil, -- when the player's last grenade was thrown
}

local assault = mod.assault

-- Each shooter's current spread and the time of their last round. The spread grows with each round and resets after a pause.
local spreads = {}

mod.handgun_start_callbacks.assault = function (self, new_action)
	self._ut_assault_checked = not new_action.ut_assault

	if not new_action.ut_assault then
		return
	end

	local owner_unit = self.owner_unit
	local t = Managers.time:time("game")
	local state = spreads[owner_unit] or { spread = CONFIG.spread, last = -math.huge }

	if t - state.last > CONFIG.spread_reset then
		state.spread = CONFIG.spread
	else
		state.spread = math.min(state.spread + CONFIG.spread_step, CONFIG.spread_max)
	end

	state.last = t
	spreads[owner_unit] = state

	utils.set_handgun_spread(self, state.spread)
end

-- Once a round is fired, finds where it hit and tells the skin, which draws the flash and the tracer
mod.handgun_update_callbacks.assault = function (self)
	if self._ut_assault_checked or self.state == "waiting_to_shoot" or not (self.current_action and self.current_action.ut_assault) then
		return
	end

	self._ut_assault_checked = true

	local end_position, hit_normal = utils.handgun_round_hit(self)

	mod.assault_round(self.owner_unit, end_position, hit_normal)
end

-- Functions called with (owner_unit, end_position, hit_normal) for every round, on every machine. The skin adds one to draw the round.
mod.assault_round_callbacks = {}

function mod.assault_round(owner_unit, end_position, hit_normal)
	for _, callback in pairs(mod.assault_round_callbacks) do
		callback(owner_unit, end_position, hit_normal)
	end

	mod:network_send("ut_assault_round", "others", Managers.state.unit_storage:go_id(owner_unit), Vector3.x(end_position), Vector3.y(end_position), Vector3.z(end_position), Vector3.x(hit_normal), Vector3.y(hit_normal), Vector3.z(hit_normal))
end

mod:network_register("ut_assault_round", function (_, owner_go_id, x, y, z, normal_x, normal_y, normal_z)
	local unit = Managers.state.unit_storage:unit(owner_go_id)

	if unit and Unit.alive(unit) then
		for _, callback in pairs(mod.assault_round_callbacks) do
			callback(unit, Vector3(x, y, z), Vector3(normal_x, normal_y, normal_z))
		end
	end
end)

-- Grenades

-- Adds a grenade in flight, on every machine. The shooter's machine makes its explosion; the others drop it when the explosion comes.
local function add_grenade(id, owner_unit, position, velocity, local_owner)
	local grenade = {
		id = id,
		local_owner = local_owner,
		owner_unit = owner_unit,
		position = Vector3Box(position),
		velocity = Vector3Box(velocity),
		age = 0,
		timer = nil, -- seconds left once it has touched something
		stopped = false,
		left = nil, -- which rifle threw it, for the skin
	}

	assault.grenades[#assault.grenades + 1] = grenade

	for _, callback in pairs(mod.assault_grenade_callbacks) do
		callback(grenade)
	end

	return grenade
end

-- What the skin is told when a grenade is thrown, bounces, and goes off
--   mod.assault_grenade_callbacks[name] = function (grenade)
--   mod.assault_bounce_callbacks[name] = function (grenade, position, speed)
mod.assault_grenade_callbacks = {}
mod.assault_bounce_callbacks = {}

local function explode(grenade, position)
	grenade.exploded = true

	if not grenade.local_owner or not Unit.alive(grenade.owner_unit) then
		return
	end

	local area_damage_system = Managers.state.entity:system("area_damage_system")

	-- (the grenades fly in the mod's update, which runs before the game's, so the units' positions are made current for the explosion)
	utils.with_valid_positions(area_damage_system.create_explosion, area_damage_system, grenade.owner_unit, position, Quaternion.identity(), EXPLOSION, 1, ITEM_KEY, grenade.power_level or 500, false, grenade.owner_unit)
	utils.apply_explosion_self_damage(grenade.owner_unit, position, ITEM_KEY, ExplosionTemplates[EXPLOSION].explosion, CONFIG.grenade_self_damage)
	mod:network_send("ut_assault_grenade_end", "others", grenade.id)
end

mod:network_register("ut_assault_grenade_end", function (_, id)
	for _, grenade in ipairs(assault.grenades) do
		if grenade.id == id then
			grenade.exploded = true
		end
	end
end)

local function raycast(physics_world, from, to, filter)
	local along = to - from
	local length = Vector3.length(along)

	if length < 0.0001 then
		return nil
	end

	return PhysicsWorld.immediate_raycast(physics_world, from, along / length, length, "closest", "collision_filter", filter)
end

-- Moves a grenade by a frame (Grenade.HitWall and ProcessTouch)
local function fly(grenade, dt, physics_world)
	grenade.age = grenade.age + dt

	if grenade.timer then
		grenade.timer = grenade.timer - dt

		if grenade.timer <= 0 then
			return explode(grenade, grenade.position:unbox())
		end
	elseif grenade.age > CONFIG.max_life then
		return explode(grenade, grenade.position:unbox())
	end

	if grenade.stopped then
		return
	end

	local position = grenade.position:unbox()
	local velocity = grenade.velocity:unbox() - Vector3(0, 0, CONFIG.grenade_gravity * UNIT * dt)
	local target = position + velocity * dt

	-- An enemy in the way sets it off at once. Only the shooter's machine checks, because it makes the explosion.
	if grenade.local_owner then
		local enemy_hit, enemy_position = raycast(physics_world, position, target, "filter_player_ray_projectile_ai_only")

		if enemy_hit then
			return explode(grenade, enemy_position)
		end
	end

	local hit, hit_position, _, normal = raycast(physics_world, position, target, "filter_player_ray_projectile_static_only")

	if hit and normal then
		grenade.timer = grenade.timer or CONFIG.explode_timer

		local into = normal * Vector3.dot(velocity, normal)

		velocity = -into * CONFIG.dampen + (velocity - into) * CONFIG.dampen_parallel
		target = hit_position + normal * (CONFIG.grenade_radius * UNIT)

		local speed = Vector3.length(velocity) / UNIT

		for _, callback in pairs(mod.assault_bounce_callbacks) do
			callback(grenade, target, speed)
		end

		if speed < CONFIG.stop_speed then
			grenade.stopped = true
			velocity = Vector3.zero()
		end
	end

	grenade.position:store(target)
	grenade.velocity:store(velocity)
end

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	local grenades = assault.grenades

	if #grenades == 0 or not Managers.world:has_world("level_world") then
		return
	end

	local physics_world = World.get_data(Managers.world:world("level_world"), "physics_world")

	for index = #grenades, 1, -1 do
		local grenade = grenades[index]

		if not grenade.exploded then
			fly(grenade, dt, physics_world)
		end

		if grenade.exploded then
			table.remove(grenades, index)
		end
	end
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(assault.grenades)

	assault.grenade_count = CONFIG.max_grenades
	-- (the game's time starts again in each level, so a throw of the last level would look like one that just happened)
	assault.last_grenade = nil
	assault.charge_started = nil
end

-- Which rifle throws the next grenade: they take turns (AssaultGrenade.DoFireEffect, bFireLeft)
local fire_left = {}

-- Throws a grenade (AssaultGrenade.DoFireEffect and SpawnProjectile)
local function throw(action, hold_time)
	local owner_unit = action.owner_unit
	local first_person_extension = ScriptUnit.extension(owner_unit, "first_person_system")
	local eye, rotation = first_person_extension:get_projectile_start_position_rotation()
	local forward, right, up = Quaternion.forward(rotation), Quaternion.right(rotation), Quaternion.up(rotation)
	local offset = CONFIG.grenade_offset

	fire_left[owner_unit] = not fire_left[owner_unit]

	local side = fire_left[owner_unit] and -1 or 1
	local start = eye + forward * (offset[1] * UNIT) + right * (side * offset[2] * UNIT) + up * (offset[3] * UNIT)

	-- If a wall is between the eye and the start, the grenade starts at the wall
	local physics_world = World.get_data(Managers.world:world("level_world"), "physics_world")
	local hit, hit_position = raycast(physics_world, eye, start, "filter_player_ray_projectile_static_only")

	if hit then
		start = hit_position
	end

	local locomotion_extension = ScriptUnit.has_extension(owner_unit, "locomotion_system")
	local own_speed = locomotion_extension and Vector3.dot(forward, locomotion_extension:current_velocity()) / UNIT or 0
	local speed = math.clamp(CONFIG.grenade_speed_min + hold_time * CONFIG.grenade_speed_gain, CONFIG.grenade_speed_min, CONFIG.grenade_speed_max) + own_speed
	local velocity = forward * (speed * UNIT)

	local id = Application.guid()
	local grenade = add_grenade(id, owner_unit, start, velocity, true)

	grenade.left = fire_left[owner_unit]
	grenade.power_level = action.power_level

	mod:network_send("ut_assault_grenade", "others", id, Managers.state.unit_storage:go_id(owner_unit), Vector3.x(start), Vector3.y(start), Vector3.z(start), Vector3.x(velocity), Vector3.y(velocity), Vector3.z(velocity), grenade.left and 1 or 0)
end

mod:network_register("ut_assault_grenade", function (_, id, owner_go_id, x, y, z, vx, vy, vz, left)
	local unit = Managers.state.unit_storage:unit(owner_go_id)

	if unit and Unit.alive(unit) then
		local grenade = add_grenade(id, unit, Vector3(x, y, z), Vector3(vx, vy, vz), false)

		grenade.left = left == 1
	end
end)

-- The charge starts with the grenade button, and the grenade goes when it is let go
local charge_started = {}

-- The throw is the action that letting go of the charge chains into: it throws the grenade as it starts, as hard as the charge was held
mod.dummy_start_callbacks.assault = function (action, new_action, t)
	local owner_unit = action.owner_unit

	if new_action.ut_assault_charge then
		charge_started[owner_unit] = t

		if utils.is_local_player_unit(owner_unit) then
			assault.charge_started = t
		end
	elseif new_action.ut_assault_throw then
		local started = charge_started[owner_unit]

		charge_started[owner_unit] = nil

		if utils.is_local_player_unit(owner_unit) then
			assault.charge_started = nil

			if not started or assault.grenade_count <= 0 then
				return
			end

			assault.grenade_count = assault.grenade_count - 1
			assault.last_grenade = t
		end

		if started then
			throw(action, t - started)
		end
	end
end

mod.dummy_finish_callbacks.assault = function (action, reason)
	local current = action.current_action

	-- A weapon switch or another interruption drops the grenade, as UT's does when the weapon is put away. Letting go chains into the
	-- throw, which takes the charge's start.
	if not current or not current.ut_assault_charge or reason == "new_interupting_action" then
		return
	end

	charge_started[action.owner_unit] = nil

	if utils.is_local_player_unit(action.owner_unit) then
		assault.charge_started = nil
	end
end

-- A pickup of ammo fills the grenades, whether the rifle is held or not
mod:hook_safe(GenericAmmoUserExtension, "add_ammo", function (self)
	if self.item_name == ITEM_KEY and self.owner_unit and utils.is_local_player_unit(self.owner_unit) then
		assault.grenade_count = CONFIG.max_grenades
	end
end)

-- With all the rounds, the game refuses a pickup of ammo (the pickup's client.can_interact, on the player's own machine; the host
-- doesn't check it). While grenades are missing, the ammo is not full, so the pickup gives them back.
mod:hook(SimpleInventoryExtension, "has_full_ammo", function (func, self, ...)
	local full = func(self, ...)

	if not full or assault.grenade_count >= CONFIG.max_grenades or not utils.is_local_player_unit(self._unit) then
		return full
	end

	local slot_data = self:get_slot_data("slot_ranged")

	return not (slot_data and slot_data.item_data and slot_data.item_data.name == ITEM_KEY)
end)

-- Weapon template

local function chain(action, sub_action, input, start_time)
	return {
		action = action,
		input = input,
		start_time = start_time or 0,
		sub_action = sub_action,
	}
end

-- The sub-actions of the stance (see stance_linger): a round after a round or in the stance, the stance after the rounds, a charge in the
-- stance, the throw, and the stance after it
local ROUND_IN_STANCE = "ut_assault_round"
local STANCE = "ut_assault_stance"
local CHARGE_IN_STANCE = "ut_assault_charge"
local THROW = "ut_assault_throw"
local STANCE_AFTER_THROW = "ut_assault_stance_after_throw"

for _, name in ipairs({ ROUND_IN_STANCE, STANCE, CHARGE_IN_STANCE, THROW, STANCE_AFTER_THROW }) do
	utils.register_network_lookup("sub_actions", name)
end

-- (a stance ends with the pistols' end of their aim, unless the rifle fires again from it)
local function leaves_stance(unit, end_reason)
	return end_reason ~= "new_interupting_action"
end

-- What the stance's actions can chain into at once: rounds, a charge, and the wield
local function stance_chains()
	return {
		chain("action_wield", "default", "action_wield", 0),
		chain("action_one", ROUND_IN_STANCE, "action_one", 0),
		chain("action_one", ROUND_IN_STANCE, "action_one_hold", 0),
		chain("action_two", CHARGE_IN_STANCE, "action_two_hold", 0),
	}
end

-- An action that holds the stance for linger seconds and then leaves it, taking it first with take
local function build_stance(linger, take)
	return {
		kind = "dummy",
		anim_event_3p = take and "lock_target" or nil,
		anim_end_event_3p = "attack_finished",
		anim_end_event_condition_func = leaves_stance,
		total_time = linger,
		allowed_chain_actions = stance_chains(),
	}
end

-- A round. Holding the button repeats it at the fire rate. It hits at once, as UT's does: the game's handgun shot traces a ray when its
-- action has no projectile (ActionHandgun), and the pistols' shot fired one, which drew the pistol's tracer and hurt with the pistol's
-- damage. The first round takes the stance, and the rounds after it keep it; once they stop, the stance follows.
local function build_round(source, first)
	local action = table.clone(source)

	action.kind = "handgun"
	-- (its own animation is the first person's only)
	action.anim_event_1p = action.anim_event
	action.anim_event = nil
	action.anim_event_last_ammo = nil
	action.anim_event_3p = first and "lock_target" or nil
	action.projectile_info = nil
	action.impact_data = nil
	action.speed = nil
	action.range = nil
	action.active_reload_time = nil
	action.anim_event_secondary = nil
	action.damage_profile = "ut_assault_bullet"
	action.fire_time = 0
	action.headshot_multiplier = 1
	action.reload_when_out_of_ammo = false
	action.total_time = CONFIG.fire_rate + CONFIG.chain_margin
	action.total_time_secondary = nil
	action.ut_assault = true
	action.ut_dropped_flow_events = {
		lua_bullet_trail = true,
		lua_bullet_trail_set = true,
	}
	action.allowed_chain_actions = {
		chain("action_wield", "default", "action_wield", 0.1),
		chain("action_one", ROUND_IN_STANCE, "action_one_hold", CONFIG.fire_rate),
		chain("action_two", CHARGE_IN_STANCE, "action_two_hold", CONFIG.fire_rate),
		-- (once the round's time is over with neither button held)
		{
			action = "action_one",
			auto_chain = true,
			start_time = CONFIG.fire_rate + CONFIG.chain_margin / 2,
			sub_action = STANCE,
		},
	}

	if action.recoil_settings then
		action.recoil_settings = table.clone(action.recoil_settings)
		action.recoil_settings.climb_duration = 0.05
		action.recoil_settings.restore_duration = 0.15
		action.recoil_settings.vertical_climb = CONFIG.recoil_climb
	end

	return action
end

-- The grenade's charge. It lasts while the button is held, and letting go chains into the throw. The next shot of either kind can come
-- once the grenade's fire rate has passed. The charge from nothing takes the stance, and one in the stance keeps it.
local function build_charge(source, first)
	local action = table.clone(source)

	action.kind = "dummy"
	action.anim_event = nil
	action.anim_end_event = nil
	action.anim_end_event_condition_func = nil
	action.anim_event_3p = first and "lock_target" or nil
	action.ammo_requirement = nil
	action.allow_hold_toggle = nil
	action.buff_data = nil
	action.minimum_hold_time = nil
	action.spread_template_override = nil
	action.hold_input = "action_two_hold"
	action.total_time = math.huge
	action.ut_assault_charge = true
	action.allowed_chain_actions = {
		chain("action_wield", "default", "action_wield"),
		{
			action = "action_two",
			auto_chain = true,
			release_required = "action_two_hold",
			start_time = 0,
			sub_action = THROW,
		},
	}
	-- The charge can start only with a grenade left, and once the grenade's fire rate has passed since the last one
	action.condition_func = function (unit)
		if not utils.is_local_player_unit(unit) then
			return true
		end

		local since = assault.last_grenade and Managers.time:time("game") - assault.last_grenade or math.huge

		return assault.grenade_count > 0 and since >= CONFIG.grenade_fire_rate
	end
	action.chain_condition_func = action.condition_func

	return action
end

-- The throw: the grenade goes as it starts (dummy_start_callbacks), and the characters play the pistols' fast shot. Rounds can follow
-- at once, and once the shot has played the stance follows, taken again.
local function build_throw()
	local entries = {
		chain("action_wield", "default", "action_wield", 0),
		chain("action_one", ROUND_IN_STANCE, "action_one", 0),
		chain("action_one", ROUND_IN_STANCE, "action_one_hold", 0),
		{
			action = "action_two",
			auto_chain = true,
			start_time = CONFIG.throw_time,
			sub_action = STANCE_AFTER_THROW,
		},
	}

	return {
		kind = "dummy",
		anim_event_3p = "attack_shoot_fast",
		total_time = CONFIG.throw_time + CONFIG.chain_margin,
		allowed_chain_actions = entries,
		ut_assault_throw = true,
	}
end

local function apply_template(template)
	local actions = template.actions

	template.weapon_diagram = {
		light_attack = {
			[DamageTypes.ARMOR_PIERCING] = 1,
			[DamageTypes.CLEAVE] = 1,
			[DamageTypes.SPEED] = 7,
			[DamageTypes.STAGGER] = 2,
			[DamageTypes.DAMAGE] = 3,
		},
		heavy_attack = {
			[DamageTypes.ARMOR_PIERCING] = 5,
			[DamageTypes.CLEAVE] = 6,
			[DamageTypes.SPEED] = 2,
			[DamageTypes.STAGGER] = 5,
			[DamageTypes.DAMAGE] = 5,
		},
	}

	local round_source = actions.action_one.default
	local charge_source = actions.action_two.default

	actions.action_one = {
		default = build_round(round_source, true),
		[ROUND_IN_STANCE] = build_round(round_source, false),
		[STANCE] = build_stance(CONFIG.stance_linger, false),
	}
	actions.action_two = {
		default = build_charge(charge_source, true),
		[CHARGE_IN_STANCE] = build_charge(charge_source, false),
		[THROW] = build_throw(),
		[STANCE_AFTER_THROW] = build_stance(CONFIG.stance_linger_alt - CONFIG.throw_time, true),
	}
	actions.action_three = nil

	utils.set_actions_lookup_data({
		action_one = actions.action_one,
		action_two = actions.action_two,
	}, TEMPLATE_NAME)

	template.ammo_data.max_ammo = CONFIG.max_ammo
	template.ammo_data.ammo_per_clip = CONFIG.max_ammo
	template.ammo_data.ammo_per_reload = CONFIG.max_ammo
	template.ammo_data.ammo_immediately_available = true
	template.ammo_data.reload_time = 0.2

	template.attack_meta_data.can_charge_shot = false
	template.attack_meta_data.charged_attack_action_name = nil
	template.attack_meta_data.fire_input = "fire_hold"
	template.attack_meta_data.max_range = CONFIG.bot_max_range

	template.tooltip_compare = {
		light = {
			action_name = "action_one",
			sub_action_name = "default",
		},
		heavy = {
			action_name = "action_one",
			sub_action_name = "default",
		},
	}
	template.tooltip_detail = template.tooltip_compare
end

mod.items.set_template_changes(TEMPLATE_NAME, apply_template)

assault.template_name = TEMPLATE_NAME
assault.fire_rate = CONFIG.fire_rate
assault.grenade_fire_rate = CONFIG.grenade_fire_rate
assault.grenade_speed = { CONFIG.grenade_speed_min, CONFIG.grenade_speed_max, CONFIG.grenade_speed_gain }
-- (for the rifles' angles in the stance, skin.lua)
assault.stance_linger = CONFIG.stance_linger
assault.stance_linger_after_throw = CONFIG.stance_linger_alt
