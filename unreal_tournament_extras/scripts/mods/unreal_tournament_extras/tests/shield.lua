local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The Shield Gun's in-game tests (see runner.lua). Run them with /ut_test shield (Kruber's), shield_dr, shield_bw, shield_wh and
-- shield_we. They run in the runner's level, Righteous Stand.

local runner = mod.test_runner
local shield = ut.shield

-- How many frames after a body starts to fall (its parts move by physics) the game takes it away, for each rat of the scenario below.
-- The punch throws a body from that frame for its kill_hold (0.15 s).
local TAKE_AWAY_FRAMES = { 0, 2, 4, 6, 8 }

-- The horde of "punching into a horde"
local HORDE = {
	-- How many rats, filled up again once fewer stand
	size = 40,
	refill_below = 25,
	-- The block they stand in, ahead of the player
	rows = 8,
	columns = 8,
	distance = 3, -- m
	spacing = 0.6, -- m
	-- How long the player punches
	time = 150, -- s
}

-- The kinds of damage that "how long a body is moved by its death animation" kills with
local DEATH_KINDS = { "blunt", "blunt_tank", "slashing", "cutting", "drakegun", "drakegun_shot", "burninating", "burn", "fire_grenade_glance", "grenade", "arrow_poison_dot", "bleed", "warpfire_ground" }

-- The horde of "a punch never hits the player who punches" (t.fight_horde): the player starts each dodge keep m from the nearest rat
local SELF_HIT_HORDE = {
	size = 30,
	breeds = { "skaven_clan_rat", "skaven_slave" },
	refill_below = 20,
	distance = 6, -- m
	keep = 3, -- m
	time = 90, -- s
}

-- How many bodies "a punch on a pinned body" pins and punches
local PIN_ROUNDS = 5
-- The speed of the bolts that pin it: a part is pinned to what is within 0.3 s of flight, and slides there in the share of 0.3 s that
-- its distance is of that
local PIN_SPEED = 2 -- m/s

-- How many times ten rats are killed and frozen in "a body pushed in the frame the game freezes it"
local FREEZE_ROUNDS = 3

-- The horde of "punching in a real horde" (t.fight_horde)
local REAL_HORDE = {
	size = 60,
	breeds = { "skaven_clan_rat", "skaven_slave" },
	refill_below = 40,
	distance = 8, -- m
	keep = 1.2, -- m
	time = 240, -- s
}

-- How far ahead of the player "the shield stops an exploding barrel" sets off the barrel: inside the explosion's full damage radius
-- (1.75 m)
local BARREL_DISTANCE = 1.5 -- m

-- The standard of "punches destroy a standard": how far ahead of the player it is planted, its health (a standard bearer's
-- place_standard action gives it 10), and how many punches it may take
local STANDARD_UNIT = "units/weapons/enemy/wpn_bm_standard_01/wpn_bm_standard_01_placed"
local STANDARD_DISTANCE = 1.5 -- m
local STANDARD_HEALTH = 10
local STANDARD_MAX_PUNCHES = 10

-- Takes a body away as the game does in a horde: it keeps up to 24 enemies, living and dead, and past that takes the oldest bodies off
-- its list (UnitSpawner.update_death_watch_list). The body's death reaction then gives it to the BreedFreezer, which takes it out of the
-- physics to use it again.
local function take_body_away(unit)
	local spawner = Managers.state.unit_spawner
	local death_data = spawner.unit_death_watch_lookup[unit]

	if not death_data then
		return false
	end

	local list, n = spawner.unit_death_watch_list, spawner.unit_death_watch_list_n

	for i = 1, n do
		if list[i] == death_data then
			list[i] = list[n]
			spawner.unit_death_watch_lookup[list[i].unit] = list[i]
			list[n] = nil

			break
		end
	end

	spawner.unit_death_watch_lookup[unit] = nil
	spawner.unit_death_watch_list_n = n - 1
	spawner.unit_death_watch_list_dirty = true
	death_data.data.remove = true

	return true
end

-- Whether any part of the unit moves by physics
local function falling(unit)
	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		if actor and Actor.is_dynamic(actor) and Actor.is_physical(actor) then
			return true
		end
	end

	return false
