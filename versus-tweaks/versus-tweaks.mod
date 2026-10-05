return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`versus-tweaks` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("versus-tweaks", {
			mod_script       = "scripts/mods/versus-tweaks/versus-tweaks",
			mod_data         = "scripts/mods/versus-tweaks/versus-tweaks_data",
			mod_localization = "scripts/mods/versus-tweaks/versus-tweaks_localization",
		})
	end,
	packages = {
		"resource_packages/versus-tweaks/versus-tweaks",
	},
}
