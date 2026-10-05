local mod = get_mod("versus-tweaks")

local presets = {
    default = {
        startup_time = 10,
        player_pick_time = 10,
        parading_duration = 5,
        closing_time = 2,
        parading_times_local_player = 5,
        parading_times_opponent_transition = 5,
        parading_times_show_match_info = 4,
        parading_times_team_transition = 0.5,
        initial_set_pre_start_duration = 45,
        pre_start_round_duration = 30,
        disable_early_win = false,
        disable_round_end_on_empty_teams = false,
        disable_round_end_on_all_dead_or_downed = false,
        allow_starting_game_with_empty_teams = false,
        enable_vs_commands = false,
    },
    balanced = {
        startup_time = 3,
        player_pick_time = 5,
        parading_duration = 1,
        closing_time = 1,
        parading_times_local_player = 2,
        parading_times_opponent_transition = 2,
        parading_times_show_match_info = 4,
        parading_times_team_transition = 0.5,
        initial_set_pre_start_duration = 20,
        pre_start_round_duration = 15,
        disable_early_win = true,
        disable_round_end_on_empty_teams = false,
        disable_round_end_on_all_dead_or_downed = false,
        allow_starting_game_with_empty_teams = false,
        enable_vs_commands = false,
    },
    fastest = {
        startup_time = 1,
        player_pick_time = 1,
        parading_duration = 1,
        closing_time = 1,
        parading_times_local_player = 1,
        parading_times_opponent_transition = 1,
        parading_times_show_match_info = 1,
        parading_times_team_transition = 0.1,
        initial_set_pre_start_duration = 1,
        pre_start_round_duration = 1,
        disable_early_win = false,
        disable_round_end_on_empty_teams = false,
        disable_round_end_on_all_dead_or_downed = false,
        allow_starting_game_with_empty_teams = false,
        enable_vs_commands = false,
    },
    debug = {
        startup_time = 1,
        player_pick_time = 1,
        parading_duration = 1,
        closing_time = 1,
        parading_times_local_player = 1,
        parading_times_opponent_transition = 1,
        parading_times_show_match_info = 1,
        parading_times_team_transition = 0.1,
        initial_set_pre_start_duration = 1,
        pre_start_round_duration = 1,
        disable_early_win = true,
        disable_round_end_on_empty_teams = true,
        disable_round_end_on_all_dead_or_downed = true,
        allow_starting_game_with_empty_teams = true,
        enable_vs_commands = true,
    }
}

-- Disable early win conditions
mod:hook("VersusWinConditions", "update_early_win_conditions", function(func, self, ...)
    if not mod:get("disable_early_win") then
        return func(self, ...)
    end

    
	if not self._has_objectives then
		return
	end

	if script_data.debug_early_win and Network.game_session() then
		self:_check_heroes_close_to_win_conditions_met()
	end

    self.party_won_early = nil

    return false, self.party_won_early
end)

-- Allow starting game with 1 player
mod:hook("PlayerHostedSlotReservationHandler", "all_teams_have_members", function(func, ...)
    if mod:get("allow_starting_game_with_empty_teams") then
        return true
    end

    return func(...)
end)

-- Fix crash at end of game
mod:hook("StateInGameRunning", "_setup_end_of_level_UI", function(func, self, ...)
    func(self, ...)

    
    local mechanism_name = Managers.mechanism:current_mechanism_name()

    if not self._booted_eac_untrusted or not (mechanism_name == "versus") then
        return
    end

    local level_end_view_context = self.parent.parent.loading_context.level_end_view_context

    if level_end_view_context.rewards then
        return
    end

    local win_conditions = Managers.mechanism:game_mechanism():win_conditions()

    level_end_view_context.rewards = {
        team_scores = win_conditions and win_conditions:get_total_scores()
    }
end)

local initial_versus_settings = nil

local update_settings = function()
    -- character picking
    GameModeSettings.versus.character_picking_settings = {
        closing_time = mod:get("closing_time"),
        parading_duration = mod:get("parading_duration"),
        player_pick_time = mod:get("player_pick_time"),
        startup_time = mod:get("startup_time"),
    }
    GameModeSettings.versus.parading_times = {
        local_player = mod:get("parading_times_local_player"),
        opponent_transition = mod:get("parading_times_opponent_transition"),
        show_match_info = mod:get("parading_times_show_match_info"),
        team_transition = mod:get("parading_times_team_transition"),
    }
    -- start game duration
    GameModeSettings.versus.pre_start_round_duration = mod:get("pre_start_round_duration")
    GameModeSettings.versus.initial_set_pre_start_duration = mod:get("initial_set_pre_start_duration")
end