end

local function scenarios()
	return {
		{
			name = "charge and punch",
			run = function (t)
				local before = shield.last_punch
				local charged = false

				-- Held for a second, the gun charges, and let go it punches
				t.press("action_one", 1, function ()
					if shield.charge_started then
						charged = true
					end
				end)
				t.wait(0.2)

				t.expect(charged, "the gun did not charge while the button was held")
				t.expect(shield.last_punch ~= before, "the gun did not punch when the button was let go")
				t.expect(shield.charge_started == nil, "the charge did not end with the punch")
			end,
		},
		{
			name = "punches by itself near an enemy",
			run = function (t)
				local target = t.spawn_target(1.5)

				if not t.expect(target, "the target could not be spawned") then
					return
				end

				local before = shield.last_punch
				local punched_while_held = false

				t.press("action_one", 1.5, function ()
					if shield.last_punch ~= before then
						punched_while_held = true
					end
				end)

				t.expect(punched_while_held, "the gun did not punch by itself with an enemy in reach")
			end,
		},
		{
			name = "a punch while moving fast does more damage",
			run = function (t)
				if ut:get("ut_movement") == false or not ut:get("momentum_damage") then
					t.skip("the movement or its momentum damage is turned off")
				end

				-- A punch standing still, and one in a dodge forward at the enemy (about 7 m/s). Each is done four times, and the least
				-- of the ones that hit is taken, as a punch can be a critical hit. The bonus is the movement's (25% at 9 m/s, none up to
				-- 4.5 m/s), most of which has to show.
				-- The punch in the dodge is the gun's own, as the enemy comes into reach while the charge is held, so it lands in the dodge
				-- whatever the reach is. It comes before min_hold_time, as the standing one does, so both are the least charged punch. The
				-- player looks at the enemy's middle, as a player does: looking level, the punch goes over a rat's head, the more so in the
				-- dodge's hop, and the gun doesn't find it in reach before the player slides off it.
				local function punch(moving)
					local target = t.spawn_target(moving and 4 or 1.5)

					if not target then
						return nil
					end

					local damage = t.track_damage(target)
					local speed

					local function watch_speed()
						if not speed and damage.total > 0 then
							local vx, vy = t.velocity()

							speed = math.sqrt(vx * vx + vy * vy)
						end
					end

					if moving then
						local spine = t.on_main_thread(function ()
							local position = Unit.world_position(target, Unit.node(target, "j_spine"))

							return { Vector3.x(position), Vector3.y(position), Vector3.z(position) }
						end)

						t.aim_at_point(spine[1], spine[2], spine[3])
						t.move(0, 1)
						t.tap("dodge")
						t.move()
						t.hold("action_one")
						t.watch(0.8, watch_speed)
						t.release("action_one")
					else
						t.press("action_one", 0.1)
						t.watch(0.8, watch_speed)
					end
					t.remove(target)
					t.go_to_start()
					t.wait(0.7)

					return damage.total, speed
				end

				local standing, moving, speed = math.huge, math.huge, math.huge

				for _ = 1, 4 do
					local damage, at = punch(false)

					if damage and damage > 0 then
						standing = math.min(standing, damage)
					end

					damage, at = punch(true)

					if damage and damage > 0 then
						moving = math.min(moving, damage)
						speed = math.min(speed, at)
					end
				end

				local bonus = 0.25 * math.max(speed - 4.5, 0) / 4.5

				t.expect(standing < math.huge and moving < math.huge, "no punch hit")
				t.expect(speed > 4.5, "the punch in a dodge came at %.1f m/s, too slow for a bonus", speed)
				t.expect(moving >= standing * (1 + bonus * 0.7), "a punch at %.1f m/s did %.1f, %.0f%% more than one standing (%.1f), not %.0f%%", speed, moving, (moving / standing - 1) * 100, standing, bonus * 100)
			end,
		},
		{
			-- The game crashed in its physics during hordes, with the Shield Gun: a punch throws the bodies it kills for a while after
			-- it, and the game can take them out of the physics in that time. The game crashing is the failure.
			name = "a punch kills enemies whose bodies the game takes away as they are thrown",
			run = function (t)
				local rats = t.spawn_group("skaven_clan_rat", #TAKE_AWAY_FRAMES, 1.5)
				local dead, falling_frames, taken, frozen = {}, {}, {}, {}

				if not t.expect(#rats == #TAKE_AWAY_FRAMES, "the rats could not be spawned") then
					return
				end

				-- Every frame: which rats died, for how many frames each body has fallen, and which the game froze. A body is taken away
				-- its number of frames after it starts to fall.
				local function watch()
					for i, rat in ipairs(rats) do
						dead[rat] = dead[rat] or not HEALTH_ALIVE[rat]
						frozen[rat] = frozen[rat] or FROZEN[rat]

						if dead[rat] and not taken[rat] and Unit.alive(rat) and (falling_frames[rat] or falling(rat)) then
							falling_frames[rat] = (falling_frames[rat] or -1) + 1

							if falling_frames[rat] >= TAKE_AWAY_FRAMES[i] then
								taken[rat] = take_body_away(rat)
							end
						end
					end
				end

				runner.frame_watchers[#runner.frame_watchers + 1] = watch

				t.wait(1)

				-- A punch throws the rats back out of reach, so the player goes up to one still standing before each punch
				local ok, problem = pcall(function ()
					for _ = 1, 20 do
						local target

						for _, rat in ipairs(rats) do
							if not dead[rat] then
								target = rat

								break
							end
						end

						if not target then
							break
						end

						t.on_main_thread(function ()
							local player = t.unit()
							local at = Unit.world_position(target, 0)
							local away = Vector3.normalize(Vector3.flat(Unit.world_position(player, 0) - at))

							runner.move_player(player, at + away * 1.2)
						end)
						t.aim_at(target)
						t.press("action_one", 1)
						t.wait(0.5)
					end

					t.wait(2)
				end)

				for i = #runner.frame_watchers, 1, -1 do
					if runner.frame_watchers[i] == watch then
						table.remove(runner.frame_watchers, i)
					end
				end

				if not ok then
					error(problem, 0)
				end

				local killed, fell, froze = 0, 0, 0

				for _, rat in ipairs(rats) do
					if dead[rat] then
						killed = killed + 1

						-- (the runner does not take it away again)
						t.remove(rat)
					end

					fell = fell + (falling_frames[rat] and 1 or 0)
					froze = froze + (frozen[rat] and 1 or 0)
				end

				t.log("%d rats killed, %d fell, %d frozen", killed, fell, froze)
				t.expect(killed == #rats, "the punches killed %d of the %d rats", killed, #rats)
				t.expect(froze == #rats, "the game froze %d of the %d bodies", froze, #rats)
			end,
		},
		{
			-- For its first moments a body is still moved by its animation (its parts are kinematic), and pushing such a part crashes
			-- the game's physics. A punch pushes the bodies in its cone. Here the rat dies a few frames before the punch: the game crashing
			-- is the failure.
			name = "a punch on a body that has just died",
			run = function (t)
				-- Counts the pushes, and those of a part that animation moves
				local push = Actor.push
				local pushes, kinematic = 0, 0

				Actor.push = function (actor, ...)
					pushes = pushes + 1

					if Actor.is_dynamic(actor) and not Actor.is_physical(actor) then
						kinematic = kinematic + 1
					end

					return push(actor, ...)
				end

				local ok, problem = pcall(function ()
					for i = 1, 12 do
						-- (out of the reach that makes the gun punch by itself, and in the reach of the punch)
						local rat = t.spawn("skaven_clan_rat", 2.5)

						if not t.expect(rat, "the rat could not be spawned") then
							return
						end

						t.wait(1)
						t.aim_at(rat)
						t.hold("action_one")
						t.wait(0.6)
						t.on_main_thread(function ()
							local player = t.unit()

							DamageUtils.add_damage_network(rat, player, 400, "torso", "blunt", nil, Vector3(0, 0, -1), "wh_1h_hammer", nil, player)
						end)

						-- 0 to 3 frames between the death and letting go
						for _ = 1, (i - 1) % 4 do
							t.wait(0)
						end

						t.release("action_one")
						t.wait(1.5)
						t.remove(rat)
					end
				end)

				Actor.push = push

				if not ok then
					error(problem, 0)
				end

				t.log("%d pushes, %d of a part that animation moves", pushes, kinematic)
			end,
		},
		{
			-- The game's physics runs while the scripts do, so what a script does to a part is applied after the frame, in one go. A
			-- punch pushes the bodies in its cone (push_body, Actor.push). If the game freezes a body in the same frame (BreedFreezer: its
			-- parts are put back under the animation), the push could be applied to the frozen parts. The game uses a frozen unit again
			-- for an enemy it spawns, and then the animation moves the parts. Here each body is pushed as it is frozen, and more rats are
			-- spawned, which take the frozen units. The game crashing is the failure.
			name = "a body pushed in the frame the game freezes it",
			run = function (t)
				local commit_freezes = BreedFreezer.commit_freezes
				local pushed = 0

				-- (each body is pushed right after it is frozen, the way the punch checks its parts: those that physics moves)
				BreedFreezer.commit_freezes = function (self)
					local units = {}

					for _, list in pairs(self.units_to_freeze) do
						for _, unit in ipairs(list) do
							units[#units + 1] = unit
						end
					end

					commit_freezes(self)

					for _, unit in ipairs(units) do
						for i = 0, Unit.num_actors(unit) - 1 do
							local actor = Unit.actor(unit, i)

							if actor and Actor.is_dynamic(actor) and Actor.is_physical(actor) then
								Actor.push(actor, Vector3(0, 0, 60), 0.5)

								pushed = pushed + 1
							end
						end
					end
				end

				local ok, problem = pcall(function ()
					for _ = 1, FREEZE_ROUNDS do
						local rats = t.spawn_group("skaven_clan_rat", 10, 3)

						t.wait(1)

						for _, rat in ipairs(rats) do
							t.on_main_thread(function ()
								local player = t.unit()

								DamageUtils.add_damage_network(rat, player, 400, "torso", "blunt", nil, Vector3(0, 0, -1), "wh_1h_hammer", nil, player)
							end)
						end

						-- Once the bodies fall, the game takes them away
						t.wait(0.5)
						t.on_main_thread(function ()
							for _, rat in ipairs(rats) do
								take_body_away(rat)
							end
						end)
						t.wait(0.5)

						for _, rat in ipairs(rats) do
							t.remove(rat)
						end
					end

					-- The frozen units are taken by the rats spawned now, and the animation moves them
					local rats = t.spawn_group("skaven_clan_rat", 30, 3)

					t.wait(5)

					for _, rat in ipairs(rats) do
						t.remove(rat)
					end
				end)

				BreedFreezer.commit_freezes = commit_freezes

				if not ok then
					error(problem, 0)
				end

				t.log("%d parts pushed as they were frozen", pushed)
				t.expect(pushed > 0, "no part was pushed as it was frozen")
			end,
		},
		{
			-- Whether the engine lets a push be put on a part that animation moves (kinematic): the parts of a living rat. The game
			-- crashing is the failure, and shows that such a push breaks the physics.
			name = "a push on a part moved by animation",
			run = function (t)
				local rat = t.spawn("skaven_clan_rat", 3)

				if not t.expect(rat, "the rat could not be spawned") then
					return
				end

				t.wait(1)

				-- Each way of pushing, on every part that animation moves, a second apart
				for _, call in ipairs({ "push", "add_impulse", "add_velocity", "add_angular_velocity", "add_torque" }) do
					local pushed = t.on_main_thread(function ()
						local count = 0

						for i = 0, Unit.num_actors(rat) - 1 do
							local actor = Unit.actor(rat, i)

							if Actor[call] and actor and Actor.is_dynamic(actor) and not Actor.is_physical(actor) then
								if call == "push" then
									Actor.push(actor, Vector3(0, 0, 60), 0.5)
								else
									Actor[call](actor, Vector3(0, 0, 1))
								end

								count = count + 1
							end
						end

						return count
					end)

					t.log("%s on %d parts", call, pushed)
					t.wait(1)
				end
			end,
		},
		{
			-- A bolt or an arrow that kills an enemy can pin its body to a wall (the bots' bows and crossbows): the game makes the pinned
			-- part kinematic and moves it there (update_wall_nail in death_reactions.lua). A push on a kinematic part breaks the game's
			-- physics, which crashes when the part is moved next. The punch pushes the bodies in its cone. Here a rat's body is pinned as
			-- the game pins one, and punched. The game crashing is the failure.
			name = "a punch on a pinned body",
			run = function (t)
				-- The parts a hit pushes, in all the zones. The body is pinned by all of them, to the floor (as by bolts from above), so
				-- that every part the punch pushes is pinned.
				local parts = {}

				for _, zone in pairs(Breeds.skaven_clan_rat.hit_zones) do
					for _, name in ipairs(zone.push_actors or {}) do
						parts[name] = true
					end
				end

				local stop_watching_motion = runner.watch_motion_calls()
				local ok, problem = pcall(function ()
					for _ = 1, PIN_ROUNDS do
						local rat = t.spawn("skaven_clan_rat", 2)

						if not t.expect(rat, "the rat could not be spawned") then
							return
						end

						t.wait(1)
						t.on_main_thread(function ()
							local player = t.unit()

							DamageUtils.add_damage_network(rat, player, 400, "torso", "blunt", nil, Vector3(0, 0, -1), "wh_1h_hammer", nil, player)
						end)
						t.wait_until(function ()
							return Unit.alive(rat) and falling(rat)
						end, 2, "the body to fall")
						t.wait(0.5)
						t.aim_at(rat)

						-- The pinned part slides to where it is pinned, for up to 0.3 s (the slower the bolt, the longer). The punch is
						-- charged first and let go while the parts slide.
						t.hold("action_one")
						t.wait(0.6)
						t.on_main_thread(function ()
							local death_extension = ScriptUnit.extension(rat, "death_system")

							for name in pairs(parts) do
								death_extension:nailing_hit(name, Vector3.down(), PIN_SPEED)
							end
						end)
						t.wait(0)
						t.wait(0)
						t.release("action_one")
						t.wait(2)
						t.remove(rat)
						t.go_to_start()
					end
				end)
				local motion_calls = stop_watching_motion()

				if not ok then
					error(problem, 0)
				end

				for where, count in pairs(motion_calls) do
					t.log("%s: %d calls, %d on a kinematic part", where, count[1], count[2])
				end
			end,
		},
		{
			-- How long the parts that a hit pushes stay moved by the animation after a death of each kind (a death can play an
			-- animation before the body falls). Says it; nothing is expected.
			name = "how long a body is moved by its death animation",
			run = function (t)
				for _, damage_type in ipairs(DEATH_KINDS) do
					local rat = t.spawn("skaven_clan_rat", 3)

					if not t.expect(rat, "the rat could not be spawned") then
						return
					end

					t.wait(1)

					local frames, kinematic_frames, missing_frames = 0, 0, 0
					local push_actors = Breeds.skaven_clan_rat.hit_zones.torso.push_actors

					t.on_main_thread(function ()
						local player = t.unit()

						DamageUtils.add_damage_network(rat, player, 400, "torso", damage_type, nil, Vector3(0, 0, -1), "wh_1h_hammer", nil, player)
					end)
					t.watch(3, function ()
						if not Unit.alive(rat) then
							return
						end

						frames = frames + 1

						local kinematic, missing = false, false

						for _, name in ipairs(push_actors) do
							local actor = Unit.actor(rat, name)

							if not actor then
								missing = true
							elseif Actor.is_dynamic(actor) and not Actor.is_physical(actor) then
								kinematic = true
							end
						end

						kinematic_frames = kinematic_frames + (kinematic and 1 or 0)
						missing_frames = missing_frames + (missing and 1 or 0)
					end)
					t.log("%s: of %d frames, %d with a pushed part moved by the animation, %d with one missing", damage_type, frames, kinematic_frames, missing_frames)
					t.remove(rat)
				end
			end,
		},
		{
			-- The crash came in a horde: many enemies close together, and the bodies of those killed falling among them. The game keeps
			-- 24 enemies, living and dead, and takes the oldest bodies away past that, so with this many it takes bodies away all the
			-- time. The player punches the nearest rat over and over, and the crowd is filled up again as it thins.
			name = "punching into a horde",
			run = function (t)
				local crowd = {}
				local living = {}
				local spots = {}
				local killed, frozen = 0, 0
				local counted = {}

				-- The crowd stands in a block ahead, 0.6 m apart
				for row = 0, HORDE.rows - 1 do
					for column = 0, HORDE.columns - 1 do
						local ground = t.ground_at(HORDE.distance + row * HORDE.spacing, (column - (HORDE.columns - 1) / 2) * HORDE.spacing)

						if ground then
							spots[#spots + 1] = ground
						end
					end
				end

				if not t.expect(#spots >= HORDE.size, "there is room for %d rats of %d", #spots, HORDE.size) then
					return
				end

				local function fill()
					local count = 0

					for unit in pairs(living) do
						if HEALTH_ALIVE[unit] then
							count = count + 1
						else
							living[unit] = nil
						end
					end

					if count >= HORDE.refill_below then
						return
					end

					t.on_main_thread(function ()
						for i = 1, HORDE.size - count do
							local spot = spots[math.random(#spots)]

							Managers.state.conflict:spawn_one(Breeds.skaven_clan_rat, Vector3(unpack(spot)), nil, {
								spawned_func = function (unit)
									runner.calm(unit)

									living[unit] = true

									if not crowd[unit] then
										crowd[unit] = true

										local spawned = t.scenario().spawned

										spawned[#spawned + 1] = unit
									end
								end,
							}, Quaternion.identity())
						end
					end)
					t.wait(1)
				end

				local function watch()
					for unit in pairs(crowd) do
						if not HEALTH_ALIVE[unit] and not counted[unit] then
							counted[unit] = "dead"
							killed = killed + 1
						elseif counted[unit] == "dead" and FROZEN[unit] then
							counted[unit] = "frozen"
							frozen = frozen + 1
						elseif HEALTH_ALIVE[unit] and counted[unit] == "frozen" then
							-- (the game used the frozen unit again for a rat it spawned)
							counted[unit] = nil
						end
					end
				end

				runner.frame_watchers[#runner.frame_watchers + 1] = watch

				local stop_watching_motion = runner.watch_motion_calls()
				local ok, problem = pcall(function ()
					local started = Managers.time:time("game")
					local said = started

					while Managers.time:time("game") - started < HORDE.time do
						fill()

						-- The player goes up to the nearest rat
						local nearest = t.on_main_thread(function ()
							local player = t.unit()
							local position = Unit.world_position(player, 0)
							local found, found_distance

							for unit in pairs(living) do
								if HEALTH_ALIVE[unit] and Unit.alive(unit) then
									local distance = Vector3.distance(position, Unit.world_position(unit, 0))

									if not found or distance < found_distance then
										found, found_distance = unit, distance
									end
								end
							end

							if found then
								local at = Unit.world_position(found, 0)
								local away = Vector3.normalize(Vector3.flat(position - at))

								runner.move_player(player, at + away * 1.2)
							end

							return found
						end)

						if nearest then
							t.aim_at(nearest)
							t.press("action_one", 1)
							t.wait(0.2)
						end

						if Managers.time:time("game") - said > 30 then
							said = Managers.time:time("game")

							t.log("%d rats killed, %d bodies frozen so far", killed, frozen)
						end
					end
				end)
				local motion_calls = stop_watching_motion()

				for i = #runner.frame_watchers, 1, -1 do
					if runner.frame_watchers[i] == watch then
						table.remove(runner.frame_watchers, i)
					end
				end

				if not ok then
					error(problem, 0)
				end

				for where, count in pairs(motion_calls) do
					t.log("%s: %d calls, %d on a kinematic part, %d on a frozen unit", where, count[1], count[2], count[3])
				end

				t.log("%d rats killed, %d bodies frozen", killed, frozen)
				t.expect(frozen > 0, "the game froze none of the bodies")
			end,
		},
		{
			-- The same with enemies that attack, as a horde's do (t.fight_horde). The player can't be hurt.
			name = "punching in a real horde",
			run = function (t)
				local killed = t.fight_horde(REAL_HORDE, function (nearest)
					t.aim_at(nearest)
					t.press("action_one", 1)
					t.wait(0.2)
				end)

				t.expect(killed > 0, "no enemy was killed")
			end,
		},
		{
			-- The punch picks the enemy straight ahead with a ray, then casts rays from the eye at the enemies in its cone. The engine
			-- fills the same tables with each ray's hits. In a dodge forward the player's own body is a frame ahead of the eye, and the rays
			-- from the eye meet it about 0.12 m out: the hit straight ahead that the punch kept became a part of the player, who was
			-- punched. Here the player fights a horde, dodging at the nearest rat with the charge held (the gun punches by itself once the
			-- rat comes into reach, at the dodge's speed), and must take nothing from the gun.
			name = "a punch never hits the player who punches",
			run = function (t)
				t.hurtable(true)

				local damage = t.track_damage(t.unit())

				t.fight_horde(SELF_HIT_HORDE, function (nearest)
					t.aim_at(nearest)
					t.hold("action_one")
					t.wait(0.2)
					t.move(0, 1)
					t.tap("dodge")
					t.move()
					t.wait(0.8)
					t.release("action_one")
					t.wait(0.3)
				end)

				local from_gun = 0

				-- (the punch's own hits, which are blows; a punch at the floor or a wall hurts the player too, as UT's, and that is fine)
				for _, hit in ipairs(damage.hits) do
					if hit.source and string.find(hit.source, "ut_shield_gun", 1, true) and hit.type ~= "drakegun" then
						from_gun = from_gun + hit.amount
					end
				end

				t.expect(from_gun == 0, "the player took %.1f damage from their own punches", from_gun)
			end,
		},
		{
			-- The shield stops an explosion from its front (shield_gun.lua: UT's ShieldGun.AdjustPlayerDamage), which the game's block
			-- doesn't. An explosive barrel is set off ahead, once with the shield up towards it, once without: the first must not hurt the
			-- player, and the second must, which shows the barrel's explosion reaches them.
			name = "the shield stops an exploding barrel",
			run = function (t)
				t.hurtable(true)

				local function explode_barrel(shielded)
					local loaded = false
					local barrel

					-- PickupSystem.spawn_pickup_async passes its callback on as the unit's extension data, so the barrel's package is
					-- loaded here and the barrel spawned once it is.
					t.on_main_thread(function ()
						Managers.level_transition_handler.pickup_package_loader:request_pickup("explosive_barrel", function ()
							loaded = true
						end)
					end)

					if not t.expect(t.wait_until(function ()
						return loaded
					end, 10, "the barrel's package to load"), "the barrel's package did not load") then
						return nil
					end

					t.on_main_thread(function ()
						local player = t.unit()
						local first_person_extension = ScriptUnit.extension(player, "first_person_system")
						local flat = Vector3.normalize(Vector3.flat(Quaternion.forward(first_person_extension:current_rotation())))
						local position = Unit.local_position(player, 0) + flat * BARREL_DISTANCE

						barrel = Managers.state.entity:system("pickup_system"):spawn_pickup("explosive_barrel", position, Quaternion.identity(), false, "dropped")
					end)

					if not t.expect(barrel, "the barrel could not be spawned") then
						return nil
					end

					t.wait(1)
					t.heal()
					t.aim_at(barrel)

					if shielded then
						t.hold("action_two")
						t.wait(0.5)
					end

					local damage = t.track_damage(t.unit())

					-- The first hit lights the barrel, and the second, 0.2 s or more later, sets it off
					for _ = 1, 2 do
						t.on_main_thread(function ()
							if Unit.alive(barrel) then
								local player = t.unit()

								DamageUtils.add_damage_network(barrel, player, 10, "full", "blunt", Unit.world_position(barrel, 0), Vector3(0, 0, -1), "wh_1h_hammer", nil, player)
							end
						end)
						t.wait(0.3)
					end

					t.wait(1)

					if shielded then
						t.release("action_two")
					end

					t.on_main_thread(function ()
						if Unit.alive(barrel) then
							t.expect(false, "the barrel did not explode")
							Managers.state.unit_spawner:mark_for_deletion(barrel)
						end
					end)

					t.log("%s: the player took %.1f", shielded and "with the shield up" or "without the shield", damage.total)

					return damage.total
				end

				local shielded = explode_barrel(true)
				local unshielded = explode_barrel(false)

				t.expect(unshielded and unshielded > 0, "the barrel's explosion did not reach the player without the shield")
				t.expect(shielded == 0, "the shield let %.1f of the barrel's explosion through", shielded or -1)
			end,
		},
		{
			-- A standard only takes damage from melee attacks and a few damage sources (BeastmenStandardHealthExtension.add_damage). The
			-- punch hits it as a melee swing hits it. A standard is planted ahead as a standard bearer plants it (BTPlaceStandardAction),
			-- and punched until it falls.
			name = "punches destroy a standard",
			run = function (t)
				-- Spawning the bearer loads the beastmen's package, which has the standard. The standard takes the bearer's side.
				local bearer = t.spawn("beastmen_standard_bearer", 8)

				if not t.expect(bearer, "the standard bearer could not be spawned") then
					return
				end

				local spot = t.ground_at(STANDARD_DISTANCE, 0)
				local standard

				t.on_main_thread(function ()
					if not spot or not Application.can_get("unit", STANDARD_UNIT) then
						return
					end

					standard = Managers.state.unit_spawner:spawn_network_unit(STANDARD_UNIT, "standard_unit", {
						health_system = {
							health = STANDARD_HEALTH,
						},
						death_system = {
							death_reaction_template = "standard",
						},
						ai_supplementary_system = {
							standard_template_name = "healing_standard",
							standard_bearer_unit = bearer,
						},
						ping_system = {
							always_pingable = true,
						},
					}, Vector3(spot[1], spot[2], spot[3]))
				end)

				t.remove(bearer)

				if not t.expect(standard, "the standard could not be spawned") then
					return
				end

				t.wait(0.5)
				t.aim_at_point(spot[1], spot[2], spot[3] + 1)

				local punches = 0
				local first_damage

				while punches < STANDARD_MAX_PUNCHES and t.health_of(standard) > 0 do
					local before = t.health_of(standard)

					t.press("action_one", 0.1)
					t.wait(0.8)

					punches = punches + 1
					first_damage = first_damage or before - t.health_of(standard)
				end

				local left = t.health_of(standard)

				t.log("%d punches, the first did %.1f, the standard has %.1f of %d left", punches, first_damage or 0, left, STANDARD_HEALTH)
				t.expect(first_damage and first_damage > 0, "the first punch did not damage the standard")
				t.expect(left == 0, "%d punches did not destroy the standard", punches)

				t.on_main_thread(function ()
					if Unit.alive(standard) and HEALTH_ALIVE[standard] then
						Managers.state.unit_spawner:mark_for_deletion(standard)
					end
				end)
			end,
		},
		{
			name = "block",
			run = function (t)
				local blocked = false

				t.press("action_two", 0.6, function ()
					local status_extension = ScriptUnit.has_extension(t.unit(), "status_system")

					if status_extension and status_extension:is_blocking() then
						blocked = true
					end
				end)

				t.expect(blocked, "the right button did not raise the shield (block)")
			end,
		},
	}
end

for _, variant in ipairs({
	{ name = "shield", setting_id = "shield_gun", careers = { "es_mercenary", "es_knight" } },
	{ name = "shield_dr", setting_id = "shield_gun_dr", careers = { "dr_ironbreaker", "dr_slayer" } },
	{ name = "shield_bw", setting_id = "shield_gun_bw", careers = { "bw_adept" } },
	{ name = "shield_wh", setting_id = "shield_gun_wh", careers = { "wh_captain" } },
	{ name = "shield_we", setting_id = "shield_gun_we", careers = { "we_shade" } },
}) do
	local definition = ut.items.weapons[variant.setting_id]

	runner.add_suite({
		name = variant.name,
		item = definition.key,
		template = definition.template,
		slot = "slot_melee",
		careers = variant.careers,
		scenarios = scenarios(),
	})
end
