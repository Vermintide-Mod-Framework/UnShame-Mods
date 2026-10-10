local mod = get_mod("unreal_tournament")

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")

-- Gameplay options
local CONFIG = {
	-- More Ammo Pickups: how many times as many ammo pickups a level gets
	ammo_multiplier = 8,
	-- Forgiving Disablers: a player who has been held by a disabler for disable_time seconds is let go of, the disabler is
	-- staggered for stagger_duration
	disable_time = 2, -- seconds
	stagger_duration = 2, -- seconds
	-- Auto Revive: a player who has been knocked down for self_revive_time seconds gets up, and can't be hurt for
	-- self_revive_invulnerable_time after
	self_revive_time = 3, -- seconds
	self_revive_invulnerable_time = 2, -- seconds
}

-- If an option is on: its own checkbox, and the Gameplay checkbox above all of them
local function is_option_on(setting_id)
	return mod:get("gameplay") and mod:get(setting_id)
end

-- No Bots: the game modes have a flag that says there are no bots, and clear the ones there are when it is
-- set. It is set for the duration of the call that handles the bots.
for _, game_mode_name in ipairs({
	"GameModeAdventure",
	"GameModeDeus",
	"GameModeWeave",
}) do
	local game_mode = rawget(_G, game_mode_name)

	if game_mode then
		mod:hook(game_mode, "_handle_bots", function (func, self, ...)
			local bots_disabled = script_data.ai_bots_disabled

			if is_option_on("no_bots") then
				script_data.ai_bots_disabled = true
			end

			func(self, ...)

			script_data.ai_bots_disabled = bots_disabled
		end)
	end
end

-- Without bots the game can fail to find the places to put the players at the start of a level
local adventure_spawning = rawget(_G, "AdventureSpawning")

if adventure_spawning then
	mod:hook(adventure_spawning, "force_update_spawn_positions", function (func, ...)
		if not is_option_on("no_bots") then
			return func(...)
		end

		pcall(func, ...)
	end)
end

-- No Friendly Fire: the damage a player does to an ally (not to themselves) is dropped where it is handed to the game,
-- on the machine of whoever deals it and on the host that applies it. The damage to a player goes through
-- add_damage_network_player, the damage to anything else (and damage over time) through add_damage_network.
local function is_friendly_fire(attacker_unit, target_unit)
	if not is_option_on("no_friendly_fire") or not attacker_unit or attacker_unit == target_unit then
		return false
	end

	local breed = Unit.alive(attacker_unit) and Unit.get_data(attacker_unit, "breed")

	return breed and breed.is_player and Managers.state.side:is_ally(attacker_unit, target_unit)
end

mod:hook(DamageUtils, "add_damage_network", function (func, attacked_unit, attacker_unit, ...)
	if is_friendly_fire(attacker_unit, attacked_unit) then
		return 0
	end

	return func(attacked_unit, attacker_unit, ...)
end)

mod:hook(DamageUtils, "add_damage_network_player", function (func, damage_profile, target_index, power_level, hit_unit, attacker_unit, ...)
	if is_friendly_fire(attacker_unit, hit_unit) then
		return 0
	end

	return func(damage_profile, target_index, power_level, hit_unit, attacker_unit, ...)
end)

-- Auto Restart: a level that is lost starts again, instead of going back to the keep
mod:hook(GameModeAdventure, "evaluate_end_conditions", function (func, self, ...)
	local ended, reason, reason_data = func(self, ...)

	if ended and reason == "lost" and is_option_on("auto_restart") then
		return ended, "reload", reason_data
	end

	return ended, reason, reason_data
end)

-- More Ammo Pickups: the game works out how many pickups of each kind a level gets (its settings for the
-- difficulty, with the multipliers of the mutators that are on), and this scales the ammo among them. The
-- pickups are still put where the level has places for them, so a level with few places can't get as many as
-- the setting says. Only the host's game decides what a level gets.
local function scale(amount, multiplier)
	return math.ceil(amount * multiplier)
end

