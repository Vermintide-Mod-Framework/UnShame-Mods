local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The Link Gun's in-game tests (see runner.lua), for every hero's copy. Run them with /ut_test link. They run in the runner's
-- level, Righteous Stand. The numbers expected are UT's (XWeapons/LinkGun, LinkAltFire, LinkProjectile and LinkFire) as the mod turns them
-- into this game's (link/link_gun.lua).

local runner = mod.test_runner
local link = ut.link

local CONFIG = {
	-- LinkAmmo.MaxAmmo, all of it in the clip
	max_ammo = 220,
	-- LinkAltFire: FireRate and AmmoPerFire. Held for hold_time, the button fires about hold_time / rate bolts, with this much either way.
	bolt_rate = 0.2, -- s
	bolt_ammo = 2,
	hold_time = 1, -- s
	count_margin = 1,
	-- LinkProjectile: Speed 1000 and 3000 a second more to 4000, in UT units, at 0.02 m a unit: 20 m/s, 60 m/s per second, at most 80 m/s.
	-- The speed is measured over the first early_time of the flight, and over late_time after late_start, with this much either way.
	bolt_start_speed = 20, -- m/s
	bolt_acceleration = 60, -- m/s/s
	bolt_max_speed = 80, -- m/s
	early_time = 0.1, -- s
	late_start = 0.5, -- s
	late_time = 0.1, -- s
	speed_margin = 6, -- m/s
	-- LinkFire: a hit every FireRate for AmmoPerFire. Held on an enemy for beam_time, the beam hurts it about beam_time / rate times.
	beam_rate = 0.12, -- s
	beam_ammo = 1,
	beam_time = 1.2, -- s
	hit_margin = 2,
	-- A link's boost: the bolt does 1 + links times its damage, and the beam 1 + 1.5 links, with this much either way (the first hit of
	-- each, before the enemy is staggered)
	bolt_link_scale = 2,
	beam_link_scale = 2.5,
	link_margin = 0.25,
	-- The enemy that is shot, and how far ahead it stands
	breed = "chaos_marauder",
	enemy_distance = 6, -- m
	-- The damage of a bolt and of the beam against armour and monsters, of the damage against an enemy with none, with this much either
	-- way (link_gun.lua's bolt_armor_attack and beam_armor_attack). Only a first hit is compared, before the enemy is staggered. A
	-- Stormvermin is armoured, a Chaos warrior's body is super armour, and a rat ogre is a monster and a boss, whose damage the game takes
	-- down to 0.45 (boss_damage_reduction).
	bolt_armour_breeds = {
		{ "skaven_storm_vermin", 0.8 },
		{ "chaos_warrior", 0.5 },
		{ "skaven_rat_ogre", 1 * 0.45 },
	},
	beam_armour_breeds = {
		{ "skaven_storm_vermin", 0.5 },
		{ "chaos_warrior", 0.3 },
		{ "skaven_rat_ogre", 1 * 0.45 },
	},
	armour_margin = 0.1,
	-- A bolt on the head of an enemy with no armour does the game's head bonus: 0.4 more on linesman_curve, with a boost of 0.5, as the
	-- Minigun's. The most of a few bolts at the head is taken, as one can hit the neck.
	headshot_ratio = 1.4,
	headshot_margin = 0.1,
	head_tries = 3,
	-- A critical hit does at least crit_least_ratio more than a plain one against an enemy with no armour, and more than a plain one
	-- against super armour, where the game adds less of a critical hit's bonus (a Chaos warrior's body)
	crit_least_ratio = 1.2,
	crit_armour_breed = "chaos_warrior",
	-- An enemy that raises a shield. One hit is fired at it: quick hits break its guard, as quick melee hits do.
	shield_breed = "skaven_clan_rat_with_shield",
	-- The enemy in front, in the test that a hit stops at the first enemy: one the hits don't kill
	sturdy_breed = "chaos_warrior",
	-- LinkAltFire.ProjSpawnOffset: the bolt starts 8 UT units to the right of the eye and 3 below it (0.02 m a unit), with this much
	-- either way, and two bolts start within start_same of each other
	bolt_start_right = 0.16, -- m
	bolt_start_down = 0.06, -- m
	start_margin = 0.03, -- m
	start_same = 0.01, -- m
	-- LinkProjectile.LifeSpan, with this much either way
	bolt_life = 3, -- s
	life_margin = 0.2, -- s
	-- The beam starts at once after a bolt whose button was let go, at most this much later: in UT a fire mode only keeps the other from
	-- starting while its button is held (Weapon.ReadyToFire, bModeExclusive and bIsFiring, which letting go clears)
	switch_late = 0.15, -- s
	-- The ally who is linked: Bardin as a Ranger with his Link Gun, this far ahead, standing still
	ally_profile = "dwarf_ranger",
	ally_career = 1,
	ally_distance = 4, -- m
	link_time = 1, -- s
	-- The bot that links on its own: Kerillian as a Waywatcher with her Link Gun, playing as the game's bots do, this far behind the
	-- player. A bot it links stands this far ahead, and the player steps this far to the right, out of the way of the beam.
	linker_profile = "wood_elf",
	linker_career = 1,
	linker_behind = -3, -- m
	firer_ahead = 4, -- m
	player_aside = 3, -- m
	-- The enemy a bot shoots with its Link Gun, a special this far off, as the Lightning Gun's test has: an enemy near a bot (within 12
	-- m) has it fight with its melee weapon (BTConditions.bot_in_melee_range). How long the bot has to hurt it.
	bot_special = "skaven_ratling_gunner",
	bot_special_distance = 14, -- m
	bot_fight_time = 30, -- s
	-- How long the bot may take to turn and link, and to let go once the firing stops (a bolt counts for half a second, and the link holds
	-- half a second more)
	bot_link_time = 5, -- s
	bot_let_go_time = 2, -- s
	-- Three bots link the player while the beam kills a monster. The monster stands in the level's unreachable place, and the player
	-- below it, this far ahead and to the right of below_unreachable, as in the Flak Cannon's boss test. The bots are the three other
	-- heroes with their Link Guns, playing as the game's bots do, in a row behind the player. They have team_link_time to make three
	-- links (in a chain or all on the player, both count three: LinkGun.Links), and the beam has kill_time to kill the monster.
	-- Everyone's ammo is filled when it runs below low_ammo.
	monster = "skaven_rat_ogre",
	player_ahead = 2, -- m
	player_right = 2, -- m
	team = {
		{ profile = "dwarf_ranger", career = 1, setting_id = "link_gun_dr", distance = -2 },
		{ profile = "wood_elf", career = 1, setting_id = "link_gun_we", distance = -3 },
		{ profile = "witch_hunter", career = 1, setting_id = "link_gun_wh", distance = -4 },
	},
	team_link_time = 10, -- s
	-- The heat given to Sienna to vent (her threshold is 10), and how long the reload button is held
	vent_heat = 8,
	vent_time = 1, -- s
	kill_time = 60, -- s
	low_ammo = 40,
}

