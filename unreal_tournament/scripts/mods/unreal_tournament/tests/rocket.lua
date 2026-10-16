local mod = get_mod("unreal_tournament")

-- The Rocket Launcher's in-game tests (see runner.lua). Run them with /ut_test rocket. They run in the runner's level, Righteous Stand.
-- The numbers expected are UT's (XWeapons/RocketFire, RocketMultiFire and RocketProj) as the mod turns them into this game's.

local runner = mod.test_runner

local definition = mod.items.weapons.rocket_launcher

local CONFIG = {
	-- All the ammo, which is all in the clip
	max_ammo = 27,
	-- A rocket's speed: 22 m/s, with this much either way
	rocket_speed = 22, -- m/s
	speed_margin = 2, -- m/s
	-- RocketFire.FireRate
	fire_rate = 0.9, -- s
	-- RocketMultiFire: a rocket is loaded at once and another every 0.95 s, up to three, and they are fired by themselves at 2.3 s
	load_interval = 0.95, -- s
	max_hold_time = 2.3, -- s
	-- The most the explosion hurts the player who fired it
	rocket_self_damage = 45,
	-- The explosion throws the player up at least this fast when it goes off at their feet
	min_jump_speed = 2, -- m/s
}

local function is_rocket(action)
	return action.ut_rocket
end

local function count_names(list, name)
	local total = 0

	for _, value in ipairs(list) do
		if value == name then
			total = total + 1
		end
	end

	return total
end

