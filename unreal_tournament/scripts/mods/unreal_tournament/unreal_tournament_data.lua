local mod = get_mod("unreal_tournament")

-- The titles and the tooltips of the settings are the localizations with the id of the setting, and the id
-- with _description added. In a game, all but the Announcer are the host's (settings.lua).
return {
	name = "Unreal Tournament",
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			{
				setting_id = "ut_movement",
				type = "checkbox",
				default_value = true,
				sub_widgets = {
					{
						setting_id = "multidodge",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "momentum_damage",
						type = "checkbox",
						default_value = false,
					},
				},
			},
			{
				setting_id = "killing_sprees",
				type = "checkbox",
				default_value = true,
				sub_widgets = {
					{
						setting_id = "announcer",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "adrenaline",
						type = "checkbox",
						default_value = true,
					},
				},
			},
			{
				setting_id = "no_barriers",
				type = "checkbox",
				default_value = false,
				sub_widgets = {
					{
						setting_id = "no_invisible_walls",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "no_kill_zones",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "no_ledges",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "no_lifts",
						type = "checkbox",
						default_value = true,
					},
				},
			},
			{
				setting_id = "gameplay",
				type = "checkbox",
				default_value = false,
				sub_widgets = {
					{
						setting_id = "more_ammo_pickups",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "auto_revive",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "no_bots",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "forgiving_disablers",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "auto_restart",
						type = "checkbox",
						default_value = false,
					},
					{
						setting_id = "no_friendly_fire",
						type = "checkbox",
						default_value = false,
					},
				},
			},
			{
				setting_id = "chaos_wastes",
				type = "group",
				sub_widgets = {
					{
						setting_id = "reliquary_ut_weapons",
						type = "checkbox",
						default_value = false,
					},
				},
			},
		},
	},
}
