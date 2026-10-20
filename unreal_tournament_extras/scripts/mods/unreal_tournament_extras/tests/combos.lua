local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The adrenaline combos' in-game tests (see runner.lua). Run them with /ut_test combos. A combo is started with a full meter, by its
-- keys or by combos.start, on this machine, the host.

local runner = mod.test_runner
local adrenaline = ut.adrenaline
local combos = ut.combos
local flak = ut.items.weapons.flak_cannon

local CONFIG = {
	-- How long a key is held and let go for a tap (xPlayer.CheckCombo takes taps 0.05 to 0.35 s apart)
	tap_time = 0.08, -- s
	-- How long the effects are given to come in
	settle = 0.5, -- s
	-- The Booster's heal: 5 every 0.9 s
	booster_wait = 2, -- s
	booster_hurt = 30,
	-- How long the game's revive is given (Auto Revive's own takes 3 s)
	get_up_wait = 2, -- s
	-- An enemy for the bot to see, and how long it has to start a combo (it looks once a second, and picks one at random)
	enemy_breed = "skaven_clan_rat",
	bot_wait = 5, -- s
	bot_profile = "bright_wizard",
	bot_career = 1,
	bot_item = "bw_skullstaff_fireball",
	bot_distance = -3, -- m
}

local function fill(t, unit)
	t.on_main_thread(function ()
		adrenaline.give(unit or t.unit(), adrenaline.max)
	end)
end

local function start(t, name)
	fill(t)
	t.on_main_thread(function ()
		combos.start(t.unit(), name)
	end)
	t.wait(CONFIG.settle)
end

-- Ends the player's combo by emptying the meter, which the host's drain ends it on
local function finish(t, unit)
	t.on_main_thread(function ()
		adrenaline.give(unit or t.unit(), -adrenaline.max)
	end)
	t.wait(CONFIG.settle)
end

-- The value of a stat after the character's buffs, from 1
local function stat(t, name)
	return t.on_main_thread(function ()
		return ScriptUnit.extension(t.unit(), "buff_system"):apply_buffs_to_value(1, name)
	end)
end

local function near(a, b)
	return math.abs(a - b) < 0.01
end

