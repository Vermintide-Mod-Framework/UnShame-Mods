local mod = get_mod("unreal_tournament")

-- A mission played as it is (see runner.lua): run it with /ut_test mission. The game's physics crashed (a worker thread of PhysX, with no
-- Lua error) twice a few minutes into a mission on Legend, in hordes, with the Shield Gun. The first time with the flak, the second in
-- the level nurgle, as a Zealot with the Shield Gun and the Rocket Launcher. This plays that: the level's own enemies,
-- hordes and bots, and more hordes sent, while the player punches the nearest enemy and now and then fires rockets at it. The game
-- crashing is the failure. It crashed so in one run of two before the weapons stopped giving velocities to the parts that the
-- animation moves (utils.moved_by_physics), which they did hundreds of thousands of times a run; that is checked too.

local runner = mod.test_runner

local shield = mod.items.weapons.shield_gun_wh
local rocket = mod.items.weapons.rocket_launcher

-- The fight (t.fight_horde): the level's own enemies, a horde sent every horde_interval seconds, for time seconds
local FIGHT = {
	-- How far along the level's way the player is put at the start
	start_distance = 60, -- m
	keep = 1.2, -- m
	horde_interval = 45, -- s
	time = 600, -- s
	-- Rockets are fired every this many attacks
	rockets_every = 5,
}

local function scenarios()
	return {
		{
			name = "a mission's hordes",
			run = function (t)
				-- The game sends nothing while the players are in the safe place at the start: the round starts once they leave it. The
				-- player is put on the level's way, a distance in.
				t.on_main_thread(function ()
					local game_mode = Managers.state.game_mode

					if not game_mode:is_round_started() then
						game_mode:round_started()
					end

					local main_paths = Managers.state.conflict.main_path_info.main_paths
					local point = main_paths and MainPathUtils.point_on_mainpath(main_paths, FIGHT.start_distance)

					if point then
						runner.move_player(t.unit(), point)
					end
				end)
				t.wait(5)

				local attacks = 0
				local stop_logging = runner.log_kinematic_pushes()
				local ok, killed, motion_calls = pcall(t.fight_horde, FIGHT, function (nearest)
					attacks = attacks + 1

					if attacks % FIGHT.rockets_every == 0 then
						t.tap("wield_2")
						t.wait(0.8)
						t.refill()

						for _ = 1, 2 do
							t.aim_at(nearest)
							t.press("action_one", 0.05)
							t.wait(0.9)
						end

						t.tap("wield_1")
						t.wait(0.8)
					else
						t.aim_at(nearest)
						t.press("action_one", 1)
						t.wait(0.2)
					end
				end)

				stop_logging()

				if not ok then
					error(killed, 0)
				end

				t.expect(killed > 0, "no enemy was killed")

				-- The mod changes no part that the animation moves (utils.moved_by_physics)
				for where, count in pairs(motion_calls) do
					t.expect(not string.find(where, "scripts/mods/", 1, true) or count[2] == 0, "%s was called on %d kinematic parts", where, count[2])
				end
			end,
		},
	}
end

runner.add_suite({
	name = "mission",
	item = shield.key,
	template = shield.template,
	slot = "slot_melee",
	careers = { "wh_zealot" },
	level = "nurgle",
	live = true,
	loadout = {
		slot_ranged = {
			wh_zealot = rocket.key,
		},
	},
	scenarios = scenarios(),
})
