local mod = get_mod("unreal_tournament")

-- The announcer (the Announcer setting). It plays UT2004's announcements of kills, in the voice of its male announcer (MaleAnnouncer),
-- and shows the words on the screen. The sounds are in a bank of their own (tools/asset_conversion/make_bank.py announcer).
--   Multi kills (UnrealPlayer.LogMultiKills, MultiKillMessage): a kill soon after your last one is the next kill of a multi kill. Each
--     kill in a row raises the level: Double Kill, Multi Kill, Mega Kill, Ultra Kill, Monster Kill, Ludicrous Kill, Holy Shit.
--   Killing sprees (KillingSpreeMessage): Killing Spree, Rampage, Dominating, Unstoppable, Godlike and Wicked Sick, for the player's own
--     sprees, which spree.lua counts.
--   First blood (DeathMatch.ScoreKill, FirstBloodMessage): announced when you kill the first enemy to die in a level.
--   Head shots (DamTypeSniperHeadShot, SpecialKillMessage): announced for a kill with a ranged shot to the head.
--   Call outs of a number of kills with a weapon (DamageType.IncrementKills): Head Hunter for head shots with the Lightning Gun and the
--     Sniper Rifle, Flak Monkey for kills with the Flak Cannon's chunks, and Combo Whore for kills with a shock combo. The call out comes a
--     moment after the kill that reaches the number.

local spree = mod.spree

local CONFIG = {
	-- UnrealPlayer.LogMultiKills: a kill counts as the next kill of a multi kill if it comes within this long after the last one. UT
	-- uses 4 seconds, but a horde in this game dies faster than players do.
	window = 1.5, -- seconds
	-- MultiKillMessage, by the level of the multi kill (level 1 is the second kill). Each entry has a sound and a text. The last entry
	-- is used for every level after it.
	multi_kills = {
		{ event = "ut_announcer_double_kill", text = "Double Kill!" },
		{ event = "ut_announcer_multi_kill", text = "Multi Kill!" },
		{ event = "ut_announcer_mega_kill", text = "Mega Kill!!" },
		{ event = "ut_announcer_ultra_kill", text = "ULTRA KILL!!" },
		{ event = "ut_announcer_monster_kill", text = "M O N S T E R  K I L L !!!" },
		{ event = "ut_announcer_ludicrous_kill", text = "L U D I C R O U S !!!" },
		{ event = "ut_announcer_holy_shit", text = "H O L Y  S H I T !" },
	},
	-- KillingSpreeMessage, by the level of the spree (spree.lua), with its SelfSpreeNote, the player's own text
	sprees = {
		{ event = "ut_announcer_killing_spree", text = "Killing Spree!" },
		{ event = "ut_announcer_rampage", text = "Rampage!" },
		{ event = "ut_announcer_dominating", text = "Dominating!" },
		{ event = "ut_announcer_unstoppable", text = "Unstoppable!" },
		{ event = "ut_announcer_godlike", text = "GODLIKE!" },
		{ event = "ut_announcer_wicked_sick", text = "WICKED SICK!" },
	},
	-- FirstBloodMessage shows "<name> drew first blood!"
	first_blood = { event = "ut_announcer_first_blood", text = "drew first blood!" },
	head_shot = { event = "ut_announcer_headshot", text = "Head Shot!!" },
	-- The attack types that the game gives the shots of a ranged weapon. A hit with one of them is a ranged hit.
	ranged_attack_types = {
		instant_projectile = true,
		heavy_instant_projectile = true,
		projectile = true,
	},
	-- The call outs for a number of kills. UT's DamageTypes call ClientDelayedAnnouncementNamed at 15 kills, a moment after the kill.
	-- The number is multiplied by this. The count starts again when an enemy hurts the player, as a spree does (spree.lua).
	call_out_multiplier = 3,
	call_out_delay = 1.5, -- seconds
	call_outs = {
		head_hunter = { event = "ut_announcer_headhunter", kills = 15 },
		flak_monkey = { event = "ut_announcer_flak_monkey", kills = 15 },
		combo_whore = { event = "ut_announcer_combo_whore", kills = 15 },
	},
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
	-- PlayerController.PlayRewardAnnouncement: an announcement that is not forced is not played if one was played in the last second
	unforced_gap = 1, -- seconds
	-- The words on the screen (LocalMessage). Each message has where it is on the screen (PosY, from the top), how long it lasts
	-- (Lifetime), how it fades out, and its color. MultiKillMessage, SpecialKillMessage and FirstBloodMessage are red. CriticalEventPlus,
	-- which the sprees use, is white. The size is one of the FontSize values, in pixels at a height of 1080.
	messages = {
		multi_kill = { y = 0.242, color = { 255, 0, 0 } },
		head_shot = { y = 0.14, color = { 255, 0, 0 } },
		critical = { y = 0.83, color = { 255, 255, 255 } },
	},
	text_life = 3, -- seconds
	text_fade = 1, -- seconds, at the end of its life
	text_shadow = 2, -- pixels of shadow, to make the text readable
	font_material = "materials/fonts/gw_head",
	font_name = "gw_head",
	font_sizes = { 40, 52, 66, 84 },
}

