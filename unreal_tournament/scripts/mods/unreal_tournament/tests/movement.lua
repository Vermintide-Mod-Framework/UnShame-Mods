local mod = get_mod("unreal_tournament")

-- The UT movement's in-game tests (see runner.lua). Run them with /ut_test movement. They run in the runner's level, Righteous Stand,
-- some of them in its named places.

local runner = mod.test_runner

local CONFIG = {
	-- The mod's multipliers of the game's jump and gravity (movement.lua)
	jump_multiplier = 1.35,
	gravity_multiplier = 1.3,
	-- The dodge launch: the upward speed, and the speed along the dodge it adds (up to 9 m/s in all)
	dodge_up = 4.25, -- m/s
	dodge_speed = 7, -- m/s
	dodge_max_speed = 9, -- m/s
	-- After landing from a dodge, the next is locked this long
	dodge_landing_delay = 0.35, -- s
	-- The double jump's upward speed, and how near the apex it is allowed (the upward speed within this of 0)
	double_jump_speed = 5, -- m/s
	double_jump_apex_speed = 1.7, -- m/s
	-- The wall dodge: the speed along it and upward
	wall_dodge_speed = 6, -- m/s
	wall_dodge_up = 4.25, -- m/s
	-- UT's MaxFallSpeed and JumpZ, which give the fall speed that starts to hurt (about 20 m/s here)
	ut_max_fall_speed = 1200,
	ut_jump_speed = 340,
	-- The ceiling test (see its scenario)
	ceiling_search = 20, -- m
	launch_past_ceiling = 1, -- m
	top_margin = 0.02, -- m
	max_time_at_top = 0.15, -- s
	-- How far off a measured speed may be
	speed_margin = 0.35, -- m/s
	-- The momentum damage: this much more damage at the full speed, none up to the least speed
	momentum_bonus = 0.25,
	momentum_min_speed = 4.5, -- m/s
	momentum_full_speed = 9, -- m/s
}

-- The game's jump speed and gravity for the player, and the player's way to the right on the ground
local function movement_settings(t)
	return t.on_main_thread(function ()
		local unit = t.unit()
		local settings = PlayerUnitMovementSettings.get_movement_settings_table(unit)
		local locomotion_extension = ScriptUnit.extension(unit, "locomotion_system")
		local rotation = ScriptUnit.extension(unit, "first_person_system"):current_rotation()
		local right = Vector3.normalize(Vector3.flat(Quaternion.right(rotation)))
		local forward = Vector3.normalize(Vector3.flat(Quaternion.forward(rotation)))

		return {
			forward = { Vector3.x(forward), Vector3.y(forward) },
			gravity = settings.gravity_acceleration * locomotion_extension:get_script_driven_gravity_scale(),
			jump = settings.jump.initial_vertical_speed,
			right = { Vector3.x(right), Vector3.y(right) },
		}
	end)
end

