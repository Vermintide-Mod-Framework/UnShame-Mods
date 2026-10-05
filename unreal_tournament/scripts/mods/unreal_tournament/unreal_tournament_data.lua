local mod = get_mod("unreal_tournament")

return {
	name = "Unreal Tournament",
	description = mod:localize("mod_description"),
	is_togglable = true,
	options = {
		widgets = {
			-- the title and the tooltip are the localizations "multidodge" and "multidodge_description"
			{
				setting_id = "multidodge",
				type = "checkbox",
				default_value = false,
			},
		},
	},
}
