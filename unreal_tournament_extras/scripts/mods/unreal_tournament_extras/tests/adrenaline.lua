local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- Adrenaline's in-game tests (see runner.lua). Run them with /ut_test adrenaline. The kills are made by damage the player deals with a
-- weapon named as the damage's source. What is checked is the player's adrenaline (adrenaline.lua) as this machine, the host, knows it.

local runner = mod.test_runner
local adrenaline = ut.adrenaline
local shock = ut.items.weapons.shock_rifle
local flak = ut.items.weapons.flak_cannon

local CONFIG = {
	-- The enemy that counts as a kill
	counted_breed = "skaven_clan_rat",
	-- Longer than a multi kill's window between kills (rewards.lua)
	apart = 2, -- s
	-- The announcement of a full meter comes this long after it (and a little more)
	announcement_delay = 1.5, -- s
	announcement_wait = 2.5, -- s
	-- Another line, played this long before the announcement is due
	other_line = "ut_announcer_double_kill",
	line_before = 0.5, -- s
	-- A special and a monster to kill, damage that is as much as a hit can be, and how many such hits an enemy can take at most
	special_breed = "skaven_ratling_gunner",
	boss_breed = "skaven_rat_ogre",
	lethal = 100000,
	most_hits = 10,
}

local function amount(t)
	return adrenaline.of(t.unit()) or 0
end

-- Kills an enemy as the player: { breed = its breed (a counted one if not given), zone = the hit zone, ranged = whether the hit is a
-- ranged shot }. Returns whether it was killed.
local function kill_one(t, how)
	how = how or {}

	local rat = t.spawn(how.breed or CONFIG.counted_breed, 5)

	t.wait(1)

	if not HEALTH_ALIVE[rat] then
		return false
	end

	-- The damage of one hit is no more than the network sends (NetworkConstants.damage), which is less than a monster's health, so it
	-- takes a few hits
	for _ = 1, CONFIG.most_hits do
		t.on_main_thread(function ()
			if HEALTH_ALIVE[rat] then
				local player = t.unit()

				DamageUtils.add_damage_network(rat, player, CONFIG.lethal, how.zone or "torso", "cutting", nil, Vector3(0, 0, -1), shock.key, nil, player, how.ranged and "instant_projectile" or nil)
			end
		end)
		t.wait(0.1)

		if not HEALTH_ALIVE[rat] then
			break
		end
	end

	t.wait(0.5)

	local killed = not HEALTH_ALIVE[rat]

	t.remove(rat)

	return killed
end

-- An enemy hurts the player, which ends a spree, so that the kills of a scenario don't reach a spree's level
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

-- Starts a scenario with the level's first blood taken and no spree or multi kill going
local function settle(t)
	kill_one(t)
	hurt_by_enemy(t)
	t.wait(CONFIG.apart)
end