-- Records the player's movement every frame for that long: { t, x, y, z, vx, vy, vz, on_ground, state }. The observer, if there is
-- one, is also called with each sample.
local function record(t, seconds, observer)
	local samples = {}
	local start = Managers.time:time("game")

	t.watch(seconds, function ()
		local x, y, z = t.position()
		local vx, vy, vz = t.velocity()
		local sample = {
			on_ground = t.on_ground(),
			state = t.state(),
			t = Managers.time:time("game") - start,
			vx = vx,
			vy = vy,
			vz = vz,
			x = x,
			y = y,
			z = z,
		}

		samples[#samples + 1] = sample

		if observer then
			observer(sample)
		end
	end)

	return samples
end

local function highest(samples, field)
	local top = -math.huge

	for _, sample in ipairs(samples) do
		top = math.max(top, sample[field])
	end

	return top
end

local function skip_without_movement(t)
	if mod:get("ut_movement") == false then
		t.skip("the UT movement is turned off")
	end
end

local function scenarios()
	return {
		{
			name = "a jump is stronger than the game's",
			run = function (t)
				skip_without_movement(t)

				local settings = movement_settings(t)
				local expected = settings.jump * CONFIG.jump_multiplier

				t.tap("jump")

				local samples = record(t, 0.3)
				local up = highest(samples, "vz")

				t.expect(math.abs(up - expected) <= CONFIG.speed_margin, "the jump went up at %.2f m/s, not %.2f", up, expected)
				t.wait(1)
			end,
		},
		{
			name = "gravity is stronger than the game's",
			run = function (t)
				skip_without_movement(t)

				local settings = movement_settings(t)

				t.tap("jump")

				local samples = record(t, 0.6)

				-- (the change of the upward speed between two samples in the air, a third of a second apart)
				local first, last

				for _, sample in ipairs(samples) do
					if not sample.on_ground and sample.t > 0.1 then
						first = first or sample
						last = sample.t - first.t < 0.35 and sample or last
					end
				end

				if not t.expect(first and last and last.t > first.t, "the player was not in the air long enough") then
					return
				end

				local gravity = -(last.vz - first.vz) / (last.t - first.t)
				local expected = settings.gravity * CONFIG.gravity_multiplier

				t.expect(math.abs(gravity - expected) <= expected * 0.05, "the player fell with %.2f m/s^2, not %.2f", gravity, expected)
				t.wait(1)
			end,
		},
		{
			name = "a dodge launches the player",
			run = function (t)
				skip_without_movement(t)

				local settings = movement_settings(t)

				t.move(1, 0)
				t.tap("dodge")
				t.move()

				local samples = record(t, 0.25)
				local up = highest(samples, "vz")
				local sideways = -math.huge

				for _, sample in ipairs(samples) do
					sideways = math.max(sideways, sample.vx * settings.right[1] + sample.vy * settings.right[2])
				end

				t.expect(math.abs(up - CONFIG.dodge_up) <= CONFIG.speed_margin, "the dodge went up at %.2f m/s, not %.2f", up, CONFIG.dodge_up)
				t.expect(sideways >= CONFIG.dodge_speed - 0.5 and sideways <= CONFIG.dodge_max_speed + 0.1, "the dodge went to the right at %.2f m/s, not %.1f", sideways, CONFIG.dodge_speed)
				t.wait(1.5)
			end,
		},
		{
			name = "the dodge key with forward dodges forward",
			run = function (t)
				skip_without_movement(t)

				local settings = movement_settings(t)

				t.move(0, 1)
				t.tap("dodge")

				local samples = record(t, 0.25)

				t.move()

				local ahead = -math.huge

				for _, sample in ipairs(samples) do
					ahead = math.max(ahead, sample.vx * settings.forward[1] + sample.vy * settings.forward[2])
				end

				t.expect(highest(samples, "vz") >= CONFIG.dodge_up - CONFIG.speed_margin, "there was no dodge launch forward")
				t.expect(ahead >= CONFIG.dodge_speed - 0.5, "the forward dodge went ahead at %.2f m/s", ahead)
				t.wait(1.5)
			end,
		},
		{
			name = "dodging is locked for a moment after landing from a dodge",
			run = function (t)
				skip_without_movement(t)

				t.move(1, 0)
				t.tap("dodge")
				t.move()
				t.wait(0.1)
				t.wait_until(function ()
					return t.on_ground()
				end, 3, "the dodge to land")

				-- Right after landing: no dodge
				t.move(-1, 0)
				t.tap("dodge")
				t.move()

				local early = highest(record(t, 0.15), "vz")

				t.wait(CONFIG.dodge_landing_delay)

				-- After the lock: a dodge
				t.move(-1, 0)
				t.tap("dodge")
				t.move()

				local late = highest(record(t, 0.2), "vz")

				t.expect(early < 1, "a dodge right after landing went up at %.2f m/s", early)
				t.expect(late >= CONFIG.dodge_up - CONFIG.speed_margin, "a dodge %.2f s after landing went up at %.2f m/s only", CONFIG.dodge_landing_delay, late)
				t.wait(1.5)
			end,
		},
		{
			name = "a double jump near the apex, once",
			run = function (t)
				skip_without_movement(t)

				t.tap("jump")
				t.wait(0.1)

				-- (near the apex: the upward speed has come down under the window)
				t.wait_until(function ()
					local _, _, vz = t.velocity()

					return vz < CONFIG.double_jump_apex_speed - 0.3
				end, 2, "the apex")
				t.tap("jump")

				local second = highest(record(t, 0.1), "vz")

				t.wait_until(function ()
					local _, _, vz = t.velocity()

					return vz < CONFIG.double_jump_apex_speed - 0.3
				end, 2, "the next apex")
				t.tap("jump")

				local third = highest(record(t, 0.1), "vz")

				t.expect(math.abs(second - CONFIG.double_jump_speed) <= CONFIG.speed_margin, "the double jump went up at %.2f m/s, not %.2f", second, CONFIG.double_jump_speed)
				t.expect(third < CONFIG.double_jump_apex_speed, "a second double jump went up at %.2f m/s", third)
				t.wait(2)
			end,
		},
		{
			name = "no double jump while going up fast",
			run = function (t)
				skip_without_movement(t)

				t.tap("jump")

				local single = record(t, 1.2)

				t.wait(1)
				t.tap("jump")
				t.wait(0.1)
				t.tap("jump")

				local pressed = record(t, 1.1)

				t.expect(math.abs(highest(single, "z") - highest(pressed, "z")) < 0.15, "a jump pressed again on the way up went %.2f m higher", highest(pressed, "z") - highest(single, "z"))
				t.wait(1)
			end,
		},
		{
			name = "a dodge in the air off a wall",
			place = "wall",
			run = function (t)
				skip_without_movement(t)

				local settings = movement_settings(t)

				-- (the wall is on the left: the dodge to the right goes off it)
				t.tap("jump")
				t.wait(0.3)
				t.move(1, 0)
				t.tap("dodge")
				t.move()

				local samples = record(t, 0.15)
				local sideways = -math.huge

				for _, sample in ipairs(samples) do
					sideways = math.max(sideways, sample.vx * settings.right[1] + sample.vy * settings.right[2])
				end

				t.expect(math.abs(highest(samples, "vz") - CONFIG.wall_dodge_up) <= CONFIG.speed_margin, "the wall dodge went up at %.2f m/s, not %.2f", highest(samples, "vz"), CONFIG.wall_dodge_up)
				t.expect(sideways >= CONFIG.wall_dodge_speed - 0.5, "the wall dodge went off the wall at %.2f m/s, not %.1f", sideways, CONFIG.wall_dodge_speed)
				t.wait(1.5)
			end,
		},
		{
			name = "no dodge in the air without a wall",
			place = "sky",
			run = function (t)
				skip_without_movement(t)

				t.look(0, 90)
				t.tap("jump")
				t.wait(0.3)
				t.move(-1, 0)
				t.tap("dodge")
				t.move()

				local samples = record(t, 0.15)

				t.expect(highest(samples, "vz") < CONFIG.wall_dodge_up - 1, "the player dodged in the air with no wall")
				t.wait(1.5)
			end,
		},
		{
			name = "a weapon jump into a ceiling does not stick to it",
			place = "ceiling",
			run = function (t)
				skip_without_movement(t)

				local start = t.on_main_thread(function ()
					local unit = t.unit()
					local position = unit and Unit.local_position(unit, 0)
					local physics_world = World.get_data(Managers.world:world("level_world"), "physics_world")
					local height

					for _, filter in ipairs({ "filter_player_mover", "filter_player_ray_projectile_static_only" }) do
						local hit, ceiling = PhysicsWorld.immediate_raycast(physics_world, position + Vector3(0, 0, 0.1), Vector3.up(), CONFIG.ceiling_search, "closest", "collision_filter", filter)

						if hit then
							height = math.min(height or math.huge, Vector3.z(ceiling) - Vector3.z(position))
						end
					end

					return position and {
						z = Vector3.z(position),
						height = height,
					}
				end)

				if not start or not start.height then
					t.skip(string.format("there is no ceiling within %.1f m over the player", CONFIG.ceiling_search))
				end

				local settings = movement_settings(t)
				local gravity = settings.gravity * CONFIG.gravity_multiplier

				t.on_main_thread(function ()
					local locomotion_extension = ScriptUnit.extension(t.unit(), "locomotion_system")
					local velocity = Vector3(0, 0, math.sqrt(2 * gravity * (start.height + CONFIG.launch_past_ceiling)))

					locomotion_extension:set_maximum_upwards_velocity(math.huge)
					locomotion_extension:force_on_ground(false)
					locomotion_extension:set_forced_velocity(velocity)
					locomotion_extension:set_wanted_velocity(velocity)
				end)

				local samples = record(t, 1.2)
				local top = highest(samples, "z")
				local first, last

				for _, sample in ipairs(samples) do
					if sample.z >= top - CONFIG.top_margin then
						first = first or sample.t
						last = sample.t
					end
				end

				local rise = top - start.z

				-- Stopped by the ceiling: the launch was for a rise 1 m past it, and the player's mover stops short of it
				t.expect(rise < start.height - 0.3, "the player did not hit the ceiling (rose %.2f m under a ceiling %.2f m up)", rise, start.height)
				t.expect(first and last - first <= CONFIG.max_time_at_top, "the player stayed at the ceiling for %.2f s", first and last - first or -1)
			end,
		},
		{
			name = "a fall faster than UT's MaxFallSpeed hurts by UT's rule, a slower one does not",
			place = "sky",
			run = function (t)
				skip_without_movement(t)
				t.hurtable(true)

				local settings = movement_settings(t)
				local max_speed = CONFIG.ut_max_fall_speed * settings.jump * CONFIG.jump_multiplier / CONFIG.ut_jump_speed

				-- (the long fall three times: the landing frame falls on a different part of the last stretch each time)
				for _, height in ipairs({ 8, 25, 25, 25 }) do
					local x, y, z = t.position()
					local taken = t.track_damage(t.unit())
					local speed = 0

					t.on_main_thread(function ()
						runner.move_player(t.unit(), Vector3(x, y, z + height))
					end)
					t.wait(0.1)
					t.wait_until(function ()
						local _, _, vz = t.velocity()

						speed = math.max(speed, -vz)

						return t.on_ground()
					end, 5, "the landing")
					t.wait(0.5)

					local fall = 0

					for _, hit in ipairs(taken.hits) do
						fall = fall + hit.amount
					end

					if speed <= max_speed then
						t.expect(fall == 0, "a fall of %d m landing at %.1f m/s hurt %.1f", height, speed, fall)
					else
						local expected = 100 * (speed - max_speed) / max_speed

						t.expect(math.abs(fall - expected) <= expected * 0.15 + 1, "a fall of %d m landing at %.1f m/s hurt %.1f, not %.1f", height, speed, fall, expected)
					end

					t.heal()
					table.clear(runner.frame_watchers)
				end
			end,
		},
		{
			name = "a crouching player does not walk off a ledge",
			place = "ledge",
			run = function (t)
				skip_without_movement(t)

				local toggle = t.on_main_thread(function ()
					return ScriptUnit.extension(t.unit(), "input_system").toggle_crouch
				end)

				if toggle then
					t.tap("crouch")
				else
					t.set_input("crouching", true)
				end

				t.wait(0.5)

				local x, y, z = t.position()

				t.move(0, 1)

				local samples = record(t, 1.5)

				t.move()

				local last = samples[#samples]
				local moved = math.sqrt((last.x - x) ^ 2 + (last.y - y) ^ 2)

				if toggle then
					t.tap("crouch")
				else
					t.set_input("crouching", nil)
				end

				t.expect(moved > 0.3, "the player did not walk toward the ledge (moved %.2f m)", moved)
				t.expect(last.z > z - 0.3, "the player walked off the ledge, %.2f m down", z - last.z)
				t.wait(0.5)
			end,
		},
		{
			name = "a melee hit while moving fast does more damage",
			run = function (t)
				skip_without_movement(t)

				if not mod:get("momentum_damage") then
					t.skip("the momentum damage is turned off")
				end

				-- A light attack of the game's sword (the suite's loadout) standing still, and one in a dodge forward at the enemy (about
				-- 7 m/s, so about 14% more). Each is done three times and the least is taken, as a hit can be a critical hit.
				t.on_main_thread(function ()
					ScriptUnit.extension(t.unit(), "inventory_system"):wield("slot_melee")
				end)
				t.wait(1.5)

				local function punch(moving)
					local target = t.spawn_target(moving and 3.5 or 1.5)

					if not target then
						return nil
					end

					local damage = t.track_damage(target)
					local speed_at_hit

					-- (a light attack starts as the button is let go and hits about half a second later: the dodge comes in that time)
					t.press("action_one", 0.05)

					if moving then
						t.wait(0.1)
						t.move(0, 1)
						t.tap("dodge")
						t.move()
					end

					t.watch(0.8, function ()
						if not speed_at_hit and damage.total > 0 then
							local vx, vy = t.velocity()

							speed_at_hit = math.sqrt(vx * vx + vy * vy)
						end
					end)
					t.remove(target)
					t.go_to_start()

					return damage.total, speed_at_hit or 0
				end

				local standing, moving, speed = math.huge, math.huge, math.huge

				-- (a swing in a dodge can pass the enemy: only the ones that hit count)
				for _ = 1, 4 do
					local damage = punch(false)

					if damage and damage > 0 then
						standing = math.min(standing, damage)
					end

					local at

					damage, at = punch(true)

					if damage and damage > 0 then
						moving = math.min(moving, damage)
						speed = math.min(speed, at)
					end
				end

				t.on_main_thread(function ()
					ScriptUnit.extension(t.unit(), "inventory_system"):wield("slot_ranged")
				end)
				t.wait(1.5)

				-- The bonus the movement gives at the speed of the hit (movement.lua: 25% at 9 m/s, none up to 4.5 m/s), of which most has to
				-- show, the damage being rounded
				local bonus = CONFIG.momentum_bonus * math.max(speed - CONFIG.momentum_min_speed, 0) / (CONFIG.momentum_full_speed - CONFIG.momentum_min_speed)

				t.expect(standing < math.huge and moving < math.huge, "a target could not be spawned")
				t.expect(speed > CONFIG.momentum_min_speed, "the hit in a dodge came at %.1f m/s, too slow for a bonus", speed)
				t.expect(moving >= standing * (1 + bonus * 0.7), "a hit at %.1f m/s did %.1f, %.0f%% more than one standing (%.1f), not %.0f%%", speed, moving, (moving / standing - 1) * 100, standing, bonus * 100)
			end,
		},
		{
			name = "with the movement off, the jump is the game's",
			run = function (t)
				local settings = movement_settings(t)
				local was = mod:get("ut_movement")

				mod:set("ut_movement", false)
				t.wait(0.1)
				t.tap("jump")

				local up = highest(record(t, 0.3), "vz")

				mod:set("ut_movement", was)
				t.wait(1)

				t.expect(math.abs(up - settings.jump) <= CONFIG.speed_margin, "the jump went up at %.2f m/s, not the game's %.2f", up, settings.jump)
			end,
		},
	}
end

-- (the weapon in the hands is the Flak Cannon, and the melee slot gets the game's sword, whose swings are the game's own, for the momentum
-- damage)
runner.add_suite({
	name = "movement",
	item = mod.items.weapons.flak_cannon.key,
	template = mod.items.weapons.flak_cannon.template,
	slot = "slot_ranged",
	loadout = {
		slot_melee = {
			es_mercenary = "es_1h_sword",
		},
	},
	careers = {
		"es_mercenary",
	},
	scenarios = scenarios(),
})
