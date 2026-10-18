local mod = get_mod("unreal_tournament")

-- Minigun: a copy of a repeating gun with its fire modes replaced, the same way the Lightning Gun is a copy of the handgun. The numbers
-- come from UT2004 (XWeapons/Minigun, MinigunFire and MinigunAltFire).
--   Left button: the barrels spin up and the gun fires 15 rounds a second, with a wide spread, for as long as the button is held.
--   Right button: the same at 5 rounds a second, for twice the damage and a tight spread.
-- The two buttons do not fire at once. The skin (skin.lua) draws all of it. This file only sets what it does to the game.

local utils = mod.utils
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for

local DESCRIPTION = "The Schultz-Metzger T23-A 23mm rotary cannon is capable of firing both high-velocity caseless ammunition and cased rounds. With an unloaded weight of only 8 kilograms, the T23 is portable and maneuverable, easily worn across the back when employing the optional carrying strap."

-- The items. Kruber's careers have a repeating gun, and Saltzpyre's a repeater pistol, and they are separate templates. What the two
-- copies set differently is here: so far the base weapons' own values, written out (see apply_gun).
--   weapon_type: what the game's talents, traits and properties take the weapon for.
--   dodge_count: how many dodges in a row go the full distance. spread_template, spread_lerp_speed: the game's spread of the crosshair
--       (each round has UT's own spread, see ut_spread). aim_assist: the aim assist for a controller.
--   update_anim_ammo: whether the gun's animations are told how much ammo is left. fire_at_gaze_setting: the setting of Tobii's eye
--       tracking that fires where the player looks.
local VARIANTS = {
	{
		base_item = "es_repeating_handgun",
		deus_copy = "deus_es_repeating_handgun",
		id = "minigun",
		key = "ut_minigun",
		template = "ut_minigun_template",
		weapon_type = "REPEATING_HANDGUN",
		dodge_count = 1,
		spread_template = "repeating_handgun",
		spread_lerp_speed = 12,
		aim_assist = {
			always_auto_aim = true,
			base_multiplier = 0.15,
			effective_max_range = 10,
			max_range = 22,
			no_aim_input_multiplier = 0,
			breed_scalars = {
				skaven_clan_rat = 1,
				skaven_slave = 1,
				skaven_storm_vermin = 0.25,
			},
		},
		update_anim_ammo = false,
		fire_at_gaze_setting = false,
	},
	{
		base_item = "wh_repeating_pistols",
		deus_copy = "deus_wh_repeating_pistols",
		id = "minigun_wh",
		key = "ut_minigun_wh",
		template = "ut_minigun_wh_template",
		-- The characters fire from the aim of the base weapon's alt fire (see apply_gun)
		volley = true,
		weapon_type = "REPEATING_PISTOL",
		dodge_count = 3,
		spread_template = "repeating_pistol",
		spread_lerp_speed = 5,
		aim_assist = {
			aim_at_node = "j_neck",
			aim_at_node_charged = "j_spine",
			base_multiplier = 0.15,
			can_charge_shot = true,
			effective_max_range = 10,
			max_range = 22,
			no_aim_input_multiplier = 0,
			breed_scalars = {
				skaven_clan_rat = 1,
				skaven_slave = 1,
				skaven_storm_vermin = 1,
			},
		},
		update_anim_ammo = true,
		fire_at_gaze_setting = "tobii_fire_at_gaze_repeating_pistol",
	},
}

for _, variant in ipairs(VARIANTS) do
	mod.items.register(variant.id, {
		key = variant.key,
		template = variant.template,
		base_item = variant.base_item,
		deus_copy = variant.deus_copy,
		name = "UT2004 Minigun",
		type_name = "Minigun",
		description = DESCRIPTION,
		keywords = { "weapon_keyword_high_damage", "weapon_keyword_crowd_control", "weapon_keyword_headshotting" },
		icon = "ut_minigun_icon",
		icon_package = "resource_packages/unreal_tournament/icons",
		icon_materials = "ui/ut/minigun_icon",
	})
end

local TEMPLATE_NAMES = {}

-- Each template's variant
local VARIANT_OF = {}

for _, variant in ipairs(VARIANTS) do
	TEMPLATE_NAMES[mod.items.weapons[variant.id].template] = true
	VARIANT_OF[variant.template] = variant
end

local CONFIG = {
	-- UT2004's Minigun holds up to 300 rounds (it starts with 150). All of the ammo is the clip, so there is no reload.
	max_ammo = 300,
	-- MinigunFire.BarrelRotationsPerSec and RoundsPerRotation: the fire rate is 1 / (rounds * rotations a second). The wind up is how
	-- long the barrels take to reach their speed (MinigunFire.WindUpTime), and the first round leaves when they have.
	primary_rate = 1 / (5 * 3), -- seconds between rounds
	primary_wind_up = 0.27,
	primary_barrel_turns = 3, -- per second at full speed
	alt_rate = 1 / (5 * 1),
	alt_wind_up = 0.15,
	alt_barrel_turns = 1,
	-- The damage is in UT2004's units, where 45 is the shock rifle's beam. MinigunFire.DamageMin and DamageMax are 7 and 8, and
	-- MinigunAltFire's are 14 and 16.
	primary_damage = 7.5,
	alt_damage = 15,
	-- The multipliers of the damage and the stagger for each armor type: unarmored, armored, monsters, players, berserkers and super
	-- armor, for normal and critical hits. UT has no armor. The primary fire's small rounds are poor against it, and the alt fire's
	-- heavier ones go through more of it.
	armor_attack = {1, 0.5, 1, 1, 1, 0.3},
	armor_impact = {1, 1, 1, 1, 1, 0.5},
	alt_armor_attack = {1, 0.8, 1, 1, 1, 0.5},
	alt_armor_impact = {1, 1, 1, 1, 1, 0.5},
	-- MinigunFire.Spread and MinigunAltFire.Spread: each round is off the aim by a random share of this much of the aim's length
	primary_spread = 0.08,
	alt_spread = 0.03,
	-- How far a bot shoots from, in meters
	bot_max_range = 25,
	-- The view's kick of a round. UT shakes the view a little instead of climbing (MinigunFire's ShakeRotMag 50 on every axis: skin.lua
	-- starts that shake).
	recoil_climb = 0.12,
	-- A held button repeats the shot. The shot lasts this much longer than the time to the next round, because a held button is only
	-- read while a shot is still running.
	chain_margin = 0.05,
}

