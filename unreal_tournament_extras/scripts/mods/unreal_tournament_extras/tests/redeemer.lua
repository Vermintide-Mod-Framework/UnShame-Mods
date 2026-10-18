local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- The Redeemer's in-game tests (see runner.lua). The Redeemer is the Bounty Hunter's career ability while he holds the Rocket Launcher.
-- Run them with /ut_test redeemer (with the Rocket Launcher) and /ut_test redeemer_vanilla (with the game's pistols, where the ability is
-- the game's). They run in the runner's level, Righteous Stand.

local runner = mod.test_runner

local CONFIG = {
	career = "wh_bountyhunter",
	-- The ability's cooldown with the Redeemer (redeemer.lua) and the game's own (Locked and Loaded)
	redeemer_cooldown = 140,
	game_cooldown = 70,
	-- How long the ability is held before it is let go: its hold chains to the shot after 0.35 s
	hold = 0.6,
	-- How far down the player looks, so that the missile hits the ground a few meters ahead
	pitch = -35,
	-- How long the missile and its blast take: the flight, and the six waves over 1.3 s
	blast_wait = 6,
}

-- The blasts that are made while a test runs: each wave's explosion, by its template
local blasts = {}
local recording = false

ut.any_explosion_callbacks.ut_test_redeemer = function (explosion_template)
	if recording and string.find(explosion_template.name, "ut_redeemer_wave_", 1, true) then
		blasts[#blasts + 1] = explosion_template.name
	end
end

local function is_missile(action)
	return action.ut_redeemer
end

-- The player's career extension
local function career_extension(t)
	return ScriptUnit.extension(t.unit(), "career_system")
end

-- Makes the ability ready: its cooldown is taken away
local function make_ready(t)
	t.on_main_thread(function ()
		career_extension(t):reduce_activated_ability_cooldown_percent(1, 1, true)
	end)
	t.wait(0.2)
end

-- The ability's cooldown: what is left, and its whole length
local function cooldown(t)
	return t.on_main_thread(function ()
		local extension = career_extension(t)
		local left, max = extension:current_ability_cooldown(1)

		return { left, max }
	end)
end

-- Whether the Redeemer's model is drawn in the player's view, and its mesh is in the character's hand
local function redeemer_drawn(t)
	return t.on_main_thread(function ()
		local skin = ut.weapon_skin.skins.redeemer

		return { skin.state() ~= nil, skin.third_person.held_mesh(t.unit()) ~= nil }
	end)
end

-- Uses the ability: holds the key, looking down, and lets it go
local function use_ability(t)
	t.look(CONFIG.pitch)
	t.press("action_career", CONFIG.hold)
end

local function scenarios()
	return {
		{
			name = "the ability's cooldown is the Redeemer's",
			run = function (t)
				t.wait(0.2)

				local max = cooldown(t)[2]

				t.expect(math.abs(max - CONFIG.redeemer_cooldown) < 0.01, "the ability's cooldown is %.1f s, not %d", max, CONFIG.redeemer_cooldown)
			end,
		},
		{
			name = "the ability draws the Redeemer",
			run = function (t)
				make_ready(t)
				t.look(CONFIG.pitch)
				t.hold("action_career")
				t.wait(0.3)

				local wielded = t.wielded()
				local drawn = redeemer_drawn(t)

				t.release("action_career")
				t.wait(CONFIG.blast_wait)

				t.expect(wielded == ut.redeemer.template, "the ability wields %s, not the career pistol", tostring(wielded))
				t.expect(drawn[1], "the Redeemer's model is not drawn in the player's view")
				t.expect(drawn[2], "the Redeemer's mesh is not in the character's hand")
			end,
		},
		{
			name = "the ability fires one missile, whose blast makes six waves, and puts the pistol away",
			run = function (t)
				make_ready(t)
				table.clear(blasts)

				recording = true

				local missiles = 0

				t.look(CONFIG.pitch)
				t.hold("action_career")
				t.wait(CONFIG.hold)
				t.release("action_career")
				t.watch(0.5, function ()
					missiles = math.max(missiles, #t.projectiles(is_missile))
				end)
				t.wait(CONFIG.blast_wait)

				recording = false

				t.expect(missiles == 1, "%d missiles were in the air, not 1", missiles)
				t.expect(#blasts == 6, "%d waves of the blast were made, not 6 (%s)", #blasts, table.concat(blasts, ", "))
				t.expect(t.wielded() == ut.items.weapons.rocket_launcher.template, "the player holds %s after the ability, not the Rocket Launcher", tostring(t.wielded()))
			end,
		},
		{
			-- The game shortens a cooldown as it starts by the player's cooldown reduction (talents and gear: the activated_cooldown buffs)
			name = "the shot starts the cooldown",
			run = function (t)
				make_ready(t)
				use_ability(t)
				t.wait(1)

				local left = cooldown(t)[1]
				local reduction = t.on_main_thread(function ()
					return ScriptUnit.extension(t.unit(), "buff_system"):apply_buffs_to_value(1, "activated_cooldown")
				end)
				local expected = CONFIG.redeemer_cooldown * reduction

				t.log("%.1f s of the cooldown is left after the shot, of %.1f (the player's cooldown reduction is %.2f)", left, expected, reduction)
				t.expect(math.abs(left - (expected - 1.5)) < 2, "%.1f s of the cooldown is left after the shot, not about %.1f", left, expected - 1.5)
				t.wait(CONFIG.blast_wait)
			end,
		},
	}
end

local definition = ut.items.weapons.rocket_launcher

runner.add_suite({
	name = "redeemer",
	item = definition.key,
	template = definition.template,
	slot = "slot_ranged",
	careers = { CONFIG.career },
	scenarios = scenarios(),
})

-- Without the Rocket Launcher the ability is the game's: its own shot and cooldown, and the career pistol as the game draws it
local function vanilla_scenarios()
	return {
		{
			name = "the ability's cooldown is the game's",
			run = function (t)
				t.wait(0.2)

				local max = cooldown(t)[2]

				t.expect(math.abs(max - CONFIG.game_cooldown) < 0.01, "the ability's cooldown is %.1f s, not %d", max, CONFIG.game_cooldown)
			end,
		},
		{
			name = "the ability fires the game's shot, and no Redeemer",
			run = function (t)
				make_ready(t)
				table.clear(blasts)

				recording = true

				local missiles = 0
				local drawn = false

				t.look(CONFIG.pitch)
				t.hold("action_career")
				t.watch(CONFIG.hold, function ()
					local skin = ut.weapon_skin.skins.redeemer

					drawn = drawn or skin.state() ~= nil or skin.third_person.held_mesh(t.unit()) ~= nil
				end)
				t.release("action_career")
				t.watch(0.5, function ()
					missiles = math.max(missiles, #t.projectiles(is_missile))
				end)
				t.wait(2)

				recording = false

				t.expect(not drawn, "the Redeemer was drawn")
				t.expect(missiles == 0, "%d Redeemer missiles were fired", missiles)
				t.expect(#blasts == 0, "%d waves of a Redeemer blast were made", #blasts)
				t.expect(cooldown(t)[1] > CONFIG.game_cooldown - 10, "the game's cooldown did not start")
			end,
		},
	}
end

runner.add_suite({
	name = "redeemer_vanilla",
	item = "wh_repeating_pistols",
	template = "repeating_pistol_template_1",
	slot = "slot_ranged",
	careers = { CONFIG.career },
	scenarios = vanilla_scenarios(),
})
