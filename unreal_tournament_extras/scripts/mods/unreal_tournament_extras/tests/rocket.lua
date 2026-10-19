local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The Rocket Launcher's in-game tests (see runner.lua). Run them with /ut_test rocket. They run in the runner's level, Righteous Stand.
-- The numbers expected are UT's (XWeapons/RocketFire, RocketMultiFire and RocketProj) as the mod turns them into this game's.

local runner = mod.test_runner
local utils = ut.utils

local definition = ut.items.weapons.rocket_launcher

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
	-- The explosion's damage against armour and monsters, of its damage against an enemy with none (a Chaos marauder), with this much
	-- either way (rocket_launcher.lua's rocket_armor_attack). A Stormvermin is armoured, a Chaos warrior's body is super armour, and a rat
	-- ogre is a monster and a boss, whose damage the game takes down to 0.45 (DamageUtils.calculate_damage's boss_damage_reduction).
	plain_breed = "chaos_marauder",
	armour_breeds = {
		{ "skaven_storm_vermin", 1 },
		{ "chaos_warrior", 0.5 },
		{ "skaven_rat_ogre", 1.5 * 0.45 },
	},
	armour_margin = 0.1,
	-- The bodies weighed: the reference (a UT player's size), a lighter one and a heavier one, and how long a body has to fall
	ragdoll_breeds = { "chaos_marauder", "skaven_clan_rat", "chaos_warrior" },
	ragdoll_wait = 3, -- s
	-- How far ahead the enemies that are shot stand
	enemy_distance = 6, -- m
	-- Where a rocket starts from the eye: to the right and below (rocket_launcher.lua's start_right and start_down)
	rocket_start_right = 0.35, -- m
	rocket_start_down = 0.18, -- m
	-- The explosion: the enemies beside the one it hits, this far from it (inside the radius of 150 UT units, 3 m, and outside)
	inside_radius = 1.5, -- m
	outside_radius = 3.8, -- m
	-- A critical rocket does the same damage as a plain one, within this share
	crit_margin = 0.05,
}

-- The horde of "firing into a horde" (t.fight_horde)
local HORDE = {
	size = 60,
	breeds = { "skaven_clan_rat", "skaven_slave" },
	refill_below = 40,
	distance = 8, -- m
	keep = 5, -- m
	time = 240, -- s
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

-- The monsters the lock is tried on, and how far ahead they stand (m). The Chaos Spawn is the biggest and the most spread out.
local MONSTERS = { "chaos_spawn" }
-- (close, so that its head and limbs are well off the aim at its middle)
local MONSTER_DISTANCE = 7

-- Where each hit zone of a unit is: the middle of the first actor of the zone (its origin is at a joint, which can be at the edge of the
-- part), as { zone, x, y, z }. The afro (the zone around the whole body for near misses) and aux (not a part of the body) are left out.
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
				local position = Actor.center_of_mass(actor)

				points[#points + 1] = { zone, Vector3.x(position), Vector3.y(position), Vector3.z(position) }
			end
		end

		table.sort(points, function (a, b)
			return a[1] < b[1]
		end)

		return points
	end)
end

-- The unit the crosshair is on: the first thing a ray along the aim meets that is the level or an enemy's body (not its afro), as the
-- lock looks for it
local function under_crosshair(t)
	return t.on_main_thread(function ()
		local first_person_extension = ScriptUnit.extension(t.unit(), "first_person_system")
		local physics_world = World.get_data(Managers.world:world("level_world"), "physics_world")
		local hits = PhysicsWorld.immediate_raycast_actors(physics_world, first_person_extension:current_position(), Quaternion.forward(first_person_extension:current_rotation()), 50, "static_collision_filter", "filter_player_ray_projectile_static_only", "dynamic_collision_filter", "filter_player_ray_projectile_ai_only", "dynamic_collision_filter", "filter_player_ray_projectile_hitbox_only")
		local hit = utils.first_beam_hit(hits, t.unit())

		return hit and ActionUtils.redirect_shield_hit(Actor.unit(hit[4]), hit[4])
	end)
end

-- Holds the secondary button where the crosshair is, and says whether the lock came and which enemies the rockets went for. The rockets
-- are fired at the end, and the lock is gone once they have landed.
local function locks_on(t)
	local locked = false

	ut.rocket_lock_callbacks.ut_test = function (owner_unit, is_locked)
		if owner_unit == t.unit() and is_locked then
			locked = true
		end
	end

	local rockets, observe = watch_rockets(t)

	t.hold("action_two")
	t.watch(1.2, observe)
	t.release("action_two")
	t.watch(2, observe)

	ut.rocket_lock_callbacks.ut_test = nil

	local targets = {}

	for _, unit in ipairs(rockets) do
		targets[#targets + 1] = rockets[unit].target or false
	end

	return locked, targets
end

-- Where the rats of a crowd stand, as { ahead, right } from the player in meters: in front of the monster beside the way to it, at its
-- sides, and in a block behind it, near the lines the crosshair takes to its parts. A rat behind it is seen past its body by a check of
-- the level alone.
local CROWD = { { 4.5, -1.2 }, { 5, 1.2 }, { 7, -2.5 }, { 7, 2.5 }, { 10, -1 }, { 10, 0 }, { 10, 1 }, { 12, -0.5 }, { 12, 0.5 } }

local function monster_scenario(breed_name, crowded)
	return {
		name = "a lock on a " .. breed_name .. " wherever the crosshair is on its body" .. (crowded and ", with rats around it" or ""),
		run = function (t)
			local monster = t.spawn(breed_name, MONSTER_DISTANCE)

			if not t.expect(monster, "the %s could not be spawned", breed_name) then
				return
			end

			t.wait(3)

			local tried = 0

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

				t.aim_at_point(point[2], point[3], point[4])

				-- (a part can be inside the body, or a rat can stand in front of it: then the crosshair is not on the monster, and the
				-- part is not tried)
				local on = under_crosshair(t)

				if on ~= monster then
					t.log("the crosshair aimed at its %s is on %s, not on it: not tried", point[1], on and tostring(Unit.get_data(on, "breed") and Unit.get_data(on, "breed").name or "the level") or "nothing")
				elseif HEALTH_ALIVE[monster] then
					tried = tried + 1

					local locked, targets = locks_on(t)
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

			t.expect(tried >= 3, "only %d parts of its body could be aimed at", tried)
		end,
	}
end

-- The largest hit in a record of t.track_damage: the explosion's
local function largest_hit(record)
	local largest = 0

	for _, hit in ipairs(record.hits) do
		largest = math.max(largest, hit.amount)
	end

	return largest
end

-- The damage of the explosion of a rocket at an enemy of a breed, enemy_distance ahead, aimed at its middle
local function rocket_damage(t, breed_name)
	t.go_to_start()

	local enemy = t.spawn(breed_name, CONFIG.enemy_distance)

	if not t.expect(enemy, "the %s could not be spawned", breed_name) then
		return nil
	end

	t.wait(1)

	-- A rocket flies along the aim from where it starts, to the right of the eye and below it (rocket_launcher.lua's start_right and
	-- start_down), so the aim is that far to the left of the enemy's middle and above it, and the rocket goes through the middle
	local aim = t.on_main_thread(function ()
		local node = Unit.has_node(enemy, "j_spine") and Unit.node(enemy, "j_spine") or 0
		local middle = Unit.world_position(enemy, node)
		local eye = ScriptUnit.extension(t.unit(), "first_person_system"):current_position()
		local right = Vector3.normalize(Vector3.cross(Vector3.normalize(Vector3.flat(middle - eye)), Vector3.up()))
		local point = middle - right * CONFIG.rocket_start_right + Vector3(0, 0, CONFIG.rocket_start_down)

		return { Vector3.x(point), Vector3.y(point), Vector3.z(point) }
	end)

	t.aim_at_point(aim[1], aim[2], aim[3])

	local damage = t.track_damage(enemy)

	t.press("action_one", 0.05)
	t.wait(1)
	t.remove(enemy)

	local hits = {}

	for _, hit in ipairs(damage.hits) do
		hits[#hits + 1] = string.format("%.1f %s", hit.amount, tostring(hit.type))
	end

	t.log("a rocket at the %s: %s", breed_name, table.concat(hits, ", "))

	return largest_hit(damage)
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

				ut.rocket_lock_callbacks.ut_test = function (owner_unit, is_locked)
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

				ut.rocket_lock_callbacks.ut_test = nil

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
		{
			-- The explosion does the armour's share of its damage against an enemy with none. There are no critical hits. The player's power
			-- against each breed is taken out of its damage first.
			name = "a rocket hurts armoured enemies and monsters by their armour",
			run = function (t)
				t.critical_hits(false)

				local plain = rocket_damage(t, CONFIG.plain_breed)

				if not t.expect(plain and plain > 0, "the rocket did not hurt the %s", CONFIG.plain_breed) then
					return
				end

				plain = plain / t.power_against(CONFIG.plain_breed, definition.key)

				for _, entry in ipairs(CONFIG.armour_breeds) do
					local breed_name, share = entry[1], entry[2]
					local damage = rocket_damage(t, breed_name)

					if t.expect(damage and damage > 0, "the rocket did not hurt the %s", breed_name) then
						local power = t.power_against(breed_name, definition.key)

						damage = damage / power
						t.log("%s: %.1f at %.2f power, %.2f of the marauder's %.1f", breed_name, damage, power, damage / plain, plain)
						t.expect(math.abs(damage / plain - share) <= CONFIG.armour_margin, "the rocket did %.2f of its damage to the %s, not %.2f", damage / plain, breed_name, share)
					end
				end
			end,
		},
		{
			-- The explosion hurts the enemy the rocket hits, and the enemies around as far as its radius, less the farther they are, and none
			-- past it
			name = "a rocket's explosion falls off to its radius",
			run = function (t)
				local hit = t.spawn_target(CONFIG.enemy_distance)

				if not t.expect(hit, "the target could not be spawned") then
					return
				end

				local places = t.on_main_thread(function ()
					local position = Unit.local_position(hit, 0)
					local right = Quaternion.right(ScriptUnit.extension(t.unit(), "first_person_system"):current_rotation())
					local side = Vector3.normalize(Vector3.flat(right))
					local inside = position + side * CONFIG.inside_radius
					local outside = position - side * CONFIG.outside_radius

					return {
						{ Vector3.x(inside), Vector3.y(inside), Vector3.z(inside) },
						{ Vector3.x(outside), Vector3.y(outside), Vector3.z(outside) },
					}
				end)
				local inside = t.spawn_at(runner.target_breed, unpack(places[1]))
				local outside = t.spawn_at(runner.target_breed, unpack(places[2]))

				if not t.expect(inside and outside, "the enemies beside it could not be spawned") then
					return
				end

				t.wait(1)
				t.aim_at(hit)

				local damages = { t.track_damage(hit), t.track_damage(inside), t.track_damage(outside) }

				t.press("action_one", 0.05)
				t.wait(1)

				local on_hit, near, far = largest_hit(damages[1]), largest_hit(damages[2]), largest_hit(damages[3])

				t.log("the one hit %.1f, %.1f m from it %.1f, %.1f m from it %.1f", on_hit, CONFIG.inside_radius, near, CONFIG.outside_radius, far)
				t.expect(on_hit > 0, "the explosion did not hurt the enemy the rocket hit")
				t.expect(near > 0, "the explosion did not hurt the enemy %.1f m from it, inside its radius", CONFIG.inside_radius)
				t.expect(near < on_hit, "the enemy %.1f m from the explosion took as much as the one it hit (%.1f, %.1f)", CONFIG.inside_radius, near, on_hit)
				t.expect(far == 0, "the explosion hurt the enemy %.1f m from it, past its radius (%.1f)", CONFIG.outside_radius, far)
			end,
		},
		{
			-- A critical rocket does the same damage as a plain one: the explosion has no critical boost, as the game's explosions have
			-- none (rocket_launcher.lua's EXPLOSION)
			name = "a critical rocket does the same damage",
			run = function (t)
				t.critical_hits(false)

				local plain = rocket_damage(t, CONFIG.plain_breed)

				t.critical_hits(true)

				local critical = rocket_damage(t, CONFIG.plain_breed)

				t.log("plain %s, critical %s", tostring(plain), tostring(critical))

				if t.expect(plain and critical and plain > 0, "a rocket did not hurt the %s", CONFIG.plain_breed) then
					t.expect(math.abs(critical - plain) <= plain * CONFIG.crit_margin, "a critical rocket did %.1f, not the plain %.1f", critical, plain)
				end
			end,
		},
		{
			-- The launcher can be put away right after a shot, and nothing is fired after it
			name = "the launcher can be put away right after a shot",
			run = function (t)
				t.look(20)

				local template = t.wielded()
				local before = t.ammo()

				t.press("action_one", 0.05)
				t.tap("wield_1")
				t.hold("action_one")
				t.wait(CONFIG.fire_rate * 2)
				t.release("action_one")

				t.expect(t.wielded() ~= template, "the launcher is still in the hands (%s)", tostring(t.wielded()))
				t.expect(before - (t.ammo() or before) <= 1, "%d rockets were fired, not 1", before - (t.ammo() or before))

				t.tap("wield_2")
				t.wait(1.5)
			end,
		},
		{
			-- A body heavier than a Chaos marauder's is thrown slower (utils.throw_share), and the marauder's mass is the reference
			-- (utils.RAGDOLL_REFERENCE_MASS). Each enemy is killed where it stands and its ragdoll weighed once physics moves it.
			name = "a body heavier than a marauder's is thrown slower",
			run = function (t)
				local masses = {}

				for _, breed_name in ipairs(CONFIG.ragdoll_breeds) do
					local unit = t.spawn(breed_name, CONFIG.enemy_distance)

					if unit then
						t.on_main_thread(function ()
							AiUtils.kill_unit(unit, t.unit())
						end)
						t.wait_until(function ()
							return t.on_main_thread(function ()
								return Unit.alive(unit) and utils.ragdoll_mass(unit) > 0
							end)
						end, CONFIG.ragdoll_wait, "the body to fall")

						masses[breed_name] = t.on_main_thread(function ()
							return Unit.alive(unit) and { utils.ragdoll_mass(unit), utils.throw_share(unit) } or nil
						end)
						t.remove(unit)
					end

					local mass = masses[breed_name]

					t.log("%s: a ragdoll of %s, thrown at %s of UT's speed", breed_name, mass and string.format("%.1f", mass[1]) or "nothing", mass and string.format("%.2f", mass[2]) or "-")
				end

				local reference = masses[CONFIG.ragdoll_breeds[1]]
				local light = masses[CONFIG.ragdoll_breeds[2]]
				local heavy = masses[CONFIG.ragdoll_breeds[3]]

				t.expect(reference and light and heavy, "not every enemy fell as a ragdoll")
				t.expect(utils.RAGDOLL_REFERENCE_MASS, "utils.RAGDOLL_REFERENCE_MASS is not set: the %s's ragdoll is %.1f", CONFIG.ragdoll_breeds[1], reference and reference[1] or -1)

				if reference and light and heavy and utils.RAGDOLL_REFERENCE_MASS then
					t.expect(math.abs(reference[2] - 1) < 0.01 and math.abs(light[2] - 1) < 0.01, "the %s and the %s are not thrown at UT's speed", CONFIG.ragdoll_breeds[1], CONFIG.ragdoll_breeds[2])
					t.expect(heavy[2] < 1, "the %s is thrown at UT's speed", CONFIG.ragdoll_breeds[3])
				end
			end,
		},
	}

	-- The game crashed in its physics in a horde, with the Rocket Launcher among the weapons. The explosions throw the bodies they kill.
	-- The player fires single rockets and loaded ones at the nearest enemy of a horde that attacks (t.fight_horde). The game crashing is
	-- the failure.
	list[#list + 1] = {
		name = "firing into a horde",
		run = function (t)
			local shots = 0
			local killed = t.fight_horde(HORDE, function (nearest)
				t.refill()
				t.aim_at(nearest)
				shots = shots + 1

				if shots % 3 == 0 then
					t.press("action_two", CONFIG.load_interval * 2 + 0.1)
				else
					t.press("action_one", 0.05)
				end

				t.wait(CONFIG.fire_rate)
			end)

			t.expect(killed > 0, "no enemy was killed")
		end,
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

-- Bots with the Rocket Launcher (rocket/bots.lua). A hero can't be a bot and the player at once, so these run in a suite of their own with
-- the player as Sienna, and the bot is Saltzpyre as a Witch Hunter Captain, with his own mind. The special stands ahead and shoots at the
-- player, who stands aside, out of the bot's way.
local BOTS = {
	profile = "witch_hunter",
	career = 1,
	behind = -3, -- m
	player_aside = 4, -- m to the right
	special = "skaven_ratling_gunner",
	special_distance = 14, -- m
	-- How long the bot has to hurt the special
	fight_time = 30, -- s
}

-- The damage from the Rocket Launcher in a record of t.track_damage
local function from_rocket_launcher(record)
	local total = 0

	for _, hit in ipairs(record.hits) do
		if hit.source == definition.key then
			total = total + hit.amount
		end
	end

	return total
end

local function bot_scenarios()
	return {
		{
			-- The bot shoots the special, and never hurts the player
			name = "a bot shoots enemies with it",
			run = function (t)
				t.hurtable(true)

				local special = t.spawn(BOTS.special, BOTS.special_distance)

				if not t.expect(special, "the %s could not be spawned", BOTS.special) then
					return
				end

				local aside = t.ground_at(0, BOTS.player_aside)

				if not t.expect(aside, "there is no ground beside the player") then
					return
				end

				-- (a bot shoots a special only once it has been seen, which a calm one never is: shooting at the player makes it seen)
				t.on_main_thread(function ()
					runner.provoke(special)
				end)

				local damage = t.track_damage(special)
				local player_damage = t.track_damage(t.unit())

				if not t.expect(t.add_bot(BOTS.profile, BOTS.career, definition.key, BOTS.behind, nil, true), "the bot could not be added") then
					return
				end

				t.on_main_thread(function ()
					runner.move_player(t.unit(), Vector3(aside[1], aside[2], aside[3]))
				end)
				t.wait_until(function ()
					return from_rocket_launcher(damage) > 0
				end, BOTS.fight_time, "the bot to hurt the special")
				t.wait(5)

				t.expect(from_rocket_launcher(damage) > 0, "the bot did not hurt the %s with the Rocket Launcher in %d s", BOTS.special, BOTS.fight_time)
				t.expect(from_rocket_launcher(player_damage) == 0, "the bot's rockets hurt the player %.1f", from_rocket_launcher(player_damage))
			end,
		},
	}
end

local shock_rifle = ut.items.weapons.shock_rifle

runner.add_suite({
	name = "rocket_bots",
	item = shock_rifle.key,
	template = shock_rifle.template,
	slot = "slot_ranged",
	careers = { "bw_adept" },
	scenarios = bot_scenarios(),
})
