local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The Sniper Rifle's in-game tests (see runner.lua), for Kruber's and Bardin's. Run them with /ut_test sniper. They run in the runner's
-- level, Righteous Stand.

local runner = mod.test_runner

local CONFIG = {
	-- The shot's damage against armour and monsters, of its damage against an enemy with none (a Chaos marauder), with this much either
	-- way (sniper_rifle.lua's ut_sniper_bullet). A Stormvermin is armoured, a rat ogre is a monster and a boss, whose damage the game
	-- takes down to 0.45 (DamageUtils.calculate_damage's boss_damage_reduction), and a Chaos warrior's body is super armour.
	plain_breed = "chaos_marauder",
	armour_breeds = {
		{ "skaven_storm_vermin", 0.8 },
		{ "skaven_rat_ogre", 1.5 * 0.45 },
		{ "chaos_warrior", 0.6 },
	},
	armour_margin = 0.1,
	super_armour_breed = "chaos_warrior",
	-- How far ahead the enemies that are shot stand, and the second of two in a line
	enemy_distance = 6, -- m
	behind_distance = 9, -- m
	-- More than the time between shots, so each shot is made at once
	between_shots = 1.5, -- s
	-- The bot that fires at the player, for the tracer: Bardin as a Ranger, this far ahead
	bot_profile = "dwarf_ranger",
	bot_career = 1,
	bot_distance = 8, -- m
}

-- Records the shots that happen while a test runs: when, and whether they hit something
local shots = {}

ut.sniper.shot_callbacks.ut_test = function (owner_unit, hit_position)
	if mod.test_recording then
		shots[#shots + 1] = {
			hit = hit_position ~= nil,
			hit_position = hit_position and Vector3Box(hit_position),
			owner_unit = owner_unit,
			time = Managers.time:time("game"),
		}
	end
end

local function start_recording()
	table.clear(shots)

	mod.test_recording = true
end

local function stop_recording()
	mod.test_recording = nil
end

-- The damage of a shot at an enemy's middle, standing ahead of the player
local function shot_damage_to(t, breed_name)
	t.go_to_start()

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
	t.wait(CONFIG.between_shots)

	return damage.total
end

local function scenarios()
	return {
		{
			name = "has ammo",
			run = function (t)
				local ammo = t.ammo()

				-- (some careers' talents give more ammo, as they do for every ranged weapon)
				t.expect(ammo ~= nil, "the weapon has no ammo extension")
				t.expect(ammo and ammo >= 30, "the weapon has %s ammo, not 30 or more", tostring(ammo))
			end,
		},
		{
			name = "fire",
			every_hero = true,
			basic = true,
			run = function (t)
				local before = t.ammo()

				start_recording()
				t.press("action_one", 0.1)
				t.wait(0.5)
				stop_recording()

				t.expect(#shots == 1, "%d shots were made, not 1", #shots)
				t.expect(before - (t.ammo() or 0) == 1, "the shot used %s ammo, not 1", tostring(before - (t.ammo() or 0)))
			end,
		},
		{
			-- Where the shot is told to have hit (for the sparks and the sound) is on the target it was aimed at
			name = "the hit is on the target",
			every_hero = true,
			run = function (t)
				local target = t.spawn_target(5)

				if not t.expect(target, "the target could not be spawned") then
					return
				end

				-- (the spine is taken before the shot, as a kill throws the body)
				local spine = t.on_main_thread(function ()
					local position = Unit.world_position(target, Unit.node(target, "j_spine"))

					return { Vector3.x(position), Vector3.y(position), Vector3.z(position) }
				end)

				start_recording()
				t.press("action_one", 0.1)
				t.wait(0.5)
				stop_recording()

				if not t.expect(shots[1] and shots[1].hit, "the shot hit nothing") then
					return
				end

				local distance, from_eye = unpack(t.on_main_thread(function ()
					local hit = shots[1].hit_position:unbox()
					local first_person_extension = ScriptUnit.extension(t.unit(), "first_person_system")

					return { Vector3.distance(hit, Vector3(spine[1], spine[2], spine[3])), Vector3.distance(hit, first_person_extension:current_position()) }
				end))

				t.log("the hit is %.2f m from the target's spine and %.2f m from the eye", distance, from_eye)
				t.expect(distance < 1, "the hit is %.2f m from the target", distance)
			end,
		},
		{
			name = "fire rate",
			run = function (t)
				-- Holding the button repeats the shot every 1.33 seconds: shots at 0, 1.33, 2.66, 3.99 and 5.32
				start_recording()
				t.press("action_one", 6)
				t.wait(0.5)
				stop_recording()

				local times = {}

				for _, shot in ipairs(shots) do
					times[#times + 1] = string.format("%.2f", shot.time - shots[1].time)
				end

				t.expect(#shots == 5, "%d shots were made in 6.5 seconds, not 5 (at %s)", #shots, table.concat(times, ", "))
			end,
		},
		{
			name = "no reload",
			run = function (t)
				local before = t.ammo()

				t.press("action_one", 0.1)
				t.wait(1.5)
				t.press("action_one", 0.1)
				t.wait(1.5)

				t.expect(before - (t.ammo() or 0) == 2, "two shots used %s ammo", tostring(before - (t.ammo() or 0)))
			end,
		},
		{
			name = "zoom",
			run = function (t)
				local zoom = ut.zoom

				t.expect(not zoom.zoomed, "the weapon starts zoomed")

				-- Holding the button zooms in, and letting go keeps the zoom
				t.press("action_two", 0.5)
				t.wait(0.2)

				t.expect(zoom.zoomed, "the weapon did not zoom")
				t.expect(zoom.magnification() > 2, "the magnification is only %.2f after half a second", zoom.magnification())

				-- Pressing it again zooms out
				t.press("action_two", 0.1)
				t.wait(0.2)

				t.expect(not zoom.zoomed, "the weapon did not zoom out")
			end,
		},
		{
			-- A hit on the head does twice the damage of a hit on the body (HeadShotDamageMult), or more with a career's talents
			name = "head shots do double damage",
			run = function (t)
				-- The smallest of three shots each, which leaves out critical hits
				local body, head = math.huge, math.huge

				for _ = 1, 3 do
					body = math.min(body, t.shot_damage(false) or math.huge)
					t.wait(1)
					head = math.min(head, t.shot_damage(true) or math.huge)
					t.wait(1)
				end

				if body == math.huge or head == math.huge then
					return
				end

				t.log("a shot to the body did %.1f, to the head %.1f", body, head)
				t.expect(body > 0, "the shot to the body did no damage")
				t.expect(head >= body * 1.8, "the shot to the head did %.1f, not twice the %.1f of the body", head, body)
			end,
		},
		{
			name = "a shot hurts armoured enemies, monsters and super armour by their armour",
			run = function (t)
				t.critical_hits(false)

				local plain = shot_damage_to(t, CONFIG.plain_breed)

				if not t.expect(plain and plain > 0, "the shot did not hurt the %s", CONFIG.plain_breed) then
					return
				end

				local definition = ut.items.weapons.sniper_rifle

				plain = plain / t.power_against(CONFIG.plain_breed, definition.key)

				for _, entry in ipairs(CONFIG.armour_breeds) do
					local breed_name, share = entry[1], entry[2]
					local damage = shot_damage_to(t, breed_name)

					if t.expect(damage, "the %s could not be shot", breed_name) then
						local power = t.power_against(breed_name, definition.key)

						damage = damage / power
						t.log("%s: %.1f at %.2f power, %.2f of the marauder's %.1f", breed_name, damage, power, damage / plain, plain)
						t.expect(math.abs(damage / plain - share) <= CONFIG.armour_margin, "the shot did %.2f of its damage to the %s, not %.2f", damage / plain, breed_name, share)
					end
				end
			end,
		},
		{
			-- A critical hit has armour multipliers of its own, the handgun's, which also hurt super armour (0.6)
			name = "a critical shot hurts super armour",
			run = function (t)
				t.critical_hits(true)

				local damage = shot_damage_to(t, CONFIG.super_armour_breed)

				t.log("a critical shot did %.1f to the %s", damage or -1, CONFIG.super_armour_breed)
				t.expect(damage and damage > 0, "a critical shot did no damage to the %s", CONFIG.super_armour_breed)
			end,
		},
		{
			-- The bullet stops at the first enemy it hits, as UT's trace does: of two in a line, the one behind is not hurt
			name = "the bullet stops at the first enemy",
			run = function (t)
				t.critical_hits(false)

				local front = t.spawn(CONFIG.plain_breed, CONFIG.enemy_distance)
				local behind = t.spawn(CONFIG.plain_breed, CONFIG.behind_distance)

				if not t.expect(front and behind, "the enemies could not be spawned") then
					return
				end

				t.wait(1)
				t.aim_at(front)

				local front_damage = t.track_damage(front)
				local behind_damage = t.track_damage(behind)

				t.press("action_one", 0.1)
				t.wait(0.5)

				t.log("the front enemy took %.1f, the one behind %.1f", front_damage.total, behind_damage.total)
				t.expect(front_damage.total > 0, "the front enemy was not hurt")
				t.expect(behind_damage.total == 0, "the enemy behind took %.1f", behind_damage.total)
			end,
		},
		{
			-- The view fades in from black as the zoom goes in and as it goes out (ClassicSniperRifle.WantsZoomFade): the zoom says when it
			-- last went in or out
			name = "the zoom fades the view when it goes in and out",
			run = function (t)
				local zoom = ut.zoom
				local before = t.on_main_thread(function ()
					return Managers.time:time("game")
				end)

				t.press("action_two", 0.3)

				local zoomed_in = zoom.toggled_at

				t.wait(0.5)
				t.press("action_two", 0.1)
				t.wait(0.2)

				local zoomed_out = zoom.toggled_at

				t.expect(zoomed_in and zoomed_in >= before, "the zoom going in was not marked")
				t.expect(zoomed_out and zoomed_in and zoomed_out > zoomed_in, "the zoom going out was not marked")
			end,
		},
		{
			-- SniperWallHitEffect: the line of a bullet passes the middle of the player who fires it, so they hear it pass
			name = "the player who fires hears the bullet pass",
			run = function (t)
				local sounds = t.sounds("ut_sniper_whiz_")

				t.press("action_one", 0.1)
				t.wait(0.5)

				t.expect(#sounds == 1, "the bullet's pass played %d times, not once", #sounds)
			end,
		},
		{
			-- TracerProjectile: another player's shot or a bot's flies as a tracer, and passing the player, it is heard
			name = "a bot's shot has a tracer, and passing the player it is heard",
			run = function (t)
				local bot = t.add_bot(CONFIG.bot_profile, CONFIG.bot_career, ut.items.weapons.sniper_rifle_dr.key, CONFIG.bot_distance)

				if not t.expect(bot, "the bot could not be added") then
					return
				end

				t.wait(1)
				t.bot_aim(bot, t.unit())
				t.wait(0.5)

				local sounds = t.sounds("ut_sniper_whiz_")
				local before = ut.sniper.tracers_made or 0

				t.bot_press(bot, "fire")
				t.wait(0.5)

				local tracers = (ut.sniper.tracers_made or 0) - before

				t.expect(tracers == 1, "%d tracers flew, not 1", tracers)
				t.expect(#sounds == 1, "the bullet's pass played %d times, not once", #sounds)
			end,
		},
		{
			-- The characters' shot animation finds no weapon unit to play the handgun's own muzzle flash and sound on (the skin draws UT's)
			name = "the handgun's own third person shot is not played",
			run = function (t)
				local hidden = t.on_main_thread(function ()
					local result = flow_query_wielded_weapon({ player_unit = t.unit() })
					local null_reference = Unit.null_reference()

					return result ~= nil and result.righthandweapon3p == null_reference and result.lefthandweapon3p == null_reference
				end)

				t.expect(hidden, "the characters' flow still gets the handgun's units")
			end,
		},
	}
end

local function hero(setting_id, careers)
	local definition = ut.items.weapons[setting_id]

	return { item = definition.key, template = definition.template, careers = careers }
end

-- Each hero's shot is a copy of their own handgun's, with its animation and where it starts, so only the firing runs for Bardin. The
-- rest is the same code for both.
runner.add_suite({
	name = "sniper",
	slot = "slot_ranged",
	heroes = {
		hero("sniper_rifle", { "es_mercenary", "es_huntsman", "es_knight" }),
		hero("sniper_rifle_dr", { "dr_ironbreaker", "dr_ranger", "dr_engineer" }),
	},
	scenarios = scenarios(),
})
