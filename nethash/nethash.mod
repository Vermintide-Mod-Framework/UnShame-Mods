return {
	run = function()
		fassert(rawget(_G, "new_mod"), "nethash must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("nethash", {
			mod_script       = "scripts/mods/nethash/nethash",
			mod_data         = "scripts/mods/nethash/nethash_data",
			mod_localization = "scripts/mods/nethash/nethash_localization"
		})
	end,
	packages = {
		"resource_packages/nethash/nethash"
	}
}