local function scenarios()
	return {
		{
			name = "four taps forward start the Speed combo",
			run = function (t)
				fill(t)

				for _ = 1, 4 do
					t.move(0, 1)
					t.wait(CONFIG.tap_time)
					t.move()
					t.wait(CONFIG.tap_time)
				end

				t.wait(CONFIG.settle)
				t.expect(combos.kind_of(t.unit()) == "speed", "the combo is %s", tostring(combos.kind_of(t.unit())))
				finish(t)
			end,
		},
		{
			name = "a combo drains the meter and ends when it is empty",
			run = function (t)
				start(t, "speed")

				local drained = adrenaline.max - (adrenaline.of(t.unit()) or 0)

				t.expect(drained > 0, "the meter did not go down")
				finish(t)
				t.expect(combos.kind_of(t.unit()) == nil, "the combo did not end (%s)", tostring(combos.kind_of(t.unit())))
			end,
		},
		{
			name = "Speed runs 1.4 times as fast, jumps 1.5 times as high, and dodges without a limit",
			run = function (t)
				local unit = t.unit()

				local function settings()
					return t.on_main_thread(function ()
						local movement = PlayerUnitMovementSettings.get_movement_settings_table(unit)

						return { run = movement.move_speed, jump = movement.jump.initial_vertical_speed }
					end)
				end

				local before = settings()

				start(t, "speed")

				local during = settings()
				local unlimited = ut.unlimited_dodge[unit] == true

				finish(t)

				local after = settings()

				t.log("run %.2f, %.2f, %.2f; jump %.2f, %.2f, %.2f", before.run, during.run, after.run, before.jump, during.jump, after.jump)
				t.expect(near(during.run / before.run, 1.4), "the run is %.2f times as fast", during.run / before.run)
				t.expect(near(during.jump / before.jump, 1.5), "the jump is %.2f times as high", during.jump / before.jump)
				t.expect(near(after.run, before.run) and near(after.jump, before.jump), "the movement is not back to what it was")
				t.expect(unlimited, "the dodge is limited")
				t.expect(not ut.unlimited_dodge[unit], "the dodge is still unlimited")
			end,
		},
		{
			name = "Berserk attacks a third faster, with a third more stagger, push and cleave",
			run = function (t)
				start(t, "berserk")

				for _, name in ipairs({ "attack_speed", "power_level_impact", "push_power", "power_level_melee_cleave" }) do
					local value = stat(t, name)

					t.expect(near(value, 1 / 0.75), "%s is %.3f", name, value)
				end

				finish(t)
				t.expect(near(stat(t, "attack_speed"), 1), "the attack speed is still %.3f", stat(t, "attack_speed"))
			end,
		},
		{
			name = "Booster heals and clears the wounds",
			run = function (t)
				local unit = t.unit()
				local rat = t.spawn(CONFIG.enemy_breed, 3)

				t.hurtable(true)
				t.on_main_thread(function ()
					local status_extension = ScriptUnit.extension(unit, "status_system")

					status_extension.wounds = status_extension:get_max_wounds() - 1

					DamageUtils.add_damage_network(unit, rat, CONFIG.booster_hurt, "torso", "cutting", nil, Vector3(0, 0, -1), CONFIG.enemy_breed, nil, rat)
				end)
				t.wait(0.2)
				t.remove(rat)

				local hurt = t.health()

				start(t, "booster")

				local wounded = t.on_main_thread(function ()
					return ScriptUnit.extension(unit, "status_system"):is_wounded()
				end)

				t.expect(not wounded, "the player is still wounded")
				t.wait(CONFIG.booster_wait)

				local healed = t.health()

				t.log("health %.1f, then %.1f", hurt, healed)
				t.expect(healed > hurt, "no health came back")
				finish(t)
				t.hurtable(false)
				t.heal()
			end,
		},
		{
			name = "Invisible makes the player invisible to the game, and visible again at its end",
			run = function (t)
				local function invisible()
					return t.on_main_thread(function ()
						return ScriptUnit.extension(t.unit(), "status_system"):is_invisible()
					end)
				end

				start(t, "invisible")
				t.expect(invisible(), "the player is not invisible")
				finish(t)
				t.expect(not invisible(), "the player is still invisible")
			end,
		},
		{
			name = "a knocked down player can start only the Booster, which gets them up and clears the wounds",
			run = function (t)
				local unit = t.unit()

				local function status()
					return t.on_main_thread(function ()
						local status_extension = ScriptUnit.extension(unit, "status_system")

						return { down = status_extension:is_knocked_down(), wounded = status_extension:is_wounded() }
					end)
				end

				local down = t.knock_down(flak.key)

				fill(t)
				t.on_main_thread(function ()
					combos.start(unit, "speed")
				end)

				local other = combos.kind_of(unit)

				t.on_main_thread(function ()
					combos.start(unit, "booster")
				end)

				local up = t.wait_until(function ()
					return not status().down
				end, CONFIG.get_up_wait, "the player to get up")

				t.wait(CONFIG.settle)

				local after = status()
				local kind = combos.kind_of(unit)

				finish(t)
				t.revive()
				t.expect(down, "the player was not knocked down")
				t.expect(other == nil, "the %s combo started while knocked down", tostring(other))
				t.expect(up, "the Booster did not get the player up")
				t.expect(kind == "booster", "the combo is %s", tostring(kind))
				t.expect(not after.wounded, "the player is wounded")
			end,
		},
		{
			name = "a knockdown ends the combo and empties the meter",
			run = function (t)
				start(t, "speed")

				local down = t.knock_down(flak.key)

				t.wait(CONFIG.settle)

				local kind = combos.kind_of(t.unit())
				local left = adrenaline.of(t.unit()) or 0

				t.revive()
				t.expect(down, "the player was not knocked down")
				t.expect(kind == nil, "the combo did not end (%s)", tostring(kind))
				t.expect(left == 0, "the meter has %.1f", left)
			end,
		},
		{
			name = "a bot with a full meter and an enemy starts a combo",
			run = function (t)
				local bot = t.add_bot(CONFIG.bot_profile, CONFIG.bot_career, CONFIG.bot_item, CONFIG.bot_distance, nil, true)

				if not t.expect(bot, "the bot could not be added") then
					return
				end

				local rat = t.spawn(CONFIG.enemy_breed, 6)

				-- (a bot takes an enemy as its target once it has been seen, which a calm one never is)
				t.on_main_thread(function ()
					runner.provoke(rat)
				end)
				fill(t, bot)

				local started = t.wait_until(function ()
					return combos.kind_of(bot) ~= nil
				end, CONFIG.bot_wait, "the bot to start a combo")

				if not started then
					local target = t.on_main_thread(function ()
						return ScriptUnit.extension(bot, "ai_system"):blackboard().target_unit
					end)

					t.log("the bot's target: %s, its meter: %s", tostring(target), tostring(adrenaline.of(bot)))
				end

				t.expect(started, "the bot started no combo")
				finish(t, bot)
				t.remove(rat)
			end,
		},
	}
end

runner.add_suite({
	name = "combos",
	item = flak.key,
	template = flak.template,
	slot = "slot_ranged",
	careers = { "es_mercenary" },
	scenarios = scenarios(),
})
