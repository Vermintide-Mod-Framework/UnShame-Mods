local mod = get_mod("unreal_tournament")

-- Announcer (the Announcer setting): UT2004's multi kill announcements. A kill of yours soon after your last one is a multi kill, and each
-- one in a row raises its level: Double Kill, Multi Kill, Mega Kill, Ultra Kill, Monster Kill, Ludicrous Kill, Holy Shit
-- (UnrealPlayer.LogMultiKills counts them, MultiKillMessage says which sound and which text each level has, MaleAnnouncer is the voice).
-- The sounds are in a bank of their own (tools/asset_conversion/make_bank.py announcer).

local CONFIG = {
	-- UnrealPlayer.LogMultiKills: a kill counts as the next one of a multi kill if it comes this soon after the last one (UT has 4
	-- seconds, a horde of this game dies faster than players do)
	window = 1.5, -- seconds
	-- What is not an enemy for it (a player is the kill of UT: the rats and the target dummies of this game are not one)
	ignored_races = {
		critter = true,
		dummy = true,
	},
	-- MultiKillMessage, by the level of the multi kill (1 is the second kill): its sound and its text; the last one is every level after it
	levels = {
		{ event = "ut_announcer_double_kill", text = "Double Kill!" },
		{ event = "ut_announcer_multi_kill", text = "Multi Kill!" },
		{ event = "ut_announcer_mega_kill", text = "Mega Kill!!" },
		{ event = "ut_announcer_ultra_kill", text = "ULTRA KILL!!" },
		{ event = "ut_announcer_monster_kill", text = "M O N S T E R  K I L L !!!" },
		{ event = "ut_announcer_ludicrous_kill", text = "L U D I C R O U S !!!" },
		{ event = "ut_announcer_holy_shit", text = "H O L Y  S H I T !" },
	},
	-- The text (MultiKillMessage and LocalMessage): red, PosY down the screen, it lasts Lifetime and fades out at the end; the size is the
	-- one of its FontSize (GetFontSize: 0 up to the 3rd level, 1 for the 4th, 3 for the 7th, 2 for the others), in pixels at 1080 high
	text_color = { 255, 0, 0 },
	text_position_y = 0.242,
	text_life = 3, -- seconds
	text_fade = 1, -- seconds, at the end of it
	text_shadow = 2, -- pixels, of the shadow it is read by
	font_material = "materials/fonts/gw_head",
	font_name = "gw_head",
	font_sizes = { 40, 52, 66, 84 },
}

local level = 0 -- UnrealPlayer.MultiKillLevel
local last_kill_time = -math.huge
local playing_id -- of the announcement that is playing
local message -- { text, size, time }: the text on the screen

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

-- MultiKillMessage.GetFontSize
local function font_size_index(multi_kill_level)
	if multi_kill_level < 4 then
		return 1
	elseif multi_kill_level == 4 then
		return 2
	elseif multi_kill_level == 7 then
		return 4
	end

	return 3
end

local function announce(multi_kill_level)
	local announcement = CONFIG.levels[math.min(multi_kill_level, #CONFIG.levels)]

	message = {
		size = CONFIG.font_sizes[font_size_index(multi_kill_level)],
		text = announcement.text,
		time = Managers.time:time("game"),
	}

	local wwise_world = Managers.world:wwise_world(Managers.world:world("level_world"))

	-- (the one that is playing is cut off by the next, a forced reward announcement is)
	if playing_id then
		WwiseWorld.stop_event(wwise_world, playing_id)
	end

	playing_id = WwiseWorld.trigger_event(wwise_world, announcement.event)
end

mod:hook_safe(StatisticsUtil, "register_kill", function (victim_unit)
	if not mod:get("announcer") or not is_local_kill(victim_unit) then
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

-- The text, every frame, in the middle of the screen (the game's own user interface draws it, as it does its debug texts)
mod:hook_safe(IngameUI, "post_update", function (self)
	if not message then
		return
	end

	local age = Managers.time:time("game") - message.time

	if age >= CONFIG.text_life then
		message = nil

		return
	end

	local gui = self.ui_renderer.gui
	local width, height = Application.resolution()
	local size = message.size * height / 1080
	local minimum, maximum = Gui.text_extents(gui, message.text, CONFIG.font_material, size)
	local alpha = 255 * math.clamp((CONFIG.text_life - age) / CONFIG.text_fade, 0, 1)
	local position = Vector3((width - (maximum.x - minimum.x)) / 2, height * (1 - CONFIG.text_position_y), 999)
	local shadow = CONFIG.text_shadow * height / 1080
	local red, green, blue = unpack(CONFIG.text_color)

	Gui.text(gui, message.text, CONFIG.font_material, size, CONFIG.font_name, position + Vector3(shadow, -shadow, -1), Color(alpha, 0, 0, 0))
	Gui.text(gui, message.text, CONFIG.font_material, size, CONFIG.font_name, position, Color(alpha, red, green, blue))
end)

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	level = 0
	last_kill_time = -math.huge
	playing_id = nil
	message = nil
end
