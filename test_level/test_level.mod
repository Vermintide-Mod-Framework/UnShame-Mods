return {
	run = function()
		fassert(rawget(_G, "new_mod"), "Test Level must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("test_level", {
			mod_script       = "scripts/mods/test_level/test_level",
			mod_data         = "scripts/mods/test_level/test_level_data",
			mod_localization = "scripts/mods/test_level/test_level_localization"
		})
	end,
	packages = {
		"resource_packages/test_level/test_level"
	}
}