mod.on_setting_changed = function(setting_id)
    if setting_id == "preset" then
        local preset = mod:get("preset")
        local settings = presets[preset]

        if preset == "custom" then
            settings = mod:get("custom_preset") or presets.default
        end

        for key, value in pairs(settings) do
            mod:set(key, value)
        end
    else
        mod:set('preset', 'custom')
        local custom_settings = {}
        for key in pairs(presets.default) do
            custom_settings[key] = mod:get(key)
        end  
        mod:set('custom_preset', custom_settings)
    end
    
    -- Reload vmf options view
    Managers.ui._ingame_ui.views["vmf_options_view"]:update_picked_option_for_settings_list_widgets()

    update_settings()
end

mod.on_enabled = function()
    if not initial_versus_settings then
        initial_versus_settings = {
            character_picking_settings = GameModeSettings.versus.character_picking_settings,
            parading_times = GameModeSettings.versus.parading_times,
            pre_start_round_duration = GameModeSettings.versus.pre_start_round_duration,
            initial_set_pre_start_duration = GameModeSettings.versus.initial_set_pre_start_duration
        }
    end

    update_settings()
end

local on_unloaded = function()
    if initial_versus_settings then
        GameModeSettings.versus.character_picking_settings = initial_versus_settings.character_picking_settings
        GameModeHelper.versus.parading_times = initial_versus_settings.parading_times
        GameModeSettings.versus.pre_start_round_duration = initial_versus_settings.pre_start_round_duration
        GameModeSettings.versus.initial_set_pre_start_duration = initial_versus_settings.initial_set_pre_start_duration
        initial_versus_settings = nil
    end
end

mod.on_disabled = on_unloaded
mod.on_unloaded = on_unloaded

mod:hook_safe("GameModeVersus", "evaluate_end_conditions", function(self)
    local disable_round_end_on_empty_teams = mod:get("disable_round_end_on_empty_teams")
    local disable_round_end_on_all_dead_or_downed = mod:get("disable_round_end_on_all_dead_or_downed")

    if not disable_round_end_on_empty_teams and not disable_round_end_on_all_dead_or_downed then
        self._lose_condition_disabled = false
        return
    end

    local ignore_bots = not disable_round_end_on_empty_teams
	local round_timer_over = self._win_conditions:is_round_timer_over()
	local objective_system = Managers.state.entity:system("objective_system")
	local all_objectives_completed = objective_system:all_objectives_completed()
	local party_won_early_data = self._win_conditions.party_won_early
	local humans_and_bots_dead = GameModeHelper.side_is_dead("heroes", ignore_bots)
	local heroes_and_bots_disabled = GameModeHelper.side_is_disabled("heroes")
	local heroes_and_bots_dead_or_disabled = humans_and_bots_dead or heroes_and_bots_disabled
	local party = Managers.state.side:get_party_from_side_name("dark_pact")
	local no_pactsworn_players = party.num_used_slots == 0

    local round_ended = (not disable_round_end_on_all_dead_or_downed and heroes_and_bots_dead_or_disabled)
        or (not disable_round_end_on_empty_teams and no_pactsworn_players)
        or self._level_failed
        or round_timer_over
        or all_objectives_completed
        or party_won_early_data
        or script_data.auto_complete_rounds or false

    self._lose_condition_disabled = not round_ended
end)

mod:command("vs_end_round", "End current round", function()
    if not mod:get("enable_vs_commands") then
        mod:echo("Command disabled")
        return
    end

    if Managers.state.game_mode then
        Managers.state.game_mode:complete_level()
    end
end)

mod:command("vs_die", "Suicide", function()
    if not mod:get("enable_vs_commands") then
        mod:echo("Command disabled")
        return
    end


    if Managers.player.is_server then
        local health_system = Managers.state.entity:system("health_system")

        health_system:suicide(Managers.player:local_player().player_unit)
    else
        local go_id = Managers.state.unit_storage:go_id(Managers.player:local_player().player_unit)

        Managers.state.network.network_transmit:send_rpc_server("rpc_suicide", go_id)
    end
end)

mod:command("vs_kill_trash", "Kill all non-player rats", function()
    if not mod:get("enable_vs_commands") then
        mod:echo("Command disabled")
        return
    end

    Managers.state.conflict:destroy_all_units(true)
end)

mod:command("vs_kill_bots", "Kill bots", function() 
    if not mod:get("enable_vs_commands") then
        mod:echo("Command disabled")
        return
    end

    for _, bot in ipairs( Managers.player:bots() ) do
        if bot.player_unit then
            if Managers.player.is_server then
                local health_system = Managers.state.entity:system("health_system")
        
                health_system:suicide(bot.player_unit)
            else
                local go_id = Managers.state.unit_storage:go_id(bot.player_unit)
        
                Managers.state.network.network_transmit:send_rpc_server("rpc_suicide", go_id)
            end
        end
    end
end)