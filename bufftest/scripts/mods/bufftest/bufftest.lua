local mod = get_mod("bufftest")

local last_update = 0
local update_interval = 1

mod:hook_safe(BuffExtension, "update", function(self, unit, input, dt, context, t) 

	if unit ~= Managers.player:local_player().player_unit then return end

	last_update = last_update + dt

	if last_update < update_interval then return end

	last_update = 0

	print("\n\nEVENT BUFFS:")
	for event, buffs in pairs(self._event_buffs) do
		if #buffs > 0 then
			print(event)
			for _, buff in ipairs(buffs) do
				print("    " .. buff.buff_type)
			end
		end
	end

	print("\nLOST BUFFS:")
	for event, buffs in pairs(self._event_buffs) do
		for i, buff in ipairs(buffs) do
			if buff.event_buff_index ~= i then
				print(event .. buff.buff_type)
			end
		end
	end
end)