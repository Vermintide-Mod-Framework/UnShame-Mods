local mod = get_mod("unreal_tournament")

-- Adrenaline (the Adrenaline setting, the host's for everyone): UT2004's (Controller.Adrenaline, UnrealPlayer.AwardAdrenaline), up to
-- 100, given only for the rewards of kills (rewards.lua): one for each level of a multi kill, five for each level of a spree (the five
-- kills between UT's levels), and five for first blood, a head shot and a call out. Kills alone give none. The host keeps each player's,
-- bots' too, which lasts through a death until the level ends (UT empties it only in a combo), and sends it to every machine. The
-- announcer says "Adrenalin" a moment after the player's fills, and the HUD shows UT's counter (HudCDeathmatch.DrawAdrenaline).
--   mod.adrenaline.of(player_unit): a player's adrenaline as this machine knows it, or nil
--   mod.adrenaline.give(player_unit, amount): on the host, adds to it (or takes from it)
--   mod.adrenaline.max: the most there is

local utils = mod.utils

local CONFIG = {
	max = 100, -- Controller.AdrenalineMax
	gains = {
		multi_kill = 1,
		spree = 5,
		first_blood = 5,
		head_shot = 5,
		call_out = 5,
	},
	-- UnrealPlayer.AwardAdrenaline: ClientDelayedAnnouncementNamed('Adrenalin', 15), in tenths of a second
	announcement = "ut_announcer_adrenalin",
	announcement_delay = 1.5, -- seconds
	-- The host sends everyone's adrenaline this often too, and a machine shows the counter while it has heard of it this lately
	sync_interval = 1, -- seconds
	shown_for = 3, -- seconds
	-- HudCDeathmatch's widgets of the counter, on HudContent's HUD texture (512 by 512) and its GlowCircle (64 by 64): the texture
	-- coordinates, TextureScale, OffsetX and OffsetY, at the top right of the screen (PosX 1). A widget's size is its texture coordinates
	-- times its TextureScale, and its offset is times its TextureScale too, in the units of a screen 480 high.
	hud_texture_size = 512,
	glow_texture_size = 64,
	background = { 168, 211, 334, 255, scale = 0.53, x = 0, y = 10, color = { 150, 0, 0, 0 } },
	disc = { 119, 258, 173, 313, scale = 0.53, x = 0, y = 5, color = { 255, 255, 255, 255 } },
	-- (fb_Pulse001: the glow circle, magnified twice by ScaledGlowCircle, stretched about its middle by GlowCirclePulse 3 times a second,
	-- by half, in HudColorHighLight)
	alert = { 0, 0, 64, 64, scale = 0.53, x = 6, y = 1, color = { 255, 255, 160, 0 } },
	alert_magnify = 0.5,
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

	-- (only once it was heard of below the most: a full one heard of for the first time, after a reload, is not new)
	if before and before < CONFIG.max and amount >= CONFIG.max and player_unit == local_unit() and mod.announcer then
		mod.announcer.play_later(CONFIG.announcement, CONFIG.announcement_delay)
	end
end

local function go_id(unit)
	return unit and Unit.alive(unit) and Managers.state.unit_storage:go_id(unit) or 0
end

-- Tells this machine and the others a player's adrenaline
local function send(player)
	local unit = player.player_unit

	if not unit or not Unit.alive(unit) then
		return
	end

	local amount = by_player[player:unique_id()] or 0

	know(unit, amount)
	mod:network_send("ut_adrenaline", "others", go_id(unit), amount)
end

mod:network_register("ut_adrenaline", function (_, player_go_id, amount)
	local unit_storage = Managers.state.unit_storage
	local player_unit = unit_storage and unit_storage:unit(player_go_id)

	if player_unit then
		know(player_unit, amount)
	end
end)

-- On the host: adds to a player's adrenaline (less for a negative amount), between none and the most, and tells everyone
function adrenaline.give(player_unit, amount)
	local player = is_host() and mod:get("adrenaline") and Managers.player:owner(player_unit)

	if not player then
		return
	end

	local id = player:unique_id()

	by_player[id] = math.clamp((by_player[id] or 0) + amount, 0, CONFIG.max)

	send(player)
end

mod.rewards.callbacks.adrenaline = function (event, player_unit)
	local gain = CONFIG.gains[event]

	if gain then
		adrenaline.give(player_unit, gain)
	end
end

-- The host sends everyone's now and then, for a player who joins or comes back
local next_sync = 0

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	if not is_host() or not mod:get("adrenaline") or not Managers.state.unit_storage then
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

-- The glow circle of a full meter, stretched about its middle as time goes
local function draw_alert(gui, scale, width, height, now)
	local widget = CONFIG.alert
	local stretch = 1 + CONFIG.alert_amplitude * math.sin(2 * math.pi * (CONFIG.alert_rate * now + CONFIG.alert_phase))
	local half = 0.5 * CONFIG.alert_magnify * stretch
	local size = widget.scale * scale
	local w, h = (widget[3] - widget[1]) * size, (widget[4] - widget[2]) * size
	local right, top = width + widget.x * size, widget.y * size
	local color = widget.color

	Gui.bitmap_uv(gui, "ut_glow_circle", Vector2(0.5 - half, 0.5 - half), Vector2(0.5 + half, 0.5 + half),
		Vector3(right - w, height - top - h, CONFIG.layer + 2), Vector2(w, h), Color(color[1], color[2], color[3], color[4]))
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

mod.ingame_ui_post_update_callbacks.adrenaline = function ()
	local unit = local_unit()
	local entry = unit and known[unit]

	if not entry then
		return
	end

	local now = Managers.time:time("game")

	-- (on a machine that isn't the host, the host's word stops coming when its setting is off)
	if not (is_host() and mod:get("adrenaline")) and now - entry.time > CONFIG.shown_for then
		return
	end

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
