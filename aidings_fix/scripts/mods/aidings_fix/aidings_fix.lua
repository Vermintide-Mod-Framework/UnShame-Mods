local mod = get_mod("aidings_fix")

local function getupvalue(func, name)
	i = 1

	while true do
		local n, v = debug.getupvalue(func, i)

		if not n then break end

		if n == name then 
			return v, i 
		end

		i = i + 1
	end

	return nil, nil
end

local function setupvalue(func, name, value)
	local v, i = getupvalue(func, name)

	if i then
		debug.setupvalue(func, i, value)
	end

	return v, i
end

local event_settings_aid = {
	text_function = function (amount, player_1_name, player_2_name)
		if amount > 1 then
			return string.format(Localize("positive_reinforcement_player_aid_player_multiple"), player_1_name, player_2_name, amount)
		else
			return string.format(Localize("positive_reinforcement_player_aid_player"), player_1_name, player_2_name)
		end
	end,
	sound_function = function ()
		return "hud_achievement_unlock_02"
	end,
	icon_function = function (image_1, image_2)
		return image_1, "reinforcement_aid", image_2
	end
}

local upvalues = { set = false }

local function set_upvalues()
	if not upvalues.set then
		upvalues.event_colors = getupvalue(PositiveReinforcementUI.event_add_positive_enforcement_kill, "event_colors")
		upvalues.event_settings = getupvalue(PositiveReinforcementUI.event_add_positive_enforcement_kill, "event_settings")
		upvalues.event_settings.aid = event_settings_aid

		upvalues.set = true
	end
end

local function reset_upvalues()
	if upvalues.set then
		upvalues = { set = false }
	end
end

--[[ Actual blackboard stagger count --]]

mod:hook(AiUtils, "stagger", function (func, unit, blackboard, ...)
	blackboard.stagger_actual_count = (blackboard.stagger_actual_count and blackboard.stagger_actual_count + 1) or 1
	return func(unit, blackboard, ...)
end)

mod:hook_safe(BTStaggerAction, "clean_blackboard", function(self, blackboard)
	blackboard.stagger_actual_count = nil
end)

mod:hook_origin(AISimpleExtension, "attacked", function(self, attacker_unit, t, damage_hit)
	local unit = self._unit
	local blackboard = self._blackboard
	attacker_unit = AiUtils.get_actual_attacker_unit(attacker_unit)
	local attacker_is_valid_player_target = VALID_TARGETS_PLAYERS_AND_BOTS[attacker_unit]

	if attacker_is_valid_player_target then
		if damage_hit and blackboard.confirmed_player_sighting and blackboard.target_unit == nil then
			blackboard.target_unit = attacker_unit
			blackboard.target_unit_found_time = t

			AiUtils.alert_nearby_friends_of_enemy(unit, blackboard.group_blackboard.broadphase, attacker_unit)
		end

		blackboard.previous_attacker = attacker_unit
		blackboard.previous_attacker_hit_time = t
	end

	-- Check actual stagger count
	if not damage_hit and blackboard.stagger_actual_count == 1 and AiUtils.unit_alive(unit) then
		StatisticsUtil.check_save(attacker_unit, unit, damage_hit)
	end
end)

--[[ Aid/save --]]

local function on_assisted(savior_unit, saved_unit, enemy_unit, predicate)


	local network_manager = Managers.state.network
	local player_manager = Managers.player
	local statistics_db = player_manager:statistics_db()

	local savior_player = player_manager:owner(savior_unit)
	local saved_player = player_manager:owner(saved_unit)
	local savior_player_stats_id = savior_player:stats_id()

	statistics_db:increment_stat(savior_player_stats_id, predicate)

	local local_human = not savior_player.remote and not savior_player.bot_player

	Managers.state.event:trigger("add_coop_feedback", savior_player_stats_id .. saved_player:stats_id(), local_human, predicate, savior_player, saved_player)

	local buff_extension = ScriptUnit.extension(saved_unit, "buff_system")

	buff_extension:trigger_procs("on_assisted", savior_unit, enemy_unit)

	local savior_buff_extension = ScriptUnit.extension(savior_unit, "buff_system")

	savior_buff_extension:trigger_procs("on_assisted_ally", saved_unit, enemy_unit)

	local network_transmit = Managers.state.network.network_transmit
	local savior_player_id = savior_player:network_id()
	local savior_local_player_id = savior_player:local_player_id()
	local saved_player_id = saved_player:network_id()
	local saved_local_player_id = saved_player:local_player_id()
	local predicate_id = NetworkLookup.coop_feedback[predicate]
	local enemy_unit_id = network_manager:unit_game_object_id(enemy_unit)

	network_transmit:send_rpc_clients("rpc_assist", savior_player_id, savior_local_player_id, saved_player_id, saved_local_player_id, predicate_id, enemy_unit_id)
end

