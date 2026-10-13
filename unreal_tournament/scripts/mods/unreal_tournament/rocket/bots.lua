local mod = get_mod("unreal_tournament")

-- Bots with the Rocket Launcher. The game's bot shooting (BTBotShootAction) already fires the primary attack, which is a rocket. Bots don't
-- use the salvo. This only keeps them from firing where the explosion (3 m in radius) would hurt them or a player.

local CONFIG = {
	-- A rocket is fired at a target in this range (meters): nearer, the explosion would hurt the bot
	min_range = 6,
	max_range = 40,
	-- No rocket when a player or bot is this close to the target (the explosion hurts them)
	ally_clearance = 4,
}

mod.bot_shot_callbacks.ut_rocket = function (func, self, shoot_blackboard, action_data, input_extension, t)
	local target_unit = shoot_blackboard.target_unit
	local bot_unit = shoot_blackboard.ut_unit

	if not bot_unit or not HEALTH_ALIVE[target_unit] then
		return func(self, shoot_blackboard, action_data, input_extension, t)
	end

	local target_position = POSITION_LOOKUP[target_unit]
	local distance = Vector3.distance(POSITION_LOOKUP[bot_unit], target_position)

	if distance < CONFIG.min_range or distance > CONFIG.max_range then
		return
	end

	for _, player in pairs(Managers.player:players()) do
		local player_unit = player.player_unit

		if player_unit and Unit.alive(player_unit) and Vector3.distance(POSITION_LOOKUP[player_unit], target_position) < CONFIG.ally_clearance then
			return
		end
	end

	return func(self, shoot_blackboard, action_data, input_extension, t)
end
