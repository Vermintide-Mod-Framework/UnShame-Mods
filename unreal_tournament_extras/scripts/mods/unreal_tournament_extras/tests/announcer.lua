local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The announcer's in-game tests (see runner.lua). Run them with /ut_test announcer. They run in the runner's level, Righteous Stand, which
-- is loaded again for them, because first blood is the first kill of a level. The kills are made by damage the player deals with a weapon
-- named as the damage's source, so they count as the weapon's. What is checked is the sounds the announcer plays.
--
-- The scenarios run in order and build on each other: the announcer's counts last for the level.

local runner = mod.test_runner

local flak = ut.items.weapons.flak_cannon
local shock = ut.items.weapons.shock_rifle
local sniper = ut.items.weapons.sniper_rifle

local CONFIG = {
	-- The damage types of a flak chunk's hit and of a flak shell's explosion (flak_cannon.lua)
	chunk_damage_type = "shot_shotgun",
	shell_damage_type = "grenade",
	-- A kill this soon after the last is the next of a multi kill
	multi_kill_window = 1.5, -- s
	-- UT's spree and call out numbers, times 3
	killing_spree = 15,
	call_out = 45,
	call_out_delay = 1.5, -- s
	-- The enemy that counts as a kill, and one that counts for nothing
	counted_breed = "skaven_clan_rat",
	ignored_breed = "skaven_slave",
}

-- The chat's system lines while a scenario records them
local chat_lines = {}
local recording_chat = false

