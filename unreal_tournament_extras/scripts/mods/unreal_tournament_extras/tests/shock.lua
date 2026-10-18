local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The Shock Rifle's in-game tests (see runner.lua). Run them with /ut_test shock. They run in the runner's level, Righteous Stand. The
-- numbers expected are UT's (XWeapons/ShockBeamFire, ShockProjFire and ShockProjectile) as the mod turns them into this game's.

local runner = mod.test_runner

local definition = ut.items.weapons.shock_rifle
local overcharge_values = PlayerUnitStatusSettings.overcharge_values

local CONFIG = {
	-- ShockBeamFire.FireRate and ShockProjFire.FireRate
	beam_fire_rate = 0.7, -- s
	ball_fire_rate = 0.6, -- s
	-- The ball's speed: 15 m/s, with this much either way
	ball_speed = 15, -- m/s
	speed_margin = 1.5, -- m/s
	-- ShockProjectile.LifeSpan
	ball_lifetime = 10, -- s
	-- The most the player's own ball and combo hurt them
	ball_self_damage = 18,
	-- A combo costs this many beams on top of the beam that set it off (ComboAmmoCost)
	combo_extra_beams = 3,
	-- The ball's explosion throws the player up at least this fast when it goes off at their feet
	min_jump_speed = 2, -- m/s
	-- Where a ball starts from the player's eye (ShockProjFire.ProjSpawnOffset: 24 ahead and 8 to the right, in UT units), with this
	-- much either way, and how much two shots may differ
	ball_start_right = 8 * ut.utils.UT_UNIT, -- m
	ball_start_margin = 0.05, -- m
	ball_start_same = 0.02, -- m
	-- The beam's damage against armour and monsters, of its damage against an enemy with none (shock_rifle.lua's armor_attack), with this
	-- much either way, by the breeds it is tried on. A Chaos warrior's body is super armour (its primary_armor_category), 0.5. A rat
	-- ogre is a monster, 1.5, and a boss, whose damage the game takes down to 0.45 (DamageUtils.calculate_damage's boss_damage_reduction).
	armour_breeds = {
		{ "chaos_warrior", 0.5 },
		{ "skaven_rat_ogre", 1.5 * 0.45 },
	},
	armour_margin = 0.1,
	-- The ball's explosion: the enemies beside the one it hits, this far from it (inside the radius of 90 UT units, 1.8 m, and outside)
	inside_radius = 1.2, -- m
	outside_radius = 2.6, -- m
	-- The combo's explosion: its radius (ShockCombo's 190 UT units), and how far from it an enemy has to be to be counted inside or
	-- outside it. Where the enemies stand from the player: as far ahead as the ball is when the beam can follow it, and to the side.
	combo_radius = 3.8, -- m
	combo_radius_margin = 0.6, -- m
	combo_ahead = 11, -- m
	combo_sides = { -1.5, 2.5, 6 }, -- m
	-- A critical hit does at least this much more than a plain one, and the breed it is also checked against, with the share of the
	-- damage the armour takes
	crit_least_ratio = 1.2,
	crit_armour_breed = { "chaos_warrior", 0.5 },
	-- An enemy with a shield that can't be broken (a shielded Stormvermin's)
	shield_breed = "skaven_storm_vermin_with_shield",
}

local function is_ball(action)
	return action.ut_shock_ball
end

local function count(list, name)
	local total = 0

	for _, value in ipairs(list) do
		if value == name then
			total = total + 1
		end
	end

	return total
end

-- The beams of the player, while a test records them
local beams = {}
local recording = false