-- Damage profiles (see utils.add_damage_profile)
-- A round stops at the first enemy it hits, as UT's trace does. A round on the head has the game's usual bonus, the repeater's, as this
-- game's guns all do, where UT gives one only to its sniper weapons. A critical hit has the same armor multipliers as any other.
local BULLET = {
	charge_value = "instant_projectile",
	shield_break = true,
	no_stagger_damage_reduction_ranged = true,
	is_explosion = false,
	-- (the repeater's hit reactions, and the shotgun's hit effects)
	attack_template = "shot_repeating_handgun",
	damage_type = "shot_shotgun",
	attack_power = attack_power_for(CONFIG.primary_damage),
	impact_power = impact_power_for(CONFIG.primary_damage),
	armor_attack = CONFIG.armor_attack,
	armor_impact = CONFIG.armor_impact,
	critical_armor_attack = CONFIG.armor_attack,
	critical_armor_impact = CONFIG.armor_impact,
	cleave_attack = 0.01,
	cleave_impact = 0.01,
	boost_curve_type = "linesman_curve",
	boost_curve_coefficient = 0.6,
	boost_curve_coefficient_headshot = 1,
	headshot_boost = 0.5,
	headshot_boost_boss = 0.25,
	headshot_boost_armor = 0.5,
	headshot_boost_heavy_armor = 0.25,
	no_headshot_boost = false,
	crit_boost = 0.5,
	no_crit_boost = false,
	stagger_duration_modifier = 1,
	stagger_distance_modifier = 1,
}

utils.add_damage_profile("ut_minigun_bullet", BULLET)
utils.add_damage_profile("ut_minigun_alt_bullet", utils.damage_profile_spec(BULLET, {
	attack_power = attack_power_for(CONFIG.alt_damage),
	impact_power = impact_power_for(CONFIG.alt_damage),
	armor_attack = CONFIG.alt_armor_attack,
	armor_impact = CONFIG.alt_armor_impact,
	critical_armor_attack = CONFIG.alt_armor_attack,
	critical_armor_impact = CONFIG.alt_armor_impact,
}))

