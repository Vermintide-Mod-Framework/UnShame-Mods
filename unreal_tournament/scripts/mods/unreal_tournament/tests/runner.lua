local mod = get_mod("unreal_tournament")

-- In-game tests. A suite is a weapon's tests: it sets up the character, career and weapon, runs its scenarios in a level that is loaded,
-- and puts everything back. It is run with the chat command /ut_test <suite>, and it prints what passed and failed to the chat and to the
-- game's console log.
--
-- A scenario is a function of the test context `t`. It runs as a coroutine, one step a frame, so it can wait for the game:
--   t.wait(seconds)                      waits that long
--   t.wait_until(condition, seconds, what)   waits until condition() is true, and returns false if it took longer than the seconds
--   t.expect(condition, message, ...)    records a failure with the message (a format string) if the condition is false
--   t.skip(reason)                       ends the scenario as skipped
--   t.press(name, seconds, observer)     holds an input of the player ("action_one", "action_two") for that long, then lets go. The
--                                        observer, if there is one, is called every frame while it is held.
--   t.watch(seconds, observer)           calls the observer every frame for that long
--   t.unit()                             the player's unit
--   t.ammo()                             the ranged weapon's ammo
--   t.refill()                           fills it
--   t.surface_ahead(distance)            where the player's aim hits the level within that distance, or nil
--   t.spawn(breed_name, distance)        spawns an enemy that distance ahead of the player on the ground, and returns it (nil if it could
--                                        not be spawned). It is removed after the scenario.
--   t.projectiles(filter)                the units of the player's projectiles whose action the filter accepts
--   t.explosions()                       a list that is filled with the names of the explosions that happen from now on
--
-- A suite is { name, item (the key of the weapon item), template, slot, careers (the careers it is run for), scenarios = { { name, run } } }.
--
-- The tests change the player's loadout and career, and put them back at the end. The loadout is kept in the backend, so what has to be
-- put back is saved in the settings while a suite runs, and put back the next time the mod loads if a suite was cut short.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")

local runner = {
	suites = {},
}

local CONFIG = {
	-- How long the player's new unit may take to appear after a profile is requested
	respawn_timeout = 30, -- seconds
	-- How long an enemy may take to spawn. Its packages may have to be loaded.
	spawn_timeout = 30, -- seconds
	-- The files of a remote driver (see poll_command_file)
	command_file = "ut_test_command.txt",
	result_file = "ut_test_result.txt",
	command_poll_interval = 0.5, -- seconds
}

local RESTORE_SETTING = "test_restore"

local function log(text, ...)
	mod:echo("[ut_test] " .. text, ...)
end

-- The commands and the results of a remote driver, when the mod has a way to read and write files (see poll_command_file)
local result_lines = {}

