local mod = get_mod("unreal_tournament")

-- The Flak Cannon's in-game tests (see runner.lua). Run them with /ut_test flak. They run in the runner's level, Righteous Stand. The
-- numbers expected are UT's (XWeapons/FlakFire, FlakAltFire, FlakChunk and FlakShell) as the mod turns them into this game's.

local runner = mod.test_runner

local definition = mod.items.weapons.flak_cannon

local CONFIG = {
	-- All the ammo, which is all in the clip
	max_ammo = 20,
	-- FlakFire.ProjPerFire, and the chunks a shell throws when it explodes
	chunk_count = 9,
	shell_chunk_count = 6,
	-- FlakFire.FireRate
	primary_fire_rate = 0.8947, -- s
	-- The most the shell's explosion hurts the player who fired it, and what a chunk that has bounced does to them
	shell_self_damage = 45,
	chunk_self_damage = 8,
	-- The shell's explosion throws the player up at least this fast when it goes off at their feet
	min_jump_speed = 2, -- m/s
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
-- trigger on a hit once a shot (and once more for its first head shot), and the shell, its explosion and its chunks are one shot.
local function shell_procs(t, distance, pitch)
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

	-- The buffs on attack that run for the player's flak, counted where the game calls them
	local procs = {}
	local buff_on_attack = DamageUtils.buff_on_attack

	DamageUtils.buff_on_attack = function (unit, hit_unit, attack_type, is_critical_strike, hit_zone_name, target_number, send_to_server, buff_type, unmodified, damage_source, ...)
		local ran = buff_on_attack(unit, hit_unit, attack_type, is_critical_strike, hit_zone_name, target_number, send_to_server, buff_type, unmodified, damage_source, ...)

		if unit == t.unit() and damage_source == definition.key and ran ~= false then
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

	t.expect(#procs >= 1, "the shell hit nothing")
	t.expect(#procs <= 1 or #procs == 2 and second_is_head, "the buffs ran %d times for one shell (%s)", #procs, table.concat(procs, ", "))
end

local function scenarios()
	return {
		{
			name = "all the ammo is in the clip",
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
			name = "a shell that lands among enemies procs once",
			run = function (t)
				-- (the shell lands on the ground in front of them, 6 m ahead, and they stand in its explosion)
				shell_procs(t, 8, -15.8)
			end,
		},
		{
			name = "a shell that hits an enemy procs once",
			run = function (t)
				-- (aimed at the feet of the middle one 5 m ahead: the lob puts the shell in its body)
				shell_procs(t, 5, -19)
			end,
		},
	}
end

runner.add_suite({
	name = "flak",
	item = definition.key,
	template = definition.template,
	slot = "slot_ranged",
	careers = { "es_mercenary" },
	scenarios = scenarios(),
})
