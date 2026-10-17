local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- In-game tests. A suite is a weapon's tests: it sets up the character, career and weapon, runs its scenarios in a level that is loaded,
-- and puts everything back. It is run with the chat command /ut_test <suite>, several with /ut_test <suite> <suite> ..., or all of them
-- with /ut_test all. /ut_test <suite>:<words> runs only the scenarios whose names have the words (with _ for a space). It prints what
-- passed and failed to the chat and to the game's console log.
--
-- The suites run in a mission, Righteous Stand (CONFIG.default_level), on Legend (CONFIG.difficulty), with the level kept empty and the
-- player unhurt (the quiet flags).
-- The level is loaded at the start of a run, whatever level the player is in, so that nothing is left in it from before, and the player
-- is taken back to the level they were in at the end.
--
-- A scenario is a function of the test context `t`. It runs as a coroutine, one step a frame, so it can wait for the game:
--   t.wait(seconds)                      waits that long
--   t.wait_until(condition, seconds, what)   waits until condition() is true, and returns false if it took longer than the seconds
--   t.expect(condition, message, ...)    records a failure with the message (a format string) if the condition is false
--   t.skip(reason)                       ends the scenario as skipped
--   t.log(text, ...)                     a line in the results
--   t.press(name, seconds, observer)     holds an input of the player ("action_one", "action_two") for that long, then lets go. The
--                                        observer, if there is one, is called every frame while it is held.
--   t.hold(name), t.release(name)        puts an input down and lets it go, for inputs that overlap
--   t.tap(name)                          an input for one frame ("jump", "dodge", "crouch")
--   t.move(x, y)                         holds the movement keys (x to the right, y forward); t.move() lets go
--   t.set_input(name, value)             an input that stays at a value until it is set to nil
--   t.watch(seconds, observer)           calls the observer every frame for that long
--   t.unit()                             the player's unit
--   t.ammo()                             the ranged weapon's ammo
--   t.refill()                           fills it and takes the overcharge away (done before each scenario)
--   t.health(), t.heal()                 the player's health, and full health again
--   t.hurtable(on)                       lets the player be hurt (still not killed) until the end of the scenario
--   t.velocity(), t.position()           the player's velocity and the place of their feet, as x, y and z
--   t.on_ground(), t.state()             whether the player is on the ground, and their character state ("standing", "falling", ...)
--   t.overcharge(), t.wielded()          the player's overcharge, and the template of the weapon in their hands
--   t.look(pitch, turn)                  turns the player to look that far up and that far to the left (degrees)
--   t.go_to(name)                        puts the player in a named place of the level (CONFIG.named_places)
--   t.go_to_start()                      puts the player back in the suite's place
--   t.surface_ahead(distance)            where the player's aim hits the level within that distance, or nil
--   t.ground_at(ahead, right)            where the ground is that far ahead and to the right, as { x, y, z }
--   t.spawn(breed_name, distance)        spawns an enemy that distance ahead of the player on the ground, and returns it (nil if it could
--                                        not be spawned). It is removed after the scenario.
--   t.spawn_at(breed_name, x, y, z)      spawns an enemy there, facing the player
--   t.spawn_group(breed_name, count, distance)   spawns that many in rows ahead
--   t.spawn_target(distance)             spawns the enemy to shoot at (CONFIG.target_breed, which never attacks) that far ahead, waits
--                                        for it to settle, and turns the player to face it
--   t.remove(unit)                       takes an enemy away before the scenario ends
--   t.health_of(unit)                    a unit's health, 0 when it is dead
--   t.track_damage(unit)                 adds up all the damage the unit takes from now on, past what kills it, and keeps each hit
--   t.aim_at(unit)                       turns the player to face the middle of a unit
--   t.aim_at_point(x, y, z)              turns the player to face a point
--   t.projectiles(filter)                the units of the player's projectiles whose action the filter accepts
--   t.explosions()                       a list that is filled with the names of the explosions that happen from now on
--   t.sounds(prefix)                     a list that is filled with the names of the sound events that start with the prefix
--
-- A suite is { name, item (the key of the weapon item), template, slot, careers (the careers it is run for), level (the level it is run
-- in, if not the default one), fresh_level (the level is loaded again for it), loadout (optional: { [slot] = { [career] = item key } },
-- items of other slots put in for the suite and put back after it), place (optional: { level, position, yaw }, where the
-- player is put instead of the level's place in CONFIG.places), scenarios = { { name, run, place (a named place it starts in) } } }.
--
-- The tests change the player's loadout and career, and put them back at the end. The loadout is kept in the backend, so what has to be
-- put back is saved in the settings while a suite runs, and put back the next time the mod loads if a suite was cut short.

local utils = ut:dofile("scripts/mods/unreal_tournament/utils")

local runner = {
	suites = {},
	-- Functions that are called every frame while a scenario runs (see t.track_damage)
	frame_watchers = {},
}

local CONFIG = {
	-- How long the player's new unit may take to appear after a profile is requested
	respawn_timeout = 30, -- seconds
	-- How long an enemy may take to spawn. Its packages may have to be loaded.
	spawn_timeout = 30, -- seconds
	-- The enemy that the tests shoot at: the game's clan rat that sees nobody and never attacks, so it stands still and the hits
	-- land the same way every time. Hits still stagger it. The player aims at this node of it.
	target_breed = "skaven_dummy_clan_rat",
	target_node = "j_spine",
	-- How long a level may take to load
	level_timeout = 240, -- seconds
	-- How long a level must have no intro playing before it counts as started
	intro_settle_time = 1.5, -- seconds
	-- The player looks this far below level in a place (degrees). An enemy's middle 5 m ahead, where most tests put it, is about that
	-- far below the eyes of a tall career (1.7 m eyes, 0.8 m middle). Level aim goes over a clan rat's head.
	place_pitch = -10,
	-- The level the suites run in, unless a suite names another: Righteous Stand, a mission, where the game's own rules apply (the Keep
	-- has none of the fall damage, for one)
	default_level = "military",
	-- The difficulty the level is loaded at, Legend, so that the numbers do not change with the difficulty of the last game (the power
	-- cap and the enemies' health are the difficulty's)
	difficulty = "hardest",
	-- Where the player is put after each respawn and before each test, for each level, so that what is ahead of them is the same every
	-- time: the position (m) and the way they face (degrees about the up axis). A suite can name its own place. The other places of a
	-- level are for the tests that need something there, by name (t.go_to).
	places = {
		-- The Keep's spawn point, facing the courtyard
		inn_level_halloween = {
			position = { -18.997, -0.246, 6.193 },
			yaw = -90,
		},
		-- The square past the alley of the start, facing across it: flat for 8 m, and open for 28 m
		military = {
			position = { 154.329, 244.924, -17.457 },
			yaw = 135,
		},
	},
	-- (found with /ut_tp, /ut_where and /ut_probe)
	named_places = {
		military = {
			-- Further out on the square, with nothing above
			sky = {
				position = { 147.2, 237.8, -17.4 },
				yaw = 45,
			},
			-- Under the arch over the start's alley: a flat ceiling 4.8 m over the feet
			ceiling = {
				position = { 159.5, 250, -17.5 },
				yaw = 135,
			},
			-- In the alley, facing along it, with its wall 1.1 m to the left and the other 3.5 m to the right
			wall = {
				position = { 162, 252.5, -17.5 },
				yaw = 135,
			},
			-- On the low wall at the side of the square, facing the yard 4 m below it, which starts 1 m ahead
			ledge = {
				position = { 144.9, 240.1, -16.126 },
				yaw = 45,
			},
		},
	},
	-- The game's flags (script_data) that a suite sets, so that the level is empty and nothing hurts the player, and puts back at the end
	quiet_flags = {
		ai_bots_disabled = true,
		ai_boss_spawning_disabled = true,
		ai_critter_spawning_disabled = true,
		ai_horde_spawning_disabled = true,
		ai_mini_patrol_disabled = true,
		ai_pacing_disabled = true,
		ai_roaming_patrols_disabled = true,
		ai_roaming_spawning_disabled = true,
		ai_specials_spawning_disabled = true,
		ai_terror_events_disabled = true,
		disable_ai_perception = true,
		player_invincible = true,
		-- Without it the game does not let the intro of a level be skipped
		skippable_cutscenes = true,
	},
}

-- The enemy the suites shoot at (see target_breed)
runner.target_breed = CONFIG.target_breed

local RESTORE_SETTING = "test_restore"
-- What /ut_equip replaced. It is put back the next time the mod loads, or with /ut_equip back.
local EQUIP_SETTING = "equip_restore"

local function log(text, ...)
	mod:echo("[ut_test] " .. text, ...)
end

-- The game writes its console log to the file in blocks of 32 KB, so the last lines of a suite can wait there for minutes.
-- Printing a block of filler pushes them into the file, where tools/run_tests.ps1 reads them.
local LOG_BLOCK = 32768
local FILLER_LINE = string.rep("-", 1023)

local function push_log_out()
	for _ = 1, LOG_BLOCK / (#FILLER_LINE + 1) do
		print(FILLER_LINE)
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

local function current_level_key()
	return Managers.level_transition_handler:get_current_level_key()
end

-- Puts the player somewhere, standing still, as PlayerUnitLocomotionExtension.teleport_to does without the fall height, which fails
-- when it is called from a suite. The yaw is the way they face, in degrees about the up axis; without one they keep facing the way
-- they do. The pitch is how far they look up (degrees, below level is negative). On the main thread.
function runner.move_player(unit, position, yaw, pitch)
	local first_person_extension = ScriptUnit.extension(unit, "first_person_system")
	local locomotion_extension = ScriptUnit.extension(unit, "locomotion_system")

	if not yaw then
		local forward = Quaternion.forward(first_person_extension:current_rotation())

		yaw = math.deg(math.atan2(-Vector3.x(forward), Vector3.y(forward)))
	end

	Mover.set_position(Unit.mover(unit), position)
	Unit.set_local_position(unit, 0, position)
	local facing = Quaternion.axis_angle(Vector3.up(), math.rad(yaw))
	local tilt = Quaternion.axis_angle(Vector3.right(), math.rad(pitch or 0))

	first_person_extension:set_rotation(Quaternion.multiply(facing, tilt))
	locomotion_extension.velocity_current:store(Vector3.zero())
	locomotion_extension:set_forced_velocity(nil)
	locomotion_extension:move_to_non_intersecting_position()
end

local function inventory_extension_of(unit)
	return unit and ScriptUnit.has_extension(unit, "inventory_system")
end

-- Input that the tests press. It is put in front of the game's input service of the player, which is what the game reads the player's
-- buttons from.
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

		-- (a vector is kept boxed, since a vector lasts only a frame: { vector = Vector3Box })
		if type(value) == "table" and value.vector then
			return value.vector:unbox()
		elseif value ~= nil then
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
	table.clear(runner.frame_watchers)
end

-- What a test waits for, which the update goes through one frame at a time
local run

-- The game takes the player's input as blocked while the chat or a menu is open or the window has no focus, and then ignores the input
-- and raises the block by itself (CharacterStateHelper: a block action starts on blocked input), which is the Shield Gun's shield. While a
-- suite runs, the player's input is not taken as blocked, so a chat, a menu or another window in front changes nothing in the suite.
mod:hook(PlayerInputExtension, "is_input_blocked", function (func, self, ...)
	if run and self.unit == player_unit() then
		return false
	end

	return func(self, ...)
end)

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

	-- Puts an input down and keeps it down until t.release, for inputs that overlap (holding one button and pressing another)
	function t.hold(name)
		injected[name] = true
		injected[name .. "_hold"] = true

		yield({
			frames = 1,
		})

		injected[name] = nil
	end

	function t.release(name)
		injected[name .. "_hold"] = nil
		injected[name .. "_release"] = true

		yield({
			frames = 1,
		})

		injected[name .. "_release"] = nil
	end

	-- An input that is on for a single frame, such as "jump" or "dodge"
	function t.tap(name)
		injected[name] = true

		yield({
			frames = 1,
		})

		injected[name] = nil
	end

	-- Holds the movement keys: x to the right, y forward, each -1 to 1. No arguments lets go.
	function t.move(x, y)
		injected.move = x and {
			vector = Vector3Box(x, y or 0, 0),
		} or nil
	end

	-- An input that stays at a value until it is set to nil
	function t.set_input(name, value)
		injected[name] = value
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

	-- Fills the ammo, and takes the overcharge away, so that each scenario starts with a weapon that has not been used
	function t.refill()
		local extension = ammo_extension()

		if extension then
			extension:add_ammo()
		end

		local unit = player_unit()
		local overcharge_extension = unit and ScriptUnit.has_extension(unit, "overcharge_system")

		if overcharge_extension and not overcharge_extension:are_you_exploding() then
			overcharge_extension:remove_charge(overcharge_extension:get_overcharge_value())
		end
	end

	-- Some engine calls refuse a reference that comes from another Lua state, and a coroutine is one. So the calls that use the world, the
	-- physics and the spawning are made on the main thread, by the update.
	local function on_main_thread(fn)
		local reply = yield({
			main = fn,
		})

		if not reply.ok then
			error(reply.value, 0)
		end

		return reply.value
	end

	t.on_main_thread = on_main_thread

	-- Runs a function that uses the engine: on the main thread from a scenario, and as it is from an observer, which the update calls
	local function engine(fn)
		if coroutine.running() then
			return on_main_thread(fn)
		end

		return fn()
	end

	local function extension(name)
		local unit = player_unit()

		return unit and ScriptUnit.has_extension(unit, name)
	end

	-- The player's health, with the temporary health
	function t.health()
		return engine(function ()
			local health_extension = extension("health_system")

			return health_extension and health_extension:current_health()
		end)
	end

	-- Whether the player can be hurt. A suite makes them invincible. While hurtable, they still cannot die (player_unkillable). The
	-- runner makes them invincible and heals them again after each scenario.
	function t.hurtable(on)
		script_data.player_invincible = not on
		script_data.player_unkillable = on or nil
		scenario.hurtable = on
	end

	function t.heal()
		engine(function ()
			local health_extension = extension("health_system")

			if health_extension then
				health_extension:reset()
			end
		end)
	end

	-- The player's velocity (m/s) as x, y and z
	function t.velocity()
		return unpack(engine(function ()
			local locomotion_extension = extension("locomotion_system")

			if not locomotion_extension then
				return { 0, 0, 0 }
			end

			local velocity = locomotion_extension:current_velocity()

			return { Vector3.x(velocity), Vector3.y(velocity), Vector3.z(velocity) }
		end))
	end

	-- Where the player's feet are, as x, y and z
	function t.position()
		return unpack(engine(function ()
			local unit = player_unit()

			if not unit then
				return { 0, 0, 0 }
			end

			local position = Unit.local_position(unit, 0)

			return { Vector3.x(position), Vector3.y(position), Vector3.z(position) }
		end))
	end

	function t.on_ground()
		return engine(function ()
			local locomotion_extension = extension("locomotion_system")

			return locomotion_extension ~= nil and locomotion_extension:is_on_ground()
		end)
	end

	function t.overcharge()
		return engine(function ()
			local overcharge_extension = extension("overcharge_system")

			return overcharge_extension and overcharge_extension:get_overcharge_value() or 0
		end)
	end

	-- The template of the weapon in the player's hands
	function t.wielded()
		return engine(function ()
			return utils.wielded_template_name(player_unit())
		end)
	end

	-- The player's character state ("standing", "walking", "jumping", "falling", "dodging", ...)
	function t.state()
		return engine(function ()
			local unit = player_unit()
			local csm = unit and ScriptUnit.extension(unit, "character_state_machine_system").state_machine

			return csm and csm.state_current and csm.state_current.name
		end)
	end

	-- The health of a unit, 0 when it is dead or gone
	function t.health_of(unit)
		return engine(function ()
			if not unit or not Unit.alive(unit) or not HEALTH_ALIVE[unit] then
				return 0
			end

			return ScriptUnit.extension(unit, "health_system"):current_health()
		end)
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
		return on_main_thread(function ()
			local origin, forward = aim()

			if not origin then
				return nil
			end

			local hit, _, hit_distance = PhysicsWorld.immediate_raycast(physics_world(), origin, forward, distance, "closest", "collision_filter", "filter_ai_line_of_sight_check")

			if hit then
				return origin + forward * hit_distance
			end

			return nil
		end)
	end

	-- Where the ground is, that far ahead of the player (on the main thread), and the way the player faces on the ground
	local function ground_ahead(distance)
		local origin, forward = aim()

		if not origin then
			return nil
		end

		local flat = Vector3.normalize(Vector3.flat(forward))
		local above = origin + flat * distance + Vector3(0, 0, 2)
		local hit, _, hit_distance = PhysicsWorld.immediate_raycast(physics_world(), above, Vector3.down(), 8, "closest", "collision_filter", "filter_ai_line_of_sight_check")

		if not hit then
			return nil
		end

		return above - Vector3(0, 0, hit_distance), flat
	end

	function t.ground_ahead(distance)
		return on_main_thread(function ()
			return ground_ahead(distance) ~= nil
		end)
	end

	function t.spawn(breed_name, distance)
		local spawned

		local started = on_main_thread(function ()
			local breed = Breeds[breed_name]
			local position, flat = ground_ahead(distance)

			if not position or not breed then
				return false
			end

			local optional_data = {
				spawned_func = function (unit)
					runner.calm(unit)

					spawned = unit
				end,
			}

			Managers.state.conflict:spawn_one(breed, position, nil, optional_data, Quaternion.look(-flat, Vector3.up()))

			return true
		end)

		if not started then
			return nil
		end

		if not t.wait_until(function ()
			return spawned ~= nil
		end, CONFIG.spawn_timeout, "the enemy to spawn") then
			return nil
		end

		scenario.spawned[#scenario.spawned + 1] = spawned

		return spawned
	end

	-- Spawns a number of enemies at once, in rows across the way the player faces, starting that distance ahead, and returns them (as many
	-- as spawned). They are removed after the scenario.
	function t.spawn_group(breed_name, count, distance)
		local spawned = {}

		on_main_thread(function ()
			local breed = Breeds[breed_name]
			local origin, forward = aim()
			local flat = Vector3.normalize(Vector3.flat(forward))
			local side = Vector3.cross(flat, Vector3.up())

			for i = 1, count do
				local row, column = math.floor((i - 1) / 5), (i - 1) % 5
				local above = origin + flat * (distance + row) + side * (column - 2) + Vector3(0, 0, 2)
				local hit, _, hit_distance = PhysicsWorld.immediate_raycast(physics_world(), above, Vector3.down(), 8, "closest", "collision_filter", "filter_ai_line_of_sight_check")

				if hit then
					Managers.state.conflict:spawn_one(breed, above - Vector3(0, 0, hit_distance), nil, {
						spawned_func = function (unit)
							runner.calm(unit)

							spawned[#spawned + 1] = unit
						end,
					}, Quaternion.look(-flat, Vector3.up()))
				end
			end
		end)

		t.wait_until(function ()
			return #spawned >= count
		end, CONFIG.spawn_timeout, "the enemies to spawn")

		for _, unit in ipairs(spawned) do
			scenario.spawned[#scenario.spawned + 1] = unit
		end

		return spawned
	end

	-- Turns the player to face the middle of a unit's body
	function t.aim_at(unit)
		on_main_thread(function ()
			local player = player_unit()
			local first_person_extension = player and ScriptUnit.has_extension(player, "first_person_system")

			if not first_person_extension or not Unit.alive(unit) then
				return
			end

			local node = Unit.has_node(unit, CONFIG.target_node) and Unit.node(unit, CONFIG.target_node) or 0
			local direction = Vector3.normalize(Unit.world_position(unit, node) - first_person_extension:current_position())

			first_person_extension:set_rotation(Quaternion.look(direction, Vector3.up()))
		end)

		-- A shot sets the view to the camera's rotation (PlayerUnitFirstPerson.apply_recoil), and the camera follows the view a frame
		-- later. A shot right away would turn the view back.
		t.wait(0.1)
	end

	-- Turns the player to face a point given as x, y, z
	function t.aim_at_point(x, y, z)
		on_main_thread(function ()
			local player = player_unit()
			local first_person_extension = player and ScriptUnit.has_extension(player, "first_person_system")

			if first_person_extension then
				local direction = Vector3.normalize(Vector3(x, y, z) - first_person_extension:current_position())

				first_person_extension:set_rotation(Quaternion.look(direction, Vector3.up()))
			end
		end)

		-- (the camera follows the view a frame later, see aim_at)
		t.wait(0.1)
	end

	-- Turns the player to look this far up (degrees, negative is down), and this far to the left of the way they face (degrees)
	function t.look(pitch, turn)
		on_main_thread(function ()
			local unit = player_unit()
			local first_person_extension = unit and ScriptUnit.has_extension(unit, "first_person_system")

			if not first_person_extension then
				return
			end

			local forward = Quaternion.forward(first_person_extension:current_rotation())
			local yaw = math.atan2(-Vector3.x(forward), Vector3.y(forward)) + math.rad(turn or 0)
			local facing = Quaternion.axis_angle(Vector3.up(), yaw)
			local tilt = Quaternion.axis_angle(Vector3.right(), math.rad(pitch or 0))

			first_person_extension:set_rotation(Quaternion.multiply(facing, tilt))
		end)

		-- (the camera follows the view a frame later, see aim_at)
		t.wait(0.1)
	end

	-- Spawns an enemy at a place given as x, y, z, facing the player. Removed after the scenario.
	function t.spawn_at(breed_name, x, y, z)
		local spawned

		on_main_thread(function ()
			local position = Vector3(x, y, z)
			local to_player = Vector3.flat(Unit.local_position(player_unit(), 0) - position)
			local facing = Vector3.length(to_player) > 0.01 and Vector3.normalize(to_player) or Vector3.forward()

			Managers.state.conflict:spawn_one(Breeds[breed_name], position, nil, {
				spawned_func = function (unit)
					runner.calm(unit)

					spawned = unit
				end,
			}, Quaternion.look(facing, Vector3.up()))
		end)

		if not t.wait_until(function ()
			return spawned ~= nil
		end, CONFIG.spawn_timeout, "the enemy to spawn") then
			return nil
		end

		scenario.spawned[#scenario.spawned + 1] = spawned

		return spawned
	end

	-- Where the ground is, a distance ahead of the player and a distance to their right, as x, y and z
	function t.ground_at(ahead, right)
		return on_main_thread(function ()
			local origin, forward = aim()

			if not origin then
				return nil
			end

			local flat = Vector3.normalize(Vector3.flat(forward))
			local side = Vector3.cross(flat, Vector3.up())
			local above = origin + flat * ahead + side * (right or 0) + Vector3(0, 0, 2)
			local hit, _, hit_distance = PhysicsWorld.immediate_raycast(physics_world(), above, Vector3.down(), 8, "closest", "collision_filter", "filter_ai_line_of_sight_check")

			if not hit then
				return nil
			end

			local ground = above - Vector3(0, 0, hit_distance)

			return { Vector3.x(ground), Vector3.y(ground), Vector3.z(ground) }
		end)
	end

	-- Adds up the damage a unit takes from now on, all of it, past what kills it: { total, hits }, with each hit as { amount, source,
	-- type, attacker }. The game keeps the damage of the last frame (GenericHealthExtension.recent_damages), which is read every frame
	-- until the scenario ends.
	function t.track_damage(unit)
		local record = {
			hits = {},
			total = 0,
		}

		runner.frame_watchers[#runner.frame_watchers + 1] = function ()
			local health_extension = Unit.alive(unit) and ScriptUnit.has_extension(unit, "health_system")
			local damages, length

			if health_extension and health_extension.recent_damages then
				damages, length = health_extension:recent_damages()
			end

			for i = 1, length or 0, DamageDataIndex.STRIDE do
				local amount = damages[i + DamageDataIndex.DAMAGE_AMOUNT - 1]
				local attacker = damages[i + DamageDataIndex.ATTACKER - 1]

				record.total = record.total + amount
				record.hits[#record.hits + 1] = {
					amount = amount,
					attacker = attacker and attacker == player_unit() and "self" or attacker and Unit.alive(attacker) and Unit.get_data(attacker, "breed") and Unit.get_data(attacker, "breed").name or "other",
					source = damages[i + DamageDataIndex.DAMAGE_SOURCE_NAME - 1],
					type = damages[i + DamageDataIndex.DAMAGE_TYPE - 1],
				}
			end
		end

		return record
	end

	-- Takes away an enemy the scenario spawned, before the scenario ends. It is taken off the list of what the runner takes away after the
	-- scenario: the game keeps a unit it takes away for later (it freezes it), and taking it away twice crashes the game.
	function t.remove(unit)
		on_main_thread(function ()
			if Unit.alive(unit) then
				Managers.state.conflict:destroy_unit(unit, BLACKBOARDS[unit], "ut_test")
			end
		end)

		for i = #scenario.spawned, 1, -1 do
			if scenario.spawned[i] == unit then
				table.remove(scenario.spawned, i)
			end
		end
	end

	-- Fights a horde for a while: enemies of the settings' kinds that attack come out in a block ahead, and more come once few stand. Before
	-- each attack the player is put the settings' distance from the nearest enemy, and attack(nearest) attacks it. Says how many were
	-- killed every 30 s, and returns that count and runner.watch_motion_calls's counts. The settings: size (how many enemies), breeds,
	-- refill_below (more come once fewer stand), distance (m, how far ahead the block is), keep (m, how far from the nearest the player
	-- stands) and time (s).
	function t.fight_horde(settings, attack)
		local spots = {}
		local seen = {}
		local killed = 0
		local last_fill

		-- The block is 8 by 8 places, 0.6 m apart
		for row = 0, 7 do
			for column = 0, 7 do
				local ground = t.ground_at(settings.distance + row * 0.6, (column - 3.5) * 0.6)

				if ground then
					spots[#spots + 1] = ground
				end
			end
		end

		if #spots == 0 then
			t.expect(false, "there is no room for the horde")

			return 0, {}
		end

		local stop_watching_motion = runner.watch_motion_calls()
		local ok, problem = pcall(function ()
			local started = Managers.time:time("game")
			local said = started

			while Managers.time:time("game") - started < settings.time do
				-- The enemies standing, more if they are few, and the nearest of them
				local state = on_main_thread(function ()
					local player = player_unit()
					local position = Unit.world_position(player, 0)
					local found, found_distance
					local count = 0

					for _, unit in ipairs(Managers.state.conflict:spawned_enemies()) do
						if HEALTH_ALIVE[unit] then
							count = count + 1
							seen[unit] = true

							local distance = Vector3.distance(position, Unit.world_position(unit, 0))

							if not found or distance < found_distance then
								found, found_distance = unit, distance
							end
						end
					end

					for unit in pairs(seen) do
						if not HEALTH_ALIVE[unit] then
							seen[unit] = nil
							killed = killed + 1
						end
					end

					-- (enemies take some frames to come out, and are counted once they have)
					local now = Managers.time:time("game")

					if count < settings.refill_below and (not last_fill or now - last_fill > 3) then
						last_fill = now

						for i = 1, settings.size - count do
							local breed = Breeds[settings.breeds[i % #settings.breeds + 1]]

							Managers.state.conflict:spawn_one(breed, Vector3(unpack(spots[math.random(#spots)])), nil, {}, Quaternion.identity())
						end
					end

					if found then
						local at = Unit.world_position(found, 0)

						runner.move_player(player, at + Vector3.normalize(Vector3.flat(position - at)) * settings.keep)
					end

					return {
						nearest = found,
						standing = count,
					}
				end)

				if state.nearest then
					attack(state.nearest)
				else
					t.wait(1)
				end

				if Managers.time:time("game") - said > 30 then
					said = Managers.time:time("game")

					t.log("%d enemies killed, %d standing", killed, state.standing)
				end
			end
		end)
		local motion_calls = stop_watching_motion()

		if not ok then
			error(problem, 0)
		end

		for where, count in pairs(motion_calls) do
			t.log("%s: %d calls, %d on a kinematic part, %d on a frozen unit", where, count[1], count[2], count[3])
		end

		t.log("%d enemies killed", killed)

		return killed, motion_calls
	end

	-- A line in the results, for what a scenario found that is not a failure
	function t.log(text, ...)
		log("%s: " .. text, scenario.name, ...)
	end

	-- Puts the player in a named place of the level (CONFIG.named_places), facing its way. Skips the scenario if the level has no
	-- such place.
	function t.go_to(name)
		local places = CONFIG.named_places[current_level_key()]
		local place = places and places[name]

		if not place then
			t.skip(string.format("%s has no place %s", tostring(current_level_key()), name))
		end

		on_main_thread(function ()
			runner.move_player(player_unit(), Vector3(unpack(place.position)), place.yaw, place.pitch or 0)
		end)
		t.wait(0.5)
	end

	-- The names of the sound events the game plays from now on, of those that start with the prefix. The list is filled until the end
	-- of the scenario.
	function t.sounds(prefix)
		local names = {}

		runner.sound_watch = {
			names = names,
			prefix = prefix,
		}

		return names
	end

	function t.spawn_target(distance)
		local target = t.spawn(CONFIG.target_breed, distance)

		if not target then
			return nil
		end

		-- Its health is only set some frames after it is spawned, and it lands on the ground
		t.wait(1)
		t.aim_at(target)

		return target
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

	-- (and names.positions[i] is where explosion i was, as { x, y, z })
	function t.explosions()
		local names = {
			positions = {},
		}

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

ut.any_explosion_callbacks.ut_test = function (explosion_template, position)
	local watch = runner.explosion_watch

	if watch then
		watch[#watch + 1] = explosion_template.name
		watch.positions[#watch] = { Vector3.x(position), Vector3.y(position), Vector3.z(position) }
	end
end

-- The sound events a scenario watches for (t.sounds)
mod:hook_safe(WwiseWorld, "trigger_event", function (wwise_world, event_name)
	local watch = runner.sound_watch

	if watch and type(event_name) == "string" and string.sub(event_name, 1, #watch.prefix) == watch.prefix then
		watch.names[#watch.names + 1] = event_name
	end
end)

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

-- Puts the player in the suite's place, or the level's, standing still and looking level. Returns false and says why if the place is
-- in another level. In a level without a place, the place is where the player was the first time after they spawned.
local function go_to_place(t, suite)
	local place = suite.place or CONFIG.places[current_level_key()]

	if place and place.level and place.level ~= current_level_key() then
		log("the suite's place is in %s", place.level)

		return false
	end

	if not place then
		t.spawn_place = t.spawn_place or t.on_main_thread(function ()
			local unit = player_unit()
			local position = Unit.local_position(unit, 0)
			local forward = Quaternion.forward(ScriptUnit.extension(unit, "first_person_system"):current_rotation())

			return {
				position = { Vector3.x(position), Vector3.y(position), Vector3.z(position) },
				yaw = math.deg(math.atan2(-Vector3.x(forward), Vector3.y(forward))),
			}
		end)
		place = t.spawn_place
	end

	t.on_main_thread(function ()
		runner.move_player(player_unit(), Vector3(unpack(place.position)), place.yaw, place.pitch or CONFIG.place_pitch)
	end)
	t.wait(0.5)

	return true
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

	-- (the items of the other slots the suite names, by the career)
	for slot, items in pairs(suite.loadout or {}) do
		if items[career] and not BackendUtils.try_set_loadout_item(career, slot, items[career]) then
			log("%s is not in the inventory", items[career])

			return false
		end
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

	t.spawn_place = nil

	if not go_to_place(t, suite) then
		return false
	end

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

-- The game's flags for an empty level where nothing hurts the player. Returns the function that puts them back.
local function set_quiet_flags()
	local previous = {}

	for flag, value in pairs(CONFIG.quiet_flags) do
		previous[flag] = script_data[flag]
		script_data[flag] = value
	end

	return function ()
		for flag, value in pairs(previous) do
			script_data[flag] = value
		end

		for flag in pairs(CONFIG.quiet_flags) do
			if previous[flag] == nil then
				script_data[flag] = nil
			end
		end
	end
end

-- Loads a level the way the game's own automated tests do, and waits until the player has spawned in it. The level exit that this
-- causes does not stop the suite.
local function load_level(t, level_key)
	local previous_unit = player_unit()

	run.loading = true

	-- (the game takes the difficulty of the next level from this setting first, LevelTransitionHandler.apply_defaults_to_level_data)
	t.on_main_thread(function ()
		local difficulty_setting = script_data.current_difficulty_setting

		script_data.current_difficulty_setting = CONFIG.difficulty

		Managers.mechanism:debug_load_level(level_key, 0)

		script_data.current_difficulty_setting = difficulty_setting
	end)

	-- The level starts with an intro fly-over. It is skipped as soon as it starts, the way the game's own tests skip it, so the test begins in
	-- first person. It is done once no intro has been playing for a moment.
	local quiet_since

	local loaded = t.wait_until(function ()
		local unit = player_unit()

		if current_level_key() ~= level_key or Managers.level_transition_handler:needs_level_load() or not unit or unit == previous_unit or not HEALTH_ALIVE[unit] then
			return false
		end

		local cutscene_system = Managers.state.entity:system("cutscene_system")
		local now = Managers.time:time("main")

		if cutscene_system:is_active() then
			cutscene_system:skip_pressed()

			quiet_since = nil

			return false
		end

		quiet_since = quiet_since or now

		return now - quiet_since >= CONFIG.intro_settle_time
	end, CONFIG.level_timeout, "the level " .. level_key .. " to load")

	run.loading = false

	return loaded
end

local function run_suite(suite, only_career)
	local t = make_context(suite)

	-- Puts the player back where the scenario started, in the middle of a scenario
	function t.go_to_start()
		go_to_place(t, suite)
	end

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

	if not player_career_name() then
		log("there is no player: start a mission first")

		return
	end

	for _, career in ipairs(careers) do
		restore[#restore + 1] = {
			backend_id = BackendUtils.get_loadout_item_id(career, suite.slot),
			career = career,
			slot = suite.slot,
		}

		for slot in pairs(suite.loadout or {}) do
			restore[#restore + 1] = {
				backend_id = BackendUtils.get_loadout_item_id(career, slot),
				career = career,
				slot = slot,
			}
		end
	end

	save_restore(restore)

	run.restore_flags = set_quiet_flags()

	-- The suite's level. A suite that needs a level as it is at the start (nothing has died in it yet) has it loaded again.
	local level = suite.level or CONFIG.default_level
	-- (the level is loaded again if it is at another difficulty, and at the start of a run, so that nothing is left in it from before)
	local wrong_difficulty = Managers.state.difficulty:get_difficulty() ~= CONFIG.difficulty

	if current_level_key() ~= level or suite.fresh_level or wrong_difficulty or not run.level_loaded then
		log("loading %s", level)

		if not load_level(t, level) then
			log("the level did not load")
			run.restore_flags()
			run.restore_flags = nil
			apply_restore(restore)
			save_restore(NOTHING_TO_RESTORE)

			return
		end

		run.level_loaded = true
	end

	for _, career in ipairs(careers) do
		log("%s as %s", suite.name, career)

		if not setup_character(t, suite, career) then
			summary.failed = summary.failed + 1
		else
			for _, scenario_definition in ipairs(suite.scenarios) do
				local scenario = {
					failures = {},
					name = string.format("%s/%s/%s", suite.name, career, scenario_definition.name),
					spawned = {},
				}

				t.scenario(scenario)
				log("RUNNING %s", scenario.name)
				runner.explosion_watch = nil
				runner.sound_watch = nil
				table.clear(runner.frame_watchers)
				t.refill()

				-- Each scenario starts in the same place, whatever the last one did to where the player is and where they look
				if not go_to_place(t, suite) then
					break
				end

				local ok, error_value = call_waiting(function ()
					-- (a scenario can start in a named place of the level instead)
					if scenario_definition.place then
						t.go_to(scenario_definition.place)
					end

					scenario_definition.run(t)
				end)

				if not ok and not (type(error_value) == "table" and error_value.skip) then
					scenario.failures[#scenario.failures + 1] = tostring(error_value)
					log("FAIL %s: error: %s", scenario.name, tostring(error_value))
				end

				-- What the scenario made is taken away
				if #scenario.spawned > 0 then
					t.on_main_thread(function ()
						for _, spawned in ipairs(scenario.spawned) do
							if Unit.alive(spawned) then
								Managers.state.conflict:destroy_unit(spawned, BLACKBOARDS[spawned], "ut_test")
							end
						end
					end)
				end

				runner.restore_input()
				runner.sound_watch = nil
				table.clear(runner.frame_watchers)
				install_input(player_unit())

				if scenario.hurtable then
					t.hurtable(false)
				end

				t.heal()
				t.wait(0.5)

				if scenario.skipped then
					summary.skipped = summary.skipped + 1
					log("SKIP %s: %s", scenario.name, scenario.skipped)
				elseif #scenario.failures > 0 then
					summary.failed = summary.failed + 1
				else
					summary.passed = summary.passed + 1
					log("PASS %s", scenario.name)
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

	if run.restore_flags then
		run.restore_flags()
		run.restore_flags = nil
	end

	log("%s: %d passed, %d failed, %d skipped", suite.name, summary.passed, summary.failed, summary.skipped)
	push_log_out()

	return summary
end

-- Runs suites one after the other. The player gets their own career back once, at the end. The last line says that all is done,
-- which is what tools/run_tests.ps1 waits for.
local function run_suites(suites, career)
	local original_career = player_career_name()
	local original_level = current_level_key()
	local total = {
		failed = 0,
		passed = 0,
		skipped = 0,
	}

	for _, suite in ipairs(suites) do
		local summary = run_suite(suite, career)

		if not summary then
			break
		end

		total.failed = total.failed + summary.failed
		total.passed = total.passed + summary.passed
		total.skipped = total.skipped + summary.skipped
	end

	-- The player is taken back to the level they were in, once, after all the suites
	if current_level_key() ~= original_level then
		log("going back to %s", original_level)
		load_level(make_context(suites[1]), original_level)
	end

	if original_career and player_career_name() ~= original_career then
		Managers.state.network:request_profile(1, CareerSettings[original_career].profile_name, original_career, true)
	end

	log("done: %d suites, %d passed, %d failed, %d skipped", #suites, total.passed, total.failed, total.skipped)
	push_log_out()
end

-- Starting and stopping. The names are a list of suites, or "all".
function runner.start(names, career)
	if run and not run.finished and not run.error then
		log("a suite is running. /ut_test stop ends it")
		push_log_out()

		return
	end

	if #names == 1 and names[1] == "all" then
		names = table.keys(runner.suites)
		table.sort(names)
	end

	local suites = {}

	for _, name in ipairs(names) do
		-- (suite:words runs only the scenarios of the suite whose names have the words in them, with _ for a space)
		local suite_name, words = string.match(name, "^([^:]+):(.+)$")

		words = words and string.gsub(words, "_", " ")
		local suite = runner.suites[suite_name or name]

		if not suite then
			log("there is no suite %s. The suites: %s", tostring(name), table.concat(table.keys(runner.suites), ", "))
			push_log_out()

			return
		end

		if words then
			local only = {}

			for _, scenario in ipairs(suite.scenarios) do
				if string.find(scenario.name, words, 1, true) then
					only[#only + 1] = scenario
				end
			end

			suite = setmetatable({
				scenarios = only,
			}, {
				__index = suite,
			})
		end

		suites[#suites + 1] = suite
	end

	run = {
		co = coroutine.create(function ()
			run_suites(suites, career)
		end),
	}

	resume()
end

function runner.stop()
	if run then
		if run.restore_flags then
			run.restore_flags()
		end

		run = nil
		runner.restore_input()
		log("stopped. The loadout is put back the next time the mod loads, or run the suite again")
	end
end

function runner.add_suite(suite)
	runner.suites[suite.name] = suite
end

-- Makes an enemy see nobody and pick no one to go for, as the game's dummies do (breed_skaven_dummy_clan_rat), so that it stands
-- where it was spawned. The game's flag for this (disable_ai_perception) is only read as the game starts. Being hit still gives an
-- enemy a target (an alert, a stagger, a boss's own reaction), so the target is taken away again every frame, and alerts are not
-- trusted (only_trust_your_own_eyes).
local calmed = setmetatable({}, {
	__mode = "k",
})

local function keep_calm(unit)
	local ai_extension = ScriptUnit.has_extension(unit, "ai_system")
	local blackboard = BLACKBOARDS[unit]

	if ai_extension and ai_extension.set_perception then
		ai_extension:set_perception("perception_no_seeing", "pick_no_targets")
	end

	if blackboard then
		blackboard.only_trust_your_own_eyes = true
		blackboard.target_unit = nil
		blackboard.delayed_target_unit = nil
	end
end

function runner.calm(unit)
	calmed[unit] = true

	keep_calm(unit)
end

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	for unit in pairs(calmed) do
		if HEALTH_ALIVE[unit] then
			keep_calm(unit)
		else
			calmed[unit] = nil
		end
	end
end

-- The engine's calls that change a part: those whose names start so (add_impulse, push, set_velocity, teleport_position, wake_up...).
-- A part that animation moves (kinematic) must not be given a push, which PhysX applies as a force.
local MOTION_CALL_PREFIXES = { "add_", "push", "set_", "teleport", "wake", "put_to_sleep" }

-- Counts, from now until the returned function is called, the calls above by every script, the game's too: for each line that made
-- one, how many, how many on a kinematic part, and how many on a unit the game froze. The returned function puts the calls back and
-- gives the counts as { [where] = { calls, kinematic, frozen } }.
function runner.watch_motion_calls()
	local counts = {}
	local originals = {}
	local names = {}

	for name, value in pairs(Actor) do
		for _, prefix in ipairs(MOTION_CALL_PREFIXES) do
			if type(value) == "function" and string.sub(name, 1, #prefix) == prefix then
				names[#names + 1] = name
			end
		end
	end

	for _, name in ipairs(names) do
		local original = Actor[name]

		if type(original) == "function" then
			originals[name] = original

			Actor[name] = function (actor, ...)
				local caller = debug.getinfo(2, "Sl")
				local where = string.format("%s %s:%d", name, caller and caller.short_src or "?", caller and caller.currentline or 0)
				local count = counts[where] or { 0, 0, 0 }
				local unit = Actor.unit(actor)

				counts[where] = count
				count[1] = count[1] + 1

				if Actor.is_dynamic(actor) and not Actor.is_physical(actor) then
					count[2] = count[2] + 1
				end

				if unit and FROZEN[unit] then
					count[3] = count[3] + 1
				end

				return original(actor, ...)
			end
		end
	end

	return function ()
		for name, original in pairs(originals) do
			Actor[name] = original
		end

		return counts
	end
end

-- Puts a suite's weapon in the player's hands, and leaves it there, for looking at it and playing with it. The loadout that is replaced
-- is saved, as it is for a suite, and put back with /ut_equip back.
function runner.equip(suite_name, career)
	if run and not run.finished and not run.error then
		log("a suite is running. /ut_test stop ends it")

		return
	end

	local suite = runner.suites[suite_name]

	if not suite then
		log("there is no suite %s. The suites: %s", tostring(suite_name), table.concat(table.keys(runner.suites), ", "))

		return
	end

	career = career or suite.careers[1]

	run = {
		co = coroutine.create(function ()
			local t = make_context(suite)
			local saved_entries = mod:get(EQUIP_SETTING)

			-- What a weapon that was equipped before replaced is still what is to be put back
			if type(saved_entries) ~= "table" or #saved_entries == 0 then
				mod:set(EQUIP_SETTING, {
					{
						backend_id = BackendUtils.get_loadout_item_id(career, suite.slot),
						career = career,
						slot = suite.slot,
					},
				})
			end

			if setup_character(t, suite, career) then
				log("%s is in your hands as %s", suite.item, career)
			end
		end),
		suite = suite,
	}

	resume()
end

-- Puts back what /ut_equip replaced
function runner.unequip()
	local entries = mod:get(EQUIP_SETTING)

	if type(entries) ~= "table" or #entries == 0 then
		log("nothing was equipped")

		return
	end

	apply_restore(entries)
	mod:set(EQUIP_SETTING, NOTHING_TO_RESTORE)
	log("the loadout is put back. The weapon changes when the character spawns again")
end

-- Each frame
local pending_restore_checked_t = 0
local equip_checked = false

local function step(dt)
	if not run then
		return
	end

	if run.error then
		log("the suite broke: %s", tostring(run.error))
		push_log_out()

		if run.restore_flags then
			run.restore_flags()
		end

		runner.restore_input()
		run = nil

		return
	end

	if run.finished then
		run = nil

		return
	end

	for _, watcher in ipairs(runner.frame_watchers) do
		pcall(watcher)
	end

	local waiting = run.waiting

	if not waiting then
		return
	end

	run.waited = run.waited + dt

	if waiting.main then
		local ok, value = pcall(waiting.main)

		resume({
			ok = ok,
			value = value,
		})
	elseif waiting.frames then
		waiting.frames = waiting.frames - 1

		if waiting.frames <= 0 then
			resume(true)
		end
	elseif waiting.condition then
		local ok, satisfied = pcall(waiting.condition)

		-- (an error in what a test watches is said once, and the wait goes on)
		if not ok and not waiting.error_said then
			waiting.error_said = true

			log("error in a watch: %s", tostring(satisfied))
		end

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

	-- The items are there once the player is in a level
	if not local_player() then
		return
	end

	local entries = mod:get(RESTORE_SETTING)

	-- A weapon put in the player's hands with /ut_equip is taken out again when the mod loads
	if not equip_checked then
		equip_checked = true

		local equipped = mod:get(EQUIP_SETTING)

		if type(equipped) == "table" and #equipped > 0 then
			pcall(function ()
				apply_restore(equipped)
				mod:set(EQUIP_SETTING, NOTHING_TO_RESTORE)
			end)
		end
	end

	if type(entries) ~= "table" or #entries == 0 then
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

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	step(dt)
	check_pending_restore(dt)
end

mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
	runner.restore_input()
	ut.any_explosion_callbacks.ut_test = nil
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	if run and not run.loading then
		if run.restore_flags then
			run.restore_flags()
		end

		run = nil
		runner.restore_input()
	end
end

-- For looking at a weapon: an enemy that stands still in front of the player, and the flags that keep the level empty and the
-- player unhurt (the ones a suite sets).
mod:command("ut_spawn", "<breed> [distance] - spawns an enemy that distance (5 m) ahead of the player, on the ground", function (breed_name, distance)
	local unit = player_unit()
	local breed = Breeds[breed_name or "chaos_marauder"]
	local first_person_extension = unit and ScriptUnit.has_extension(unit, "first_person_system")

	if not breed or not first_person_extension then
		log("ut_spawn: there is no such enemy or no player")

		return
	end

	local origin = first_person_extension:current_position()
	local flat = Vector3.normalize(Vector3.flat(Quaternion.forward(first_person_extension:current_rotation())))
	local above = origin + flat * (tonumber(distance) or 5) + Vector3(0, 0, 2)
	local physics_world = World.get_data(Managers.world:world("level_world"), "physics_world")
	local hit, _, hit_distance = PhysicsWorld.immediate_raycast(physics_world, above, Vector3.down(), 8, "closest", "collision_filter", "filter_ai_line_of_sight_check")

	if not hit then
		log("ut_spawn: there is no ground there")

		return
	end

	Managers.state.conflict:spawn_one(breed, above - Vector3(0, 0, hit_distance), nil, {
		spawned_func = runner.calm,
	}, Quaternion.look(-flat, Vector3.up()))
end)

mod:command("ut_quiet", "on | off - keeps the level empty and the player unhurt, like a suite does", function (argument)
	if argument == "off" then
		if runner.quiet_restore then
			runner.quiet_restore()
			runner.quiet_restore = nil
		end
	elseif not runner.quiet_restore then
		runner.quiet_restore = set_quiet_flags()
	end
end)

-- For finding the places of a level: loading it, as a suite does, and moving the player to a point
mod:command("ut_level", "<level> - loads a level, as the tests do (military is Righteous Stand)", function (level_key)
	if not level_key or not LevelSettings[level_key] then
		log("ut_level: there is no level %s", tostring(level_key))

		return
	end

	Managers.mechanism:debug_load_level(level_key, 0)
end)

mod:command("ut_tp", "<x> <y> <z> [yaw] - puts the player there, facing that way (degrees)", function (x, y, z, yaw)
	local unit = player_unit()

	if not unit or not tonumber(z) then
		log("ut_tp: there is no player, or no place")

		return
	end

	runner.move_player(unit, Vector3(tonumber(x), tonumber(y), tonumber(z)), tonumber(yaw))
end)

-- How far the level is from the player: up, and level in eight ways around them, for finding a place under a ceiling or by a wall
mod:command("ut_probe", "- says how far the level is above the player and around them", function ()
	local unit = player_unit()

	if not unit then
		return
	end

	local physics_world = World.get_data(Managers.world:world("level_world"), "physics_world")
	local origin = Unit.local_position(unit, 0) + Vector3(0, 0, 0.9)
	local forward = Vector3.normalize(Vector3.flat(Quaternion.forward(ScriptUnit.extension(unit, "first_person_system"):current_rotation())))
	local function distance(direction)
		local hit, _, hit_distance = PhysicsWorld.immediate_raycast(physics_world, origin, direction, 30, "closest", "collision_filter", "filter_player_mover")

		return hit and string.format("%.1f", hit_distance) or "-"
	end
	local around = {}

	for i = 0, 7 do
		around[#around + 1] = distance(Quaternion.rotate(Quaternion.axis_angle(Vector3.up(), i * math.pi / 4), forward))
	end

	-- (the height of the ground ahead, every half meter, against the player's feet)
	local heights = {}

	for i = 1, 16 do
		local above = origin + forward * (i * 0.5) + Vector3(0, 0, 3)
		local hit, ground = PhysicsWorld.immediate_raycast(physics_world, above, Vector3.down(), 10, "closest", "collision_filter", "filter_player_mover")

		heights[#heights + 1] = hit and string.format("%.1f", Vector3.z(ground) - Vector3.z(origin) + 0.9) or "-"
	end

	log("ut_probe: up %s, around from ahead to the left: %s; ground ahead: %s", distance(Vector3.up()), table.concat(around, " "), table.concat(heights, " "))
	push_log_out()
end)

-- Where the player stands, for a test that has to run at a certain place
mod:command("ut_where", "- says where the player stands", function ()
	local unit = player_unit()

	if not unit then
		log("ut_where: there is no player")

		return
	end

	local position = Unit.local_position(unit, 0)
	local forward = Quaternion.forward(ScriptUnit.extension(unit, "first_person_system"):current_rotation())
	local yaw = math.deg(math.atan2(-Vector3.x(forward), Vector3.y(forward)))

	log("ut_where: %s Vector3(%.3f, %.3f, %.3f) yaw %.0f", current_level_key(), Vector3.x(position), Vector3.y(position), Vector3.z(position), yaw)
	push_log_out()
end)

-- For looking at the weapon in the character's hand: the camera goes behind the shoulder, and the character is shown. The game does this
-- for its own third person debug mode.
mod:command("ut_3p", "on | off - the third person view, for looking at the weapon in the hand", function (argument)
	local player = local_player()
	local unit = player_unit()
	local first_person_extension = unit and ScriptUnit.has_extension(unit, "first_person_system")

	if not player or not first_person_extension or not Unit.alive(player.camera_follow_unit) then
		log("ut_3p: there is no player")

		return
	end

	-- The game's own third person mode (a debug setting): with it on, the camera's follow state is the one over the shoulder
	-- (CharacterStateHelper.change_camera_state), and the character's mesh and the weapons in its hands are shown. In the released game
	-- Development.set_parameter does nothing, and Development.parameter reads this table.
	local on = argument ~= "off"

	Development._hardcoded_dev_params.third_person_mode = on or nil
	CharacterStateHelper.change_camera_state(player, "follow")

	-- The camera over the shoulder is so near the head that the game fades the character out, so the camera that follows from further
	-- behind is used instead
	if on then
		Managers.state.entity:system("camera_system"):external_state_change(player, "follow_third_person")
	end
	first_person_extension:set_first_person_mode(not on)
end)

mod:command("ut_equip","<suite> [career] | back - puts the weapon of a suite in your hands, or puts your loadout back", function (argument, career)
	if argument == "back" or not argument then
		runner.unequip()
	else
		runner.equip(argument, career)
	end
end)

mod:command("ut_test", "list | stop | all | <suite> [<suite> ...] [career] - runs the in-game tests of weapons", function (...)
	local arguments = { ... }
	local argument = arguments[1]

	if argument == "list" or not argument then
		log("suites: %s", table.concat(table.keys(runner.suites), ", "))
	elseif argument == "stop" then
		runner.stop()
	else
		-- A career at the end runs the suites only as that career
		local career = CareerSettings[arguments[#arguments]] and table.remove(arguments) or nil

		runner.start(arguments, career)
	end
end)

return runner
