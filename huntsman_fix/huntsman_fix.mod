return {
	run = function()
		fassert(rawget(_G, "new_mod"), "huntsman_fix must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("huntsman_fix", {
			mod_script       = "scripts/mods/huntsman_fix/huntsman_fix",
			mod_data         = "scripts/mods/huntsman_fix/huntsman_fix_data",
			mod_localization = "scripts/mods/huntsman_fix/huntsman_fix_localization"
		})
	end,
	packages = {
		"resource_packages/huntsman_fix/huntsman_fix"
	}
}
