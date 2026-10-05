local mod = get_mod("versus-tweaks")

return {
	name = "Versus Configuration",
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "preset",
				type = "dropdown",
				default_value = "default",
				options = {
					{ text = "preset_default", value = "default" },
					{ text = "preset_balanced", value = "balanced" },
					{ text = "preset_fastest", value = "fastest" },
					{ text = "preset_debug", value = "debug" },
					{ text = "preset_custom", value = "custom" },
				},
			},
			{
				setting_id    = "character_picking_settings",
				type          = "group",
				sub_widgets   = {
					{
						setting_id    = "startup_time",
						type          = "numeric",
						default_value = 10,
						range         = {1, 10},
						unit_text     = "unit_seconds",
					},
					{
						setting_id    = "player_pick_time",
						type          = "numeric",
						default_value = 10,
						range         = {1, 10},
						unit_text     = "unit_seconds",
					},
					{
						setting_id    = "parading_duration",
						type          = "numeric",
						default_value = 5,
						range         = {1, 10},
						unit_text     = "unit_seconds",
					},
					{
						setting_id    = "closing_time",
						type          = "numeric",
						default_value = 2,
						range         = {1, 10},
						unit_text     = "unit_seconds",
					},
				},
			},
			{
				setting_id = "parading_times",
				type = "group",
				sub_widgets = {
					{
						setting_id = "parading_times_local_player",
						type = "numeric",
						default_value = 5,
						range = {1, 10},
						unit_text = "unit_seconds",
					},
					{
						setting_id = "parading_times_opponent_transition",
						type = "numeric",
						default_value = 5,
						range = {1, 10},
						unit_text = "unit_seconds",
					},
					{
						setting_id = "parading_times_show_match_info",
						type = "numeric",
						default_value = 4,
						range = {1, 10},
						unit_text = "unit_seconds",
					},
					{
						setting_id = "parading_times_team_transition",
						type = "numeric",
						default_value = 0.5,
						range = {0.1, 1},
						unit_text = "unit_seconds",
						decimals_number = 1
					},
				},
			},
			{
				setting_id = "round_start_settings",
				type = "group",
				sub_widgets = {
					{
						setting_id = "initial_set_pre_start_duration",
						type = "numeric",
						default_value = 45,
						range = {1, 100},
						unit_text = "unit_seconds",
					},
					{
						setting_id = "pre_start_round_duration",
						type = "numeric",
						default_value = 30,
						range = {1, 100},
						unit_text = "unit_seconds",
					},
				},
			},
			{
				setting_id = "round_end_behaviors",
				type = "group",
				sub_widgets = {
					{
						setting_id = "disable_early_win",
						tooltip = "tooltip_disable_early_win",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "disable_round_end_on_empty_teams",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "disable_round_end_on_all_dead_or_downed",
						type = "checkbox",
						default_value = false,
					}
				},
			},
			{
				setting_id = "allow_starting_game_with_empty_teams",
				type = "checkbox",
				default_value = false,
			},
			{
				setting_id = "enable_vs_commands",
				type = "checkbox",
				default_value = false,
			}
		}
	}
}
