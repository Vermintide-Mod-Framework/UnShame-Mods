local mod = get_mod("unreal_tournament")

-- The Bio Rifle's in-game tests (see runner.lua). Run them with /ut_test bio. They run in the runner's level, Righteous Stand. The
-- numbers expected are UT's (XWeapons/BioFire, BioChargedFire and BioGlob) as the mod turns them into this game's.

local runner = mod.test_runner

local definition = mod.items.weapons.bio_rifle

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

local skin_land = mod.goop_visual_callbacks.land

mod.goop_visual_callbacks.land = function (id, position, normal, level, ...)
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

	mod.any_explosion_callbacks.ut_test_bio = function (explosion_template)
		if explosion_template.name == name then
			times[#times + 1] = Managers.time:time("game")
		end
	end

	return times
end

local function stop_recording()
	recording = false
	mod.any_explosion_callbacks.ut_test_bio = nil
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
						level = mod.bio_goop.level_of_scale(ScriptUnit.extension(unit, "projectile_system").scale),
						positions = {},
					}
					seen[#seen + 1] = unit
				end

				local position = Unit.world_position(unit, 0)
				local positions = seen[unit].positions

				positions[#positions + 1] = {
					t = Managers.time:time("game"),
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

				-- (shots at 0, 0.33 and 0.66 s)
				t.press("action_one", 0.9)
				t.wait(0.3)

				t.expect(before - (t.ammo() or 0) == 3, "%s shots in 0.9 s, not 3", tostring(before - (t.ammo() or 0)))
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