local function is_bolt(action)
	return action.ut_link_bolt
end

-- The key of the Link Gun in the player's hands
local function item_key(t)
	return t.on_main_thread(function ()
		local slot_data = ScriptUnit.extension(t.unit(), "inventory_system"):get_slot_data("slot_ranged")

		return slot_data and slot_data.item_data and slot_data.item_data.name
	end)
end

-- Collects the player's bolts that start from now on, each with where it was and when: { [unit] = { { t, x, y, z }, ... } }
local function bolt_tracker(t)
	local earlier = {}

	for _, unit in ipairs(t.projectiles(is_bolt)) do
		earlier[unit] = true
	end

	local tracks = {}

	return tracks, function ()
		for _, unit in ipairs(t.projectiles(is_bolt)) do
			if not earlier[unit] then
				local position = Unit.world_position(unit, 0)
				local track = tracks[unit] or {}

				track[#track + 1] = { Managers.time:time("game"), Vector3.x(position), Vector3.y(position), Vector3.z(position) }
				tracks[unit] = track
			end
		end
	end
end

-- Keeps a bot from using its career skill, as the Lightning Gun's bot tests do: the skill is put on its cooldown, which is paused. The bot
-- is taken away after the scenario.
local function no_career_skill(t, bot)
	t.on_main_thread(function ()
		local career_extension = ScriptUnit.extension(bot, "career_system")

		career_extension:start_activated_ability_cooldown(1, nil, nil, true)
		career_extension:set_activated_ability_cooldown_paused(1)
	end)
end

-- The ammo extension of a character's Link Gun (on the main thread)
local function gun_ammo(unit)
	local slot_data = Unit.alive(unit) and ScriptUnit.extension(unit, "inventory_system"):get_slot_data("slot_ranged")

	return slot_data and GearUtils.get_ammo_extension(slot_data.right_unit_1p, slot_data.left_unit_1p)
end

-- The ammo of a character's Link Gun
local function ammo_of(t, unit)
	return t.on_main_thread(function ()
		local ammo_extension = gun_ammo(unit)

		return ammo_extension and ammo_extension:total_remaining_ammo() or 0
	end)
end

-- Fills a character's Link Gun
local function fill(t, unit)
	t.on_main_thread(function ()
		local ammo_extension = gun_ammo(unit)

		if ammo_extension then
			ammo_extension:add_ammo()
		end
	end)
end

local function count(set)
	local total = 0

	for _ in pairs(set) do
		total = total + 1
	end

	return total
end

-- The average speed of a track between two times after its first point, in m/s
local function speed_between(track, from, to)
	local start_t = track[1][1]
	local a, b

	for _, point in ipairs(track) do
		local age = point[1] - start_t

		if not a and age >= from then
			a = point
		end

		if age <= to then
			b = point
		end
	end

	if not a or not b or b[1] <= a[1] then
		return nil
	end

	local distance = math.sqrt((b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2 + (b[4] - a[4]) ^ 2)

	return distance / (b[1] - a[1])
end

-- The player's first hit of a mode on an enemy ahead, aimed at its middle or at its head: its damage and its hit zone
local function one_hit(t, mode, breed_name, at_head)
	t.go_to_start()

	local enemy = t.spawn(breed_name, CONFIG.enemy_distance)

	if not t.expect(enemy, "the %s could not be spawned", breed_name) then
		return nil
	end

	t.wait(1)

	if at_head then
		local head = t.on_main_thread(function ()
			local position = Unit.world_position(enemy, Unit.node(enemy, "j_head"))

			return { Vector3.x(position), Vector3.y(position), Vector3.z(position) }
		end)

		t.aim_at_point(head[1], head[2], head[3])
	else
		t.aim_at(enemy)
	end

	local damage = t.track_damage(enemy)

	if mode == "bolt" then
		t.press("action_one", 0.05)
		t.wait(1)
	else
		t.press("action_two", CONFIG.beam_rate * 0.5)
		t.wait(0.5)
	end

	t.remove(enemy)
	t.wait(0.5)

	-- The player's own first hit (an ally bot can shoot the enemy too)
	local first
	local hits = {}

	for _, hit in ipairs(damage.hits) do
		hits[#hits + 1] = string.format("%.1f by %s on the %s", hit.amount, hit.attacker, tostring(hit.zone))

		if not first and hit.attacker == "self" then
			first = hit
		end
	end

	t.log("%s at the %s: %s", mode, breed_name, table.concat(hits, ", "))

	return first and first.amount, first and first.zone
end

-- The damage of the first hit of a mode on an enemy ahead: "bolt" (a tap of the left button) or "beam" (a moment of the right button). The
-- enemy is CONFIG.breed if no breed is given, and the shot is aimed at its middle, or at its head. A shot at the middle can hit the head
-- (a linked bolt starts further ahead, and the enemy's idle moves its head), which does the head bonus: it is shot again then.
local function first_hit(t, mode, breed_name, at_head)
	breed_name = breed_name or CONFIG.breed

	local amount, zone

	for _ = 1, 3 do
		amount, zone = one_hit(t, mode, breed_name, at_head)

		if at_head or (zone ~= "head" and zone ~= "neck") then
			return amount
		end
	end

	return nil
end

-- Checks a mode's damage against each armour type, as a share of the damage against an enemy with none. There are no critical hits.
local function check_armour(t, mode, breeds)
	t.critical_hits(false)

	local plain = first_hit(t, mode)

	if not t.expect(plain, "the %s did not hurt the %s", mode, CONFIG.breed) then
		return
	end

	for _, entry in ipairs(breeds) do
		local breed_name, share = entry[1], entry[2]
		local damage = first_hit(t, mode, breed_name)

		if t.expect(damage, "the %s did not hurt the %s", mode, breed_name) then
			t.log("%s, %s: %.2f, %.2f of the marauder's %.2f", mode, breed_name, damage, damage / plain, plain)
			t.expect(math.abs(damage / plain - share) <= CONFIG.armour_margin, "the %s did %.2f of its damage to the %s, not %.2f", mode, damage / plain, breed_name, share)
		end
	end
end

-- Takes all the ammo out of the player's Link Gun
local function empty(t)
	t.on_main_thread(function ()
		local ammo_extension = gun_ammo(t.unit())

		if ammo_extension then
			ammo_extension:use_ammo(ammo_extension:ammo_count())
		end
	end)
	t.wait(0.2)
end

-- Where the player's eye is and the way it looks: { position, forward, right, up }, boxed
local function eye_of(t)
	return t.on_main_thread(function ()
		local first_person_extension = ScriptUnit.extension(t.unit(), "first_person_system")
		local rotation = first_person_extension:current_rotation()

		return {
			position = Vector3Box(first_person_extension:current_position()),
			forward = Vector3Box(Quaternion.forward(rotation)),
			right = Vector3Box(Quaternion.right(rotation)),
			up = Vector3Box(Quaternion.up(rotation)),
		}
	end)
end

-- How far to the right of the eye and below it a track's first point is
local function start_offset(track, eye)
	local point = track and track[1]

	if not point then
		return nil
	end

	local offset = Vector3(point[2], point[3], point[4]) - eye.position:unbox()

	return { Vector3.dot(offset, eye.right:unbox()), -Vector3.dot(offset, eye.up:unbox()) }
end

-- The bolt the player fires with a tap, as it flies: its unit, or nil if none was seen
local function fire_and_find_bolt(t)
	local found

	local function look()
		found = found or t.projectiles(is_bolt)[1]
	end

	t.press("action_one", 0.05, look)
	t.watch(0.2, look)

	return found
end

local function scenarios()
	return {
		{
			-- Sienna's heat is her career's, so it builds while she holds the Link Gun, and her copy vents it on the reload button, as her
			-- staffs do. The heat is given here, and the button held for vent_time.
			name = "Sienna's copy vents her heat on the reload button",
			every_hero = true,
			run = function (t)
				if t.wielded() ~= ut.items.weapons.link_gun_bw.template then
					t.skip("only Sienna's copy vents")
				end

				t.on_main_thread(function ()
					ScriptUnit.extension(t.unit(), "overcharge_system"):add_charge(CONFIG.vent_heat)
				end)

				local before = t.overcharge()
				local vented = false

				t.press("weapon_reload", CONFIG.vent_time, function ()
					local overcharge_extension = ScriptUnit.has_extension(t.unit(), "overcharge_system")

					vented = vented or overcharge_extension ~= nil and overcharge_extension.venting_overcharge == true
				end)

				t.log("heat %.1f to %.1f", before, t.overcharge())
				t.expect(before > 0, "the heat could not be given")
				t.expect(vented, "holding the reload button didn't vent the heat")
			end,
		},
		{
			name = "all the ammo is in the clip",
			every_hero = true,
			run = function (t)
				local ammo = t.on_main_thread(function ()
					local slot_data = ScriptUnit.extension(t.unit(), "inventory_system"):get_slot_data("slot_ranged")
					local ammo_extension = GearUtils.get_ammo_extension(slot_data.right_unit_1p, slot_data.left_unit_1p)

					return ammo_extension and { ammo_extension:ammo_count(), ammo_extension:total_remaining_ammo() }
				end)

				if t.expect(ammo, "the gun has no ammo") then
					t.expect(ammo[2] >= CONFIG.max_ammo, "the gun holds %d, less than %d", ammo[2], CONFIG.max_ammo)
					t.expect(ammo[1] == ammo[2], "%d of the %d are in the clip: there is a reload", ammo[1], ammo[2])
				end
			end,
		},
		{
			name = "the left button fires a bolt for 2 ammo",
			every_hero = true,
			basic = true,
			run = function (t)
				t.look(10)

				local before = t.ammo()
				local tracks, observe = bolt_tracker(t)

				t.press("action_one", 0.05, observe)
				t.watch(0.5, observe)

				t.expect(count(tracks) == 1, "%d bolts were fired, not 1", count(tracks))
				t.expect(before - (t.ammo() or 0) == CONFIG.bolt_ammo, "the bolt used %d ammo, not %d", before - (t.ammo() or 0), CONFIG.bolt_ammo)
			end,
		},
		{
			name = "holding the left button fires a bolt every 0.2 s",
			every_hero = true,
			run = function (t)
				t.look(10)

				local tracks, observe = bolt_tracker(t)

				t.press("action_one", CONFIG.hold_time, observe)
				t.watch(0.3, observe)

				local expected = math.floor(CONFIG.hold_time / CONFIG.bolt_rate) + 1

				t.log("%d bolts in %.1f s", count(tracks), CONFIG.hold_time)
				t.expect(math.abs(count(tracks) - expected) <= CONFIG.count_margin, "%d bolts in %.1f s, not about %d", count(tracks), CONFIG.hold_time, expected)
			end,
		},
		{
			name = "a bolt speeds up as it flies",
			run = function (t)
				t.look(5)

				local tracks, observe = bolt_tracker(t)

				t.press("action_one", 0.05, observe)
				t.watch(CONFIG.late_start + CONFIG.late_time + 0.1, observe)

				local track = next(tracks) and tracks[next(tracks)]

				if not t.expect(track, "no bolt was fired") then
					return
				end

				local early = speed_between(track, 0, CONFIG.early_time)
				local late = speed_between(track, CONFIG.late_start, CONFIG.late_start + CONFIG.late_time)
				local expected_early = CONFIG.bolt_start_speed + CONFIG.bolt_acceleration * CONFIG.early_time / 2
				local expected_late = math.min(CONFIG.bolt_start_speed + CONFIG.bolt_acceleration * (CONFIG.late_start + CONFIG.late_time / 2), CONFIG.bolt_max_speed)

				t.log("early %.1f m/s, late %.1f m/s", early or -1, late or -1)

				if t.expect(early and late, "the bolt did not fly long enough to be measured") then
					t.expect(math.abs(early - expected_early) <= CONFIG.speed_margin, "the bolt left at %.1f m/s, not about %.1f", early, expected_early)
					t.expect(math.abs(late - expected_late) <= CONFIG.speed_margin, "the bolt flew %.1f m/s after %.1f s, not about %.1f", late, CONFIG.late_start, expected_late)
				end
			end,
		},
		{
			name = "a bolt hurts an enemy",
			every_hero = true,
			run = function (t)
				local damage = first_hit(t, "bolt")

				t.expect(damage and damage > 0, "the bolt did not hurt the %s", CONFIG.breed)
			end,
		},
		{
			name = "the beam hurts an enemy every 0.12 s, for 1 ammo each",
			every_hero = true,
			run = function (t)
				local key = item_key(t)
				local enemy = t.spawn(CONFIG.breed, CONFIG.enemy_distance)

				if not t.expect(enemy, "the %s could not be spawned", CONFIG.breed) then
					return
				end

				t.wait(1)
				t.aim_at(enemy)

				local damage = t.track_damage(enemy)
				local before = t.ammo()

				t.press("action_two", CONFIG.beam_time)
				t.wait(0.3)

				local hits = 0

				for _, hit in ipairs(damage.hits) do
					if hit.source == key then
						hits = hits + 1
					end
				end

				local used = before - (t.ammo() or 0)
				local expected = math.floor(CONFIG.beam_time / CONFIG.beam_rate)

				t.log("%d hits and %d ammo in %.1f s", hits, used, CONFIG.beam_time)
				t.expect(math.abs(hits - expected) <= CONFIG.hit_margin, "the beam hurt the %s %d times, not about %d", CONFIG.breed, hits, expected)
				t.expect(math.abs(used - expected * CONFIG.beam_ammo) <= CONFIG.hit_margin, "the beam used %d ammo, not about %d", used, expected * CONFIG.beam_ammo)
			end,
		},
		{
			name = "with no ammo nothing is fired",
			run = function (t)
				empty(t)
				t.expect(t.ammo() == 0, "%s ammo is left, not 0", tostring(t.ammo()))

				local tracks, observe = bolt_tracker(t)
				local beamed = false

				local function watch()
					observe()

					beamed = beamed or link.beams[t.unit()] ~= nil
				end

				t.press("action_one", 0.5, watch)
				t.press("action_two", 0.5, watch)
				t.watch(0.3, watch)

				t.expect(count(tracks) == 0, "%d bolts were fired with no ammo", count(tracks))
				t.expect(not beamed, "the beam was fired with no ammo")
			end,
		},
		{
			-- The bolt starts ProjSpawnOffset from the eye, and two bolts start in the same place
			name = "a bolt starts to the right of the eye and below it, in the same place each time",
			run = function (t)
				local starts = {}

				for i = 1, 2 do
					t.look(0)

					local eye = eye_of(t)
					local tracks, observe = bolt_tracker(t)

					t.press("action_one", 0.05, observe)
					t.watch(0.15, observe)

					starts[i] = start_offset(next(tracks) and tracks[next(tracks)], eye)

					if not t.expect(starts[i], "bolt %d was not seen flying", i) then
						return
					end

					t.log("bolt %d: %.3f m right, %.3f m down", i, starts[i][1], starts[i][2])
					t.wait(CONFIG.bolt_rate)
				end

				for i, start in ipairs(starts) do
					t.expect(math.abs(start[1] - CONFIG.bolt_start_right) <= CONFIG.start_margin, "bolt %d started %.2f m to the right of the eye, not %.2f", i, start[1], CONFIG.bolt_start_right)
					t.expect(math.abs(start[2] - CONFIG.bolt_start_down) <= CONFIG.start_margin, "bolt %d started %.2f m below the eye, not %.2f", i, start[2], CONFIG.bolt_start_down)
				end

				t.expect(math.abs(starts[1][1] - starts[2][1]) <= CONFIG.start_same and math.abs(starts[1][2] - starts[2][2]) <= CONFIG.start_same, "the two bolts started in different places")
			end,
		},
		{
			-- A bolt that hits nothing is gone after LinkProjectile.LifeSpan
			name = "a bolt that hits nothing is gone after its life",
			run = function (t)
				t.look(60)

				local tracks, observe = bolt_tracker(t)

				t.press("action_one", 0.05, observe)
				t.watch(CONFIG.bolt_life + 1, observe)

				local track = next(tracks) and tracks[next(tracks)]

				if not t.expect(track, "no bolt was fired") then
					return
				end

				local life = track[#track][1] - track[1][1]

				t.log("the bolt flew for %.2f s", life)
				t.expect(math.abs(life - CONFIG.bolt_life) <= CONFIG.life_margin, "the bolt flew for %.2f s, not %.1f", life, CONFIG.bolt_life)
			end,
		},
		{
			-- The bolt hits an enemy as a rocket does (utils.UT_PROJECTILE_RADIUS), and a wall by a ray, as UT's bolt is a point
			name = "a bolt's sphere is UT's against enemies, and a ray against walls",
			run = function (t)
				t.look(20)

				local bolt = fire_and_find_bolt(t)

				if not t.expect(bolt, "no bolt flew") then
					return
				end

				local sizes = t.on_main_thread(function ()
					local impact_extension = Unit.alive(bolt) and ScriptUnit.has_extension(bolt, "projectile_impact_system")

					return impact_extension and { radius = impact_extension.radius, static_impact_type = impact_extension.static_impact_type }
				end)

				if t.expect(sizes, "the bolt was gone before it was looked at") then
					t.log("enemies %.2f m, walls %s", sizes.radius, tostring(sizes.static_impact_type))
					t.expect(math.abs(sizes.radius - ut.utils.UT_PROJECTILE_RADIUS) < 0.001, "the bolt's sphere against enemies is %.2f m, not %.2f", sizes.radius, ut.utils.UT_PROJECTILE_RADIUS)
					t.expect(sizes.static_impact_type == "raycast", "the bolt meets walls by %s, not a ray", tostring(sizes.static_impact_type))
				end
			end,
		},
		{
			-- The right button starts the beam at once after a bolt whose button was let go, as UT's does
			name = "the beam starts right after a bolt",
			run = function (t)
				t.look(10)

				local tracks, observe = bolt_tracker(t)
				local beam_t

				local function watch()
					observe()

					if not beam_t and link.beams[t.unit()] then
						beam_t = Managers.time:time("game")
					end
				end

				t.press("action_one", 0.05, watch)
				t.press("action_two", CONFIG.bolt_rate + 0.5, watch)

				local track = next(tracks) and tracks[next(tracks)]

				if not t.expect(track and beam_t, "the bolt or the beam was not seen (bolt %s, beam %s)", tostring(track ~= nil), tostring(beam_t)) then
					return
				end

				local gap = beam_t - track[1][1]

				t.log("the beam started %.2f s after the bolt", gap)
				t.expect(gap <= CONFIG.switch_late, "the beam started %.2f s after the bolt, not at once", gap)
			end,
		},
		{
			-- The gun can be put away while the beam is held, and the beam stops
			name = "the gun can be put away while the beam fires",
			every_hero = true,
			run = function (t)
				local template = t.wielded()
				local enemy = t.spawn(CONFIG.breed, CONFIG.enemy_distance)

				if not t.expect(enemy, "the %s could not be spawned", CONFIG.breed) then
					return
				end

				t.wait(1)
				t.aim_at(enemy)

				local damage = t.track_damage(enemy)

				t.hold("action_two")
				t.wait(0.5)
				t.tap("wield_1")
				t.wait(0.3)

				local hits_at_switch = #damage.hits

				t.wait(1)
				t.release("action_two")

				t.expect(t.wielded() ~= template, "the gun is still in the hands (%s)", tostring(t.wielded()))
				t.expect(link.beams[t.unit()] == nil, "the beam is still held after the gun was put away")
				t.expect(#damage.hits - hits_at_switch <= 1, "the beam hurt the %s %d times after the gun was put away", CONFIG.breed, #damage.hits - hits_at_switch)

				t.tap("wield_2")
				t.wait(1.5)
			end,
		},
		{
			-- A bolt and a hit of the beam stop at the first enemy, as UT's do. The near one is one the hits don't kill, else the beam
			-- goes on to the far one once it is dead.
			name = "a bolt and the beam stop at the first enemy",
			run = function (t)
				for _, entry in ipairs({ { "action_one", 0.05, "bolt" }, { "action_two", CONFIG.beam_rate * 3, "beam" } }) do
					local button, time, name = entry[1], entry[2], entry[3]

					t.go_to_start()

					local near = t.spawn(CONFIG.sturdy_breed, 3)
					local far = t.spawn(runner.target_breed, 6)

					if not t.expect(near and far, "the targets could not be spawned") then
						return
					end

					t.wait(1)
					t.aim_at(near)

					local near_damage, far_damage = t.track_damage(near), t.track_damage(far)

					t.press(button, time)
					t.wait(1)

					t.expect(near_damage.total > 0, "the %s did not hurt the near target", name)
					t.expect(far_damage.total == 0, "the %s hurt the far target, behind the near one: %.1f", name, far_damage.total)

					t.remove(near)
					t.remove(far)
				end
			end,
		},
		{
			-- There are no critical hits, so a hit on the body is the same each time
			name = "a bolt on the head does the game's head bonus",
			run = function (t)
				t.critical_hits(false)

				local body = first_hit(t, "bolt")
				local head

				for _ = 1, CONFIG.head_tries do
					local damage = first_hit(t, "bolt", nil, true)

					if damage then
						head = math.max(head or 0, damage)
					end
				end

				if t.expect(body and head, "a bolt did not hurt the %s (body %s, head %s)", CONFIG.breed, tostring(body), tostring(head)) then
					t.log("body %.2f, head %.2f", body, head)
					t.expect(math.abs(head / body - CONFIG.headshot_ratio) <= CONFIG.headshot_margin, "a bolt on the head did %.2f times the body's, not %.2f", head / body, CONFIG.headshot_ratio)
				end
			end,
		},
		{
			name = "bolts hurt armoured enemies and monsters by their armour",
			run = function (t)
				check_armour(t, "bolt", CONFIG.bolt_armour_breeds)
			end,
		},
		{
			name = "the beam hurts armoured enemies and monsters by their armour",
			run = function (t)
				check_armour(t, "beam", CONFIG.beam_armour_breeds)
			end,
		},
		{
			-- A shield blocks a bolt and a hit of the beam, and they don't break it (shield_break)
			name = "a raised shield stops a bolt and a hit of the beam",
			run = function (t)
				for _, entry in ipairs({ { "action_one", 0.05, "bolt" }, { "action_two", CONFIG.beam_rate * 0.5, "beam" } }) do
					local button, time, name = entry[1], entry[2], entry[3]

					t.go_to_start()

					local enemy = t.spawn(CONFIG.shield_breed, CONFIG.enemy_distance)

					if not t.expect(enemy, "the %s could not be spawned", CONFIG.shield_breed) then
						return
					end

					t.raise_shield(enemy)
					t.wait(1)
					t.aim_at(enemy)

					local damage = t.track_damage(enemy)

					t.press(button, time)
					t.wait(1)

					t.expect(not t.shield_broken(enemy), "the %s broke the %s's shield", name, CONFIG.shield_breed)
					t.expect(damage.total == 0, "the %s hurt the %s through its shield (%.1f)", name, CONFIG.shield_breed, damage.total)

					t.remove(enemy)
				end
			end,
		},
		{
			-- A critical bolt does more damage than a plain one, against an enemy with no armour and against super armour
			name = "a critical bolt does more damage, against super armour too",
			run = function (t)
				local armoured_breed = CONFIG.crit_armour_breed

				t.critical_hits(false)

				local plain = first_hit(t, "bolt")
				local plain_armoured = first_hit(t, "bolt", armoured_breed)

				t.critical_hits(true)

				local critical = first_hit(t, "bolt")
				local critical_armoured = first_hit(t, "bolt", armoured_breed)

				if not t.expect(plain and plain_armoured and critical and critical_armoured, "a bolt did not hurt its enemy") then
					return
				end

				t.log("plain %.2f, critical %.2f; against the %s plain %.2f, critical %.2f", plain, critical, armoured_breed, plain_armoured, critical_armoured)
				t.expect(critical > plain * CONFIG.crit_least_ratio, "a critical bolt did %.2f, not more than the plain %.2f", critical, plain)
				t.expect(critical_armoured > plain_armoured, "a critical bolt did %.2f to the %s, not more than the plain %.2f", critical_armoured, armoured_breed, plain_armoured)
			end,
		},
		{
			-- A bot fights an enemy with its Link Gun, and never hurts the player beside it
			name = "a bot shoots enemies with it",
			run = function (t)
				t.hurtable(true)

				local key = ut.items.weapons.link_gun_we.key
				local enemy = t.spawn(CONFIG.bot_special, CONFIG.bot_special_distance)

				if not t.expect(enemy, "the %s could not be spawned", CONFIG.bot_special) then
					return
				end

				local aside = t.ground_at(0, CONFIG.player_aside)

				if not t.expect(aside, "there is no ground beside the player") then
					return
				end

				local damage = t.track_damage(enemy)
				local player_damage = t.track_damage(t.unit())
				local bot = t.add_bot(CONFIG.linker_profile, CONFIG.linker_career, key, CONFIG.linker_behind, nil, true)

				if not t.expect(bot, "the bot could not be added") then
					return
				end

				no_career_skill(t, bot)

				t.on_main_thread(function ()
					runner.move_player(t.unit(), Vector3(aside[1], aside[2], aside[3]))
					-- (a bot fights an enemy only once it has been seen, which a calm one never is)
					runner.provoke(enemy)
				end)

				local function from_gun(record)
					local total = 0

					for _, hit in ipairs(record.hits) do
						if hit.source == key then
							total = total + hit.amount
						end
					end

					return total
				end

				t.wait_until(function ()
					return from_gun(damage) > 0
				end, CONFIG.bot_fight_time, "the bot to hurt the enemy")
				t.wait(3)

				t.expect(from_gun(damage) > 0, "the bot did not hurt the %s with its Link Gun in %d s", CONFIG.bot_special, CONFIG.bot_fight_time)
				t.expect(from_gun(player_damage) == 0, "the bot's Link Gun hurt the player %.1f", from_gun(player_damage))
			end,
		},
		{
			-- The beam on an ally who holds a Link Gun links them: it does no damage, takes no ammo, and gives them a link
			name = "the beam links an ally who holds a Link Gun",
			run = function (t)
				local ally = t.add_bot(CONFIG.ally_profile, CONFIG.ally_career, ut.items.weapons.link_gun_dr.key, CONFIG.ally_distance)

				if not t.expect(ally, "the ally could not be added") then
					return
				end

				t.aim_at(ally)

				local hurt = t.track_damage(ally)
				local before = t.ammo()
				local linked, links = false, 0

				t.press("action_two", CONFIG.link_time, function ()
					linked = linked or link.locked[t.unit()] == ally
					links = math.max(links, link.links_of(ally))
				end)
				t.wait(0.5)

				t.expect(linked, "the beam did not link the ally")
				t.expect(links == 1, "the ally had %d links, not 1", links)
				t.expect(before == t.ammo(), "the link used %d ammo", before - (t.ammo() or 0))
				t.expect(hurt.total == 0, "the beam hurt the ally %.1f", hurt.total)
				t.expect(link.locked[t.unit()] == nil, "the link was still there after the beam was let go")
			end,
		},
		{
			-- A player who is linked does twice the damage with a bolt, and two and a half times with the beam, and the allies who link
			-- them pay the same ammo. The ally's link is set here, as their machine (the host, for a bot) would set it.
			name = "a link boosts the bolts and the beam, and the linker pays the ammo too",
			run = function (t)
				t.critical_hits(false)

				local plain_bolt = first_hit(t, "bolt")
				local plain_beam = first_hit(t, "beam")
				local ally = t.add_bot(CONFIG.ally_profile, CONFIG.ally_career, ut.items.weapons.link_gun_dr.key, -CONFIG.ally_distance)

				if not t.expect(plain_bolt and plain_beam and ally, "the plain hits or the ally could not be had") then
					return
				end

				link.locked[ally] = t.unit()

				t.after(function ()
					link.locked[ally] = nil
				end)

				local ally_before = ammo_of(t, ally)
				local linked_bolt = first_hit(t, "bolt")
				local ally_after_bolt = ammo_of(t, ally)
				local linked_beam = first_hit(t, "beam")

				link.locked[ally] = nil

				if t.expect(linked_bolt and linked_beam, "a linked hit did not hurt the %s", CONFIG.breed) then
					t.log("bolt %.1f to %.1f, beam %.1f to %.1f, the ally's ammo %d to %d", plain_bolt, linked_bolt, plain_beam, linked_beam, ally_before, ally_after_bolt)
					t.expect(math.abs(linked_bolt / plain_bolt - CONFIG.bolt_link_scale) <= CONFIG.link_margin, "a linked bolt did %.2f times the damage, not %.1f", linked_bolt / plain_bolt, CONFIG.bolt_link_scale)
					t.expect(math.abs(linked_beam / plain_beam - CONFIG.beam_link_scale) <= CONFIG.link_margin, "a linked beam did %.2f times the damage, not %.1f", linked_beam / plain_beam, CONFIG.beam_link_scale)
					t.expect(ally_before - ally_after_bolt == CONFIG.bolt_ammo, "the linker paid %d ammo for the bolt, not %d", ally_before - ally_after_bolt, CONFIG.bolt_ammo)
				end
			end,
		},
		{
			-- A bot links the player while they fire, as UT's bots link their leader (LinkGun.FocusOnLeader), and lets go when they stop
			-- (link/bots.lua)
			name = "a bot links the player who fires",
			run = function (t)
				t.look(10)

				local bot = t.add_bot(CONFIG.linker_profile, CONFIG.linker_career, ut.items.weapons.link_gun_we.key, CONFIG.linker_behind, nil, true)

				if not t.expect(bot, "the bot could not be added") then
					return
				end

				t.hold("action_one")

				local linked = t.wait_until(function ()
					return link.locked[bot] == t.unit()
				end, CONFIG.bot_link_time, "the bot to link the player")
				local links = link.links_of(t.unit())

				t.release("action_one")

				t.expect(linked, "the bot did not link the player in %d s", CONFIG.bot_link_time)
				t.expect(not linked or links == 1, "the player had %d links, not 1", links)

				local let_go = t.wait_until(function ()
					return link.locked[bot] == nil
				end, CONFIG.bot_let_go_time, "the bot to let go")

				t.expect(let_go, "the bot still linked the player %d s after they stopped firing", CONFIG.bot_let_go_time)
			end,
		},
		{
			-- A bot does not step into the player's line of fire: it does not link a player who aims at it (FocusOnLeader). The player aims
			-- over its head.
			name = "a bot does not link a player who aims at it",
			run = function (t)
				local bot = t.add_bot(CONFIG.linker_profile, CONFIG.linker_career, ut.items.weapons.link_gun_we.key, CONFIG.linker_behind, nil, true)

				if not t.expect(bot, "the bot could not be added") then
					return
				end

				-- (the bot walks about, so the aim follows it)
				local aim_over_bot = function ()
					local above = t.on_main_thread(function ()
						local position = Unit.world_position(bot, 0)

						return { Vector3.x(position), Vector3.y(position), Vector3.z(position) + 2 }
					end)

					t.aim_at_point(above[1], above[2], above[3])
				end
				local linked = false
				local watch = function ()
					linked = linked or link.locked[bot] == t.unit()
				end
				local start = Managers.time:time("game")

				aim_over_bot()
				t.hold("action_one")

				while Managers.time:time("game") - start < CONFIG.bot_link_time do
					t.watch(0.2, watch)
					aim_over_bot()
				end

				t.release("action_one")

				t.expect(not linked, "the bot linked the player who aimed at it")
			end,
		},
		{
			-- A bot links another bot who fires a Link Gun. The bot who fires stands ahead, looking away from the one behind, and the player
			-- steps aside, or the beam would pass through them and link them instead.
			name = "a bot links another bot who fires",
			run = function (t)
				local aside = t.ground_at(0, CONFIG.player_aside)

				if not t.expect(aside, "there is no ground beside the player") then
					return
				end

				local firer = t.add_bot(CONFIG.ally_profile, CONFIG.ally_career, ut.items.weapons.link_gun_dr.key, CONFIG.firer_ahead)
				local linker = t.add_bot(CONFIG.linker_profile, CONFIG.linker_career, ut.items.weapons.link_gun_we.key, CONFIG.linker_behind, nil, true)

				if not t.expect(firer and linker, "the bots could not be added") then
					return
				end

				local away = t.on_main_thread(function ()
					local direction = Vector3.normalize(Vector3.flat(Unit.world_position(firer, 0) - Unit.world_position(linker, 0)))

					runner.move_player(t.unit(), Vector3(aside[1], aside[2], aside[3]))

					return { Vector3.x(direction), Vector3.y(direction), 0 }
				end)

				t.bot_look(firer, away)

				local linked = false
				local start = Managers.time:time("game")

				while not linked and Managers.time:time("game") - start < CONFIG.bot_link_time do
					t.bot_press(firer, "fire")

					linked = link.locked[linker] == firer
				end

				t.expect(linked, "the bot did not link the bot who fired in %d s", CONFIG.bot_link_time)
			end,
		},
		{
			-- The whole team: three bots link the player while the player's beam kills a monster. The player has three links, the beam
			-- hits harder once they are made (1 + 1.5 links), and the bots pay ammo with the player.
			name = "three bots link the player while the beam kills a monster",
			run = function (t)
				local key = item_key(t)
				local bots = {}

				-- The monster stands where bots can't walk to, and the player below it (the places of the Flak Cannon's "a bot fires shells
				-- at a boss it can't reach"), so the bots can't melee it. A boss is no target for their Link Guns either (the attack_meta_data's
				-- effective_against), so they are free to link.
				t.go_to("below_unreachable")

				local stand = t.ground_at(CONFIG.player_ahead, CONFIG.player_right)

				if not t.expect(stand, "there is no ground where the player should stand") then
					return
				end

				t.on_main_thread(function ()
					runner.move_player(t.unit(), Vector3(stand[1], stand[2], stand[3]))
				end)
				t.wait(0.5)

				-- The bots come first, and the monster after them, with their career skills held back: otherwise they attack it while the
				-- others are added (the Waystalker's volley at once), and it is dead before the player fires.
				for _, member in ipairs(CONFIG.team) do
					local bot = t.add_bot(member.profile, member.career, ut.items.weapons[member.setting_id].key, member.distance, nil, true)

					if not t.expect(bot, "the %s bot could not be added", member.profile) then
						return
					end

					no_career_skill(t, bot)

					bots[#bots + 1] = bot
				end

				local monster = t.spawn_at(CONFIG.monster, unpack(t.place("unreachable")))

				if not t.expect(monster, "the %s could not be spawned", CONFIG.monster) then
					return
				end

				t.wait(1)

				if not t.expect(t.health_of(monster) > 0, "the %s died before the player fired", CONFIG.monster) then
					return
				end

				-- For each bot: the ammo when it was last read, all it has paid, and how long its beam linked someone
				local last_ammo, spent, linked_for = {}, {}, {}

				for i, bot in ipairs(bots) do
					last_ammo[i], spent[i], linked_for[i] = ammo_of(t, bot), 0, 0
				end

				-- Adds what each bot has paid since the last read, and fills a bot that runs low
				local read_ammo = function ()
					for i, bot in ipairs(bots) do
						local ammo = ammo_of(t, bot)

						spent[i] = spent[i] + math.max(last_ammo[i] - ammo, 0)
						last_ammo[i] = ammo

						if ammo < CONFIG.low_ammo then
							fill(t, bot)

							last_ammo[i] = ammo_of(t, bot)
						end
					end
				end

				t.aim_at(monster)

				local damage = t.track_damage(monster)
				local most_links = 0
				local linked_at
				local last_frame = Managers.time:time("game")
				local watch_links = function ()
					local now = Managers.time:time("game")
					local links = link.links_of(t.unit())

					most_links = math.max(most_links, links)

					if links >= #bots and not linked_at then
						linked_at = #damage.hits
					end

					for i, bot in ipairs(bots) do
						if link.locked[bot] then
							linked_for[i] = linked_for[i] + now - last_frame
						end
					end

					last_frame = now
				end
				local start = Managers.time:time("game")

				t.hold("action_two")

				while t.health_of(monster) > 0 and Managers.time:time("game") - start < CONFIG.kill_time do
					t.watch(0.5, watch_links)
					t.aim_at(monster)

					if (t.ammo() or 0) < CONFIG.low_ammo then
						t.refill()
					end

					read_ammo()
				end

				t.release("action_two")
				read_ammo()

				for i in ipairs(bots) do
					t.log("the %s bot linked for %.1f s and paid %d ammo", CONFIG.team[i].profile, linked_for[i], spent[i])
				end

				local took = Managers.time:time("game") - start
				local first, strongest = nil, 0

				for i, hit in ipairs(damage.hits) do
					if hit.source == key then
						first = first or hit.amount

						if linked_at and i > linked_at then
							strongest = math.max(strongest, hit.amount)
						end
					end
				end

				t.log("%d links at most, the %s took %d hits in %.1f s, the first %.1f and the strongest linked one %.1f", most_links, CONFIG.monster, #damage.hits, took, first or -1, strongest)
				t.expect(most_links == #bots, "the player had %d links at most, not %d", most_links, #bots)
				t.expect(t.health_of(monster) == 0, "the %s was not killed in %d s", CONFIG.monster, CONFIG.kill_time)
				t.expect(first and strongest > first * 2, "the linked beam hit for %.1f at most, not much more than the first hit's %.1f", strongest, first or -1)

				for i in ipairs(bots) do
					t.expect(linked_for[i] > 0, "the %s bot never linked", CONFIG.team[i].profile)
					t.expect(linked_for[i] == 0 or spent[i] > 0, "the %s bot linked for %.1f s and paid no ammo", CONFIG.team[i].profile, linked_for[i])
				end
			end,
		},
	}
end

local function hero(setting_id, careers)
	local definition = ut.items.weapons[setting_id]

	return { item = definition.key, template = definition.template, careers = careers }
end

-- Every hero's copy has the same shots, on the base's animations, so every hero's first career runs what comes from the base: the ammo, the
-- shots and their damage
runner.add_suite({
	name = "link",
	slot = "slot_ranged",
	heroes = {
		hero("link_gun", { "es_mercenary", "es_huntsman", "es_knight" }),
		hero("link_gun_dr", { "dr_ironbreaker", "dr_ranger", "dr_engineer" }),
		hero("link_gun_wh", { "wh_captain", "wh_zealot", "wh_bountyhunter" }),
		hero("link_gun_bw", { "bw_adept", "bw_scholar", "bw_unchained" }),
		hero("link_gun_we", { "we_waywatcher", "we_maidenguard", "we_shade" }),
	},
	scenarios = scenarios(),
})
