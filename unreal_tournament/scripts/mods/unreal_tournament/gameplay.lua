local mod = get_mod("unreal_tournament")

local stagger_types = require("scripts/utils/stagger_types")

-- Gameplay options. (The ammo pickups are in pickups.lua.)

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

			if mod:get("no_bots") then
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
		if not mod:get("no_bots") then
			return func(...)
		end

		pcall(func, ...)
	end)
end

-- Auto Restart: a level that is lost starts again, instead of going back to the keep
mod:hook(GameModeAdventure, "evaluate_end_conditions", function (func, self, ...)
	local ended, reason, reason_data = func(self, ...)

	if ended and reason == "lost" and mod:get("auto_restart") then
		return ended, "reload", reason_data
	end

	return ended, reason, reason_data
end)

-- Forgiving Disablers: a player who has been held by a disabler for DISABLE_TIME seconds is let go of. The
-- disabler is staggered, which takes its behavior away from the hold, and that frees the player. A disabler
-- that holds on gets staggered again after the same time. The host's game does this, it is where the enemies are.
local DISABLE_TIME = 2 -- seconds
local STAGGER_DURATION = 2 -- seconds
local disabled_since = {} -- the player's unit: { disabler = the unit holding them, t = since when }

local function release_player(disabler_unit, player_unit, t)
	local blackboard = BLACKBOARDS[disabler_unit]
	local breed = blackboard and blackboard.breed

	if not breed then
		return
	end

	local away = Vector3.flat(Unit.world_position(disabler_unit, 0) - Unit.world_position(player_unit, 0))
	local direction = Vector3.length(away) > 0.01 and Vector3.normalize(away) or Vector3.forward()

	-- (the big ones can only be staggered by the strongest kind)
	local stagger_type = breed.boss_staggers and stagger_types.explosion or stagger_types.heavy

	AiUtils.stagger(disabler_unit, blackboard, player_unit, direction, 1, stagger_type, STAGGER_DURATION, nil, t, 1, true, false)
end

local function update_forgiving_disablers(t)
	if not t or not mod:get("forgiving_disablers") then
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
		local disabler_unit = status_extension and status_extension:get_disabler_unit()
		local state = disabled_since[player_unit]

		if not disabler_unit then
			disabled_since[player_unit] = nil
		elseif not state or state.disabler ~= disabler_unit then
			disabled_since[player_unit] = {
				disabler = disabler_unit,
				t = t,
			}
		elseif t - state.t >= DISABLE_TIME then
			state.t = t

			release_player(disabler_unit, player_unit, t)
		end
	end
end

-- Auto Revive: a player who has been knocked down for SELF_REVIVE_TIME seconds gets back up, every time. Not
-- while something is holding them (the disabler first, see Forgiving Disablers). The host's game does this, it
-- is where the revives are decided.
local SELF_REVIVE_TIME = 3 -- seconds
local SELF_REVIVE_INVULNERABLE_TIME = 2 -- seconds of not taking damage after getting up
local SELF_REVIVE_BUFF = "ut_self_revive_invulnerability"
local knocked_down_since = {} -- the player's unit: since when

-- The protection is a buff like the one of the game's invulnerability potion, with a duration of its own. The
-- buffs go over the network by name, everyone in the game needs the mod.
BuffTemplates[SELF_REVIVE_BUFF] = {
	buffs = {
		{
			duration = SELF_REVIVE_INVULNERABLE_TIME,
			max_stacks = 1,
			name = SELF_REVIVE_BUFF,
			refresh_durations = true,
			perks = {
				require("scripts/unit_extensions/default_player_unit/buffs/settings/buff_perk_names").invulnerable,
			},
		},
	},
}

mod:dofile("scripts/mods/unreal_tournament/registration").register_network_lookup("buff_templates", SELF_REVIVE_BUFF)

local function update_self_revive(t)
	if not t or not mod:get("auto_revive") then
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
		elseif t - knocked_down_since[player_unit] >= SELF_REVIVE_TIME then
			knocked_down_since[player_unit] = nil

			StatusUtils.set_revived_network(player_unit, true, player_unit)
			CharacterStateHelper.play_animation_event(player_unit, "revive_complete")
			Managers.state.entity:system("buff_system"):add_buff(player_unit, SELF_REVIVE_BUFF, player_unit, false)
		end
	end
end

local previous_update = mod.update

mod.update = function (dt, ...)
	if previous_update then
		previous_update(dt, ...)
	end

	local t = Managers.time:time("game")

	update_forgiving_disablers(t)
	update_self_revive(t)
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(disabled_since)
	table.clear(knocked_down_since)
end
