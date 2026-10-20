local mod = get_mod("unreal_tournament")

-- The rewards of kills, as UT2004 gives them: first blood (DeathMatch.ScoreKill, FirstBloodMessage), multi kills (UnrealPlayer.LogMultiKills,
-- MultiKillMessage), killing sprees (DeathMatch.NotifySpree and EndSpree, KillingSpreeMessage), head shots (SpecialKillMessage) and the
-- call outs of a number of kills with a weapon (DamageType.IncrementKills). The host decides them for every player, bots too, as it sees
-- every kill and every hit, and tells every machine. They are decided whatever the announcer setting is: the announcer (announcer.lua)
-- voices the player's own, and adrenaline (adrenaline.lua) is given for them.
--   First blood is the first kill of the level. A multi kill is a kill soon after the last one. A spree is a player's kills in a row
--   without being hurt by an enemy. Only an enemy's damage ends a spree: a player's own weapons, overcharge and allies' damage do not,
--   unless they knock the player down or kill them, which ends it as UT's suicide does. Past its top level, Wicked Sick, Dominating
--   comes again every as many kills as the top level took. A call out comes at a number of kills of its kind, and at every as many more,
--   counted again after an enemy's hurt, as a spree.
-- What UT tells everyone is written in everyone's chat: a first blood, a spree and the end of one.
--   mod.rewards.callbacks[name] = function (event, player_unit, value, other_unit): on every machine, for a reward of player_unit:
--       "first_blood"; "multi_kill" with its level (1 is a double kill); "spree" with its level (1 is Killing Spree, up to 6, Wicked Sick);
--       "spree_end", hurt by other_unit, or by no one (nil) when the player was knocked down or died otherwise; "head_shot"; "call_out"
--       with its name (head_hunter, flak_monkey or combo_whore); and this game's own, which UT has none of: "special_kill" (a special or
--       a sack rat) and "boss_kill" (a monster or a lord).
--   mod.rewards.is_counted(unit), mod.rewards.killer_of(victim_unit): which deaths are kills, and whose.

local CONFIG = {
	-- These are not enemies as far as kills are concerned. In UT a player is a kill, and the target dummies and critters of this game are
	-- not.
	ignored_races = {
		critter = true,
		dummy = true,
	},
	-- The most basic enemy of each race. Its kills are not counted at all.
	ignored_breeds = {
		beastmen_ungor = true,
		chaos_fanatic = true,
		skaven_slave = true,
	},
	-- UnrealPlayer.LogMultiKills: a kill counts as the next kill of a multi kill if it comes within this long after the last one. UT
	-- uses 4 seconds, but a horde in this game dies faster than players do.
	multi_kill_window = 1.5, -- seconds
	-- DeathMatch.NotifySpree: the levels come at 5, 10, 15, 20, 25 and 30 kills, times this. A horde dies faster than players do.
	spree_kills_per_level = 5,
	spree_levels = 6,
	spree_multiplier = 3,
	-- Past the top level, which UT has no more of, Dominating comes again every time the spree goes on by as many kills as the top level
	-- took (a choice)
	spree_repeat_level = 3,
	-- The call outs: UT's DamageTypes announce them at 15 kills, times this, and here again at every as many more
	call_out_kills = 15,
	call_out_multiplier = 3,
	-- The kills that the call outs count, as UT's damage types do (the combo's are counted from the combo's kills). Head Hunter counts
	-- the head shots of UT's sniper weapons (DamTypeSniperHeadShot and DamTypeClassicHeadshot), and Flak Monkey the kills of the flak
	-- chunks, a shell's too, but not of the shell's explosion (DamTypeFlakChunk). The weapons are matched by the template of the item
	-- that killed, and the chunks by the damage type of their hit (flak_cannon.lua's ut_flak_chunk).
	head_hunter_weapons = {
		mod.items.weapons.lightning_gun.template,
		mod.items.weapons.sniper_rifle.template,
		mod.items.weapons.sniper_rifle_dr.template,
	},
	flak_monkey_weapons = {
		mod.items.weapons.flak_cannon.template,
	},
	flak_chunk_damage_type = "shot_shotgun",
	-- The attack types that the game gives the shots of a ranged weapon. A hit with one of them is a ranged hit.
	ranged_attack_types = {
		instant_projectile = true,
		heavy_instant_projectile = true,
		projectile = true,
	},
	-- The kills of these are rewards of their own: specials (breed.special) and the sack rat, and monsters and lords (breed.boss)
	special_breeds = {
		skaven_loot_rat = true,
	},
	-- KillingSpreeMessage's SpreeNote, EndSpreeNote, EndSelfSpree and EndFemaleSpree, and the heroes who are women
	spree_notes = {
		"is on a killing spree!",
		"is on a rampage!",
		"is dominating!",
		"is unstoppable!",
		"is Godlike!",
		"is Wicked SICK!",
	},
	spree_end_note = "'s killing spree ended by",
	spree_end_self_note = "was looking good till he killed himself!",
	spree_end_self_note_female = "was looking good till she killed herself!",
	female_heroes = {
		bright_wizard = true,
		wood_elf = true,
	},
	-- FirstBloodMessage's FirstBloodString
	first_blood_note = "drew first blood!",
	chat_channel = 1,
}

local EVENTS = { "first_blood", "multi_kill", "spree", "spree_end", "head_shot", "call_out", "special_kill", "boss_kill" }
local CALL_OUTS = { "head_hunter", "flak_monkey", "combo_whore" }

local rewards = {
	callbacks = {},
}

mod.rewards = rewards

-- Returns whether the death of a unit counts as a kill. It does if the unit is an enemy of a kind that is not ignored.
function rewards.is_counted(unit)
	local breed = Unit.get_data(unit, "breed")

	return breed ~= nil and not breed.is_player and not CONFIG.ignored_races[breed.race] and not CONFIG.ignored_breeds[breed.name]
end

-- Returns the player whose kill an enemy's death was, which is the one who hurt it last. The game's own statistics decide kills the
-- same way.
function rewards.killer_of(victim_unit)
	local health_extension = ScriptUnit.has_extension(victim_unit, "health_system")
	local damage_data = health_extension and health_extension.last_damage_data
	local killer = damage_data and damage_data.attacker_unique_id and Managers.player:player_from_unique_id(damage_data.attacker_unique_id)

	if not killer or not rewards.is_counted(victim_unit) then
		return nil
	end

	local side_manager = Managers.state.side

	if not side_manager:is_enemy_by_side(damage_data.attacker_side, side_manager.side_by_unit[victim_unit]) then
		return nil
	end

	return killer
end

-- On the host, for each player's character: { spree = kills in a row, multi_kill = its level, last_kill = when, call_outs = { [name] =
-- kills } }; and whether the level has had its first blood
local players = {}
local first_blood_taken = false

