local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The Shield Gun's in-game tests (see runner.lua), for each hero's Shield Gun. Run them with /ut_test shield. They run in the runner's
-- level, Righteous Stand.

local runner = mod.test_runner
local shield = ut.shield

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
	time = 37.5, -- s
}

-- The horde of "a punch never hits the player who punches" (t.fight_horde): the player starts each dodge keep m from the nearest rat
local SELF_HIT_HORDE = {
	size = 30,
	breeds = { "skaven_clan_rat", "skaven_slave" },
	refill_below = 20,
	distance = 6, -- m
	keep = 3, -- m
	time = 90, -- s
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

-- "a full punch at the floor hurts the player as UT's": how long the charge is held (past the full charge's 2.5 s), how far the player
-- looks down, and the damage UT's punch of a wall does at a full charge, halved as shield_gun.lua halves it (MinSelfDamage 8 +
-- SelfDamageScale 0.3 * 150, times 0.5)
local FULL_CHARGE_TIME = 2.8 -- s
local FLOOR_PITCH = -60 -- degrees
local FULL_SELF_DAMAGE = 26.5

-- "a bot punches enemies with it": the rats it is given to fight, how far ahead of the player they and the bot are, and how long it has
local BOT_FIGHT_RATS = 3
local BOT_FIGHT_DISTANCE = 4 -- m
local BOT_FIGHT_TIME = 20 -- s
-- "a bot punches only what is in reach": how much farther than the punch's reach a rat's feet may be from the bot's, when it punches
-- (the reach is from the eyes to the rat's body, which is about this wide)
local BOT_REACH_MARGIN = 0.6 -- m

-- The shield scenarios: how far ahead the enemy with a shield stands, and how long the charge of a charged punch is held (past a third
-- of the charge, which breaks shields: shield_gun.lua's shield_break_share)
local SHIELD_ENEMY_DISTANCE = 1.5 -- m
local SHIELD_BREAK_HOLD = 1.5 -- s

-- Has the gun punch an enemy with a shield ahead, charged past a third or not, and returns the damage it took and whether its shield
-- is broken. A charged punch is charged facing away, as the charge punches by itself once an enemy is in reach, and then the player
-- turns to the enemy, so the punch comes at once.
local function punch_shield(t, breed_name, charged)
	local enemy = t.spawn(breed_name, SHIELD_ENEMY_DISTANCE)

	if not t.expect(enemy, "the %s could not be spawned", breed_name) then
		return nil
	end

	-- (an enemy's shield blocks only while it holds it up, which a horde's enemies do from their spawn and the others once they fight:
	-- AIShieldUserExtension. The runner's enemy is calm, so its shield is put up as a horde's is.)
	t.on_main_thread(function ()
		ScriptUnit.extension(enemy, "ai_shield_system"):set_is_blocking(true)
	end)
	t.wait(1)

	local damage = t.track_damage(enemy)

	if charged then
		t.look(0, 180)
		t.hold("action_one")
		t.wait(SHIELD_BREAK_HOLD)
		t.aim_at(enemy)
		t.wait(0.3)
		t.release("action_one")
	else
		t.aim_at(enemy)
		t.press("action_one", 0.1)
	end

	t.wait(0.5)

	local broken = t.on_main_thread(function ()
		local shield_extension = Unit.alive(enemy) and ScriptUnit.has_extension(enemy, "ai_shield_system")

		return shield_extension and shield_extension.shield_broken or false
	end)

	return damage.total, broken
end

-- The scenarios of an enemy's attack at the shield: how far ahead the enemy starts, and how long it is given to attack
local ATTACK_DISTANCE = 8 -- m
local ATTACK_TIME = 20 -- s
-- After the shield stopped an attack, how long the player keeps the shield up and is watched, in case the enemy tries again
local ATTACK_AFTER = 3 -- s

-- The Shock Rifle's shots at the shield come from a bot: Sienna as a Battle Wizard (her first career) with the Shock Rifle, this far ahead
local SHOCK_BOT_PROFILE = "bright_wizard"
local SHOCK_BOT_CAREER = 1
local SHOCK_DISTANCE = 6 -- m
-- The player looks this far to the side of the bot (inside the shield's arc of 68 degrees), at an enemy that far away, so that a
-- reflected shot, which goes on the way the player looks, hits that enemy
local SHOCK_TURN = 30 -- degrees
-- How long after the bot fires its shot is given to get to the shield and on to the enemy, and how long the bot waits between shots
local SHOCK_SHOT_TIME = 1.5 -- s
local SHOCK_SHOT_GAP = 2 -- s
-- The second shield of the reflections from shield to shield: Bardin as an Ironbreaker (his second career) with his Shield Gun
local SHIELD_BOT_PROFILE = "dwarf_ranger"
local SHIELD_BOT_CAREER = 2
-- The rat that the shot goes on to from Bardin's shield: on the open square ahead, 45 degrees to the other side of Sienna (the player,
-- who faces Bardin, turns this far the other way to put it there), and this far from the player. From Bardin it is 46 degrees off the
-- way to the player, inside his shield's arc, and the way to it passes 4 m from the player and 1.5 m from Sienna. (Behind the player
-- is the alley of the start, whose walls were in the way.)
local CHAIN_ENEMY_TURN = SHOCK_TURN + 45 -- degrees
local CHAIN_ENEMY_DISTANCE = 5 -- m
-- How high above its feet the rat's middle is, which the shot from Bardin's shield is sent at
local CHAIN_ENEMY_MIDDLE = 0.7 -- m
-- How high above Bardin's feet the player looks at him
local CHAIN_AIM_HEIGHT = 1 -- m

-- Turns the player to face the middle of a unit at once, from inside an observer of a frame (t.aim_at waits a little)
local function face(t, unit)
	local first_person_extension = Unit.alive(t.unit()) and ScriptUnit.has_extension(t.unit(), "first_person_system")

	if first_person_extension and Unit.alive(unit) then
		local direction = Vector3.normalize(Unit.world_position(unit, 0) + Vector3(0, 0, 1) - first_person_extension:current_position())

		first_person_extension:set_rotation(Quaternion.look(direction, Vector3.up()))
	end
end

local function stamina_spent(t)
	local status_extension = ScriptUnit.has_extension(t.unit(), "status_system")

	return status_extension and status_extension:current_fatigue() or 0
end

-- Spawns an enemy of the breed ahead and lets it attack the player, who faces it all the while, with the shield up or not. With the
-- shield up, it waits until the shield stops the attack (it costs stamina) and a while after. Without it, it waits until the attack
-- takes the player. Returns whether the attack took the player (taken(status_extension): pounced, grabbed) and whether the shield
-- stopped one. The enemy is killed at the end, which lets the player go.
local function let_attack(t, breed_name, shielded, taken)
	-- (the enemy is spawned ahead of the player, so the player is put back each time, facing the way they started: they faced the
	-- last enemy. It is below the stairs, which a gutter runner gets stuck on.)
	t.go_to("below_stairs")

	local enemy = t.spawn(breed_name, ATTACK_DISTANCE)

	if not t.expect(enemy, "the %s could not be spawned", breed_name) then
		return nil
	end

	t.aim_at(enemy)

	if shielded then
		t.hold("action_two")
		t.wait(0.5)
	end

	local was_taken, stopped = false, false
	local stamina = t.on_main_thread(function ()
		runner.provoke(enemy)

		return stamina_spent(t)
	end)

	local function watch()
		face(t, enemy)

		local status_extension = ScriptUnit.has_extension(t.unit(), "status_system")

		was_taken = was_taken or status_extension and taken(status_extension) or false
		stopped = stopped or stamina_spent(t) > stamina
	end

	t.wait_until(function ()
		watch()

		return was_taken or stopped
	end, ATTACK_TIME, shielded and "the attack to get to the shield" or "the attack to take the player")

	if shielded then
		t.watch(ATTACK_AFTER, watch)
		t.release("action_two")
	end

	t.on_main_thread(function ()
		if HEALTH_ALIVE[enemy] then
			AiUtils.kill_unit(enemy, t.unit())
		end
	end)
	t.wait(2)

	return was_taken, stopped
end

-- Has a bot with the Shock Rifle shoot at the player twice, once with the shield up and once without, with the player looking at an
-- enemy SHOCK_TURN to the side of the bot. button is the bot's button of the shot ("fire" for the beam, "charge_shot" for the ball).
-- With the shield up, the shot must cost the shield's stamina and go on to the enemy and hurt it. Without it, the enemy must not be hurt.
local function shock_at_shield(t, button, what)
	local bot = t.add_bot(SHOCK_BOT_PROFILE, SHOCK_BOT_CAREER, ut.items.weapons.shock_rifle.key, SHOCK_DISTANCE)

	if not t.expect(bot, "the bot could not be added") then
		return
	end

	t.look(0, -SHOCK_TURN)

	local enemy = t.spawn("skaven_clan_rat", SHOCK_DISTANCE)

	if not t.expect(enemy, "the enemy could not be spawned") then
		return
	end

	t.aim_at(enemy)
	t.bot_aim(bot, t.unit())

	local function shoot(shielded)
		if shielded then
			t.hold("action_two")
			t.wait(0.5)
		end

		local damage = t.track_damage(enemy)
		local stamina = t.on_main_thread(function ()
			return stamina_spent(t)
		end)
		local paid = false

		-- (a blocked shot costs a quarter of a stamina point, which comes back within a second, so it is watched for as it happens)
		t.bot_press(bot, button)
		t.watch(SHOCK_SHOT_TIME, function ()
			paid = paid or stamina_spent(t) > stamina
		end)

		if shielded then
			t.release("action_two")
		end

		t.wait(SHOCK_SHOT_GAP)

		return paid, damage.total
	end

	local paid, hurt = shoot(true)

	t.expect(paid, "the %s cost the shield no stamina: it did not get to the shield", what)
	t.expect(hurt > 0, "the reflected %s did not hurt the enemy the player looks at", what)

	local paid_unshielded, hurt_unshielded = shoot(false)

	t.expect(not paid_unshielded, "the %s cost stamina without the shield", what)
	t.expect(hurt_unshielded == 0, "the %s hurt the enemy without the shield (%.1f)", what, hurt_unshielded)
end

-- A Shock Rifle shot that one shield reflects into another is reflected again: the beam up to max_reflections times
-- (InstantFire.DoTrace), the ball each time it gets to a shield (ShockProjectile.ProcessTouch). Sienna (a bot) shoots at the player, who
-- looks at Bardin (a bot with his Shield Gun's shield up) SHOCK_TURN to the side of her. With to_rat, Bardin looks at a rat on the square
-- (CHAIN_ENEMY_TURN), so the shot goes from the player's shield to Bardin's and on to the rat. Without it, Bardin looks back at the player, so the
-- shot goes back and forth between the two shields. The player looks at Bardin level, at CHAIN_AIM_HEIGHT, so the shot gets to his
-- shield as high as it got to the player's (his middle is low: from there the shot went into the ground). A ball is still Sienna's
-- after every reflection, and a shooter's own shield never reflects their ball, so the two shields are the others'. Each reflection is
-- seen by a watch on mod.shield.reflect, which every shot goes through. Returns the reflections as text ("the player, Bardin, ..."),
-- how many there were, and the damage the rat took.
local function shield_to_shield(t, button, to_rat)
	local player = t.unit()
	local shooter = t.add_bot(SHOCK_BOT_PROFILE, SHOCK_BOT_CAREER, ut.items.weapons.shock_rifle.key, SHOCK_DISTANCE)

	if not t.expect(shooter, "Sienna could not be added") then
		return nil
	end

	t.look(0, -SHOCK_TURN)

	local bardin = t.add_bot(SHIELD_BOT_PROFILE, SHIELD_BOT_CAREER, ut.items.weapons.shield_gun_dr.key, SHOCK_DISTANCE, "slot_melee")

	if not t.expect(bardin, "Bardin could not be added") then
		return nil
	end

	local rat

	if to_rat then
		t.look(0, CHAIN_ENEMY_TURN)

		rat = t.spawn("skaven_clan_rat", CHAIN_ENEMY_DISTANCE)

		if not t.expect(rat, "the rat could not be spawned") then
			return nil
		end
	end

	local at = t.on_main_thread(function ()
		local position = Unit.local_position(bardin, 0)

		return { Vector3.x(position), Vector3.y(position), Vector3.z(position) + CHAIN_AIM_HEIGHT }
	end)

	t.aim_at_point(at[1], at[2], at[3])

	if rat then
		-- (a reflected shot starts where it got to the shield's cylinder, on the side towards the player, and goes the way Bardin looks,
		-- so he looks along the line from there to the rat's middle: looking at the rat from his eyes, the shot missed it)
		local direction = t.on_main_thread(function ()
			local bardin_position = Unit.local_position(bardin, 0)
			local towards_player = Vector3.normalize(Vector3.flat(Unit.local_position(player, 0) - bardin_position))
			local hit = bardin_position + towards_player * shield.pawn_radius + Vector3(0, 0, CHAIN_AIM_HEIGHT)
			local way = Vector3.normalize(Unit.local_position(rat, 0) + Vector3(0, 0, CHAIN_ENEMY_MIDDLE) - hit)

			return { Vector3.x(way), Vector3.y(way), Vector3.z(way) }
		end)

		t.bot_look(bardin, direction)
	else
		t.bot_aim(bardin, player)
	end

	t.bot_aim(shooter, player)
	t.bot_defend(bardin, true)
	t.hold("action_two")
	t.wait(0.5)

	local reflected_by = {}
	local reflect = shield.reflect

	shield.reflect = function (...)
		local position, distance, direction, unit = reflect(...)

		if unit then
			reflected_by[#reflected_by + 1] = unit == player and "the player" or unit == bardin and "Bardin" or "someone else"
		end

		return position, distance, direction, unit
	end

	t.after(function ()
		shield.reflect = reflect
	end)

	local damage = rat and t.track_damage(rat)

	t.bot_press(shooter, button)
	t.wait(SHOCK_SHOT_TIME * 2)
	t.release("action_two")

	shield.reflect = reflect

	return table.concat(reflected_by, ", "), #reflected_by, damage and damage.total or 0
end

local function scenarios()
	return {
		{
			name = "charge and punch",
			every_hero = true,
			basic = true,
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
			-- Many enemies close together, and the bodies of those killed falling among them and thrown by the punches. The game keeps
			-- 24 enemies, living and dead, and takes the oldest bodies away past that, so with this many it takes bodies away all the
			-- time. The player punches the nearest rat over and over, and the crowd is filled up again as it thins. The game crashing
			-- is a failure.
			name = "punching into a horde",
			run = function (t)
				local crowd = {}
				local living = {}
				local spots = {}
				local killed = 0
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

				-- (the game uses a dead rat's unit again for one it spawns, so a unit is counted again once it lives again)
				local function watch()
					for unit in pairs(crowd) do
						if not HEALTH_ALIVE[unit] and not counted[unit] then
							counted[unit] = true
							killed = killed + 1
						elseif HEALTH_ALIVE[unit] then
							counted[unit] = nil
						end
					end
				end

				runner.frame_watchers[#runner.frame_watchers + 1] = watch

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

								-- (close enough that the punch reaches it: from 1.2 m it didn't)
								runner.move_player(player, at + away * 0.8)
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

							t.log("%d rats killed so far", killed)
						end
					end
				end)

				for i = #runner.frame_watchers, 1, -1 do
					if runner.frame_watchers[i] == watch then
						table.remove(runner.frame_watchers, i)
					end
				end

				if not ok then
					error(problem, 0)
				end

				t.log("%d rats killed", killed)
				t.expect(killed > 0, "no rat was killed")
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
			-- A gutter runner's pounce that gets to the shield throws it back (shield_gun.lua's hook of BTCrazyJumpAction.run). It
			-- is let pounce once with the shield up towards it, which must cost the shield's stamina and not pin the player, and once
			-- without, which must pin them: that shows the pounce reaches them.
			name = "the shield throws back a gutter runner's pounce",
			run = function (t)
				local function pounced(status_extension)
					return status_extension:is_pounced_down()
				end

				local taken, stopped = let_attack(t, "skaven_gutter_runner", true, pounced)

				t.expect(stopped, "the gutter runner's pounce never got to the shield")
				t.expect(not taken, "the gutter runner pinned the player through the shield")

				local unshielded = let_attack(t, "skaven_gutter_runner", false, pounced)

				t.expect(unshielded, "the gutter runner did not pin the player without the shield")
			end,
		},
		{
			-- A lifeleech's grab fails at the shield (shield_gun.lua's hook of BTCorruptorGrabAction.grab_player), as when the player
			-- dodges it. The same as the pounce: once with the shield up, once without.
			name = "the shield stops a lifeleech's grab",
			run = function (t)
				local function grabbed(status_extension)
					return status_extension:is_grabbed_by_corruptor()
				end

				local taken, stopped = let_attack(t, "chaos_corruptor_sorcerer", true, grabbed)

				t.expect(stopped, "the lifeleech's grab never got to the shield")
				t.expect(not taken, "the lifeleech grabbed the player through the shield")

				local unshielded = let_attack(t, "chaos_corruptor_sorcerer", false, grabbed)

				t.expect(unshielded, "the lifeleech did not grab the player without the shield")
			end,
		},
		{
			-- A Shock Rifle beam that gets to the shield goes on the way the player looks (mod.shield.reflect, from the Shock Rifle's
			-- trace of its beam). A bot fires it (see shock_at_shield).
			name = "the shield reflects a Shock Rifle beam",
			run = function (t)
				shock_at_shield(t, "fire", "beam")
			end,
		},
		{
			-- A Shock Rifle ball that gets to the shield is sent on the way the player looks as a new ball (ShockProjectile.ProcessTouch,
			-- shield_gun.lua's hook of PlayerProjectileImpactUnitExtension.update). A bot fires it (see shock_at_shield).
			name = "the shield reflects a Shock Rifle ball",
			run = function (t)
				shock_at_shield(t, "charge_shot", "ball")
			end,
		},
		{
			-- A beam goes from the player's shield to Bardin's and on to a rat, which it hurts (see shield_to_shield)
			name = "the shield reflects a Shock Rifle beam into another shield and on to a rat",
			run = function (t)
				local order, _, hurt = shield_to_shield(t, "fire", true)

				if order then
					t.expect(order == "the player, Bardin", "the beam was not reflected by the player's shield and then Bardin's, but by: %s", order)
					t.expect(hurt > 0, "the beam did not hurt the rat after the two shields")
				end
			end,
		},
		{
			-- A ball goes from the player's shield to Bardin's and on to a rat, which it hurts (see shield_to_shield)
			name = "the shield reflects a Shock Rifle ball into another shield and on to a rat",
			run = function (t)
				local order, _, hurt = shield_to_shield(t, "charge_shot", true)

				if order then
					t.expect(order == "the player, Bardin", "the ball was not reflected by the player's shield and then Bardin's, but by: %s", order)
					t.expect(hurt > 0, "the ball did not hurt the rat after the two shields")
				end
			end,
		},
		{
			-- A beam between two shields that face each other goes back and forth max_reflections times, and then ends at the shield
			-- it gets to next (see shield_to_shield)
			name = "the shield reflects a Shock Rifle beam back and forth at most max_reflections times",
			run = function (t)
				local order = shield_to_shield(t, "fire", false)
				local expected = { "the player", "Bardin", "the player", "Bardin", "the player" }

				if order then
					expected = table.concat(expected, ", ", 1, shield.max_reflections)
					t.expect(order == expected, "the beam was reflected by %s, not by %s", order, expected)
				end
			end,
		},
		{
			-- A ball between two shields that face each other goes back and forth for as long as it gets to one (see
			-- shield_to_shield); three times is looked for
			name = "the shield reflects a Shock Rifle ball back and forth",
			run = function (t)
				local order, count = shield_to_shield(t, "charge_shot", false)

				if order then
					t.expect(count >= 3 and string.find(order, "the player, Bardin, the player", 1, true) == 1, "the ball did not go back and forth three times or more, but: %s", order)
				end
			end,
		},
		{
			-- The punch chains to the shield at once (shield_gun.lua's build_punch: action_two from 0 s)
			name = "the shield goes up right after a punch",
			run = function (t)
				local before = shield.last_punch

				t.press("action_one", 0.1)

				local blocked = false

				t.hold("action_two")
				t.watch(0.3, function ()
					local status_extension = ScriptUnit.has_extension(t.unit(), "status_system")

					blocked = blocked or status_extension and status_extension:is_blocking() or false
				end)
				t.release("action_two")

				t.expect(shield.last_punch ~= before, "the quick press did not punch")
				t.expect(blocked, "the shield did not go up within 0.3 s of the punch")
			end,
		},
		{
			-- Let down, the shield doesn't keep the gun from charging and punching
			name = "a punch right after the shield",
			run = function (t)
				t.press("action_two", 0.5)

				local before = shield.last_punch

				t.press("action_one", 1)
				t.wait(0.2)

				t.expect(shield.last_punch ~= before, "the gun did not punch right after the shield was let down")
			end,
		},
		{
			-- The punch hurts what the game's blows of its kind hurt: an armoured enemy (a Chaos warrior) and a monster (a rat ogre). The
			-- charge punches by itself with the enemy in reach.
			name = "a punch hurts armoured enemies and monsters",
			run = function (t)
				for _, breed_name in ipairs({ "chaos_warrior", "skaven_rat_ogre" }) do
					t.go_to_start()

					local enemy = t.spawn(breed_name, 2)

					if t.expect(enemy, "the %s could not be spawned", breed_name) then
						t.wait(1)
						t.aim_at(enemy)

						local damage = t.track_damage(enemy)

						t.press("action_one", 1.5)
						t.wait(0.5)

						t.expect(damage.total > 0, "the punch did not hurt the %s", breed_name)
						t.log("%s: %.1f", breed_name, damage.total)
						t.remove(enemy)
					end
				end
			end,
		},
		{
			-- A punch that hits a wall or the floor, and no enemy or thing, hurts the player as UT's punch of a wall does (ShieldFire:
			-- MinSelfDamage + SelfDamageScale * the damage, halved)
			name = "a full punch at the floor hurts the player as UT's",
			run = function (t)
				t.hurtable(true)
				t.look(FLOOR_PITCH, 0)

				local damage = t.track_damage(t.unit())

				t.press("action_one", FULL_CHARGE_TIME)
				t.wait(0.5)

				local own = 0

				for _, hit in ipairs(damage.hits) do
					if hit.source and string.find(hit.source, "ut_shield_gun", 1, true) then
						own = own + hit.amount
					end
				end

				t.expect(math.abs(own - FULL_SELF_DAMAGE) < 0.5, "the punch at the floor hurt the player %.1f, not %.1f", own, FULL_SELF_DAMAGE)
			end,
		},
		{
			-- Putting the gun away while it charges ends the charge without a punch, and taken out again it charges and punches as before
			name = "switching away while charging doesn't punch",
			run = function (t)
				local before = shield.last_punch

				t.hold("action_one")
				t.wait(1)
				t.on_main_thread(function ()
					ScriptUnit.extension(t.unit(), "inventory_system"):wield("slot_ranged")
				end)
				t.wait(1)
				t.release("action_one")
				t.wait(0.5)

				t.expect(shield.last_punch == before, "the gun punched as it was put away")
				t.expect(shield.charge_started == nil, "the charge went on after the gun was put away")

				t.on_main_thread(function ()
					ScriptUnit.extension(t.unit(), "inventory_system"):wield("slot_melee")
				end)
				t.wait(1.5)
				t.press("action_one", 1)
				t.wait(0.2)

				t.expect(shield.last_punch ~= before, "the gun did not punch after it was taken out again")
			end,
		},
		{
			-- A bot holding it (Bardin, with his own mind, as the game's bots play) fights rats with it: its heavy attack holds the charge
			-- until an enemy is in reach, and its light attack is a quick punch (shield_gun.lua's attack_meta_data). The rats come at the
			-- player, so the bot fights them around the player. It must hurt the rats, punch only with a rat in its reach, and never hurt
			-- the player.
			name = "a bot fights enemies with it",
			run = function (t)
				local gun = ut.items.weapons.shield_gun_dr.key
				local bardin = t.add_bot(SHIELD_BOT_PROFILE, SHIELD_BOT_CAREER, gun, BOT_FIGHT_DISTANCE, "slot_melee", true)

				if not t.expect(bardin, "Bardin could not be added") then
					return
				end

				t.hurtable(true)

				local rats = t.spawn_group("skaven_clan_rat", BOT_FIGHT_RATS, BOT_FIGHT_DISTANCE)
				local damages = {}
				local player_damage = t.track_damage(t.unit())
				-- (how far the nearest living rat was from the bot at each of its punches)
				local punches = {}

				-- (a bot takes no enemy of a group that has no target for its own as a target (PlayerBotBase._target_valid), and the
				-- runner's rats are kept calm with none, so they are let attack)
				t.on_main_thread(function ()
					for _, rat in ipairs(rats) do
						runner.provoke(rat)
					end
				end)

				for i, rat in ipairs(rats) do
					damages[i] = t.track_damage(rat)
				end

				shield.event_callbacks.ut_test_bot = function (owner_unit, event)
					if owner_unit ~= bardin or event ~= shield.events.punch then
						return
					end

					local nearest = math.huge

					for _, rat in ipairs(rats) do
						if HEALTH_ALIVE[rat] then
							nearest = math.min(nearest, Vector3.distance(Unit.local_position(rat, 0), Unit.local_position(bardin, 0)))
						end
					end

					punches[#punches + 1] = nearest
				end

				t.after(function ()
					shield.event_callbacks.ut_test_bot = nil
				end)

				local function from_gun(damage_records)
					local total = 0

					for _, damage in ipairs(damage_records) do
						for _, hit in ipairs(damage.hits) do
							if hit.source == gun then
								total = total + hit.amount
							end
						end
					end

					return total
				end

				t.wait_until(function ()
					return from_gun(damages) > 0
				end, BOT_FIGHT_TIME, "the bot to punch a rat")

				-- (the fight goes on a while longer, for more of its punches)
				t.wait(5)

				local farthest = 0

				for _, distance in ipairs(punches) do
					farthest = math.max(farthest, distance)
				end

				t.log("the bot punched %d times, at most %.1f m from the nearest rat", #punches, farthest)
				t.expect(from_gun(damages) > 0, "the bot did not hurt a rat with the Shield Gun in %d s", BOT_FIGHT_TIME)
				t.expect(farthest <= shield.reach + BOT_REACH_MARGIN, "the bot punched with the nearest rat %.1f m away, out of its reach (%.1f m)", farthest, shield.reach)
				t.expect(from_gun({ player_damage }) == 0, "the bot's punches hurt the player %.1f", from_gun({ player_damage }))
			end,
		},
		{
			-- A punch from less than a third of the charge glances off an enemy's shield: no damage, and the shield stays
			-- (shield_gun.lua's shield_break_share)
			name = "a light punch glances off a shield",
			run = function (t)
				local damage, broken = punch_shield(t, "skaven_clan_rat_with_shield", false)

				if damage then
					t.expect(damage == 0, "the light punch hurt the rat through its shield (%.1f)", damage)
					t.expect(not broken, "the light punch broke the rat's shield")
				end
			end,
		},
		{
			-- A punch charged past a third breaks an enemy's shield
			name = "a charged punch breaks a shield",
			run = function (t)
				local _, broken = punch_shield(t, "skaven_clan_rat_with_shield", true)

				if broken ~= nil then
					t.expect(broken, "the charged punch did not break the rat's shield")
				end
			end,
		},
		{
			-- A shield that can't be broken (a shielded Stormvermin's) stops a charged punch too
			name = "a charged punch glances off a shield that can't be broken",
			run = function (t)
				local damage, broken = punch_shield(t, "skaven_storm_vermin_with_shield", true)

				if damage then
					t.expect(damage == 0, "the charged punch hurt the Stormvermin through its shield (%.1f)", damage)
					t.expect(not broken, "the charged punch broke the Stormvermin's shield")
				end
			end,
		},
		{
			name = "block",
			every_hero = true,
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

local function hero(setting_id, careers)
	local definition = ut.items.weapons[setting_id]

	return { item = definition.key, template = definition.template, careers = careers }
end

-- Each hero has their own Shield Gun, made from a different base weapon. Its charge, punch and block come from that weapon, so those
-- scenarios run for every hero. The others run only for Kruber.
runner.add_suite({
	name = "shield",
	slot = "slot_melee",
	heroes = {
		hero("shield_gun", { "es_mercenary", "es_knight" }),
		hero("shield_gun_dr", { "dr_ironbreaker", "dr_slayer" }),
		hero("shield_gun_bw", { "bw_adept" }),
		hero("shield_gun_wh", { "wh_captain" }),
		hero("shield_gun_we", { "we_shade" }),
	},
	scenarios = scenarios(),
})
