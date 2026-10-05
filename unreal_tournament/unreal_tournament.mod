return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Unreal Tournament` mod must be lower than Vermintide Mod Framework in your launcher's load order.")

		new_mod("unreal_tournament", {
			mod_script       = "scripts/mods/unreal_tournament/unreal_tournament",
			mod_data         = "scripts/mods/unreal_tournament/unreal_tournament_data",
			mod_localization = "scripts/mods/unreal_tournament/unreal_tournament_localization",
		})
	end,
	packages = {
		"resource_packages/unreal_tournament/unreal_tournament",
	},
}
