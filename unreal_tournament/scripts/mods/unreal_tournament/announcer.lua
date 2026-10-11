local mod = get_mod("unreal_tournament")

-- Announcer (the Announcer setting): UT2004's announcements of kills, with the voice of its male announcer (MaleAnnouncer) and the words on the
-- screen. The sounds are in a bank of their own (tools/asset_conversion/make_bank.py announcer).
--   Multi kills (UnrealPlayer.LogMultiKills, MultiKillMessage): a kill of yours soon after your last one is the next one of a multi kill, and each
--     one in a row raises its level: Double Kill, Multi Kill, Mega Kill, Ultra Kill, Monster Kill, Ludicrous Kill, Holy Shit.
--   Killing sprees (DeathMatch.NotifySpree, KillingSpreeMessage): kills in a row without being hurt by an enemy: Killing Spree, Rampage,
--     Dominating, Unstoppable, Godlike, Wicked Sick. What hurts you is an enemy's damage, not your own weapons, overcharge or your allies'.
--   First blood (DeathMatch.ScoreKill, FirstBloodMessage): the first enemy to die in a level, if it was you who killed it.
--   Head shots (DamTypeSniperHeadShot, SpecialKillMessage): a kill with a ranged shot to the head.
--   Call outs of a number of kills with a weapon (DamageType.IncrementKills): Head Hunter for head shots, Flak Monkey for kills with the Flak
--     Cannon, Combo Whore for kills with a shock combo, a moment after the kill that makes the number.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")

