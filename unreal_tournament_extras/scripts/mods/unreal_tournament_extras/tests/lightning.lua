local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The Lightning Gun's in-game tests (see runner.lua). Run them with /ut_test lightning, and the bots' with /ut_test lightning_bots. They
-- run in the runner's level, Righteous Stand.

local runner = mod.test_runner

local definition = ut.items.weapons.lightning_gun

local CONFIG = {
	-- SniperFire.FireRate, and how much sooner than that a second bolt may be recorded
	fire_rate = 1.6, -- s
	fire_rate_margin = 0.05, -- s
	-- The damage of a bolt against armour and monsters, of the damage against an enemy with none (a Chaos marauder), with this much either
	-- way (lightning_gun.lua's armor_attack). Only a first hit is compared, before the enemy is staggered. A Stormvermin is armoured, a
	-- Chaos warrior's body is super armour, and a rat ogre is a monster and a boss, whose damage the game takes down to 0.45
	-- (DamageUtils.calculate_damage's boss_damage_reduction).
	plain_breed = "chaos_marauder",
	armour_breeds = {
		{ "skaven_storm_vermin", 1 },
		{ "chaos_warrior", 0.6 },
		{ "skaven_rat_ogre", 1.2 * 0.45 },
	},
	armour_margin = 0.1,
	-- A critical hit does at least this much more than a plain one (the profile's crit_boost of 0.5 on its curve), and the breed it is
	-- also checked against, with the share of the damage the armour takes
	crit_least_ratio = 1.2,
	crit_armour_breed = { "chaos_warrior", 0.6 },
	-- An enemy with a shield that can't be broken (a shielded Stormvermin's)
	shield_breed = "skaven_storm_vermin_with_shield",
	-- An arc does half of the bolt's damage (SniperFire.SecDamageMult)
	arc_damage_ratio = 0.5,
	arc_damage_margin = 0.1,
	-- How far ahead the enemies that are shot stand, and how far to the side of the first one the enemy an arc goes for stands
	enemy_distance = 5, -- m
	arc_enemy_aside = 1.5, -- m
}

-- Records the bolts that happen while a test runs. The vectors are kept in boxes, as a vector only lasts its frame. The arcs are only
-- counted.
local bolts = {}

ut.lightning_bolt_callbacks.ut_test = function (owner_unit, end_position, hit_normal, arcs)
	if mod.test_recording then
		bolts[#bolts + 1] = {
			arc_count = #arcs,
			end_position = Vector3Box(end_position),
			hit = Vector3.length(hit_normal) > 0,
			owner_unit = owner_unit,
			time = Managers.time:time("game"),
		}
	end
end

local function start_recording()
	table.clear(bolts)

	mod.test_recording = true
end

local function stop_recording()
	mod.test_recording = nil
end

-- Whether the player's gun is locked out by overheating. It is asked from the scenario and from a wait's condition, which the runner
-- calls on the main thread already.
local function locked_out(t)
	local function check()
		local overcharge_extension = ScriptUnit.extension(t.unit(), "overcharge_system")

		return overcharge_extension:are_you_locked_out()
	end

	if coroutine.running() then
		return t.on_main_thread(check)
	end

	return check()
end

-- Takes all the heat off a unit's gun, so that the bolts of a scenario don't add up to an overheat
local function cool(t, unit)
	t.on_main_thread(function ()
		local overcharge_extension = ScriptUnit.extension(unit or t.unit(), "overcharge_system")

		overcharge_extension:remove_charge(overcharge_extension:get_overcharge_value())
	end)
end

-- Zooms out, if the view is zoomed
local function zoom_out(t)
	if ut.lightning.zoom.zoomed then
		t.press("action_two", 0.1)
		t.wait(0.2)
	end
end

-- The damage of the first bolt that hits an enemy of a breed, enemy_distance ahead, aimed at its middle
local function one_first_hit(t, breed_name)
	t.go_to_start()
	cool(t)

	local enemy = t.spawn(breed_name, CONFIG.enemy_distance)

	if not t.expect(enemy, "the %s could not be spawned", breed_name) then
		return nil
	end

	t.wait(1)
	t.aim_at(enemy)

	local damage = t.track_damage(enemy)

	t.press("action_one", 0.1)
	t.wait(0.5)
	t.remove(enemy)
	-- (the next bolt can't come before the fire time)
	t.wait(CONFIG.fire_rate)

	return damage.hits[1] and damage.hits[1].amount
end

-- The smaller of two first hits: a critical hit does more, and a bolt aimed at the middle can hit the head, so one of the two is taken
-- to be a plain one
local function first_hit(t, breed_name)
	local least

	for _ = 1, 2 do
		local damage = one_first_hit(t, breed_name)

		if damage then
			least = math.min(least or math.huge, damage)
		end
	end

	return least
end

local function scenarios()
	return {
		{
			-- A hit on the head does twice the damage of a hit on the body (SniperFire.HeadShotDamageMult), or more with a career's
			-- talents
			name = "head shots do double damage",
			run = function (t)
				-- The smallest of three bolts each, which leaves out critical hits (the Shade's passive makes them common)
				local body, head = math.huge, math.huge

				cool(t)

				for _ = 1, 3 do
					body = math.min(body, t.shot_damage(false) or math.huge)
					t.wait(1.8)
					head = math.min(head, t.shot_damage(true) or math.huge)
					t.wait(1.8)
				end

				if body == math.huge or head == math.huge then
					return
				end

				t.log("a bolt to the body did %.1f, to the head %.1f", body, head)
				t.expect(body > 0, "the bolt to the body did no damage")
				t.expect(head >= body * 1.8, "the bolt to the head did %.1f, not twice the %.1f of the body", head, body)
			end,
		},
		{
			name = "fire",
			basic = true,
			run = function (t)
				local before = t.overcharge()

				start_recording()
				t.press("action_one", 0.1)
				t.wait(0.5)
				stop_recording()

				local heat = t.overcharge() - before
				local cost = PlayerUnitStatusSettings.overcharge_values.ut_lightning_bolt

				t.expect(#bolts == 1, "%d bolts were made, not 1", #bolts)
				-- (the heat starts to cool half a second after the shot)
				t.expect(math.abs(heat - cost) <= cost * 0.1, "the shot added %.2f heat, not %.2f", heat, cost)

				if bolts[1] then
					t.expect(bolts[1].arc_count == 3 or not bolts[1].hit, "%d arcs jumped, not 3", bolts[1].arc_count)
				end
			end,
		},
		{
			name = "fire rate",
			run = function (t)
				-- Holding the button repeats the shot every 1.6 seconds: shots at 0, 1.6, 3.2 and 4.8. A fifth would heat the gun to the
				-- top.
				start_recording()
				t.press("action_one", 5.3)
				t.wait(0.5)
				stop_recording()

				local times = {}

				for _, bolt in ipairs(bolts) do
					times[#times + 1] = string.format("%.2f", bolt.time - bolts[1].time)
				end

				t.expect(#bolts == 4, "%d bolts were made in 5.8 seconds, not 4 (at %s)", #bolts, table.concat(times, ", "))
				t.expect(not locked_out(t), "four bolts overheated the gun")
			end,
		},
		{
			-- The Deepwood Staff's overheat: the gun is locked out until the heat is gone, and the player loses the gun's share of their health
			-- (lightning_gun.lua's overheat_health_lost; the staff's is 40%). Bolts
			-- can't be fired while it is. The heat cools between bolts, so it takes 14 at the fire rate: the 13th stops just short of the top
			-- (the game's critical margin) and the 14th overheats it. From 65% of the heat the game slows attacks (the overcharged buff),
			-- so the last bolts come further apart, and it takes about 25 s.
			name = "overheating locks the gun out",
			run = function (t)
				t.hurtable(true)
				t.heal()

				local health = t.health()

				start_recording()
				t.hold("action_one")

				local overheated = t.wait_until(function ()
					return locked_out(t)
				end, 40, "the gun to overheat")

				t.release("action_one")
				t.wait(0.5)
				stop_recording()

				local fired = #bolts

				t.expect(overheated, "%d bolts did not overheat the gun (heat %.1f)", fired, t.overcharge())
				local times = {}

				for _, bolt in ipairs(bolts) do
					times[#times + 1] = string.format("%.2f", bolt.time - bolts[1].time)
				end

				t.expect(fired == 14, "%d bolts were fired before the gun overheated, not 14 (at %s)", fired, table.concat(times, ", "))

				local lost = health - t.health()

				t.log("%d bolts, the overheat took %.0f of %.0f health", fired, lost, health)
				local share = ut.overheat_health_lost[definition.template]

				t.expect(math.abs(lost / health - share) < 0.05, "overheating took %.0f%% of the player's health, not %.0f%%", lost / health * 100, share * 100)

				start_recording()
				t.press("action_one", 1)
				t.wait(0.3)
				stop_recording()

				t.expect(#bolts == 0, "%d bolts were fired while the gun was locked out", #bolts)

				t.expect(t.wait_until(function ()
					return not locked_out(t)
				end, 30, "the lockout to end"), "the gun was still locked out after 30 seconds")
			end,
		},
		{
			name = "venting removes heat",
			run = function (t)
				t.press("action_one", 0.1)
				t.wait(1.8)
				t.press("action_one", 0.1)
				t.wait(0.3)

				local before = t.overcharge()

				t.press("weapon_reload", 1.5)
				t.wait(0.2)

				local after = t.overcharge()

				t.log("venting took the heat from %.1f to %.1f", before, after)
				t.expect(after < before * 0.5, "venting took the heat only from %.1f to %.1f", before, after)
			end,
		},
		{
			name = "zoom",
			run = function (t)
				local zoom = ut.lightning.zoom

				t.expect(not zoom.zoomed, "the weapon starts zoomed")

				-- Holding the button zooms in, and letting go keeps the zoom
				t.press("action_two", 0.5)
				t.wait(0.2)

				t.expect(zoom.zoomed, "the weapon did not zoom")

				local magnification = zoom.magnification()

				t.expect(magnification > 2, "the magnification is only %.2f after half a second", magnification)
				t.wait(0.3)
				t.expect(math.abs(zoom.magnification() - magnification) < 0.001, "the zoom went on after the button was let go")

				-- Pressing it again zooms out
				t.press("action_two", 0.1)
				t.wait(0.2)

				t.expect(not zoom.zoomed, "the weapon did not zoom out")
			end,
		},
		{
			-- The zoom button right after a shot works as at any other time: the shot turns into the zoom. Pressing it again after a
			-- shot zooms out, and the press doesn't start the zoom again.
			name = "the zoom button after a shot zooms in and out",
			run = function (t)
				local zoom = ut.lightning.zoom

				t.press("action_one", 0.1)
				t.wait(0.2)
				t.press("action_two", 0.3)
				t.wait(0.2)
				t.expect(zoom.zoomed, "the zoom button after a shot did not zoom in")
				t.wait(CONFIG.fire_rate)
				t.press("action_one", 0.1)
				t.wait(0.2)
				t.press("action_two", 0.1)
				t.wait(0.5)
				t.expect(not zoom.zoomed, "the zoom button after a shot did not zoom out, or zoomed in again")
				zoom_out(t)
			end,
		},
		{
			-- A shot can turn into the zoom at once and back, and the next bolt still waits for the fire time after the last one
			name = "zooming doesn't shorten the fire time",
			run = function (t)
				cool(t)
				start_recording()
				t.press("action_one", 0.1)
				t.hold("action_two")
				t.press("action_one", 2)
				t.release("action_two")
				t.wait(0.3)
				stop_recording()
				zoom_out(t)

				t.expect(#bolts == 2, "%d bolts were made, not 2", #bolts)

				if bolts[2] then
					local gap = bolts[2].time - bolts[1].time

					t.log("the second bolt came %.2f s after the first", gap)
					t.expect(gap >= CONFIG.fire_rate - CONFIG.fire_rate_margin, "the second bolt came %.2f s after the first, before the fire time of %.2f", gap, CONFIG.fire_rate)
				end
			end,
		},
		{
			-- Inspecting the weapon ends the zoom, and the zoom button does nothing until the inspect ends
			name = "inspecting ends the zoom and keeps it from starting",
			run = function (t)
				local zoom = ut.lightning.zoom

				t.press("action_two", 0.3)
				t.wait(0.2)

				if not t.expect(zoom.zoomed, "the weapon did not zoom") then
					return
				end

				t.hold("action_inspect")
				t.wait(0.5)
				t.expect(not zoom.zoomed, "inspecting did not end the zoom")
				t.press("action_two", 0.3)
				t.wait(0.2)

				local zoomed = zoom.zoomed

				t.release("action_inspect")
				t.wait(0.5)
				t.expect(not zoomed, "the zoom button zoomed while inspecting")
				zoom_out(t)
			end,
		},
		{
			name = "bolts hurt armoured enemies and monsters by their armour",
			run = function (t)
				local plain = first_hit(t, CONFIG.plain_breed)

				if not t.expect(plain, "a bolt did not hurt the %s", CONFIG.plain_breed) then
					return
				end

				for _, entry in ipairs(CONFIG.armour_breeds) do
					local breed_name, share = entry[1], entry[2]
					local damage = first_hit(t, breed_name)

					if t.expect(damage, "a bolt did not hurt the %s", breed_name) then
						t.log("%s: %.2f, %.2f of the marauder's %.2f", breed_name, damage, damage / plain, plain)
						t.expect(math.abs(damage / plain - share) <= CONFIG.armour_margin, "a bolt did %.2f of its damage to the %s, not %.2f", damage / plain, breed_name, share)
					end
				end
			end,
		},
		{
			-- An arc goes for an enemy near where the bolt hit and does half of the bolt's damage. It has the bolt's critical hit, so the
			-- two are compared as they are.
			name = "an arc hurts an enemy near the one hit for half the damage",
			run = function (t)
				cool(t)

				local first = t.spawn(CONFIG.plain_breed, CONFIG.enemy_distance)
				local aside = t.ground_at(CONFIG.enemy_distance, CONFIG.arc_enemy_aside)

				if not t.expect(first and aside, "the enemies could not be spawned") then
					return
				end

				local second = t.spawn_at(CONFIG.plain_breed, aside[1], aside[2], aside[3])

				if not t.expect(second, "the second %s could not be spawned", CONFIG.plain_breed) then
					return
				end

				t.wait(1)
				t.aim_at(first)

				local first_damage = t.track_damage(first)
				local second_damage = t.track_damage(second)

				t.press("action_one", 0.1)
				t.wait(0.5)

				local bolt = first_damage.hits[1] and first_damage.hits[1].amount
				local arc = second_damage.hits[1] and second_damage.hits[1].amount

				if t.expect(bolt, "the bolt did not hurt the enemy it was aimed at") and t.expect(arc, "no arc hurt the enemy beside it") then
					t.log("the bolt did %.2f, the arc %.2f", bolt, arc)
					t.expect(math.abs(arc / bolt - CONFIG.arc_damage_ratio) <= CONFIG.arc_damage_margin, "the arc did %.2f of the bolt's damage, not %.2f", arc / bolt, CONFIG.arc_damage_ratio)
				end
			end,
		},
		{
			-- The bolt goes through an enemy's raised shield (ignore_shield_hit), as UT has no shields to stop it
			name = "a bolt goes through a raised shield",
			run = function (t)
				cool(t)

				local enemy = t.spawn(CONFIG.shield_breed, CONFIG.enemy_distance)

				if not t.expect(enemy, "the %s could not be spawned", CONFIG.shield_breed) then
					return
				end

				t.raise_shield(enemy)
				t.wait(1)
				t.aim_at(enemy)

				local damage = t.track_damage(enemy)

				t.press("action_one", 0.1)
				t.wait(0.5)

				t.expect(damage.total > 0, "the bolt did no damage through the %s's shield", CONFIG.shield_breed)
			end,
		},
		{
			-- A critical hit does more damage, and armour takes the same share of it as of a plain hit (the profile's critical armour
			-- values are its plain ones)
			name = "a critical bolt does more damage, and armour takes the same share of it",
			run = function (t)
				t.critical_hits(false)

				local plain = one_first_hit(t, CONFIG.plain_breed)

				t.critical_hits(true)

				local critical = one_first_hit(t, CONFIG.plain_breed)
				local armoured = one_first_hit(t, CONFIG.crit_armour_breed[1])

				if not t.expect(plain and critical and armoured, "a bolt did not hurt its enemy") then
					return
				end

				t.log("plain %.2f, critical %.2f, critical against the %s %.2f", plain, critical, CONFIG.crit_armour_breed[1], armoured)
				t.expect(critical > plain * CONFIG.crit_least_ratio, "a critical bolt did %.2f, not more than the plain %.2f", critical, plain)
				t.expect(math.abs(armoured / critical - CONFIG.crit_armour_breed[2]) <= CONFIG.armour_margin, "a critical bolt did %.2f of its damage to the %s, not %.2f", armoured / critical, CONFIG.crit_armour_breed[1], CONFIG.crit_armour_breed[2])
			end,
		},
		{
			-- The bolt and its arcs are one shot, so the game's buffs on attack (talents, traits) run once for each enemy it hurts, numbered
			-- as the targets of a shot that goes through enemies are: the bolt's is the first, and each arc's the next
			name = "a bolt and its arcs run the buffs as the targets of one shot",
			run = function (t)
				cool(t)

				local enemies = {}

				for i, side in ipairs({ 0, -CONFIG.arc_enemy_aside, CONFIG.arc_enemy_aside }) do
					local ground = t.ground_at(CONFIG.enemy_distance, side)

					enemies[i] = ground and t.spawn_at(CONFIG.plain_breed, ground[1], ground[2], ground[3])
				end

				if not t.expect(enemies[1] and enemies[2] and enemies[3], "the enemies could not be spawned") then
					return
				end

				t.wait(1)
				t.aim_at(enemies[1])

				local procs = t.procs(definition.key)
				local damages = {}

				for i, enemy in ipairs(enemies) do
					damages[i] = t.track_damage(enemy)
				end

				t.press("action_one", 0.1)
				t.wait(0.5)

				local hurt = 0

				for _, damage in ipairs(damages) do
					if damage.total > 0 then
						hurt = hurt + 1
					end
				end

				-- (each entry ends with its target number)
				local numbers = {}

				for _, proc in ipairs(procs) do
					local number = tonumber(string.match(proc, "(%d+)$"))

					if number then
						numbers[number] = (numbers[number] or 0) + 1
					end
				end

				t.log("%d enemies hurt, the buffs ran %d times (%s)", hurt, #procs, table.concat(procs, ", "))
				t.expect(hurt > 1, "the arcs hurt no enemy beside the one hit")
				t.expect(#procs == hurt, "the buffs ran %d times for %d enemies hurt (%s)", #procs, hurt, table.concat(procs, ", "))

				for number = 1, hurt do
					t.expect(numbers[number] == 1, "the buffs ran %d times as target %d, not once (%s)", numbers[number] or 0, number, table.concat(procs, ", "))
				end
			end,
		},
		{
			-- The gun can be put away right after a shot, and no bolt comes after it
			name = "the gun can be put away right after a shot",
			run = function (t)
				local template = t.wielded()

				start_recording()
				t.press("action_one", 0.1)
				t.tap("wield_1")
				t.hold("action_one")
				t.wait(CONFIG.fire_rate + 0.5)
				t.release("action_one")
				stop_recording()

				t.expect(t.wielded() ~= template, "the gun is still in the hands (%s)", tostring(t.wielded()))
				t.expect(#bolts == 1, "%d bolts were made, not 1", #bolts)

				t.tap("wield_2")
				t.wait(1.5)
			end,
		},
		{
			name = "damages an enemy",
			run = function (t)
				local target = t.spawn_target(5)

				if not t.expect(target, "the target could not be spawned") then
					return
				end

				local health_extension = ScriptUnit.extension(target, "health_system")
				local before = health_extension:current_health()

				start_recording()
				t.press("action_one", 0.1)
				t.wait(1)
				stop_recording()

				local after = HEALTH_ALIVE[target] and health_extension:current_health() or 0

				t.expect(after < before, "the target was not hurt: %s of %s", tostring(after), tostring(before))
				mod:echo("[ut_test] the bolt did %s damage to a target with %s health", tostring(before - after), tostring(before))

				if bolts[1] then
					-- Vectors are made on the main thread, and the engine refuses them in a coroutine
					-- Where the bolt ended and where the target is, from the player's eyes: how far ahead and how far up
					local report = t.on_main_thread(function ()
						local first_person_extension = ScriptUnit.extension(t.unit(), "first_person_system")
						local eyes = first_person_extension:current_position()
						local target_position = Unit.alive(target) and Unit.world_position(target, 0) or eyes
						local ahead = Vector3.normalize(Vector3.flat(target_position - eyes))
						local bolt_end = bolts[1].end_position:unbox() - eyes
						local to_target = target_position - eyes

						local pitch = math.deg(math.asin(Vector3.z(Quaternion.forward(first_person_extension:current_rotation()))))

						return string.format("the bolt ended %.2f m ahead and %.2f m up, the target's feet are %.2f m ahead and %.2f m up (%s); the view is %.1f degrees up", Vector3.dot(bolt_end, ahead), Vector3.z(bolt_end), Vector3.dot(to_target, ahead), Vector3.z(to_target), bolts[1].hit and "it hit something" or "it hit nothing", pitch)
					end)

					mod:echo("[ut_test] %s", report)
				end
			end,
		},
	}
end

runner.add_suite({
	name = "lightning",
	item = definition.key,
	template = definition.template,
	slot = "slot_ranged",
	careers = { "we_waywatcher", "we_thornsister", "we_shade", "we_maidenguard" },
	scenarios = scenarios(),
})

-- Bots with the Lightning Gun (its attack_meta_data in lightning_gun.lua). A hero can't be a bot and the player at once, so these run in a
-- suite of their own with the player as Sienna, and the bot is Kerillian as a Waystalker, with her own mind. The heat is the game's bot
-- tree's to watch (bt_bot.lua): a bot stops firing near the top of the heat, and vents from half the threshold up (the game's bots only
-- up to the threshold, see lightning_gun.lua).
local BOTS = {
	profile = "wood_elf",
	career = 1,
	behind = -3, -- m
	player_aside = 3, -- m to the right
	special = "skaven_ratling_gunner",
	special_distance = 14, -- m
	-- How long the bot has to hurt the special
	fight_time = 30, -- s
	-- The heat given to the bot to vent: three bolts' worth, far over the threshold of 10 (OverchargeData.we_thornsister), where the
	-- game's own bots wouldn't vent until it had cooled for about 20 s
	vent_heat = 24,
	vent_time = 5, -- s
}

-- The damage from the Lightning Gun in a record of t.track_damage
local function from_lightning_gun(record)
	local total = 0

	for _, hit in ipairs(record.hits) do
		if hit.source == definition.key then
			total = total + hit.amount
		end
	end

	return total
end

-- Keeps a bot from using its career skill: the Waystalker's volley would shoot the special instead of the gun. The skill is put on its
-- cooldown, which is paused. The bot is taken away after the scenario.
local function no_career_skill(t, bot)
	t.on_main_thread(function ()
		local career_extension = ScriptUnit.extension(bot, "career_system")

		career_extension:start_activated_ability_cooldown(1, nil, nil, true)
		career_extension:set_activated_ability_cooldown_paused(1)
	end)
end

local function bot_scenarios()
	return {
		{
			-- The bot shoots the special, never hurts the player, and never overheats the gun
			name = "a bot shoots enemies with it",
			run = function (t)
				t.hurtable(true)

				local special = t.spawn(BOTS.special, BOTS.special_distance)

				if not t.expect(special, "the %s could not be spawned", BOTS.special) then
					return
				end

				local aside = t.ground_at(0, BOTS.player_aside)

				if not t.expect(aside, "there is no ground beside the player") then
					return
				end

				local bot = t.add_bot(BOTS.profile, BOTS.career, definition.key, BOTS.behind, nil, true)

				if not t.expect(bot, "the bot could not be added") then
					return
				end

				no_career_skill(t, bot)

				-- (a bot shoots a special only once it has been seen, which a calm one never is: shooting at the player makes it seen)
				t.on_main_thread(function ()
					runner.provoke(special)
				end)

				local damage = t.track_damage(special)
				local player_damage = t.track_damage(t.unit())

				local locked = false

				runner.frame_watchers[#runner.frame_watchers + 1] = function ()
					local overcharge_extension = Unit.alive(bot) and ScriptUnit.has_extension(bot, "overcharge_system")

					if overcharge_extension and overcharge_extension:are_you_locked_out() then
						locked = true
					end
				end

				t.on_main_thread(function ()
					runner.move_player(t.unit(), Vector3(aside[1], aside[2], aside[3]))
				end)
				start_recording()
				t.wait_until(function ()
					return from_lightning_gun(damage) > 0
				end, BOTS.fight_time, "the bot to hurt the special")
				t.wait(5)
				stop_recording()

				local fired = 0

				for _, bolt in ipairs(bolts) do
					if bolt.owner_unit == bot then
						fired = fired + 1
					end
				end

				t.log("the bot fired %d bolts", fired)
				t.expect(from_lightning_gun(damage) > 0, "the bot did not hurt the %s with the Lightning Gun in %d s", BOTS.special, BOTS.fight_time)
				t.expect(from_lightning_gun(player_damage) == 0, "the bot's bolts hurt the player %.1f", from_lightning_gun(player_damage))
				t.expect(not locked, "the bot overheated the gun")
			end,
		},
		{
			-- With no enemies about, a bot whose gun is over the threshold vents it at once (the reload button)
			name = "a bot vents its heat",
			run = function (t)
				local bot = t.add_bot(BOTS.profile, BOTS.career, definition.key, BOTS.behind, nil, true)

				if not t.expect(bot, "the bot could not be added") then
					return
				end

				t.on_main_thread(function ()
					ScriptUnit.extension(bot, "overcharge_system"):add_charge(BOTS.vent_heat)
				end)

				local vented = t.wait_until(function ()
					local overcharge_extension = Unit.alive(bot) and ScriptUnit.has_extension(bot, "overcharge_system")

					return overcharge_extension and overcharge_extension.venting_overcharge
				end, BOTS.vent_time, "the bot to vent")

				t.expect(vented, "the bot did not vent %.1f heat in %d s", BOTS.vent_heat, BOTS.vent_time)
			end,
		},
	}
end

local shock_rifle = ut.items.weapons.shock_rifle

runner.add_suite({
	name = "lightning_bots",
	item = shock_rifle.key,
	template = shock_rifle.template,
	slot = "slot_ranged",
	careers = { "bw_adept" },
	scenarios = bot_scenarios(),
})