local function scenarios()
	local list = {
		{
			name = "plain kills give no adrenaline",
			run = function (t)
				settle(t)

				local before = amount(t)

				for _ = 1, 3 do
					kill_one(t)
					t.wait(CONFIG.apart)
				end

				t.expect(amount(t) == before, "three kills apart took the adrenaline from %d to %d", before, amount(t))
			end,
		},
		{
			-- A multi kill gives as many as its kills: three kills in a row are a double kill (2) and a multi kill (3)
			name = "a multi kill gives as many as its kills",
			run = function (t)
				settle(t)

				local before = amount(t)
				local rats = t.spawn_group(CONFIG.counted_breed, 3, 5)

				t.wait(1)

				for _, rat in ipairs(rats) do
					t.on_main_thread(function ()
						if HEALTH_ALIVE[rat] then
							local player = t.unit()

							DamageUtils.add_damage_network(rat, player, 400, "torso", "cutting", nil, Vector3(0, 0, -1), shock.key, nil, player)
						end
					end)
					t.wait(0.1)
				end

				t.wait(0.5)

				for _, rat in ipairs(rats) do
					t.remove(rat)
				end

				local gained = amount(t) - before

				t.expect(gained == 5, "three kills in a row gave %d, not 5", gained)
			end,
		},
		{
			name = "a head shot gives none",
			run = function (t)
				settle(t)

				local before = amount(t)

				kill_one(t, { zone = "head", ranged = true })

				local gained = amount(t) - before

				t.expect(gained == 0, "a head shot gave %d", gained)
			end,
		},
		{
			name = "the kill of a special gives five",
			run = function (t)
				settle(t)

				local before = amount(t)

				if t.expect(kill_one(t, { breed = CONFIG.special_breed }), "the %s could not be killed", CONFIG.special_breed) then
					local gained = amount(t) - before

					t.expect(gained == 5, "the kill of a %s gave %d, not 5", CONFIG.special_breed, gained)
				end
			end,
		},
		{
			name = "the kill of a monster gives fifty",
			run = function (t)
				settle(t)
				t.on_main_thread(function ()
					adrenaline.give(t.unit(), -adrenaline.max)
				end)

				if t.expect(kill_one(t, { breed = CONFIG.boss_breed }), "the %s could not be killed", CONFIG.boss_breed) then
					local gained = amount(t)

					t.expect(gained == 50, "the kill of a %s gave %d, not 50", CONFIG.boss_breed, gained)
				end
			end,
		},
		{
			-- Controller.AdrenalineMax, and UnrealPlayer.AwardAdrenaline's Adrenalin a moment after it fills (with the announcer on)
			name = "the meter stops at the most, and a full one is announced",
			run = function (t)
				local sounds = t.sounds("ut_announcer_adrenalin")

				t.on_main_thread(function ()
					adrenaline.give(t.unit(), -adrenaline.max)
				end)
				t.wait(0.5)
				t.on_main_thread(function ()
					adrenaline.give(t.unit(), adrenaline.max + 50)
				end)
				t.wait(CONFIG.announcement_wait)

				t.expect(amount(t) == adrenaline.max, "the adrenaline is %d, not %d", amount(t), adrenaline.max)

				if ut.option("announcer") then
					t.expect(#sounds == 1, "Adrenalin was announced %d times, not once", #sounds)
				else
					t.log("the announcer is off: Adrenalin is not checked")
				end

				t.on_main_thread(function ()
					adrenaline.give(t.unit(), -adrenaline.max)
				end)
			end,
		},
		{
			-- In UT the line is dropped if another one played in the second before it is due. Here it waits for that second to pass
			-- (announcer.lua), as the kills keep the multi kill lines coming.
			name = "Adrenalin waits for a line that played just before it was due",
			run = function (t)
				if not ut.option("announcer") then
					t.skip("the announcer is turned off")
				end

				local sounds = t.sounds("ut_announcer_")

				t.on_main_thread(function ()
					adrenaline.give(t.unit(), -adrenaline.max)
				end)
				t.wait(0.5)
				t.on_main_thread(function ()
					adrenaline.give(t.unit(), adrenaline.max)
				end)

				-- (another line, half a second before the Adrenalin line is due)
				t.wait(CONFIG.announcement_delay - CONFIG.line_before)
				t.on_main_thread(function ()
					ut.announcer.play(CONFIG.other_line, true)
				end)

				-- (when UT would have dropped it, it hasn't played yet)
				t.wait(CONFIG.line_before + 0.2)

				local early = #sounds

				t.wait(CONFIG.announcement_wait)

				t.log("lines: %s", table.concat(sounds, ", "))
				t.expect(early == 1 and sounds[1] == CONFIG.other_line, "Adrenalin played within a second of the other line (%s)", table.concat(sounds, ", "))
				t.expect(#sounds == 2 and sounds[2] == "ut_announcer_adrenalin", "Adrenalin did not play after the other line (%s)", table.concat(sounds, ", "))

				t.on_main_thread(function ()
					adrenaline.give(t.unit(), -adrenaline.max)
				end)
			end,
		},
		{
			-- A line that waits is dropped once it is no longer true: here a combo has started before it played
			name = "Adrenalin is not announced once a combo has started",
			run = function (t)
				if not ut.option("announcer") then
					t.skip("the announcer is turned off")
				end

				local sounds = t.sounds("ut_announcer_adrenalin")

				t.on_main_thread(function ()
					adrenaline.give(t.unit(), -adrenaline.max)
				end)
				t.wait(0.5)
				t.on_main_thread(function ()
					adrenaline.give(t.unit(), adrenaline.max)
				end)
				t.wait(0.5)
				t.on_main_thread(function ()
					ut.combos.start(t.unit(), "speed")
				end)
				t.wait(CONFIG.announcement_wait)

				t.expect(#sounds == 0, "Adrenalin was announced %d times during the combo", #sounds)

				-- (an empty meter ends the combo)
				t.on_main_thread(function ()
					adrenaline.give(t.unit(), -adrenaline.max)
				end)
				t.wait(0.5)
			end,
		},
	}

	for _, scenario in ipairs(list) do
		local run = scenario.run

		scenario.run = function (t)
			if not ut.option("adrenaline") then
				t.skip("adrenaline is turned off")
			end

			run(t)
		end
	end

	return list
end

-- The weapon does not matter: the kills are made by damage
runner.add_suite({
	name = "adrenaline",
	item = flak.key,
	template = flak.template,
	slot = "slot_ranged",
	careers = { "es_mercenary" },
	scenarios = scenarios(),
})
