local mod = get_mod("hud_toggle")

local setting_strings = {
	"ELEMENTS",
	"OBJECTIVES",
	"OUTLINES",
	"CROSSHAIR",
	"PING",
	"FEEDBACK",
	"WEAPON"
}

return {
	name = "HUD Toggle",
	description = mod:localize("mod_description"),
	is_togglable = true,
	options_widgets = {
    {
      ["setting_name"] = "toggle_group",
      ["widget_type"] = "group",
      ["text"] = "Toggle Elements",
      ["sub_widgets"] = {
        --[[ELEMENTS = ]]{
          ["setting_name"] = setting_strings[1],
          ["widget_type"] = "checkbox",
          ["text"] = "HUD Elements",
          ["tooltip"] = "Whether to display HUD elements like equipment, health bars, stamina and overcharge.",
          ["default_value"] = true,
        },
        --[[OBJECTIVES = ]]{
          ["setting_name"] = setting_strings[2],
          ["widget_type"] = "checkbox",
          ["text"] = "Objectives",
          ["tooltip"] = "Whether to display objective banner, markers and button prompts.",
          ["default_value"] = true,
        },
        --[[OUTLINES = ]]{
          ["setting_name"] = setting_strings[3],
          ["widget_type"] = "checkbox",
          ["text"] = "Outlines",
          ["tooltip"] = "Whether to display player, object and item outlines.\n" ..
            "Overrides Player Outlines Always On setting.",
          ["default_value"] = true,
        },
        --[[CROSSHAIR = ]]{
          ["setting_name"] = setting_strings[4],
          ["widget_type"] = "checkbox",
          ["text"] = "Crosshair",
          ["tooltip"] = "Whether to display crosshair.",
          ["default_value"] = true,
        },
        --[[PING = ]]{
          ["setting_name"] = setting_strings[5],
          ["widget_type"] = "checkbox",
          ["text"] = "Ping",
          ["tooltip"] = "Whether enemies, players and items can be pinged.",
          ["default_value"] = true,
        },
        --[[FEEDBACK = ]]{
          ["setting_name"] = setting_strings[6],
          ["widget_type"] = "checkbox",
          ["text"] = "Feedback",
          ["tooltip"] = "Whether damage indicators, special kills and assists are shown.\n",
          ["default_value"] = true,
        },
        --[[WEAPON = ]]{
          ["setting_name"] = setting_strings[7],
          ["widget_type"] = "checkbox",
          ["text"] = "Weapon Model",
          ["tooltip"] = "Whether to display weapon model and hands.",
          ["default_value"] = true,
        },
      },
    },

    {
      ["setting_name"] = "hud_toggle",
      ["widget_type"] = "keybind",
      ["text"] = "Toggle All",
      ["default_value"] = {},
      ["action"] = "toggle"
    },
    {
      ["setting_name"] = "hud_more",
      ["widget_type"] = "keybind",
      ["text"] = "Show More",
      ["tooltip"] = "Show more HUD elements",
      ["default_value"] = {},
      ["action"] = "more"
    },
    {
      ["setting_name"] = "hud_less",
      ["widget_type"] = "keybind",
      ["text"] = "Show Less",
      ["tooltip"] = "Show fewer HUD elements",
      ["default_value"] = {},
      ["action"] = "less"
    }
  }
}