mod:hook_origin(StatisticsUtil, "check_save", function(savior_unit, enemy_unit)
	local blackboard = BLACKBOARDS[enemy_unit]
	local saved_unit = blackboard.target_unit
	local player_manager = Managers.player

	if not savior_unit or not saved_unit then
		return
	end

	local savior_is_player = player_manager:is_player_unit(savior_unit)
	local saved_is_player = player_manager:is_player_unit(saved_unit)

	if not savior_is_player or not saved_is_player then
		return
	end

	local savior_player = player_manager:owner(savior_unit)
	local saved_player = player_manager:owner(saved_unit)

	if savior_player == saved_player then
		return
	end

	local saved_unit_dir = nil
	local network_manager = Managers.state.network
	local game = network_manager:game()
	local game_object_id = game and network_manager:unit_game_object_id(saved_unit)

	if game_object_id then
		saved_unit_dir = Vector3.normalize(Vector3.flat(GameSession.game_object_field(game, game_object_id, "aim_direction")))
	else
		saved_unit_dir = Quaternion.forward(Unit.local_rotation(saved_unit, 0))
	end

	local enemy_unit_dir = Quaternion.forward(Unit.local_rotation(enemy_unit, 0))
	local saved_unit_pos = POSITION_LOOKUP[saved_unit]
	local enemy_unit_pos = POSITION_LOOKUP[enemy_unit]
	local attack_dir = saved_unit_pos - enemy_unit_pos
	local is_behind = Vector3.distance(saved_unit_pos, enemy_unit_pos) < 3 and Vector3.dot(attack_dir, saved_unit_dir) > 0 and Vector3.dot(attack_dir, enemy_unit_dir) > 0
	local status_ext = ScriptUnit.extension(saved_unit, "status_system")
	local grabber_unit = status_ext:get_disabler_unit()
	local is_disabled = status_ext:is_disabled()

	if not grabber_unit and (is_behind or is_disabled) then
		on_assisted(savior_unit, saved_unit, enemy_unit, "aid")
	end
end)

-- Enable on aid event
mod:hook_origin(PositiveReinforcementUI, "event_add_positive_enforcement", function(self, hash, is_local_player, event_type, player1, player2)
	
	if not upvalues.event_settings[event_type] then
		return
	end

	local player_1_unit = player1 and player1.player_unit
	local player_2_unit = player2 and player2.player_unit
	local player_1_career_extension = Unit.alive(player_1_unit) and ScriptUnit.extension(player_1_unit, "career_system")
	local player_2_career_extension = Unit.alive(player_2_unit) and ScriptUnit.extension(player_2_unit, "career_system")
	local player_1_profile_index = (player1 and player1:profile_index()) or nil
	local player_2_profile_index = (player2 and player2:profile_index()) or nil
	local player_1_career_index = (player_1_career_extension and player_1_career_extension:career_index()) or (player1 and player1:career_index())
	local player_2_career_index = (player_2_career_extension and player_2_career_extension:career_index()) or (player2 and player2:career_index())
	local player_1_profile_image = player_1_profile_index and player_1_career_index and self:_get_hero_portrait(player_1_profile_index, player_1_career_index)
	local player_2_profile_image = player_2_profile_index and player_2_career_index and self:_get_hero_portrait(player_2_profile_index, player_2_career_index)

	self:add_event(hash, is_local_player, upvalues.event_colors.default, event_type, player_1_profile_image, player_2_profile_image)
end)

-- Remove duped aid popups
mod:hook_safe(PositiveReinforcementUI, "add_event", function (self, hash, is_local_player, color_from, event_type, ...)
	if script_data.disable_reinforcement_ui then return end

	if event_type ~= "aid" then return end

	local events = self._positive_enforcement_events
	local settings = upvalues.event_settings[event_type]
	local texture_1, _, texture_3 = settings.icon_function(...)

	for i = #events, 2, -1 do
		local event = events[i]
		local widget = event.widget

		if event.event_type == "aid" and 
			widget.content.portrait_1.texture_id == texture_1 and 
			widget.content.portrait_2.texture_id == texture_3 
		then
			mod:echo("Removed " .. i)
			self:remove_event(i)
		end
	end
end)

--[[ Save events --]]

local function check_chaos_vortex_sorcerer_save(enemy_unit, savior_unit)

	if not Unit.alive(savior_unit) then
		return 
	end

	local players = Managers.player:players()

	for _, player in pairs(players) do
		local saved_unit = player.player_unit
		local status_extension = saved_unit and ScriptUnit.extension(saved_unit, "status_system")

		if saved_unit ~= savior_unit and status_extension and status_extension:is_in_vortex() then
			on_assisted(savior_unit, saved_unit, enemy_unit, "save")
			break
		end
	end
end

local function check_gutter_runner_save_check(blackboard, savior_unit)
	local enemy_unit = blackboard.unit
	local saved_unit = blackboard.jump_data and blackboard.jump_data.target_unit

	if not enemy_unit or not saved_unit or not Unit.alive(saved_unit) or not Unit.alive(savior_unit) then return end

	local ai_extension = ScriptUnit.extension(enemy_unit, "ai_system")
	local bt_node_name = ai_extension:current_action_name()

	if bt_node_name == "target_pounced" then
		on_assisted(savior_unit, saved_unit, enemy_unit, "save")
	end
end

mod:hook_safe(Breeds.chaos_vortex_sorcerer, "custom_death_enter_function", function (unit, killer_unit, damage_type, death_hit_zone, t, damage_source)
	check_chaos_vortex_sorcerer_save(unit, killer_unit)
end)


mod:hook_safe(BTTargetPouncedAction.leave, "before_stagger_enter_function", function (unit, blackboard, attacker_unit, is_push)
	check_gutter_runner_save_check(blackboard, attacker_unit)
end)

--[[
	Callbacks
--]]

mod.on_enabled = function(is_first_call)
	set_upvalues()
end

mod.on_disabled = function(is_first_call)
	reset_upvalues()
end

mod.on_unload = function(exit_game)
	reset_upvalues()
end


