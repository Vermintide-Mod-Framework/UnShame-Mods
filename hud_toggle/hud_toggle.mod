local directory_name = "hud_toggle"
local file_name = "hud_toggle"

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
