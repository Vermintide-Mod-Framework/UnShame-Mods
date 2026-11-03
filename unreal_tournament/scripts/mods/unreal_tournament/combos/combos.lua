local mod = get_mod("unreal_tournament")

-- Adrenaline's combos (XGame's Combo, and its ComboSpeed, ComboBerserk, ComboDefensive (Booster) and ComboInvis). With a full meter
-- (adrenaline.lua), four quick taps of the movement keys in a combo's order start it (xPlayer.CheckCombo), and it drains the meter over
-- its duration (Combo.Tick), ending when the meter is empty. The host starts and ends them, for players and bots, and tells every
-- machine, which plays what everyone sees and hears of it: the activation's sound and burst (Combo.ActivateSound, ComboActivation) and
-- the combo's own (combos/*.lua). The player who started one sees its name (ComboMessage) and hears the announcer say it. A knockdown or
-- a death in a combo ends it and empties the meter (xPawn.Died). A knocked down character can start the Booster, which gets it up (not
-- UT's: its pawns are never down). Bots start one at random once their meter is full and they have an enemy (SquadAI.AssignCombo), and
-- the Booster when they are knocked down, held by a special or hanging from a ledge (the Booster gets them out).
--   mod.combos.kinds[name] = { start = function (unit, owner), stop = function (unit, owner), update = function (unit, dt, owner) }: a
--       combo's own effects, on every machine. owner is whether this machine runs the character (the player's own, or a bot on the host).
--   mod.combos.kind_of(unit): the name of the combo a character is in, or nil

local utils = mod.utils
local adrenaline = mod.adrenaline
local particles = mod.skin_particles

local UNIT = utils.UT_UNIT

-- The keys of xPlayer.CheckCombo: CK_Up, CK_Down, and the two ways to the side
local FORWARD, BACK, RIGHT, LEFT = 1, 2, 4, 8

