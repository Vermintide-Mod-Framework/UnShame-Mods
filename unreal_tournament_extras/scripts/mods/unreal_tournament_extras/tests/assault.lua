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
			-- A round hits at once, with the rifle's damage: it fires none of the game's projectiles (the pistols' shot does, with its
			-- tracer), and every hit on the enemy is the round's (ut_assault_bullet's damage type)
			name = "a round hits at once, with the rifle's damage",
			run = function (t)
				local enemy = t.spawn("chaos_marauder", 6)

				if not t.expect(enemy, "the enemy could not be spawned") then
					return
				end

				t.wait(1)
				t.aim_at(enemy)

				local damage = t.track_damage(enemy)
				local projectiles = 0

				t.press("action_one", 0.3, function ()
					projectiles = math.max(projectiles, #t.projectiles(function ()
						return true
					end))
				end)
				t.wait(0.5)

				local others = 0

				for _, hit in ipairs(damage.hits) do
					if hit.type ~= "shot_shotgun" then
						others = others + 1
					end
				end

				t.expect(projectiles == 0, "%d projectiles flew", projectiles)
				t.expect(#damage.hits > 0, "the rounds did not hurt the enemy")
				t.expect(others == 0, "%d of %d hits were not the round's", others, #damage.hits)
			end,
		},
		{
			-- AssaultRifle.ChargeBar: the grenade's charge fills the bar over the time its speed takes to reach its most (1 s)
			name = "the grenade's charge fills the charge bar",
			run = function (t)
				local charge_of = ut.charge_bars[assault.template_name]
				local fraction

				t.hold("action_two")
				t.wait(0.5)

				fraction = charge_of(t.unit()).fraction

				t.release("action_two")
				t.wait(1)

				t.expect(math.abs(fraction - 0.5) < 0.15, "the bar was %.2f full after 0.5 s, not 0.5", fraction)
				t.expect(charge_of(t.unit()).fraction == 0, "the bar is not empty once the grenade is thrown")
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
		{
			-- The game refuses a pickup of ammo while the ammo is full. With all the rounds but a grenade missing, it is not full, and the
			-- pickup gives the grenades back.
			name = "with all the rounds, a pickup of ammo gives back the grenades",
			run = function (t)
				-- (all the rounds first: the scenarios before fire them)
				t.on_main_thread(function ()
					ScriptUnit.extension(t.unit(), "inventory_system"):add_ammo_from_pickup(Pickups.ammo.all_ammo)
				end)
				t.wait(1)
				t.press("action_two", 0.3)
				t.wait(1)

				local missing = t.on_main_thread(function ()
					local inventory_extension = ScriptUnit.extension(t.unit(), "inventory_system")
					local rounds_full = true

					for _, slot_data in pairs(inventory_extension:equipment().slots) do
						local unit = slot_data.right_unit_1p or slot_data.left_unit_1p
						local ammo_extension = unit and ScriptUnit.has_extension(unit, "ammo_system")

						if ammo_extension and not ammo_extension:full_ammo() then
							rounds_full = false
						end
					end

					return { rounds_full, inventory_extension:has_full_ammo() }
				end)

				t.expect(assault.grenade_count < assault.max_grenades, "no grenade was thrown")
				t.expect(missing[1], "the rounds are not full")
				t.expect(not missing[2], "the ammo is full with %d of %d grenades", assault.grenade_count, assault.max_grenades)

				t.on_main_thread(function ()
					ScriptUnit.extension(t.unit(), "inventory_system"):add_ammo_from_pickup(Pickups.ammo.all_ammo)
				end)

				t.expect(assault.grenade_count == assault.max_grenades, "the pickup left %d of %d grenades", assault.grenade_count, assault.max_grenades)
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
