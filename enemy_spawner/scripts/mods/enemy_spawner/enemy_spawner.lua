--[[
	Author: IAmLupo	
--]]

local mod = get_mod("enemy_spawner")

local options_widgets = {
	{
		["setting_name"] = "spawn",
		["widget_type"] = "keybind",
		["text"] = "Spawn",
		["tooltip"] = "Press to spawn currently selected breed in front of you.",
		["default_value"] = {},
		["action"] = "spawn"
	},
	{
		["setting_name"] = "switch_breed",
		["widget_type"] = "keybind",
		["text"] = "Next Breed",
		["tooltip"] = "Press to switch to the next breed to spawn.",
		["default_value"] = {},
		["action"] = "switch_breed"
	},
	{
		["setting_name"] = "remove_all",
		["widget_type"] = "keybind",
		["text"] = "Despawn All",
		["tooltip"] = "Press to despawn every enemy in the level.",
		["default_value"] = {},
		["action"] = "remove_all"
	},
}


--[[
	Functions
--]] 

local errorMessage = "Must be host"

function mod.remove_all()
	local in_inn = Managers.state and Managers.state.game_mode and Managers.state.game_mode._game_mode_key == "inn"
	if in_inn then
		mod:echo("Cannot despawn enemies in the inn")
		return
	end
	if Managers.player and Managers.player.is_server then
		mod:pcall(function()
			Managers.state.conflict:destroy_all_units()
			mod:echo("Removed all enemies")
		end)
	else
		mod:echo(errorMessage)
	end
end

function mod.spawn()
	local in_inn = Managers.state and Managers.state.game_mode and Managers.state.game_mode._game_mode_key == "inn"
	if in_inn then
		mod:echo("Cannot spawn enemies in the inn")
		return
	end
	if Managers.player and Managers.player.is_server then
		mod:pcall(function()
			local conflict_director = Managers.state.conflict
			conflict_director:debug_spawn_breed(0)
			mod:echo("Spawned " .. conflict_director._debug_breed)
		end)
	else
		mod:echo(errorMessage)
	end
end

function mod.switch_breed()
	if Managers.player and Managers.player.is_server then
		mod:pcall(function()
			local conflict_director = Managers.state.conflict
			conflict_director:debug_spawn_switch_breed(0)
			mod:echo("Switched to " .. conflict_director._debug_breed)
		end)
	else
		mod:echo(errorMessage)
	end
end

--[[
	Execution
--]] 

mod:create_options(options_widgets, true, "Enemy Spawner", "Allows you to spawn and despawn enemies. Only works if you're the host.")
