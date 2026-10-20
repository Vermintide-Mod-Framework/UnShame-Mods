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
	announcement_wait = 2.5, -- s
}

local function amount(t)
	return adrenaline.of(t.unit()) or 0
end

-- Kills a counted enemy as the player: { zone = the hit zone, ranged = whether the hit is a ranged shot }
local function kill_one(t, how)
	how = how or {}

	local rat = t.spawn(CONFIG.counted_breed, 5)

	t.wait(1)
	t.on_main_thread(function ()
		if HEALTH_ALIVE[rat] then
			local player = t.unit()

			DamageUtils.add_damage_network(rat, player, 400, how.zone or "torso", "cutting", nil, Vector3(0, 0, -1), shock.key, nil, player, how.ranged and "instant_projectile" or nil)
		end
	end)
	t.wait(0.5)
	t.remove(rat)
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
			-- One for each level of the multi kill: three kills in a row are a double kill and a multi kill
			name = "a multi kill gives one for each level",
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

				t.expect(gained == 2, "three kills in a row gave %d, not 2", gained)
			end,
		},
		{
			name = "a head shot gives five",
			run = function (t)
				settle(t)

				local before = amount(t)

				kill_one(t, { zone = "head", ranged = true })

				local gained = amount(t) - before

				t.expect(gained == 5, "a head shot gave %d, not 5", gained)
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

				if ut:get("announcer") then
					t.expect(#sounds == 1, "Adrenalin was announced %d times, not once", #sounds)
				else
					t.log("the announcer is off: Adrenalin is not checked")
				end

				t.on_main_thread(function ()
					adrenaline.give(t.unit(), -adrenaline.max)
				end)
			end,
		},
	}

	for _, scenario in ipairs(list) do
		local run = scenario.run

		scenario.run = function (t)
			if not ut:get("adrenaline") then
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
