return {
	run = function()
		local mod_resources = {
			mod_script       = "scripts/mods/hud_toggle/hud_toggle",
			mod_data         = "scripts/mods/hud_toggle/hud_toggle_data",
			mod_localization = "scripts/mods/hud_toggle/hud_toggle_localization"
		}
		new_mod("hud_toggle", mod_resources)
	end,
	packages = {
		"resource_packages/hud_toggle/hud_toggle"
	}
}