local CONFIG = {
	-- xPlayer: keys pressed within MinComboKeyTime of each other count as one press, and a gap longer than MaxComboKeyTime starts over
	min_key_time = 0.05, -- s
	max_key_time = 0.35, -- s
	-- How far the movement input has to go for a key to count as held (UT reads the keys' axes, aForward and aStrafe)
	axis_threshold = 0.5,
	-- The combos, as xPlayer.ComboNameList orders them: their keys in the order they are pressed (UT's keys are newest first), Duration,
	-- ExecMessage and ComboAnnouncementName
	combos = {
		{ name = "speed", keys = { FORWARD, FORWARD, FORWARD, FORWARD }, duration = 16, message = "Speed!", announcement = "ut_announcer_speed" },
		{ name = "berserk", keys = { FORWARD, FORWARD, BACK, BACK }, duration = 30, message = "Berserk!", announcement = "ut_announcer_berzerk" },
		{ name = "booster", keys = { BACK, BACK, BACK, BACK }, duration = 30, message = "Booster!", announcement = "ut_announcer_booster", gets_up = true },
		{ name = "invisible", keys = { RIGHT, RIGHT, LEFT, LEFT }, duration = 30, message = "Invisible!", announcement = "ut_announcer_invisible" },
	},
	-- The host sends a player's draining adrenaline this often, and looks at the bots' this often
	sync_interval = 0.25, -- s
	bot_interval = 1, -- s
	-- Combo.ActivateSound, at the pawn
	activate_sound = "ut_combo_activated_3d",
	-- ComboActivation: a burst of 20 balls of light (80 a second for 0.25 s) from 10 units around the pawn's middle, out from it at 75
	-- units a second, faster as they go (mAirResistance -4), red to white, of size 3 (utils.UT_SPRITE_SIDE times that across), for 0.75 s,
	-- following the pawn (mPosRelative). It is ST_Explode: each starts mPosDev along a random direction and flies along it (Engine.dll's
	-- InitParticle, decompiled).
	burst = {
		count = 20,
		spawn_time = 0.25, -- s
		spread = 10, -- units
		speed = 75, -- units a second
		acceleration = 4, -- the speed times this a second
		life = 0.75, -- s
		size = 3, -- mSizeRange
		colors = { { 1, 0, 0 }, { 1, 1, 1 } },
		texture = "combo_ball",
	},
	-- The middle of a pawn, above its feet: xPawn's CollisionHeight
	pawn_middle = 44, -- units
}

local combos = {
	kinds = {},
	config = CONFIG,
}

mod.combos = combos

local function is_host()
	return Managers.state.network ~= nil and Managers.state.network.is_server
end

local function go_id(unit)
	return unit and Unit.alive(unit) and Managers.state.unit_storage:go_id(unit) or 0
end

local function index_of(name)
	for index, combo in ipairs(CONFIG.combos) do
		if combo.name == name then
			return index
		end
	end
end

-- Whether this machine runs a character's actions: the player's own, or a bot on the host
local function is_owner(unit)
	if utils.is_local_player_unit(unit) then
		return true
	end

	local player = Managers.player:owner(unit)

	return player ~= nil and player.bot_player == true and is_host()
end

-- The combo each character is in, on every machine: { index, owner }
local active = {}

function combos.kind_of(unit)
	local entry = active[unit]

	return entry and CONFIG.combos[entry.index].name
end

function combos.pawn_middle(unit)
	return Unit.world_position(unit, 0) + Vector3(0, 0, CONFIG.pawn_middle * UNIT)
end

combos.is_host = is_host

-- A combo's buff: a template of one buff of the game, named as the buff, which goes over the network by its name, so everyone in the
-- game needs the mod
function combos.buff(buff)
	buff.max_stacks = buff.max_stacks or 1

	BuffTemplates[buff.name] = {
		buffs = {
			buff,
		},
	}

	utils.register_network_lookup("buff_templates", buff.name)
end

-- On the host: adds a combo's buffs to a character, as buffs the host takes away (add_buff's is_server_controlled), and returns them
function combos.add_buffs(unit, names)
	local buff_system = Managers.state.entity:system("buff_system")
	local ids = {}

	for _, name in ipairs(names) do
		ids[#ids + 1] = buff_system:add_buff(unit, name, unit, true)
	end

	return ids
end

function combos.remove_buffs(unit, ids)
	local buff_system = Managers.state.entity:system("buff_system")

	for _, id in ipairs(ids or {}) do
		buff_system:remove_server_controlled_buff(unit, id)
	end
end

-- ComboActivation, around the pawn and following it
local function burst(unit)
	local settings = CONFIG.burst

	local now = Managers.time:time("game")
	local low, high = settings.colors[1], settings.colors[2]

	for i = 1, settings.count do
		local direction = utils.random_direction()
		local start = Vector3Box(direction * (settings.spread * UNIT))
		local way = Vector3Box(direction)
		local share = math.random()
		local accel = settings.acceleration
		local speed = settings.speed * UNIT
		local delay = (i - 1) / settings.count * settings.spawn_time
		local born = now + delay

		particles.sprite({
			color = { low[1] + (high[1] - low[1]) * share, low[2] + (high[2] - low[2]) * share, low[3] + (high[3] - low[3]) * share },
			delay = delay,
			fade_squared = true,
			life = settings.life,
			size = settings.size * utils.UT_SPRITE_SIDE * UNIT,
			texture = settings.texture,
			follow = function ()
				if not Unit.alive(unit) then
					return nil
				end

				-- (the speed grows as e^(accel t), so the way gone is speed / accel (e^(accel t) - 1))
				local age = math.max(Managers.time:time("game") - born, 0)
				local gone = speed / accel * (math.exp(accel * age) - 1)

				return combos.pawn_middle(unit) + start:unbox() + way:unbox() * gone
			end,
		})
	end
end

local function begin(unit, index)
	local combo = CONFIG.combos[index]
	local owner = is_owner(unit)

	active[unit] = { index = index, owner = owner }

	utils.play_on_unit(CONFIG.activate_sound, unit)
	burst(unit)

	if utils.is_local_player_unit(unit) then
		if mod.announcer then
			mod.announcer.combo_message(combo.message)
			mod.announcer.play(combo.announcement, true)
		end
	end

	local kind = combos.kinds[combo.name]

	if kind and kind.start then
		kind.start(unit, owner)
	end
end

local function finish(unit)
	local entry = active[unit]

	if not entry then
		return
	end

	active[unit] = nil

	local kind = combos.kinds[CONFIG.combos[entry.index].name]

	if kind and kind.stop then
		kind.stop(unit, entry.owner)
	end
end

mod:network_register("ut_combo", function (_, player_go_id, index)
	local unit_storage = Managers.state.unit_storage
	local unit = unit_storage and unit_storage:unit(player_go_id)

	if not unit then
		return
	end

	if index == 0 then
		finish(unit)
	else
		finish(unit)
		begin(unit, index)
	end
end)

local function is_knocked_down(unit)
	local status_extension = ScriptUnit.has_extension(unit, "status_system")

	return status_extension ~= nil and status_extension:is_knocked_down()
end

-- On the host: starts a combo (xPawn.DoCombo, when the meter is full and the pawn is in none) and tells everyone. A knocked down
-- character can only start one that gets it up (the Booster's, not UT's).
local function start(unit, index)
	if not is_host() or active[unit] or (adrenaline.of(unit) or 0) < adrenaline.max then
		return
	end

	local down = is_knocked_down(unit)

	if down and not CONFIG.combos[index].gets_up then
		return
	end

	begin(unit, index)

	-- (a knockdown only ends a combo once the character has been up in it: the game's revive takes a moment)
	active[unit].up = not down
	mod:network_send("ut_combo", "others", go_id(unit), index)
end

-- On the host: ends a combo, emptying the meter if empty is given, and tells everyone
local function stop(unit, empty)
	if not active[unit] then
		return
	end

	if empty then
		adrenaline.give(unit, -adrenaline.max)
	end

	mod:network_send("ut_combo", "others", go_id(unit), 0)
	finish(unit)
end

mod:network_register("ut_combo_request", function (_, player_go_id, index)
	local unit_storage = Managers.state.unit_storage
	local unit = unit_storage and unit_storage:unit(player_go_id)

	if unit and CONFIG.combos[index] then
		start(unit, index)
	end
end)

-- Asks for a combo: on the host it starts, on a client the host is asked
local function request(unit, index)
	if is_host() then
		start(unit, index)
	else
		mod:network_send("ut_combo_request", "others", go_id(unit), index)
	end
end

-- xPlayer.CheckCombo: the keys pressed lately, newest first, read while the player has a full meter and is in no combo
local history = { 0, 0, 0, 0 }
local old_key = 0
local last_key_time = -math.huge

local function held_keys(input_extension)
	local move = input_extension:get("move")
	local key = 0

	if move then
		local threshold = CONFIG.axis_threshold
		local forward, right = Vector3.y(move), Vector3.x(move)

		if forward > threshold then
			key = FORWARD
		elseif forward < -threshold then
			key = BACK
		end

		if right > threshold then
			key = key + RIGHT
		elseif right < -threshold then
			key = key + LEFT
		end
	end

	return key
end

local function read_keys(unit, t)
	local input_extension = ScriptUnit.has_extension(unit, "input_system")

	if not input_extension or active[unit] or (adrenaline.of(unit) or 0) < adrenaline.max then
		history[1] = 0

		return
	end

	local key = held_keys(input_extension)

	if key == old_key then
		return
	end

	-- (the keys pressed now that weren't last frame)
	local new_keys = bit.band(key, bit.bnot(old_key))

	old_key = key

	if new_keys == 0 then
		return
	end

	local full = false

	if t - last_key_time < CONFIG.min_key_time then
		history[1] = bit.bor(history[1], new_keys)
	elseif t - last_key_time > CONFIG.max_key_time then
		history[1] = new_keys
		history[2] = 0
		last_key_time = t
	else
		full = true

		for i = 4, 2, -1 do
			history[i] = history[i - 1]

			if history[i] == 0 then
				full = false
			end
		end

		history[1] = new_keys
		last_key_time = t
	end

	if not full then
		return
	end

	for index, combo in ipairs(CONFIG.combos) do
		local match = true

		-- (the history is newest first, the combo's keys oldest first)
		for i = 1, 4 do
			if history[i] ~= combo.keys[5 - i] then
				match = false

				break
			end
		end

		if match then
			history[1] = 0

			request(unit, index)

			return
		end
	end
end

-- On the host: the drain, the ends, and the bots' choices
local next_sync = 0
local next_bot_check = 0

local function update_host(dt, t)
	local sync = t >= next_sync

	if sync then
		next_sync = t + CONFIG.sync_interval
	end

	for unit, entry in pairs(active) do
		local status_extension = Unit.alive(unit) and ScriptUnit.has_extension(unit, "status_system")

		if not status_extension then
			mod:network_send("ut_combo", "others", go_id(unit), 0)
			finish(unit)
		elseif status_extension:is_dead() or status_extension:is_knocked_down() and entry.up then
			stop(unit, true)
		else
			entry.up = entry.up or not status_extension:is_knocked_down()

			local combo = CONFIG.combos[entry.index]

			adrenaline.give(unit, -adrenaline.max * dt / combo.duration, true)

			if (adrenaline.of(unit) or 0) <= 0 then
				adrenaline.sync(unit)
				stop(unit)
			elseif sync then
				adrenaline.sync(unit)
			end
		end
	end

	if t < next_bot_check then
		return
	end

	next_bot_check = t + CONFIG.bot_interval

	for _, player in pairs(Managers.player:human_and_bot_players()) do
		local unit = player.bot_player and player.player_unit
		local ai_extension = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "ai_system")
		local blackboard = ai_extension and ai_extension.blackboard and ai_extension:blackboard()
		local target = blackboard and blackboard.target_unit

		local ready = ai_extension and not active[unit] and (adrenaline.of(unit) or 0) >= adrenaline.max

		-- (a bot that is knocked down, held by a special or hanging from a ledge gets itself out with the Booster)
		local status_extension = ready and ScriptUnit.has_extension(unit, "status_system")
		local stuck = status_extension and (status_extension:is_knocked_down() or utils.get_disabler(status_extension) or status_extension:get_is_ledge_hanging())

		if ready and stuck then
			start(unit, index_of("booster"))
		elseif ready and target and HEALTH_ALIVE[target] then
			start(unit, math.random(#CONFIG.combos))
		end
	end
end

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	if not Managers.state.unit_storage or not Managers.time then
		return
	end

	local t = Managers.time:time("game")
	local player = Managers.player and Managers.player:local_player_safe()
	local unit = player and player.player_unit

	if unit and Unit.alive(unit) and not DamageUtils.is_in_inn then
		read_keys(unit, t)
	end

	if is_host() then
		update_host(dt, t)
	end

	for active_unit, entry in pairs(active) do
		local kind = combos.kinds[CONFIG.combos[entry.index].name]

		if not Unit.alive(active_unit) then
			-- (a character that is gone takes its combo's effects with it)
			finish(active_unit)
		elseif kind and kind.update then
			kind.update(active_unit, dt, entry.owner)
		end
	end
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	for unit in pairs(active) do
		finish(unit)
	end

	table.clear(active)

	history[1] = 0
	old_key = 0
	last_key_time = -math.huge

	-- (the game's clock starts again at 0 in the next level)
	next_sync = 0
	next_bot_check = 0
end

combos.index_of = index_of

-- On the host: starts a combo by its name, as its keys would (for the tests)
function combos.start(unit, name)
	start(unit, index_of(name))
end
