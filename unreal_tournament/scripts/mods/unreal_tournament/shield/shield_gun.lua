local mod = get_mod("unreal_tournament")

-- Shield Gun: a copy of a melee weapon with its attacks replaced. The numbers come from UT2004 (XWeapons/ShieldGun, ShieldFire and
-- ShieldAltFire).
--   Left button: held, it charges the gun, for up to 2.5 seconds. Let go, it punches what is right in front with a wave of force, for
--       40 to 150 damage by how long it charged. While it charges, it punches by itself as soon as an enemy is in reach. Punching a wall
--       throws the player away from it (the shield jump).
--   Right button: the base weapon's block. UT's shield blocks what comes from the front and is drained by what it stops, which is what
--       the game's block and stamina do. The skin draws UT's shield while it is up.
-- Each hero has a melee weapon to be a copy of, so the weapon is six items of the mod that share everything but the base.
-- The skin (skin.lua) draws all of it, and this file only sets what it does to the game.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local register_damage_profile = utils.register_damage_profile
local make_flat = utils.make_flat
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for
local first_beam_hit = utils.first_beam_hit

local DESCRIPTION = "The Kemphler DD280 Riot Control Device has the ability to resist and reflect incoming projectiles and energy beams. The plasma wave inflicts massive damage, rupturing tissue, pulverizing organs, and flooding the bloodstream with dangerous gas bubbles."

-- The items, one for each hero. The careers of each are those of its base.
local VARIANTS = {
	{
		base_item = "es_bastard_sword",
		deus_copy = "deus_es_bastard_sword",
		id = "shield_gun",
		key = "ut_shield_gun",
		template = "ut_shield_gun_template",
	},
	{
		base_item = "dr_2h_cog_hammer",
		deus_copy = "deus_dr_2h_cog_hammer",
		id = "shield_gun_dr",
		key = "ut_shield_gun_dr",
		template = "ut_shield_gun_dr_template",
	},
	{
		base_item = "bw_ghost_scythe",
		deus_copy = "deus_bw_ghost_scythe",
		id = "shield_gun_bw",
		key = "ut_shield_gun_bw",
		template = "ut_shield_gun_bw_template",
	},
	{
		base_item = "wh_2h_billhook",
		deus_copy = "deus_wh_2h_billhook",
		id = "shield_gun_wh",
		key = "ut_shield_gun_wh",
		template = "ut_shield_gun_wh_template",
	},
	{
		base_item = "we_spear",
		deus_copy = "deus_we_spear",
		id = "shield_gun_we",
		key = "ut_shield_gun_we",
		template = "ut_shield_gun_we_template",
	},
	{
		base_item = "wh_1h_hammer",
		deus_copy = "deus_wh_1h_hammer",
		id = "shield_gun_priest",
		key = "ut_shield_gun_priest",
		template = "ut_shield_gun_priest_template",
	},
}

for _, variant in ipairs(VARIANTS) do
	mod.items.register(variant.id, {
		key = variant.key,
		template = variant.template,
		base_item = variant.base_item,
		deus_copy = variant.deus_copy,
		name = "UT2004 Shield Gun",
		type_name = "Shield Gun",
		description = DESCRIPTION,
		keywords = { "weapon_keyword_high_damage", "weapon_keyword_charged_attack", "weapon_keyword_damage_against_armoured" },
		icon = "ut_shield_gun_icon",
		icon_package = "resource_packages/unreal_tournament/icons",
		icon_materials = "ui/ut/shield_gun_icon",
	})
end

local TEMPLATE_NAMES = {}

for _, variant in ipairs(VARIANTS) do
	TEMPLATE_NAMES[mod.items.weapons[variant.id].template] = true
end