-- The state of the local player's barrels and buttons, which the skin draws and plays
mod.minigun = {
	-- The mode the barrels turn for, how fast they turn (0 to 1 of its speed), and whether they slow down to a stop
	mode = nil,
	spin = 0,
	winding_down = false,
	-- Whether the button of each mode is held, with ammo to fire
	held = {
		primary = false,
		alt = false,
	},
	-- The mode of the shot that was made last, and when
	last_shot_time = nil,
}

-- Weapon template

-- After a round, a held button fires the next round of its mode. The other mode doesn't follow: it can only start once the barrels have
-- stopped (barrels_stopped).
local function fire_chain_actions(own_action, loop_name, interval)
	return {
		-- (a weapon switch can end a round at any time: a round is shorter than the base weapon's 0.3 s, and a held button starts the
		-- next one at once)
		{
			action = "action_wield",
			input = "action_wield",
			start_time = 0,
			sub_action = "default",
		},
		{
			action = own_action,
			input = own_action .. "_hold",
			start_time = interval,
			sub_action = loop_name,
		},
	}
end

-- Returns whether a mode's first round can start: as in UT, only once the barrels have stopped (Minigun.StartFire waits for both modes to
-- be Idle), so a switch of modes, or a press while they still slow down, waits for them to stop and then winds up from the start. While
-- the mode's button is still held and its barrels turn, its rounds go on (something else ended the last one). The barrels' state is the
-- local player's; the others' guns (bots on the host) fire as their own machines let them.
local function can_start(mode)
	return function (unit)
		local state = mod.minigun

		return not utils.is_local_player_unit(unit) or state.spin <= 0 or state.mode == mode and not state.winding_down
	end
end

-- The flow events of the game's handgun shot that start its tracer (ActionHandgun.client_owner_post_update)
local DROPPED_FLOW_EVENTS = {
	lua_bullet_trail = true,
	lua_bullet_trail_set = true,
}

