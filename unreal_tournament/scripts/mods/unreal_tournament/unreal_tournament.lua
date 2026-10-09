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

local function call_all(callbacks, ...)
	for i = 1, #callbacks do
		callbacks[i](...)
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

mod.on_game_state_changed = function (status, state_name)
	if status == "exit" and state_name == "StateIngame" then
		call_all(mod.level_exit_callbacks)
	end
end

-- The hooks of the game's functions that the weapons share, and the tables of callbacks they run
mod:dofile("scripts/mods/unreal_tournament/hooks")

-- The scaled particle effects of the weapons, the one copy of them
mod.effects = mod:dofile("scripts/mods/unreal_tournament/effects")

mod:dofile("scripts/mods/unreal_tournament/shock_rifle")
mod:dofile("scripts/mods/unreal_tournament/flak_cannon")
mod:dofile("scripts/mods/unreal_tournament/rocket_launcher")
mod:dofile("scripts/mods/unreal_tournament/bio_rifle")
mod:dofile("scripts/mods/unreal_tournament/link_gun")
mod:dofile("scripts/mods/unreal_tournament/movement")
mod:dofile("scripts/mods/unreal_tournament/gameplay")

-- (seen in the chat each time the mod is loaded or reloaded, to know which build is running: the number is the count of
-- commits of the repository, which goes up by one with every change)
mod:echo("Unreal Tournament loaded (build 103)")
