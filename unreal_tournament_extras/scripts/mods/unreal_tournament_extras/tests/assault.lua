local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The Assault Rifle's in-game tests (see runner.lua). Run them with /ut_test assault. They run in the runner's level, Righteous Stand.

local runner = mod.test_runner
local assault = ut.assault

local CONFIG = {
	-- A round's damage against armour, of its damage against an enemy with none (a Chaos marauder), with this much either way
	-- (assault_rifle.lua's bullet_armor_attack). A Stormvermin is armoured. A Chaos warrior's body is super armour, which takes none,
	-- but for the game's critical bonus: at least half of a round's 8 against an enemy with no armour (about 1.5 was seen).
	plain_breed = "chaos_marauder",
	armoured_breed = "skaven_storm_vermin",
	armoured_share = 0.5,
	armour_margin = 0.1,
	super_armour_breed = "chaos_warrior",
	super_armour_critical_most = 4,
	-- How far ahead the enemies that are shot stand, and how long the button is held for one round (they come 0.088 s apart)
	enemy_distance = 5, -- m
	one_round = 0.05, -- s
	-- An enemy whose shield the repeater's shot breaks (a shielded clan rat's), which stops the rounds
	shield_breed = "skaven_clan_rat_with_shield",
	-- A grenade thrown at an enemy this far ahead goes off on it before it touches anything else, so well before the 2 s timer
	grenade_enemy_distance = 4, -- m
	grenade_touch_time = 1, -- s
	-- The most the grenade's explosion hurts the player who threw it (grenade_self_damage), how long one thrown at the floor takes to go
	-- off at most (2 s after it first touches the floor), and how long before it goes off the player is put where it lies
	grenade_self_damage = 7,
	grenade_feet_wait = 3.5, -- s
	grenade_move_before = 0.3, -- s
}

-- The key of the rifle in the melee slot
local function rifle_key(t)
	return t.on_main_thread(function ()
		local slot_data = ScriptUnit.extension(t.unit(), "inventory_system"):get_slot_data("slot_melee")

		return slot_data and slot_data.item_data and slot_data.item_data.name
	end)
end

-- The first hit of one round on an enemy of a breed, enemy_distance ahead, aimed at its middle. A hit on the head is passed over.
-- Returns the damage, and the record of all the hits.
local function round_damage(t, breed_name)
	t.go_to_start()

	local enemy = t.spawn(breed_name, CONFIG.enemy_distance)

	if not t.expect(enemy, "the %s could not be spawned", breed_name) then
		return nil
	end

	t.wait(1)
	t.aim_at(enemy)

	local damage = t.track_damage(enemy)

	t.press("action_one", CONFIG.one_round)
	t.wait(0.5)
	t.remove(enemy)
	t.wait(0.5)

	for _, hit in ipairs(damage.hits) do
		if hit.zone ~= "head" then
			return hit.amount, damage
		end
	end

	return nil, damage
end

-- The rounds and the grenade explosions that are made while a test runs, and the time of the player's last round
local rounds = 0
local explosions = 0
local recording = false
local last_round

ut.assault_round_callbacks.ut_test = function (owner_unit)
	if recording and Managers.player:local_player().player_unit == owner_unit then
		rounds = rounds + 1
		last_round = Managers.time:time("game")
	end
end

ut.any_explosion_callbacks.ut_test_assault = function (explosion_template)
	if recording and explosion_template.name == assault.explosion then
		explosions = explosions + 1
	end
end

-- The third person animation events of the player's weapon actions while a test records them: { { event, time } }
local anim_events = {}

