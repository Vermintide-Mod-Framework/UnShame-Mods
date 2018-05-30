return {
	run = function()
		local mod_resources = {
			mod_script       = "scripts/mods/unique_trinkets_on_loot_table/unique_trinkets_on_loot_table",
			mod_data         = "scripts/mods/unique_trinkets_on_loot_table/unique_trinkets_on_loot_table_data",
			mod_localization = "scripts/mods/unique_trinkets_on_loot_table/unique_trinkets_on_loot_table_localization"
		}
		new_mod("unique_trinkets_on_loot_table", mod_resources)
	end,
	packages = {
		"resource_packages/unique_trinkets_on_loot_table/unique_trinkets_on_loot_table"
	}
}