local function is_host()
	return Managers.state.network ~= nil and Managers.state.network.is_server
end

local function state_of(player_unit)
	local state = players[player_unit]

	if not state then
		state = { spree = 0, multi_kill = 0, last_kill = -math.huge, call_outs = {} }
		players[player_unit] = state
	end

	return state
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

-- The line in everyone's chat for a reward that UT tells everyone of, or nil
local function chat_line(event, player_unit, value, other_unit)
	local name = name_of(player_unit)

	if event == "first_blood" then
		return name .. " " .. CONFIG.first_blood_note
	elseif event == "spree" then
		return name .. " " .. CONFIG.spree_notes[value]
	elseif event == "spree_end" and other_unit then
		return name .. CONFIG.spree_end_note .. " " .. name_of(other_unit)
	elseif event == "spree_end" then
		local player = Managers.player:owner(player_unit)
		local female = player and CONFIG.female_heroes[player:profile_display_name()]

		return name .. " " .. (female and CONFIG.spree_end_self_note_female or CONFIG.spree_end_self_note)
	end
end

-- Writes the line, and tells the callbacks, on this machine
local function tell(event, player_unit, value, other_unit)
	if not Unit.alive(player_unit) then
		return
	end

	local line = chat_line(event, player_unit, value, other_unit)

	if line and Managers.chat then
		Managers.chat:add_local_system_message(CONFIG.chat_channel, line, true)
	end

	for _, callback in pairs(rewards.callbacks) do
		callback(event, player_unit, value, other_unit)
	end
end

local function go_id(unit)
	return unit and Unit.alive(unit) and Managers.state.unit_storage:go_id(unit) or 0
end

-- (the event and the call out go as their index in EVENTS and CALL_OUTS, and a missing value as 0)
local function reward(event, player_unit, value, other_unit)
	tell(event, player_unit, value, other_unit)

	local sent_value = event == "call_out" and table.index_of(CALL_OUTS, value) or value or 0

	mod:network_send("ut_reward", "others", table.index_of(EVENTS, event), go_id(player_unit), sent_value, go_id(other_unit))
end

mod:network_register("ut_reward", function (_, event_index, player_go_id, value, other_go_id)
	local unit_storage = Managers.state.unit_storage
	local player_unit = unit_storage and unit_storage:unit(player_go_id)
	local event = EVENTS[event_index]

	if not player_unit or not event then
		return
	end

	if event == "call_out" then
		value = CALL_OUTS[value]
	end

	tell(event, player_unit, value, other_go_id ~= 0 and unit_storage:unit(other_go_id) or nil)
end)

-- Returns whether the shot that killed was a ranged one. This works the way the game's own statistics do: by the type of the attack,
-- or by the slot of the weapon when the attack has no type.
local function is_ranged_hit(damage_data)
	local attack_type = damage_data[DamageDataIndex.ATTACK_TYPE]

	if attack_type and attack_type ~= "n/a" then
		return CONFIG.ranged_attack_types[attack_type] == true
	end

	local item = rawget(ItemMasterList, damage_data[DamageDataIndex.DAMAGE_SOURCE_NAME])

	return item ~= nil and item.slot_type == "ranged"
end

-- Returns whether the item that killed is one of these weapons, given by their templates.
local function is_killed_by(templates, damage_data)
	local item = rawget(ItemMasterList, damage_data[DamageDataIndex.DAMAGE_SOURCE_NAME])

	for _, template in ipairs(item and templates or {}) do
		if item.template == template then
			return true
		end
	end

	return false