local CONFIG = {
	meters_per_uu = 0.02, -- Unreal unit to meters
	-- ShieldFire.ShieldRange: how far the punch reaches from the player, in UT units
	range = 112,
	-- ShieldFire.MinHoldTime and FullyChargedTime: held for MinHoldTime or less, the punch does MinDamage; held for FullyChargedTime or
	-- more, MaxDamage; in between, in a line
	min_hold_time = 0.4,
	fully_charged_time = 2.5,
	min_damage = 40,
	max_damage = 150,
	-- The damage is a profile for each of this many steps between the two
	damage_steps = 12,
	-- ShieldFire.FireRate: after a punch, the next charge starts this long after
	fire_rate = 0.6,
	-- ShieldFire.AutoFireTestFreq: how often the charge looks for an enemy in reach
	auto_fire_test_freq = 0.15,
	-- ShieldFire.MinForce and MaxForce: the push of a punch, UT's momentum. A wall pushes the player back with SelfForceScale (1) of
	-- it. UT divides momentum by the player's mass (100) for the speed, and on the ground makes the upward part at least 0.4 of it
	-- (Pawn.TakeDamage).
	min_force = 65000,
	max_force = 100000,
	self_force_scale = 1,
	ut_mass = 100,
	ground_lift = 0.4,
	-- Pawn.TakeDamage takes the momentum a player gives themselves down to this share (instigatedBy == self), after the lift
	self_momentum = 0.6,
	-- UT speeds are turned into this game's, upward by the ratio of the jumps (UT's JumpZ is 340 units a second, and the mod's jump is
	-- 4.25 * 1.35 m/s, movement.lua) and along the ground by the ratio of the run speeds (UT's GroundSpeed is 440, and the game's is
	-- PlayerUnitMovementSettings.move_speed). This game runs slower for its jump than UT, so one ratio for both would push the player
	-- along the ground about twice as hard for their run as UT does. The movement's dodges are made from the run speed the same way.
	ut_speed_to_mps = 4.25 * 1.35 / 340,
	ut_ground_speed = 440,
	-- The multipliers of the damage and the stagger for each armor type: unarmored, armored, monsters, players, berserkers and super
	-- armor. UT has no armor, and the punch's force is not stopped by it.
	armor_attack = {1, 1, 1, 1, 1, 0.8},
	armor_impact = {1, 1, 1, 1, 1, 1},
}

local UNIT = CONFIG.meters_per_uu

-- What the gun does now, on the player's own machine, for the skin
mod.shield = {
	charge_started = nil, -- when the charge started, or nil
	last_punch = nil, -- when the last punch was
	fully_charged_time = CONFIG.fully_charged_time,
}

-- Damage profiles: one for each step of the charge

local function damage_for_step(step)
	return CONFIG.min_damage + (CONFIG.max_damage - CONFIG.min_damage) * step / (CONFIG.damage_steps - 1)
end

local PUNCH_ACTIONS = {}

for step = 0, CONFIG.damage_steps - 1 do
	local name = "ut_shield_punch_" .. step
	local damage = damage_for_step(step)

	register_damage_profile(name, "shot_sniper", function (profile)
		make_flat(profile, attack_power_for(damage), impact_power_for(damage), "blunt")

		-- The punch hurts the one thing it hits, as UT's trace does
		profile.cleave_distribution = {
			attack = 0.01,
			impact = 0.01,
		}
		utils.set_armor_modifiers(profile, CONFIG.armor_attack, CONFIG.armor_impact)
	end)

	-- What a punch is, to the game's hit processing
	PUNCH_ACTIONS[step] = {
		damage_profile = name,
		hit_effect = "melee_hit_hammers_2h",
		ignore_shield_hit = true,
	}
end

-- The step of the charge after holding for some time (ShieldFire.DoFireEffect)
local function charge_step(hold_time)
	local scale = (math.clamp(hold_time, CONFIG.min_hold_time, CONFIG.fully_charged_time) - CONFIG.min_hold_time) / (CONFIG.fully_charged_time - CONFIG.min_hold_time)

	return math.floor(scale * (CONFIG.damage_steps - 1) + 0.5), scale
end

