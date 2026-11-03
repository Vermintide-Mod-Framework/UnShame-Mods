return {
	run = function()
		fassert(rawget(_G, "new_mod"), "`Unreal Tournament Extras` mod must be lower than Vermintide Mod Framework in your launcher's load order.")
		-- The extras use the Unreal Tournament mod's weapons and code, so that mod must be loaded first
		fassert(get_mod("unreal_tournament"), "`Unreal Tournament Extras` mod needs the `Unreal Tournament` mod, and must be lower than it in your launcher's load order.")

		new_mod("unreal_tournament_extras", {
			mod_script       = "scripts/mods/unreal_tournament_extras/unreal_tournament_extras",
			mod_data         = "scripts/mods/unreal_tournament_extras/unreal_tournament_extras_data",
			mod_localization = "scripts/mods/unreal_tournament_extras/unreal_tournament_extras_localization",
		})
	end,
	packages = {
		"resource_packages/unreal_tournament_extras/unreal_tournament_extras",
	},
}