mod:hook(MutatorHandler, "pickup_settings_updated_settings", function (func, self, pickup_settings)
	local updated_settings = func(self, pickup_settings)

	if not updated_settings or not is_option_on("more_ammo_pickups") then
		return updated_settings
	end

	local multiplier = CONFIG.ammo_multiplier

	-- (what the game gives back is a copy, it is changed in place)
	local ammo = updated_settings.ammo

	if type(ammo) == "table" then
		for pickup_name, amount in pairs(ammo) do
			ammo[pickup_name] = scale(amount, multiplier)
		end
	elseif type(ammo) == "number" then
		updated_settings.ammo = scale(ammo, multiplier)
	end

	return updated_settings
end)

-- Forgiving Disablers: a player who has been held by a disabler for disable_time seconds is let go of. The
-- disabler is staggered, which takes its behavior away from the hold, and that frees the player. It is
-- staggered once for a hold: one that holds on after it isn't staggered again (that would only keep it stunned). The
-- host's game does this, it is where the enemies are.
local disabled_since = {} -- the player's unit: { disabler = the unit holding them, t = since when, released = it was staggered }

local function update_forgiving_disablers(t)
	if not t or not is_option_on("forgiving_disablers") then
		table.clear(disabled_since)

		return
	end

	local network_manager = Managers.state.network
	local side_manager = Managers.state.side
	local side = network_manager and network_manager.is_server and side_manager and side_manager:get_side_from_name("heroes")

	if not side then
		return
	end

	for _, player_unit in ipairs(side.PLAYER_AND_BOT_UNITS) do
		local status_extension = Unit.alive(player_unit) and ScriptUnit.has_extension(player_unit, "status_system")
		local disabler_unit = status_extension and utils.get_disabler(status_extension)
		local state = disabled_since[player_unit]

		if not disabler_unit then
			disabled_since[player_unit] = nil
		elseif not state or state.disabler ~= disabler_unit then
			disabled_since[player_unit] = {
				disabler = disabler_unit,
				t = t,
			}
		elseif not state.released and t - state.t >= CONFIG.disable_time then
			state.released = true

			utils.release_from_disabler(disabler_unit, player_unit, t, CONFIG.stagger_duration)
		end
	end
end

-- Auto Revive: a player who has been knocked down for self_revive_time seconds gets back up, every time. Not
-- while something is holding them (the disabler first, see Forgiving Disablers). The host's game does this, it
-- is where the revives are decided.
local SELF_REVIVE_BUFF = "ut_self_revive_invulnerability"
local knocked_down_since = {} -- the player's unit: since when

-- The protection is a buff like the one of the game's invulnerability potion, with a duration of its own. The
-- buffs go over the network by name, everyone in the game needs the mod.
BuffTemplates[SELF_REVIVE_BUFF] = {
	buffs = {
		{
			duration = CONFIG.self_revive_invulnerable_time,
			max_stacks = 1,
			name = SELF_REVIVE_BUFF,
			refresh_durations = true,
			perks = {
				require("scripts/unit_extensions/default_player_unit/buffs/settings/buff_perk_names").invulnerable,
			},
		},
	},
}

utils.register_network_lookup("buff_templates", SELF_REVIVE_BUFF)

local function update_self_revive(t)
	if not t or not is_option_on("auto_revive") then
		table.clear(knocked_down_since)

		return
	end

	local network_manager = Managers.state.network
	local side_manager = Managers.state.side
	local side = network_manager and network_manager.is_server and side_manager and side_manager:get_side_from_name("heroes")

	if not side then
		return
	end

	for _, player_unit in ipairs(side.PLAYER_AND_BOT_UNITS) do
		local player = Managers.player:owner(player_unit)
		local status_extension = Unit.alive(player_unit) and HEALTH_ALIVE[player_unit] and player and not player.bot_player and ScriptUnit.has_extension(player_unit, "status_system")
		local can_get_up = status_extension and status_extension:is_knocked_down() and not status_extension:is_disabled_by_pact_sworn()

		if not can_get_up then
			knocked_down_since[player_unit] = nil
		elseif not knocked_down_since[player_unit] then
			knocked_down_since[player_unit] = t
		elseif t - knocked_down_since[player_unit] >= CONFIG.self_revive_time then
			knocked_down_since[player_unit] = nil

			StatusUtils.set_revived_network(player_unit, true, player_unit)
			CharacterStateHelper.play_animation_event(player_unit, "revive_complete")
			Managers.state.entity:system("buff_system"):add_buff(player_unit, SELF_REVIVE_BUFF, player_unit, false)
		end
	end
