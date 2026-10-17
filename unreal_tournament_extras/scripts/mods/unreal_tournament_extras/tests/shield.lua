local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The Shield Gun's in-game tests (see runner.lua). Run them with /ut_test shield (Kruber's), shield_dr, shield_bw, shield_wh and
-- shield_we. They run in the runner's level, Righteous Stand.

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

local function scenarios()
	return {
		{
			name = "charge and punch",
			every_hero = true,
			run =function (t)
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
			name = "block",
			every_hero = true,
			run =function (t)
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

-- Each hero has their own Shield Gun, made from a different base weapon. Its charge, punch and block come from that weapon, so those
-- scenarios run for every hero, as one career of theirs. The others run only for Kruber.
local function every_hero_scenarios()
	local kept = {}

	for _, scenario in ipairs(scenarios()) do
		if scenario.every_hero then
			kept[#kept + 1] = scenario
		end
	end

	return kept
end

for _, variant in ipairs({
	{ name = "shield", setting_id = "shield_gun", career = "es_mercenary", scenarios = scenarios() },
	{ name = "shield_dr", setting_id = "shield_gun_dr", career = "dr_ironbreaker", scenarios = every_hero_scenarios() },
	{ name = "shield_bw", setting_id = "shield_gun_bw", career = "bw_adept", scenarios = every_hero_scenarios() },
	{ name = "shield_wh", setting_id = "shield_gun_wh", career = "wh_captain", scenarios = every_hero_scenarios() },
	{ name = "shield_we", setting_id = "shield_gun_we", career = "we_shade", scenarios = every_hero_scenarios() },
}) do
	local definition = ut.items.weapons[variant.setting_id]

	runner.add_suite({
		name = variant.name,
		item = definition.key,
		template = definition.template,
		slot = "slot_melee",
		careers = { variant.career },
		scenarios = variant.scenarios,
	})
end