-- What is in reach in front of a player: the first thing the ray from their eyes hits within the range, and whether it is an enemy
local function raycast(physics_world, origin, direction)
	return PhysicsWorld.immediate_raycast_actors(physics_world, origin, direction, CONFIG.range * UNIT, "static_collision_filter", "filter_player_ray_projectile_static_only", "dynamic_collision_filter", "filter_player_ray_projectile_ai_only", "dynamic_collision_filter", "filter_player_ray_projectile_hitbox_only")
end

local function in_reach(owner_unit, physics_world)
	local first_person_extension = ScriptUnit.has_extension(owner_unit, "first_person_system")

	if not first_person_extension then
		return nil
	end

	local origin = first_person_extension:current_position()
	local direction = Quaternion.forward(first_person_extension:current_rotation())
	local hit = first_beam_hit(raycast(physics_world, origin, direction), owner_unit)

	if not hit then
		return nil, nil, direction
	end

	local hit_unit = ActionUtils.redirect_shield_hit(Actor.unit(hit[4]), hit[4])

	return hit, Unit.get_data(hit_unit, "breed") ~= nil, direction
end

-- The charge ends by itself when an enemy comes into reach (ShieldFire.Timer). The game asks this every frame while the charge goes
-- on, and it looks every auto_fire_test_freq seconds.
local next_auto_test = {}

local function enemy_in_reach(unit)
	local t = Managers.time:time("game")

	if next_auto_test[unit] and t < next_auto_test[unit] then
		return false
	end

	next_auto_test[unit] = t + CONFIG.auto_fire_test_freq

	local world = Managers.world:world("level_world")
	local _, is_enemy = in_reach(unit, World.get_data(world, "physics_world"))

	return is_enemy == true
end

-- The shield jump: punching a wall pushes the player away from it (ShieldFire.DoFireEffect, Pawn.TakeDamage)
local function push_player(owner_unit, direction, force)
	local locomotion_extension = ScriptUnit.has_extension(owner_unit, "locomotion_system")

	if not locomotion_extension then
		return
	end

	local momentum = -direction * (CONFIG.self_force_scale * force / CONFIG.ut_mass)

	if locomotion_extension:is_on_ground() then
		local size = Vector3.length(momentum)

		momentum = Vector3(momentum.x, momentum.y, math.max(momentum.z, CONFIG.ground_lift * size))
	end

	local ground_scale = PlayerUnitMovementSettings.move_speed / CONFIG.ut_ground_speed
	local push = Vector3(momentum.x * ground_scale, momentum.y * ground_scale, momentum.z * CONFIG.ut_speed_to_mps) * CONFIG.self_momentum
	local velocity = locomotion_extension:current_velocity() + push

	locomotion_extension:set_maximum_upwards_velocity(math.huge)
	locomotion_extension:force_on_ground(false)
	locomotion_extension:set_forced_velocity(velocity)
	locomotion_extension:set_wanted_velocity(velocity)
end

-- When each player's charge started, on the machine that owns their actions
local charge_started = {}

local function punch(action, t, power_level)
	local owner_unit = action.owner_unit
	local hold_time = charge_started[owner_unit] and t - charge_started[owner_unit] or 0
	local step, scale = charge_step(hold_time)
	local hit, is_enemy, direction = in_reach(owner_unit, action.physics_world)

	charge_started[owner_unit] = nil

	if utils.is_local_player_unit(owner_unit) then
		mod.shield.charge_started = nil
		mod.shield.last_punch = t
	end

	if not hit then
		return
	end

	if is_enemy then
		DamageUtils.process_projectile_hit(action.world, action.item_name, owner_unit, action.is_server, { hit }, PUNCH_ACTIONS[step], direction, true, nil, nil, false, power_level)
	elseif utils.is_local_player_unit(owner_unit) then
		push_player(owner_unit, direction, CONFIG.min_force + scale * (CONFIG.max_force - CONFIG.min_force))
	end
end

