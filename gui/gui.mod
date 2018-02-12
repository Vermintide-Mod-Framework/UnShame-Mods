local directory_name = "gui"
local file_name = "gui"

print("'" ..file_name.. "' Mod loading...")

return {
	run = function()
		new_mod("basic_gui"):dofile("scripts/mods/basic_gui/basic_gui")
		new_mod("gui"):dofile("scripts/mods/gui/gui")
	end,
	packages = {
		"resource_packages/" .. directory_name .. "/" .. file_name
	},
}