local CONFIG = {
	-- UnrealPlayer.LogMultiKills: a kill counts as the next one of a multi kill if it comes this soon after the last one (UT has 4
	-- seconds, a horde of this game dies faster than players do)
	window = 1.5, -- seconds
	-- What is not an enemy for it (a player is the kill of UT: the target dummies of this game are not one)
	ignored_races = {
		dummy = true,
	},
	-- MultiKillMessage, by the level of the multi kill (1 is the second kill): its sound and its text; the last one is every level after it
	multi_kills = {
		{ event = "ut_announcer_double_kill", text = "Double Kill!" },
		{ event = "ut_announcer_multi_kill", text = "Multi Kill!" },
		{ event = "ut_announcer_mega_kill", text = "Mega Kill!!" },
		{ event = "ut_announcer_ultra_kill", text = "ULTRA KILL!!" },
		{ event = "ut_announcer_monster_kill", text = "M O N S T E R  K I L L !!!" },
		{ event = "ut_announcer_ludicrous_kill", text = "L U D I C R O U S !!!" },
		{ event = "ut_announcer_holy_shit", text = "H O L Y  S H I T !" },
	},
	-- KillingSpreeMessage, by the kills of the spree that UT makes it for, times this much (a horde is killed faster than players are)
	spree_multiplier = 3,
	sprees = {
		{ kills = 5, event = "ut_announcer_killing_spree", text = "Killing Spree!" },
		{ kills = 10, event = "ut_announcer_rampage", text = "Rampage!" },
		{ kills = 15, event = "ut_announcer_dominating", text = "Dominating!" },
		{ kills = 20, event = "ut_announcer_unstoppable", text = "Unstoppable!" },
		{ kills = 25, event = "ut_announcer_godlike", text = "GODLIKE!" },
		{ kills = 30, event = "ut_announcer_wicked_sick", text = "WICKED SICK!" },
	},
	-- (FirstBloodMessage: "<name> drew first blood!")
	first_blood = { event = "ut_announcer_first_blood", text = "drew first blood!" },
	head_shot = { event = "ut_announcer_headshot", text = "Head Shot!!" },
	-- (what is a ranged hit: the types of attack the game tells the shots of a ranged weapon by)
	ranged_attack_types = {
		instant_projectile = true,
		heavy_instant_projectile = true,
		projectile = true,
	},
	-- The call outs of a number of kills (the DamageTypes call ClientDelayedAnnouncementNamed at 15 of them, a moment later), times this
	-- much: they start again when an enemy hurts the player, as a spree does
	call_out_multiplier = 3,
	call_out_delay = 1.5, -- seconds
	call_outs = {
		head_hunter = { event = "ut_announcer_headhunter", kills = 15 },
		flak_monkey = { event = "ut_announcer_flak_monkey", kills = 15 },
		combo_whore = { event = "ut_announcer_combo_whore", kills = 15 },
	},
	-- The weapons of the call outs: what the item that killed has as its template (the setting of the weapon must be on, or it is the
	-- game's own weapon that has it)
	flak_cannon = { setting = "flak_cannon", template = "blunderbuss_template_1" },
	shock_rifle = { setting = "shock_rifle", template = "staff_blast_beam_template_1" },
	-- PlayerController.PlayRewardAnnouncement: an announcement that is not forced is not played if one has been played in the last second
	unforced_gap = 1, -- seconds
	-- The words (LocalMessage): where they are on the screen (PosY of each message, from the top), how long they last (Lifetime) and how they
	-- fade out, and their colors (MultiKillMessage and SpecialKillMessage are red, CriticalEventPlus, which the sprees are, is white and
	-- FirstBloodMessage is red). The size is one of those of FontSize, in pixels at 1080 high
	messages = {
		multi_kill = { y = 0.242, color = { 255, 0, 0 } },
		head_shot = { y = 0.1, color = { 255, 0, 0 } },
		critical = { y = 0.83, color = { 255, 255, 255 } },
	},
	text_life = 3, -- seconds
	text_fade = 1, -- seconds, at the end of it
	text_shadow = 2, -- pixels, of the shadow it is read by
	font_material = "materials/fonts/gw_head",
	font_name = "gw_head",
	font_sizes = { 40, 52, 66, 84 },
}

local multi_kill_level = 0 -- UnrealPlayer.MultiKillLevel
local last_kill_time = -math.huge
local spree = 0 -- Pawn.Spree
local call_out_kills = {} -- by name: how many of the kills of each
local first_blood_taken = false
local last_sound_time = -math.huge
local playing_id -- of the announcement that is playing
local delayed = {} -- { time = when, event = ... }
local messages = {} -- by name (the places on the screen): { text, size, color, time }

-- The player whose kill the death of an enemy was: the one that last hurt it (the game's own statistics tell kills the same way)
local function killer_of(victim_unit)
	local health_extension = ScriptUnit.has_extension(victim_unit, "health_system")
	local damage_data = health_extension and health_extension.last_damage_data
	local killer = damage_data and damage_data.attacker_unique_id and Managers.player:player_from_unique_id(damage_data.attacker_unique_id)

	if not killer then
		return nil
	end

	local breed = Unit.get_data(victim_unit, "breed")

	if not breed or breed.is_player or CONFIG.ignored_races[breed.race] then
		return nil
	end

	local side_manager = Managers.state.side

	if not side_manager:is_enemy_by_side(damage_data.attacker_side, side_manager.side_by_unit[victim_unit]) then
		return nil
	end

	return killer
end

local function play(event, forced)
	local now = Managers.time:time("game")

	if not forced and now - last_sound_time < CONFIG.unforced_gap then
		return
	end

	last_sound_time = now

	local wwise_world = Managers.world:wwise_world(Managers.world:world("level_world"))

	-- (the one that is playing is cut off by the next, a forced reward announcement is)
	if playing_id then
		WwiseWorld.stop_event(wwise_world, playing_id)
	end

	playing_id = WwiseWorld.trigger_event(wwise_world, event)
end

local function show(place, text, font_size_index, color)
	local settings = CONFIG.messages[place]

	messages[place] = {
		color = color or settings.color,
		size = CONFIG.font_sizes[font_size_index],
		text = text,
		time = Managers.time:time("game"),
	}
end

-- MultiKillMessage.GetFontSize
local function multi_kill_font_size(level)
	if level < 4 then
		return 1
	elseif level == 4 then
		return 2
	elseif level == 7 then
		return 4
	end

	return 3
end

local function announce_multi_kill(level)
	local announcement = CONFIG.multi_kills[math.min(level, #CONFIG.multi_kills)]

	show("multi_kill", announcement.text, multi_kill_font_size(level))
	play(announcement.event, true)
end

local function announce_spree(kills)
	for _, level in ipairs(CONFIG.sprees) do
		if kills == level.kills * CONFIG.spree_multiplier then
			-- (KillingSpreeMessage: the player's own is the size 2)
			show("critical", level.text, 3)
			play(level.event, true)
		end
	end
end

-- A kill that counts for a call out (DamageType.IncrementKills): the call out comes a moment after the kill that makes the number
local function count_call_out(name, kills)
	local call_out = CONFIG.call_outs[name]
	local before = call_out_kills[name] or 0

	call_out_kills[name] = before + kills

	if before < call_out.kills * CONFIG.call_out_multiplier and call_out_kills[name] >= call_out.kills * CONFIG.call_out_multiplier then
		delayed[#delayed + 1] = {
			event = call_out.event,
			time = Managers.time:time("game") + CONFIG.call_out_delay,
		}
	end
end

local function announce_head_shot()
	show("head_shot", CONFIG.head_shot.text, 2)
	play(CONFIG.head_shot.event, false)
	count_call_out("head_hunter", 1)
end

-- If the shot that killed was a ranged one (how the game's own statistics tell: by the type of the attack, or the slot of the weapon when
-- it says none)
local function is_ranged_hit(damage_data)
	local attack_type = damage_data[DamageDataIndex.ATTACK_TYPE]

	if attack_type and attack_type ~= "n/a" then
		return CONFIG.ranged_attack_types[attack_type] == true
	end

	local item = rawget(ItemMasterList, damage_data[DamageDataIndex.DAMAGE_SOURCE_NAME])

	return item ~= nil and item.slot_type == "ranged"
end

-- If the item that killed is the weapon (and the weapon is the one of the mod, not the game's)
local function is_killed_by(weapon, damage_data)
	local item = rawget(ItemMasterList, damage_data[DamageDataIndex.DAMAGE_SOURCE_NAME])

	return item ~= nil and item.template == weapon.template and utils.is_weapon_enabled(weapon.setting)
end


mod:hook_safe(StatisticsUtil, "register_kill", function (victim_unit, damage_data)
	if not mod:get("announcer") then
		return
	end

	local killer = killer_of(victim_unit)

	if not killer then
		return
	end

	local is_local = killer == Managers.player:local_player()

	-- (the first enemy that dies in the level, whoever kills it)
	if not first_blood_taken then
		first_blood_taken = true

		if is_local then
			show("critical", killer:name() .. " " .. CONFIG.first_blood.text, 2, { 255, 0, 0 })
			play(CONFIG.first_blood.event, true)
		end
	end

	if not is_local then
		return
	end

	local now = Managers.time:time("game")

	if now - last_kill_time < CONFIG.window then
		multi_kill_level = multi_kill_level + 1

		announce_multi_kill(multi_kill_level)
	else
		multi_kill_level = 0
	end

	last_kill_time = now
	spree = spree + 1

	announce_spree(spree)

	-- (the zone of the shot that killed: the game's own statistics tell a head shot this way)
	if damage_data[DamageDataIndex.HIT_ZONE] == "head" and is_ranged_hit(damage_data) then
		announce_head_shot()
	end

	if is_killed_by(CONFIG.flak_cannon, damage_data) then
		count_call_out("flak_monkey", 1)
	end
end)

-- The kills of a shock combo: the Shock Rifle tells which enemies it killed (the host, which applies the damage, knows), and the host tells
-- the player whose combo it was if that is not itself
mod.shock_combo_callbacks.announcer = function (attacker_unit, killed_units)
	if #killed_units == 0 then
		return
	end

	local attacker = Managers.player:owner(attacker_unit)

	-- (the setting is each player's own: the one whose combo it was is the one who has it)
	if attacker == Managers.player:local_player() then
		if mod:get("announcer") then
			count_call_out("combo_whore", #killed_units)
		end
	elseif attacker and not attacker.bot_player then
		mod:network_send("ut_combo_kills", attacker.peer_id, #killed_units)
	end
end

mod:network_register("ut_combo_kills", function (_, kills)
	if mod:get("announcer") then
		count_call_out("combo_whore", kills)
	end
end)

-- What ends a spree, and starts the count of the call outs again: an enemy hurts the player. Their own weapons (and the overcharge) and their
-- allies' don't: the one who hurts is the unit that did it, an enemy is a unit that has a breed that is not a player's
mod:hook_safe(PlayerUnitHealthExtension, "add_damage", function (self, attacker_unit, damage_amount, _, _, _, _, _, _, source_attacker_unit)
	if (spree == 0 and next(call_out_kills) == nil) or damage_amount <= 0 or not attacker_unit then
		return
	end

	local local_player = Managers.player:local_player()

	if not local_player or self.unit ~= local_player.player_unit then
		return
	end

	local source_unit = AiUtils.get_actual_attacker_unit(source_attacker_unit or attacker_unit)
	local breed = Unit.alive(source_unit) and Unit.get_data(source_unit, "breed")

	if breed and not breed.is_player then
		spree = 0

		table.clear(call_out_kills)
	end
end)

-- The announcements that come a moment after
mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	if not delayed[1] then
		return
	end

	local now = Managers.time:time("game")

	for i = #delayed, 1, -1 do
		if now >= delayed[i].time then
			play(delayed[i].event, false)
			table.remove(delayed, i)
		end
	end
end

-- The words, every frame (the game's own user interface draws them, as it does its debug texts)
mod:hook_safe(IngameUI, "post_update", function (self)
	if not next(messages) then
		return
	end

	local now = Managers.time:time("game")
	local gui = self.ui_renderer.gui
	local width, height = Application.resolution()

	for place, message in pairs(messages) do
		local age = now - message.time

		if age >= CONFIG.text_life then
			messages[place] = nil
		else
			local size = message.size * height / 1080
			local minimum, maximum = Gui.text_extents(gui, message.text, CONFIG.font_material, size)
			local alpha = 255 * math.clamp((CONFIG.text_life - age) / CONFIG.text_fade, 0, 1)
			local position = Vector3((width - (maximum.x - minimum.x)) / 2, height * (1 - CONFIG.messages[place].y), 999)
			local shadow = CONFIG.text_shadow * height / 1080
			local red, green, blue = unpack(message.color)

			Gui.text(gui, message.text, CONFIG.font_material, size, CONFIG.font_name, position + Vector3(shadow, -shadow, -1), Color(alpha, 0, 0, 0))
			Gui.text(gui, message.text, CONFIG.font_material, size, CONFIG.font_name, position, Color(alpha, red, green, blue))
		end
	end
end)

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	multi_kill_level = 0
	last_kill_time = -math.huge
	spree = 0
	first_blood_taken = false
	last_sound_time = -math.huge
	playing_id = nil

	table.clear(call_out_kills)
	table.clear(delayed)
	table.clear(messages)
end