-- Builds a round of the gun's, the game's handgun shot (kind "handgun") with every field given. The first round has the wind up before
-- it, and the rounds after it follow at the fire rate. The hand is the base weapon's, as the game crashes on an action for a hand with no
-- weapon. anims is the base weapon's action whose animations a round plays: its rapid fire, made to be played a round after another.
-- volley is the aim of the base weapon's alt fire that the rapid fire is shot from, if the characters take it: { start, finish }
-- animations.
local function build_shot(mode, first, hand, anims, volley)
	local alt = mode == "alt"
	local interval = alt and CONFIG.alt_rate or CONFIG.primary_rate
	local wind_up = alt and CONFIG.alt_wind_up or CONFIG.primary_wind_up
	local own_action = alt and "action_two" or "action_one"
	local fire_time = first and wind_up or 0
	local action = {
		kind = "handgun",
		weapon_action_hand = hand,
		anim_event = anims.anim_event,
		anim_event_last_ammo = anims.anim_event_last_ammo,
		damage_profile = alt and "ut_minigun_alt_bullet" or "ut_minigun_bullet",
		fire_time = fire_time,
		-- The other button's shot can only follow once this round's time is over, so the two never fire at once (UT's fire modes are
		-- exclusive)
		total_time = fire_time + interval + CONFIG.chain_margin,
		allowed_chain_actions = fire_chain_actions(own_action, "loop", fire_time + interval),
		-- The gun fires while its button is held, as UT's does: the game starts an action with a hold_input when that button is held, not
		-- only when it is pressed (validate_action), so the rounds start again by themselves whenever something ends them, and a round ends
		-- when the button is let go
		hold_input = own_action .. "_hold",
		condition_func = first and can_start(mode) or nil,
		-- A hit on the player doesn't stop the rounds, as it doesn't in UT. Otherwise the game's hit reaction ends the round's action
		-- (CharacterStateHelper).
		uninterruptible = true,
		enter_function = function (attacker_unit, input_extension)
			input_extension:clear_input_buffer()
		end,
		ammo_usage = 1,
		-- (all the ammo is the clip: there is no reload)
		reload_when_out_of_ammo = false,
		reload_time = 0.5,
		-- The view's kick (see recoil_climb)
		apply_recoil = true,
		recoil_settings = {
			climb_duration = 0.05,
			climb_function = math.easeInCubic,
			horizontal_climb = 0,
			restore_duration = 0.2,
			restore_function = math.ease_out_quad,
			vertical_climb = CONFIG.recoil_climb,
		},
		-- What talents, traits and properties take a round for (the game's guns' value), and the critical hits: the career's chance, with
		-- nothing added
		charge_value = "bullet_hit",
		additional_critical_strike_chance = 0,
		critical_strike = {},
		-- (not used for damage, see the damage profiles; the game's repeater has it)
		headshot_multiplier = 2,
		-- The game's own impact, which the skin draws UT's on top of
		hit_effect = "bullet_impact",
		critical_hit_effect = "bullet_critical_impact",
		-- (for the stat chart's speed: a round's hit is this long after it starts)
		damage_window_start = 0.1,
		damage_window_end = 0,
		-- How far away enemies hear a round, and its hit, in meters
		alert_sound_range_fire = 10,
		alert_sound_range_hit = 1.5,
		-- The aim assist for a controller
		aim_assist_auto_hit_chance = 0.5,
		aim_assist_max_ramp_multiplier = 0.3,
		aim_assist_ramp_decay_delay = 0.2,
		aim_assist_ramp_multiplier = 0.1,
		ut_minigun = mode,
		ut_minigun_first = first,
		ut_spread = alt and CONFIG.alt_spread or CONFIG.primary_spread,
		-- The repeating handgun's own tracer is not drawn (hooks.lua): the skin draws UT's
		ut_dropped_flow_events = DROPPED_FLOW_EVENTS,
	}

	-- The characters take the aim with the first round, hold it while the rounds come, with no animation of a shot, and leave it when
	-- the rounds stop (not when the next round follows). The rounds keep their first person event, which the skin drops, because the game
	-- only puts the recoil on a shot that plays one (WeaponUnitExtension.start_action).
	if volley then
		action.anim_event_1p = action.anim_event
		action.anim_event = nil
		action.anim_event_last_ammo = nil
		action.anim_event_3p = first and volley.start or nil
		action.anim_event_last_ammo_3p = first and volley.start or nil
		action.anim_end_event_3p = volley.finish
		action.anim_end_event_condition_func = function (unit, end_reason)
			return end_reason ~= "new_interupting_action"
		end
	end

	return action
end

-- Makes the gun on the shell of its base weapon (utils.template_shell): everything that is not the base's animations, models and sounds
-- is set here, and what the two copies set differently is in VARIANTS
local function apply_gun(template)
	local base = utils.template_shell(template)
	local variant = VARIANT_OF[template.name]

	-- The chart of the item's stats, from 0 to 7. The rounds are the normal attack.
	template.weapon_diagram = {
		light_attack = {
			[DamageTypes.ARMOR_PIERCING] = 2,
			[DamageTypes.CLEAVE] = 1,
			[DamageTypes.SPEED] = 7,
			[DamageTypes.STAGGER] = 3,
			[DamageTypes.DAMAGE] = 5,
		},
		heavy_attack = {
			[DamageTypes.ARMOR_PIERCING] = 3,
			[DamageTypes.CLEAVE] = 1,
			[DamageTypes.SPEED] = 4,
			[DamageTypes.STAGGER] = 3,
			[DamageTypes.DAMAGE] = 5,
		},
	}

	local actions = template.actions
	local base_actions = base.actions

	-- The base weapon's animations. Kruber plays the repeating handgun's rapid fire (its bullet spray, attack_shoot_fast) for every round,
	-- instead of its single shot. Saltzpyre holds the aim of the repeater pistol's alt fire (lock_target) while he fires.
	local hand = base_actions.action_one.default.weapon_action_hand
	local anims = base_actions.action_one.bullet_spray
	local aim = base_actions.action_two.default
	local volley = variant.volley and {
		start = aim.anim_event,
		finish = aim.anim_end_event,
	}

	actions.action_one = {
		default = build_shot("primary", true, hand, anims, volley),
		loop = build_shot("primary", false, hand, anims, volley),
	}
	actions.action_two = {
		default = build_shot("alt", true, hand, anims, volley),
		loop = build_shot("alt", false, hand, anims, volley),
	}
	-- The game's own wielding and reload, which every gun of the game has (the reload only comes with picked up ammo, see ammo_data).
	-- Inspecting is the base's, kept by the shell.
	actions.action_wield = table.clone(ActionTemplates.wield)
	actions.weapon_reload = table.clone(ActionTemplates.reload)

	utils.set_actions_lookup_data(actions, template.name)

	-- All the ammo is the clip, and picked up ammo is added to it, so there is no reload between shots
	template.ammo_data = {
		ammo_hand = "right",
		max_ammo = CONFIG.max_ammo,
		ammo_per_clip = CONFIG.max_ammo,
		ammo_per_reload = CONFIG.max_ammo,
		ammo_immediately_available = true,
		reload_time = 0.2,
		reload_on_ammo_pickup = true,
		play_reload_anim_on_wield_reload = true,
		should_update_anim_ammo = variant.update_anim_ammo or nil,
	}

	-- How bots use it. They hold the button, as they do for the game's staves that fire for as long as they are held, and use it against
	-- berserkers, specials and armored enemies (the repeater's). They don't shoot past an ally in the way.
	local effective_against = bit.bor(BreedCategory.Berserker, BreedCategory.Special, BreedCategory.Armored)

	template.attack_meta_data = {
		aim_at_node = "j_neck",
		can_charge_shot = false,
		effective_against = effective_against,
		effective_against_charged = 0,
		effective_against_combined = effective_against,
		fire_input = "fire_hold",
		max_range = CONFIG.bot_max_range,
		ut_minigun = true,
	}

	-- What the game's talents, traits and properties take it for: a ranged weapon of the base's kind
	template.buff_type = "RANGED"
	template.weapon_type = variant.weapon_type

	-- Dodging, and the game's crosshair and its spread (each round has UT's own spread, see ut_spread)
	template.dodge_count = variant.dodge_count
	template.buffs = {
		change_dodge_distance = {
			external_optional_multiplier = 1,
		},
		change_dodge_speed = {
			external_optional_multiplier = 1,
		},
	}
	template.crosshair_style = "default"
	template.default_spread_template = variant.spread_template
	template.spread_lerp_speed = variant.spread_lerp_speed
	template.fire_at_gaze_setting = variant.fire_at_gaze_setting or nil

	-- The aim assist for a controller
	template.aim_assist_settings = table.clone(variant.aim_assist)

	template.tooltip_compare = {
		light = {
			action_name = "action_one",
			sub_action_name = "loop",
		},
		heavy = {
			action_name = "action_two",
			sub_action_name = "loop",
		},
	}
	template.tooltip_detail = template.tooltip_compare
end

for template_name in pairs(TEMPLATE_NAMES) do
	mod.items.set_template_changes(template_name, apply_gun)
end

-- The shot. The game's own shot does the damage. This puts UT's spread on it, and tells the skin about each round. It runs on the
-- machine that owns the shot, which is the player's, or the host's for its bots.

mod.handgun_start_callbacks.minigun = function (self, new_action)
	self._ut_minigun_checked = not new_action.ut_minigun

	if not new_action.ut_minigun then
		return
	end

	-- The first round of a press starts the still barrels for its mode (can_start)
	local state = mod.minigun

	if new_action.ut_minigun_first and utils.is_local_player_unit(self.owner_unit) and state.spin <= 0 then
		state.mode = new_action.ut_minigun
		state.winding_down = false
	end

	-- UT's spread instead of the game's. The direction of the round is kept, for the tracer.
	utils.set_handgun_spread(self, new_action.ut_spread)
end

-- The surfaces (the game's surface materials) where UT's primary round doesn't make its heavy wall hit (HitEffect.GetHitEffect): dirt
-- makes DirtImpact, wood and plants pclImpactSmoke, flesh pclredsmoke. Those are left to the game's own impact. Every other surface,
-- and one UT has no type for, makes xHeavyWallHitEffect.
local NOT_HEAVY_WALL = {
	dirt = true,
	mud = true,
	sand = true,
	wood_bridge = true,
	wood_solid = true,
	wood_hollow = true,
	grass = true,
	forest_grass = true,
	hay = true,
	fruit = true,
	flesh = true,
	puke = true,
}

mod.handgun_update_callbacks.minigun = function (self)
	if self._ut_minigun_checked or self.state == "waiting_to_shoot" then
		return
	end

	self._ut_minigun_checked = true

	local owner_unit = self.owner_unit
	local action = self.current_action
	local end_position, hit_normal, hit_level, surface = utils.handgun_round_hit(self)

	mod.minigun.last_shot_time = Managers.time:time("game")
	mod.minigun.last_mode = action.ut_minigun

	mod.minigun_shot(owner_unit, action.ut_minigun, end_position, hit_normal, hit_level, hit_level and not NOT_HEAVY_WALL[surface])
end

-- What the skin is told (mod.minigun_shot_callbacks in hooks.lua), and what is sent to the other players, who see the same tracers and
-- hits from the weapon of the player's character. The hit is sent as 0 (not the level), 1 (the level) or 2 (a heavy wall of the level).
function mod.minigun_shot(owner_unit, mode, end_position, hit_normal, hit_level, heavy_wall)
	for _, callback in pairs(mod.minigun_shot_callbacks) do
		callback(owner_unit, mode, end_position, hit_normal, hit_level, heavy_wall)
	end

	mod:network_send("ut_minigun_shot", "others", Managers.state.unit_storage:go_id(owner_unit), mode == "alt" and 1 or 0,
		Vector3.x(end_position), Vector3.y(end_position), Vector3.z(end_position), Vector3.x(hit_normal), Vector3.y(hit_normal), Vector3.z(hit_normal),
		heavy_wall and 2 or hit_level and 1 or 0)
end

mod:network_register("ut_minigun_shot", function (_, owner_go_id, alt, x, y, z, normal_x, normal_y, normal_z, hit)
	local unit = Managers.state.unit_storage:unit(owner_go_id)

	if not unit or not Unit.alive(unit) then
		return
	end

	for _, callback in pairs(mod.minigun_shot_callbacks) do
		callback(unit, alt == 1 and "alt" or "primary", Vector3(x, y, z), Vector3(normal_x, normal_y, normal_z), hit >= 1, hit == 2)
	end
end)

-- The barrels, like MinigunFire's Idle, WindUp, FireLoop and WindDown states. When they are still, a held button picks the mode, and they
-- speed up at its rate while its button stays held. Once it is let go they slow down at the same rate until they stop, whatever is held
-- then: only stopped barrels can wind up again, for either mode. mod.minigun.spin (0 to 1 of the mode's speed), mode and winding_down
-- are for the skin and for when a round can start (can_start).
local function stop_barrels(state)
	state.spin = 0
	state.mode = nil
	state.winding_down = false
end

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	local state = mod.minigun
	local player = Managers.player and Managers.player:local_player_safe()
	local unit = player and player.player_unit

	if not unit or not Unit.alive(unit) or not TEMPLATE_NAMES[utils.wielded_template_name(unit)] then
		stop_barrels(state)
		state.held.primary = false
		state.held.alt = false

		return
	end

	local input_extension = ScriptUnit.extension(unit, "input_system")
	local has_ammo = (utils.local_ranged_ammo() or 0) > 0

	state.held.primary = has_ammo and input_extension:get("action_one_hold") or false
	state.held.alt = has_ammo and input_extension:get("action_two_hold") or false

	if state.spin <= 0 then
		stop_barrels(state)

		-- (the mode of a round that has started is set by it, see handgun_start_callbacks)
		state.mode = state.held.primary and "primary" or state.held.alt and "alt" or nil
	end

	if state.mode then
		local wind_up = state.mode == "alt" and CONFIG.alt_wind_up or CONFIG.primary_wind_up

		if state.held[state.mode] and not state.winding_down then
			state.spin = math.min(1, state.spin + dt / wind_up)
		else
			state.winding_down = true
			state.spin = math.max(0, state.spin - dt / wind_up)
		end
	end

	state.turns_per_second = (state.mode == "alt" and CONFIG.alt_barrel_turns or CONFIG.primary_barrel_turns) * state.spin
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	stop_barrels(mod.minigun)
end
