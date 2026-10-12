local mod = get_mod("unreal_tournament")

-- Bots with the Shock Rifle. The game's own shooting of bots (BTBotShootAction) aims at an enemy and fires the weapon's primary attack, which
-- is the beam here, so bots already shoot the beam. This teaches them the combo: against an elite or a boss, or a cluster of enemies, a bot
-- fires the ball (the secondary attack), waits for it to get near the target, and then fires the beam along the line the ball flew: the beam
-- passes through the ball, which goes off (see find_ball_hit_by_beam in shock_rifle.lua).

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")

local TEMPLATE_NAME = "staff_blast_beam_template_1"

local CONFIG = {
	-- The ball is used against a target this far away (meters): nearer, the ball is gone before the beam can follow it; further, the beam is
	-- out of range of the bot's aim
	min_range = 8,
	max_range = 35,
	-- The beam is fired when the ball is this far from the target (meters)
	meet_distance = 3,
	-- A cluster is this many enemies within this radius of the target
	cluster_size = 4,
	cluster_radius = 3,
	-- No ball when a player or bot is this close to the target (the combo's explosion hurts them)
	ally_clearance = 5,
	-- Seconds between a bot's balls, and how long past the time the ball takes to get there the bot waits before it shoots the beam anyway
	cooldown = 6,
	wait_grace = 1.5,
	-- The least time (seconds) between the ball and the beam
	min_wait = 0.4,
}

-- How fast the ball flies, in meters a second (the action's speed is in centimeters)
local function ball_speed()
	local template = rawget(Weapons, TEMPLATE_NAME)
	local action = template and template.actions.action_two.default

	return action.speed / 100
end

local function worth_a_ball(target_unit, target_position, world)
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

mod:hook_safe(BTBotShootAction, "enter", function (self, unit, blackboard)
	blackboard.shoot.ut_unit = unit
end)

-- The bot fires: a ball, a wait for it, and then the beam, or just the beam
mod:hook(BTBotShootAction, "_fire_shot", function (func, self, shoot_blackboard, action_data, input_extension, t)
	if not shoot_blackboard.attack_meta_data.ut_shock then
		return func(self, shoot_blackboard, action_data, input_extension, t)
	end

	local target_unit = shoot_blackboard.target_unit
	local pending = shoot_blackboard.ut_pending

	if pending then
		if not HEALTH_ALIVE[target_unit] or t >= pending.expire then
			shoot_blackboard.ut_pending = nil
		elseif t < pending.fire_time then
			return
		else
			shoot_blackboard.ut_pending = nil
		end

		return func(self, shoot_blackboard, action_data, input_extension, t)
	end

	local bot_unit = shoot_blackboard.ut_unit

	if bot_unit and HEALTH_ALIVE[target_unit] and t >= (shoot_blackboard.ut_next_ball or 0) then
		local target_position = POSITION_LOOKUP[target_unit]
		local distance = Vector3.distance(POSITION_LOOKUP[bot_unit], target_position)

		if distance >= CONFIG.min_range and distance <= CONFIG.max_range and worth_a_ball(target_unit, target_position, Managers.world:world("level_world")) then
			local flight = math.max(CONFIG.min_wait, (distance - CONFIG.meet_distance) / ball_speed())

			shoot_blackboard.fired = true
			shoot_blackboard.stop_fire_t = t + shoot_blackboard.stop_fire_delay
			shoot_blackboard.ut_next_ball = t + CONFIG.cooldown
			shoot_blackboard.ut_pending = {
				expire = t + flight + CONFIG.wait_grace,
				fire_time = t + flight,
			}

			input_extension:charge_shot()

			return
		end
	end

	return func(self, shoot_blackboard, action_data, input_extension, t)
end)
