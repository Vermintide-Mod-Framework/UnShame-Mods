local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The Flak Cannon's in-game tests (see runner.lua). Run them with /ut_test flak. They run in the runner's level, Righteous Stand. The
-- numbers expected are UT's (XWeapons/FlakFire, FlakAltFire, FlakChunk and FlakShell) as the mod turns them into this game's.

local runner = mod.test_runner

local definition = ut.items.weapons.flak_cannon

local CONFIG = {
	-- All the ammo, which is all in the clip
	max_ammo = 20,
	-- FlakFire.ProjPerFire, and the chunks a shell throws when it explodes
	chunk_count = 9,
	shell_chunk_count = 6,
	-- FlakFire.FireRate and FlakAltFire.FireRate, and how much sooner a shot may be seen, and how much later a held shot may come
	primary_fire_rate = 0.8947, -- s
	alt_fire_rate = 1.11, -- s
	fire_rate_early = 0.05, -- s
	fire_rate_late = 0.25, -- s
	-- Where the shots start from the player's eye: ahead, to the right and down (FlakFire.ProjSpawnOffset, 25, 5 and -6 in UT units, and
	-- FlakAltFire.ProjSpawnOffset, 25, 9 and -12), with this much either way, and how much two shots may differ
	start_forward = 25 * ut.utils.UT_UNIT, -- m
	chunk_start = { 5 * ut.utils.UT_UNIT, 6 * ut.utils.UT_UNIT }, -- m right, m down
	shell_start = { 9 * ut.utils.UT_UNIT, 12 * ut.utils.UT_UNIT }, -- m right, m down
	start_margin = 0.03, -- m
	start_same = 0.02, -- m
	-- The damage against armour and monsters, of the damage against an enemy with none (a Chaos marauder), with this much either way
	-- (flak_cannon.lua's chunk_armor_attack and shell_armor_attack). A Stormvermin is armoured, a Chaos warrior's body is super armour,
	-- and a rat ogre is a monster and a boss, whose damage the game takes down to 0.45 (DamageUtils.calculate_damage's
	-- boss_damage_reduction). The game also adds damage against a staggered enemy (stagger_damage_multiplier in the difficulty's
	-- settings). The first hit staggers the marauder, so the later ones do more, but it does not stagger a rat ogre: the third value
	-- says that a breed is not staggered.
	plain_breed = "chaos_marauder",
	chunk_armour_breeds = {
		{ "skaven_storm_vermin", 0.7 },
		{ "chaos_warrior", 0.5 },
		{ "skaven_rat_ogre", 1 * 0.45, true },
	},
	shell_armour_breeds = {
		{ "skaven_storm_vermin", 1 },
		{ "chaos_warrior", 0.5 },
		{ "skaven_rat_ogre", 1.5 * 0.45, true },
	},
	armour_margin = 0.1,
	-- The shell's explosion: the enemies beside the one it hits, this far from it (inside the radius of 150 UT units, 3 m, and outside)
	inside_radius = 1.5, -- m
	outside_radius = 3.8, -- m
	-- The most the shell's explosion hurts the player who fired it, and what a chunk that has bounced does to them
	shell_self_damage = 45,
	chunk_self_damage = 8,
	-- The shell's explosion throws the player up at least this fast when it goes off at their feet
	min_jump_speed = 2, -- m/s
	-- The chunks (flak_cannon.lua's chunk_speed, chunk_lifetime and chunk_spread_degrees): their speed and how long they last, with this
	-- much either way, and the cone they go in, which the chunks of a shot at the sky must fill to at least spread_least of it
	chunk_speed = 35, -- m/s
	speed_margin = 3, -- m/s
	chunk_lifetime = 2.7, -- s
	lifetime_margin = 0.25, -- s
	chunk_spread = 4, -- degrees
	spread_margin = 0.5, -- degrees
	spread_least = 0.4,
	-- The shell: its speed and the pull of its gravity (shell_speed and shell_gravity), with this much either way
	shell_speed = 24, -- m/s
	shell_gravity = 17, -- m/s/s
	gravity_margin = 2, -- m/s/s
	-- A critical chunk does at least this much more than a plain one
	crit_least_ratio = 1.2,
	-- An enemy with a shield that can't be broken (a shielded Stormvermin's)
	shield_breed = "skaven_storm_vermin_with_shield",
	-- A shot's view shake (FlakFire.ShakeOffsetMag, 20 UT units, 0.4 m back) reaches at least this far back, and the aim turns by at
	-- most this much, as the sine of its pitch (the Blunderbuss's recoil turned it up 15 degrees, 0.26)
	least_kick = 0.2, -- m
	most_turn = 0.01,
	-- The shell's sphere against walls (flak_cannon.lua's shell_wall_radius)
	shell_wall_radius = 0.2, -- m
	-- The Ironbreaker's talent that staggers the enemies around him when his Gromril Armour is lost (its buff and its explosion have its
	-- name), and the self damage that takes the armour
	gromril_talent = "bardin_ironbreaker_gromril_stagger",
	gromril_self_damage = 5,
}

local function is_chunk(action)
	return action.ut_flak_chunk and not action.ut_flak_burst
end

local function is_burst_chunk(action)
	return action.ut_flak_burst
end

local function is_shell(action)
	return action.ut_flak_shell
end

