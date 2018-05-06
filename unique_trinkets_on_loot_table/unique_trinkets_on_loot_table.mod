local directory_name = "unique_trinkets_on_loot_table"
local file_name = "unique_trinkets_on_loot_table"

local main_script_path = "scripts/mods/"..directory_name.."/"..file_name

return {
	run = function()
		local mod = new_mod(file_name)
		mod:initialize(main_script_path)
	end,
	packages = {
		"resource_packages/"..directory_name.."/"..file_name
	},
}
