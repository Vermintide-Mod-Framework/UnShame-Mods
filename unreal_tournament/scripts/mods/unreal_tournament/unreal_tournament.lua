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

-- The shared files. Each puts itself on mod under its own name (mod.utils, mod.items and so on), so they are loaded once, in this
-- order, before the weapons.

-- Helpers (mod.utils)
mod:dofile("scripts/mods/unreal_tournament/utils")

-- The hooks on the game's functions that the weapons share, and the callback tables those hooks run
mod:dofile("scripts/mods/unreal_tournament/hooks")

-- The weapons as items of their own (mod.items). Each weapon's file registers its item.
mod:dofile("scripts/mods/unreal_tournament/items")

-- The scaled particle effects of the weapons (mod.effects)
mod:dofile("scripts/mods/unreal_tournament/effects")

-- What lets the weapons damage beastmen standards (mod.standards)
mod:dofile("scripts/mods/unreal_tournament/standards")

-- The particles of the weapon skins, which are UT2004's effects (mod.skin_particles)
mod:dofile("scripts/mods/unreal_tournament/skin_particles")

-- UT's effects where a bullet hits a wall, which the Sniper Rifle and the Minigun draw (mod.hit_effects)
mod:dofile("scripts/mods/unreal_tournament/hit_effects")

-- UT's first person flash of the Minigun, which the Assault Rifle, the Sniper Rifle and the Rocket Launcher also use (mod.muzzle_flash)
mod:dofile("scripts/mods/unreal_tournament/muzzle_flash")

-- What the weapon skins have in common (mod.weapon_skin). A weapon's own file calls mod.weapon_skin.new with the parts that are its own.
mod:dofile("scripts/mods/unreal_tournament/weapon_skin")

-- UT's view shake of a shot (mod.view_shake), and UT's zoom of the Lightning Gun and the Sniper Rifle (mod.zoom)
mod:dofile("scripts/mods/unreal_tournament/view_shake")
mod:dofile("scripts/mods/unreal_tournament/zoom")

-- A weapon's charge on a copy of the game's overcharge bar (mod.charge_bars)
mod:dofile("scripts/mods/unreal_tournament/charge_bar")

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
mod:dofile("scripts/mods/unreal_tournament/sniper/sniper_rifle")
mod:dofile("scripts/mods/unreal_tournament/sniper/skin")
mod:dofile("scripts/mods/unreal_tournament/minigun/minigun")
mod:dofile("scripts/mods/unreal_tournament/minigun/skin")
mod:dofile("scripts/mods/unreal_tournament/shield/shield_gun")
mod:dofile("scripts/mods/unreal_tournament/shield/skin")
mod:dofile("scripts/mods/unreal_tournament/redeemer/redeemer")
mod:dofile("scripts/mods/unreal_tournament/redeemer/skin")
mod:dofile("scripts/mods/unreal_tournament/assault/assault_rifle")
mod:dofile("scripts/mods/unreal_tournament/assault/skin")
-- Crafting for those items.
mod:dofile("scripts/mods/unreal_tournament/crafting")

-- Weapon skins in the menus
mod:dofile("scripts/mods/unreal_tournament/menu_preview")
mod:dofile("scripts/mods/unreal_tournament/announcer")
mod:dofile("scripts/mods/unreal_tournament/movement")
mod:dofile("scripts/mods/unreal_tournament/gameplay")

-- The chat commands (UT's cheats), the development commands and the in-game tests are in the extras mod (unreal_tournament_extras),
-- which uses this mod's tables and functions.

-- This message appears in the chat each time the mod is loaded or reloaded, so you can tell which build is running. The build
-- number is the repository's commit count, which goes up by one with every change. It only appears with the mod framework's
-- developer mode on.
if get_mod("VMF"):get("developer_mode") then
	mod:echo("Unreal Tournament loaded (build 1503)")
end
