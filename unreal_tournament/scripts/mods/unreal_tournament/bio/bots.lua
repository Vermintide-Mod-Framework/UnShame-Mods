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

mod.bot_shot_callbacks.ut_bio = function (func, self, shoot_blackboard, action_data, input_extension, t)
	local target_unit = shoot_blackboard.target_unit
	local bot_unit = shoot_blackboard.ut_unit

	if not bot_unit or not HEALTH_ALIVE[target_unit] then
		return func(self, shoot_blackboard, action_data, input_extension, t)
	end

	local target_position = POSITION_LOOKUP[target_unit]
	local distance = Vector3.distance(POSITION_LOOKUP[bot_unit], target_position)

	if distance < CONFIG.min_range then
		return
	end

	for _, player in pairs(Managers.player:players()) do
		local player_unit = player.player_unit

		if player_unit and Unit.alive(player_unit) and player_unit ~= bot_unit and Vector3.distance(POSITION_LOOKUP[player_unit], target_position) < CONFIG.ally_clearance then
			return
		end
	end

	return func(self, shoot_blackboard, action_data, input_extension, t)
end
