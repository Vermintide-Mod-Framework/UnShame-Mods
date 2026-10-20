local mod = get_mod("unreal_tournament")

-- The announcer (the Announcer setting). It voices the player's own rewards (rewards.lua) in UT2004's male announcer (MaleAnnouncer),
-- and shows their words on the screen. The sounds are in a bank of their own (tools/asset_conversion/make_bank.py announcer).
--   Multi kills (MultiKillMessage): Double Kill, Multi Kill, Mega Kill, Ultra Kill, Monster Kill, Ludicrous Kill, Holy Shit.
--   Killing sprees (KillingSpreeMessage): Killing Spree, Rampage, Dominating, Unstoppable, Godlike and Wicked Sick.
--   First blood (FirstBloodMessage), head shots (SpecialKillMessage), and the call outs (Head Hunter, Flak Monkey and Combo Whore), which
--     come a moment after the kill that reaches their number (ClientDelayedAnnouncementNamed).
-- Others voice through it too (adrenaline): mod.announcer.play(event, forced), mod.announcer.play_later(event, delay). The setting
-- covers every line.

local CONFIG = {
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
	-- KillingSpreeMessage, by the level of the spree, with its SelfSpreeNote, the player's own text
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
	-- UT's DamageTypes call ClientDelayedAnnouncementNamed a moment after the kill
	call_out_delay = 1.5, -- seconds
	call_outs = {
		head_hunter = "ut_announcer_headhunter",
		flak_monkey = "ut_announcer_flak_monkey",
		combo_whore = "ut_announcer_combo_whore",
	},
	-- PlayerController.PlayRewardAnnouncement: an announcement that is not forced is not played if one was played in the last second
	unforced_gap = 1, -- seconds
	-- The words on the screen (LocalMessage). Each message has where it is on the screen (PosY, from the top), how long it lasts
	-- (Lifetime), how it fades out, and its color. MultiKillMessage, SpecialKillMessage and FirstBloodMessage are red. CriticalEventPlus,
	-- which the sprees use, is white. The size is one of the FontSize values, in pixels at a height of 1080.
	-- ComboMessage, a combo's name when it starts, is red at the top.
	messages = {
		multi_kill = { y = 0.242, color = { 255, 0, 0 } },
		head_shot = { y = 0.14, color = { 255, 0, 0 } },
		critical = { y = 0.83, color = { 255, 255, 255 } },
		combo = { y = 0.1, color = { 255, 0, 0 } },
	},
	text_life = 3, -- seconds
	text_fade = 1, -- seconds, at the end of its life
	text_shadow = 2, -- pixels of shadow, to make the text readable
	font_material = "materials/fonts/gw_head",
	font_name = "gw_head",
	font_sizes = { 40, 52, 66, 84 },
}

local last_sound_time = -math.huge
local playing_id -- the id of the announcement that is playing
local delayed = {} -- announcements waiting to play, each { time = when, event = ... }
local messages = {} -- the words on the screen, by place name, each { text, size, color, time }

local function play(event, forced)
	if not mod:get("announcer") then
		return
	end

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

local function play_later(event, delay)
	delayed[#delayed + 1] = {
		event = event,
		time = Managers.time:time("game") + delay,
	}
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

mod.announcer = {
	play = play,
	play_later = play_later,
	-- (a combo's name on the screen, ComboMessage at LocalMessage's FontSize 0: words, not the voice, so with the setting off too)
	combo_message = function (text)
		show("combo", text, 1)
	end,
}

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

-- The player's own rewards
mod.rewards.callbacks.announcer = function (event, player_unit, value)
	local local_player = Managers.player:local_player()

	if not mod:get("announcer") or not local_player or player_unit ~= local_player.player_unit then
		return
	end

	if event == "first_blood" then
		show("critical", local_player:name() .. " " .. CONFIG.first_blood.text, 2, { 255, 0, 0 })
		play(CONFIG.first_blood.event, true)
	elseif event == "multi_kill" then
		local announcement = CONFIG.multi_kills[math.min(value, #CONFIG.multi_kills)]

		show("multi_kill", announcement.text, multi_kill_font_size(value))
		play(announcement.event, true)
	elseif event == "spree" then
		local announcement = CONFIG.sprees[value]

		-- In KillingSpreeMessage the player's own message is size 2.
		show("critical", announcement.text, 3)
		play(announcement.event, true)
	elseif event == "head_shot" then
		show("head_shot", CONFIG.head_shot.text, 2)
		play(CONFIG.head_shot.event, false)
	elseif event == "call_out" then
		play_later(CONFIG.call_outs[value], CONFIG.call_out_delay)
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
	last_sound_time = -math.huge
	playing_id = nil

	table.clear(delayed)
	table.clear(messages)
end
