local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The Lightning Gun's in-game tests (see runner.lua), for each of Kerillian's careers. Run them with /ut_test lightning. They run in the
-- runner's level, Righteous Stand.

local runner = mod.test_runner

-- Records the bolts that happen while a test runs. The vectors are kept in boxes, as a vector only lasts its frame. The arcs are only
-- counted.
local bolts = {}

ut.lightning_bolt_callbacks.ut_test = function (owner_unit, end_position, hit_normal, arcs)
	if mod.test_recording then
		bolts[#bolts + 1] = {
			arc_count = #arcs,
			end_position = Vector3Box(end_position),
			hit = Vector3.length(hit_normal) > 0,
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

-- Whether the player's gun is locked out by overheating. It is asked from the scenario and from a wait's condition, which the runner
-- calls on the main thread already.
local function locked_out(t)
	local function check()
		local overcharge_extension = ScriptUnit.extension(t.unit(), "overcharge_system")

		return overcharge_extension:are_you_locked_out()
	end

	if coroutine.running() then
		return t.on_main_thread(check)
	end

	return check()
end

-- Spawns a target, aims at its head or its middle, fires once, and returns the damage it took
local function bolt_damage(t, at_head)
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
			-- A hit on the head does twice the damage of a hit on the body (SniperFire.HeadShotDamageMult), or more with a career's
			-- talents
			name = "head shots do double damage",
			run = function (t)
				-- The smallest of three bolts each, which leaves out critical hits (the Shade's passive makes them common)
				local body, head = math.huge, math.huge

				for _ = 1, 3 do
					body = math.min(body, bolt_damage(t, false) or math.huge)
					t.wait(1.8)
					head = math.min(head, bolt_damage(t, true) or math.huge)
					t.wait(1.8)
				end

				if body == math.huge or head == math.huge then
					return
				end

				t.log("a bolt to the body did %.1f, to the head %.1f", body, head)
				t.expect(body > 0, "the bolt to the body did no damage")
				t.expect(head >= body * 1.8, "the bolt to the head did %.1f, not twice the %.1f of the body", head, body)
			end,
		},
		{
			name = "fire",
			run = function (t)
				local before = t.overcharge()

				start_recording()
				t.press("action_one", 0.1)
				t.wait(0.5)
				stop_recording()

				local heat = t.overcharge() - before
				local cost = PlayerUnitStatusSettings.overcharge_values.ut_lightning_bolt

				t.expect(#bolts == 1, "%d bolts were made, not 1", #bolts)
				-- (the heat starts to cool half a second after the shot)
				t.expect(math.abs(heat - cost) <= cost * 0.1, "the shot added %.2f heat, not %.2f", heat, cost)

				if bolts[1] then
					t.expect(bolts[1].arc_count == 3 or not bolts[1].hit, "%d arcs jumped, not 3", bolts[1].arc_count)
				end
			end,
		},
		{
			name = "fire rate",
			run = function (t)
				-- Holding the button repeats the shot every 1.6 seconds: shots at 0, 1.6, 3.2 and 4.8. A fifth would heat the gun to the
				-- top.
				start_recording()
				t.press("action_one", 5.3)
				t.wait(0.5)
				stop_recording()

				local times = {}

				for _, bolt in ipairs(bolts) do
					times[#times + 1] = string.format("%.2f", bolt.time - bolts[1].time)
				end

				t.expect(#bolts == 4, "%d bolts were made in 5.8 seconds, not 4 (at %s)", #bolts, table.concat(times, ", "))
				t.expect(not locked_out(t), "four bolts overheated the gun")
			end,
		},
		{
			-- The Deepwood Staff's overheat: the player loses 40% of their health, and the gun is locked out until the heat is gone. Bolts
			-- can't be fired while it is. The heat cools between bolts, so it takes 7 at the fire rate.
			name = "overheating locks the gun out",
			run = function (t)
				t.hurtable(true)
				t.heal()

				local health = t.health()

				start_recording()
				t.hold("action_one")

				local overheated = t.wait_until(function ()
					return locked_out(t)
				end, 15, "the gun to overheat")

				t.release("action_one")
				t.wait(0.5)
				stop_recording()

				local fired = #bolts

				t.expect(overheated, "%d bolts did not overheat the gun (heat %.1f)", fired, t.overcharge())
				t.expect(fired == 7, "%d bolts were fired before the gun overheated, not 7", fired)

				local lost = health - t.health()

				t.log("%d bolts, the overheat took %.0f of %.0f health", fired, lost, health)
				t.expect(math.abs(lost / health - 0.4) < 0.05, "overheating took %.0f%% of the player's health, not 40%%", lost / health * 100)

				start_recording()
				t.press("action_one", 1)
				t.wait(0.3)
				stop_recording()

				t.expect(#bolts == 0, "%d bolts were fired while the gun was locked out", #bolts)

				t.expect(t.wait_until(function ()
					return not locked_out(t)
				end, 30, "the lockout to end"), "the gun was still locked out after 30 seconds")
			end,
		},
		{
			name = "venting removes heat",
			run = function (t)
				t.press("action_one", 0.1)
				t.wait(1.8)
				t.press("action_one", 0.1)
				t.wait(0.3)

				local before = t.overcharge()

				t.press("weapon_reload", 1.5)
				t.wait(0.2)

				local after = t.overcharge()

				t.log("venting took the heat from %.1f to %.1f", before, after)
				t.expect(after < before * 0.5, "venting took the heat only from %.1f to %.1f", before, after)
			end,
		},
		{
			name = "zoom",
			run = function (t)
				local zoom = ut.lightning.zoom

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
				local target = t.spawn_target(5)

				if not t.expect(target, "the target could not be spawned") then
					return
				end

				local health_extension = ScriptUnit.extension(target, "health_system")
				local before = health_extension:current_health()

				start_recording()
				t.press("action_one", 0.1)
				t.wait(1)
				stop_recording()

				local after = HEALTH_ALIVE[target] and health_extension:current_health() or 0

				t.expect(after < before, "the target was not hurt: %s of %s", tostring(after), tostring(before))
				mod:echo("[ut_test] the bolt did %s damage to a target with %s health", tostring(before - after), tostring(before))

				if bolts[1] then
					-- Vectors are made on the main thread, and the engine refuses them in a coroutine
					-- Where the bolt ended and where the target is, from the player's eyes: how far ahead and how far up
					local report = t.on_main_thread(function ()
						local first_person_extension = ScriptUnit.extension(t.unit(), "first_person_system")
						local eyes = first_person_extension:current_position()
						local target_position = Unit.alive(target) and Unit.world_position(target, 0) or eyes
						local ahead = Vector3.normalize(Vector3.flat(target_position - eyes))
						local bolt_end = bolts[1].end_position:unbox() - eyes
						local to_target = target_position - eyes

						local pitch = math.deg(math.asin(Vector3.z(Quaternion.forward(first_person_extension:current_rotation()))))

						return string.format("the bolt ended %.2f m ahead and %.2f m up, the target's feet are %.2f m ahead and %.2f m up (%s); the view is %.1f degrees up", Vector3.dot(bolt_end, ahead), Vector3.z(bolt_end), Vector3.dot(to_target, ahead), Vector3.z(to_target), bolts[1].hit and "it hit something" or "it hit nothing", pitch)
					end)

					mod:echo("[ut_test] %s", report)
				end
			end,
		},
	}
end

for _, variant in ipairs({
	{
		careers = { "we_waywatcher", "we_thornsister", "we_shade", "we_maidenguard" },
		name = "lightning",
		setting_id = "lightning_gun",
	},
}) do
	local definition = ut.items.weapons[variant.setting_id]

	runner.add_suite({
		name = variant.name,
		item = definition.key,
		template = definition.template,
		slot = "slot_ranged",
		careers = variant.careers,
		scenarios = scenarios(),
	})
end