-- Watches the player's rockets from now on: the ones fired, in order, with where each was every frame and its action. A rocket of an
-- earlier shot that still flies is left out.
local function watch_rockets(t)
	local seen = {}
	local earlier = t.on_main_thread(function ()
		local units = {}

		for _, unit in ipairs(t.projectiles(is_rocket)) do
			units[unit] = true
		end

		return units
	end)

	return seen, function ()
		for _, unit in ipairs(t.projectiles(is_rocket)) do
			if not earlier[unit] then
				local extension = ScriptUnit.extension(unit, "projectile_system")
				local locomotion_extension = ScriptUnit.has_extension(unit, "projectile_locomotion_system")

				if not seen[unit] then
					seen[unit] = {
						action = extension._current_action,
						positions = {},
						-- (the enemy a homing rocket goes for)
						target = locomotion_extension and locomotion_extension.target_unit,
						true_flight = locomotion_extension and locomotion_extension.true_flight_template ~= nil,
					}
					seen[#seen + 1] = unit
				end

				local position = Unit.world_position(unit, 0)
				local positions = seen[unit].positions

				positions[#positions + 1] = {
					t = Managers.time:time("game"),
					x = Vector3.x(position),
					y = Vector3.y(position),
					z = Vector3.z(position),
				}
			end
		end
	end
end

-- Holds the secondary button for that long, watching the rockets, and lets go
local function load_and_fire(t, seconds, observe)
	t.hold("action_two")
	t.watch(seconds, observe)
	t.release("action_two")
	t.watch(0.5, observe)
end

-- The monsters the lock is tried on, and how far ahead they stand (m)
local MONSTERS = { "chaos_spawn", "skaven_rat_ogre", "chaos_troll", "skaven_stormfiend", "beastmen_minotaur" }
local MONSTER_DISTANCE = 12

-- Where each hit zone of a unit is: the first actor of the zone, as { zone, x, y, z }. The afro (the zone around the whole body for near
-- misses) and aux (not a part of the body) are left out.
local NOT_BODY = {
	afro = true,
	aux = true,
}
local function hit_zone_points(t, unit)
	return t.on_main_thread(function ()
		local breed = Unit.get_data(unit, "breed")
		local points = {}

		for zone, data in pairs(breed and breed.hit_zones or {}) do
			local actor_name = data.actors and data.actors[1]
			local actor = not NOT_BODY[zone] and actor_name and Unit.actor(unit, actor_name)

			if actor then
				local position = Actor.position(actor)

				points[#points + 1] = { zone, Vector3.x(position), Vector3.y(position), Vector3.z(position) }
			end
		end

		table.sort(points, function (a, b)
			return a[1] < b[1]
		end)

		return points
	end)
end

-- Holds the secondary button with the crosshair on a point of a monster, and says whether the lock came and which enemies the rockets
-- went for. The rockets are fired at the end, and the lock is gone once they have landed.
local function locks_on(t, x, y, z)
	local locked = false

	mod.rocket_lock_callbacks.ut_test = function (owner_unit, is_locked)
		if owner_unit == t.unit() and is_locked then
			locked = true
		end
	end

	local rockets, observe = watch_rockets(t)

	t.aim_at_point(x, y, z)
	t.hold("action_two")
	t.watch(1.2, observe)
	t.release("action_two")
	t.watch(2, observe)

	mod.rocket_lock_callbacks.ut_test = nil

	local targets = {}

	for _, unit in ipairs(rockets) do
		targets[#targets + 1] = rockets[unit].target or false
	end

	return locked, targets
end

-- Where the rats of a crowd stand, as { ahead, right } from the player in meters: in front of the monster beside the way to it, at its
-- sides, and behind it
local CROWD = { { 8, -1.2 }, { 9, 1.4 }, { 11, -2.5 }, { 12, 2.5 }, { 15, -1 }, { 16, 1.5 } }

local function monster_scenario(breed_name, crowded)
	return {
		name = "a lock on a " .. breed_name .. " wherever the crosshair is on its body" .. (crowded and ", with rats around it" or ""),
		run = function (t)
			local monster = t.spawn(breed_name, MONSTER_DISTANCE)

			if not t.expect(monster, "the %s could not be spawned", breed_name) then
				return
			end

			t.wait(3)

			for _, point in ipairs(hit_zone_points(t, monster)) do
				-- (each try fires its rockets, so the ammo is filled again, and the rats are made again)
				t.refill()

				local rats = {}

				if crowded then
					t.look(0)

					for _, place in ipairs(CROWD) do
						local ground = t.ground_at(place[1], place[2])

						rats[#rats + 1] = ground and t.spawn_at("skaven_clan_rat", ground[1], ground[2], ground[3])
					end

					t.wait(1)
				end

				if HEALTH_ALIVE[monster] then
					local locked, targets = locks_on(t, point[2], point[3], point[4])
					local others = 0

					for _, target in ipairs(targets) do
						if target ~= monster then
							others = others + 1
						end
					end

					t.expect(locked, "no lock with the crosshair on its %s", point[1])
					t.expect(#targets > 0 and others == 0, "with the crosshair on its %s, %d of %d rockets went for another enemy or none", point[1], others, #targets)
				end

				for _, rat in ipairs(rats) do
					t.remove(rat)
				end
			end
		end,
	}
end

local function scenarios()
	local list = {
		{
			name = "all the ammo is in the clip",
			run = function (t)
				local ammo = t.on_main_thread(function ()
					local inventory_extension = ScriptUnit.extension(t.unit(), "inventory_system")
					local slot_data = inventory_extension:get_slot_data("slot_ranged")
					local ammo_extension = GearUtils.get_ammo_extension(slot_data.right_unit_1p, slot_data.left_unit_1p)

					return { ammo_extension:ammo_count(), ammo_extension:total_remaining_ammo() }
				end)
				local clip, total = ammo[1], ammo[2]

				t.expect(total >= CONFIG.max_ammo, "the launcher holds %s, less than %d", tostring(total), CONFIG.max_ammo)
				t.expect(clip == total, "%s of the %s are in the clip: there is a reload", tostring(clip), tostring(total))
			end,
		},
		{
			name = "a rocket flies straight at its speed and explodes where it hits",
			run = function (t)
				t.look(0)

				local before = t.ammo()
				local rockets, observe = watch_rockets(t)
				local explosions = t.explosions()

				t.press("action_one", 0.1, observe)
				t.watch(0.5, observe)

				t.expect(#rockets == 1, "%d rockets were fired, not 1", #rockets)
				t.expect(before - (t.ammo() or 0) == 1, "the shot used %s ammo, not 1", tostring(before - (t.ammo() or 0)))

				local positions = rockets[1] and rockets[rockets[1]].positions

				if positions and #positions >= 5 then
					local first, last = positions[2], positions[#positions]
					local time = last.t - first.t
					local speed = math.sqrt((last.x - first.x) ^ 2 + (last.y - first.y) ^ 2 + (last.z - first.z) ^ 2) / time

					t.expect(math.abs(speed - CONFIG.rocket_speed) <= CONFIG.speed_margin, "the rocket flew %.1f m/s, not %.1f", speed, CONFIG.rocket_speed)
					t.expect(math.abs(last.z - first.z) < 0.15, "the rocket fell %.2f m in %.2f s", first.z - last.z, time)
				else
					t.expect(false, "the rocket was not seen in flight long enough")
				end

				-- (it flies 28 m across the square and hits the houses)
				t.wait_until(function ()
					return count_names(explosions, "ut_rocket_explosion") > 0
				end, 4, "the rocket to explode")
				t.expect(count_names(explosions, "ut_rocket_explosion") == 1, "the rocket made %d explosions, not 1", count_names(explosions, "ut_rocket_explosion"))
			end,
		},
		{
			name = "a rocket hurts an enemy",
			run = function (t)
				local target = t.spawn_target(6)

				if not t.expect(target, "the target could not be spawned") then
					return
				end

				local damage = t.track_damage(target)

				t.press("action_one", 0.1)
				t.wait(1)

				t.expect(damage.total > 0, "the target was not hurt")
			end,
		},
		{
			name = "holding primary fire repeats it at its fire rate",
			run = function (t)
				t.look(20)

				local before = t.ammo()

				-- (shots at 0, 0.9 and 1.8 s)
				t.press("action_one", 2)
				t.wait(0.3)

				t.expect(before - (t.ammo() or 0) == 3, "%s shots in 2 s, not 3", tostring(before - (t.ammo() or 0)))
			end,
		},
		{
			name = "the secondary button loads one rocket, then one more each 0.95 s",
			run = function (t)
				t.look(20)

				for _, case in ipairs({ { 0.4, 1 }, { 1.3, 2 }, { 2.1, 3 } }) do
					local before = t.ammo()
					local rockets, observe = watch_rockets(t)

					load_and_fire(t, case[1], observe)

					t.expect(#rockets == case[2], "held %.1f s, %d rockets were fired, not %d", case[1], #rockets, case[2])
					t.expect(before - (t.ammo() or 0) == case[2], "held %.1f s, %s ammo was used, not %d", case[1], tostring(before - (t.ammo() or 0)), case[2])

					-- (the launcher can load again after the salvo's fire rate)
					t.wait(1)
				end
			end,
		},
		{
			name = "loaded rockets are fired by themselves, and holding on loads no more",
			run = function (t)
				t.look(20)

				local before = t.ammo()
				local rockets, observe = watch_rockets(t)
				local fired_at

				t.hold("action_two")

				local start = Managers.time:time("game")

				t.watch(CONFIG.max_hold_time + 2, function ()
					observe()

					fired_at = fired_at or #rockets > 0 and Managers.time:time("game") - start or nil
				end)
				t.release("action_two")
				t.watch(0.5, observe)

				t.expect(#rockets == 3, "%d rockets were fired, not 3", #rockets)
				t.expect(fired_at and math.abs(fired_at - CONFIG.max_hold_time) < 0.2, "they were fired %s s into the hold, not at %.1f", tostring(fired_at), CONFIG.max_hold_time)
				t.expect(before - (t.ammo() or 0) == 3, "%s ammo was used, not 3", tostring(before - (t.ammo() or 0)))
			end,
		},
		{
			name = "the primary button while loading makes a spiral",
			run = function (t)
				t.look(20)

				local rockets, observe = watch_rockets(t)

				t.hold("action_two")
				t.watch(0.3, observe)
				t.press("action_one", 0.1, observe)
				t.watch(1.8, observe)
				t.release("action_two")
				t.watch(0.5, observe)

				local spirals = 0

				for _, unit in ipairs(rockets) do
					if rockets[unit].action.ut_rocket_spiral then
						spirals = spirals + 1
					end
				end

				t.expect(#rockets == 3, "%d rockets were fired, not 3", #rockets)
				t.expect(spirals == #rockets, "%d of %d rockets were a spiral", spirals, #rockets)
			end,
		},
		{
			name = "a lock on an enemy makes the rockets home in on it",
			run = function (t)
				-- (a real clan rat: the dummy is not one to aim at, no_autoaim, which the lock follows)
				local target = t.spawn("skaven_clan_rat", 12)

				if not t.expect(target, "the target could not be spawned") then
					return
				end

				t.wait(1)
				t.aim_at(target)

				local locked = false

				mod.rocket_lock_callbacks.ut_test = function (owner_unit, is_locked)
					if owner_unit == t.unit() then
						locked = is_locked
					end
				end

				local rockets, observe = watch_rockets(t)
				local damage = t.track_damage(target)

				-- Loading with the aim on the enemy locks on. Then the aim is turned away, and the rockets fired that way still go to it.
				t.hold("action_two")
				t.watch(1.2, observe)
				t.expect(locked, "no lock after 1.2 s on the enemy")
				t.look(10, 30)
				t.release("action_two")
				t.watch(2, observe)

				mod.rocket_lock_callbacks.ut_test = nil

				local homing = 0

				for _, unit in ipairs(rockets) do
					if rockets[unit].true_flight then
						homing = homing + 1
					end
				end

				t.expect(#rockets == 2, "%d rockets were fired, not 2", #rockets)
				t.expect(homing == #rockets and homing > 0, "%d of %d rockets homed in", homing, #rockets)
				t.expect(damage.total > 0, "the rockets fired away from the enemy did not reach it")
			end,
		},
		{
			name = "a rocket at the feet hurts the player and throws them up",
			run = function (t)
				t.hurtable(true)
				t.look(-85)

				local up = 0
				local taken = t.track_damage(t.unit())

				t.press("action_one", 0.05)
				t.watch(0.5, function ()
					local _, _, z = t.velocity()

					up = math.max(up, z)
				end)

				local blast = taken.hits[1]

				t.expect(blast, "the rocket's explosion did not hurt the player")
				t.expect(not blast or blast.amount <= CONFIG.rocket_self_damage + 0.5, "the rocket hurt the player %.1f, more than %d", blast and blast.amount or 0, CONFIG.rocket_self_damage)
				t.expect(#taken.hits <= 1, "the rocket hurt the player %d times", #taken.hits)
				t.expect(up >= CONFIG.min_jump_speed, "the rocket threw the player up at %.1f m/s at most", up)
			end,
		},
	}

	for _, breed_name in ipairs(MONSTERS) do
		list[#list + 1] = monster_scenario(breed_name)
		list[#list + 1] = monster_scenario(breed_name, true)
	end

	return list
end

runner.add_suite({
	name = "rocket",
	item = definition.key,
	template = definition.template,
	slot = "slot_ranged",
	careers = { "wh_captain" },
	scenarios = scenarios(),
})
