local mod = get_mod("unreal_tournament")

-- The mod framework calls the mod when it is enabled, disabled, updated or unloaded, when a setting changes, and when a level is
-- left. Each of those calls goes to every function in the matching list below, in the order the files are loaded. A file adds its
-- own function to the list it wants:
--   mod.update_callbacks[#mod.update_callbacks + 1] = function (dt) ... end
-- The level_exit_callbacks list is for what the weapons have running inside a level, such as effects, units and worlds. It is
-- cleared when the level is left. The game tells the mods before it takes the level's world down. Calling something on a world
-- that is gone crashes the game, and no pcall catches that.
mod.enabled_callbacks = {}
mod.disabled_callbacks = {}
mod.setting_changed_callbacks = {}
mod.update_callbacks = {}
mod.unload_callbacks = {}
mod.level_exit_callbacks = {}
-- The all_mods_loaded_callbacks list runs once all mods are loaded. It is for hooks that must run before other mods' hooks.
mod.all_mods_loaded_callbacks = {}

-- Calls every function in the list. An error in one of them is reported, and the others are still called. A weapon must always take
-- back what it set up when the mod is unloaded or a level is left, even if another weapon's cleanup failed. A unit of the mod's
-- package that is still alive when the package is unloaded crashes the game.
local function call_all(callbacks, ...)
	for i = 1, #callbacks do
		local ok, error_message = pcall(callbacks[i], ...)

		if not ok then
			mod:error("%s", tostring(error_message))
		end
	end
end

mod.on_enabled = function (...)
	call_all(mod.enabled_callbacks, ...)
end

mod.on_disabled = function (...)
	call_all(mod.disabled_callbacks, ...)
end

mod.on_setting_changed = function (...)
	call_all(mod.setting_changed_callbacks, ...)
end

mod.update = function (...)
	call_all(mod.update_callbacks, ...)
end

mod.on_unload = function (...)
	call_all(mod.unload_callbacks, ...)
end

mod.on_all_mods_loaded = function (...)
	call_all(mod.all_mods_loaded_callbacks, ...)
end

mod.on_game_state_changed = function (status, state_name)
	if status == "exit" and state_name == "StateIngame" then
		call_all(mod.level_exit_callbacks)
	end
end

-- The hooks on the game's functions that the weapons share, and the callback tables those hooks run
mod:dofile("scripts/mods/unreal_tournament/hooks")

-- The weapons as items of their own. Each weapon's file registers its item.
mod.items = mod:dofile("scripts/mods/unreal_tournament/items")

-- The scaled particle effects of the weapons. All weapons share this one copy.
mod.effects = mod:dofile("scripts/mods/unreal_tournament/effects")

-- What lets the weapons damage beastmen standards (banners). All weapons share this one copy.
mod.standards = mod:dofile("scripts/mods/unreal_tournament/standards")

-- The particles of the weapon skins, which are UT2004's effects. All skins share this one copy.
mod.skin_particles = mod:dofile("scripts/mods/unreal_tournament/skin_particles")

-- What the weapon skins have in common. A weapon's own file calls mod.weapon_skin.new with the parts that are its own.
mod.weapon_skin = mod:dofile("scripts/mods/unreal_tournament/weapon_skin")

-- The weapons. Each has a folder with its gameplay (<weapon>.lua) and its skin (skin.lua, with its animations and effects). Each
-- also has a folder of the same name in units/ut with its models.
mod:dofile("scripts/mods/unreal_tournament/shock/shock_rifle")
mod:dofile("scripts/mods/unreal_tournament/shock/skin")
mod:dofile("scripts/mods/unreal_tournament/shock/bots")
mod:dofile("scripts/mods/unreal_tournament/flak/flak_cannon")
mod:dofile("scripts/mods/unreal_tournament/flak/bots")
mod:dofile("scripts/mods/unreal_tournament/flak/skin")
mod:dofile("scripts/mods/unreal_tournament/rocket/rocket_launcher")
mod:dofile("scripts/mods/unreal_tournament/rocket/skin")
mod:dofile("scripts/mods/unreal_tournament/rocket/bots")
mod:dofile("scripts/mods/unreal_tournament/bio/bio_rifle")
mod:dofile("scripts/mods/unreal_tournament/bio/bots")
mod:dofile("scripts/mods/unreal_tournament/bio/skin")
mod:dofile("scripts/mods/unreal_tournament/link/link_gun")
mod:dofile("scripts/mods/unreal_tournament/link/skin")
mod:dofile("scripts/mods/unreal_tournament/lightning/lightning_gun")
mod:dofile("scripts/mods/unreal_tournament/lightning/skin")
-- Crafting for those items.
mod:dofile("scripts/mods/unreal_tournament/crafting")

-- Weapon skins in the menus
mod:dofile("scripts/mods/unreal_tournament/menu_preview")
mod:dofile("scripts/mods/unreal_tournament/announcer")
mod:dofile("scripts/mods/unreal_tournament/movement")
mod:dofile("scripts/mods/unreal_tournament/gameplay")

-- The in-game tests, run with /ut_test. The runner is loaded once, and each weapon's file adds its suite to it.
mod.test_runner = mod:dofile("scripts/mods/unreal_tournament/tests/runner")
mod:dofile("scripts/mods/unreal_tournament/tests/flak")
mod:dofile("scripts/mods/unreal_tournament/tests/lightning")

-- This message appears in the chat each time the mod is loaded or reloaded, so you can tell which build is running. The build
-- number is the repository's commit count, which goes up by one with every change. It only appears with the mod framework's
-- developer mode on.
if get_mod("VMF"):get("developer_mode") then
	mod:echo("Unreal Tournament loaded (build 915)")
end
