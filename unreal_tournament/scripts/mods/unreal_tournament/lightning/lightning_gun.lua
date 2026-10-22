local mod = get_mod("unreal_tournament")

-- Lightning Gun: Kerillian's, made on the shell of the Deepwood Staff (utils.template_shell), as the Shock Rifle is of the Beam Staff.
-- The numbers come from UT2004 (XWeapons/SniperRifle, SniperFire and SniperZoom).
--   Left button: fires a lightning bolt that hits at once. After it hits, three short arcs of lightning jump from the place it hit
--       to enemies near it. A hit on the head does double damage.
--   Right button: zooms. Holding it zooms in, until it is let go, and the zoom stays. Pressing it again zooms out.
--   Reload: vents the heat, as the staff does.
-- UT's Lightning Gun has 40 rounds of ammo. Here a bolt adds heat instead, half as much as the Beam Staff's charged shot, and overheating
-- is the Deepwood Staff's: the player loses part of their health and the gun is locked out while the heat cools.
-- The staff is the Sister of the Thorn's only, so the copy is given to all four of Kerillian's careers. They have the same third person
-- body (way_watcher), whose animations the staff uses. The skin (skin.lua) draws all of it, and this file only sets what it does to
-- the game.

local utils = mod.utils
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for
local first_beam_hit = utils.first_beam_hit

local DESCRIPTION = "The Lightning Gun is a high-power energy rifle capable of ablating even the heaviest carapace armor. Acquisition of a target at long range requires a steady hand, but the anti-jitter effect of the optical system reduces the weapon's learning curve significantly."

-- Kerillian's careers. The Sister of the Thorn is the staff's own.
local CAREERS = { "we_shade", "we_maidenguard", "we_waywatcher", "we_thornsister" }

local SETTING_ID = "lightning_gun"
local ITEM_KEY = "ut_lightning_gun"
local TEMPLATE_NAME = "ut_lightning_gun_template"

mod.items.register(SETTING_ID, {
	key = ITEM_KEY,
	template = TEMPLATE_NAME,
	base_item = "we_life_staff",
	can_wield = CAREERS,
	-- A staff's: the overcharge traits
	slot_type = "ranged",
	property_table_name = "ranged",
	trait_table_name = "ranged_heat",
	deus_property_table_name = "deus_ranged",
	deus_trait_table_name = "deus_ranged_heat",
	name = "UT2004 Lightning Gun",
	type_name = "Lightning Gun",
	description = DESCRIPTION,
	keywords = { "weapon_keyword_high_damage", "weapon_keyword_sniper", "weapon_keyword_overheat" },
	icon = "ut_lightning_gun_icon",
	icon_package = "resource_packages/unreal_tournament/icons",
	icon_materials = "ui/ut/lightning_gun_icon",
})

local TEMPLATE_NAMES = {
	[TEMPLATE_NAME] = true,
}

