local mod = get_mod("unreal_tournament")

-- The Shock Rifle's in-game tests (see runner.lua). Run them with /ut_test shock. They run in the runner's level, Righteous Stand. The
-- numbers expected are UT's (XWeapons/ShockBeamFire, ShockProjFire and ShockProjectile) as the mod turns them into this game's.

local runner = mod.test_runner

local definition = mod.items.weapons.shock_rifle
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

mod.shock_beam_callbacks.ut_test = function (owner_unit, start_position, end_position, hit_normal, reflected)
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
