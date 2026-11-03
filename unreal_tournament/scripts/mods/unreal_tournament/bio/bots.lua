local mod = get_mod("unreal_tournament")

-- Bots with the Bio Rifle. The game's bot shooting (BTBotShootAction) already uses the pistol's way of shooting, which the rifle keeps: it
-- fires the primary attack and charges the big glob. This only keeps them from firing where the explosion would hurt them or a player.
-- A glob explodes in a radius of 1.6 m, and the biggest one in 5 m, so the range and the clearance are wider than for the rocket.

local CONFIG = {
	-- A glob is fired at a target at least this far, in meters. Nearer, the explosion would hurt the bot. The furthest is the weapon's
	-- max_range in its attack_meta_data (see bio_rifle.lua), which the game's bot shooting checks.
	min_range = 4,
	-- No glob is fired when a player or bot is this close to the target, because the explosion would hurt them.
	ally_clearance = 3.5,
}

mod.bot_shot_callbacks.ut_bio = mod.utils.explosive_bot_shot(CONFIG.min_range, CONFIG.ally_clearance)
