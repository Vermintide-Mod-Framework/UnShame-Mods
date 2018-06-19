local mod = get_mod("huntsman_fix")

-- Removes empty (false) buff entries from the ends of event buff tables
local function cleanup_event_buffs(self)
	for _, event_buffs in pairs(self._event_buffs) do
		while true do
			if event_buffs[#event_buffs] == false then
				table.remove(event_buffs, #event_buffs)
			else
				break
			end
		end
	end
end

mod:hook_origin(BuffExtension, "remove_buff", function (self, id, handled_in_buff_update_function)
	local buffs = self._buffs
	local num_buffs = #buffs
	local end_time = Managers.time:time("game")
	local num_buffs_removed = 0
	local i = 1

	while num_buffs >= i do
		local buff = buffs[i]
		local template = buff.template
		buff_extension_function_params.bonus = buff.bonus
		buff_extension_function_params.multiplier = buff.multiplier
		buff_extension_function_params.t = end_time
		buff_extension_function_params.end_time = end_time
		buff_extension_function_params.attacker_unit = buff.attacker_unit

		if buff.id == id or (buff.parent_id and buff.parent_id == id) then
			self:_remove_sub_buff(buff, i, buff_extension_function_params)

			num_buffs = num_buffs - 1
			num_buffs_removed = num_buffs_removed + 1
		else
			i = i + 1
		end
	end

	-- Try removing empty buff entries from the ends of buff tables
	cleanup_event_buffs(self)

	return num_buffs_removed
end)

mod:hook_origin(BuffExtension, "_remove_sub_buff", function (self, buff, index, buff_extension_function_params)
	local world = self.world
	local template = buff.template
	local remove_buff_func = template.remove_buff_func

	if remove_buff_func then
		BuffFunctionTemplates.functions[remove_buff_func](self._unit, buff, buff_extension_function_params, world)
	end

	if template.stat_buff then
		self:_remove_stat_buff(buff)
	end

	local buff_to_remove = template.buff_to_add

	if buff_to_remove then
		for i, buff in ipairs(self._buffs) do
			local buff_type = buff.buff_type

			if buff_type == buff_to_remove and not buff.duration then
				buff.duration = 0
			end
		end
	end

	if template.event_buff then
		local event = template.event
		local event_buff_index = buff.event_buff_index

		-- Instead of using table.remove, set the buff entry to false
		-- This makes sure that other event_buff_indexs point to the right buffs
		self._event_buffs[event][event_buff_index] = false
	end

	table.remove(self._buffs, index)

	local id = buff.id
	local deactivation_sound = self._deactivation_sounds[id]

	if deactivation_sound then
		self:_play_buff_sound(deactivation_sound)
	end

	local continuous_screen_effect_id = self._continuous_screen_effects[id]

	if continuous_screen_effect_id then
		self:_stop_screen_effect(continuous_screen_effect_id)
	end

	local deactivation_screen_effect = self._deactivation_screen_effects[id]

	if deactivation_screen_effect then
		self:_play_screen_effect(deactivation_screen_effect)
	end
end)

mod:hook_origin(BuffExtension, "trigger_procs", function (self, event, ...)
	local event_buffs = self._event_buffs[event]
	local num_event_buffs = #event_buffs

	if num_event_buffs == 0 then
		return
	end

	local player = Managers.player:owner(self._unit)
	local num_args = select("#", ...)
	local params = FrameTable.alloc_table()
	local event_buffs_to_remove = FrameTable.alloc_table()

	for i = 1, num_args, 1 do
		local arg = select(i, ...)
		params[#params + 1] = arg
	end

	for i = 1, num_event_buffs, 1 do
		local buff = event_buffs[i]
		
		-- Check if the buff entry isn't empty
		if buff then
			local proc_chance = buff.proc_chance or 1

			if math.random() <= proc_chance then
				local buff_func = buff.buff_func
				local success = buff_func(player, buff, params)

				if success and buff.template.remove_on_proc then
					event_buffs_to_remove[#event_buffs_to_remove + 1] = buff
				end
			end
		end
	end

	for i = 1, #event_buffs_to_remove, 1 do
		local buff = event_buffs_to_remove[i]
		local id = buff.id

		self:remove_buff(id)
	end
end)


mod:hook_safe(BuffExtension, "add_buff", function (self, template_name, params)
    
    local id = self.id - 1

    for _, buff in ipairs(self._buffs) do
        if buff.id == id then return end
    end

    self._deactivation_sounds[id] = nil
	self._deactivation_screen_effects[id] = nil

	if self._continuous_screen_effects[id] then
		self:_stop_screen_effect(self._continuous_screen_effects[id])
	end

end)