local CONFIG = {
	-- The heat of a bolt: half the Beam Staff's charged shot's (4 of the 40 a player can take), so ten bolts heat the gun to the top and
	-- an eleventh overheats it. UT's gun has 40 rounds instead.
	bolt_overcharge = PlayerUnitStatusSettings.overcharge_values.beam_staff_sniper / 2,
	-- Every career of Kerillian overheats as the Sister of the Thorn does with the staff (her OverchargeData): she loses 40% of her
	-- health, the staff is locked out until the heat is gone, and there is no explosion. The other careers have no data of their own,
	-- which would make them overheat as Sienna does, losing all of their health.
	overheat_like = "we_thornsister",
	-- SniperFire.FireRate. After a shot, the next one can be made once this much time has passed.
	fire_rate = 1.6,
	chain_margin = 0.15, -- seconds
	-- The damage is in UT2004's units, where 45 is the shock rifle's beam. SniperFire.DamageMin and DamageMax are 70.
	damage = 70,
	-- SniperFire.HeadShotDamageMult
	headshot_multiplier = 2,
	-- The multipliers of the damage and the stagger for each armor type: unarmored, armored, monsters, players, berserkers and super
	-- armor. UT has no armor, and the bolt is said to ablate even the heaviest carapace. The game's own multiplier for beams is 0
	-- against super armor, which chaos warriors have.
	armor_attack = {1, 1, 1.2, 1, 1, 0.6},
	armor_impact = {1, 1, 1, 1, 1, 0.6},
	-- How far a bolt that hits nothing goes, in meters. UT's SniperFire.TraceRange is 17000 units.
	bolt_range = 100,
	-- The arcs (SniperFire.NumArcs, SecDamageMult and SecTraceDist: 3 arcs of 300 units that do half the damage). They start a little
	-- off the surface the bolt hit (2 units) and go in random directions.
	arc_count = 3,
	arc_damage_multiplier = 0.5,
	arc_range = 6, -- m
	arc_start_offset = 0.04, -- m
	-- An arc goes for an enemy within this of where the bolt hit, the nearest first and one each, and the arcs left over go in random
	-- directions, as UT's all do. This is the mod's own: UT's arcs only hit what happens to be in their way. A choice, half their range.
	arc_seek_range = 3, -- m
	-- How far a bot shoots from, in meters
	bot_max_range = 60,
	-- The camera shake of a shot is the handgun's recoil, scaled by this.
	recoil_scale = 0.5,
}

local TOTAL_TIME = CONFIG.fire_rate + CONFIG.chain_margin

PlayerUnitStatusSettings.overcharge_values.ut_lightning_bolt = CONFIG.bolt_overcharge

-- The overheating of the Sister of the Thorn for the careers that have none of their own. The game reads it when it spawns a
-- character, so a career has it from its next spawn. Her burst of thorns as she overheats (explode_vfx_name) is left out: its effect is
-- in her career's package, which the game loads only for her, and playing an effect that isn't loaded crashes the game.
local overheat_given = {}