end

-- Counts kills for a call out (DamageType.IncrementKills). It comes at the kill that reaches the number, and at each as many more.
local function count_call_out(player_unit, name, kills)
	local call_outs = state_of(player_unit).call_outs
	local before = call_outs[name] or 0
	local needed = CONFIG.call_out_kills * CONFIG.call_out_multiplier

	call_outs[name] = before + kills

	for _ = math.floor(before / needed) + 1, math.floor(call_outs[name] / needed) do
		reward("call_out", player_unit, name)
	end
end

mod.kill_callbacks.rewards = function (victim_unit, damage_data)
	if not is_host() then
		return
	end

	local killer = rewards.killer_of(victim_unit)
	local player_unit = killer and killer.player_unit

	if not player_unit or not Unit.alive(player_unit) then
		return
	end

	local state = state_of(player_unit)
	local now = Managers.time:time("game")

	-- (the first enemy that dies in the level by a player's hand, whoever's)
	if not first_blood_taken then
		first_blood_taken = true

		reward("first_blood", player_unit)
	end

	if now - state.last_kill < CONFIG.multi_kill_window then
		state.multi_kill = state.multi_kill + 1

		reward("multi_kill", player_unit, state.multi_kill)
	else
		state.multi_kill = 0
	end

	state.last_kill = now

	-- The game's own statistics recognize a head shot by the hit zone of the shot that killed.
	local is_head_shot = damage_data[DamageDataIndex.HIT_ZONE] == "head" and is_ranged_hit(damage_data)

	if is_head_shot then
		reward("head_shot", player_unit)
	end

	local breed = Unit.get_data(victim_unit, "breed")

	if breed.boss then
		reward("boss_kill", player_unit)
	elseif breed.special or CONFIG.special_breeds[breed.name] then
		reward("special_kill", player_unit)
	end

	state.spree = state.spree + 1

	local step = CONFIG.spree_kills_per_level * CONFIG.spree_multiplier
	local top = step * CONFIG.spree_levels

	if state.spree % step == 0 and state.spree <= top then
		reward("spree", player_unit, state.spree / step)
	elseif state.spree > top and (state.spree - top) % top == 0 then
		reward("spree", player_unit, CONFIG.spree_repeat_level)
	end

	if is_head_shot and is_killed_by(CONFIG.head_hunter_weapons, damage_data) then
		count_call_out(player_unit, "head_hunter", 1)
	end

	if is_killed_by(CONFIG.flak_monkey_weapons, damage_data) and damage_data[DamageDataIndex.DAMAGE_TYPE] == CONFIG.flak_chunk_damage_type then
		count_call_out(player_unit, "flak_monkey", 1)
	end
end

-- The kills of a shock combo, which the host knows, as it applies the damage
mod.shock_combo_callbacks.rewards = function (attacker_unit, killed_units)
	if not is_host() or not Managers.player:owner(attacker_unit) then
		return
	end

	local kills = 0

	for _, unit in ipairs(killed_units) do
		if rewards.is_counted(unit) then
			kills = kills + 1
		end
	end

	if kills > 0 then
		count_call_out(attacker_unit, "combo_whore", kills)
	end
end

-- An enemy hurting a player ends the spree (DeathMatch.Killed: a death with a spree of a level ends it there) and starts the call outs'
-- counts again. The one who hurts is the unit that did the damage, and an enemy is a unit with a breed that is not a player's.
mod.player_damage_callbacks.rewards = function (health_extension, attacker_unit, damage_amount, source_attacker_unit)
	local player_unit = health_extension.unit
	local state = players[player_unit]

	if not state or damage_amount <= 0 or not attacker_unit or not is_host() then
		return
	end

	local source_unit = AiUtils.get_actual_attacker_unit(source_attacker_unit or attacker_unit)
	local breed = Unit.alive(source_unit) and Unit.get_data(source_unit, "breed")

	if not breed or breed.is_player then
		return
	end

	local spree = state.spree

	state.spree = 0

	table.clear(state.call_outs)

	if spree >= CONFIG.spree_kills_per_level * CONFIG.spree_multiplier then
		reward("spree_end", player_unit, nil, source_unit)
	end
end

-- A player who is knocked down or dies with a spree going ends it, whatever did it (an enemy's hit ends it first, above): UT's death
-- by the player's own hand (DeathMatch.EndSpree with no killer). A shorter count just starts again, as UT's does at a death.
mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	if not next(players) or not is_host() then
		return
	end

	for player_unit, state in pairs(players) do
		local status_extension = Unit.alive(player_unit) and ScriptUnit.has_extension(player_unit, "status_system")

		if not status_extension then
			players[player_unit] = nil
		elseif state.spree > 0 and (status_extension:is_knocked_down() or status_extension:is_dead()) then
			local spree = state.spree

			state.spree = 0

			if spree >= CONFIG.spree_kills_per_level * CONFIG.spree_multiplier then
				reward("spree_end", player_unit)
			end
		end
	end
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(players)

	first_blood_taken = false
end
