local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The Assault Rifle's in-game tests (see runner.lua). Run them with /ut_test assault. They run in the runner's level, Righteous Stand.

local runner = mod.test_runner
local assault = ut.assault

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

-- Bots with the Assault Rifle (its attack_meta_data in assault_rifle.lua), which is their melee weapon: they fire it at an enemy up close.
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

-- The bot shoots the enemy with the rifle up close, and never hurts the player
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
	},
})