-- Counts the distinct units that the test has seen so far
local function count(set)
	local total = 0

	for _ in pairs(set) do
		total = total + 1
	end

	return total
end

local function count_names(list, name)
	local total = 0

	for _, value in ipairs(list) do
		if value == name then
			total = total + 1
		end
	end

	return total
end

-- Collects the units of the player's projectiles that a filter accepts, every frame it is called. The ones of an earlier shot that still
-- fly are left out.
local function collector(t, filter, set)
	local earlier = t.on_main_thread(function ()
		local units = {}

		for _, unit in ipairs(t.projectiles(filter)) do
			units[unit] = true
		end

		return units
	end)

	return function ()
		for _, unit in ipairs(t.projectiles(filter)) do
			if not earlier[unit] then
				local z = Vector3.z(Unit.world_position(unit, 0))
				local extension = ScriptUnit.has_extension(unit, "projectile_system")

				set[unit] = set[unit] or {
					first = z,
					top = -math.huge,
				}
				set[unit].top = math.max(set[unit].top, z)
				set[unit].bounced = set[unit].bounced or extension and extension._ut_flak_bounced
			end
		end
	end
end

-- A shell fired at three targets close together, that far ahead, looking that far down. The game's hitscan shotguns run the buffs that
-- trigger on a hit once a shot (and once more for its first head shot), and the shell's hit and its chunks are one shot. Its explosion
-- runs them as the game's explosions do, and is not counted. With hits_enemy the shell hits one of them, so they run at least once.
local function shell_procs(t, distance, pitch, hits_enemy)
	local targets = {}

	for i, side in ipairs({ -0.8, 0, 0.8 }) do
		local ground = t.ground_at(distance, side)

		targets[i] = ground and t.spawn_at(runner.target_breed, ground[1], ground[2], ground[3])
	end

	if not t.expect(targets[1] and targets[2] and targets[3], "the targets could not be spawned") then
		return
	end

	t.wait(1)
	t.look(pitch)

	-- The buffs on attack that run for the player's flak, counted where the game calls them, but not the explosion's
	local procs = {}
	local buff_on_attack = DamageUtils.buff_on_attack

	DamageUtils.buff_on_attack = function (unit, hit_unit, attack_type, is_critical_strike, hit_zone_name, target_number, send_to_server, buff_type, unmodified, damage_source, ...)
		local ran = buff_on_attack(unit, hit_unit, attack_type, is_critical_strike, hit_zone_name, target_number, send_to_server, buff_type, unmodified, damage_source, ...)

		if unit == t.unit() and damage_source == definition.key and attack_type ~= "aoe" and ran ~= false then
			procs[#procs + 1] = string.format("%s %s", tostring(attack_type), tostring(hit_zone_name))
		end

		return ran
	end

	local ok, error_message = pcall(function ()
		t.press("action_two", 0.1)
		t.wait(1.5)
	end)

	DamageUtils.buff_on_attack = buff_on_attack

	if not ok then
		error(error_message, 0)
	end

	local second_is_head = procs[2] and string.find(procs[2], "head", 1, true)

	t.log("the buffs ran %d times for the shell's hit and its chunks (%s)", #procs, table.concat(procs, ", "))
	t.expect(not hits_enemy or #procs >= 1, "the shell hit no enemy")
	t.expect(#procs <= 1 or #procs == 2 and second_is_head, "the buffs ran %d times for one shell (%s)", #procs, table.concat(procs, ", "))
end

-- Watches the player's projectiles that a filter accepts from now on: the ones fired, in order, and where each was every frame. The ones
-- of an earlier shot that still fly are left out.
local function watch_shots(t, filter)
	local seen = {}
	local earlier = t.on_main_thread(function ()
		local units = {}

		for _, unit in ipairs(t.projectiles(filter)) do
			units[unit] = true
		end

		return units
	end)

	return seen, function ()
		for _, unit in ipairs(t.projectiles(filter)) do
			if not seen[unit] and not earlier[unit] then
				seen[unit] = {}
				seen[#seen + 1] = unit
			end

			if seen[unit] then
				local position = Unit.world_position(unit, 0)
				local positions = seen[unit]

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

-- The way the player aims, as { x, y, z }
local function aim_forward(t)
	return t.on_main_thread(function ()
		local forward = Quaternion.forward(ScriptUnit.extension(t.unit(), "first_person_system"):current_rotation())

		return { Vector3.x(forward), Vector3.y(forward), Vector3.z(forward) }
	end)
end

-- When the first of the watched shots was seen
local function first_seen(shots)
	return shots[1] and shots[shots[1]][1].t
end

-- Where the watched shots started, to the right of the eye and below it, on average. Each shot's line is followed back from its first
-- two places to the plane start_forward ahead of the eye, where the cannon spawns it (it may have flown on by the frame it is seen).
local function start_offset(shots, eye)
	local position, forward, right, up = eye.position:unbox(), eye.forward:unbox(), eye.right:unbox(), eye.up:unbox()
	local total_right, total_down, total = 0, 0, 0

	for _, unit in ipairs(shots) do
		local positions = shots[unit]
		local first = positions[1] and Vector3(positions[1].x, positions[1].y, positions[1].z)

		for i = 2, #positions do
			local next_position = Vector3(positions[i].x, positions[i].y, positions[i].z)
			local step = next_position - first
			local ahead = Vector3.dot(step, forward)

			if ahead > 0.01 then
				local start = first + step * ((CONFIG.start_forward - Vector3.dot(first - position, forward)) / ahead)

				total_right = total_right + Vector3.dot(start - position, right)
				total_down = total_down - Vector3.dot(start - position, up)
				total = total + 1

				break
			end
		end
	end

	return total > 0 and { total_right / total, total_down / total } or nil
end

-- The damage in a record of t.track_damage from the shell's explosion: its largest hit of the explosion's damage types, grenade and
-- grenade_glance (utils.make_flat). The shell's own hit is a grenade hit too, of about 1 (flak_cannon.lua's damage profiles).
local function explosion_damage(record)
	local largest = 0

	for _, hit in ipairs(record.hits) do
		if hit.type == "grenade" or hit.type == "grenade_glance" then
			largest = math.max(largest, hit.amount)
		end
	end

	return largest
end

-- The least damage one chunk did in a record of t.track_damage, or nil
local function chunk_damage(record)
	local least

	for _, hit in ipairs(record.hits) do
		if hit.type == "shot_shotgun" then
			least = math.min(least or math.huge, hit.amount)
		end
	end

	return least
end

-- Aims at the feet of an enemy: a shell aimed there is lobbed into its body
local function aim_at_feet(t, unit)
	local feet = t.on_main_thread(function ()
		local position = Unit.local_position(unit, 0)

		return { Vector3.x(position), Vector3.y(position), Vector3.z(position) }
	end)

	t.aim_at_point(unpack(feet))
end

-- The least damage of two shots at an enemy of the breed 5 m ahead, each at a new one (the least, as a shot can be a critical hit): of
-- one chunk, or of the shell's explosion
local function armour_damage(t, breed_name, shell)
	local least

	for _ = 1, 2 do
		t.go_to_start()

		local enemy = t.spawn(breed_name, 5)

		if not t.expect(enemy, "the %s could not be spawned", breed_name) then
			return nil
		end

		t.wait(1)

		if shell then
			aim_at_feet(t, enemy)
		else
			t.aim_at(enemy)
		end

		local damage = t.track_damage(enemy)

		t.press(shell and "action_two" or "action_one", 0.05)
		t.wait(1)
		t.remove(enemy)

		local amount

		if shell then
			amount = explosion_damage(damage)
		else
			amount = chunk_damage(damage)
		end

		if amount and amount > 0 then
			least = math.min(least or math.huge, amount)
		end
	end

	return least
end

-- Checks that chunks or shells do the armour's share of their damage against an enemy with none, for each breed
local function check_armour(t, shell, breeds)
	local what = shell and "the shell's explosion" or "a chunk"
	local plain = armour_damage(t, CONFIG.plain_breed, shell)

	if not t.expect(plain, "%s did not hurt the %s", what, CONFIG.plain_breed) then
		return
	end

	local stagger_bonus = t.on_main_thread(function ()
		return DifficultySettings[Managers.state.difficulty:get_difficulty()].stagger_damage_multiplier or 0
	end)

	for _, entry in ipairs(breeds) do
		local breed_name, share, not_staggered = entry[1], entry[2], entry[3]
		local damage = armour_damage(t, breed_name, shell)

		if not_staggered then
			share = share / (1 + stagger_bonus)
		end

		if t.expect(damage, "%s did not hurt the %s", what, breed_name) then
			t.log("%s, %s: %.1f, %.2f of the marauder's %.1f", what, breed_name, damage, damage / plain, plain)
			t.expect(math.abs(damage / plain - share) <= CONFIG.armour_margin, "%s did %.2f of its damage to the %s, not %.2f", what, damage / plain, breed_name, share)
		end
	end
end

local function scenarios()
	return {
		{
			name = "all the ammo is in the clip",
			every_hero = true,
			run = function (t)
				local ammo = t.on_main_thread(function ()
					local inventory_extension = ScriptUnit.extension(t.unit(), "inventory_system")
					local slot_data = inventory_extension:get_slot_data("slot_ranged")
					local ammo_extension = GearUtils.get_ammo_extension(slot_data.right_unit_1p, slot_data.left_unit_1p)

					return { ammo_extension:ammo_count(), ammo_extension:total_remaining_ammo() }
				end)
				local clip, total = ammo[1], ammo[2]

				t.expect(total >= CONFIG.max_ammo, "the cannon holds %s, less than %d", tostring(total), CONFIG.max_ammo)
				t.expect(clip == total, "%s of the %s are in the clip: there is a reload", tostring(clip), tostring(total))
			end,
		},
		{
			name = "primary fire throws nine chunks for one ammo",
			every_hero = true,
			basic = true,
			run = function (t)
				local before = t.ammo()
				local chunks = {}
				local observe = collector(t, is_chunk, chunks)

				t.press("action_one", 0.1, observe)
				t.watch(0.5, observe)

				t.expect(count(chunks) == CONFIG.chunk_count, "%d chunks were fired, not %d", count(chunks), CONFIG.chunk_count)
				t.expect(before - (t.ammo() or 0) == 1, "the shot used %s ammo, not 1", tostring(before - (t.ammo() or 0)))
			end,
		},
		{
			name = "holding primary fire repeats it at its fire rate",
			run = function (t)
				local before = t.ammo()

				-- (shots at 0, 0.89 and 1.79 s)
				t.press("action_one", 2)
				t.wait(0.3)

				t.expect(before - (t.ammo() or 0) == 3, "%s shots in 2 s, not 3", tostring(before - (t.ammo() or 0)))
			end,
		},
		{
			name = "chunks hurt an enemy",
			run = function (t)
				local target = t.spawn_target(5)

				if not t.expect(target, "the target could not be spawned") then
					return
				end

				local damage = t.track_damage(target)

				t.press("action_one", 0.1)
				t.wait(1)

				t.expect(damage.total > 0, "the target was not hurt")
			end,
		},
		{
			name = "chunks bounce off the ground",
			run = function (t)
				local chunks = {}
				local observe = collector(t, is_chunk, chunks)

				-- (the ground about 3 m ahead)
				t.look(-30)
				t.press("action_one", 0.1, observe)
				t.watch(0.6, observe)

				local bounced = 0

				for _, chunk in pairs(chunks) do
					if chunk.bounced then
						bounced = bounced + 1
					end
				end

				-- (every chunk has at least the two extra bounces)
				t.expect(bounced == count(chunks) and bounced > 0, "%d of %d chunks bounced", bounced, count(chunks))
			end,
		},
		{
			name = "a shell is lobbed, explodes, and throws chunks",
			every_hero = true,
			run = function (t)
				t.look(0)

				local before = t.ammo()
				local explosions = t.explosions()
				local shells = {}
				local burst = {}
				local observe_shells = collector(t, is_shell, shells)
				local observe_burst = collector(t, is_burst_chunk, burst)
				local function observe()
					observe_shells()
					observe_burst()
				end

				t.press("action_two", 0.1, observe)
				t.wait_until(function ()
					observe()

					return count_names(explosions, "ut_flak_shell_explosion") > 0
				end, 6, "the shell to explode")
				t.watch(0.2, observe)

				local shell = next(shells) and shells[next(shells)]

				t.expect(count(shells) == 1, "%d shells were fired, not 1", count(shells))
				t.expect(shell and shell.top > shell.first + 0.2, "the shell did not rise: it was not lobbed")
				t.expect(count_names(explosions, "ut_flak_shell_explosion") == 1, "the shell made %d explosions, not 1", count_names(explosions, "ut_flak_shell_explosion"))
				t.expect(count(burst) == CONFIG.shell_chunk_count, "the shell threw %d chunks, not %d", count(burst), CONFIG.shell_chunk_count)
				t.expect(before - (t.ammo() or 0) == 1, "the shell used %s ammo, not 1", tostring(before - (t.ammo() or 0)))
			end,
		},
		{
			name = "a shell hurts an enemy",
			run = function (t)
				local target = t.spawn_target(6)

				if not t.expect(target, "the target could not be spawned") then
					return
				end

				local damage = t.track_damage(target)

				t.press("action_two", 0.1)
				t.wait(1.5)

				t.expect(damage.total > 0, "the target was not hurt")
			end,
		},
		{
			name = "a shell at the feet hurts the player and throws them up",
			run = function (t)
				t.hurtable(true)
				t.look(-85)

				local up = 0
				local taken = t.track_damage(t.unit())

				t.press("action_two", 0.05)
				t.watch(0.5, function ()
					local _, _, z = t.velocity()

					up = math.max(up, z)
				end)

				-- The explosion's hurt is the first. The chunks it throws bounce off the floor at the player's feet and hit them too,
				-- as UT's FlakChunk hits its shooter once it falls.
				local blast = taken.hits[1]

				t.expect(blast, "the shell's explosion did not hurt the player")
				t.expect(not blast or blast.amount <= CONFIG.shell_self_damage + 0.5, "the shell's explosion hurt the player %.1f, more than %d", blast and blast.amount or 0, CONFIG.shell_self_damage)

				for i = 2, #taken.hits do
					t.expect(math.abs(taken.hits[i].amount - CONFIG.chunk_self_damage) < 0.5, "a chunk hurt the player %.1f, not %d", taken.hits[i].amount, CONFIG.chunk_self_damage)
				end
				t.expect(up >= CONFIG.min_jump_speed, "the shell threw the player up at %.1f m/s at most", up)
			end,
		},
		{
			name = "with no ammo left nothing is fired",
			run = function (t)
				t.on_main_thread(function ()
					local inventory_extension = ScriptUnit.extension(t.unit(), "inventory_system")
					local slot_data = inventory_extension:get_slot_data("slot_ranged")
					local ammo_extension = GearUtils.get_ammo_extension(slot_data.right_unit_1p, slot_data.left_unit_1p)

					ammo_extension:use_ammo(ammo_extension:ammo_count() - 1)
				end)
				t.wait(0.2)

				t.expect(t.ammo() == 1, "%s left, not 1", tostring(t.ammo()))

				local last = {}

				t.press("action_one", 0.1, collector(t, is_chunk, last))
				t.wait(1)
				t.expect(count(last) == CONFIG.chunk_count, "the last shot threw %d chunks, not %d", count(last), CONFIG.chunk_count)
				t.expect(t.ammo() == 0, "%s left after the last shot, not 0", tostring(t.ammo()))

				local chunks = {}
				local observe = collector(t, is_chunk, chunks)

				t.wait(1)
				t.press("action_one", 0.1, observe)
				t.watch(0.5, observe)
				t.press("action_two", 0.1, observe)
				t.watch(0.5, observe)

				t.expect(count(chunks) == 0, "%d chunks were fired with no ammo", count(chunks))
			end,
		},
		{
			name = "a shell that lands among enemies procs at most once",
			run = function (t)
				-- (the shell lands on the ground in front of them, 6 m ahead, and they stand in its explosion)
				shell_procs(t, 8, -15.8)
			end,
		},
		{
			name = "a shell that hits an enemy procs once",
			run = function (t)
				-- (aimed at the feet of the middle one 5 m ahead: the lob puts the shell in its body)
				shell_procs(t, 5, -19, true)
			end,
		},
		{
			-- Either mode waits for the fire rate of the last shot, and a held button fires as soon as it may
			name = "a shell waits for the chunks' fire rate, and chunks for the shell's",
			run = function (t)
				t.look(20)

				for _, order in ipairs({
					{ "action_one", is_chunk, "action_two", is_shell, CONFIG.primary_fire_rate, "the shell", "the chunks" },
					{ "action_two", is_shell, "action_one", is_chunk, CONFIG.alt_fire_rate, "the chunks", "the shell" },
				}) do
					local first_button, first_filter, second_button, second_filter, rate, second_name, first_name = unpack(order)
					local first, observe_first = watch_shots(t, first_filter)
					local second, observe_second = watch_shots(t, second_filter)
					local function observe()
						observe_first()
						observe_second()
					end

					t.press(first_button, 0.05, observe)
					t.press(second_button, rate + 0.3, observe)
					t.watch(0.2, observe)

					local first_t, second_t = first_seen(first), first_seen(second)

					if t.expect(first_t and second_t, "%s or %s were not fired", first_name, second_name) then
						t.expect(second_t - first_t >= rate - CONFIG.fire_rate_early, "%s left %.2f s after %s, before its %.2f s", second_name, second_t - first_t, first_name, rate)
						t.expect(second_t - first_t <= rate + CONFIG.fire_rate_late, "%s left %.2f s after %s, not soon after its %.2f s", second_name, second_t - first_t, first_name, rate)
					end

					t.wait(CONFIG.alt_fire_rate)
				end
			end,
		},
		{
			-- The chunks and the shell start ProjSpawnOffset from the eye, and two shots start in the same place
			name = "chunks and the shell start to the right of the eye and below it, in the same place each time",
			run = function (t)
				for _, kind in ipairs({
					{ "action_one", is_chunk, CONFIG.chunk_start, "the chunks", CONFIG.primary_fire_rate },
					{ "action_two", is_shell, CONFIG.shell_start, "the shell", CONFIG.alt_fire_rate },
				}) do
					local button, filter, expected, name, rate = unpack(kind)
					local starts = {}

					for i = 1, 2 do
						t.look(0)

						local eye = t.on_main_thread(function ()
							local first_person_extension = ScriptUnit.extension(t.unit(), "first_person_system")
							local rotation = first_person_extension:current_rotation()

							return {
								position = Vector3Box(first_person_extension:current_position()),
								forward = Vector3Box(Quaternion.forward(rotation)),
								right = Vector3Box(Quaternion.right(rotation)),
								up = Vector3Box(Quaternion.up(rotation)),
							}
						end)
						local shots, observe = watch_shots(t, filter)

						t.press(button, 0.05, observe)
						t.watch(0.15, observe)

						starts[i] = start_offset(shots, eye)

						if not t.expect(starts[i], "%s of shot %d were not seen flying", name, i) then
							return
						end

						t.log("%s of shot %d: %.3f m right, %.3f m down", name, i, starts[i][1], starts[i][2])
						t.wait(rate)
					end

					for i, start in ipairs(starts) do
						t.expect(math.abs(start[1] - expected[1]) <= CONFIG.start_margin, "%s of shot %d started %.2f m to the right of the eye, not %.2f", name, i, start[1], expected[1])
						t.expect(math.abs(start[2] - expected[2]) <= CONFIG.start_margin, "%s of shot %d started %.2f m below the eye, not %.2f", name, i, start[2], expected[2])
					end

					t.expect(math.abs(starts[1][1] - starts[2][1]) <= CONFIG.start_same and math.abs(starts[1][2] - starts[2][2]) <= CONFIG.start_same, "%s of the two shots started in different places", name)
				end
			end,
		},
		{
			name = "chunks hurt armoured enemies and monsters by their armour",
			run = function (t)
				check_armour(t, false, CONFIG.chunk_armour_breeds)
			end,
		},
		{
			name = "a shell's explosion hurts armoured enemies and monsters by their armour",
			run = function (t)
				check_armour(t, true, CONFIG.shell_armour_breeds)
			end,
		},
		{
			-- A shell goes off on the enemy it hits, and its explosion hurts the enemies around as far as its radius, less the farther they
			-- are, and none past it (the chunks it throws can hit them too, and are not counted)
			name = "a shell's explosion falls off to its radius",
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
				aim_at_feet(t, hit)

				local damages = { t.track_damage(hit), t.track_damage(inside), t.track_damage(outside) }

				t.press("action_two", 0.05)
				t.wait(1.5)

				local on_hit, near, far = explosion_damage(damages[1]), explosion_damage(damages[2]), explosion_damage(damages[3])

				t.log("the one hit %.1f, %.1f m from it %.1f, %.1f m from it %.1f", on_hit, CONFIG.inside_radius, near, CONFIG.outside_radius, far)
				t.expect(on_hit > 0, "the explosion did not hurt the enemy the shell hit")
				t.expect(near > 0, "the explosion did not hurt the enemy %.1f m from it, inside its radius", CONFIG.inside_radius)
				t.expect(near < on_hit, "the enemy %.1f m from the explosion took as much as the one it hit (%.1f, %.1f)", CONFIG.inside_radius, near, on_hit)
				t.expect(far == 0, "the explosion hurt the enemy %.1f m from it, past its radius (%.1f)", CONFIG.outside_radius, far)
			end,
		},
		{
			-- Chunks fired at the sky fly at their speed, straight, for their lifetime, each within the cone of the spread
			name = "chunks fly at their speed for their lifetime, within their spread",
			run = function (t)
				t.look(60)

				local forward = aim_forward(t)
				local shots, observe = watch_shots(t, is_chunk)

				t.press("action_one", 0.05, observe)
				t.watch(CONFIG.chunk_lifetime + 1, observe)

				local speeds, lifetimes, widest = {}, {}, 0

				for _, unit in ipairs(shots) do
					local positions = shots[unit]
					local first, second, last = positions[1], positions[2], positions[#positions]

					if second and second.t > first.t then
						local dx, dy, dz = second.x - first.x, second.y - first.y, second.z - first.z
						local length = math.sqrt(dx * dx + dy * dy + dz * dz)

						speeds[#speeds + 1] = length / (second.t - first.t)
						lifetimes[#lifetimes + 1] = last.t - first.t

						local cosine = (dx * forward[1] + dy * forward[2] + dz * forward[3]) / length

						widest = math.max(widest, math.deg(math.acos(math.min(1, cosine))))
					end
				end

				if not t.expect(#speeds == CONFIG.chunk_count, "%d of the %d chunks were seen flying", #speeds, CONFIG.chunk_count) then
					return
				end

				for i, speed in ipairs(speeds) do
					t.log("chunk %d: %.1f m/s, %.2f s, ", i, speed, lifetimes[i])
					t.expect(math.abs(speed - CONFIG.chunk_speed) <= CONFIG.speed_margin, "a chunk flew at %.1f m/s, not %.1f", speed, CONFIG.chunk_speed)
					t.expect(math.abs(lifetimes[i] - CONFIG.chunk_lifetime) <= CONFIG.lifetime_margin, "a chunk lasted %.2f s, not %.2f", lifetimes[i], CONFIG.chunk_lifetime)
				end

				t.log("the widest chunk went %.1f degrees off the aim", widest)
				t.expect(widest <= CONFIG.chunk_spread + CONFIG.spread_margin, "a chunk went %.1f degrees off the aim, past the spread of %.1f", widest, CONFIG.chunk_spread)
				t.expect(widest >= CONFIG.chunk_spread * CONFIG.spread_least, "the chunks went at most %.1f degrees off the aim, much less than the spread of %.1f", widest, CONFIG.chunk_spread)
			end,
		},
		{
			-- The shell leaves at its speed and falls by its gravity
			name = "the shell flies at its speed and falls by its gravity",
			run = function (t)
				t.look(20)

				local shots, observe = watch_shots(t, is_shell)

				t.press("action_two", 0.05, observe)
				t.watch(0.8, observe)

				local positions = shots[1] and shots[shots[1]]

				if not t.expect(positions and #positions >= 6, "the shell was not seen flying") then
					return
				end

				local function velocity(a, b)
					local dt = b.t - a.t

					return (b.x - a.x) / dt, (b.y - a.y) / dt, (b.z - a.z) / dt, (a.t + b.t) / 2
				end

				local vx, vy, vz, early = velocity(positions[1], positions[2])
				local _, _, late_vz, late = velocity(positions[#positions - 1], positions[#positions])
				local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
				local gravity = (vz - late_vz) / (late - early)

				t.log("the shell left at %.1f m/s and fell by %.1f m/s/s", speed, gravity)
				t.expect(math.abs(speed - CONFIG.shell_speed) <= CONFIG.speed_margin, "the shell left at %.1f m/s, not %.1f", speed, CONFIG.shell_speed)
				t.expect(math.abs(gravity - CONFIG.shell_gravity) <= CONFIG.gravity_margin, "the shell fell by %.1f m/s/s, not %.1f", gravity, CONFIG.shell_gravity)
			end,
		},
		{
			-- An enemy's raised shield stops the chunks, as it stops the game's shots
			name = "a raised shield stops the chunks",
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
				t.wait(1)

				t.expect(damage.total == 0, "the chunks hurt the %s through its shield (%.1f)", CONFIG.shield_breed, damage.total)
			end,
		},
		{
			-- A critical chunk does more damage than a plain one
			name = "a critical chunk does more damage",
			run = function (t)
				t.critical_hits(false)

				local plain = armour_damage(t, CONFIG.plain_breed, false)

				t.critical_hits(true)

				local critical = armour_damage(t, CONFIG.plain_breed, false)

				if t.expect(plain and critical, "a chunk did not hurt the %s", CONFIG.plain_breed) then
					t.log("plain %.1f, critical %.1f", plain, critical)
					t.expect(critical > plain * CONFIG.crit_least_ratio, "a critical chunk did %.1f, not more than the plain %.1f", critical, plain)
				end
			end,
		},
		{
			-- The cannon can be put away right after a shot, and nothing is fired after it
			name = "the cannon can be put away right after a shot",
			run = function (t)
				local template = t.wielded()
				local before = t.ammo()

				t.press("action_one", 0.05)
				t.tap("wield_1")
				t.hold("action_one")
				t.wait(CONFIG.primary_fire_rate * 2)
				t.release("action_one")

				t.expect(t.wielded() ~= template, "the cannon is still in the hands (%s)", tostring(t.wielded()))
				t.expect(before - (t.ammo() or before) <= 1, "%d shots were fired, not 1", before - (t.ammo() or before))

				t.tap("wield_2")
				t.wait(1.5)
			end,
		},
		{
			-- FlakFire's view shake: the view jumps back (ShakeOffsetMag 20 units along it) and does not turn (ShakeRotMag is 0), so the
			-- base's recoil, which turns the aim up, is off
			name = "a shot kicks the view back, as UT's, and does not turn the aim",
			run = function (t)
				local start_up = t.on_main_thread(function ()
					return Vector3.z(Quaternion.forward(ScriptUnit.extension(t.unit(), "first_person_system"):current_rotation()))
				end)
				local back, turned = 0, 0

				t.press("action_one", 0.05, function ()
					local up = Vector3.z(Quaternion.forward(ScriptUnit.extension(t.unit(), "first_person_system"):current_rotation()))

					back = math.min(back, Vector3.y(ut.view_shake.offset()))
					turned = math.max(turned, math.abs(up - start_up))
				end)
				t.watch(0.5, function ()
					local up = Vector3.z(Quaternion.forward(ScriptUnit.extension(t.unit(), "first_person_system"):current_rotation()))

					back = math.min(back, Vector3.y(ut.view_shake.offset()))
					turned = math.max(turned, math.abs(up - start_up))
				end)

				t.log("the view went %.2f m back, and the aim turned %.3f", -back, turned)
				t.expect(back <= -CONFIG.least_kick, "the view went %.2f m back, not at least %.2f", -back, CONFIG.least_kick)
				t.expect(turned <= CONFIG.most_turn, "the aim turned %.3f (the sine of its pitch)", turned)
			end,
		},
		{
			-- The shell hits an enemy as a rocket does (utils.UT_PROJECTILE_RADIUS) and a wall with its own sphere (ut_wall_radius,
			-- hooks.lua), which the game sweeps with these numbers
			name = "the shell's sphere is UT's against enemies and its own against walls",
			run = function (t)
				t.look(20)

				local found

				t.press("action_two", 0.05, function ()
					found = found or t.projectiles(is_shell)[1]
				end)
				t.watch(0.2, function ()
					found = found or t.projectiles(is_shell)[1]
				end)

				if not t.expect(found, "no shell flew") then
					return
				end

				local sizes = t.on_main_thread(function ()
					local impact_extension = Unit.alive(found) and ScriptUnit.has_extension(found, "projectile_impact_system")
					local projectile = Unit.alive(found) and ScriptUnit.has_extension(found, "projectile_system")
					local projectile_info = projectile and projectile._current_action.projectile_info

					return impact_extension and projectile_info and {
						radius = impact_extension.radius,
						static_impact_type = impact_extension.static_impact_type,
						wall = projectile_info.ut_wall_radius,
					}
				end)

				if t.expect(sizes, "the shell was gone before it was looked at") then
					t.log("enemies %.2f m, walls %s %.2f m", sizes.radius, tostring(sizes.static_impact_type), sizes.wall or -1)
					t.expect(math.abs(sizes.radius - ut.utils.UT_PROJECTILE_RADIUS) < 0.001, "the shell's sphere against enemies is %.2f m, not %.2f", sizes.radius, ut.utils.UT_PROJECTILE_RADIUS)
					t.expect(sizes.static_impact_type == "sphere_sweep" and sizes.wall == CONFIG.shell_wall_radius, "the shell is swept against walls by %s %s, not a sphere of %.2f m", tostring(sizes.static_impact_type), tostring(sizes.wall), CONFIG.shell_wall_radius)
				end
			end,
		},
		{
			-- The player's own damage can set off their buffs. The Ironbreaker's talent that staggers the enemies around him when his
			-- Gromril Armour is lost makes an explosion at his position, which the game has not yet made current in the mod's update, where
			-- the weapons' self damage is done (utils.apply_self_damage, with_valid_positions).
			name = "self damage that takes the Gromril Armour sets off its talent's explosion",
			every_hero = true,
			run = function (t)
				if Managers.player:local_player():career_name() ~= "dr_ironbreaker" then
					t.skip("only the Ironbreaker has Gromril Armour")
				end

				local explosions = t.explosions()

				t.hurtable(true)

				local result = t.on_main_thread(function ()
					local unit = t.unit()
					local buff_extension = ScriptUnit.extension(unit, "buff_system")
					local talent_id

					if not buff_extension:has_buff_type("bardin_ironbreaker_gromril_armour") then
						buff_extension:add_buff("bardin_ironbreaker_gromril_armour")
					end

					if not buff_extension:has_buff_type(CONFIG.gromril_talent) then
						talent_id = buff_extension:add_buff(CONFIG.gromril_talent)
					end

					local had_armour = buff_extension:has_buff_type("bardin_ironbreaker_gromril_armour")

					-- (the mod's update, as the weapons' self damage)
					ut.utils.apply_self_damage(unit, Unit.world_position(unit, 0), Vector3.up(), ut.items.weapons.flak_cannon_dr.key, CONFIG.gromril_self_damage)

					return {
						had_armour = had_armour,
						has_armour = buff_extension:has_buff_type("bardin_ironbreaker_gromril_armour"),
						talent_id = talent_id,
					}
				end)

				if result.talent_id then
					t.after(function ()
						local buff_extension = ScriptUnit.has_extension(t.unit(), "buff_system")

						if buff_extension then
							buff_extension:remove_buff(result.talent_id)
						end
					end)
				end

				t.wait(0.5)

				t.expect(result.had_armour, "the Gromril Armour could not be given")
				t.expect(not result.has_armour, "the self damage did not take the Gromril Armour")
				t.expect(count_names(explosions, CONFIG.gromril_talent) >= 1, "the talent made no explosion (%s)", table.concat(explosions, ", "))
			end,
		},
	}
end

local function hero(setting_id, careers)
	local hero_definition = ut.items.weapons[setting_id]

	return { item = hero_definition.key, template = hero_definition.template, careers = careers }
end

-- Bardin's copy is on the Grudge-raker and shares the rest, so his careers run what the copy takes from its base: the ammo and the shots.
-- The Ironbreaker also runs the self damage that takes his Gromril Armour.
runner.add_suite({
	name = "flak",
	slot = "slot_ranged",
	heroes = {
		hero("flak_cannon", { "es_mercenary", "es_huntsman", "es_knight" }),
		hero("flak_cannon_dr", { "dr_ironbreaker", "dr_ranger", "dr_engineer" }),
	},
	scenarios = scenarios(),
})

-- Bots with the Flak Cannon (flak/bots.lua). Only Kruber's and Bardin's careers have it, and a hero can't be a bot and the player at
-- once, so these run in a suite of their own with the player as Sienna, and the bot is Kruber as a Mercenary, with his own mind. The places are the Shock
-- Rifle's bot tests' (shock.lua): a special ahead that shoots at the player, past the player in the bot's way, and a boss where bots can't
-- walk to.
local BOTS = {
	profile = "empire_soldier",
	career = 1,
	behind = -3, -- m
	special = "skaven_ratling_gunner",
	special_distance = 14, -- m
	boss = "skaven_rat_ogre",
	players_ahead = 2, -- m
	players_right = 2, -- m
	bot_distance = 2, -- m
	-- How long the bot has to hurt the special or the boss
	fight_time = 30, -- s
}

-- The damage from the Flak Cannon in a record of t.track_damage
local function from_flak(record)
	local total = 0

	for _, hit in ipairs(record.hits) do
		if hit.source == definition.key then
			total = total + hit.amount
		end
	end

	return total
end

local function bot_scenarios()
	return {
		{
			-- The bot shoots the special with the chunks, past the player in its way, and never hurts the player
			name = "a bot shoots enemies with it",
			run = function (t)
				t.hurtable(true)

				local special = t.spawn(BOTS.special, BOTS.special_distance)

				if not t.expect(special, "the %s could not be spawned", BOTS.special) then
					return
				end

				-- (a bot shoots a special only once it has been seen, which a calm one never is: shooting at the player makes it seen)
				t.on_main_thread(function ()
					runner.provoke(special)
				end)

				local damage = t.track_damage(special)
				local player_damage = t.track_damage(t.unit())

				if not t.expect(t.add_bot(BOTS.profile, BOTS.career, definition.key, BOTS.behind, nil, true), "the bot could not be added") then
					return
				end

				t.wait_until(function ()
					return from_flak(damage) > 0
				end, BOTS.fight_time, "the bot to hurt the special")
				t.wait(5)

				t.expect(from_flak(damage) > 0, "the bot did not hurt the %s with the Flak Cannon in %d s", BOTS.special, BOTS.fight_time)
				t.expect(from_flak(player_damage) == 0, "the bot's shots hurt the player %.1f", from_flak(player_damage))
			end,
		},
		{
			-- The bot fires shells at a boss it can't reach (bots.lua: a boss is worth a shell), and hurts it
			name = "a bot fires shells at a boss it can't reach",
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

				-- (a bot goes for a boss only once it has been seen, see shock.lua)
				t.on_main_thread(function ()
					ScriptUnit.extension(boss, "proximity_system").has_been_seen = true
				end)

				local damage = t.track_damage(boss)
				local explosions = t.explosions()

				if not t.expect(t.add_bot(BOTS.profile, BOTS.career, definition.key, BOTS.bot_distance, nil, true), "the bot could not be added") then
					return
				end

				t.wait_until(function ()
					return count_names(explosions, "ut_flak_shell_explosion") > 0 and from_flak(damage) > 0
				end, BOTS.fight_time, "the bot to fire a shell and hurt the boss")

				t.expect(count_names(explosions, "ut_flak_shell_explosion") > 0, "the bot fired no shell in %d s", BOTS.fight_time)
				t.expect(from_flak(damage) > 0, "the bot did not hurt the %s with the Flak Cannon in %d s", BOTS.boss, BOTS.fight_time)
			end,
		},
	}
end

local shock_rifle = ut.items.weapons.shock_rifle

runner.add_suite({
	name = "flak_bots",
	item = shock_rifle.key,
	template = shock_rifle.template,
	slot = "slot_ranged",
	careers = { "bw_adept" },
	scenarios = bot_scenarios(),
})
