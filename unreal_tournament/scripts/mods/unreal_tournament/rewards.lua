local mod = get_mod("unreal_tournament")

-- Killing sprees (DeathMatch.NotifySpree and EndSpree, KillingSpreeMessage) and first blood (DeathMatch.ScoreKill, FirstBloodMessage).
-- A spree is a player's kills in a row without being hurt by an enemy, bots' too. Only an enemy's damage ends a spree: a player's own
-- weapons, overcharge and allies' damage do not, unless they knock the player down or kill them, which ends it as UT's suicide does.
-- First blood is the first kill of the level. The host counts them, as it sees every kill and every hit, and tells every machine, which
-- writes UT's line in the chat for everyone, as UT tells every player. They are counted whatever the announcer setting is: the
-- announcer (announcer.lua) plays the player's own, and other things can take from them.
--   mod.spree.callbacks[name] = function (player_unit, level, ender_unit): on every machine, when a player's spree reaches a level (1 is
--       Killing Spree, up to 6, Wicked Sick), or with level 0 when a spree of a level ends, hurt by ender_unit, or by no one (nil) when
--       the player was knocked down or died otherwise.
--   mod.spree.first_blood_callbacks[name] = function (player_unit): on every machine, for the first kill of the level.
--   mod.spree.is_counted(unit), mod.spree.killer_of(victim_unit): which deaths are kills, and whose (for the announcer's kills too).

local CONFIG = {
	-- These are not enemies as far as kills are concerned. In UT a player is a kill, and the target dummies and critters of this game are
	-- not.
	ignored_races = {
		critter = true,
		dummy = true,
	},
	-- The most basic enemy of each race. Its kills are not counted at all: not for a spree, nor by the announcer.
	ignored_breeds = {
		beastmen_ungor = true,
		chaos_fanatic = true,
		skaven_slave = true,
	},
	-- DeathMatch.NotifySpree: the levels come at 5, 10, 15, 20, 25 and 30 kills, times this. A horde dies faster than players do.
	kills_per_level = 5,
	levels = 6,
	multiplier = 3,
	-- KillingSpreeMessage's SpreeNote, EndSpreeNote and EndSpreeNoteTrailer
	notes = {
		"is on a killing spree!",
		"is on a rampage!",
		"is dominating!",
		"is unstoppable!",
		"is Godlike!",
		"is Wicked SICK!",
	},
	end_note = "'s killing spree ended by",
	-- (EndSelfSpree and EndFemaleSpree, and the heroes who are women)
	end_self_note = "was looking good till he killed himself!",
	end_self_note_female = "was looking good till she killed herself!",
	female_heroes = {
		bright_wizard = true,
		wood_elf = true,
	},
	-- FirstBloodMessage's FirstBloodString
	first_blood_note = "drew first blood!",
	chat_channel = 1,
}

local spree = {
	callbacks = {},
	first_blood_callbacks = {},
}

mod.spree = spree

-- Returns whether the death of a unit counts as a kill. It does if the unit is an enemy of a kind that is not ignored.
function spree.is_counted(unit)
	local breed = Unit.get_data(unit, "breed")

	return breed ~= nil and not breed.is_player and not CONFIG.ignored_races[breed.race] and not CONFIG.ignored_breeds[breed.name]
end

-- Returns the player whose kill an enemy's death was, which is the one who hurt it last. The game's own statistics decide kills the
-- same way.
function spree.killer_of(victim_unit)
	local health_extension = ScriptUnit.has_extension(victim_unit, "health_system")
	local damage_data = health_extension and health_extension.last_damage_data
	local killer = damage_data and damage_data.attacker_unique_id and Managers.player:player_from_unique_id(damage_data.attacker_unique_id)

	if not killer or not spree.is_counted(victim_unit) then
		return nil
	end

	local side_manager = Managers.state.side

	if not side_manager:is_enemy_by_side(damage_data.attacker_side, side_manager.side_by_unit[victim_unit]) then
		return nil
	end

	return killer
end

-- The kills in a row of each player's character, and whether the level has had its first blood, on the host
local kills = {}
local first_blood_taken = false

local function is_host()
	return Managers.state.network ~= nil and Managers.state.network.is_server
end

-- The name of a player's character, or of an enemy's breed
local function name_of(unit)
	local player = unit and Unit.alive(unit) and Managers.player:owner(unit)

	if player then
		return player:name()
	end

	local breed = unit and Unit.alive(unit) and Unit.get_data(unit, "breed")

	return breed and Localize(breed.name) or "?"
end

-- Writes the line, and tells the callbacks, on this machine
local function tell(player_unit, level, ender_unit)
	if not Unit.alive(player_unit) then
		return
	end

	local text

	if level > 0 then
		text = name_of(player_unit) .. " " .. CONFIG.notes[level]
	elseif ender_unit then
		text = name_of(player_unit) .. CONFIG.end_note .. " " .. name_of(ender_unit)
	else
		local player = Managers.player:owner(player_unit)
		local female = player and CONFIG.female_heroes[player:profile_display_name()]

		text = name_of(player_unit) .. " " .. (female and CONFIG.end_self_note_female or CONFIG.end_self_note)
	end

	if Managers.chat then
		Managers.chat:add_local_system_message(CONFIG.chat_channel, text, true)
	end

	for _, callback in pairs(spree.callbacks) do
		callback(player_unit, level, ender_unit)
	end
end

local function go_id(unit)
	return unit and Unit.alive(unit) and Managers.state.unit_storage:go_id(unit) or 0
end

local function announce(player_unit, level, ender_unit)
	tell(player_unit, level, ender_unit)
	mod:network_send("ut_spree", "others", go_id(player_unit), level, go_id(ender_unit))
end

mod:network_register("ut_spree", function (_, player_go_id, level, ender_go_id)
	local unit_storage = Managers.state.unit_storage
	local player_unit = unit_storage and unit_storage:unit(player_go_id)

	if player_unit then
		tell(player_unit, level, ender_go_id ~= 0 and unit_storage:unit(ender_go_id) or nil)
	end
end)

-- First blood: the line, and the callbacks, on this machine
local function tell_first_blood(player_unit)
	if not Unit.alive(player_unit) then
		return
	end

	if Managers.chat then
		Managers.chat:add_local_system_message(CONFIG.chat_channel, name_of(player_unit) .. " " .. CONFIG.first_blood_note, true)
	end

	for _, callback in pairs(spree.first_blood_callbacks) do
		callback(player_unit)
	end
end

mod:network_register("ut_first_blood", function (_, player_go_id)
	local unit_storage = Managers.state.unit_storage
	local player_unit = unit_storage and unit_storage:unit(player_go_id)

	if player_unit then
		tell_first_blood(player_unit)
	end
end)

mod.kill_callbacks.spree = function (victim_unit)
	if not is_host() then
		return
	end

	local killer = spree.killer_of(victim_unit)
	local player_unit = killer and killer.player_unit

	if not player_unit or not Unit.alive(player_unit) then
		return
	end

	-- (the first enemy that dies in the level by a player's hand, whoever's)
	if not first_blood_taken then
		first_blood_taken = true

		tell_first_blood(player_unit)
		mod:network_send("ut_first_blood", "others", go_id(player_unit))
	end

	local count = (kills[player_unit] or 0) + 1

	kills[player_unit] = count

	local step = CONFIG.kills_per_level * CONFIG.multiplier

	if count % step == 0 and count / step <= CONFIG.levels then
		announce(player_unit, count / step, nil)
	end
end

-- An enemy hurting a player ends the spree (DeathMatch.Killed: a death with a spree of a level ends it there). The one who hurts is the
-- unit that did the damage, and an enemy is a unit with a breed that is not a player's.
mod.player_damage_callbacks.spree = function (health_extension, attacker_unit, damage_amount, source_attacker_unit)
	local player_unit = health_extension.unit
	local count = kills[player_unit]

	if not count or count == 0 or damage_amount <= 0 or not attacker_unit or not is_host() then
		return
	end

	local source_unit = AiUtils.get_actual_attacker_unit(source_attacker_unit or attacker_unit)
	local breed = Unit.alive(source_unit) and Unit.get_data(source_unit, "breed")

	if not breed or breed.is_player then
		return
	end

	kills[player_unit] = nil

	if count >= CONFIG.kills_per_level * CONFIG.multiplier then
		announce(player_unit, 0, source_unit)
	end
end

-- A player who is knocked down or dies with a spree going ends it, whatever did it (an enemy's hit ends it first, above): UT's death
-- by the player's own hand (DeathMatch.EndSpree with no killer). A shorter count just starts again, as UT's does at a death.
mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	if not next(kills) or not is_host() then
		return
	end

	for player_unit, count in pairs(kills) do
		local status_extension = Unit.alive(player_unit) and ScriptUnit.has_extension(player_unit, "status_system")

		if not status_extension then
			kills[player_unit] = nil
		elseif status_extension:is_knocked_down() or status_extension:is_dead() then
			kills[player_unit] = nil

			if count >= CONFIG.kills_per_level * CONFIG.multiplier then
				announce(player_unit, 0, nil)
			end
		end
	end
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(kills)

	first_blood_taken = false
end
