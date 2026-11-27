return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Red Moon Inn` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("red_moon_inn", {
			mod_script       = "scripts/mods/red_moon_inn/red_moon_inn",
			mod_data         = "scripts/mods/red_moon_inn/red_moon_inn_data",
			mod_localization = "scripts/mods/red_moon_inn/red_moon_inn_localization",
		})
	end,
	packages = {
		"resource_packages/red_moon_inn/red_moon_inn",
	},
}
