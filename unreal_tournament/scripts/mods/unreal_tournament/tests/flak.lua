local mod = get_mod("unreal_tournament")

-- The Flak Cannon's in-game tests (see runner.lua). Run them with /ut_test flak, as Kruber, in a mission.

local runner = mod.test_runner

local definition = mod.items.weapons.flak_cannon

local function is_chunk(action)
	return action.ut_flak_chunk
end

local function is_shell(action)
	return action.ut_flak_shell
end

-- Counts the distinct units that the test has seen so far
local function count(set)
	local total = 0

	for _ in pairs(set) do
		total = total + 1
	end

	return total
end

runner.add_suite({
	name = "flak",
	item = definition.key,
	template = definition.template,
	slot = "slot_ranged",
	-- The careers of the Blunderbuss that the weapon is a copy of
	careers = { "es_mercenary", "es_huntsman", "es_knight" },
	scenarios = {
		{
			name = "has ammo",
			run = function (t)
				local ammo = t.ammo()

				t.expect(ammo ~= nil, "the weapon has no ammo extension")
				t.expect(ammo and ammo > 0, "the weapon has no ammo: %s", tostring(ammo))
			end,
		},
		{
			name = "primary fire",
			run = function (t)
				local before = t.ammo()
				local chunks = {}
				local function observe()
					for _, unit in ipairs(t.projectiles(is_chunk)) do
						chunks[unit] = true
					end
				end

				t.press("action_one", 0.1, observe)
				t.watch(0.8, observe)

				t.expect(count(chunks) >= 1, "no flechettes were fired")
				t.expect(before - (t.ammo() or 0) == 1, "the shot used %s ammo, not 1", tostring(before - (t.ammo() or 0)))

				mod:echo("[ut_test] primary fire: %d flechettes seen", count(chunks))
			end,
		},
		{
			name = "shell",
			run = function (t)
				if not t.surface_ahead(25) then
					t.skip("there is nothing to shoot at ahead: face a wall or the ground")
				end

				local before = t.ammo()
				local explosions = t.explosions()
				local shells = {}
				local function observe()
					for _, unit in ipairs(t.projectiles(is_shell)) do
						shells[unit] = true
					end
				end

				t.press("action_two", 0.1, observe)

				local exploded = t.wait_until(function ()
					observe()

					for _, name in ipairs(explosions) do
						if name == "ut_flak_shell_explosion" then
							return true
						end
					end

					return false
				end, 8, "the shell to explode")

				t.expect(count(shells) == 1, "%d shells were fired, not 1", count(shells))
				t.expect(exploded, "the shell did not explode")
				t.expect(before - (t.ammo() or 0) == 1, "the shell used %s ammo, not 1", tostring(before - (t.ammo() or 0)))
			end,
		},
		{
			name = "damages a target",
			run = function (t)
				local target = t.spawn("training_dummy", 5)

				if not t.expect(target, "the target could not be spawned") then
					return
				end

				local health_extension = ScriptUnit.extension(target, "health_system")
				local before = health_extension:current_health()

				-- A moment for the target to settle
				t.wait(1)
				t.press("action_one", 0.1)
				t.wait(1.5)

				local after = HEALTH_ALIVE[target] and health_extension:current_health() or 0

				t.expect(after < before, "the target was not hurt: %s of %s", tostring(after), tostring(before))
			end,
		},
	},
})
