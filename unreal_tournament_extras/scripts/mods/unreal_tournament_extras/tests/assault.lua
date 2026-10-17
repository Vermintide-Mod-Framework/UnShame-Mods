local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The Assault Rifle's in-game tests (see runner.lua). Run them with /ut_test assault. They run in the runner's level, Righteous Stand.

local runner = mod.test_runner
local assault = ut.assault

-- The rounds and the grenade explosions that are made while a test runs
local rounds = 0
local explosions = 0
local recording = false

ut.assault_round_callbacks.ut_test = function (owner_unit)
	if recording and Managers.player:local_player().player_unit == owner_unit then
		rounds = rounds + 1
	end
end

ut.any_explosion_callbacks.ut_test_assault = function (explosion_template)
	if recording and explosion_template.name == assault.explosion then
		explosions = explosions + 1
	end
end

local function scenarios()
	return {
		{
			name = "holds 200 rounds",
			run = function (t)
				-- (a career's own bonus adds to it: the Bounty Hunter carries half as much again)
				t.expect(t.ammo() and t.ammo() >= 200, "the rifle holds %s rounds, not 200", tostring(t.ammo()))
			end,
		},
		{
			name = "fire rate",
			basic = true,
			run = function (t)
				rounds = 0
				recording = true

				-- Held for a second, the two rifles fire about 1 / 0.088 rounds
				t.press("action_one", 1)
				t.wait(0.2)

				recording = false

				t.expect(rounds >= 10 and rounds <= 13, "%d rounds in a second, not 11 or so", rounds)
			end,
		},
		{
			name = "grenade",
			run = function (t)
				local before = assault.grenade_count

				explosions = 0
				recording = true

				-- A grenade lobbed ahead bounces and goes off two seconds after it first touches something
				t.press("action_two", 0.3)
				t.wait(5)

				recording = false

				t.expect(assault.grenade_count == before - 1, "the grenade count went from %d to %d, not down by 1", before, assault.grenade_count)
				t.expect(explosions == 1, "%d grenades went off, not 1", explosions)
			end,
		},
	}
end

local definition = ut.items.weapons.assault_rifle

runner.add_suite({
	name = "assault",
	item = definition.key,
	template = definition.template,
	slot = "slot_ranged",
	careers = { "wh_captain", "wh_zealot", "wh_bountyhunter" },
	scenarios = scenarios(),
})
