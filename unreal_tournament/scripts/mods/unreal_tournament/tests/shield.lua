local mod = get_mod("unreal_tournament")

-- The Shield Gun's in-game tests (see runner.lua). Run them with /ut_test shield (Kruber's), shield_dr, shield_bw, shield_wh, shield_we
-- and shield_priest. They run in the runner's level, Righteous Stand.

local runner = mod.test_runner
local shield = mod.shield

-- How many frames after a body starts to fall (its parts move by physics) the game takes it away, for each rat of the scenario below.
-- The punch throws a body from that frame for its kill_hold (0.15 s).
local TAKE_AWAY_FRAMES = { 0, 2, 4, 6, 8 }

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
				if mod:get("ut_movement") == false or not mod:get("momentum_damage") then
					t.skip("the movement or its momentum damage is turned off")
				end

				-- A punch standing still, and one in a dodge forward at the enemy (about 7 m/s). Each is done four times, and the least
				-- of the ones that hit is taken, as a punch can be a critical hit. The bonus is the movement's (25% at 9 m/s, none up to
				-- 4.5 m/s), most of which has to show.
				local function punch(moving)
					local target = t.spawn_target(moving and 4 or 1.5)

					if not target then
						return nil
					end

					local damage = t.track_damage(target)
					local speed

					if moving then
						t.look(0)
						t.move(0, 1)
						t.tap("dodge")
						t.move()
						t.wait(0.1)
					end

					t.press("action_one", 0.1)
					t.watch(0.8, function ()
						if not speed and damage.total > 0 then
							local vx, vy = t.velocity()

							speed = math.sqrt(vx * vx + vy * vy)
						end
					end)
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
	{ name = "shield_priest", setting_id = "shield_gun_priest", careers = { "wh_priest" } },
}) do
	local definition = mod.items.weapons[variant.setting_id]

	runner.add_suite({
		name = variant.name,
		item = definition.key,
		template = definition.template,
		slot = "slot_melee",
		careers = variant.careers,
		scenarios = scenarios(),
	})
end
