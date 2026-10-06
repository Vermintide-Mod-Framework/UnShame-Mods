local mod = get_mod("unreal_tournament")

-- What the weapons have running that belongs to a level (effects, units, worlds) is cleared when the
-- level is left: the game tells the mods before it takes the level's world down, calling something on a world
-- that is gone crashes the game and no pcall catches that. The files add their functions to this.
mod.level_exit_callbacks = {}

mod.on_game_state_changed = function (status, state_name)
	if status == "exit" and state_name == "StateIngame" then
		for _, callback in ipairs(mod.level_exit_callbacks) do
			callback()
		end
	end
end

mod:dofile("scripts/mods/unreal_tournament/shock_rifle")
mod:dofile("scripts/mods/unreal_tournament/flak_cannon")
mod:dofile("scripts/mods/unreal_tournament/rocket_launcher")
mod:dofile("scripts/mods/unreal_tournament/movement")
mod:dofile("scripts/mods/unreal_tournament/pickups")
mod:dofile("scripts/mods/unreal_tournament/gameplay")
