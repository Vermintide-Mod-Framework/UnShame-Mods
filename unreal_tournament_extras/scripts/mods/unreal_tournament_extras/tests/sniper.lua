local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The Sniper Rifle's in-game tests (see runner.lua), for Kruber's and Bardin's. Run them with /ut_test sniper. They run in the runner's
-- level, Righteous Stand.

local runner = mod.test_runner

-- Records the shots that happen while a test runs: when, and whether they hit something
local shots = {}

ut.sniper.shot_callbacks.ut_test = function (owner_unit, hit_position)
	if mod.test_recording then
		shots[#shots + 1] = {
			hit = hit_position ~= nil,
			hit_position = hit_position and Vector3Box(hit_position),
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

local function scenarios()
	return {
		{
			name = "has ammo",
			run = function (t)
				local ammo = t.ammo()

				-- (some careers' talents give more ammo, as they do for every ranged weapon)
				t.expect(ammo ~= nil, "the weapon has no ammo extension")
				t.expect(ammo and ammo >= 30, "the weapon has %s ammo, not 30 or more", tostring(ammo))
			end,
		},
		{
			name = "fire",
			every_hero = true,
			basic = true,
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
			-- Where the shot is told to have hit (for the sparks and the sound) is on the target it was aimed at
			name = "the hit is on the target",
			every_hero = true,
			run = function (t)
				local target = t.spawn_target(5)

				if not t.expect(target, "the target could not be spawned") then
					return
				end

				-- (the spine is taken before the shot, as a kill throws the body)
				local spine = t.on_main_thread(function ()
					local position = Unit.world_position(target, Unit.node(target, "j_spine"))

					return { Vector3.x(position), Vector3.y(position), Vector3.z(position) }
				end)

				start_recording()
				t.press("action_one", 0.1)
				t.wait(0.5)
				stop_recording()

				if not t.expect(shots[1] and shots[1].hit, "the shot hit nothing") then
					return
				end

				local distance, from_eye = unpack(t.on_main_thread(function ()
					local hit = shots[1].hit_position:unbox()
					local first_person_extension = ScriptUnit.extension(t.unit(), "first_person_system")

					return { Vector3.distance(hit, Vector3(spine[1], spine[2], spine[3])), Vector3.distance(hit, first_person_extension:current_position()) }
				end))

				t.log("the hit is %.2f m from the target's spine and %.2f m from the eye", distance, from_eye)
				t.expect(distance < 1, "the hit is %.2f m from the target", distance)
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
				local zoom = ut.zoom

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
					body = math.min(body, t.shot_damage(false) or math.huge)
					t.wait(1)
					head = math.min(head, t.shot_damage(true) or math.huge)
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

local function hero(setting_id, careers)
	local definition = ut.items.weapons[setting_id]

	return { item = definition.key, template = definition.template, careers = careers }
end

-- Each hero's shot is a copy of their own handgun's, with its animation and where it starts, so only the firing runs for Bardin. The
-- rest is the same code for both.
runner.add_suite({
	name = "sniper",
	slot = "slot_ranged",
	heroes = {
		hero("sniper_rifle", { "es_mercenary", "es_huntsman", "es_knight" }),
		hero("sniper_rifle_dr", { "dr_ironbreaker", "dr_ranger" }),
	},
	scenarios = scenarios(),
})
