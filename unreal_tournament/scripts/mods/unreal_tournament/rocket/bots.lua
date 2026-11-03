local mod = get_mod("unreal_tournament")

-- Bots with the Rocket Launcher. The game's bot shooting (BTBotShootAction) already fires the primary attack, which is a rocket. Bots
-- don't use the salvo. This only keeps them from firing where the explosion (3 m in radius) would hurt them or a player.

local CONFIG = {
	-- A rocket is fired at a target at least this far, in meters. Nearer, the explosion would hurt the bot. The furthest is the weapon's
	-- max_range in its attack_meta_data (see rocket_launcher.lua), which the game's bot shooting checks.
	min_range = 6,
	-- No rocket is fired when a player or bot is this close to the target, because the explosion would hurt them.
	ally_clearance = 4,
}

mod.bot_shot_callbacks.ut_rocket = mod.utils.explosive_bot_shot(CONFIG.min_range, CONFIG.ally_clearance)
