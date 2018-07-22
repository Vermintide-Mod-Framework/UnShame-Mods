return {
	run = function()
		fassert(rawget(_G, "new_mod"), "aidings_fix must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("aidings_fix", {
			mod_script       = "scripts/mods/aidings_fix/aidings_fix",
			mod_data         = "scripts/mods/aidings_fix/aidings_fix_data",
			mod_localization = "scripts/mods/aidings_fix/aidings_fix_localization"
		})
	end,
	packages = {
		"resource_packages/aidings_fix/aidings_fix"
	}
}
