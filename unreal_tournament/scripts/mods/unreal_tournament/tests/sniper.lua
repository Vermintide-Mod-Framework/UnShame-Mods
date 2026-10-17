local mod = get_mod("unreal_tournament")

-- The Sniper Rifle's in-game tests (see runner.lua). Run them with /ut_test sniper (Kruber's) and /ut_test sniper_dr (Bardin's). They run
-- in the runner's level, Righteous Stand.

local runner = mod.test_runner

-- Records the shots that happen while a test runs: when, and whether they hit something
local shots = {}

mod.sniper.shot_callbacks.ut_test = function (owner_unit, hit_position)
	if mod.test_recording then
		shots[#shots + 1] = {
			hit = hit_position ~= nil,
			owner_unit = owner_unit,
			time = Managers.time:time("game"),
		}
	end
end

local function start_recording()
	table.clear(shots)

	mod.test_recording = true
end

local function stop_recording()
	mod.test_recording = nil
end

-- Spawns a target, aims at its head or its middle, fires once, and returns the damage it took
local function shot_damage(t, at_head)
	local target = t.spawn_target(5)

	if not t.expect(target, "the target could not be spawned") then
		return nil
	end

	if at_head then
		local head = t.on_main_thread(function ()
			local position = Unit.world_position(target, Unit.node(target, "j_head"))

			return { Vector3.x(position), Vector3.y(position), Vector3.z(position) }
		end)

		t.aim_at_point(head[1], head[2], head[3])
	end

	local damage = t.track_damage(target)

	t.press("action_one", 0.1)
	t.wait(0.5)
	t.remove(target)

	return damage.total
end

local function scenarios()
	return {
		{
			name = "has ammo",
			run = function (t)
				local ammo = t.ammo()

				-- (some careers' talents give more ammo, as they do for every ranged weapon)
				t.expect(ammo ~= nil, "the weapon has no ammo extension")
				t.expect(ammo and ammo >= 35, "the weapon has %s ammo, not 35 or more", tostring(ammo))
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

				t.expect(#shots == 1, "%d shots were made, not 1", #shots)
				t.expect(before - (t.ammo() or 0) == 1, "the shot used %s ammo, not 1", tostring(before - (t.ammo() or 0)))
			end,
		},
		{
			name = "fire rate",
			run = function (t)
				-- Holding the button repeats the shot every 1.33 seconds: shots at 0, 1.33, 2.66, 3.99 and 5.32
				start_recording()
				t.press("action_one", 6)
				t.wait(0.5)
				stop_recording()

				local times = {}

				for _, shot in ipairs(shots) do
					times[#times + 1] = string.format("%.2f", shot.time - shots[1].time)
				end

				t.expect(#shots == 5, "%d shots were made in 6.5 seconds, not 5 (at %s)", #shots, table.concat(times, ", "))
			end,
		},
		{
			name = "no reload",
			run = function (t)
				local before = t.ammo()

				t.press("action_one", 0.1)
				t.wait(1.5)
				t.press("action_one", 0.1)
				t.wait(1.5)

				t.expect(before - (t.ammo() or 0) == 2, "two shots used %s ammo", tostring(before - (t.ammo() or 0)))
			end,
		},
		{
			name = "zoom",
			run = function (t)
				local zoom = mod.zoom

				t.expect(not zoom.zoomed, "the weapon starts zoomed")

				-- Holding the button zooms in, and letting go keeps the zoom
				t.press("action_two", 0.5)
				t.wait(0.2)

				t.expect(zoom.zoomed, "the weapon did not zoom")
				t.expect(zoom.magnification() > 2, "the magnification is only %.2f after half a second", zoom.magnification())

				-- Pressing it again zooms out
				t.press("action_two", 0.1)
				t.wait(0.2)

				t.expect(not zoom.zoomed, "the weapon did not zoom out")
			end,
		},
		{
			-- A hit on the head does twice the damage of a hit on the body (HeadShotDamageMult), or more with a career's talents
			name = "head shots do double damage",
			run = function (t)
				-- The smallest of three shots each, which leaves out critical hits
				local body, head = math.huge, math.huge

				for _ = 1, 3 do
					body = math.min(body, shot_damage(t, false) or math.huge)
					t.wait(1)
					head = math.min(head, shot_damage(t, true) or math.huge)
					t.wait(1)
				end

				if body == math.huge or head == math.huge then
					return
				end

				t.log("a shot to the body did %.1f, to the head %.1f", body, head)
				t.expect(body > 0, "the shot to the body did no damage")
				t.expect(head >= body * 1.8, "the shot to the head did %.1f, not twice the %.1f of the body", head, body)
			end,
		},
	}
end

for _, variant in ipairs({
	{
		careers = { "es_mercenary", "es_huntsman", "es_knight" },
		name = "sniper",
		setting_id = "sniper_rifle",
	},
	{
		careers = { "dr_ironbreaker", "dr_ranger" },
		name = "sniper_dr",
		setting_id = "sniper_rifle_dr",
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