mod.dummy_start_callbacks.shield_gun = function (action, new_action, t, power_level)
	if new_action.ut_shield_charge then
		charge_started[action.owner_unit] = t

		if utils.is_local_player_unit(action.owner_unit) then
			mod.shield.charge_started = t
		end
	elseif new_action.ut_shield_punch then
		punch(action, t, power_level)
	end
end

-- The actions

local function chain(action, sub_action, input, start_time)
	return {
		action = action,
		input = input,
		start_time = start_time or 0,
		sub_action = sub_action,
	}
end

-- The charge: held for as long as the button is, until it is let go or an enemy comes into reach
local function build_charge(original)
	local action = table.clone(original)

	action.kind = "dummy"
	action.total_time = math.huge
	action.buff_data = nil
	action.blocking_charge = nil
	action.ut_shield_charge = true
	action.allowed_chain_actions = {
		chain("action_one", "punch", "action_one_release"),
		{
			action = "action_one",
			auto_chain = true,
			start_time = 0,
			sub_action = "punch_auto",
		},
		chain("action_two", "default", "action_two_hold"),
		chain("action_wield", "default", "action_wield"),
	}

	return action
end

-- The punch: the hit is made when it starts (see punch above), and the next charge can start after the fire rate
local function build_punch(original, auto)
	local action = table.clone(original)

	action.kind = "dummy"
	action.total_time = CONFIG.fire_rate
	action.damage_window_start = nil
	action.damage_window_end = nil
	action.ut_shield_punch = true
	action.allowed_chain_actions = {
		chain("action_one", "default", "action_one", CONFIG.fire_rate),
		chain("action_one", "default", "action_one_hold", CONFIG.fire_rate),
		chain("action_two", "default", "action_two_hold", 0),
		chain("action_wield", "default", "action_wield", 0),
	}

	if auto then
		action.chain_condition_func = function (unit)
			return enemy_in_reach(unit)
		end
	end

	return action
end

local function apply_template(template_name)
	local template = rawget(Weapons, template_name)
	local actions = template.actions
	local original = actions.action_one
	local heavy = original.heavy_attack or original.heavy_attack_left or original.default

	-- The chart of the item's stats, from 0 to 7
	template.weapon_diagram = {
		light_attack = {
			[DamageTypes.ARMOR_PIERCING] = 5,
			[DamageTypes.CLEAVE] = 0,
			[DamageTypes.SPEED] = 3,
			[DamageTypes.STAGGER] = 6,
			[DamageTypes.DAMAGE] = 3,
		},
		heavy_attack = {
			[DamageTypes.ARMOR_PIERCING] = 6,
			[DamageTypes.CLEAVE] = 0,
			[DamageTypes.SPEED] = 1,
			[DamageTypes.STAGGER] = 7,
			[DamageTypes.DAMAGE] = 7,
		},
	}

	actions.action_one = {
		default = build_charge(original.default),
		punch = build_punch(heavy, false),
		punch_auto = build_punch(heavy, true),
	}

	-- The block does not push: UT's fire modes don't go together, so the button starts a charge again
	local block = actions.action_two and actions.action_two.default

	if block and block.allowed_chain_actions then
		local kept = {}

		for _, entry in ipairs(block.allowed_chain_actions) do
			if not (entry.action == "action_one" and entry.sub_action ~= "default") then
				kept[#kept + 1] = entry
			end
		end

		block.allowed_chain_actions = kept
	end

	utils.set_actions_lookup_data({
		action_one = actions.action_one,
	}, template_name)

	template.tooltip_compare = {
		light = {
			action_name = "action_one",
			sub_action_name = "punch",
		},
		heavy = {
			action_name = "action_one",
			sub_action_name = "punch",
		},
	}
	template.tooltip_detail = template.tooltip_compare
end

-- The templates are the mod's own copies (items.register), so they are changed once
for template_name in pairs(TEMPLATE_NAMES) do
	apply_template(template_name)
end

mod.shield.template_names = TEMPLATE_NAMES
