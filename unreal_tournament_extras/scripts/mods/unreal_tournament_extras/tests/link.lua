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

-- The damage of the first hit of a mode on an enemy ahead: "bolt" (a tap of the left button) or "beam" (a moment of the right button)
local function first_hit(t, mode)
	t.go_to_start()

	local enemy = t.spawn(CONFIG.breed, CONFIG.enemy_distance)

	if not t.expect(enemy, "the %s could not be spawned", CONFIG.breed) then
		return nil
	end

	t.wait(1)
	t.aim_at(enemy)

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

	return damage.hits[1] and damage.hits[1].amount
end

local function scenarios()
	return {
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
