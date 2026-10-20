local mod = get_mod("unreal_tournament_extras")

-- What the Unreal Tournament mod (unreal_tournament) leaves out: UT's console commands as chat commands, the development commands, and
-- the in-game tests of the weapons. They use that mod's weapons and code, which they reach through get_mod("unreal_tournament").

-- The mod framework calls the mod when it is updated or unloaded, and when a level is left. Each of those calls goes to every function in
-- the matching list below, as in unreal_tournament.lua. The level_exit_callbacks list is for what runs inside a level. It is called before
-- the game takes the level's world down.
mod.update_callbacks = {}
mod.unload_callbacks = {}
mod.level_exit_callbacks = {}

-- Calls every function in the list. An error in one of them is reported, and the others are still called.
local function call_all(callbacks, ...)
	for i = 1, #callbacks do
		local ok, error_message = pcall(callbacks[i], ...)

		if not ok then
			mod:error("%s", tostring(error_message))
		end
	end
end

mod.update = function (...)
	call_all(mod.update_callbacks, ...)
end

mod.on_unload = function (...)
	call_all(mod.unload_callbacks, ...)
end

mod.on_game_state_changed = function (status, state_name)
	if status == "exit" and state_name == "StateIngame" then
		call_all(mod.level_exit_callbacks)
	end
end

-- UT's console commands, and /skin for the weapon skins
mod:dofile("scripts/mods/unreal_tournament_extras/cheats")

-- The in-game tests, run with /ut_test. The runner is loaded once, and each weapon's file adds its suite to it. The runner also has the
-- development commands (/ut_equip, /ut_3p, /ut_spawn and the others).
mod.test_runner = mod:dofile("scripts/mods/unreal_tournament_extras/tests/runner")
mod:dofile("scripts/mods/unreal_tournament_extras/tests/flak")
mod:dofile("scripts/mods/unreal_tournament_extras/tests/lightning")
mod:dofile("scripts/mods/unreal_tournament_extras/tests/sniper")
mod:dofile("scripts/mods/unreal_tournament_extras/tests/minigun")
mod:dofile("scripts/mods/unreal_tournament_extras/tests/shield")
mod:dofile("scripts/mods/unreal_tournament_extras/tests/redeemer")
mod:dofile("scripts/mods/unreal_tournament_extras/tests/assault")
mod:dofile("scripts/mods/unreal_tournament_extras/tests/movement")
mod:dofile("scripts/mods/unreal_tournament_extras/tests/shock")
mod:dofile("scripts/mods/unreal_tournament_extras/tests/rocket")
mod:dofile("scripts/mods/unreal_tournament_extras/tests/bio")
mod:dofile("scripts/mods/unreal_tournament_extras/tests/announcer")
mod:dofile("scripts/mods/unreal_tournament_extras/tests/adrenaline")
mod:dofile("scripts/mods/unreal_tournament_extras/tests/combos")
mod:dofile("scripts/mods/unreal_tournament_extras/tests/effects")
mod:dofile("scripts/mods/unreal_tournament_extras/tests/link_new")
