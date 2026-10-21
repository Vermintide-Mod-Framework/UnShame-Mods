local mod = get_mod("unreal_tournament")

-- Bots link allies with the Link Gun, as UT2004's bots link their squad leader (LinkGun.FocusOnLeader and BestMode). A bot whose ranged
-- weapon is a Link Gun with ammo turns to an ally who is firing a Link Gun and holds the beam on them. The ally has to be in the beam's
-- reach and in sight, and not aiming at the bot. UT's bots link only their leader. Here a bot links any player or bot, a player first.
-- The game's bots run a behaviour tree (BotBehaviors.default in bt_bot.lua). This adds a branch to it, after the attacks on priority
-- targets and before the ordinary fighting and following: switch to the ranged weapon, then link. A bot with an enemy in melee range
-- fights instead.

local link = mod.link_new

local CONFIG = {
	-- How long after a bolt an ally still counts as firing. A held button fires a bolt every 0.2 s.
	fire_memory = 0.5, -- s
	-- An ally aims at the bot when the cosine of the angle between their aim and the way to the bot is above this (FocusOnLeader)
	aimed_at = 0.9,
	-- The bot holds the beam once its aim is this close to the ally: the widest aim the game's bots shoot with (BTBotShootAction)
	fire_angle = math.pi / 16, -- radians
}

local NODE_NAME = "ut_link_new_ally"
local ACTION_CLASS_NAME = "BTBotUtLinkNewAction"

-- Whether a character is firing a Link Gun: the beam, or a bolt a moment ago (UT's Weapon.IsFiring)
local function firing(unit, t)
	local bolt_time = link.bolt_times[unit]

	return link.beams[unit] ~= nil or bolt_time ~= nil and t - bolt_time < CONFIG.fire_memory
end

-- Whether a character aims at a unit, from the aim every machine is sent
local function aims_at(unit, other)
	local game = Managers.state.network:game()
	local go_id = Managers.state.unit_storage:go_id(unit)

	if not game or not go_id then
		return false
	end

	local aim = GameSession.game_object_field(game, go_id, "aim_direction")

	return Vector3.dot(aim, Vector3.normalize(POSITION_LOOKUP[other] - POSITION_LOOKUP[unit])) > CONFIG.aimed_at
end

-- Whether a bot's ranged weapon is a Link Gun with ammo for the beam
local function can_beam(blackboard)
	local inventory_extension = blackboard.inventory_extension
	local slot_data = inventory_extension:get_slot_data("slot_ranged")
	local template_name = slot_data and slot_data.item_data and slot_data.item_data.template

	if not link.templates[template_name] then
		return false
	end

	local ammo = inventory_extension:current_ammo_status("slot_ranged")

	return ammo ~= nil and ammo >= link.config.beam_ammo
end

-- Whether a bot should link an ally. It picks the ally (blackboard.ut_link_new_target): the one it links already, then a player, then
-- the nearest.
BTConditions[NODE_NAME] = function (blackboard)
	blackboard.ut_link_new_target = nil

	if not can_beam(blackboard) or BTConditions.bot_in_melee_range(blackboard) then
		return false
	end

	local unit = blackboard.unit
	local t = Managers.time:time("game")
	local eye = blackboard.first_person_extension:current_position()
	local physics_world = World.get_data(blackboard.world, "physics_world")
	local range = link.beam_range(unit)
	local best, best_score

	for _, player in pairs(Managers.player:human_and_bot_players()) do
		local ally = player.player_unit

		if ally and ally ~= unit and Unit.alive(ally) and firing(ally, t) and link.linkable(unit, ally) and not aims_at(ally, unit) then
			local to_ally = link.linked_end(ally) - eye
			local distance = Vector3.length(to_ally)

			if distance < range and not PhysicsWorld.immediate_raycast(physics_world, eye, Vector3.normalize(to_ally), distance, "closest", "collision_filter", "filter_player_ray_projectile_static_only") then
				local score = distance

				if link.locked[unit] == ally then
					score = score - 2000
				elseif not player.bot_player then
					score = score - 1000
				end

				if not best_score or score < best_score then
					best, best_score = ally, score
				end
			end
		end
	end

	blackboard.ut_link_new_target = best

	return best ~= nil
end

-- The action: turn to the ally as the game's bots turn to an enemy, and hold the beam (the right button) once the aim is close
local BTBotUtLinkNewAction = class(rawget(_G, ACTION_CLASS_NAME), BTNode)

BTBotUtLinkNewAction.name = ACTION_CLASS_NAME

rawset(_G, ACTION_CLASS_NAME, BTBotUtLinkNewAction)

BTBotUtLinkNewAction.init = function (self, ...)
	BTBotUtLinkNewAction.super.init(self, ...)
end

BTBotUtLinkNewAction.enter = function (self, unit, blackboard, t)
	blackboard.input_extension:set_aiming(true, false, true)

	blackboard.ut_link_new = {
		yaw_speed = 0,
		pitch_speed = 0,
		holding = false,
	}
end

BTBotUtLinkNewAction.leave = function (self, unit, blackboard, t, reason, destroy)
	blackboard.input_extension:set_aiming(false)

	blackboard.ut_link_new = nil
end

BTBotUtLinkNewAction.run = function (self, unit, blackboard, t, dt)
	local target = blackboard.ut_link_new_target
	local state = blackboard.ut_link_new

	if not target or not state then
		return "failed"
	end

	local first_person_extension = blackboard.first_person_extension
	local eye = first_person_extension:current_position()
	local rotation = first_person_extension:current_rotation()
	local wanted = Quaternion.look(link.linked_end(target) - eye, Vector3.up())
	local yaw, pitch = Quaternion.yaw(rotation), Quaternion.pitch(rotation)
	local wanted_yaw, wanted_pitch = Quaternion.yaw(wanted), Quaternion.pitch(wanted)

	state.yaw_speed, state.pitch_speed = BTBotShootAction._calculate_aim_speed(nil, unit, dt, yaw, pitch, wanted_yaw, wanted_pitch, state.yaw_speed, state.pitch_speed)

	local new_yaw = yaw + state.yaw_speed * dt
	local new_pitch = pitch + state.pitch_speed * dt
	local input_extension = blackboard.input_extension

	input_extension:set_aim_rotation(Quaternion.multiply(Quaternion(Vector3.up(), new_yaw), Quaternion(Vector3.right(), new_pitch)))

	local yaw_offset = (new_yaw - wanted_yaw + math.pi) % (math.pi * 2) - math.pi
	local pitch_offset = new_pitch - wanted_pitch

	if state.holding or math.sqrt(yaw_offset * yaw_offset + pitch_offset * pitch_offset) < CONFIG.fire_angle then
		state.holding = true

		input_extension:charge_shot()
	end

	return "running"
end

-- The branch, put in the tree before "in_combat". The trees are made from it when a level starts (AISystem.create_all_trees). A reload of
-- the mod replaces it.
local root = BotBehaviors.default

for i = #root, 2, -1 do
	if root[i].name == NODE_NAME then
		table.remove(root, i)
	end
end

for i = 2, #root do
	if root[i].name == "in_combat" then
		table.insert(root, i, {
			"BTSelector",
			{
				"BTBotInventorySwitchAction",
				condition = "is_slot_not_wielded",
				name = "switch_ranged_ut_link_new",
				condition_args = {
					"slot_ranged",
				},
				action_data = BotActions.default.switch_ranged,
			},
			{
				ACTION_CLASS_NAME,
				name = "ut_link_new_link",
			},
			condition = NODE_NAME,
			name = NODE_NAME,
		})

		break
	end
end