local multi_kill_level = 0 -- UnrealPlayer.MultiKillLevel
local last_kill_time = -math.huge
local call_out_kills = {} -- how many kills each call out has counted, by name
local first_blood_taken = false
local last_sound_time = -math.huge
local playing_id -- the id of the announcement that is playing
local delayed = {} -- announcements waiting to play, each { time = when, event = ... }
local messages = {} -- the words on the screen, by place name, each { text, size, color, time }

local is_counted = spree.is_counted
local killer_of = spree.killer_of

local function play(event, forced)
	local now = Managers.time:time("game")

	if not forced and now - last_sound_time < CONFIG.unforced_gap then
		return
	end

	last_sound_time = now

	local wwise_world = Managers.world:wwise_world(Managers.world:world("level_world"))

	-- The announcement that is playing is cut off by the next one, as a forced reward announcement is in UT.
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

-- Returns the font size index for a multi kill level, as MultiKillMessage.GetFontSize does.
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

-- The player's own spree reaching a level (spree.lua)
spree.callbacks.announcer = function (player_unit, level)
	local local_player = Managers.player:local_player()
	local announcement = CONFIG.sprees[level]

	if not announcement or not mod:get("announcer") or not local_player or player_unit ~= local_player.player_unit then
		return
	end

	-- In KillingSpreeMessage the player's own message is size 2.
	show("critical", announcement.text, 3)
	play(announcement.event, true)
end

-- Counts a kill for a call out (DamageType.IncrementKills). The call out comes a moment after the kill that reaches the number.
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
end

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


mod.kill_callbacks.announcer = function (victim_unit, damage_data)
	if not mod:get("announcer") then
		return
	end

	local killer = killer_of(victim_unit)

	if not killer then
		return
	end

	local is_local = killer == Managers.player:local_player()

	-- The first enemy that dies in the level counts as first blood, whoever kills it.
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

	-- The game's own statistics recognize a head shot by the hit zone of the shot that killed.
	local is_head_shot = damage_data[DamageDataIndex.HIT_ZONE] == "head" and is_ranged_hit(damage_data)

	if is_head_shot then
		announce_head_shot()
	end

	if is_head_shot and is_killed_by(CONFIG.head_hunter_weapons, damage_data) then
		count_call_out("head_hunter", 1)
	end

	if is_killed_by(CONFIG.flak_monkey_weapons, damage_data) and damage_data[DamageDataIndex.DAMAGE_TYPE] == CONFIG.flak_chunk_damage_type then
		count_call_out("flak_monkey", 1)
	end
end

-- Counts the kills of a shock combo. The Shock Rifle reports which enemies the combo killed, and the host, which applies the damage,
-- knows. The host tells the player whose combo it was, if that is not the host itself.
mod.shock_combo_callbacks.announcer = function (attacker_unit, killed_units)
	local kills = 0

	for _, unit in ipairs(killed_units) do
		if is_counted(unit) then
			kills = kills + 1
		end
	end

	if kills == 0 then
		return
	end

	local attacker = Managers.player:owner(attacker_unit)

	-- The setting belongs to each player, so only the player whose combo it was can have it on.
	if attacker == Managers.player:local_player() then
		if mod:get("announcer") then
			count_call_out("combo_whore", kills)
		end
	elseif attacker and not attacker.bot_player then
		mod:network_send("ut_combo_kills", attacker.peer_id, kills)
	end
end

mod:network_register("ut_combo_kills", function (_, kills)
	if mod:get("announcer") then
		count_call_out("combo_whore", kills)
	end
end)

-- An enemy hurting the player starts the count of the call outs again, as it ends a spree (spree.lua). The player's own weapons (and
-- overcharge) and their allies don't. The one who hurts is the unit that did the damage, and an enemy is a unit with a breed that is not
-- a player's.
mod.player_damage_callbacks.announcer = function (health_extension, attacker_unit, damage_amount, source_attacker_unit)
	if next(call_out_kills) == nil or damage_amount <= 0 or not attacker_unit then
		return
	end

	local local_player = Managers.player:local_player()

	if not local_player or health_extension.unit ~= local_player.player_unit then
		return
	end

	local source_unit = AiUtils.get_actual_attacker_unit(source_attacker_unit or attacker_unit)
	local breed = Unit.alive(source_unit) and Unit.get_data(source_unit, "breed")

	if breed and not breed.is_player then
		table.clear(call_out_kills)
	end
end

-- Plays the announcements that were delayed, when their time comes.
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

-- Draws the words every frame. The game's own user interface draws them, the way it draws its debug texts.
mod.ingame_ui_post_update_callbacks.announcer = function (self)
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
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	multi_kill_level = 0
	last_kill_time = -math.huge
	first_blood_taken = false
	last_sound_time = -math.huge
	playing_id = nil

	table.clear(call_out_kills)
	table.clear(delayed)
	table.clear(messages)
end