mod:hook_safe(ChatManager, "add_local_system_message", function (self, channel_id, message)
	if recording_chat then
		chat_lines[#chat_lines + 1] = message
	end
end)

local function count(list, name)
	local total = 0

	for _, value in ipairs(list) do
		if value == "ut_announcer_" .. name then
			total = total + 1
		end
	end

	return total
end

-- Kills an enemy as the player: { source = the item, zone = the hit zone, ranged = whether the hit is a ranged shot, damage_type = the
-- hit's damage type }
local function kill(t, unit, how)
	how = how or {}

	local killed = t.on_main_thread(function ()
		if HEALTH_ALIVE[unit] then
			local player = t.unit()

			DamageUtils.add_damage_network(unit, player, 400, how.zone or "torso", how.damage_type or "cutting", nil, Vector3(0, 0, -1), how.source or shock.key, nil, player, how.ranged and "instant_projectile" or nil)

			return true
		end
	end)

	return killed
end

-- Kills a number of counted enemies, a moment apart, and takes the bodies away
local function kill_many(t, total, how, gap)
	local done = 0

	while done < total do
		local group = t.spawn_group(CONFIG.counted_breed, math.min(10, total - done), 5)

		t.wait(1)

		for i, unit in ipairs(group) do
			if not kill(t, unit, how) then
				local where = t.on_main_thread(function ()
					local p = Unit.alive(unit) and Unit.world_position(unit, 0)

					return p and string.format("%.1f %.1f %.1f", Vector3.x(p), Vector3.y(p), Vector3.z(p)) or "gone"
				end)

				t.log("enemy %d of %d was dead before it was killed, at %s", i, #group, where)
			end

			done = done + 1

			if gap then
				t.wait(gap)
			end
		end

		t.wait(0.5)

		for _, unit in ipairs(group) do
			t.remove(unit)
		end
	end
end

-- An enemy hurts the player, which ends a spree and starts the call outs' counts again
local function hurt_by_enemy(t)
	local rat = t.spawn(CONFIG.counted_breed, 3)

	t.hurtable(true)
	t.on_main_thread(function ()
		DamageUtils.add_damage_network(t.unit(), rat, 1, "torso", "cutting", nil, Vector3(0, 0, -1), CONFIG.counted_breed, nil, rat)
	end)
	t.wait(0.2)
	t.hurtable(false)
	t.heal()
	t.remove(rat)
end

local function scenarios()
	local list = {
		{
			name = "the first kill of the level is first blood",
			run = function (t)
				local sounds = t.sounds("ut_announcer_")
				local rat = t.spawn(CONFIG.counted_breed, 6)

				t.wait(1)
				kill(t, rat)
				t.wait(0.5)

				t.expect(count(sounds, "first_blood") == 1, "first blood was announced %d times (%s)", count(sounds, "first_blood"), table.concat(sounds, ", "))

				-- (and only the first)
				rat = t.spawn(CONFIG.counted_breed, 6)
				t.wait(2)
				kill(t, rat)
				t.wait(0.5)

				t.expect(count(sounds, "first_blood") == 1, "the second kill was first blood too")
			end,
		},
		{
			name = "kills apart are no multi kill",
			run = function (t)
				local sounds = t.sounds("ut_announcer_")
				local rats = t.spawn_group(CONFIG.counted_breed, 2, 6)

				t.wait(1)
				kill(t, rats[1])
				t.wait(CONFIG.multi_kill_window + 0.3)
				kill(t, rats[2])
				t.wait(0.5)

				t.expect(count(sounds, "double_kill") == 0, "two kills %.1f s apart were a double kill", CONFIG.multi_kill_window + 0.3)
			end,
		},
		{
			name = "kills close together are a double kill, then a multi kill",
			run = function (t)
				local sounds = t.sounds("ut_announcer_")
				local rats = t.spawn_group(CONFIG.counted_breed, 3, 6)

				t.wait(2)

				for _, rat in ipairs(rats) do
					kill(t, rat)
					t.wait(0.5)
				end

				t.expect(sounds[1] == "ut_announcer_double_kill" and sounds[2] == "ut_announcer_multi_kill" and #sounds == 2, "three kills 0.5 s apart announced %s, not a double kill and a multi kill", table.concat(sounds, ", "))
			end,
		},
		{
			name = "a slave counts for nothing",
			run = function (t)
				local sounds = t.sounds("ut_announcer_")
				local slave = t.spawn(CONFIG.ignored_breed, 6)
				local rat = t.spawn(CONFIG.counted_breed, 7)

				t.wait(2)
				kill(t, slave)
				t.wait(0.5)
				kill(t, rat)
				t.wait(0.5)

				t.expect(#sounds == 0, "a slave and a rat 0.5 s apart announced %s", table.concat(sounds, ", "))
			end,
		},
		{
			name = "a ranged kill to the head is a head shot, a melee one is not",
			run = function (t)
				local sounds = t.sounds("ut_announcer_")
				local rats = t.spawn_group(CONFIG.counted_breed, 2, 6)

				t.wait(2)

				-- (a melee weapon's hit: the game tells a ranged hit by its attack, or by the slot of the weapon when it has none)
				kill(t, rats[1], {
					source = ut.items.weapons.shield_gun.key,
					zone = "head",
				})
				t.wait(CONFIG.multi_kill_window + 0.3)

				t.expect(count(sounds, "headshot") == 0, "a kill to the head that was not a ranged shot was a head shot")

				kill(t, rats[2], {
					ranged = true,
					zone = "head",
				})
				t.wait(0.5)

				t.expect(count(sounds, "headshot") == 1, "a ranged kill to the head announced %s", table.concat(sounds, ", "))
			end,
		},
		{
			name = "a head shot is not announced over another announcement",
			run = function (t)
				local sounds = t.sounds("ut_announcer_")
				local rats = t.spawn_group(CONFIG.counted_breed, 2, 6)

				t.wait(2)

				-- (the second kill is a double kill, forced, and then the head shot is too soon after it)
				kill(t, rats[1])
				t.wait(0.3)
				kill(t, rats[2], {
					ranged = true,
					zone = "head",
				})
				t.wait(0.5)

				t.expect(count(sounds, "double_kill") == 1, "no double kill (%s)", table.concat(sounds, ", "))
				t.expect(count(sounds, "headshot") == 0, "the head shot was announced 0.3 s after the double kill")
			end,
		},
		{
			name = "fifteen kills without an enemy's hurt are a killing spree",
			run = function (t)
				hurt_by_enemy(t)

				local sounds = t.sounds("ut_announcer_")

				kill_many(t, CONFIG.killing_spree - 1, nil, 0.1)
				t.expect(count(sounds, "killing_spree") == 0, "a killing spree after %d kills", CONFIG.killing_spree - 1)

				kill_many(t, 1)
				t.expect(count(sounds, "killing_spree") == 1, "no killing spree after %d kills (%s)", CONFIG.killing_spree, table.concat(sounds, ", "))
			end,
		},
		{
			name = "an enemy's hurt ends the spree",
			run = function (t)
				hurt_by_enemy(t)

				local sounds = t.sounds("ut_announcer_")

				kill_many(t, 10, nil, 0.1)
				hurt_by_enemy(t)
				kill_many(t, 10, nil, 0.1)

				t.expect(count(sounds, "killing_spree") == 0, "the spree went on through an enemy's hurt (%s)", table.concat(sounds, ", "))
			end,
		},
		{
			-- Only the chunks count, as UT's DamTypeFlakChunk does
			name = "the kills of flak shells' explosions are no flak monkey",
			run = function (t)
				hurt_by_enemy(t)

				local sounds = t.sounds("ut_announcer_flak_monkey")

				kill_many(t, CONFIG.call_out, {
					source = flak.key,
					damage_type = CONFIG.shell_damage_type,
				}, 0.05)
				t.wait(CONFIG.call_out_delay + 0.5)
				t.expect(#sounds == 0, "a flak monkey after %d kills of shells' explosions", CONFIG.call_out)
			end,
		},
		{
			name = "forty five flak chunk kills are a flak monkey, called out a moment after",
			run = function (t)
				hurt_by_enemy(t)

				local sounds = t.sounds("ut_announcer_flak_monkey")

				kill_many(t, CONFIG.call_out - 1, {
					source = flak.key,
					damage_type = CONFIG.chunk_damage_type,
				}, 0.05)
				t.wait(CONFIG.call_out_delay + 0.5)
				t.expect(#sounds == 0, "a flak monkey after %d kills", CONFIG.call_out - 1)

				kill_many(t, 1, {
					source = flak.key,
					damage_type = CONFIG.chunk_damage_type,
				})

				local called = t.wait_until(function ()
					return #sounds > 0
				end, CONFIG.call_out_delay + 1, "the flak monkey")

				t.expect(called, "no flak monkey after %d flak kills", CONFIG.call_out)
			end,
		},
		{
			name = "forty five combo kills are a combo whore",
			run = function (t)
				hurt_by_enemy(t)

				local sounds = t.sounds("ut_announcer_combo_whore")
				local rats = t.spawn_group(CONFIG.counted_breed, 15, 6)

				-- The combo's kills as the Shock Rifle reports them (ut.shock_combo_callbacks), 15 at a time
				for _ = 1, CONFIG.call_out / #rats do
					t.on_main_thread(function ()
						ut.shock_combo_callbacks.announcer(t.unit(), rats)
					end)
					t.wait(0.2)
				end

				local called = t.wait_until(function ()
					return #sounds > 0
				end, CONFIG.call_out_delay + 1, "the combo whore")

				t.expect(called, "no combo whore after %d combo kills", CONFIG.call_out)
			end,
		},
		{
			-- Only the sniper weapons' head shots count, as UT's DamTypeSniperHeadShot and DamTypeClassicHeadshot do
			name = "the head shots of other weapons are no head hunter",
			run = function (t)
				hurt_by_enemy(t)

				local sounds = t.sounds("ut_announcer_headhunter")

				kill_many(t, CONFIG.call_out, {
					source = shock.key,
					ranged = true,
					zone = "head",
				}, 0.05)
				t.wait(CONFIG.call_out_delay + 0.5)
				t.expect(#sounds == 0, "a head hunter after %d head shots with the Shock Rifle", CONFIG.call_out)
			end,
		},
		{
			name = "forty five head shots with the Sniper Rifle are a head hunter",
			run = function (t)
				hurt_by_enemy(t)

				local sounds = t.sounds("ut_announcer_headhunter")

				kill_many(t, CONFIG.call_out, {
					source = sniper.key,
					ranged = true,
					zone = "head",
				}, 0.05)

				local called = t.wait_until(function ()
					return #sounds > 0
				end, CONFIG.call_out_delay + 1, "the head hunter")

				t.expect(called, "no head hunter after %d head shots", CONFIG.call_out)
			end,
		},
		{
			name = "with the announcer off, nothing is announced",
			run = function (t)
				local was = ut:get("announcer")
				local sounds = t.sounds("ut_announcer_")

				ut:set("announcer", false)

				local ok, error_message = pcall(function ()
					kill_many(t, 3)
				end)

				ut:set("announcer", was)

				if not ok then
					error(error_message, 0)
				end

				t.expect(#sounds == 0, "the announcer was off and announced %s", table.concat(sounds, ", "))
			end,
		},
	}

	-- (each needs the announcer on, but the last, which turns it off itself)
	for i = 1, #list - 1 do
		local run = list[i].run

		list[i].run = function (t)
			if not ut:get("announcer") then
				t.skip("the announcer is turned off")
			end

			run(t)
		end
	end

	-- KillingSpreeMessage: everyone is told of a player's spree and of its end (spree.lua), whatever the announcer setting is
	list[#list + 1] = {
		name = "a spree and its end are written in the chat, with the announcer off too",
		run = function (t)
			local was = ut:get("announcer")

			hurt_by_enemy(t)
			ut:set("announcer", false)
			table.clear(chat_lines)

			recording_chat = true

			local ok, error_message = pcall(function ()
				kill_many(t, CONFIG.killing_spree, nil, 0.1)
				hurt_by_enemy(t)
			end)

			recording_chat = false
			ut:set("announcer", was)

			if not ok then
				error(error_message, 0)
			end

			local name = Managers.player:local_player():name()
			local spree_line, end_line

			for _, line in ipairs(chat_lines) do
				spree_line = spree_line or line == name .. " is on a killing spree!"
				end_line = end_line or string.find(line, name .. "'s killing spree ended by ", 1, true) == 1
			end

			t.log("chat: %s", table.concat(chat_lines, " / "))
			t.expect(spree_line, "no \"%s is on a killing spree!\" in the chat", name)
			t.expect(end_line, "no \"%s's killing spree ended by\" in the chat", name)
		end,
	}

	return list
end

-- The weapon does not matter: the kills are made by damage
runner.add_suite({
	name = "announcer",
	item = flak.key,
	template = flak.template,
	slot = "slot_ranged",
	careers = { "es_mercenary" },
	fresh_level = true,
	scenarios = scenarios(),
})