for _, career_name in ipairs(CAREERS) do
	if not OverchargeData[career_name] then
		OverchargeData[career_name] = table.clone(OverchargeData[CONFIG.overheat_like])
		OverchargeData[career_name].explode_vfx_name = nil
		overheat_given[#overheat_given + 1] = career_name
	end
end

mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
	for _, career_name in ipairs(overheat_given) do
		OverchargeData[career_name] = nil
	end
end

-- Spread: the bolt hits exactly where the crosshair is.
utils.zero_spread_template("ut_lightning_bolt", "handgun")

-- Damage profiles (see utils.add_damage_profile)
-- The bolt stops at the first enemy it hits, as UT's trace does: a cleave that is tiny hurts one enemy. A hit on the head does
-- HeadShotDamageMult times the damage to every enemy, bosses too: a boost of 1 on a curve that ends at 1. A critical hit has the same
-- armor multipliers as any other.
local headshot_boost = math.clamp(CONFIG.headshot_multiplier - 1, 0, 1)
local BOLT = {
	charge_value = "instant_projectile",
	shield_break = true,
	no_stagger_damage_reduction_ranged = true,
	is_explosion = false,
	-- (the handgun's sniper shot's hit reactions and hit effects)
	attack_template = "shot_sniper",
	damage_type = "shot_sniper",
	attack_power = attack_power_for(CONFIG.damage),
	impact_power = impact_power_for(CONFIG.damage),
	armor_attack = CONFIG.armor_attack,
	armor_impact = CONFIG.armor_impact,
	critical_armor_attack = CONFIG.armor_attack,
	critical_armor_impact = CONFIG.armor_impact,
	cleave_attack = 0.01,
	cleave_impact = 0.01,
	boost_curve_type = "smiter_curve",
	boost_curve_coefficient = 1,
	boost_curve_coefficient_headshot = 1,
	headshot_boost = headshot_boost,
	headshot_boost_boss = headshot_boost,
	headshot_boost_armor = headshot_boost,
	headshot_boost_heavy_armor = headshot_boost,
	no_headshot_boost = false,
	crit_boost = 0.5,
	no_crit_boost = false,
	stagger_duration_modifier = 1,
	stagger_distance_modifier = 1,
}

utils.add_damage_profile("ut_lightning_bolt", BOLT)

-- An arc does half of the bolt's damage. It never hits the head, as in UT, where only the first trace looks for a head shot.
utils.add_damage_profile("ut_lightning_arc", utils.damage_profile_spec(BOLT, {
	attack_power = attack_power_for(CONFIG.damage * CONFIG.arc_damage_multiplier),
	impact_power = impact_power_for(CONFIG.damage * CONFIG.arc_damage_multiplier),
	no_headshot_boost = true,
}))

-- The bolt and the arcs have no hit effect of their own. Without this, the game would play the sound, particles and decals of the
-- surface that is hit. The skin draws the impact instead (see mod.silent_hit_effects in hooks.lua).
local NO_HIT_EFFECT = "ut_lightning_impact"

mod.silent_hit_effects[NO_HIT_EFFECT] = true

-- The flow events of the game's handgun shot that start its tracer (ActionHandgun.client_owner_post_update)
local DROPPED_FLOW_EVENTS = {
	lua_bullet_trail = true,
	lua_bullet_trail_set = true,
}

-- What an arc is, to the game's hit processing: an action with the profile of the arc.
local ARC_ACTION = {
	damage_profile = "ut_lightning_arc",
	hit_effect = NO_HIT_EFFECT,
	ignore_shield_hit = true,
}

-- Weapon template

-- When each character last fired, on the machine that runs their actions, and how long the next shot waits: UT's fire time, scaled as
-- the game scaled that shot's action, whatever action the next one starts from (the zoom's, which a shot can turn into at once, say).
-- The scale is the one the shot's action started with, as the game keeps it for the action's chain window: the overheat's slower
-- attacks (the overcharged buff) start with the shot that heats the gun that far, so the shot after it must wait as long as its window
-- says, or a held button would miss the window and stop.
local last_shots = setmetatable({}, {
	__mode = "k",
})

local function ready_to_fire(unit)
	local last = last_shots[unit]

	return not last or Managers.time:time("game") - last.time >= last.wait - 0.01
end

-- The actions that can follow a shot. Holding the button repeats the shot, as in UT, the heat can be vented, and the zoom can start at
-- any time.
local function fire_chain_actions()
	local entries = {
		{
			action = "action_wield",
			input = "action_wield",
			start_time = 0.4,
			sub_action = "default",
		},
		{
			action = "weapon_reload",
			input = "weapon_reload",
			start_time = 0.4,
			sub_action = "default",
		},
		{
			action = "action_two",
			input = "action_two",
			start_time = 0,
			sub_action = "default",
		},
	}

	for _, input in ipairs({ "action_one", "action_one_hold" }) do
		entries[#entries + 1] = {
			action = "action_one",
			input = input,
			start_time = CONFIG.fire_rate,
			sub_action = "default",
		}
	end

	return entries
end

-- The bolt can be fired when the gun is not locked out by its heat and UT's fire time has passed
local function can_fire(action_user)
	local overcharge_extension = ScriptUnit.extension(action_user, "overcharge_system")

	return overcharge_extension:are_you_locked_out() == false and ready_to_fire(action_user)
end