ut.shock_beam_callbacks.ut_test = function (owner_unit, start_position, end_position, hit_normal, reflected)
	local player = Managers.player:local_player()

	if recording and not reflected and player and owner_unit == player.player_unit then
		beams[#beams + 1] = Managers.time:time("game")
	end
end

local function record_beams()
	table.clear(beams)

	recording = true
end

-- Watches the player's balls from now on: the ones fired, in order, and where each was every frame. A ball of an earlier shot that
-- still flies is left out.
local function watch_balls(t)
	local seen = {}
	local earlier = t.on_main_thread(function ()
		local units = {}

		for _, unit in ipairs(t.projectiles(is_ball)) do
			units[unit] = true
		end

		return units
	end)

	return seen, function ()
		for _, unit in ipairs(t.projectiles(is_ball)) do
			if not seen[unit] and not earlier[unit] then
				seen[unit] = {
					positions = {},
				}
				seen[#seen + 1] = unit
			end

			if seen[unit] then
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

-- The least damage of two beams at an enemy of the breed ahead (the least, as one can be a critical hit; a beam at one that is dead
-- already isn't counted)
local function beam_damage(t, breed_name)
	t.go_to_start()

	local enemy = t.spawn(breed_name, 5)

	if not t.expect(enemy, "the %s could not be spawned", breed_name) then
		return nil
	end

	t.wait(1)
	t.aim_at(enemy)

	local least

	for _ = 1, 2 do
		if t.health_of(enemy) > 0 then
			local damage = t.track_damage(enemy)

			t.press("action_one", 0.05)
			t.wait(CONFIG.beam_fire_rate + 0.2)

			least = math.min(least or math.huge, damage.total)
		end
	end

	t.remove(enemy)

	return least
end

-- The damage of one beam at an enemy of the breed 5 m ahead, aimed at its middle
local function one_beam(t, breed_name)
	t.go_to_start()

	local enemy = t.spawn(breed_name, 5)

	if not t.expect(enemy, "the %s could not be spawned", breed_name) then
		return nil
	end

	t.wait(1)
	t.aim_at(enemy)

	local damage = t.track_damage(enemy)

	t.press("action_one", 0.05)
	t.wait(CONFIG.beam_fire_rate + 0.2)
	t.remove(enemy)

	return damage.hits[1] and damage.hits[1].amount
end

local function scenarios()
	return {
		{
			name = "a beam hurts what it hits and costs overcharge",
			run = function (t)
				local target = t.spawn_target(6)

				if not t.expect(target, "the target could not be spawned") then
					return
				end

				local health = t.health_of(target)
				local before = t.overcharge()

				record_beams()
				t.press("action_one", 0.05)

				local overcharge = t.overcharge() - before

				t.wait(0.5)
				recording = false

				local cost = overcharge_values.ut_shock_beam

				t.expect(#beams == 1, "%d beams were fired, not 1", #beams)
				t.expect(t.health_of(target) < health, "the target was not hurt: %s of %s", t.health_of(target), health)
				t.expect(math.abs(overcharge - cost) <= cost * 0.2, "the beam cost %.2f overcharge, not %.2f", overcharge, cost)
			end,
		},
		{
			name = "a beam stops at the first enemy",
			run = function (t)
				local near = t.spawn(runner.target_breed, 4)
				local far = t.spawn(runner.target_breed, 7)

				if not t.expect(near and far, "the targets could not be spawned") then
					return
				end

				t.wait(1)
				t.aim_at(near)

				local near_health, far_health = t.health_of(near), t.health_of(far)

				t.press("action_one", 0.05)
				t.wait(0.5)

				t.expect(t.health_of(near) < near_health, "the near target was not hurt")
				t.expect(t.health_of(far) == far_health, "the far target, behind the near one, was hurt: %s of %s", t.health_of(far), far_health)
			end,
		},
		{
			name = "holding fire repeats the beam at its fire rate",
			run = function (t)
				t.look(20)
				record_beams()
				t.press("action_one", 2)
				t.wait(0.3)
				recording = false

				-- (shots at 0, 0.7 and 1.4 s)
				t.expect(#beams == 3, "%d beams in 2 s, not 3", #beams)

				for i = 2, #beams do
					local gap = beams[i] - beams[i - 1]

					t.expect(math.abs(gap - CONFIG.beam_fire_rate) < 0.05, "beam %d came %.3f s after the one before, not %.2f", i, gap, CONFIG.beam_fire_rate)
				end
			end,
		},
		{
			name = "the ball waits for the beam's fire rate",
			run = function (t)
				t.look(20)

				local balls, observe = watch_balls(t)
				local beam_t = Managers.time:time("game")

				t.press("action_one", 0.05)
				t.press("action_two", 1, observe)

				local first = balls[1] and balls[balls[1]].positions[1]

				t.expect(first ~= nil, "no ball was fired")
				t.expect(not first or first.t - beam_t >= CONFIG.beam_fire_rate - 0.05, "the ball left %.2f s after the beam, before its %.2f s", first and first.t - beam_t or -1, CONFIG.beam_fire_rate)
				t.expect(#balls == 1, "%d balls were fired while the button was held 1 s, not 1", #balls)
			end,
		},
		{
			name = "a ball flies straight at its speed",
			run = function (t)
				-- Level, over the open square
				t.look(0)

				local before = t.overcharge()
				local balls, observe = watch_balls(t)

				t.press("action_two", 0.05, observe)
				t.watch(0.5, observe)

				t.expect(#balls == 1, "%d balls were fired, not 1", #balls)

				local positions = balls[1] and balls[balls[1]].positions

				if not positions or #positions < 5 then
					t.expect(false, "the ball was not seen in flight long enough")

					return
				end

				local first, last = positions[2], positions[#positions]
				local time = last.t - first.t
				local distance = math.sqrt((last.x - first.x) ^ 2 + (last.y - first.y) ^ 2 + (last.z - first.z) ^ 2)
				local speed = distance / time

				t.expect(math.abs(speed - CONFIG.ball_speed) <= CONFIG.speed_margin, "the ball flew %.1f m/s, not %.1f", speed, CONFIG.ball_speed)
				t.expect(math.abs(last.z - first.z) < 0.05, "the ball fell %.2f m in %.2f s: it has gravity", first.z - last.z, time)
				t.expect(t.overcharge() > before, "the ball cost no overcharge")
			end,
		},
		{
			name = "a ball explodes on what it hits and hurts it",
			run = function (t)
				local target = t.spawn_target(6)

				if not t.expect(target, "the target could not be spawned") then
					return
				end

				local health = t.health_of(target)
				local explosions = t.explosions()

				t.press("action_two", 0.05)
				t.wait(1)

				t.expect(count(explosions, "ut_shock_ball_explosion") == 1, "the ball made %d explosions, not 1 (%s)", count(explosions, "ut_shock_ball_explosion"), table.concat(explosions, ", "))
				t.expect(t.health_of(target) < health, "the target was not hurt: %s of %s", t.health_of(target), health)
			end,
		},
		{
			name = "a beam into a ball makes a combo",
			run = function (t)
				t.look(0)

				local explosions = t.explosions()
				local before = t.overcharge()

				t.press("action_two", 0.05)
				t.wait(CONFIG.ball_fire_rate + 0.05)

				local before_beam = t.overcharge()

				t.press("action_one", 0.05)

				local beam_cost = t.overcharge() - before_beam

				t.wait(0.5)

				local expected = overcharge_values.ut_shock_beam * (1 + CONFIG.combo_extra_beams)

				t.expect(count(explosions, "ut_shock_combo_explosion") == 1, "there were %d combos, not 1 (%s)", count(explosions, "ut_shock_combo_explosion"), table.concat(explosions, ", "))
				t.expect(count(explosions, "ut_shock_ball_explosion") == 0, "the ball also exploded on its own")
				t.expect(math.abs(beam_cost - expected) <= expected * 0.2, "the combo's beam cost %.2f overcharge, not %.2f (a beam and %d more)", beam_cost, expected, CONFIG.combo_extra_beams)
				t.expect(before_beam > before, "the ball cost no overcharge")
			end,
		},
		{
			name = "a combo hurts much more than a beam",
			run = function (t)
				-- The damage is all of it, past what kills a rat (t.track_damage). The first rat is shot with a beam. The second
				-- stands beside the way of a ball, and a beam sets the ball off as it passes.
				local first = t.spawn_target(6)

				if not t.expect(first, "the first target could not be spawned") then
					return
				end

				local beam = t.track_damage(first)

				t.press("action_one", 0.05)
				t.wait(0.8)

				t.expect(beam.total > 0, "the beam did not hurt the target")

				-- (it would be in the ball's way)
				t.remove(first)

				-- (the ball is about 11 m along when the beam can follow it; the rat is 1.2 m to the left of its way)
				local ground = t.ground_at(11, -1.2)
				local second = ground and t.spawn_at(runner.target_breed, ground[1], ground[2], ground[3])

				if not t.expect(second, "the second target could not be spawned") then
					return
				end

				t.wait(1)
				t.look(0)

				local combo = t.track_damage(second)
				local explosions = t.explosions()

				t.press("action_two", 0.05)
				t.wait(CONFIG.ball_fire_rate + 0.05)
				t.press("action_one", 0.05)
				t.wait(0.8)

				t.expect(count(explosions, "ut_shock_combo_explosion") == 1, "no combo went off (%s)", table.concat(explosions, ", "))
				t.expect(combo.total > 2 * beam.total, "the combo did %.1f damage beside it, a beam %.1f", combo.total, beam.total)
			end,
		},
		{
			name = "a ball at the feet hurts the player and throws them up",
			run = function (t)
				t.hurtable(true)
				t.look(-85)

				local health = t.health()
				local up = 0

				t.press("action_two", 0.05)
				t.watch(0.4, function ()
					local _, _, z = t.velocity()

					up = math.max(up, z)
				end)

				local hurt = health - t.health()

				t.expect(hurt > 0, "the ball's explosion did not hurt the player")
				t.expect(hurt <= CONFIG.ball_self_damage + 0.5, "the ball hurt the player %.1f, more than %d", hurt, CONFIG.ball_self_damage)
				t.expect(up >= CONFIG.min_jump_speed, "the ball threw the player up at %.1f m/s at most", up)
			end,
		},
		{
			name = "a ball that hits nothing is gone after its life",
			place = "sky",
			run = function (t)
				t.look(85)

				local balls, observe = watch_balls(t)
				local explosions = t.explosions()

				t.press("action_two", 0.05, observe)
				t.watch(CONFIG.ball_lifetime - 0.5, observe)

				local alive_late = #t.projectiles(is_ball) == 1

				t.wait(1.5)

				t.expect(#balls == 1, "%d balls were fired, not 1", #balls)
				t.expect(alive_late, "the ball was gone before its %d s", CONFIG.ball_lifetime)
				t.expect(#t.projectiles(is_ball) == 0, "the ball was still there after %d s", CONFIG.ball_lifetime)
				t.expect(count(explosions, "ut_shock_ball_explosion") == 0, "the ball exploded when its life ended")
			end,
		},
		{
			name = "the Instagib skin fires a beam that kills with both buttons, for no overcharge",
			run = function (t)
				-- The skin is the wielded slot's (utils.wielded_skin), and the rifle takes its fire modes from it every frame
				local function set_skin(skin)
					return t.on_main_thread(function ()
						local equipment = ScriptUnit.extension(t.unit(), "inventory_system"):equipment()
						local slot_data = equipment.slots[equipment.wielded_slot]
						local before = slot_data.skin

						slot_data.skin = skin

						return before
					end)
				end

				local targets = {}

				for i, side in ipairs({ -1, 1 }) do
					local ground = t.ground_at(6, side)

					targets[i] = ground and t.spawn_at(runner.target_breed, ground[1], ground[2], ground[3])
				end

				if not t.expect(targets[1] and targets[2], "the targets could not be spawned") then
					return
				end

				local skin = set_skin("ut_shock_rifle_skin_instagib")
				local ok, error_message = pcall(function ()
					t.wait(1)

					local balls, observe = watch_balls(t)
					local before = t.overcharge()

					record_beams()

					for i, button in ipairs({ "action_one", "action_two" }) do
						local damage = t.track_damage(targets[i])

						t.aim_at(targets[i])
						t.press(button, 0.05, observe)
						t.watch(1.3, observe)

						t.expect(damage.total >= 200, "the %s beam did %.1f damage, not a kill of anything", button, damage.total)
						t.expect(t.health_of(targets[i]) == 0, "the %s beam did not kill the target", button)
					end

					recording = false

					t.expect(#beams == 2, "%d beams were fired, not 2", #beams)
					t.expect(#balls == 0, "a ball was fired")
					t.expect(t.overcharge() <= before + 0.01, "the beams cost %.2f overcharge", t.overcharge() - before)
				end)

				set_skin(skin)
				t.wait(0.5)

				if not ok then
					error(error_message, 0)
				end
			end,
		},
		{
			name = "overheating sets off a combo at the player",
			run = function (t)
				local explosions = t.explosions()

				t.on_main_thread(function ()
					local overcharge_extension = ScriptUnit.extension(t.unit(), "overcharge_system")

					-- (the game stops the first big step just short of the most, OverchargeExtension.add_charge)
					overcharge_extension:add_charge(overcharge_extension:get_max_value())
					overcharge_extension:add_charge(overcharge_extension:get_max_value())
				end)

				t.wait_until(function ()
					return count(explosions, "ut_shock_combo_explosion") > 0
				end, 10, "the overheat's combo")

				t.expect(count(explosions, "ut_shock_combo_explosion") == 1, "overheating made %d combos, not 1 (%s)", count(explosions, "ut_shock_combo_explosion"), table.concat(explosions, ", "))

				-- (the player gets up again before the next scenario)
				t.wait_until(function ()
					return t.state() ~= "overcharge_exploding"
				end, 10, "the overheat to end")
				t.wait(1)
			end,
		},
		{
			name = "the beam waits for the ball's fire rate",
			run = function (t)
				t.look(20)

				local balls, observe = watch_balls(t)

				record_beams()
				t.press("action_two", 0.05, observe)
				t.press("action_one", 1)
				t.wait(0.2)
				recording = false

				local ball = balls[1] and balls[balls[1]].positions[1]

				t.expect(ball ~= nil, "no ball was fired")
				t.expect(#beams >= 1, "no beam was fired after the ball")

				if ball and beams[1] then
					t.expect(beams[1] - ball.t >= CONFIG.ball_fire_rate - 0.05, "the beam left %.2f s after the ball, before its %.2f s", beams[1] - ball.t, CONFIG.ball_fire_rate)
				end
			end,
		},
		{
			-- A ball starts ProjSpawnOffset from the eye: to the right of it by Y, level with it, and ahead (it has flown on a little by the
			-- frame it is seen, so only its place across the aim is measured). Two shots start in the same place.
			name = "a ball starts to the right of the eye, in the same place each time",
			run = function (t)
				t.look(0)

				local starts = {}

				for i = 1, 2 do
					local eye = t.on_main_thread(function ()
						local first_person_extension = ScriptUnit.extension(t.unit(), "first_person_system")
						local rotation = first_person_extension:current_rotation()

						return {
							position = Vector3Box(first_person_extension:current_position()),
							right = Vector3Box(Quaternion.right(rotation)),
							up = Vector3Box(Quaternion.up(rotation)),
						}
					end)
					local balls, observe = watch_balls(t)

					t.press("action_two", 0.05, observe)
					t.watch(0.1, observe)

					local first = balls[1] and balls[balls[1]].positions[1]

					if not t.expect(first, "ball %d was not seen", i) then
						return
					end

					local offset = Vector3(first.x, first.y, first.z) - eye.position:unbox()

					starts[i] = {
						right = Vector3.dot(offset, eye.right:unbox()),
						up = Vector3.dot(offset, eye.up:unbox()),
					}
					t.wait(1)
				end

				for i, start in ipairs(starts) do
					t.expect(math.abs(start.right - CONFIG.ball_start_right) <= CONFIG.ball_start_margin, "ball %d started %.2f m to the right of the eye, not %.2f", i, start.right, CONFIG.ball_start_right)
					t.expect(math.abs(start.up) <= CONFIG.ball_start_margin, "ball %d started %.2f m above the eye, not level with it", i, start.up)
				end

				t.expect(math.abs(starts[1].right - starts[2].right) <= CONFIG.ball_start_same and math.abs(starts[1].up - starts[2].up) <= CONFIG.ball_start_same, "the two balls started in different places")
			end,
		},
		{
			-- The beam's damage is the armour's share of its damage against an enemy with none (a Chaos marauder)
			name = "a beam hurts armoured enemies and monsters by their armour",
			run = function (t)
				local plain = beam_damage(t, "chaos_marauder")

				if not plain or not t.expect(plain > 0, "the beam did not hurt the marauder") then
					return
				end

				for _, entry in ipairs(CONFIG.armour_breeds) do
					local breed_name, share = entry[1], entry[2]
					local damage = beam_damage(t, breed_name)

					if damage then
						t.log("%s: %.1f, %.2f of the marauder's %.1f", breed_name, damage, damage / plain, plain)
						t.expect(math.abs(damage / plain - share) <= CONFIG.armour_margin, "the beam did %.2f of its damage to the %s, not %.2f", damage / plain, breed_name, share)
					end
				end
			end,
		},
		{
			-- A ball goes off on the enemy it hits, and hurts the enemies around as far as its radius, less the farther they are, and none
			-- past it
			name = "a ball's explosion falls off to its radius",
			run = function (t)
				local hit = t.spawn_target(6)

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

				t.press("action_two", 0.05)
				t.wait(1)

				local on_hit, near, far = damages[1].total, damages[2].total, damages[3].total

				t.log("the one hit %.1f, %.1f m from it %.1f, %.1f m from it %.1f", on_hit, CONFIG.inside_radius, near, CONFIG.outside_radius, far)
				t.expect(near > 0, "the explosion did not hurt the enemy %.1f m from it, inside its radius", CONFIG.inside_radius)
				t.expect(near < on_hit, "the enemy %.1f m from the explosion took as much as the one it hit (%.1f, %.1f)", CONFIG.inside_radius, near, on_hit)
				t.expect(far == 0, "the explosion hurt the enemy %.1f m from it, past its radius (%.1f)", CONFIG.outside_radius, far)
			end,
		},
		{
			-- A combo hurts the enemies within its radius and none past it, and the game's buffs on attack (talents, traits) run once for
			-- it, as for the Flak Cannon's shell, or twice when the second hit is on the head. Each enemy is judged by how far it was from
			-- where the combo went off.
			name = "a combo hurts the enemies within its radius, and procs once",
			run = function (t)
				local enemies = {}

				for i, side in ipairs(CONFIG.combo_sides) do
					local ground = t.ground_at(CONFIG.combo_ahead, side)

					enemies[i] = ground and t.spawn_at(runner.target_breed, ground[1], ground[2], ground[3])
				end

				if not t.expect(#enemies == #CONFIG.combo_sides, "the enemies could not be spawned") then
					return
				end

				t.wait(1)
				t.look(0)

				local damages = {}

				for i, enemy in ipairs(enemies) do
					damages[i] = t.track_damage(enemy)
				end

				local explosions = t.explosions()

				t.press("action_two", 0.05)
				t.wait(CONFIG.ball_fire_rate + 0.05)

				local procs = t.procs(definition.key)

				t.press("action_one", 0.05)
				t.wait(0.8)

				local combo = nil

				for i, name in ipairs(explosions) do
					if name == "ut_shock_combo_explosion" then
						combo = explosions.positions[i]
					end
				end

				if not t.expect(combo, "no combo went off (%s)", table.concat(explosions, ", ")) then
					return
				end

				local distances = t.on_main_thread(function ()
					local list = {}

					for i, enemy in ipairs(enemies) do
						list[i] = Unit.alive(enemy) and Vector3.distance(Unit.local_position(enemy, 0), Vector3(combo[1], combo[2], combo[3])) or math.huge
					end

					return list
				end)

				for i, distance in ipairs(distances) do
					local hurt = damages[i].total > 0

					t.log("an enemy %.1f m from the combo took %.1f", distance, damages[i].total)

					if distance < CONFIG.combo_radius - CONFIG.combo_radius_margin then
						t.expect(hurt, "the combo did not hurt an enemy %.1f m from it, inside its radius of %.1f m", distance, CONFIG.combo_radius)
					elseif distance > CONFIG.combo_radius + CONFIG.combo_radius_margin then
						t.expect(not hurt, "the combo hurt an enemy %.1f m from it, past its radius of %.1f m (%.1f)", distance, CONFIG.combo_radius, damages[i].total)
					end
				end

				local second_is_head = procs[2] and string.find(procs[2], "head", 1, true)

				t.log("the buffs ran %d times (%s)", #procs, table.concat(procs, ", "))
				t.expect(#procs >= 1, "the buffs did not run for the combo")
				t.expect(#procs <= 1 or #procs == 2 and second_is_head, "the buffs ran %d times for one combo (%s)", #procs, table.concat(procs, ", "))
			end,
		},
		{
			-- An enemy's raised shield stops the beam, as it stops the game's shots (the beam has no ignore_shield_hit)
			name = "a raised shield stops the beam",
			run = function (t)
				local enemy = t.spawn(CONFIG.shield_breed, 5)

				if not t.expect(enemy, "the %s could not be spawned", CONFIG.shield_breed) then
					return
				end

				t.raise_shield(enemy)
				t.wait(1)
				t.aim_at(enemy)

				local damage = t.track_damage(enemy)

				t.press("action_one", 0.05)
				t.wait(0.5)

				t.expect(damage.total == 0, "the beam hurt the %s through its shield (%.1f)", CONFIG.shield_breed, damage.total)
			end,
		},
		{
			-- A critical beam does more damage, and armour takes the same share of it as of a plain one
			name = "a critical beam does more damage, and armour takes the same share of it",
			run = function (t)
				t.critical_hits(false)

				local plain = one_beam(t, "chaos_marauder")

				t.critical_hits(true)

				local critical = one_beam(t, "chaos_marauder")
				local armoured = one_beam(t, CONFIG.crit_armour_breed[1])

				if not t.expect(plain and critical and armoured, "a beam did not hurt its enemy") then
					return
				end

				t.log("plain %.1f, critical %.1f, critical against the %s %.1f", plain, critical, CONFIG.crit_armour_breed[1], armoured)
				t.expect(critical > plain * CONFIG.crit_least_ratio, "a critical beam did %.1f, not more than the plain %.1f", critical, plain)
				t.expect(math.abs(armoured / critical - CONFIG.crit_armour_breed[2]) <= CONFIG.armour_margin, "a critical beam did %.2f of its damage to the %s, not %.2f", armoured / critical, CONFIG.crit_armour_breed[1], CONFIG.crit_armour_breed[2])
			end,
		},
		{
			-- The rifle can be put away right after a beam, and no beam comes after it
			name = "the rifle can be put away right after a beam",
			run = function (t)
				local template = t.wielded()

				record_beams()
				t.press("action_one", 0.05)
				t.tap("wield_1")
				t.hold("action_one")
				t.wait(CONFIG.beam_fire_rate * 2)
				t.release("action_one")
				recording = false

				t.expect(t.wielded() ~= template, "the rifle is still in the hands (%s)", tostring(t.wielded()))
				t.expect(#beams == 1, "%d beams were fired, not 1", #beams)

				t.tap("wield_2")
				t.wait(1.5)
			end,
		},
	}
end

runner.add_suite({
	name = "shock",
	item = definition.key,
	template = definition.template,
	slot = "slot_ranged",
	careers = { "bw_adept" },
	scenarios = scenarios(),
})

-- Bots with the Shock Rifle (shock/bots.lua). Only Sienna's careers have it, and a hero can't be a bot and the player at once, so these run
-- in a suite of their own with the player as Kruber, and the bot is Sienna as a Battle Wizard, with her own mind.
-- "a bot shoots enemies with it": the bot starts behind the player, so the player is in its way, and its target is a special ahead: from
-- afar a bot goes for a special (an opportunity target, within 40 m: AIBotGroupSystem), and keeps its rifle out for it until it is
-- within 2 m (BTConditions.bot_in_melee_range). A special is shot once it has been seen, which a calm one never is, so it attacks: a
-- ratling gunner shoots at the player from where it stands.
local BOTS = {
	profile = "bright_wizard",
	career = 1,
	behind = -3, -- m
	special = "skaven_ratling_gunner",
	special_distance = 14, -- m
	-- "a bot shoots a boss it can't reach": the boss, where the player stands from below_unreachable (ahead, and to the right), and how
	-- far ahead of the player the bot is
	boss = "skaven_rat_ogre",
	players_ahead = 2, -- m
	players_right = 2, -- m
	bot_distance = 2, -- m
	-- How long the bot has to hurt the special or the boss
	fight_time = 30, -- s
}

-- Adds the bot behind the player
local function shock_bot(t)
	local bot = t.add_bot(BOTS.profile, BOTS.career, definition.key, BOTS.behind, nil, true)

	t.expect(bot, "the bot could not be added")

	return bot
end

-- The damage from the Shock Rifle in records of t.track_damage
local function from_shock_rifle(records)
	local total = 0

	for _, record in ipairs(records) do
		for _, hit in ipairs(record.hits) do
			if hit.source == definition.key then
				total = total + hit.amount
			end
		end
	end

	return total
end

local function bot_scenarios()
	return {
		{
			-- The bot shoots the special with the rifle, past the player in its way, and never hurts the player
			name = "a bot shoots enemies with it",
			run = function (t)
				t.hurtable(true)

				local special = t.spawn(BOTS.special, BOTS.special_distance)

				if not t.expect(special, "the %s could not be spawned", BOTS.special) then
					return
				end

				-- (a bot shoots a special only once it has been seen, which a calm one never is: shooting at the player makes it seen,
				-- and a ratling gunner shoots from where it stands)
				t.on_main_thread(function ()
					runner.provoke(special)
				end)

				local damage = t.track_damage(special)
				local player_damage = t.track_damage(t.unit())

				if not shock_bot(t) then
					return
				end

				t.wait_until(function ()
					return from_shock_rifle({ damage }) > 0
				end, BOTS.fight_time, "the bot to hurt the special")
				t.wait(5)

				t.expect(from_shock_rifle({ damage }) > 0, "the bot did not hurt the %s with the Shock Rifle in %d s", BOTS.special, BOTS.fight_time)
				t.expect(from_shock_rifle({ player_damage }) == 0, "the bot's shots hurt the player %.1f", from_shock_rifle({ player_damage }))
			end,
		},
		{
			-- The bot shoots a boss with the rifle (shock_rifle.lua's effective_against). A bot fights a boss in melee once it is within
			-- about 12 m (BTConditions.bot_in_melee_range: a boss is a target of the bot's ordinary fighting), unless it is 2 m or more
			-- above the bot. So the boss stands where bots can't walk to, and the bot and the player 4.5 m below it (the runner's named
			-- places unreachable and below_unreachable).
			name = "a bot shoots a boss it can't reach",
			run = function (t)
				t.go_to("below_unreachable")

				local stand = t.ground_at(BOTS.players_ahead, BOTS.players_right)

				if not t.expect(stand, "there is no ground where the player should stand") then
					return
				end

				t.on_main_thread(function ()
					runner.move_player(t.unit(), Vector3(stand[1], stand[2], stand[3]))
				end)
				t.wait(0.5)

				local boss = t.spawn_at(BOTS.boss, unpack(t.place("unreachable")))

				if not t.expect(boss, "the %s could not be spawned", BOTS.boss) then
					return
				end

				-- (a bot goes for a boss only once it has been seen (AIBotGroupSystem._calculate_opportunity_utility), which a calm one
				-- isn't: it is marked seen, as a player's look at it marks it (ProximitySystem))
				t.on_main_thread(function ()
					ScriptUnit.extension(boss, "proximity_system").has_been_seen = true
				end)

				local damage = t.track_damage(boss)

				if not t.expect(t.add_bot(BOTS.profile, BOTS.career, definition.key, BOTS.bot_distance, nil, true), "the bot could not be added") then
					return
				end

				t.wait_until(function ()
					return from_shock_rifle({ damage }) > 0
				end, BOTS.fight_time, "the bot to hurt the boss")

				t.expect(from_shock_rifle({ damage }) > 0, "the bot did not hurt the %s with the Shock Rifle in %d s", BOTS.boss, BOTS.fight_time)
			end,
		},
	}
end

local flak_cannon = ut.items.weapons.flak_cannon

runner.add_suite({
	name = "shock_bots",
	item = flak_cannon.key,
	template = flak_cannon.template,
	slot = "slot_ranged",
	careers = { "es_mercenary" },
	scenarios = bot_scenarios(),
})
