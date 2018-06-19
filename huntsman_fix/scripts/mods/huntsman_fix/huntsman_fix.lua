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


mod:hook_origin(BuffExtension, "add_buff", function (self, template_name, params)
	local buff_template = BuffTemplates[template_name]
	local buffs = buff_template.buffs
	local start_time = Managers.time:time("game")
	local id = self.id
	local world = self.world

	for i, sub_buff_template in ipairs(buffs) do
		repeat
			local duration = sub_buff_template.duration
			local max_stacks = sub_buff_template.max_stacks
			local end_time = duration and start_time + duration

			if max_stacks then
				local has_max_stacks = false
				local stacks = 0

				for j = 1, #self._buffs, 1 do
					local existing_buff = self._buffs[j]

					if existing_buff.buff_type == sub_buff_template.name then
						if duration and sub_buff_template.refresh_durations then
							existing_buff.start_time = start_time
							existing_buff.duration = duration
							existing_buff.end_time = end_time
							existing_buff.attacker_unit = (params and params.attacker_unit) or nil
							local reapply_buff_func = sub_buff_template.reapply_buff_func

							if reapply_buff_func then
								buff_extension_function_params.bonus = existing_buff.bonus
								buff_extension_function_params.multiplier = existing_buff.multiplier
								buff_extension_function_params.t = start_time
								buff_extension_function_params.end_time = end_time
								buff_extension_function_params.attacker_unit = existing_buff.attacker_unit

								BuffFunctionTemplates.functions[reapply_buff_func](self._unit, existing_buff, buff_extension_function_params, world)
							end
						end

						stacks = stacks + 1

						if stacks == max_stacks then
							has_max_stacks = true

							break
						end
					end
				end

				if has_max_stacks then
					break
				elseif stacks == max_stacks - 1 then
					local on_max_stacks_func = sub_buff_template.on_max_stacks_func

					if on_max_stacks_func then
						local player = Managers.player:owner(self._unit)

						if player then
							on_max_stacks_func(player, sub_buff_template)
						end
					end

					if sub_buff_template.reset_on_max_stacks then
						local num_buffs = #self._buffs
						local j = 1

						while num_buffs >= j do
							local buff = self._buffs[j]

							if buff.buff_type == sub_buff_template.name then
								buff_extension_function_params.bonus = buff.bonus
								buff_extension_function_params.multiplier = buff.multiplier
								buff_extension_function_params.t = start_time
								buff_extension_function_params.end_time = buff.duration and buff.start_time + buff.duration
								buff_extension_function_params.attacker_unit = buff.attacker_unit

								self:_remove_sub_buff(buff, j, buff_extension_function_params)

								num_buffs = num_buffs - 1
							else
								j = j + 1
							end
						end

						break
					end
				end
			end

			local buff = {
				id = id,
				parent_id = params and params.parent_id,
				start_time = start_time,
				template = sub_buff_template,
				buff_type = sub_buff_template.name,
				attacker_unit = (params and params.attacker_unit) or nil
			}
			local bonus = sub_buff_template.bonus
			local multiplier = sub_buff_template.multiplier
			local proc_chance = sub_buff_template.proc_chance
			local range = sub_buff_template.range
			local damage_source, power_level, spawned_unit_go_id = nil

			if params then
				local variable_value = params.variable_value

				if variable_value then
					local variable_bonus_table = sub_buff_template.variable_bonus

					if variable_bonus_table then
						local bonus_index = (variable_value == 1 and #variable_bonus_table) or 1 + math.floor(variable_value / (1 / #variable_bonus_table))
						bonus = variable_bonus_table[bonus_index]
					end

					local variable_multiplier_table = sub_buff_template.variable_multiplier

					if variable_multiplier_table then
						local min_multiplier = variable_multiplier_table[1]
						local max_multiplier = variable_multiplier_table[2]
						multiplier = math.lerp(min_multiplier, max_multiplier, variable_value)
					end
				end

				if not params.external_optional_bonus then
				end

				if not params.external_optional_multiplier then
				end

				if not params.external_optional_proc_chance then
				end

				if not params.external_optional_duration then
				end

				if not params.external_optional_range then
				end

				damage_source = params.damage_source
				power_level = params.power_level
				spawned_unit_go_id = params.spawned_unit_go_id
			end

			buff.bonus = bonus
			buff.multiplier = multiplier
			buff.proc_chance = proc_chance
			buff.duration = duration
			buff.range = range
			buff.damage_source = damage_source
			buff.power_level = power_level
			buff.spawned_unit_go_id = spawned_unit_go_id
			buff_extension_function_params.bonus = bonus
			buff_extension_function_params.multiplier = multiplier
			buff_extension_function_params.t = start_time
			buff_extension_function_params.end_time = end_time
			buff_extension_function_params.attacker_unit = buff.attacker_unit
			local apply_buff_func = sub_buff_template.apply_buff_func

			if apply_buff_func then
				BuffFunctionTemplates.functions[apply_buff_func](self._unit, buff, buff_extension_function_params, world)
			end

			if sub_buff_template.stat_buff then
				local index = self:_add_stat_buff(sub_buff_template, buff)
				buff.stat_buff_index = index
			end

			if sub_buff_template.event_buff then
				local buff_func = sub_buff_template.buff_func
				local event = sub_buff_template.event
				buff.buff_func = buff_func
				local event_buffs = self._event_buffs[event]
				local index = #event_buffs + 1
				buff.event_buff_index = index
				event_buffs[index] = buff
			end

			if sub_buff_template.buff_after_delay then
				local delayed_buff_name = sub_buff_template.delayed_buff_name
				buff.delayed_buff_name = delayed_buff_name
			end

			self._buffs[#self._buffs + 1] = buff
		until true
	end

	local activation_sound = buff_template.activation_sound

	if activation_sound then
		self:_play_buff_sound(activation_sound)
	end

	local activation_effect = buff_template.activation_effect

	if activation_effect then
		self:_play_screen_effect(activation_effect)
	end

	local continuous_effect = buff_template.continuous_effect

    if continuous_effect 
        -- Check that a continuous effect isn't already playing
        and not self._continuous_screen_effects[id]
    then
		self._continuous_screen_effects[id] = self:_play_screen_effect(continuous_effect)
	end

	local deactivation_effect = buff_template.deactivation_effect

	if deactivation_effect then
		self._deactivation_screen_effects[id] = deactivation_effect
	end

	local deactivation_sound = buff_template.deactivation_sound

	if deactivation_sound then
		self._deactivation_sounds[id] = deactivation_sound
	end

	self.id = id + 1

	return id
end)