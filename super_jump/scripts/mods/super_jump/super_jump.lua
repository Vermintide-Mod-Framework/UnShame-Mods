--[[
	Author: UnShame	
--]]

local mod = get_mod("super_jump")

--[[
	Hooks
--]] 

mod:hook("DamageSystem.rpc_take_falling_damage", function (func, ...)
	if Managers.player and Managers.player.is_server and mod:is_suspended() then
		return func(...)
	end
end)

--[[
	Callback
--]] 

mod.suspended = function()
	script_data.use_super_jumps = false
	mod:echo("You feel grounded again")
	mod:disable_all_hooks()
end

mod.unsuspended = function()
	script_data.use_super_jumps = true
	mod:echo("You feel much lighter")
	mod:enable_all_hooks()
end

--[[
	Execution
--]] 

-- Add option to mod settings menu (args: 1 = widget table, 2 = presence of checkbox in mod settings, 3 = descriptive name, 4 = description)
mod:create_options({}, true, "super_jump", "super_jump description")

-- Check for suspend setting
if mod:is_suspended() then
	script_data.use_super_jumps = false
	mod:disable_all_hooks()
else
	script_data.use_super_jumps = true
end
