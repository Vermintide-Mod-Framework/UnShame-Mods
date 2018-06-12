local mod = get_mod("salvage_on_loot_table")

return {
	name = "Loot Table: Salvage Loot",
	description = mod:localize("mod_description"),
  is_togglable = true,
  options_widgets = {
    {
      ["setting_name"] = "popup",
      ["widget_type"] = "checkbox",
      ["text"] = mod:localize("popup_text"),
      ["tooltip"] = mod:localize("popup_tooltip"),
      ["value_type"] = "boolean",
      ["default_value"] = false,
    }
  }
}