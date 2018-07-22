return {
	run = function()
		fassert(rawget(_G, "new_mod"), "bufftest must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("bufftest", {
			mod_script       = "scripts/mods/bufftest/bufftest",
			mod_data         = "scripts/mods/bufftest/bufftest_data",
			mod_localization = "scripts/mods/bufftest/bufftest_localization"
		})
	end,
	packages = {
		"resource_packages/bufftest/bufftest"
	}
}
