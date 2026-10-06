local mod = get_mod("unreal_tournament")

-- The titles and the tooltips of the settings are the localizations with the id of the setting, and the id
-- with _description added.
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
				},
			},
			{
				setting_id = "ut_weapons",
				type = "checkbox",
				default_value = true,
				sub_widgets = {
					{
						setting_id = "shock_rifle",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "flak_cannon",
						type = "checkbox",
						default_value = true,
					},
					{
						setting_id = "rocket_launcher",
						type = "checkbox",
						default_value = true,
					},
				},
			},
		},
	},
}
