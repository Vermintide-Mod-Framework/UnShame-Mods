local directory_name = "crosshair_customization"
local file_name = "crosshair_customization"

local main_script_path = "scripts/mods/"..directory_name.."/"..file_name

print("'"..file_name.."' Mod loading...")

local ret = {
	run = function()
		local mod = new_mod(file_name)
		mod:dofile(main_script_path)
	end,
	packages = {
		"resource_packages/"..directory_name.."/"..file_name
	},
}
return ret