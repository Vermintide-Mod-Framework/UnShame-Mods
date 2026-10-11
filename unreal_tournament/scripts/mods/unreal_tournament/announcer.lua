local mod = get_mod("unreal_tournament")

-- Announcer (the Announcer setting): UT2004's multi kill announcements. A kill of yours within 4 seconds of your last one is a multi
-- kill, and each one in a row raises its level: Double Kill, Multi Kill, Mega Kill, Ultra Kill, Monster Kill, Ludicrous Kill, Holy Shit
-- (UnrealPlayer.LogMultiKills counts them, MultiKillMessage says which sound each level plays, MaleAnnouncer is the voice). The sounds
-- are in a bank of their own (tools/asset_conversion/make_bank.py announcer).

local CONFIG = {
	-- UnrealPlayer.LogMultiKills: a kill counts as the next one of a multi kill if it comes this long after the last one
	window = 4, -- seconds
	-- What is not an enemy for it (a player is the kill of UT: the rats and the target dummies of this game are not one)
	ignored_races = {
		critter = true,
		dummy = true,
	},
	-- MultiKillMessage.KillSoundName, by the level of the multi kill (1 is the second kill): the last one is every level after it
	events = {
		"ut_announcer_double_kill",
		"ut_announcer_multi_kill",
		"ut_announcer_mega_kill",
		"ut_announcer_ultra_kill",
		"ut_announcer_monster_kill",
		"ut_announcer_ludicrous_kill",
		"ut_announcer_holy_shit",
	},
}

local level = 0 -- UnrealPlayer.MultiKillLevel
local last_kill_time = -math.huge
local playing_id -- of the announcement that is playing

local function is_enabled()
	return mod:get("announcer") and mod:get("multi_kills")
end

-- A kill of the player's own: the enemy that died was last hurt by them (the game's own statistics tell kills the same way)
local function is_local_kill(victim_unit)
	local health_extension = ScriptUnit.has_extension(victim_unit, "health_system")
	local damage_data = health_extension and health_extension.last_damage_data
	local local_player = Managers.player:local_player()

	if not damage_data or not local_player or damage_data.attacker_unique_id ~= local_player:unique_id() then
		return false
	end

	local breed = Unit.get_data(victim_unit, "breed")

	if not breed or breed.is_player or CONFIG.ignored_races[breed.race] then
		return false
	end

	local side_manager = Managers.state.side

	return side_manager:is_enemy_by_side(damage_data.attacker_side, side_manager.side_by_unit[victim_unit])
end

local function announce(multi_kill_level)
	local wwise_world = Managers.world:wwise_world(Managers.world:world("level_world"))

	-- (the one that is playing is cut off by the next, a forced reward announcement is)
	if playing_id then
		WwiseWorld.stop_event(wwise_world, playing_id)
	end

	playing_id = WwiseWorld.trigger_event(wwise_world, CONFIG.events[math.min(multi_kill_level, #CONFIG.events)])
end

mod:hook_safe(StatisticsUtil, "register_kill", function (victim_unit)
	if not is_enabled() or not is_local_kill(victim_unit) then
		return
	end

	local now = Managers.time:time("game")

	if now - last_kill_time < CONFIG.window then
		level = level + 1

		announce(level)
	else
		level = 0
	end

	last_kill_time = now
end)

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	level = 0
	last_kill_time = -math.huge
	playing_id = nil
end
