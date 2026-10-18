local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The Minigun's in-game tests (see runner.lua), for Kruber's and Saltzpyre's. Run them with /ut_test minigun. They run in the runner's
-- level, Righteous Stand.

local runner = mod.test_runner

-- The rounds that are made while a test runs
local shots = {}
local recording = false

ut.minigun_shot_callbacks.ut_test = function (owner_unit, mode, end_position)
	if recording then
		shots[#shots + 1] = {
			mode = mode,
			time = Managers.time:time("game"),
		}
	end
end

local function record()
	table.clear(shots)

	recording = true
end

local function stop_recording()
	recording = false
end

local function scenarios()
	return {
		{
			name = "has ammo",
			run = function (t)
				local ammo = t.ammo()

				t.expect(ammo ~= nil, "the weapon has no ammo extension")
				t.expect(ammo and ammo >= 300, "the weapon has %s ammo, not 300", tostring(ammo))
			end,
		},
		{
			name = "primary fire",
			every_hero = true,
			basic = true,
			run = function (t)
				local before = t.ammo()

				record()
				t.press("action_one", 2)
				t.wait(0.3)
				stop_recording()

				-- The first round comes after the wind up of 0.27 s, and then there are 15 a second
				local expected = math.floor((2 - 0.27) * 15) + 1

				t.expect(#shots >= expected - 2 and #shots <= expected + 1, "%d rounds in 2 seconds, not about %d", #shots, expected)
				t.expect(before - (t.ammo() or 0) == #shots, "the rounds used %s ammo, not %d", tostring(before - (t.ammo() or 0)), #shots)

				if shots[1] then
					local first = shots[1].time

					mod:echo("[ut_test] first round at the first frame +%.2f s, the last at +%.2f s", 0, shots[#shots].time - first)
				end
			end,
		},
		{
			name = "alt fire",
			every_hero = true,
			run = function (t)
				record()
				t.press("action_two", 2)
				t.wait(0.3)
				stop_recording()

				local expected = math.floor((2 - 0.15) * 5) + 1

				t.expect(#shots >= expected - 1 and #shots <= expected + 1, "%d rounds in 2 seconds, not about %d", #shots, expected)
			end,
		},
		{
			-- The other button is pressed while a round runs and the first is let go: the barrels slow down to a stop and wind up again,
			-- as in UT, and the other mode fires (about 0.42 s later either way)
			name = "switching modes while firing fires the other mode",
			run = function (t)
				for _, order in ipairs({ { "action_one", "action_two", "alt" }, { "action_two", "action_one", "primary" } }) do
					local first, second, second_mode = unpack(order)

					t.hold(first)
					t.wait(1)
					record()
					t.hold(second)
					t.release(first)
					t.wait(1.5)
					t.release(second)
					stop_recording()

					local switched = 0

					for _, shot in ipairs(shots) do
						if shot.mode == second_mode then
							switched = switched + 1
						end
					end

					t.expect(switched >= 3, "%d %s rounds in 1.5 s after switching to it", switched, second_mode)
					t.wait(1)
				end
			end,
		},
		{
			name = "damages an enemy",
			run = function (t)
				local target = t.spawn_target(5)

				if not t.expect(target, "the target could not be spawned") then
					return
				end

				local health_extension = ScriptUnit.extension(target, "health_system")
				local before = health_extension:current_health()

				t.press("action_one", 0.8)
				t.wait(0.5)

				local after = HEALTH_ALIVE[target] and health_extension:current_health() or 0

				t.expect(after < before, "the target was not hurt: %s of %s", tostring(after), tostring(before))
			end,
		},
	}
end

local function hero(setting_id, careers)
	local definition = ut.items.weapons[setting_id]

	return { item = definition.key, template = definition.template, careers = careers }
end

-- Saltzpyre's Minigun differs from Kruber's only in its base weapon (the repeater pistol), so only the firing runs for him
runner.add_suite({
	name = "minigun",
	slot = "slot_ranged",
	heroes = {
		hero("minigun", { "es_mercenary", "es_huntsman", "es_knight" }),
		hero("minigun_wh", { "wh_captain", "wh_zealot", "wh_bountyhunter" }),
	},
	scenarios = scenarios(),
})
