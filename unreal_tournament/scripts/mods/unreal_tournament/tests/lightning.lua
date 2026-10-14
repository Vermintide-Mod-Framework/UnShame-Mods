local mod = get_mod("unreal_tournament")

-- The Lightning Gun's in-game tests (see runner.lua). Run them with /ut_test lightning (Kruber's) and /ut_test lightning_dr (Bardin's).
-- They run in the level the player is in, which is the Keep.

local runner = mod.test_runner

-- Records the bolts that happen while a test runs
local bolts = {}

mod.lightning_bolt_callbacks.ut_test = function (owner_unit, end_position, hit_normal, arcs)
	if mod.test_recording then
		bolts[#bolts + 1] = {
			arcs = arcs,
			end_position = end_position,
			hit_normal = hit_normal,
			owner_unit = owner_unit,
			time = Managers.time:time("game"),
		}
	end
end

local function start_recording()
	table.clear(bolts)

	mod.test_recording = true
end

local function stop_recording()
	mod.test_recording = nil
end

local function scenarios()
	return {
		{
			name = "has ammo",
			run = function (t)
				local ammo = t.ammo()

				t.expect(ammo ~= nil, "the weapon has no ammo extension")
				t.expect(ammo and ammo > 0, "the weapon has no ammo: %s", tostring(ammo))
			end,
		},
		{
			name = "fire",
			run = function (t)
				local before = t.ammo()

				start_recording()
				t.press("action_one", 0.1)
				t.wait(0.5)
				stop_recording()

				t.expect(#bolts == 1, "%d bolts were made, not 1", #bolts)
				t.expect(before - (t.ammo() or 0) == 1, "the shot used %s ammo, not 1", tostring(before - (t.ammo() or 0)))

				if bolts[1] then
					t.expect(#bolts[1].arcs == 3 or Vector3.length(bolts[1].hit_normal) == 0, "%d arcs jumped, not 3", #bolts[1].arcs)
				end
			end,
		},
		{
			name = "fire rate",
			run = function (t)
				-- Holding the button repeats the shot every 1.6 seconds: shots at 0, 1.6, 3.2, 4.8 and 6.4
				start_recording()
				t.press("action_one", 7)
				t.wait(0.5)
				stop_recording()

				local times = {}

				for _, bolt in ipairs(bolts) do
					times[#times + 1] = string.format("%.2f", bolt.time - bolts[1].time)
				end

				t.expect(#bolts == 5, "%d bolts were made in 7.5 seconds, not 5 (at %s)", #bolts, table.concat(times, ", "))
			end,
		},
		{
			name = "no reload",
			run = function (t)
				local before = t.ammo()

				t.press("action_one", 0.1)
				t.wait(1.8)
				t.press("action_one", 0.1)
				t.wait(1.8)

				t.expect(before - (t.ammo() or 0) == 2, "two shots used %s ammo", tostring(before - (t.ammo() or 0)))
			end,
		},
		{
			name = "zoom",
			run = function (t)
				local zoom = mod.lightning.zoom

				t.expect(not zoom.zoomed, "the weapon starts zoomed")

				-- Holding the button zooms in, and letting go keeps the zoom
				t.press("action_two", 0.5)
				t.wait(0.2)

				t.expect(zoom.zoomed, "the weapon did not zoom")

				local magnification = zoom.magnification()

				t.expect(magnification > 2, "the magnification is only %.2f after half a second", magnification)
				t.wait(0.3)
				t.expect(math.abs(zoom.magnification() - magnification) < 0.001, "the zoom went on after the button was let go")

				-- Pressing it again zooms out
				t.press("action_two", 0.1)
				t.wait(0.2)

				t.expect(not zoom.zoomed, "the weapon did not zoom out")
			end,
		},
		{
			name = "damages an enemy",
			run = function (t)
				local target = t.spawn("chaos_marauder", 5)

				if not t.expect(target, "the target could not be spawned") then
					return
				end

				local health_extension = ScriptUnit.extension(target, "health_system")
				local before = health_extension:current_health()

				-- A moment for the target to settle
				t.wait(1)
				start_recording()
				t.press("action_one", 0.1)
				t.wait(1)
				stop_recording()

				local after = HEALTH_ALIVE[target] and health_extension:current_health() or 0

				t.expect(after < before, "the target was not hurt: %s of %s", tostring(after), tostring(before))
				mod:echo("[ut_test] the bolt did %s damage to a marauder with %s health", tostring(before - after), tostring(before))

				if bolts[1] then
					-- Vectors are made on the main thread, and the engine refuses them in a coroutine
					local distance = t.on_main_thread(function ()
						return Unit.alive(target) and Vector3.length(bolts[1].end_position - Unit.world_position(target, 0)) or -1
					end)

					mod:echo("[ut_test] the bolt ended %.2f m from the marauder", distance)
				end
			end,
		},
	}
end

for _, variant in ipairs({
	{
		careers = { "es_mercenary", "es_huntsman", "es_knight" },
		name = "lightning",
		setting_id = "lightning_gun",
	},
	{
		careers = { "dr_ironbreaker", "dr_ranger" },
		name = "lightning_dr",
		setting_id = "lightning_gun_dr",
	},
}) do
	local definition = mod.items.weapons[variant.setting_id]

	runner.add_suite({
		name = variant.name,
		item = definition.key,
		template = definition.template,
		slot = "slot_ranged",
		careers = variant.careers,
		scenarios = scenarios(),
	})
end
