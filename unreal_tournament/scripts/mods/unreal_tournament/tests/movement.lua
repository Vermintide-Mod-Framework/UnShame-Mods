local mod = get_mod("unreal_tournament")

-- The UT movement's in-game tests (see runner.lua). Run them with /ut_test movement, in the Keep. The weapon does not matter; the
-- suite holds the Shield Gun.

local runner = mod.test_runner

local CONFIG = {
	-- The ceiling is looked for this far up
	ceiling_search = 20, -- m
	-- The launch straight up, like a weapon jump, is fast enough to rise this far past the ceiling with nothing there. The rise
	-- comes from the game's gravity times the mod's (11 * 1.3 m/s^2).
	gravity = 11 * 1.3, -- m/s^2
	launch_past_ceiling = 1, -- m
	-- The player counts as at the top while within this of the highest point
	top_margin = 0.02, -- m
	-- With the blocked speed taken away, the player falls from the ceiling at once: 2 cm takes 0.05 s. Without it, the player
	-- stays at the ceiling until gravity has used up the speed left, over half a second with this launch.
	max_time_at_top = 0.15, -- s
}

runner.add_suite({
	name = "movement",
	item = mod.items.weapons.shield_gun.key,
	template = mod.items.weapons.shield_gun.template,
	slot = "slot_melee",
	careers = {
		"es_mercenary",
	},
	-- A place in the Keep under a low flat ceiling (found with /ut_where)
	place = {
		level = "inn_level_halloween",
		position = { 0.398, 10.382, 5.227 },
	},
	scenarios = {
		{
			name = "a weapon jump into a ceiling does not stick to it",
			run = function (t)
				if mod:get("ut_movement") == false then
					t.skip("the UT movement is turned off")
				end

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

				local samples = {}

				t.on_main_thread(function ()
					local locomotion_extension = ScriptUnit.extension(t.unit(), "locomotion_system")
					local velocity = Vector3(0, 0, math.sqrt(2 * CONFIG.gravity * (start.height + CONFIG.launch_past_ceiling)))

					locomotion_extension:set_maximum_upwards_velocity(math.huge)
					locomotion_extension:force_on_ground(false)
					locomotion_extension:set_forced_velocity(velocity)
					locomotion_extension:set_wanted_velocity(velocity)
				end)

				local launch_t = Managers.time:time("game")

				t.watch(1.2, function ()
					local unit = t.unit()

					if unit then
						samples[#samples + 1] = {
							t = Managers.time:time("game") - launch_t,
							z = Vector3.z(Unit.local_position(unit, 0)),
						}
					end
				end)

				local top = -math.huge

				for _, sample in ipairs(samples) do
					top = math.max(top, sample.z)
				end

				local first, last

				for _, sample in ipairs(samples) do
					if sample.z >= top - CONFIG.top_margin then
						first = first or sample.t
						last = sample.t
					end
				end

				local rise = top - start.z

				-- Stopped by the ceiling, the player's feet stay more than a body below it
				t.expect(rise < start.height - 1,"the player did not hit the ceiling (rose %.2f m under a ceiling %.2f m up)", rise, start.height)
				t.expect(first and last - first <= CONFIG.max_time_at_top, "the player stayed at the ceiling for %.2f s", first and last - first or -1)
			end,
		},
	},
})
