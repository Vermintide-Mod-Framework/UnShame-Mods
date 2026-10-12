local mod = get_mod("unreal_tournament")

-- What the files do when the mod is enabled, disabled, reloaded, updated, when a setting changes, or when a level is
-- left: the mod framework's calls to the mod go to each of these lists, in the order the files are loaded. A file adds its
-- own function to the list it wants:
--   mod.update_callbacks[#mod.update_callbacks + 1] = function (dt) ... end
-- level_exit_callbacks: what the weapons have running that belongs to a level (effects, units, worlds) is cleared when the
-- level is left: the game tells the mods before it takes the level's world down, calling something on a world that is
-- gone crashes the game and no pcall catches that.
mod.enabled_callbacks = {}
mod.disabled_callbacks = {}
mod.setting_changed_callbacks = {}
mod.update_callbacks = {}
mod.unload_callbacks = {}
mod.level_exit_callbacks = {}
-- all_mods_loaded_callbacks: run once all mods are loaded, for hooks that must run before other mods' hooks
mod.all_mods_loaded_callbacks = {}

-- (an error in one of them is told and the others are still called: what a weapon takes back when the mod is unloaded or a level is left
-- must not be skipped because another weapon's failed, a unit of the mod's package that is alive when the package is unloaded
-- crashes the game)
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

-- The hooks of the game's functions that the weapons share, and the tables of callbacks they run
mod:dofile("scripts/mods/unreal_tournament/hooks")

-- The weapons as items of their own; each weapon's file registers its item
mod.items = mod:dofile("scripts/mods/unreal_tournament/items")

-- The scaled particle effects of the weapons, the one copy of them
mod.effects = mod:dofile("scripts/mods/unreal_tournament/effects")

-- The particles of the weapon skins (UT2004's effects), the one copy of them
mod.skin_particles = mod:dofile("scripts/mods/unreal_tournament/skin_particles")

-- What the skins of the weapons have in common (a weapon's own file calls mod.weapon_skin.new with what is its own)
mod.weapon_skin = mod:dofile("scripts/mods/unreal_tournament/weapon_skin")

-- The weapons: each has a folder with its gameplay (<weapon>.lua) and its skin (skin.lua, with its animations and effects), and a folder of
-- the same name in units/ut with its models
mod:dofile("scripts/mods/unreal_tournament/shock/shock_rifle")
mod:dofile("scripts/mods/unreal_tournament/shock/skin")
mod:dofile("scripts/mods/unreal_tournament/shock/bots")
mod:dofile("scripts/mods/unreal_tournament/flak/flak_cannon")
mod:dofile("scripts/mods/unreal_tournament/flak/skin")
mod:dofile("scripts/mods/unreal_tournament/rocket/rocket_launcher")
mod:dofile("scripts/mods/unreal_tournament/rocket/skin")
mod:dofile("scripts/mods/unreal_tournament/bio/bio_rifle")
mod:dofile("scripts/mods/unreal_tournament/bio/skin")
mod:dofile("scripts/mods/unreal_tournament/link/link_gun")
mod:dofile("scripts/mods/unreal_tournament/link/skin")
-- Crafting for those items
mod:dofile("scripts/mods/unreal_tournament/crafting")

-- Weapon skins in the menus
mod:dofile("scripts/mods/unreal_tournament/menu_preview")
mod:dofile("scripts/mods/unreal_tournament/announcer")
mod:dofile("scripts/mods/unreal_tournament/movement")
mod:dofile("scripts/mods/unreal_tournament/gameplay")

-- (seen in the chat each time the mod is loaded or reloaded, to know which build is running: the number is the count of
-- commits of the repository, which goes up by one with every change). Only with the developer mode of the mod framework on.
if get_mod("VMF"):get("developer_mode") then
	mod:echo("Unreal Tournament loaded (build 606)")
end