local function result(text, ...)
	result_lines[#result_lines + 1] = string.format(text, ...)
end

local function write_result_file()
	local ok_io, io_lib = pcall(function ()
		return rawget(_G, "io")
	end)

	if not ok_io or not io_lib or not io_lib.open then
		return
	end

	local path = runner.file_directory and runner.file_directory .. CONFIG.result_file

	if not path then
		return
	end

	local file = io_lib.open(path, "w")

	if file then
		file:write(table.concat(result_lines, "\n"), "\n")
		file:close()
	end
end

-- The player
local function local_player()
	return Managers.player and Managers.player:local_player_safe()
end

local function player_unit()
	local player = local_player()
	local unit = player and player.player_unit

	return unit and Unit.alive(unit) and unit or nil
end

local function player_career_name()
	local player = local_player()

	return player and player:career_name()
end

local function inventory_extension_of(unit)
	return unit and ScriptUnit.has_extension(unit, "inventory_system")
end

-- Input that the tests press. It is put in front of the game's input service of the player, which is what the game reads the player's
-- buttons from. The game ignores the player's input while its window has no focus, so a test needs the window to be in front.
local injected = {}
local patched_service

local function install_input(unit)
	local input_extension = ScriptUnit.has_extension(unit, "input_system")
	local service = input_extension and input_extension.input_service

	if not service or patched_service == service then
		return
	end

	runner.restore_input()

	local original = service.get

	service.get = function (self, key, ...)
		local value = injected[key]

		if value ~= nil then
			return value
		end

		return original(self, key, ...)
	end

	patched_service = service
end

function runner.restore_input()
	if patched_service then
		patched_service.get = nil
		patched_service = nil
	end

	table.clear(injected)
end

-- What a test waits for, which the update goes through one frame at a time
local run

local function resume(value)
	local ok, request = coroutine.resume(run.co, value)

	if not ok then
		run.error = request
		run.waiting = nil

		return
	end

	if coroutine.status(run.co) == "dead" then
		run.finished = true
		run.waiting = nil

		return
	end

	run.waiting = request
	run.waited = 0
end

local function yield(request)
	return coroutine.yield(request)
end

-- Runs a function that waits as a coroutine of its own and passes its waits up, so that an error in it does not need a pcall that waits
-- across. Returns true, or false and the error.
local function call_waiting(fn, ...)
	local co = coroutine.create(fn)
	local ok, request = coroutine.resume(co, ...)

	while ok and coroutine.status(co) ~= "dead" do
		ok, request = coroutine.resume(co, coroutine.yield(request))
	end

	return ok, request
end

-- The context the scenarios get
local function make_context(suite)
	local t = {}
	local scenario

	function t.wait(seconds)
		yield({
			seconds = seconds,
		})
	end

	function t.wait_until(condition, seconds, what)
		return yield({
			condition = condition,
			seconds = seconds,
			what = what,
		})
	end

	function t.expect(condition, message, ...)
		if not condition then
			local text = string.format(message or "failed", ...)

			scenario.failures[#scenario.failures + 1] = text
			log("FAIL %s: %s", scenario.name, text)
		end

		return condition
	end

	function t.skip(reason)
		scenario.skipped = reason

		error({
			skip = true,
		})
	end

	function t.watch(seconds, observer)
		yield({
			condition = function ()
				observer()

				return false
			end,
			quiet = true,
			seconds = seconds,
		})
	end

	function t.press(name, seconds, observer)
		injected[name] = true
		injected[name .. "_hold"] = true

		yield({
			frames = 1,
		})

		injected[name] = nil

		if observer then
			t.watch(seconds or 0.1, observer)
		else
			yield({
				seconds = seconds or 0.1,
			})
		end

		injected[name .. "_hold"] = nil
		injected[name .. "_release"] = true

		yield({
			frames = 1,
		})

		injected[name .. "_release"] = nil
	end

	function t.unit()
		return player_unit()
	end

	local function ammo_extension()
		local unit = player_unit()
		local extension = inventory_extension_of(unit)
		local slot_data = extension and extension:get_slot_data(suite.slot)

		return slot_data and GearUtils.get_ammo_extension(slot_data.right_unit_1p, slot_data.left_unit_1p)
	end

	function t.ammo()
		local extension = ammo_extension()

		return extension and extension:total_remaining_ammo()
	end

	function t.refill()
		local extension = ammo_extension()

		if extension then
			extension:add_ammo()
		end
	end

	local function aim()
		local unit = player_unit()
		local first_person_extension = unit and ScriptUnit.has_extension(unit, "first_person_system")

		if not first_person_extension then
			return
		end

		return first_person_extension:current_position(), Quaternion.forward(first_person_extension:current_rotation())
	end

	local function physics_world()
		return World.get_data(Managers.world:world("level_world"), "physics_world")
	end

	function t.surface_ahead(distance)
		local origin, forward = aim()

		if not origin then
			return nil
		end

		local hit, _, hit_distance = PhysicsWorld.immediate_raycast(physics_world(), origin, forward, distance, "closest", "collision_filter", "filter_ai_line_of_sight_check")

		if hit then
			return origin + forward * hit_distance
		end

		return nil
	end

	function t.spawn(breed_name, distance)
		local origin, forward = aim()
		local breed = Breeds[breed_name]

		if not origin or not breed then
			return nil
		end

		local flat = Vector3.normalize(Vector3.flat(forward))
		local above = origin + flat * distance + Vector3(0, 0, 2)
		local hit, _, hit_distance = PhysicsWorld.immediate_raycast(physics_world(), above, Vector3.down(), 8, "closest", "collision_filter", "filter_ai_line_of_sight_check")

		if not hit then
			return nil
		end

		local position = above - Vector3(0, 0, hit_distance)
		local spawned
		local optional_data = {
			spawned_func = function (unit)
				spawned = unit
			end,
		}

		Managers.state.conflict:spawn_one(breed, position, nil, optional_data, Quaternion.look(-flat, Vector3.up()))

		if not t.wait_until(function ()
			return spawned ~= nil
		end, CONFIG.spawn_timeout, "the enemy to spawn") then
			return nil
		end

		scenario.spawned[#scenario.spawned + 1] = spawned

		return spawned
	end

	function t.projectiles(filter)
		local found = {}

		for _, projectile in ipairs(utils.flying_projectiles() or {}) do
			local action = projectile.extension._current_action

			if projectile.own and action and filter(action) then
				found[#found + 1] = projectile.unit
			end
		end

		return found
	end

	function t.explosions()
		local names = {}

		runner.explosion_watch = names

		return names
	end

	t.scenario = function (value)
		if value then
			scenario = value
		end

		return scenario
	end

	return t
end

mod.any_explosion_callbacks.ut_test = function (explosion_template)
	local watch = runner.explosion_watch

	if watch then
		watch[#watch + 1] = explosion_template.name
	end
end

-- Putting the loadout back
local function save_restore(entries)
	mod:set(RESTORE_SETTING, entries)
end

local NOTHING_TO_RESTORE = {}

local function apply_restore(entries)
	for _, entry in ipairs(entries or {}) do
		if entry.backend_id then
			BackendUtils.set_loadout_item(entry.backend_id, entry.career, entry.slot)
		end
	end
end

-- Sets what a suite needs: the career, with the weapon in its slot, and the weapon in the player's hands. Returns false and says why if
-- it could not.
local function setup_character(t, suite, career)
	local player = local_player()
	local unit = player_unit()

	if not player or not unit then
		log("there is no player unit: start a mission first")

		return false
	end

	local item = BackendUtils.try_set_loadout_item(career, suite.slot, suite.item)

	if not item then
		log("%s is not in the inventory", suite.item)

		return false
	end

	-- The loadout is read when the player spawns, so the player is respawned even if the career is the same
	Managers.state.network:request_profile(1, CareerSettings[career].profile_name, career, true)

	local previous_unit = unit

	if not t.wait_until(function ()
		local new_unit = player_unit()

		return new_unit and new_unit ~= previous_unit and HEALTH_ALIVE[new_unit] and player_career_name() == career
	end, CONFIG.respawn_timeout, "the player to respawn as " .. career) then
		log("the game did not respawn the player as %s. The hero may be in use: play as %s first", career, CareerSettings[career].profile_name)

		return false
	end

	-- A moment for the new unit to settle
	t.wait(1)

	local new_unit = player_unit()

	install_input(new_unit)
	inventory_extension_of(new_unit):wield(suite.slot)

	if not t.wait_until(function ()
		return utils.wielded_template_name(player_unit()) == suite.template
	end, 10, "the weapon to be wielded") then
		log("the weapon was not wielded")

		return false
	end

	-- The wield has a delay before the weapon can be used
	t.wait(1.5)

	return true
end

local function run_suite(suite, only_career)
	local t = make_context(suite)
	local summary = {
		failed = 0,
		passed = 0,
		skipped = 0,
	}
	local careers = {}

	for _, career in ipairs(suite.careers) do
		if not only_career or only_career == career then
			careers[#careers + 1] = career
		end
	end

	-- What has to be put back, saved first
	local restore = {}
	local original_career = player_career_name()

	if not original_career then
		log("there is no player: start a mission first")

		return
	end

	for _, career in ipairs(careers) do
		restore[#restore + 1] = {
			backend_id = BackendUtils.get_loadout_item_id(career, suite.slot),
			career = career,
			slot = suite.slot,
		}
	end

	save_restore(restore)

	if not Window.has_focus() then
		log("the game window has no focus: the game ignores input without it")
	end

	for _, career in ipairs(careers) do
		log("%s as %s", suite.name, career)

		if not setup_character(t, suite, career) then
			summary.failed = summary.failed + 1
			result("FAIL %s %s: setup", suite.name, career)
		else
			for _, scenario_definition in ipairs(suite.scenarios) do
				local scenario = {
					failures = {},
					name = string.format("%s/%s/%s", suite.name, career, scenario_definition.name),
					spawned = {},
				}

				t.scenario(scenario)
				runner.explosion_watch = nil
				t.refill()

				local ok, error_value = call_waiting(scenario_definition.run, t)

				if not ok and not (type(error_value) == "table" and error_value.skip) then
					scenario.failures[#scenario.failures + 1] = tostring(error_value)
					log("FAIL %s: error: %s", scenario.name, tostring(error_value))
				end

				-- What the scenario made is taken away
				for _, spawned in ipairs(scenario.spawned) do
					if Unit.alive(spawned) then
						Managers.state.conflict:destroy_unit(spawned, BLACKBOARDS[spawned], "ut_test")
					end
				end

				runner.restore_input()
				install_input(player_unit())
				t.wait(0.5)

				if scenario.skipped then
					summary.skipped = summary.skipped + 1
					log("SKIP %s: %s", scenario.name, scenario.skipped)
					result("SKIP %s: %s", scenario.name, scenario.skipped)
				elseif #scenario.failures > 0 then
					summary.failed = summary.failed + 1
					result("FAIL %s: %s", scenario.name, table.concat(scenario.failures, "; "))
				else
					summary.passed = summary.passed + 1
					log("PASS %s", scenario.name)
					result("PASS %s", scenario.name)
				end

				if not player_unit() then
					log("the player is gone: the suite is stopped")
					summary.failed = summary.failed + 1

					break
				end
			end
		end
	end

	-- Putting everything back
	runner.restore_input()
	apply_restore(restore)
	save_restore(NOTHING_TO_RESTORE)

	if original_career and player_career_name() ~= original_career then
		Managers.state.network:request_profile(1, CareerSettings[original_career].profile_name, original_career, true)
	end

	log("%s: %d passed, %d failed, %d skipped", suite.name, summary.passed, summary.failed, summary.skipped)
	result("SUMMARY %s: %d passed, %d failed, %d skipped", suite.name, summary.passed, summary.failed, summary.skipped)
	result("DONE")
	write_result_file()
end

-- Starting and stopping
function runner.start(suite_name, career)
	if run and not run.finished and not run.error then
		log("a suite is running. /ut_test stop ends it")

		return
	end

	local suite = runner.suites[suite_name]

	if not suite then
		log("there is no suite %s. The suites: %s", tostring(suite_name), table.concat(table.keys(runner.suites), ", "))

		return
	end

	table.clear(result_lines)

	run = {
		co = coroutine.create(function ()
			run_suite(suite, career)
		end),
		suite = suite,
	}

	resume()
end

function runner.stop()
	if run then
		run = nil
		runner.restore_input()
		log("stopped. The loadout is put back the next time the mod loads, or run the suite again")
	end
end

function runner.add_suite(suite)
	runner.suites[suite.name] = suite
end

-- Each frame
local pending_restore_checked_t = 0

local function step(dt)
	if not run then
		return
	end

	if run.error then
		log("the suite broke: %s", tostring(run.error))
		result("ERROR %s", tostring(run.error))
		result("DONE")
		write_result_file()
		runner.restore_input()
		run = nil

		return
	end

	if run.finished then
		run = nil

		return
	end

	local waiting = run.waiting

	if not waiting then
		return
	end

	run.waited = run.waited + dt

	if waiting.frames then
		waiting.frames = waiting.frames - 1

		if waiting.frames <= 0 then
			resume(true)
		end
	elseif waiting.condition then
		local ok, satisfied = pcall(waiting.condition)

		if ok and satisfied then
			resume(true)
		elseif run.waited >= (waiting.seconds or 10) then
			if not waiting.quiet then
				log("timed out waiting for %s", tostring(waiting.what))
			end

			resume(false)
		end
	elseif run.waited >= (waiting.seconds or 0) then
		resume(true)
	end
end

-- A suite that was cut short, because the game was closed or the mod was reloaded, leaves the loadout as the suite set it. This puts it
-- back once the backend is there.
local function check_pending_restore(dt)
	pending_restore_checked_t = pending_restore_checked_t + dt

	if pending_restore_checked_t < 1 or run then
		return
	end

	pending_restore_checked_t = 0

	local entries = mod:get(RESTORE_SETTING)

	if type(entries) ~= "table" or #entries == 0 then
		return
	end

	-- The items are there once the player is in a level
	if not local_player() then
		return
	end

	local ok = pcall(function ()
		apply_restore(entries)
		save_restore(NOTHING_TO_RESTORE)
		log("put back the loadout of a suite that was cut short")
	end)

	if not ok then
		pending_restore_checked_t = -30
	end
end

-- A driver outside the game can start a suite by writing its command to a file that the mod reads, and reads the results from another.
-- This only works if the game's Lua has the io library, which nothing else of the mod uses. The files are in the game's folder in the
-- user's AppData (Fatshark\Vermintide 2).
local command_elapsed = 0

local function poll_command_file(dt)
	command_elapsed = command_elapsed + dt

	if command_elapsed < CONFIG.command_poll_interval then
		return
	end

	command_elapsed = 0

	local ok_io, io_lib = pcall(function ()
		return rawget(_G, "io")
	end)

	if not ok_io or not io_lib or not io_lib.open then
		return
	end

	if not runner.file_directory then
		local appdata = os and os.getenv and os.getenv("APPDATA")

		if not appdata then
			return
		end

		runner.file_directory = appdata .. "\\Fatshark\\Vermintide 2\\"
	end

	local file = io_lib.open(runner.file_directory .. CONFIG.command_file, "r")

	if not file then
		return
	end

	local line = file:read("*l")

	file:close()
	os.remove(runner.file_directory .. CONFIG.command_file)

	if not line or line == "" then
		return
	end

	local command, argument, career = string.match(line, "^(%S+)%s*(%S*)%s*(%S*)")

	if command == "run" and argument ~= "" then
		runner.start(argument, career ~= "" and career or nil)
	elseif command == "stop" then
		runner.stop()
	end
end

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	step(dt)
	check_pending_restore(dt)

	if not runner.poll_failed then
		local ok = pcall(poll_command_file, dt)

		-- Without the files, nothing more is tried
		runner.poll_failed = not ok
	end
end

mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
	runner.restore_input()
	mod.any_explosion_callbacks.ut_test = nil
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	if run then
		run = nil
		runner.restore_input()
	end
end

mod:command("ut_test", "list | stop | <suite> [career] - runs the in-game tests of a weapon", function (argument, career)
	if argument == "list" or not argument then
		log("suites: %s", table.concat(table.keys(runner.suites), ", "))
	elseif argument == "stop" then
		runner.stop()
	else
		runner.start(argument, career)
	end
end)

return runner