local function record_anim(owner_unit, event)
	if recording and Managers.player:local_player().player_unit == owner_unit then
		anim_events[#anim_events + 1] = { event = event, time = Managers.time:time("game") }
	end
end

mod:hook_safe(WeaponUnitExtension, "_play_3p_anim", function (self, event_3p, event, owner_unit)
	record_anim(owner_unit, event_3p)
end)

mod:hook_safe(WeaponUnitExtension, "_play_end_event_3p", function (self, event)
	record_anim(self.owner_unit, event)
end)

local function start_recording()
	table.clear(anim_events)

	rounds = 0
	explosions = 0
	last_round = nil
	recording = true
end

-- The events of the stance on the wielded copy: its take, its leave, and the grenade's shot (assault_rifle.lua's VARIANTS)
local function stance_events(t)
	local actions = Weapons[ut.utils.wielded_template_name(t.unit())].actions

	return {
		take = actions.action_one.default.anim_event_3p,
		leave = actions.action_one.default.anim_end_event_3p,
		shot = actions.action_two.ut_assault_throw.anim_event_3p,
	}
end

-- The recorded events of one name: their times
local function times_of(event)
	local times = {}

	for _, entry in ipairs(anim_events) do
		if entry.event == event then
			times[#times + 1] = entry.time
		end
	end

	return times
end

-- How far a stance's leave may be from when it is due
local STANCE_TOLERANCE = 0.15 -- s

local function scenarios()
	return {
		{
			-- A weapon of the melee slot: the rounds are endless, so it has no ammo
			name = "is in the melee slot, with no ammo",
			every_hero = true,
			run = function (t)
				local result = t.on_main_thread(function ()
					local inventory_extension = ScriptUnit.extension(t.unit(), "inventory_system")
					local slot_data = inventory_extension:get_slot_data("slot_melee")
					local unit = slot_data and (slot_data.right_unit_1p or slot_data.left_unit_1p)

					return {
						item = slot_data and slot_data.item_data and slot_data.item_data.name,
						ammo = unit and ScriptUnit.has_extension(unit, "ammo_system") ~= nil,
					}
				end)

				local rifles = {
					[ut.items.weapons.assault_rifle.key] = true,
					[ut.items.weapons.assault_rifle_dr.key] = true,
				}

				t.expect(rifles[result.item], "the melee slot holds %s", tostring(result.item))
				t.expect(not result.ammo, "the rifle has ammo")
			end,
		},
		{
			name = "fire rate",
			basic = true,
			run = function (t)
				start_recording()

				-- Held for a second, the two rifles fire about 1 / 0.088 rounds
				t.press("action_one", 1)
				t.wait(0.2)

				recording = false

				t.expect(rounds >= 10 and rounds <= 13, "%d rounds in a second, not 11 or so", rounds)
			end,
		},
		{
			-- A round hits at once, with the rifle's damage: it fires none of the game's projectiles (the pistols' shot does, with its
			-- tracer), and every hit on the enemy is the round's (ut_assault_bullet's damage type)
			name = "a round hits at once, with the rifle's damage",
			every_hero = true,
			run = function (t)
				local enemy = t.spawn("chaos_marauder", 6)

				if not t.expect(enemy, "the enemy could not be spawned") then
					return
				end

				t.wait(1)
				t.aim_at(enemy)

				local damage = t.track_damage(enemy)
				local projectiles = 0

				t.press("action_one", 0.3, function ()
					projectiles = math.max(projectiles, #t.projectiles(function ()
						return true
					end))
				end)
				t.wait(0.5)

				local others = 0

				for _, hit in ipairs(damage.hits) do
					if hit.type ~= "shot_shotgun" then
						others = others + 1
					end
				end

				t.expect(projectiles == 0, "%d projectiles flew", projectiles)
				t.expect(#damage.hits > 0, "the rounds did not hurt the enemy")
				t.expect(others == 0, "%d of %d hits were not the round's", others, #damage.hits)
			end,
		},
		{
			-- AssaultRifle.ChargeBar: the grenade's charge fills the bar over the time its speed takes to reach its most (1 s)
			name = "the grenade's charge fills the charge bar",
			every_hero = true,
			run = function (t)
				local charge_of = ut.charge_bars[ut.utils.wielded_template_name(t.unit())]
				local fraction

				t.hold("action_two")
				t.wait(0.5)

				fraction = charge_of(t.unit()).fraction

				t.release("action_two")
				t.wait(1)

				t.expect(math.abs(fraction - 0.5) < 0.15, "the bar was %.2f full after 0.5 s, not 0.5", fraction)
				t.expect(charge_of(t.unit()).fraction == 0, "the bar is not empty once the grenade is thrown")
			end,
		},
		{
			name = "grenade",
			every_hero = true,
			run = function (t)
				-- (the grenade of the scenario before, the charge bar's, may still be about to go off)
				t.wait_until(function ()
					return #assault.grenades == 0
				end, 10, "the grenades in flight to go off")

				local before = assault.grenade_count

				start_recording()

				-- A grenade lobbed ahead bounces and goes off two seconds after it first touches something
				t.press("action_two", 0.3)
				t.wait(5)

				recording = false

				t.expect(assault.grenade_count == before - 1, "the grenade count went from %d to %d, not down by 1", before, assault.grenade_count)
				t.expect(explosions == 1, "%d grenades went off, not 1", explosions)
			end,
		},
		{
			-- The characters take the stance of the base's alt attack with the first round, keep it while the rounds go on, and leave it
			-- stance_linger after the last, once the round has chained into the stance (a round's own time, and half the chain margin)
			name = "the rounds take the stance once and leave it after the last",
			every_hero = true,
			run = function (t)
				local events = stance_events(t)

				t.wait(1.5)
				start_recording()
				t.press("action_one", 0.5)
				t.wait(1.2)

				recording = false

				local takes, leaves, shots = times_of(events.take), times_of(events.leave), times_of(events.shot)

				t.expect(rounds > 0, "no round was fired")
				t.expect(#takes == 1, "the stance (%s) was taken %d times, not once", events.take, #takes)
				t.expect(#shots == 0, "the grenade's shot (%s) played %d times", events.shot, #shots)

				if t.expect(#leaves == 1 and last_round, "the stance was left (%s) %d times, not once", events.leave, #leaves) then
					local due = assault.stance_linger + assault.fire_rate

					t.log("left %.2f s after the last round", leaves[1] - last_round)
					t.expect(math.abs(leaves[1] - last_round - due) < STANCE_TOLERANCE, "the stance was left %.2f s after the last round, not %.2f", leaves[1] - last_round, due)
				end
			end,
		},
		{
			-- The charge takes the stance, the throw plays the shot from it, which leaves it, and the stance is taken again once the shot has
			-- played. It is left the grenade's fire rate and half a second after the throw.
			name = "the grenade's charge takes the stance, and the throw takes it again after its shot",
			every_hero = true,
			run = function (t)
				local events = stance_events(t)

				t.wait(1.5)
				start_recording()
				t.hold("action_two")
				t.wait(0.5)
				t.release("action_two")

				local released = Managers.time:time("game")

				t.wait(2.2)

				recording = false

				local takes, leaves, shots = times_of(events.take), times_of(events.leave), times_of(events.shot)

				t.expect(#takes == 2, "the stance (%s) was taken %d times, not twice", events.take, #takes)
				t.expect(#shots == 1, "the grenade's shot (%s) played %d times, not once", events.shot, #shots)

				if #shots == 1 then
					t.expect(math.abs(shots[1] - released) < STANCE_TOLERANCE, "the shot played %.2f s after the release", shots[1] - released)
				end

				if #takes == 2 then
					t.expect(takes[2] > released, "the stance was not taken again after the throw")
				end

				if t.expect(#leaves == 1, "the stance was left (%s) %d times, not once", events.leave, #leaves) then
					local due = assault.stance_linger_after_throw

					t.log("left %.2f s after the throw", leaves[1] - released)
					t.expect(math.abs(leaves[1] - released - due) < STANCE_TOLERANCE, "the stance was left %.2f s after the throw, not %.2f", leaves[1] - released, due)
				end
			end,
		},
		{
			-- The characters' shot animation finds no weapon unit to play the pistols' own muzzle flash and sound on (the skin draws UT's)
			name = "the pistols' own third person shot is not played",
			every_hero = true,
			run = function (t)
				local hidden = t.on_main_thread(function ()
					local result = flow_query_wielded_weapon({ player_unit = t.unit() })
					local null_reference = Unit.null_reference()

					return result ~= nil and result.righthandweapon3p == null_reference and result.lefthandweapon3p == null_reference
				end)

				t.expect(hidden, "the characters' flow still gets the pistols' units")
			end,
		},
		{
			-- The game refuses a pickup of ammo while the ammo is full. With all the other weapons' ammo but a grenade missing, it is not
			-- full, and the pickup gives the grenades back.
			name = "with all the other ammo, a pickup of ammo gives back the grenades",
			every_hero = true,
			run = function (t)
				-- (all the other weapons' ammo first)
				t.on_main_thread(function ()
					ScriptUnit.extension(t.unit(), "inventory_system"):add_ammo_from_pickup(Pickups.ammo.all_ammo)
				end)
				t.wait(1)
				t.press("action_two", 0.3)
				t.wait(1)

				local missing = t.on_main_thread(function ()
					local inventory_extension = ScriptUnit.extension(t.unit(), "inventory_system")
					local rounds_full = true

					for _, slot_data in pairs(inventory_extension:equipment().slots) do
						local unit = slot_data.right_unit_1p or slot_data.left_unit_1p
						local ammo_extension = unit and ScriptUnit.has_extension(unit, "ammo_system")

						if ammo_extension and not ammo_extension:full_ammo() then
							rounds_full = false
						end
					end

					return { rounds_full, inventory_extension:has_full_ammo() }
				end)

				t.expect(assault.grenade_count < assault.max_grenades, "no grenade was thrown")
				t.expect(missing[1], "the other weapons' ammo is not full")
				t.expect(not missing[2], "the ammo is full with %d of %d grenades", assault.grenade_count, assault.max_grenades)

				t.on_main_thread(function ()
					ScriptUnit.extension(t.unit(), "inventory_system"):add_ammo_from_pickup(Pickups.ammo.all_ammo)
				end)

				t.expect(assault.grenade_count == assault.max_grenades, "the pickup left %d of %d grenades", assault.grenade_count, assault.max_grenades)
			end,
		},
		{
			-- The game's own refill of the other slots is kept while the rifles are in the hands
			name = "a pickup of ammo fills the ranged weapon while the rifles are held",
			run = function (t)
				local before = t.on_main_thread(function ()
					local slot_data = ScriptUnit.extension(t.unit(), "inventory_system"):get_slot_data("slot_ranged")
					local ammo_extension = slot_data and GearUtils.get_ammo_extension(slot_data.right_unit_1p, slot_data.left_unit_1p)

					if not ammo_extension or ammo_extension:infinite_ammo() then
						return nil
					end

					ammo_extension:use_ammo(math.ceil(ammo_extension:ammo_count() / 2))

					return true
				end)

				if not before then
					t.skip("the ranged weapon has no ammo")
				end

				t.wait(0.5)

				local result = t.on_main_thread(function ()
					local inventory_extension = ScriptUnit.extension(t.unit(), "inventory_system")
					local slot_data = inventory_extension:get_slot_data("slot_ranged")
					local ammo_extension = GearUtils.get_ammo_extension(slot_data.right_unit_1p, slot_data.left_unit_1p)
					local used = ammo_extension:total_remaining_ammo()

					inventory_extension:add_ammo_from_pickup(Pickups.ammo.all_ammo)

					return {
						used = used,
						after = ammo_extension:total_remaining_ammo(),
						max = ammo_extension:max_ammo(),
						wielded = inventory_extension:get_wielded_slot_name(),
					}
				end)

				t.log("the ranged weapon had %d of %d, and %d after the pickup", result.used, result.max, result.after)
				t.expect(result.wielded == "slot_melee", "the rifles are not in the hands (%s)", tostring(result.wielded))
				t.expect(result.used < result.max, "no ammo was used")
				t.expect(result.after == result.max, "the pickup left the ranged weapon at %d of %d", result.after, result.max)
			end,
		},
		{
			name = "rounds hurt armoured enemies by their armour",
			run = function (t)
				t.critical_hits(false)

				local key = rifle_key(t)
				local plain = round_damage(t, CONFIG.plain_breed)

				if not t.expect(plain and plain > 0, "a round did not hurt the %s", CONFIG.plain_breed) then
					return
				end

				local armoured = round_damage(t, CONFIG.armoured_breed)

				if t.expect(armoured, "a round did not hurt the %s", CONFIG.armoured_breed) then
					local share = (armoured / t.power_against(CONFIG.armoured_breed, key)) / (plain / t.power_against(CONFIG.plain_breed, key))

					t.log("%s %.2f, %s %.2f: %.2f", CONFIG.plain_breed, plain, CONFIG.armoured_breed, armoured, share)
					t.expect(math.abs(share - CONFIG.armoured_share) <= CONFIG.armour_margin, "a round did %.2f of its damage to the %s, not %.2f", share, CONFIG.armoured_breed, CONFIG.armoured_share)
				end
			end,
		},
		{
			-- The rounds only stagger super armour. A critical one does a little: the game's critical bonus is at least half of what the hit
			-- does to an enemy with no armour, whatever the armour.
			name = "rounds don't hurt super armour, and critical ones only a little",
			run = function (t)
				for _, critical in ipairs({ false, true }) do
					t.critical_hits(critical)
					start_recording()

					local damage, record = round_damage(t, CONFIG.super_armour_breed)
					local most = critical and CONFIG.super_armour_critical_most or 0

					recording = false

					t.log("%s: %d rounds, %d hits, the first on the body %s", critical and "critical" or "plain", rounds, record and #record.hits or 0, tostring(damage))
					t.expect(rounds > 0, "no round was fired")
					t.expect((damage or 0) <= most, "a %s round did %.1f to the %s's body, more than %.1f", critical and "critical" or "plain", damage or 0, CONFIG.super_armour_breed, most)
				end
			end,
		},
		{
			-- A shield blocks the rounds, and they don't break it (the repeater's shot does)
			name = "a raised shield stops the rounds",
			run = function (t)
				local enemy = t.spawn(CONFIG.shield_breed, CONFIG.enemy_distance)

				if not t.expect(enemy, "the %s could not be spawned", CONFIG.shield_breed) then
					return
				end

				t.raise_shield(enemy)
				t.wait(1)
				t.aim_at(enemy)

				local damage = t.track_damage(enemy)

				t.press("action_one", CONFIG.one_round)
				t.wait(0.5)

				t.expect(not t.shield_broken(enemy), "the round broke the %s's shield", CONFIG.shield_breed)
				t.expect(damage.total == 0, "the round hurt the %s through its shield (%.1f)", CONFIG.shield_breed, damage.total)
			end,
		},
		{
			-- A grenade goes off as it touches an enemy (Grenade.ProcessTouch): a sphere of utils.UT_PROJECTILE_RADIUS on the enemy's body
			name = "a grenade thrown at an enemy goes off on it",
			run = function (t)
				t.wait_until(function ()
					return #assault.grenades == 0
				end, 10, "the grenades in flight to go off")

				local key = rifle_key(t)
				local enemy = t.spawn(CONFIG.plain_breed, CONFIG.grenade_enemy_distance)

				if not t.expect(enemy, "the %s could not be spawned", CONFIG.plain_breed) then
					return
				end

				t.wait(1)
				t.aim_at(enemy)

				local damage = t.track_damage(enemy)

				start_recording()
				t.press("action_two", CONFIG.one_round)
				t.wait(CONFIG.grenade_touch_time)

				recording = false

				local from_grenade = 0

				for _, hit in ipairs(damage.hits) do
					if hit.source == key then
						from_grenade = from_grenade + hit.amount
					end
				end

				t.expect(explosions == 1, "%d grenades went off within %.1f s, not 1", explosions, CONFIG.grenade_touch_time)
				t.expect(from_grenade > 0, "the grenade did not hurt the %s", CONFIG.plain_breed)
			end,
		},
		{
			-- The grenade's explosion hurts the player who threw it, far less than the Rocket Launcher's
			name = "a grenade that goes off at the feet hurts the player, at most 7",
			run = function (t)
				t.wait_until(function ()
					return #assault.grenades == 0
				end, 10, "the grenades in flight to go off")

				local key = rifle_key(t)

				t.hurtable(true)
				t.look(-89)

				local taken = t.track_damage(t.unit())
				local where = t.explosions()

				start_recording()
				t.press("action_two", CONFIG.one_round)

				-- The view can't look straight down, so the grenade bounces off ahead. The player is put where it lies just before it goes off.
				t.wait_until(function ()
					return #assault.grenades > 0
				end, 1, "the grenade to be thrown")

				local grenade = assault.grenades[#assault.grenades]

				if t.expect(grenade, "no grenade was thrown") then
					t.wait_until(function ()
						return grenade.exploded or grenade.timer and grenade.timer <= CONFIG.grenade_move_before
					end, CONFIG.grenade_feet_wait, "the grenade to be about to go off")
					t.on_main_thread(function ()
						if not grenade.exploded then
							runner.move_player(t.unit(), grenade.position:unbox())
						end
					end)
				end

				t.wait(1)

				recording = false

				local own = 0
				local hits = {}

				for _, hit in ipairs(taken.hits) do
					hits[#hits + 1] = string.format("%.1f %s %s", hit.amount, tostring(hit.source), tostring(hit.type))

					if hit.source == key then
						own = own + hit.amount
					end
				end

				local x, y, z = t.position()

				for i, name in ipairs(where) do
					local position = where.positions[i]

					t.log("%s %.2f m from the feet", name, math.sqrt((position[1] - x) ^ 2 + (position[2] - y) ^ 2 + (position[3] - z) ^ 2))
				end

				t.log("the grenade hurt the player %.1f (%s; all hits: %s)", own, tostring(key), table.concat(hits, ", "))
				t.expect(explosions == 1, "%d grenades went off, not 1", explosions)
				t.expect(own > 0, "the grenade's explosion did not hurt the player")
				t.expect(own <= CONFIG.grenade_self_damage + 0.5, "the grenade's explosion hurt the player %.1f, more than %d", own, CONFIG.grenade_self_damage)
			end,
		},
	}
end

local function hero(setting_id, careers)
	local definition = ut.items.weapons[setting_id]

	return { item = definition.key, template = definition.template, careers = careers }
end

-- Victor's copy is on the Brace of Pistols and Bardin's on the Drakefire Pistols. Each plays its own base's stance, so the scenarios
-- run for both.
runner.add_suite({
	name = "assault",
	slot = "slot_melee",
	heroes = {
		hero("assault_rifle", { "wh_captain", "wh_zealot", "wh_bountyhunter" }),
		hero("assault_rifle_dr", { "dr_ironbreaker", "dr_ranger", "dr_engineer" }),
	},
	scenarios = scenarios(),
})

-- Bots with the Assault Rifle (its attack_meta_data in assault_rifle.lua), which is their melee weapon: they fire it at an enemy up close,
-- and at one further off from where they stand, and they revive the player with it in hand.
-- A hero can't be a bot and the player at once, so these run in a suite of their own with the player as Sienna, and the bots are Victor as
-- a Captain and Bardin as an Ironbreaker, with their own minds. The enemy stands ahead and comes at them, and the player stands aside,
-- out of the bot's way.
local BOTS = {
	behind = -3, -- m
	player_aside = 3, -- m to the right
	enemy = "chaos_marauder",
	enemy_distance = 3, -- m
	-- How long the bot has to hurt the enemy
	fight_time = 30, -- s
	-- An enemy this far ahead is within the bot's range (assault_rifle.lua's bot_range), and the bot fires from where it stands: it
	-- moves less than stand_still before its rounds first hurt the enemy, where it used to walk up to it
	far_enemy_distance = 9, -- m
	stand_still = 2, -- m
	-- How long the bot has to revive the player who is down
	revive_time = 20, -- s
}

-- The damage from an item in a record of t.track_damage
local function from_item(record, item_key)
	local total = 0

	for _, hit in ipairs(record.hits) do
		if hit.source == item_key then
			total = total + hit.amount
		end
	end

	return total
end

-- The rounds each character fired while a bot test records
local rounds_by = {}
local recording_bots = false

ut.assault_round_callbacks.ut_test_bots = function (owner_unit)
	if recording_bots then
		rounds_by[owner_unit] = (rounds_by[owner_unit] or 0) + 1
	end
end

-- Watches every frame whether a bot's rifles start a grenade's charge, which a bot never should: it doesn't throw grenades, and a bot
-- that charged one stood charging it (the rifle's block button is the charge). Returns { charged }, which is set once one starts.
local function watch_charges(bot)
	local seen = { charged = false }

	runner.frame_watchers[#runner.frame_watchers + 1] = function ()
		local inventory_extension = Unit.alive(bot) and ScriptUnit.has_extension(bot, "inventory_system")
		local equipment = inventory_extension and inventory_extension:equipment()

		if not equipment then
			return
		end

		for _, key in ipairs({ "right_hand_wielded_unit", "left_hand_wielded_unit" }) do
			local weapon_unit = equipment[key]
			local weapon_extension = weapon_unit and Unit.alive(weapon_unit) and ScriptUnit.has_extension(weapon_unit, "weapon_system")
			local action = weapon_extension and weapon_extension.current_action_settings

			if action and action.ut_assault_charge then
				seen.charged = true
			end
		end
	end

	return seen
end

-- The bot shoots the enemy with the rifle up close, never hurts the player, and never charges a grenade
local function bot_scenario(profile, career, setting_id)
	local item_key = ut.items.weapons[setting_id].key

	return {
		name = string.format("a bot (%s) shoots enemies up close with it", profile),
		run = function (t)
			t.hurtable(true)

			local enemy = t.spawn(BOTS.enemy, BOTS.enemy_distance)

			if not t.expect(enemy, "the %s could not be spawned", BOTS.enemy) then
				return
			end

			local aside = t.ground_at(0, BOTS.player_aside)

			if not t.expect(aside, "there is no ground beside the player") then
				return
			end

			-- (a bot fights an enemy only once it has been seen, which a calm one never is)
			t.on_main_thread(function ()
				runner.provoke(enemy)
			end)

			local damage = t.track_damage(enemy)
			local player_damage = t.track_damage(t.unit())
			local bot = t.add_bot(profile, career, item_key, BOTS.behind, "slot_melee", true)

			if not t.expect(bot, "the bot could not be added") then
				return
			end

			local charges = watch_charges(bot)

			t.on_main_thread(function ()
				runner.move_player(t.unit(), Vector3(aside[1], aside[2], aside[3]))
			end)

			table.clear(rounds_by)

			recording_bots = true

			t.wait_until(function ()
				return from_item(damage, item_key) > 0
			end, BOTS.fight_time, "the bot to hurt the enemy")
			t.wait(5)

			recording_bots = false

			t.log("the bot fired %d rounds", rounds_by[bot] or 0)
			t.expect((rounds_by[bot] or 0) > 0, "the bot fired no rounds the skin was told of")
			t.expect(from_item(damage, item_key) > 0, "the bot did not hurt the %s with the rifle in %d s", BOTS.enemy, BOTS.fight_time)
			t.expect(from_item(player_damage, item_key) == 0, "the bot's rounds hurt the player %.1f", from_item(player_damage, item_key))
			t.expect(not charges.charged, "the bot charged a grenade")
		end,
	}
end

-- Where a unit stands, as { x, y, z }
local function position_of(t, unit)
	return t.on_main_thread(function ()
		local position = Unit.alive(unit) and POSITION_LOOKUP[unit]

		return position and { Vector3.x(position), Vector3.y(position), Vector3.z(position) }
	end)
end

-- The bot fires at an enemy further off from where it stands, and doesn't walk up to it
local function bot_range_scenario(profile, career, setting_id)
	local item_key = ut.items.weapons[setting_id].key

	return {
		name = string.format("a bot (%s) fires at an enemy %d m off from where it stands", profile, BOTS.far_enemy_distance),
		run = function (t)
			t.hurtable(true)

			local aside = t.ground_at(0, BOTS.player_aside)

			if not t.expect(aside, "there is no ground beside the player") then
				return
			end

			local bot = t.add_bot(profile, career, item_key, BOTS.behind, "slot_melee", true)

			if not t.expect(bot, "the bot could not be added") then
				return
			end

			t.on_main_thread(function ()
				runner.move_player(t.unit(), Vector3(aside[1], aside[2], aside[3]))
			end)

			local enemy = t.spawn(BOTS.enemy, BOTS.far_enemy_distance)

			if not t.expect(enemy, "the %s could not be spawned", BOTS.enemy) then
				return
			end

			local start = position_of(t, bot)
			local damage = t.track_damage(enemy)
			local charges = watch_charges(bot)

			-- (a bot fights an enemy only once it has been seen, which a calm one never is)
			t.on_main_thread(function ()
				runner.provoke(enemy)
			end)

			local hurt = t.wait_until(function ()
				return from_item(damage, item_key) > 0
			end, BOTS.fight_time, "the bot to hurt the enemy")

			local now = position_of(t, bot)

			if not t.expect(hurt, "the bot did not hurt the %s with the rifle in %d s", BOTS.enemy, BOTS.fight_time) or not (start and now) then
				return
			end

			local moved = math.sqrt((now[1] - start[1]) ^ 2 + (now[2] - start[2]) ^ 2)

			t.log("the bot moved %.1f m before its rounds first hurt the enemy", moved)
			t.expect(moved < BOTS.stand_still, "the bot moved %.1f m before it hurt the enemy, at most %.1f", moved, BOTS.stand_still)
			t.expect(not charges.charged, "the bot charged a grenade")
		end,
	}
end

-- The bot revives the player who is down. The game's bots block while they revive, and wait until they block: the rifle's block
-- button charges a grenade, and a bot used to stand charging it (assault_rifle.lua's BTBotInteractAction hook).
local function bot_revive_scenario(profile, career, setting_id)
	local item_key = ut.items.weapons[setting_id].key

	return {
		name = string.format("a bot (%s) revives the player who is down", profile),
		run = function (t)
			local bot = t.add_bot(profile, career, item_key, BOTS.behind, "slot_melee", true)

			if not t.expect(bot, "the bot could not be added") then
				return
			end

			local charges = watch_charges(bot)

			if not t.expect(t.knock_down(item_key), "the player was not knocked down") then
				return
			end

			-- (the condition runs in the update, on the main thread)
			local revived = t.wait_until(function ()
				local unit = t.unit()
				local status_extension = unit and ScriptUnit.has_extension(unit, "status_system")

				return status_extension ~= nil and not status_extension:is_knocked_down()
			end, BOTS.revive_time, "the bot to revive the player")

			t.expect(revived, "the bot did not revive the player in %d s", BOTS.revive_time)
			t.expect(not charges.charged, "the bot charged a grenade while it revived the player")

			-- (the player is stood up for the next scenario if the bot didn't)
			t.revive()
		end,
	}
end

local shock_rifle = ut.items.weapons.shock_rifle

runner.add_suite({
	name = "assault_bots",
	item = shock_rifle.key,
	template = shock_rifle.template,
	slot = "slot_ranged",
	careers = { "bw_adept" },
	scenarios = {
		bot_scenario("witch_hunter", 1, "assault_rifle"),
		bot_scenario("dwarf_ranger", 1, "assault_rifle_dr"),
		bot_range_scenario("witch_hunter", 1, "assault_rifle"),
		bot_range_scenario("dwarf_ranger", 1, "assault_rifle_dr"),
		bot_revive_scenario("witch_hunter", 1, "assault_rifle"),
		bot_revive_scenario("dwarf_ranger", 1, "assault_rifle_dr"),
	},
})
