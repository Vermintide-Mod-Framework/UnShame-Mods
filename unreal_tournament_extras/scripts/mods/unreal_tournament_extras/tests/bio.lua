local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The Bio Rifle's in-game tests (see runner.lua). Run them with /ut_test bio. They run in the runner's level, Righteous Stand. The
-- numbers expected are UT's (XWeapons/BioFire, BioChargedFire and BioGlob) as the mod turns them into this game's.

local runner = mod.test_runner

local definition = ut.items.weapons.bio_rifle

local CONFIG = {
	-- All the ammo, which is all in the clip
	max_ammo = 50,
	-- BioGlob.RestTime and TouchDetonationDelay, and the delay of a glob that an explosion sets off
	rest_time = 2.25, -- s
	touch_detonation_delay = 0.15, -- s
	detonation_delay = 0.1, -- s
	-- BioChargedFire.MaxGoopLoad, and the level a glob that has landed keeps at most (the rest is thrown off)
	max_goop_load = 10,
	max_landed_level = 4,
	-- How much of a level 1 glob's damage (20 + 19, scaled by 60 / 90) the player who fired it takes at most
	glob_self_damage = (20 + 19) * 60 / 90 * 0.75,
	-- The explosion throws the player up at least this fast when it goes off at their feet
	min_jump_speed = 1.5, -- m/s
	-- Timing margins
	margin = 0.15, -- s
	-- A glob's speed (BioGlob.Speed, 2000 UT units a second, times bio_rifle.lua's speed_scale of 0.75) and the pull of its gravity
	-- (bio_rifle.lua's gravity), with this much either way
	glob_speed = 2000 * 0.02 * 0.75, -- m/s
	speed_margin = 3, -- m/s
	glob_gravity = 10.7, -- m/s/s
	gravity_margin = 1.5, -- m/s/s
	-- The explosion's damage against armour and monsters, of its damage against an enemy with none (a Chaos marauder), with this much
	-- either way (bio_rifle.lua's armor_attack). A Stormvermin is armoured, a Chaos warrior's body is super armour, and a rat ogre is a
	-- monster and a boss, whose damage the game takes down to 0.45 (DamageUtils.calculate_damage's boss_damage_reduction).
	plain_breed = "chaos_marauder",
	armour_breeds = {
		{ "skaven_storm_vermin", 0.8 },
		{ "chaos_warrior", 0.5 },
		{ "skaven_rat_ogre", 1.5 * 0.45 },
	},
	armour_margin = 0.1,
	-- How far ahead the enemies that are shot stand
	enemy_distance = 5, -- m
	-- A small glob's explosion: the enemies beside the one it hits, this far from it (inside the radius of 80 UT units, 1.6 m, and outside)
	inside_radius = 0.8, -- m
	outside_radius = 2.2, -- m
	-- A critical glob does the same damage as a plain one, within this share
	crit_margin = 0.05,
	-- A flying glob's spheres: against enemies UT's (utils.UT_PROJECTILE_RADIUS) with the glob's 2 UT units, against walls the pistol
	-- shot's it is made on
	glob_enemy_radius = 2 * 0.02 + 0.3, -- m
	glob_wall_radius = 0.15, -- m
}

local function is_shot(action)
	return action.ut_bio_shot
end

local function is_child(action)
	return action.ut_bio_glob and not action.ut_bio_shot
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

-- The globs that land while a test records them, from the skin's callback: { t, x, y, z, normal_z, level }
local landings = {}
local recording = false

local skin_land = ut.goop_visual_callbacks.land

ut.goop_visual_callbacks.land = function (id, position, normal, level, ...)
	if recording then
		landings[#landings + 1] = {
			level = level,
			normal_z = Vector3.z(normal),
			t = Managers.time:time("game"),
			x = Vector3.x(position),
			y = Vector3.y(position),
			z = Vector3.z(position),
		}
	end

	return skin_land(id, position, normal, level, ...)
end

local function record_landings()
	table.clear(landings)

	recording = true

	return landings
end

-- The times of the explosions of a template that happen from now on
local function explosion_times(t, name)
	local times = {}

	ut.any_explosion_callbacks.ut_test_bio = function (explosion_template)
		if explosion_template.name == name then
			times[#times + 1] = Managers.time:time("game")
		end
	end

	return times
end

local function stop_recording()
	recording = false
	ut.any_explosion_callbacks.ut_test_bio = nil
end

-- Watches the player's globs from now on: the ones fired, in order, with where each was every frame and its goop level
local function watch_globs(t, filter)
	local seen = {}
	local earlier = t.on_main_thread(function ()
		local units = {}

		for _, unit in ipairs(t.projectiles(filter)) do
			units[unit] = true
		end

		return units
	end)

	return seen, function ()
		for _, unit in ipairs(t.projectiles(filter)) do
			if not earlier[unit] then
				if not seen[unit] then
					seen[unit] = {
						level = ut.bio_goop.level_of_scale(ScriptUnit.extension(unit, "projectile_system").scale),
						positions = {},
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

local function ammo_extension_of(unit)
	local inventory_extension = ScriptUnit.extension(unit, "inventory_system")
	local slot_data = inventory_extension:get_slot_data("slot_ranged")

	return GearUtils.get_ammo_extension(slot_data.right_unit_1p, slot_data.left_unit_1p)
end

-- The largest hit in a record of t.track_damage: the explosion's
local function largest_hit(record)
	local largest = 0

	for _, hit in ipairs(record.hits) do
		largest = math.max(largest, hit.amount)
	end

	return largest
end

-- The damage of a small glob's blast that goes off at the middle of an enemy of a breed, enemy_distance ahead. A glob that hits an
-- enemy goes off on its body, and the blast does its full damage only near its middle (bio_rifle.lua's blast_full_damage_share), so how
-- much of the blast a hit enemy takes goes with its size. Here the blast is made at the enemy's middle, as a glob's is
-- (AreaDamageSystem.create_explosion), so that only the armour counts. critical makes it a critical hit's blast.
local function blast_damage(t, breed_name, critical)
	t.go_to_start()

	local enemy = t.spawn(breed_name, CONFIG.enemy_distance)

	if not t.expect(enemy, "the %s could not be spawned", breed_name) then
		return nil
	end

	t.wait(1)

	local damage = t.track_damage(enemy)

	t.on_main_thread(function ()
		local player = t.unit()
		local node = Unit.has_node(enemy, "j_spine") and Unit.node(enemy, "j_spine") or 0
		local power_level = ScriptUnit.extension(player, "career_system"):get_career_power_level()
		local area_damage_system = Managers.state.entity:system("area_damage_system")

		-- (with the units' positions made current, as the rifle's own blasts are: utils.with_valid_positions)
		ut.utils.with_valid_positions(area_damage_system.create_explosion, area_damage_system, player, Unit.world_position(enemy, node), Quaternion.identity(), "ut_bio_blast", 0, definition.key, power_level, critical == true, player)
	end)
	t.wait(0.5)
	t.remove(enemy)

	return largest_hit(damage)
end

local function scenarios()
	return {
		{
			name = "all the ammo is in the clip",
			run = function (t)
				local ammo = t.on_main_thread(function ()
					local ammo_extension = ammo_extension_of(t.unit())

					return { ammo_extension:ammo_count(), ammo_extension:total_remaining_ammo() }
				end)
				local clip, total = ammo[1], ammo[2]

				t.expect(total >= CONFIG.max_ammo, "the rifle holds %s, less than %d", tostring(total), CONFIG.max_ammo)
				t.expect(clip == total, "%s of the %s are in the clip: there is a reload", tostring(clip), tostring(total))
			end,
		},
		{
			name = "primary fire lobs one glob for one ammo",
			run = function (t)
				t.look(0)

				local before = t.ammo()
				local globs, observe = watch_globs(t, is_shot)

				t.press("action_one", 0.05, observe)
				t.watch(0.35, observe)

				t.expect(#globs == 1, "%d globs were fired, not 1", #globs)
				t.expect(before - (t.ammo() or 0) == 1, "the shot used %s ammo, not 1", tostring(before - (t.ammo() or 0)))

				local glob = globs[1] and globs[globs[1]]

				t.expect(glob and glob.level == 1, "the glob has %s goop, not 1", glob and tostring(glob.level) or "no")

				-- (it falls with gravity: 0.5 m in 0.3 s)
				local positions = glob and glob.positions

				if positions and #positions >= 5 then
					local drop = positions[1].z - positions[#positions].z

					t.expect(drop > 0.2, "the glob fell %.2f m in %.2f s", drop, positions[#positions].t - positions[1].t)
				end
			end,
		},
		{
			name = "holding primary fire repeats it at its fire rate",
			run = function (t)
				t.look(20)

				local before = t.ammo()

				-- (shots at 0, 0.33 and 0.66 s. The button is let go about halfway to the fourth at 0.99 s, which a late frame used to reach
				-- when it was let go at 0.9 s.)
				t.press("action_one", 0.8)
				t.wait(0.3)

				t.expect(before - (t.ammo() or 0) == 3, "%s shots in 0.8 s, not 3", tostring(before - (t.ammo() or 0)))
			end,
		},
		{
			name = "a glob that lands explodes after its rest",
			run = function (t)
				t.look(-30)

				local landed = record_landings()
				local blasts = explosion_times(t, "ut_bio_blast")

				t.press("action_one", 0.05)
				t.wait_until(function ()
					return #blasts > 0
				end, 5, "the glob to explode")
				stop_recording()

				t.expect(#landed == 1, "%d globs landed, not 1", #landed)

				if landed[1] and blasts[1] then
					local rest = blasts[1] - landed[1].t

					t.expect(math.abs(rest - CONFIG.rest_time) <= CONFIG.margin, "the glob exploded %.2f s after it landed, not %.2f", rest, CONFIG.rest_time)
				end
			end,
		},
		{
			name = "a glob that hits an enemy explodes there",
			run = function (t)
				local target = t.spawn_target(5)

				if not t.expect(target, "the target could not be spawned") then
					return
				end

				local damage = t.track_damage(target)
				local explosions = t.explosions()
				local landed = record_landings()

				t.press("action_one", 0.05)
				t.wait(1)
				stop_recording()

				t.expect(count_names(explosions, "ut_bio_blast_air") == 1, "the glob made %d explosions in the air, not 1 (%s)", count_names(explosions, "ut_bio_blast_air"), table.concat(explosions, ", "))
				t.expect(#landed == 0, "the glob landed instead")
				t.expect(damage.total > 0, "the target was not hurt")
			end,
		},
		{
			name = "the secondary button loads goop, one ammo at once and one each 0.25 s",
			run = function (t)
				t.look(20)

				local before = t.ammo()
				local globs, observe = watch_globs(t, is_shot)

				t.hold("action_two")
				t.wait(1.1)

				local loaded = before - (t.ammo() or 0)

				t.release("action_two")
				t.watch(0.3, observe)

				t.expect(loaded == 5, "1.1 s of loading used %d ammo, not 5", loaded)
				t.expect(#globs == 1, "%d globs were fired, not 1", #globs)
				t.expect(globs[1] and globs[globs[1]].level == 5, "the glob has %s goop, not 5", globs[1] and tostring(globs[globs[1]].level) or "no")
				t.expect(before - (t.ammo() or 0) == 5, "the big glob used %s ammo in all, not 5", tostring(before - (t.ammo() or 0)))
			end,
		},
		{
			name = "a full load is ten",
			run = function (t)
				t.look(20)

				local before = t.ammo()
				local globs, observe = watch_globs(t, is_shot)

				t.hold("action_two")
				t.wait(3.5)
				t.release("action_two")
				t.watch(0.3, observe)

				t.expect(before - (t.ammo() or 0) == CONFIG.max_goop_load, "a full load used %s ammo, not %d", tostring(before - (t.ammo() or 0)), CONFIG.max_goop_load)
				t.expect(globs[1] and globs[globs[1]].level == CONFIG.max_goop_load, "the glob has %s goop, not %d", globs[1] and tostring(globs[globs[1]].level) or "no", CONFIG.max_goop_load)
			end,
		},
		{
			name = "a load that is not fired gives the ammo back",
			run = function (t)
				local before = t.ammo()

				t.hold("action_two")
				t.wait(1.1)

				local loaded = before - (t.ammo() or 0)

				-- (a switch to the melee weapon ends the load)
				t.on_main_thread(function ()
					ScriptUnit.extension(t.unit(), "inventory_system"):wield("slot_melee")
				end)
				t.wait(0.5)
				t.release("action_two")
				t.wait(0.5)

				local after = t.ammo()

				t.on_main_thread(function ()
					ScriptUnit.extension(t.unit(), "inventory_system"):wield("slot_ranged")
				end)
				t.wait(1.5)

				t.expect(loaded > 0, "the load used no ammo")
				t.expect(after == before, "%s ammo after the switch, not the %s before the load", tostring(after), tostring(before))
			end,
		},
		{
			name = "a big glob that lands throws off small globs",
			run = function (t)
				t.look(-30)

				local landed = record_landings()
				local children, observe = watch_globs(t, is_child)

				t.hold("action_two")
				t.wait(3)
				t.release("action_two")
				t.watch(1, observe)
				stop_recording()

				local first = landed[1]

				t.expect(first and first.level >= 2 and first.level <= CONFIG.max_landed_level, "the big glob landed with %s goop, not 2 to %d", first and tostring(first.level) or "no", CONFIG.max_landed_level)
				t.expect(first and #children == CONFIG.max_goop_load - first.level, "it threw off %d small globs, not %d", #children, first and CONFIG.max_goop_load - first.level or -1)
			end,
		},
		{
			name = "a glob that lands explodes soon after the player steps in",
			run = function (t)
				-- (the globs of the scenario before have gone off by then: one would take this glob in)
				t.wait(CONFIG.rest_time)
				t.look(-30)

				local landed = record_landings()
				local blasts = explosion_times(t, "ut_bio_blast")

				t.press("action_one", 0.05)
				t.wait_until(function ()
					return #landed > 0
				end, 3, "the glob to land")

				local glob = landed[1]

				if not t.expect(glob, "the glob did not land") then
					stop_recording()

					return
				end

				local stepped_t = Managers.time:time("game")

				t.on_main_thread(function ()
					runner.move_player(t.unit(), Vector3(glob.x, glob.y, glob.z + 0.05))
				end)
				t.wait_until(function ()
					return #blasts > 0
				end, 3, "the glob to explode")
				stop_recording()

				local delay = blasts[1] and blasts[1] - stepped_t

				t.expect(delay and delay <= CONFIG.touch_detonation_delay + CONFIG.margin, "the glob exploded %s s after the player stepped in, not %.2f", delay and string.format("%.2f", delay) or "never", CONFIG.touch_detonation_delay)
			end,
		},
		{
			name = "an explosion sets off a glob near it",
			run = function (t)
				local landed = record_landings()
				local blasts = explosion_times(t, "ut_bio_blast")

				-- Two globs half a meter apart, the second 0.4 s after the first
				t.look(-30)
				t.press("action_one", 0.05)
				t.wait(0.4)
				t.look(-26)
				t.press("action_one", 0.05)
				t.wait_until(function ()
					return #blasts >= 2
				end, 5, "both globs to explode")
				stop_recording()

				t.expect(#landed == 2, "%d globs landed, not 2", #landed)

				if #landed == 2 and #blasts == 2 then
					local gap = blasts[2] - blasts[1]

					t.expect(gap <= CONFIG.detonation_delay + CONFIG.margin, "the second glob went off %.2f s after the first, not %.2f", gap, CONFIG.detonation_delay)
					t.expect(blasts[2] < landed[2].t + CONFIG.rest_time - 0.1, "the second glob was not set off: it went off after its own rest")
				end
			end,
		},
		{
			name = "a glob on a ceiling drips",
			place = "ceiling",
			run = function (t)
				t.look(85)

				local landed = record_landings()

				t.press("action_one", 0.05)
				t.wait_until(function ()
					return #landed >= 2
				end, 5, "the glob to drip and land again")
				stop_recording()

				t.expect(landed[1] and landed[1].normal_z < -0.7, "the glob did not land on the ceiling")
				t.expect(landed[2] and landed[2].normal_z > 0.7, "the glob did not drip to the floor")

				if landed[1] and landed[2] then
					local hang = landed[2].t - landed[1].t

					-- (the drip falls after the landing's animation and the drip time, 2.4 s, and falls 3 m)
					t.expect(hang > 2.2 and hang < 3.5, "it hung on the ceiling %.2f s", hang)
				end
			end,
		},
		{
			name = "a glob at the feet hurts the player and throws them up",
			run = function (t)
				t.hurtable(true)
				t.look(-85)

				local up = 0
				local taken = t.track_damage(t.unit())

				t.press("action_one", 0.05)
				t.watch(0.8, function ()
					local _, _, z = t.velocity()

					up = math.max(up, z)
				end)

				local blast = taken.hits[1]

				t.expect(blast, "the glob's explosion did not hurt the player")
				t.expect(not blast or blast.amount <= CONFIG.glob_self_damage + 0.5, "the glob hurt the player %.1f, more than %.1f", blast and blast.amount or 0, CONFIG.glob_self_damage)
				t.expect(up >= CONFIG.min_jump_speed, "the glob threw the player up at %.1f m/s at most", up)
			end,
		},
		{
			-- A glob leaves at its speed and falls by its gravity
			name = "a glob flies at its speed and falls by its gravity",
			run = function (t)
				t.look(20)

				local globs, observe = watch_globs(t, is_shot)

				t.press("action_one", 0.05, observe)
				t.watch(0.5, observe)

				local positions = globs[1] and globs[globs[1]].positions

				if not t.expect(positions and #positions >= 6, "the glob was not seen flying") then
					return
				end

				local function velocity(a, b)
					local dt = b.t - a.t

					return (b.x - a.x) / dt, (b.y - a.y) / dt, (b.z - a.z) / dt, (a.t + b.t) / 2
				end

				local vx, vy, vz, early = velocity(positions[1], positions[2])
				local _, _, late_vz, late = velocity(positions[#positions - 1], positions[#positions])
				local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
				local gravity = (vz - late_vz) / (late - early)

				t.log("the glob left at %.1f m/s and fell by %.1f m/s/s", speed, gravity)
				t.expect(math.abs(speed - CONFIG.glob_speed) <= CONFIG.speed_margin, "the glob left at %.1f m/s, not %.1f", speed, CONFIG.glob_speed)
				t.expect(math.abs(gravity - CONFIG.glob_gravity) <= CONFIG.gravity_margin, "the glob fell by %.1f m/s/s, not %.1f", gravity, CONFIG.glob_gravity)
			end,
		},
		{
			-- The blast does the armour's share of its damage against an enemy with none (see blast_damage). The player's power against
			-- each breed is taken out of its damage first.
			name = "a glob hurts armoured enemies and monsters by their armour",
			run = function (t)
				local plain = blast_damage(t, CONFIG.plain_breed)

				if not t.expect(plain and plain > 0, "the blast did not hurt the %s", CONFIG.plain_breed) then
					return
				end

				plain = plain / t.power_against(CONFIG.plain_breed, definition.key)

				for _, entry in ipairs(CONFIG.armour_breeds) do
					local breed_name, share = entry[1], entry[2]
					local damage = blast_damage(t, breed_name)

					if t.expect(damage and damage > 0, "the blast did not hurt the %s", breed_name) then
						local power = t.power_against(breed_name, definition.key)

						damage = damage / power
						t.log("%s: %.1f at %.2f power, %.2f of the marauder's %.1f", breed_name, damage, power, damage / plain, plain)
						t.expect(math.abs(damage / plain - share) <= CONFIG.armour_margin, "the blast did %.2f of its damage to the %s, not %.2f", damage / plain, breed_name, share)
					end
				end
			end,
		},
		{
			-- A small glob's explosion hurts the enemy it hits, and the enemies around as far as its radius, less the farther they are, and
			-- none past it
			name = "a glob's explosion falls off to its radius",
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
				t.expect(on_hit > 0, "the explosion did not hurt the enemy the glob hit")
				t.expect(near > 0, "the explosion did not hurt the enemy %.1f m from it, inside its radius", CONFIG.inside_radius)
				t.expect(near < on_hit, "the enemy %.1f m from the explosion took as much as the one it hit (%.1f, %.1f)", CONFIG.inside_radius, near, on_hit)
				t.expect(far == 0, "the explosion hurt the enemy %.1f m from it, past its radius (%.1f)", CONFIG.outside_radius, far)
			end,
		},
		{
			-- A critical glob does the same damage as a plain one: the blast has no critical boost, as the game's explosions have none
			-- (bio_rifle.lua's BLAST). The blasts are made at the enemy's middle: a glob that is fired goes off where it hits the body,
			-- and the blast glances (less damage) when that is outside its inner radius, critical or not.
			name = "a critical glob does the same damage",
			run = function (t)
				local plain = blast_damage(t, CONFIG.plain_breed, false)
				local critical = blast_damage(t, CONFIG.plain_breed, true)

				if t.expect(plain and critical and plain > 0, "a glob did not hurt the %s", CONFIG.plain_breed) then
					t.log("plain %.1f, critical %.1f", plain, critical)
					t.expect(math.abs(critical - plain) <= plain * CONFIG.crit_margin, "a critical glob did %.1f, not the plain %.1f", critical, plain)
				end
			end,
		},
		{
			-- The rifle can be put away right after a shot, and nothing is fired after it
			name = "the rifle can be put away right after a shot",
			run = function (t)
				t.look(20)

				local template = t.wielded()
				local before = t.ammo()

				t.press("action_one", 0.05)
				t.tap("wield_1")
				t.hold("action_one")
				t.wait(1)
				t.release("action_one")

				t.expect(t.wielded() ~= template, "the rifle is still in the hands (%s)", tostring(t.wielded()))
				t.expect(before - (t.ammo() or before) <= 1, "%d globs were fired, not 1", before - (t.ammo() or before))

				t.tap("wield_2")
				t.wait(1.5)
			end,
		},
		{
			-- A glob in the air hits an enemy as a rocket does (utils.UT_PROJECTILE_RADIUS) with its own 2 UT units added, and a wall
			-- with the pistol shot's sphere it is made on (ut_wall_radius, hooks.lua), which the game sweeps with these numbers
			name = "a flying glob's sphere is UT's against enemies and the base's against walls",
			run = function (t)
				t.look(20)

				local found

				t.press("action_one", 0.05, function ()
					found = found or t.projectiles(is_shot)[1]
				end)
				t.watch(0.2, function ()
					found = found or t.projectiles(is_shot)[1]
				end)

				if not t.expect(found, "no glob flew") then
					return
				end

				local sizes = t.on_main_thread(function ()
					local impact_extension = Unit.alive(found) and ScriptUnit.has_extension(found, "projectile_impact_system")
					local projectile = Unit.alive(found) and ScriptUnit.has_extension(found, "projectile_system")
					local projectile_info = projectile and projectile._current_action.projectile_info

					return impact_extension and projectile_info and {
						radius = impact_extension.radius,
						static_impact_type = impact_extension.static_impact_type,
						wall = projectile_info.ut_wall_radius,
					}
				end)

				if t.expect(sizes, "the glob was gone before it was looked at") then
					t.log("enemies %.2f m, walls %s %.2f m", sizes.radius, tostring(sizes.static_impact_type), sizes.wall or -1)
					t.expect(math.abs(sizes.radius - CONFIG.glob_enemy_radius) < 0.001, "the glob's sphere against enemies is %.2f m, not %.2f", sizes.radius, CONFIG.glob_enemy_radius)
					t.expect(sizes.static_impact_type == "sphere_sweep" and sizes.wall == CONFIG.glob_wall_radius, "the glob is swept against walls by %s %s, not a sphere of %.2f m", tostring(sizes.static_impact_type), tostring(sizes.wall), CONFIG.glob_wall_radius)
				end
			end,
		},
	}
end

runner.add_suite({
	name = "bio",
	item = definition.key,
	template = definition.template,
	slot = "slot_ranged",
	careers = { "dr_ranger" },
	scenarios = scenarios(),
})

-- Bots with the Bio Rifle (bio/bots.lua). A hero can't be a bot and the player at once, so these run in a suite of their own with the
-- player as Sienna, and the bot is Bardin as a Ranger, with his own mind. The special stands ahead and shoots at the player, who stands
-- aside, out of the bot's way.
local BOTS = {
	profile = "dwarf_ranger",
	career = 1,
	behind = -3, -- m
	player_aside = 4, -- m to the right
	special = "skaven_ratling_gunner",
	special_distance = 14, -- m
	-- How long the bot has to hurt the special
	fight_time = 30, -- s
}

-- The damage from the Bio Rifle in a record of t.track_damage
local function from_bio_rifle(record)
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
					return from_bio_rifle(damage) > 0
				end, BOTS.fight_time, "the bot to hurt the special")
				t.wait(5)

				t.expect(from_bio_rifle(damage) > 0, "the bot did not hurt the %s with the Bio Rifle in %d s", BOTS.special, BOTS.fight_time)
				t.expect(from_bio_rifle(player_damage) == 0, "the bot's globs hurt the player %.1f", from_bio_rifle(player_damage))
			end,
		},
	}
end

local shock_rifle = ut.items.weapons.shock_rifle

runner.add_suite({
	name = "bio_bots",
	item = shock_rifle.key,
	template = shock_rifle.template,
	slot = "slot_ranged",
	careers = { "bw_adept" },
	scenarios = bot_scenarios(),
})
