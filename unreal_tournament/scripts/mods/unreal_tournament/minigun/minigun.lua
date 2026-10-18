local mod = get_mod("unreal_tournament")

-- Minigun: a copy of a repeating gun with its fire modes replaced, the same way the Lightning Gun is a copy of the handgun. The numbers
-- come from UT2004 (XWeapons/Minigun, MinigunFire and MinigunAltFire).
--   Left button: the barrels spin up and the gun fires 15 rounds a second, with a wide spread, for as long as the button is held.
--   Right button: the same at 5 rounds a second, for twice the damage and a tight spread.
-- The two buttons do not fire at once. The skin (skin.lua) draws all of it. This file only sets what it does to the game.

local utils = mod.utils
local register_damage_profile = utils.register_damage_profile
local make_flat = utils.make_flat
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for

local DESCRIPTION = "The Schultz-Metzger T23-A 23mm rotary cannon is capable of firing both high-velocity caseless ammunition and cased rounds. With an unloaded weight of only 8 kilograms, the T23 is portable and maneuverable, easily worn across the back when employing the optional carrying strap."

-- The items. Kruber's careers have a repeating gun, and Saltzpyre's a repeater pistol, and they are separate templates.
local VARIANTS = {
	{
		base_item = "es_repeating_handgun",
		deus_copy = "deus_es_repeating_handgun",
		id = "minigun",
		key = "ut_minigun",
		template = "ut_minigun_template",
	},
	{
		base_item = "wh_repeating_pistols",
		deus_copy = "deus_wh_repeating_pistols",
		id = "minigun_wh",
		key = "ut_minigun_wh",
		template = "ut_minigun_wh_template",
		-- The characters fire from the aim of the base weapon's alt fire (see apply_gun)
		volley = true,
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

-- The templates whose characters fire from the aim of the base weapon's alt fire
local VOLLEY_TEMPLATES = {}

for _, variant in ipairs(VARIANTS) do
	TEMPLATE_NAMES[mod.items.weapons[variant.id].template] = true
	VOLLEY_TEMPLATES[variant.template] = variant.volley
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
	-- armor. UT has no armor. Small rounds are poor against it.
	armor_attack = {1, 0.5, 1, 1, 1, 0.3},
	armor_impact = {1, 1, 1, 1, 1, 0.5},
	-- MinigunFire.Spread and MinigunAltFire.Spread: each round is off the aim by a random share of this much of the aim's length
	primary_spread = 0.08,
	alt_spread = 0.03,
	-- How far a bot shoots from, in meters
	bot_max_range = 25,
	-- The view's kick of a round. UT shakes the view a little (ShakeRotMag 50 in every axis) instead of climbing.
	recoil_climb = 0.12,
	-- A held button repeats the shot. The shot lasts this much longer than the time to the next round, because a held button is only
	-- read while a shot is still running.
	chain_margin = 0.05,
}

-- Damage profiles
-- A round stops at the first enemy it hits, as UT's trace does. A round on the head has the game's usual bonus (shot_repeating's), as
-- this game's guns all do, where UT gives one only to its sniper weapons.

local function set_armor_modifiers(profile)
	utils.set_armor_modifiers(profile, CONFIG.armor_attack, CONFIG.armor_impact)
end

local function bullet_profile(profile, damage)
	make_flat(profile, attack_power_for(damage), impact_power_for(damage), "shot_shotgun")

	profile.cleave_distribution = {
		attack = 0.01,
		impact = 0.01,
	}
	set_armor_modifiers(profile)
end

register_damage_profile("ut_minigun_bullet", "shot_repeating", function (profile)
	bullet_profile(profile, CONFIG.primary_damage)
end)
register_damage_profile("ut_minigun_alt_bullet", "shot_repeating", function (profile)
	bullet_profile(profile, CONFIG.alt_damage)
end)

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

-- Builds a round of the gun's. The first round has the wind up before it, and the rounds after it follow at the fire rate. The hand
-- is the base weapon's, as the game crashes on an action for a hand with no weapon.
-- spray is the base weapon's own rapid fire, if it has one: its animation is made to be played a round after another. volley is the
-- aim of the base weapon's alt fire that the rapid fire is shot from, if the characters take it: { start, finish } animations.
local function build_shot(source, mode, first, hand, spray, volley)
	local action = table.clone(source)
	local alt = mode == "alt"

	action.weapon_action_hand = hand

	if spray then
		action.anim_event = spray.anim_event
		action.anim_event_last_ammo = spray.anim_event_last_ammo
	end

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

	local interval = alt and CONFIG.alt_rate or CONFIG.primary_rate
	local wind_up = alt and CONFIG.alt_wind_up or CONFIG.primary_wind_up
	local own_action = alt and "action_two" or "action_one"
	local fire_time = first and wind_up or 0

	action.active_reload_time = nil
	action.anim_event_secondary = nil
	action.damage_profile = alt and "ut_minigun_alt_bullet" or "ut_minigun_bullet"
	action.fire_time = fire_time
	action.reload_when_out_of_ammo = false
	-- A hit on the player doesn't stop the rounds, as it doesn't in UT. Otherwise the game's hit reaction ends the round's action
	-- (CharacterStateHelper).
	action.uninterruptible = true
	-- The gun fires while its button is held, as UT's does: the game starts an action with a hold_input when that button is held, not only
	-- when it is pressed (validate_action), so the rounds start again by themselves whenever something ends them, and a round ends when
	-- the button is let go
	action.hold_input = own_action .. "_hold"
	action.condition_func = first and can_start(mode) or nil
	action.total_time = fire_time + interval + CONFIG.chain_margin
	action.total_time_secondary = nil
	action.ut_minigun = mode
	action.ut_minigun_first = first
	action.ut_spread = alt and CONFIG.alt_spread or CONFIG.primary_spread
	-- The repeating handgun's own tracer is not drawn (hooks.lua): the skin draws UT's
	action.ut_dropped_flow_events = DROPPED_FLOW_EVENTS
	-- The other button's shot can only follow once this round's time is over, so the two never fire at once (UT's fire modes are
	-- exclusive)
	action.allowed_chain_actions = fire_chain_actions(own_action, "loop", fire_time + interval)

	if action.recoil_settings then
		action.recoil_settings.climb_duration = 0.05
		action.recoil_settings.restore_duration = 0.2
		action.recoil_settings.vertical_climb = CONFIG.recoil_climb
	end

	action.enter_function = function (attacker_unit, input_extension)
		input_extension:clear_input_buffer()
	end

	return action
end

local function apply_gun(template)
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
	local attack_meta_data = template.attack_meta_data

	-- The shot comes from the game's repeating gun, whichever the template is a copy of
	local source = rawget(Weapons, "repeating_handgun_template_1").actions.action_one.default
	local hand = actions.action_one.default.weapon_action_hand
	-- Kruber plays the repeating handgun's rapid fire (its bullet spray, attack_shoot_fast) for every round, instead of its single shot.
	-- Saltzpyre holds the aim of the repeater pistol's alt fire (lock_target) while he fires.
	local spray = actions.action_one.bullet_spray
	local aim = actions.action_two.default
	local volley = VOLLEY_TEMPLATES[template.name] and {
		start = aim.anim_event,
		finish = aim.anim_end_event,
	}

	actions.action_one = {
		default = build_shot(source, "primary", true, hand, spray, volley),
		loop = build_shot(source, "primary", false, hand, spray, volley),
	}
	actions.action_two = {
		default = build_shot(source, "alt", true, hand, spray, volley),
		loop = build_shot(source, "alt", false, hand, spray, volley),
	}

	utils.set_actions_lookup_data(actions, template.name)

	-- All the ammo is the clip, and picked up ammo is added to it, so there is no reload between shots.
	template.ammo_data.max_ammo = CONFIG.max_ammo
	template.ammo_data.ammo_per_clip = CONFIG.max_ammo
	template.ammo_data.ammo_per_reload = CONFIG.max_ammo
	template.ammo_data.ammo_immediately_available = true
	template.ammo_data.reload_time = 0.2

	attack_meta_data.can_charge_shot = false
	attack_meta_data.charged_attack_action_name = nil
	-- Bots hold the button, as they do for the game's staves that fire for as long as they are held
	attack_meta_data.fire_input = "fire_hold"
	attack_meta_data.max_range = CONFIG.bot_max_range
	attack_meta_data.ut_minigun = true

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

mod.handgun_update_callbacks.minigun = function (self)
	if self._ut_minigun_checked or self.state == "waiting_to_shoot" then
		return
	end

	self._ut_minigun_checked = true

	local owner_unit = self.owner_unit
	local action = self.current_action
	local end_position, hit_normal, hit_level = utils.handgun_round_hit(self)

	mod.minigun.last_shot_time = Managers.time:time("game")
	mod.minigun.last_mode = action.ut_minigun

	mod.minigun_shot(owner_unit, action.ut_minigun, end_position, hit_normal, hit_level)
end

-- What the skin is told (mod.minigun_shot_callbacks in hooks.lua), and what is sent to the other players, who see the same tracers and
-- hits from the weapon of the player's character.
function mod.minigun_shot(owner_unit, mode, end_position, hit_normal, hit_level)
	for _, callback in pairs(mod.minigun_shot_callbacks) do
		callback(owner_unit, mode, end_position, hit_normal, hit_level)
	end

	mod:network_send("ut_minigun_shot", "others", Managers.state.unit_storage:go_id(owner_unit), mode == "alt" and 1 or 0,
		Vector3.x(end_position), Vector3.y(end_position), Vector3.z(end_position), Vector3.x(hit_normal), Vector3.y(hit_normal), Vector3.z(hit_normal),
		hit_level and 1 or 0)
end

mod:network_register("ut_minigun_shot", function (_, owner_go_id, alt, x, y, z, normal_x, normal_y, normal_z, hit_level)
	local unit = Managers.state.unit_storage:unit(owner_go_id)

	if not unit or not Unit.alive(unit) then
		return
	end

	for _, callback in pairs(mod.minigun_shot_callbacks) do
		callback(unit, alt == 1 and "alt" or "primary", Vector3(x, y, z), Vector3(normal_x, normal_y, normal_z), hit_level == 1)
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