end

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	local t = Managers.time:time("game")

	update_forgiving_disablers(t)
	update_self_revive(t)
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(disabled_since)
	table.clear(knocked_down_since)
end

-- Unlock Keep: the keep's levels ask the game what the account has finished (the flow scripts call these functions, by name),
-- and what is locked on a new account is open when they are told it is all done. Only what the keep is told, nothing is saved.
-- Each is a function the flow scripts call that returns a table of values; what the mod answers is what a finished account
-- gives. The hardest difficulty is 5 for a level, and a wave count that nothing reaches is as many waves as can be asked for.
local KEEP_UNLOCKS = {
	flow_callback_check_progression_unlocked = function ()
		return {
			is_locked = false,
			is_unlocked = true,
		}
	end,
	flow_callback_get_completed_game_difficulty = function ()
		return {
			completed_difficulty = 5,
		}
	end,
	flow_callback_get_completed_drachenfels_difficulty = function ()
		return {
			completed_difficulty = 5,
		}
	end,
	flow_callback_get_completed_dwarf_levels_difficulty = function ()
		return {
			completed_difficulty = 5,
		}
	end,
	flow_callback_get_completed_survival_waves = function ()
		return {
			dlc_survival_magnus = 99,
			dlc_survival_ruins = 99,
		}
	end,
	-- The queries of the leader of the party, the same kind (their value is the answer): how many acts are done, the difficulty of
	-- the levels and of the bosses (the rank of the hardest difficulty), the level of the hero, what has been crafted, the
	-- achievements. The ownership of the game's DLCs is not touched: what is owned is owned.
	flow_query_leader_num_acts_completed = function ()
		return {
			value = table.size(GameActs),
		}
	end,
	flow_query_leader_completed_difficulty = function ()
		return {
			value = 5,
		}
	end,
	flow_query_leader_completed_dlc_difficulty = function ()
		return {
			value = 5,
		}
	end,
	flow_query_leader_completed_all_dlc_levels = function ()
		return {
			value = true,
		}
	end,
	flow_query_leader_completed_exalted_champion_difficulty = function ()
		return {
			value = 8,
		}
	end,
	flow_query_leader_completed_exalted_sorcerer_difficulty = function ()
		return {
			value = 8,
		}
	end,
	flow_query_leader_completed_grey_seer_difficulty = function ()
		return {
			value = 8,
		}
	end,
	flow_query_leader_completed_storm_vermin_warlord_difficulty = function ()
		return {
			value = 8,
		}
	end,
	flow_query_leader_hero_level = function ()
		return {
			value = 30,
		}
	end,
	flow_query_leader_num_crafted_items = function ()
		return {
			value = 99,
		}
	end,
	-- The persistent statistics that a level's flow asks for by name (the levels completed, say: the training grounds' way out is
	-- open once the tutorial is done): a number that is more than any of them is, whatever the name is
	flow_query_leader_get_persistant_stat = function (params)
		mod:echo("DEBUG unlock keep: stat asked %s", tostring(params and params.stat_name))

		return {
			value = 99,
		}
	end,
	flow_query_local_player_get_persistant_stat = function (params)
		mod:echo("DEBUG unlock keep: stat asked %s", tostring(params and params.stat_name))

		return {
			value = 99,
		}
	end,
	flow_query_leader_achievement_completed = function ()
		return {
			value = true,
		}
	end,
	flow_query_local_player_achievement_completed = function ()
		return {
			value = true,
		}
	end,
}

local reported = {}

for name, unlocked in pairs(KEEP_UNLOCKS) do
	if rawget(_G, name) then
		mod:hook(_G, name, function (func, ...)
			if is_option_on("unlock_keep") then
				if not reported[name] then
					reported[name] = true

					mod:echo("DEBUG unlock keep: %s was asked", name)
				end

				return unlocked(...)
			end

			return func(...)
		end)
	end
end

-- (the last level played is shown in the keep as won: the level it was is the game's)
if rawget(_G, "flow_callback_get_last_level_played") then
	mod:hook(_G, "flow_callback_get_last_level_played", function (func, ...)
		local result = func(...)

		if is_option_on("unlock_keep") then
			result.won = true
		end

		return result
	end)
end
