local mod = get_mod("unreal_tournament")

-- Adrenaline (the Adrenaline setting, the host's for everyone): UT2004's (Controller.Adrenaline, UnrealPlayer.AwardAdrenaline), up to
-- 100, given only for the rewards of kills (rewards.lua): a multi kill gives as many as its kills (two for a double kill, three for the
-- next), a spree's level as many as UT's kills for it (5, 10, 15 and on), first blood ten, a weapon's call out fifteen, the kill of a
-- special or a sack rat five, and the kill of a monster or a lord fifty. Other kills, head shots too, give none. The host keeps each player's,
-- bots' too, which lasts through a death until the level ends (UT empties it only in a combo), and sends it to every machine. The
-- announcer says "Adrenalin" a moment after the player's fills, and the HUD shows UT's counter (HudCDeathmatch.DrawAdrenaline).
--   mod.adrenaline.of(player_unit): a player's adrenaline as this machine knows it, or nil
--   mod.adrenaline.give(player_unit, amount, quiet): on the host, adds to it (or takes from it); mod.adrenaline.sync(player_unit) sends
--       it after quiet changes
--   mod.adrenaline.fill(player_unit): fills it, from any machine
--   mod.adrenaline.max: the most there is

local utils = mod.utils

local CONFIG = {
	max = 100, -- Controller.AdrenalineMax
	-- (a number, or a function of the reward's value: a multi kill's level, 1 for a double kill, or a spree's, 1 for Killing Spree)
	gains = {
		multi_kill = function (level)
			return level + 1
		end,
		spree = function (level)
			return 5 * level
		end,
		first_blood = 10,
		call_out = 15,
		special_kill = 5,
		boss_kill = 50,
	},
	-- UnrealPlayer.AwardAdrenaline: ClientDelayedAnnouncementNamed('Adrenalin', 15), in tenths of a second
	announcement = "ut_announcer_adrenalin",
	announcement_delay = 1.5, -- seconds
	-- The host sends everyone's adrenaline this often too, for a player who joins or comes back
	sync_interval = 1, -- seconds
	-- HudCDeathmatch's widgets of the counter, on HudContent's HUD texture (512 by 512) and its GlowCircle (64 by 64): the texture
	-- coordinates, TextureScale, OffsetX and OffsetY, at the top right of the screen (PosX 1). A widget's size is its texture coordinates
	-- times its TextureScale, and its offset is times its TextureScale too, in the units of a screen 480 high.
	hud_texture_size = 512,
	glow_texture_size = 64,
	background = { 168, 211, 334, 255, scale = 0.53, x = 0, y = 10, color = { 150, 0, 0, 0 } },
	disc = { 119, 258, 173, 313, scale = 0.53, x = 0, y = 5, color = { 255, 255, 255, 255 } },
	-- (fb_Pulse001: the glow circle at half its widget's size (ScaledGlowCircle's scale of 0.5 about its middle), its texture
	-- coordinates stretched about its middle by GlowCirclePulse 3 times a second, by half each way, which makes it a third of the widget
	-- to all of it; in HudColorHighLight)
	alert = { 0, 0, 64, 64, scale = 0.53, x = 6, y = 1, color = { 255, 255, 160, 0 } },
	alert_shrink = 0.5,
	alert_rate = 3, -- a second
	alert_amplitude = 0.5,
	alert_phase = 0.01,
	icon = { 113, 38, 165, 106, scale = 0.33, x = -15, y = 17, color = { 255, 255, 255, 255 } },
	-- (DrawHUDAnimWidget: the icon grows by 0.6 of its size a second for 0.3 s after a gain, and shrinks back as long)
	icon_anim_time = 0.6, -- seconds
	icon_anim_scale = 0.6,
	-- AdrenalineCount in DigitsBig: digit d is 38 by 38 from (39 d, 0), its right end and middle at the offset
	digit_size = 38,
	digit_step = 39,
	count = { scale = 0.49, x = -60, y = 35, color = { 255, 255, 255, 255 } },
	layer = 900,
}

local adrenaline = {
	max = CONFIG.max,
}

mod.adrenaline = adrenaline

local function is_host()
	return Managers.state.network ~= nil and Managers.state.network.is_server
end

local function local_unit()
	local player = Managers.player and Managers.player:local_player_safe()

	return player and player.player_unit
end

-- On the host, each player's adrenaline by their unique id; on every machine, what is known of each player's character: { amount, time
-- (when it was last heard of), gained (when it last went up) }
local by_player = {}
local known = {}

function adrenaline.of(player_unit)
	local entry = known[player_unit]

	return entry and entry.amount
end

local function know(player_unit, amount)
	local now = Managers.time:time("game")
	local entry = known[player_unit]
	local before = entry and entry.amount

	known[player_unit] = {
		amount = amount,
		time = now,
		gained = before and amount > before and now or entry and entry.gained or -math.huge,
	}

	-- (only once it was heard of below the most: a full one heard of for the first time, after a reload, is not new. Not in a combo,
	-- whose meter fills again as it drains: UnrealPlayer.AwardAdrenaline, InCurrentCombo)
	local in_combo = mod.combos and mod.combos.kind_of(player_unit) ~= nil

	if before and before < CONFIG.max and amount >= CONFIG.max and player_unit == local_unit() and not in_combo and mod.announcer then
		-- (it may wait for other announcements: not once the meter is no longer full, or a combo has started)
		mod.announcer.play_later(CONFIG.announcement, CONFIG.announcement_delay, function ()
			local entry = known[player_unit]

			return entry ~= nil and entry.amount >= CONFIG.max and not (mod.combos and mod.combos.kind_of(player_unit))
		end)
	end
end

local function go_id(unit)
	return unit and Unit.alive(unit) and Managers.state.unit_storage:go_id(unit) or 0
end

-- Tells this machine a player's adrenaline, and the others unless quiet
local function send(player, quiet)
	local unit = player.player_unit

	if not unit or not Unit.alive(unit) then
		return
	end

	local amount = by_player[player:unique_id()] or 0

	know(unit, amount)

	if not quiet then
		mod:network_send("ut_adrenaline", "others", go_id(unit), amount)
	end
end

mod:network_register("ut_adrenaline", function (_, player_go_id, amount)
	local unit_storage = Managers.state.unit_storage
	local player_unit = unit_storage and unit_storage:unit(player_go_id)

	if player_unit then
		know(player_unit, amount)
	end
end)

-- On the host: adds to a player's adrenaline (less for a negative amount), between none and the most, and tells everyone
-- (quiet tells only this machine: a combo's drain, every frame, which adrenaline.sync then sends now and then)
function adrenaline.give(player_unit, amount, quiet)
	-- (there is none in the Keep, which shows no counter and starts no combo)
	local player = is_host() and mod.option("adrenaline") and not DamageUtils.is_in_inn and Managers.player:owner(player_unit)

	if not player then
		return
	end

	local id = player:unique_id()

	by_player[id] = math.clamp((by_player[id] or 0) + amount, 0, CONFIG.max)

	send(player, quiet)
end

-- On the host: tells everyone a player's adrenaline now
function adrenaline.sync(player_unit)
	local player = is_host() and Managers.player:owner(player_unit)

	if player then
		send(player)
	end
end

-- Fills a player's adrenaline: on the host, or by asking the host (the extras mod's recharge)
function adrenaline.fill(player_unit)
	if is_host() then
		adrenaline.give(player_unit, CONFIG.max)
	else
		mod:network_send("ut_adrenaline_fill", "others", go_id(player_unit))
	end
end

mod:network_register("ut_adrenaline_fill", function (_, player_go_id)
	local unit_storage = Managers.state.unit_storage
	local player_unit = is_host() and unit_storage and unit_storage:unit(player_go_id)

	if player_unit then
		adrenaline.give(player_unit, CONFIG.max)
	end
end)

mod.rewards.callbacks.adrenaline = function (event, player_unit, value)
	local gain = CONFIG.gains[event]

	if type(gain) == "function" then
		gain = gain(value)
	end

	if gain then
		adrenaline.give(player_unit, gain)
	end
end

-- The host sends everyone's now and then, for a player who joins or comes back
local next_sync = 0

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	if not is_host() or not mod.option("adrenaline") or not Managers.state.unit_storage then
		return
	end

	local now = Managers.time:time("game")

	if now < next_sync then
		return
	end

	next_sync = now + CONFIG.sync_interval

	for _, player in pairs(Managers.player:human_and_bot_players()) do
		send(player)
	end
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(by_player)
	table.clear(known)

	next_sync = 0
end

-- The counter: UT's widgets at the top right of the screen, drawn with a screen gui of its own in the level's world
local gui_now = utils.level_screen_gui("ui/ut/adrenaline")

-- Draws a widget with its upper right at its offset from the top right of the screen, on a layer above the counter's lowest (the order
-- UT draws them in)
local function draw(gui, material, texture_size, widget, scale, width, height, layer, texture_scale)
	local x1, y1, x2, y2 = widget[1], widget[2], widget[3], widget[4]
	local size = (texture_scale or widget.scale) * scale
	local w, h = (x2 - x1) * size, (y2 - y1) * size
	local right = width + widget.x * size
	local top = widget.y * size
	local color = widget.color

	-- (the gui's y goes up from the bottom of the screen, and the texture's v down from the top, as UT's does)
	Gui.bitmap_uv(gui, material, Vector2(x1 / texture_size, y1 / texture_size), Vector2(x2 / texture_size, y2 / texture_size),
		Vector3(right - w, height - top - h, CONFIG.layer + layer), Vector2(w, h), Color(color[1], color[2], color[3], color[4]))
end

-- The glow circle of a full meter: the whole circle, in the middle of its widget, at the size its material gives it as time goes
local function draw_alert(gui, scale, width, height, now)
	local widget = CONFIG.alert
	local stretch = 1 + CONFIG.alert_amplitude * math.sin(2 * math.pi * (CONFIG.alert_rate * now + CONFIG.alert_phase))
	local size = widget.scale * scale
	local w, h = (widget[3] - widget[1]) * size, (widget[4] - widget[2]) * size
	local center_x, center_y = width + widget.x * size - w / 2, widget.y * size + h / 2
	local share = CONFIG.alert_shrink / stretch
	local color = widget.color

	Gui.bitmap(gui, "ut_glow_circle", Vector3(center_x - w * share / 2, height - center_y - h * share / 2, CONFIG.layer + 2),
		Vector2(w * share, h * share), Color(color[1], color[2], color[3], color[4]))
end

-- The number, right to left from its right end
local function draw_count(gui, value, scale, width, height)
	local count = CONFIG.count
	local digit = CONFIG.digit_size * count.scale * scale
	local text = tostring(value)
	local right = width + count.x * count.scale * scale
	local top = count.y * count.scale * scale - digit / 2
	local color = count.color
	local size = CONFIG.hud_texture_size

	for i = 1, #text do
		local d = tonumber(text:sub(i, i))
		local u = CONFIG.digit_step * d / size
		local left = right - (#text - i + 1) * digit

		Gui.bitmap_uv(gui, "ut_hud", Vector2(u, 0), Vector2(u + CONFIG.digit_size / size, CONFIG.digit_size / size),
			Vector3(left, height - top - digit, CONFIG.layer + 4), Vector2(digit, digit), Color(color[1], color[2], color[3], color[4]))
	end
end

-- Whether the game shows its HUD as it does for a living player: its "alive" visibility group, which the weapons' panel is shown in
-- (hud_component_list_adventure.lua). The others are a menu, a cutscene, the end screen, photo mode, being dead, and so on.
local function hud_shown()
	local ui_manager = Managers.ui
	local ingame_ui = ui_manager and ui_manager._ui_enabled and ui_manager._ingame_ui
	local ingame_hud = ingame_ui and ingame_ui.ingame_hud

	-- (ingame_hud is false, not nil, while the UI is off)
	return ingame_hud and ingame_hud._current_group_name == "alive" or false
end

-- What is known of the player's adrenaline while the counter is shown, or nil
local function shown_entry()
	-- (not in the Keep, which is a hub level: StateIngame sets this, nor while the game's HUD is hidden)
	if DamageUtils.is_in_inn or not hud_shown() then
		return nil
	end

	local unit = local_unit()
	local entry = unit and known[unit]

	-- (the host's setting, in a game: mod.option)
	if not entry or not mod.option("adrenaline") then
		return nil
	end

	return entry
end

-- The kill feed (PositiveReinforcementUI) is at the top right too: while the counter is shown it starts below it, as far below as it is
-- below the top of the screen otherwise. Its scenegraph is 1080 high, and the counter's lowest widget (the glow) ends this far down.
local function counter_bottom()
	local alert = CONFIG.alert

	return (alert.y + alert[4] - alert[2]) * alert.scale * 1080 / 480
end

mod:hook(PositiveReinforcementUI, "update", function (func, self, ...)
	local node = self.ui_scenegraph and self.ui_scenegraph.message_animated

	if node then
		self._ut_feed_y = self._ut_feed_y or node.local_position[2]
		node.local_position[2] = self._ut_feed_y - (shown_entry() and counter_bottom() or 0)
	end

	return func(self, ...)
end)

mod.ingame_ui_post_update_callbacks.adrenaline = function ()
	local entry = shown_entry()

	if not entry then
		return
	end

	local now = Managers.time:time("game")
	local gui = gui_now()

	if not gui then
		return
	end

	local width, height = Application.resolution()
	local scale = height / 480
	local size = CONFIG.hud_texture_size
	local value = math.floor(math.clamp(entry.amount, 0, CONFIG.max))

	draw(gui, "ut_hud", size, CONFIG.background, scale, width, height, 0)
	draw(gui, "ut_hud", size, CONFIG.disc, scale, width, height, 1)

	if value >= CONFIG.max then
		draw_alert(gui, scale, width, height, now)
	end

	-- (DrawHUDAnimWidget: the icon's TextureScale grows and shrinks back after a gain)
	local since = now - entry.gained
	local icon_scale = CONFIG.icon.scale
	local anim_time = CONFIG.icon_anim_time

	if since < anim_time / 2 then
		icon_scale = icon_scale * (1 + CONFIG.icon_anim_scale * since)
	elseif since < anim_time then
		icon_scale = icon_scale * (1 + CONFIG.icon_anim_scale * (anim_time - since))
	end

	draw(gui, "ut_hud", size, CONFIG.icon, scale, width, height, 3, icon_scale)
	draw_count(gui, value, scale, width, height)
end
