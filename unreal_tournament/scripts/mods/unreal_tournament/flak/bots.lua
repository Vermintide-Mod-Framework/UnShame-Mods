local mod = get_mod("unreal_tournament")

-- Bots with the Flak Cannon. The game's own shooting of bots (BTBotShootAction) aims at an enemy and fires the weapon's primary attack, which
-- is the flechettes here, so bots already shoot them. This teaches them the shell (the secondary attack): against an elite or a boss, or a
-- cluster of enemies, a bot fires the shell. The shell is tossed up from the aim, so a target about as far as it flies (a level target at
-- 10 to 12 m) is hit where the bot aims.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")

local CONFIG = {
	-- The shell is used against a target in this range (meters): nearer, its explosion (3 m) would hurt the bot, further, it falls short
	min_range = 6,
	max_range = 14,
	-- A cluster is this many enemies within this radius of the target (the explosion is 3 m in radius)
	cluster_size = 3,
	cluster_radius = 3,
	-- No shell when a player or bot is this close to the target (the explosion hurts them)
	ally_clearance = 4,
	-- Seconds between a bot's shells
	cooldown = 3,
}

-- Whether to fire the shell at this target
local function worth_a_shell(target_unit, target_position, world)
	local breed = Unit.get_data(target_unit, "breed")

	for _, player in pairs(Managers.player:players()) do
		local player_unit = player.player_unit

		if player_unit and Unit.alive(player_unit) and Vector3.distance(POSITION_LOOKUP[player_unit], target_position) < CONFIG.ally_clearance then
			return false
		end
	end

	if breed and (breed.elite or breed.boss) then
		return true
	end

	local enemies = 0

	for unit in pairs(utils.units_in_radius(world, target_position, CONFIG.cluster_radius)) do
		if HEALTH_ALIVE[unit] then
			enemies = enemies + 1
		end
	end

	return enemies >= CONFIG.cluster_size
end

-- The bot fires the shell, or the flechettes
mod.bot_shot_callbacks.ut_flak = function (func, self, shoot_blackboard, action_data, input_extension, t)
	local target_unit = shoot_blackboard.target_unit
	local bot_unit = shoot_blackboard.ut_unit

	if bot_unit and HEALTH_ALIVE[target_unit] and t >= (shoot_blackboard.ut_next_shell or 0) then
		local target_position = POSITION_LOOKUP[target_unit]
		local distance = Vector3.distance(POSITION_LOOKUP[bot_unit], target_position)

		if distance >= CONFIG.min_range and distance <= CONFIG.max_range and worth_a_shell(target_unit, target_position, Managers.world:world("level_world")) then
			shoot_blackboard.fired = true
			shoot_blackboard.stop_fire_t = t + shoot_blackboard.stop_fire_delay
			shoot_blackboard.ut_next_shell = t + CONFIG.cooldown

			input_extension:charge_shot()

			return
		end
	end

	return func(self, shoot_blackboard, action_data, input_extension, t)
end