-- The shot: the game's handgun shot (kind "handgun"), which hits at once. It adds heat instead of using ammo and can be repeated after
-- UT's fire time. The animation of the characters is the staff's shot. The values that are not UT's are the ones it had as a copy of
-- Kruber's handgun's shot: how loud it is to enemies, the aim assist, the talents' kind of hit (charge_value), when its damage is dealt,
-- and its recoil, which is the camera's shake, at half of the handgun's.
local function build_shot()
	return {
		kind = "handgun",
		-- (the staff is the left hand's, as its own actions say)
		weapon_action_hand = "left",
		anim_event = "attack_shoot",
		overcharge_type = "ut_lightning_bolt",
		fire_time = 0,
		-- The shot lasts slightly longer than the time to the next shot. A held button is only read while a shot is still running, so a
		-- shot that ends exactly when the next one may start would miss it.
		total_time = TOTAL_TIME,
		damage_window_start = 0.1,
		damage_window_end = 0,
		damage_profile = "ut_lightning_bolt",
		headshot_multiplier = CONFIG.headshot_multiplier,
		hit_effect = NO_HIT_EFFECT,
		ignore_shield_hit = true,
		ranged_attack = true,
		charge_value = "light_attack",
		alert_sound_range_fire = 10,
		alert_sound_range_hit = 2,
		aim_assist_max_ramp_multiplier = 1,
		aim_assist_ramp_decay_delay = 0.1,
		aim_assist_ramp_multiplier = 0.3,
		apply_recoil = true,
		recoil_settings = {
			climb_duration = 0.2,
			horizontal_climb = 0,
			restore_duration = 0.3,
			vertical_climb = 3 * CONFIG.recoil_scale,
			climb_function = math.easeInCubic,
			restore_function = math.ease_out_quad,
		},
		reload_when_out_of_ammo = false,
		spread_template_override = "ut_lightning_bolt",
		allowed_chain_actions = fire_chain_actions(),
		condition_func = can_fire,
		chain_condition_func = can_fire,
		enter_function = function (attacker_unit, input_extension)
			input_extension:clear_input_buffer()
		end,
		ut_lightning_bolt = true,
		-- The game's tracer is not drawn: the bolt is the skin's (hooks.lua)
		ut_dropped_flow_events = DROPPED_FLOW_EVENTS,
	}
end

-- Venting the heat: the staff's. Holding the reload button vents it over 3 seconds while the player is slowed, when there is heat, the
-- gun is not locked out and the player's talents let them vent.
local function can_vent(action_user)
	local overcharge_extension = ScriptUnit.extension(action_user, "overcharge_system")

	if overcharge_extension:get_overcharge_value() == 0 or overcharge_extension:are_you_locked_out() ~= false then
		return false
	end

	local buff_extension = ScriptUnit.extension(action_user, "buff_system")

	return buff_extension:apply_buffs_to_value(1, "vent_speed") > 0
end

local function build_vent()
	return {
		kind = "charge",
		weapon_action_hand = "left",
		anim_event = "cooldown_start",
		anim_end_event = "cooldown_end",
		anim_end_event_condition_func = function (unit, end_reason)
			return end_reason ~= "new_interupting_action"
		end,
		charge_effect_material_name = "Fire",
		charge_effect_material_variable_name = "intensity",
		charge_sound_name = "Play_weapon_life_staff_cooldown_loop",
		charge_sound_stop_event = "Stop_weapon_life_staff_cooldown_loop",
		charge_time = 3,
		do_not_validate_with_hold = true,
		hold_input = "weapon_reload_hold",
		minimum_hold_time = 0.5,
		uninterruptible = true,
		vent_overcharge = true,
		total_time = math.huge,
		buff_data = {
			{
				buff_name = "planted_fast_decrease_movement",
				external_multiplier = 0.2,
				start_time = 0,
				end_time = math.huge,
			},
		},
		enter_function = function (attacker_unit, input_extension)
			input_extension:reset_release_input()
			input_extension:clear_input_buffer()
		end,
		allowed_chain_actions = {
			{
				action = "action_wield",
				input = "action_wield",
				start_time = 0.2,
				sub_action = "default",
			},
		},
		condition_func = can_vent,
		chain_condition_func = can_vent,
	}
end

-- Makes the gun on the shell of the staff (utils.template_shell): everything that is not the staff's animations, models and sounds is
-- set here
local function apply_staff(template)
	utils.template_shell(template)

	-- The chart of the item's stats, from 0 to 7. The bolt is the normal attack.
	template.weapon_diagram = {
		-- (full damage to armor and 1.2 to monsters; the arcs reach 3 more enemies for half damage; 0.47 of impact, where the repeater's
		-- 0.3 shows 3)
		light_attack = {
			[DamageTypes.ARMOR_PIERCING] = 7,
			[DamageTypes.CLEAVE] = 3,
			[DamageTypes.SPEED] = 2,
			[DamageTypes.STAGGER] = 5,
			[DamageTypes.DAMAGE] = 7,
		},
		heavy_attack = {
			[DamageTypes.ARMOR_PIERCING] = 0,
			[DamageTypes.CLEAVE] = 0,
			[DamageTypes.SPEED] = 0,
			[DamageTypes.STAGGER] = 0,
			[DamageTypes.DAMAGE] = 0,
		},
	}

	local actions = template.actions

	-- The shot, and UT's zoom in place of the staff's charged attack. Inspecting is the staff's, kept by the shell.
	actions.action_one = {
		default = build_shot(),
	}
	-- The zoom (zoom.lua): while it is held, a shot can follow at once (it waits for its fire time), and so can venting and wielding
	actions.action_two = {
		default = mod.zoom.action("left", {
			{
				action = "action_wield",
				input = "action_wield",
				start_time = 0,
				sub_action = "default",
			},
			{
				action = "weapon_reload",
				input = "weapon_reload",
				start_time = 0,
				sub_action = "default",
			},
			{
				action = "action_one",
				input = "action_one",
				start_time = 0,
				sub_action = "default",
			},
			{
				action = "action_one",
				input = "action_one_hold",
				start_time = 0,
				sub_action = "default",
			},
		}),
	}

	actions.weapon_reload = {
		default = build_vent(),
	}
	-- The game's own wielding
	actions.action_wield = table.clone(ActionTemplates.wield)

	utils.set_actions_lookup_data(actions, template.name)

	-- The staff's heat: its warning sounds, how soon it cools and how fast. Overheating is the career's (see overheat_like).
	template.overcharge_data = {
		explosion_template = "overcharge_explosion_brw",
		hit_overcharge_threshold_sound = "ui_special_attack_ready",
		overcharge_threshold = 10,
		overcharge_value_decrease_rate = 1,
		overcharge_warning_critical_sound_event = "weapon_life_staff_overcharge_warning_critical",
		overcharge_warning_high_sound_event = "weapon_life_staff_overcharge_warning_high",
		overcharge_warning_med_sound_event = "weapon_life_staff_overcharge_warning_medium",
		time_until_overcharge_decreases = 0.5,
	}

	-- What the game's talents, traits and properties take it for: the staff it is a copy of
	template.buff_type = "RANGED"
	template.weapon_type = "LIFE_STAFF"

	-- Dodging, the staff's, and a rifle's crosshair, not the staff's arrows, with the staff's spread (the bolt has none of its own, see
	-- ut_lightning_bolt). The staff's wield lit trails on the fingers of the first person arms, and its charged attack more: the skin
	-- hides the arms, but not their effects, so the gun has neither (the staff's on_wield and synced_states).
	template.buffs = {
		change_dodge_distance = {
			external_optional_multiplier = 1,
		},
		change_dodge_speed = {
			external_optional_multiplier = 1,
		},
	}
	template.crosshair_style = "default"
	template.default_spread_template = "spear"

	-- The aim assist for a controller: the staff's
	template.aim_assist_settings = {
		always_auto_aim = true,
		base_multiplier = 0,
		effective_max_range = 30,
		max_range = 50,
		no_aim_input_multiplier = 0,
		target_node = "j_spine1",
		breed_scalars = {
			skaven_clan_rat = 1,
			skaven_slave = 1,
			skaven_storm_vermin = 1,
		},
	}

	-- How bots use it. The game's bot shooting presses the left button when its aim is on an enemy, and the shot waits for its fire
	-- time. A bot aims at the head, which takes double damage, with the staff's aim for its charged shot, the long range one. It is used
	-- against every kind of enemy, bosses too (the bolt does 1.2 times its damage to monsters). A bot doesn't shoot through an enemy in
	-- the way, as the bolt stops at the first one. The heat is the game's bot tree's to watch (bt_bot.lua): a bot stops firing near the
	-- top of the heat and vents.
	local effective_against = bit.bor(BreedCategory.Infantry, BreedCategory.Shielded, BreedCategory.Berserker, BreedCategory.Boss, BreedCategory.Armored, BreedCategory.SuperArmor, BreedCategory.Special)

	template.attack_meta_data = {
		aim_at_node = "j_head",
		aim_data = {
			max_radius_pseudo_random_c = 0.01475,
			min_radius_pseudo_random_c = 0.0557,
			min_radius = math.pi / 72,
			max_radius = math.pi / 16,
		},
		can_charge_shot = false,
		effective_against = effective_against,
		effective_against_charged = 0,
		effective_against_combined = effective_against,
		ignore_enemies_for_obstruction = false,
		max_range = CONFIG.bot_max_range,
		obstruction_fuzzyness_range = 1,
	}

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

mod.items.set_template_changes(TEMPLATE_NAME, apply_staff)

-- The bolt and its arcs. The game's own shot damages what the bolt hits. This works out where the bolt ends, jumps the arcs, and tells
-- the skin what to draw. It runs on the machine that owns the shot, which is the player's, or the host's for its bots.

local random_direction = utils.random_direction

local function raycast(physics_world, origin, direction)
	return PhysicsWorld.immediate_raycast_actors(physics_world, origin, direction, "static_collision_filter", "filter_player_ray_projectile_static_only", "dynamic_collision_filter", "filter_player_ray_projectile_ai_only", "dynamic_collision_filter", "filter_player_ray_projectile_hitbox_only")
end

-- Returns the unit that a hit of a ray is on
local function hit_unit_of(hit)
	local actor = hit[4]
	local unit = Actor.unit(actor)

	return (ActionUtils.redirect_shield_hit(unit, actor))
end

-- The living enemies of the shooter within arc_seek_range of where the bolt hit, other than the one it hit, nearest first, each as the
-- point an arc goes for (its spine)
local function arc_targets(shot, origin, main_unit, world)
	local targets = {}

	for unit in pairs(utils.units_in_radius(world, origin, CONFIG.arc_seek_range)) do
		if unit ~= main_unit and HEALTH_ALIVE[unit] and DamageUtils.is_enemy(shot.owner_unit, unit) then
			local point = Unit.has_node(unit, "j_spine") and Unit.world_position(unit, Unit.node(unit, "j_spine")) or Unit.world_position(unit, 0) + Vector3.up()

			targets[#targets + 1] = {
				distance = Vector3.distance(origin, point),
				point = Vector3Box(point),
			}
		end
	end

	table.sort(targets, function (a, b)
		return a.distance < b.distance
	end)

	return targets
end

-- Jumps the arcs from the place the bolt hit. Returns where each one ends, and the normal of what it hit: the surface's, or the way
-- back along the arc if it hit nothing (SniperFire.DoTrace). An arc that hits an enemy that is not the one the bolt hit damages it. The
-- arcs go for the enemies near (arc_targets) before they go in random directions. An arc's hit runs the buffs on attack (talents and
-- traits) as the next target of the bolt's shot, as the game's shots that go through enemies number them (the bolt's own hit is the
-- first, DamageUtils._projectile_hit_character's target_number). An arc that hits an enemy that another arc has hit damages it again,
-- but runs no buffs: it is not a new target.
local function jump_arcs(shot, origin, main_unit, world)
	local arcs = {}
	local normals = {}
	local targets = arc_targets(shot, origin, main_unit, world)
	-- (the enemies the arcs have hit, and how many targets the shot has, the bolt's included)
	local hit_units = {}
	local target_number = 1

	for i = 1, CONFIG.arc_count do
		local target = targets[i]
		local direction = target and Vector3.normalize(target.point:unbox() - origin) or random_direction()
		local hits = raycast(shot.physics_world, origin, direction)
		local hit = first_beam_hit(hits, shot.owner_unit)
		local ends = hit and hit[2] <= CONFIG.arc_range
		local end_position = ends and hit[1] or origin + direction * CONFIG.arc_range

		arcs[#arcs + 1] = end_position
		normals[#normals + 1] = ends and hit[3] or -direction

		if ends then
			local unit = hit_unit_of(hit)

			if unit ~= main_unit and Unit.get_data(unit, "breed") then
				local new_target = not hit_units[unit]

				if new_target then
					hit_units[unit] = true
					target_number = target_number + 1
				end

				DamageUtils.process_projectile_hit(world, shot.item_name, shot.owner_unit, shot.is_server, { hit }, ARC_ACTION, direction, new_target, nil, nil, shot._is_critical_strike, shot.power_level, nil, target_number)
			end
		end
	end

	return arcs, normals
end

mod.handgun_start_callbacks.lightning = function (self, new_action)
	self._ut_lightning_checked = not new_action.ut_lightning_bolt

	if new_action.ut_lightning_bolt then
		last_shots[self.owner_unit] = {
			time = Managers.time:time("game"),
			wait = CONFIG.fire_rate / ActionUtils.get_action_time_scale(self.owner_unit, new_action),
		}
	end
end

mod.handgun_update_callbacks.lightning = function (self)
	if self._ut_lightning_checked or self.state == "waiting_to_shoot" then
		return
	end

	self._ut_lightning_checked = true

	local owner_unit = self.owner_unit
	local first_person_extension = ScriptUnit.extension(owner_unit, "first_person_system")
	local origin, rotation = first_person_extension:get_projectile_start_position_rotation()
	local direction = Quaternion.forward(rotation)
	local hit = first_beam_hit(raycast(self.physics_world, origin, direction), owner_unit)
	local end_position = hit and hit[1] or origin + direction * CONFIG.bolt_range
	-- The surface normal is the zero-length vector when there is no surface.
	local hit_normal = hit and hit[3] or Vector3.zero()
	-- The arcs start a little off the surface. A bolt that hits nothing has no arcs.
	local arcs_start = hit and hit[1] + hit[3] * CONFIG.arc_start_offset or end_position
	local arcs, arc_normals = {}, {}

	if hit then
		arcs, arc_normals = jump_arcs(self, arcs_start, hit_unit_of(hit), self.world)
	end

	-- The scope's charge bar and the sparks at the tip of the weapon follow the player's shots
	if utils.is_local_player_unit(owner_unit) then
		mod.lightning.last_fire_time = Managers.time:time("game")
		mod.lightning.shot_wait = last_shots[owner_unit] and last_shots[owner_unit].wait or CONFIG.fire_rate
	end

	mod.lightning.bolt(owner_unit, end_position, hit_normal, arcs, arcs_start, arc_normals)
end

-- What the skin is told (mod.lightning_bolt_callbacks in hooks.lua), and what is sent to the other players. The skin draws the bolt of
-- the player who fires, from the weapon in their own view, and the others see it come from the weapon of the player's character.
mod.lightning = {
	-- The seconds between shots, when the player last fired, and how long the player's next shot waits after that (see ready_to_fire)
	fire_rate = CONFIG.fire_rate,
	last_fire_time = nil,
	shot_wait = nil,
}

-- The game's time starts again in each level, so a shot of the last level would keep the gun from being ready until the new level's time
-- got as far
mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	mod.lightning.last_fire_time = nil
	mod.lightning.shot_wait = nil

	table.clear(last_shots)
end

-- A vector's three numbers. Vectors are userdata, and a missing one is the zero vector.
local function components(vector)
	if not vector then
		return 0, 0, 0
	end

	return Vector3.x(vector), Vector3.y(vector), Vector3.z(vector)
end

function mod.lightning.bolt(owner_unit, end_position, hit_normal, arcs, arcs_start, arc_normals)
	for _, callback in pairs(mod.lightning_bolt_callbacks) do
		callback(owner_unit, end_position, hit_normal, arcs, arcs_start, arc_normals)
	end

	-- The arcs go as a list of numbers: each arc's end and its normal
	local arc_numbers = {}

	for i = 1, #arcs do
		local end_x, end_y, end_z = components(arcs[i])
		local arc_normal_x, arc_normal_y, arc_normal_z = components(arc_normals[i])

		for _, number in ipairs({ end_x, end_y, end_z, arc_normal_x, arc_normal_y, arc_normal_z }) do
			arc_numbers[#arc_numbers + 1] = number
		end
	end

	local end_x, end_y, end_z = components(end_position)
	local normal_x, normal_y, normal_z = components(hit_normal)
	local start_x, start_y, start_z = components(arcs_start)

	mod:network_send("ut_lightning_bolt", "others", Managers.state.unit_storage:go_id(owner_unit), end_x, end_y, end_z, normal_x, normal_y, normal_z, start_x, start_y, start_z, arc_numbers)
end

mod:network_register("ut_lightning_bolt", function (_, owner_go_id, x, y, z, normal_x, normal_y, normal_z, start_x, start_y, start_z, arc_numbers)
	local unit = Managers.state.unit_storage:unit(owner_go_id)

	if not unit or not Unit.alive(unit) then
		return
	end

	local arcs, arc_normals = {}, {}

	for i = 1, #arc_numbers - 5, 6 do
		local n = arc_numbers

		arcs[#arcs + 1] = Vector3(n[i], n[i + 1], n[i + 2])
		arc_normals[#arc_normals + 1] = Vector3(n[i + 3], n[i + 4], n[i + 5])
	end

	for _, callback in pairs(mod.lightning_bolt_callbacks) do
		callback(unit, Vector3(x, y, z), Vector3(normal_x, normal_y, normal_z), arcs, Vector3(start_x, start_y, start_z), arc_normals)
	end
end)

-- Bots vent the heat above the threshold too. The game's bots start to vent only between half the threshold and just under it
-- (bt_bot.lua's vent_overcharge), where venting doesn't hurt them, which suits the staves' small shots. A bolt adds 8 heat against a
-- threshold of 10, so after two bolts a bot would wait seconds for the heat to cool before it could vent, and after more, close to a
-- minute. Here a bot with the Lightning Gun starts to vent at any heat from half the threshold up, and takes the venting's damage above
-- the threshold, as a player does.
mod:hook(BTConditions, "should_vent_overcharge", function (func, blackboard, args, ...)
	local inventory_extension = blackboard.inventory_extension
	local slot_data = inventory_extension and inventory_extension:get_slot_data("slot_ranged")
	local item_data = slot_data and slot_data.item_data

	if blackboard.reloading or not item_data or not TEMPLATE_NAMES[item_data.template] or args.overcharge_limit_type ~= "threshold" then
		return func(blackboard, args, ...)
	end

	local current, threshold = blackboard.overcharge_extension:current_overcharge_status()

	return current / threshold >= args.start_min_percentage
end)

-- The zoom is UT's (zoom.lua)
mod.zoom.register(TEMPLATE_NAME)

mod.lightning.zoom = mod.zoom

