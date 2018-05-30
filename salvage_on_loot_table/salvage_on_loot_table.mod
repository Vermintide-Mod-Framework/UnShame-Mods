return {
	run = function()
		local mod_resources = {
			mod_script       = "scripts/mods/salvage_on_loot_table/salvage_on_loot_table",
			mod_data         = "scripts/mods/salvage_on_loot_table/salvage_on_loot_table_data",
			mod_localization = "scripts/mods/salvage_on_loot_table/salvage_on_loot_table_localization"
		}
		new_mod("salvage_on_loot_table", mod_resources)
	end,
	packages = {
		"resource_packages/salvage_on_loot_table/salvage_on_loot_table"
	}
}