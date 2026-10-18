local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The Minigun's in-game tests (see runner.lua), for Kruber's and Saltzpyre's. Run them with /ut_test minigun, and the bots' with
-- /ut_test minigun_bots. They run in the runner's level, Righteous Stand. The numbers expected are UT's (XWeapons/Minigun, MinigunFire
-- and MinigunAltFire) as the mod turns them into this game's (minigun/minigun.lua).

local runner = mod.test_runner

local CONFIG = {
	-- All the ammo, which is all in the clip
	max_ammo = 300,
	-- The wind up of each mode before its first round, and the time between rounds (MinigunFire and MinigunAltFire)
	primary_wind_up = 0.27, -- s
	primary_rate = 1 / 15, -- s
	alt_wind_up = 0.15, -- s
	alt_rate = 1 / 5, -- s
	-- How much later than the time between rounds the last round may come after the button is let go
	release_margin = 0.05, -- s
	-- How long a button is held to fire a few rounds of a mode
	burst_time = 0.6, -- s
	-- The alt fire's round does twice the primary's (DamageMin and DamageMax of 14 to 16, against 7 to 8)
	alt_damage_ratio = 2,
	damage_margin = 0.15,
	-- A round on the head of an enemy with no armour does the game's head bonus: 0.4 more on the repeater's curve (linesman_curve, a
	-- boost of 0.5)
	headshot_ratio = 1.4,
	headshot_margin = 0.1,
	-- The damage of a round against armour and monsters, of the damage against an enemy with none (a Chaos marauder), with this much
	-- either way (minigun.lua's armor_attack and alt_armor_attack). Only a first hit is compared, before the enemy is staggered (the
	-- game adds damage against a staggered enemy). A Stormvermin is armoured, a Chaos warrior's body is super armour, and a rat ogre is a
	-- monster and a boss, whose damage the game takes down to 0.45 (DamageUtils.calculate_damage's boss_damage_reduction).
	plain_breed = "chaos_marauder",
	primary_armour_breeds = {
		{ "skaven_storm_vermin", 0.5 },
		{ "chaos_warrior", 0.3 },
		{ "skaven_rat_ogre", 1 * 0.45 },
	},
	alt_armour_breeds = {
		{ "skaven_storm_vermin", 0.8 },
		{ "chaos_warrior", 0.5 },
		{ "skaven_rat_ogre", 1 * 0.45 },
	},
	armour_margin = 0.1,
	-- How far ahead the enemies that are shot stand
	enemy_distance = 5, -- m
}

-- The rounds that are made while a test runs
local shots = {}
local recording = false

ut.minigun_shot_callbacks.ut_test = function (owner_unit, mode, end_position)
	if recording then
		shots[#shots + 1] = {
			mode = mode,
			time = Managers.time:time("game"),
		}
	end
end

local function record()
	table.clear(shots)

	recording = true
end

local function stop_recording()
	recording = false
end

local function now(t)
	return t.on_main_thread(function ()
		return Managers.time:time("game")
	end)
end

local function button_of(mode)
	return mode == "alt" and "action_two" or "action_one"
end

-- The damage of the first round of a mode that hits an enemy of a breed, enemy_distance ahead: aimed at its middle, or at its head
local function first_hit(t, breed_name, mode, at_head)
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

	t.press(button_of(mode), CONFIG.burst_time)
	t.wait(0.5)
	t.remove(enemy)
	t.wait(1)

	return damage.hits[1] and damage.hits[1].amount
end

-- Checks a mode's damage against each armour type, as a share of the damage against an enemy with none
local function check_armour(t, mode, breeds)
	local plain = first_hit(t, CONFIG.plain_breed, mode)

	if not t.expect(plain, "a %s round did not hurt the %s", mode, CONFIG.plain_breed) then
		return
	end

	for _, entry in ipairs(breeds) do
		local breed_name, share = entry[1], entry[2]
		local damage = first_hit(t, breed_name, mode)

		if t.expect(damage, "a %s round did not hurt the %s", mode, breed_name) then
			t.log("%s, %s: %.2f, %.2f of the marauder's %.2f", mode, breed_name, damage, damage / plain, plain)
			t.expect(math.abs(damage / plain - share) <= CONFIG.armour_margin, "a %s round did %.2f of its damage to the %s, not %.2f", mode, damage / plain, breed_name, share)
		end
	end
end

local function set_ammo(t, count)
	t.on_main_thread(function ()
		local inventory_extension = ScriptUnit.extension(t.unit(), "inventory_system")
		local slot_data = inventory_extension:get_slot_data("slot_ranged")
		local ammo_extension = GearUtils.get_ammo_extension(slot_data.right_unit_1p, slot_data.left_unit_1p)

		ammo_extension:use_ammo(ammo_extension:ammo_count() - count)
	end)
	t.wait(0.2)
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

					return ammo_extension and { ammo_extension:ammo_count(), ammo_extension:total_remaining_ammo() }
				end)

				if not t.expect(ammo, "the weapon has no ammo extension") then
					return
				end

				local clip, total = ammo[1], ammo[2]

				t.expect(total >= CONFIG.max_ammo, "the gun holds %s, less than %d", tostring(total), CONFIG.max_ammo)
				t.expect(clip == total, "%s of the %s are in the clip: there is a reload", tostring(clip), tostring(total))
			end,
		},
		{
			name = "primary fire",
			every_hero = true,
			basic = true,
			run = function (t)
				local before = t.ammo()

				record()
				t.press("action_one", 2)
				t.wait(0.3)
				stop_recording()

				-- The first round comes after the wind up, and then there are 15 a second
				local expected = math.floor((2 - CONFIG.primary_wind_up) / CONFIG.primary_rate) + 1

				t.expect(#shots >= expected - 2 and #shots <= expected + 1, "%d rounds in 2 seconds, not about %d", #shots, expected)
				t.expect(before - (t.ammo() or 0) == #shots, "the rounds used %s ammo, not %d", tostring(before - (t.ammo() or 0)), #shots)

				if shots[1] then
					mod:echo("[ut_test] first round at the first frame +%.2f s, the last at +%.2f s", 0, shots[#shots].time - shots[1].time)
				end
			end,
		},
		{
			name = "alt fire",
			every_hero = true,
			run = function (t)
				record()
				t.press("action_two", 2)
				t.wait(0.3)
				stop_recording()

				local expected = math.floor((2 - CONFIG.alt_wind_up) / CONFIG.alt_rate) + 1

				t.expect(#shots >= expected - 1 and #shots <= expected + 1, "%d rounds in 2 seconds, not about %d", #shots, expected)
			end,
		},
		{
			-- The last round comes no later than the time between rounds after the button is let go
			name = "letting go stops the rounds",
			every_hero = true,
			run = function (t)
				for _, mode in ipairs({ "primary", "alt" }) do
					local rate = mode == "alt" and CONFIG.alt_rate or CONFIG.primary_rate

					record()
					t.press(button_of(mode), 1)

					local released = now(t)

					t.wait(1)
					stop_recording()

					local last = shots[#shots]

					if t.expect(last, "no %s rounds were fired", mode) then
						t.expect(last.time - released <= rate + CONFIG.release_margin, "the last %s round came %.2f s after the button was let go", mode, last.time - released)
					end

					t.wait(1)
				end
			end,
		},
		{
			-- The other button is pressed while a round runs and the first is let go: the barrels slow down to a stop and wind up again,
			-- as in UT, and the other mode fires (about 0.42 s later either way)
			name = "switching modes while firing fires the other mode",
			run = function (t)
				for _, order in ipairs({ { "action_one", "action_two", "alt" }, { "action_two", "action_one", "primary" } }) do
					local first, second, second_mode = unpack(order)

					t.hold(first)
					t.wait(1)
					record()
					t.hold(second)
					t.release(first)
					t.wait(1.5)
					t.release(second)
					stop_recording()

					local switched = 0

					for _, shot in ipairs(shots) do
						if shot.mode == second_mode then
							switched = switched + 1
						end
					end

					t.expect(switched >= 3, "%d %s rounds in 1.5 s after switching to it", switched, second_mode)
					t.wait(1)
				end
			end,
		},
		{
			name = "with no ammo nothing is fired",
			run = function (t)
				set_ammo(t, 1)
				t.press("action_one", 1)
				t.wait(0.5)
				t.expect(t.ammo() == 0, "%s left after the last round, not 0", tostring(t.ammo()))

				record()
				t.press("action_one", 1)
				t.press("action_two", 1)
				t.wait(0.5)
				stop_recording()

				t.expect(#shots == 0, "%d rounds were fired with no ammo", #shots)
			end,
		},
		{
			-- The gun can be put away while a mode fires, and its rounds stop
			name = "the gun can be put away while it fires",
			every_hero = true,
			run = function (t)
				local template = t.wielded()

				t.hold("action_one")
				t.wait(1)
				record()
				t.tap("wield_1")
				t.wait(1)
				t.release("action_one")
				stop_recording()

				t.expect(t.wielded() ~= template, "the gun is still in the hands (%s)", tostring(t.wielded()))
				t.expect(#shots <= 2, "%d rounds came after the gun was put away", #shots)

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

				t.press("action_one", 0.8)
				t.wait(0.5)

				local after = HEALTH_ALIVE[target] and health_extension:current_health() or 0

				t.expect(after < before, "the target was not hurt: %s of %s", tostring(after), tostring(before))
			end,
		},
		{
			-- A round stops at the first enemy it hits, as UT's trace does. The alt fire's tight spread keeps its rounds on the near one.
			name = "a round stops at the first enemy",
			run = function (t)
				local near = t.spawn(runner.target_breed, 3)
				local far = t.spawn(runner.target_breed, 6)

				if not t.expect(near and far, "the targets could not be spawned") then
					return
				end

				t.wait(1)
				t.aim_at(near)

				local near_damage, far_damage = t.track_damage(near), t.track_damage(far)

				t.press("action_two", CONFIG.burst_time)
				t.wait(0.5)

				t.expect(near_damage.total > 0, "the near target was not hurt")
				t.expect(far_damage.total == 0, "the far target, behind the near one, was hurt: %.1f", far_damage.total)
			end,
		},
		{
			name = "an alt fire round does twice the damage of a primary round",
			run = function (t)
				local primary = first_hit(t, CONFIG.plain_breed, "primary")
				local alt = first_hit(t, CONFIG.plain_breed, "alt")

				if t.expect(primary and alt, "a round did not hurt the %s (primary %s, alt %s)", CONFIG.plain_breed, tostring(primary), tostring(alt)) then
					t.log("primary %.2f, alt %.2f", primary, alt)
					t.expect(math.abs(alt / primary - CONFIG.alt_damage_ratio) <= CONFIG.damage_margin, "the alt fire's round did %.2f times the primary's, not %.2f", alt / primary, CONFIG.alt_damage_ratio)
				end
			end,
		},
		{
			name = "a round on the head does the game's head bonus",
			run = function (t)
				local body = first_hit(t, CONFIG.plain_breed, "alt")
				local head = first_hit(t, CONFIG.plain_breed, "alt", true)

				if t.expect(body and head, "a round did not hurt the %s (body %s, head %s)", CONFIG.plain_breed, tostring(body), tostring(head)) then
					t.log("body %.2f, head %.2f", body, head)
					t.expect(math.abs(head / body - CONFIG.headshot_ratio) <= CONFIG.headshot_margin, "a round on the head did %.2f times the body's, not %.2f", head / body, CONFIG.headshot_ratio)
				end
			end,
		},
		{
			name = "primary rounds hurt armoured enemies and monsters by their armour",
			run = function (t)
				check_armour(t, "primary", CONFIG.primary_armour_breeds)
			end,
		},
		{
			name = "alt fire rounds hurt armoured enemies and monsters by their armour",
			run = function (t)
				check_armour(t, "alt", CONFIG.alt_armour_breeds)
			end,
		},
	}
end

local function hero(setting_id, careers)
	local definition = ut.items.weapons[setting_id]

	return { item = definition.key, template = definition.template, careers = careers }
end

-- Saltzpyre's Minigun differs from Kruber's only in its base weapon (the repeater pistol), so only the firing runs for him
runner.add_suite({
	name = "minigun",
	slot = "slot_ranged",
	heroes = {
		hero("minigun", { "es_mercenary", "es_huntsman", "es_knight" }),
		hero("minigun_wh", { "wh_captain", "wh_zealot", "wh_bountyhunter" }),
	},
	scenarios = scenarios(),
})

-- Bots with the Minigun (its attack_meta_data in minigun.lua). A hero can't be a bot and the player at once, so these run in a suite of
-- their own with the player as Sienna, and the bot is Kruber as a Mercenary, with his own mind. The special stands ahead and shoots at the
-- player, who is in the bot's way.
local BOTS = {
	profile = "empire_soldier",
	career = 1,
	behind = -3, -- m
	special = "skaven_ratling_gunner",
	special_distance = 14, -- m
	-- How long the bot has to hurt the special
	fight_time = 30, -- s
}

local minigun = ut.items.weapons.minigun

-- The damage from the Minigun in a record of t.track_damage
local function from_minigun(record)
	local total = 0

	for _, hit in ipairs(record.hits) do
		if hit.source == minigun.key then
			total = total + hit.amount
		end
	end

	return total
end

local function bot_scenarios()
	return {
		{
			-- The bot shoots the special, past the player in its way, and never hurts the player
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

				if not t.expect(t.add_bot(BOTS.profile, BOTS.career, minigun.key, BOTS.behind, nil, true), "the bot could not be added") then
					return
				end

				t.wait_until(function ()
					return from_minigun(damage) > 0
				end, BOTS.fight_time, "the bot to hurt the special")
				t.wait(5)

				t.expect(from_minigun(damage) > 0, "the bot did not hurt the %s with the Minigun in %d s", BOTS.special, BOTS.fight_time)
				t.expect(from_minigun(player_damage) == 0, "the bot's rounds hurt the player %.1f", from_minigun(player_damage))
			end,
		},
	}
end

local shock_rifle = ut.items.weapons.shock_rifle

runner.add_suite({
	name = "minigun_bots",
	item = shock_rifle.key,
	template = shock_rifle.template,
	slot = "slot_ranged",
	careers = { "bw_adept" },
	scenarios = bot_scenarios(),
})
