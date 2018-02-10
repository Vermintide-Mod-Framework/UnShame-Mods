--[[
	Author: Walterr	
	Mod which shows player equipment in the Player List screen
--]]

local mod = get_mod("player_list_equipment")

-- Quest view widget definitions
mod.definitions = local_require("scripts/ui/quest_view/quest_view_definitions")

mod.relevant_style_ids = {
	tooltip_text = true,
	item_reward_texture = true,
	item_reward_frame_texture = true,
}
 
mod.padding = {
	y = 50
}

mod.equipment_slots = {
	"slot_melee",
	"slot_ranged",
	"slot_trinket_1",
	"slot_trinket_2",
	"slot_trinket_3",
}

--[[
	Collected trait information from all human players
]]--
mod.player_traits = {}

--[[
	Event that triggers when the local player traits has been updated
]]--
mod.player_traits_event = EMPTY_FUNC

-- Borrow some more code from Quests & Contracts for generating item tooltips.
if not PLAYERLIST_QUEST_VIEW then
	PLAYERLIST_QUEST_VIEW = {
		ui_renderer = nil,
		
		_get_number_of_rows = QuestView._get_number_of_rows,
		_get_item_tooltip = QuestView._get_item_tooltip, -- is needed because _get_number_of_rows is using it
	}
end

-- ####################################################################################################################
-- ##### Functions ####################################################################################################
-- ####################################################################################################################

-- Creates a widget to show a single item of equipment (as an icon: we borrow some code from the
-- Quests & Contracts UI to create it).
mod.create_equipment_widget = function(x_offset, y_offset)
	local widget = mod.definitions.create_quest_widget("player_list")
	widget.scenegraph_id = "player_list"
	local passes = widget.element.passes
	
	widget.content.active = true
	
	-- The quest widget contains a bunch of elements we dont want - remove them and
	-- zero out the offsets of the ones we keep.
	for i = #passes, 1, -1 do
		local style_id = passes[i].style_id
		
		if not mod.relevant_style_ids[style_id] then
			table.remove(passes, i)
		elseif style_id == "tooltip_text" then
			widget.style[style_id].cursor_offset = { 32, -120 }
		else
			local offset = widget.style[style_id].offset
			
			offset[1] = x_offset
			offset[2] = y_offset
		end
	end
	
	return UIWidget.init(widget)
end

-- Create all the equipment widgets and add them to the given IngamePlayerListUI instance.
mod.create_equipment_widgets = function(player_list_ui)
	PLAYERLIST_QUEST_VIEW.ui_renderer = player_list_ui.ui_renderer
 
	local extra_y_offset = 0
	local equipment_widgets = {}
	player_list_ui.player_list_equipment_widgets = equipment_widgets
 
	for i, player_list_widget in ipairs(player_list_ui.player_list_widgets) do
		-- adjust the Y offsets of existing widgets to create room for the equipment icons
		local styles = player_list_widget.style
		local y_offset = styles.offset[2] - extra_y_offset
		styles.offset[2] = y_offset
 
		for style_id, style in pairs(styles) do
			if style.offset and style_id ~= "tooltip_text" then
				style.offset[2] = style.offset[2] - extra_y_offset
			end
		end
 
		-- create the new equipment icon widgets.
		local x_offset = 1024
		y_offset = y_offset - 56
		local slot_widgets = {}
		for _, equipment_slot in ipairs(mod.equipment_slots) do
			slot_widgets[equipment_slot] = mod.create_equipment_widget(x_offset, y_offset)
			x_offset = x_offset + 78
		end
		equipment_widgets[i] = slot_widgets
		extra_y_offset = extra_y_offset + mod.padding.y
	end
end

mod.generate_item_tooltip = function(item, item_key, style, player, slot_name)
	local text = ""
	local color = {}
	
	mod:pcall(function()
		-- Generate text
		if slot_name == "slot_melee" or slot_name == "slot_ranged" then
			local trait_template = BuffTemplates[item.traits[1]]
			text, color = mod.generate_weapon_tooltip(item, item_key, style, player, slot_name, trait_template)
			
			-- Check if proc data exist from player
			local id = tostring(player.peer_id)
			if not mod.player_traits[id] then
				text = text .. "No trait data available\n"
				color[#color + 1] = Colors.get_color_table_with_alpha("red", 255)
			end
		else
			local trait_template = BuffTemplates[item_key]
			text, color = mod.generate_trinket_tooltip(item, item_key, style, player, slot_name, trait_template)
		end
	end)
	
	return text, color
end

mod.generate_trinket_tooltip = function(item, item_key, style, player, slot_name, trait_template)
	local text = ""
	local color = {}
	
	-- Item name
	text = text .. Localize(item.display_name) .. "\n"
	color[#color + 1] = Colors.get_table(item.rarity)
	
	if trait_template then -- trinket with trait_template
		local display_name = trait_template.display_name or "Unknown"
		local description_text = BackendUtils.get_trait_description(item_key, item.rarity)
		local description_rows = PLAYERLIST_QUEST_VIEW:_get_number_of_rows(style, description_text)
		
		-- Empty space
		text = text .. "\n"
		color[#color + 1] = Colors.get_color_table_with_alpha("white", 255)
		
		-- Trait name
		text = text .. Localize(display_name) .. "\n"
		color[#color + 1] = Colors.get_color_table_with_alpha("cheeseburger", 255)
		
		-- Trait description
		text = text .. description_text .. "\n"
		for k = 1, description_rows, 1 do
			color[#color + 1] = Colors.get_color_table_with_alpha("white", 255)
		end
	elseif item.traits[1] then -- trinket with only description
		local description_text = BackendUtils.get_trait_description(item.traits[1], item.rarity)
		local description_rows = PLAYERLIST_QUEST_VIEW:_get_number_of_rows(style, description_text)
		
		-- Empty space
		text = text .. "\n"
		color[#color + 1] = Colors.get_color_table_with_alpha("white", 255)
		
		-- Trinket description
		text = text .. description_text .. "\n"
		for k = 1, description_rows, 1 do
			color[#color + 1] = Colors.get_color_table_with_alpha("white", 255)
		end
	end
	
	return text, color
end

mod.generate_weapon_tooltip = function(item, item_key, style, player, slot_name, trait_template)
	local text = ""
	local color = {}
	
	-- Item name
	text = text .. Localize(item.display_name) .. "\n"
	color[#color + 1] = Colors.get_table(item.rarity)
	
	if trait_template then
		local display_name = trait_template.display_name or "Unknown"
		
		for _, trait_name in ipairs(item.traits) do
			trait_template = BuffTemplates[trait_name]
			local description_text = mod.get_weapon_trait_description(item, player, slot_name, trait_template, trait_name)
			local description_rows = PLAYERLIST_QUEST_VIEW:_get_number_of_rows(style, description_text)
			
			-- Empty space
			text = text .. "\n"
			color[#color + 1] = Colors.get_color_table_with_alpha("white", 255)
			
			-- Trait name
			text = text .. Localize(trait_template.display_name) .. "\n"
			color[#color + 1] = Colors.get_color_table_with_alpha("cheeseburger", 255)
			
			-- Trait description
			text = text .. description_text .. "\n"
			for k = 1, description_rows, 1 do
				color[#color + 1] = Colors.get_color_table_with_alpha("white", 255)
			end
		end
	end
	
	return text, color
end

--[[
	Generates the weapon description text based on the proc information.
	
	Because there doesnt exist a function to generate the text based with proc data parameter
	we need to set the proc data into our account and generate the text. After we need to restore
	our orginal proc data.
]]--
mod.get_weapon_trait_description = function(item, player, slot_name, trait_template, trait_name)
	local backup_proc = {}
	local id = tostring(player.peer_id)
	
	if not trait_template.buffs[1] then
		return ""
	end
	
	if trait_template.buffs[1].proc_chance then
		-- Save proc
		backup_proc = table.clone(trait_template.buffs[1].proc_chance)
		
		-- Edit Proc data
		if mod.player_traits[id] then
			local player_traits = mod.player_traits[id][slot_name]
			
			if #trait_template.buffs[1].proc_chance > 1 then
				for _, player_trait in ipairs(player_traits) do
					if player_trait.trait_name == trait_name then
						trait_template.buffs[1].proc_chance[1] = player_trait.proc_chance
					end
				end
			end
		end
	end
	
	-- Generate trait description text
	local text = BackendUtils.get_trait_description(trait_name, item.rarity)
	
	--Restore proc data
	if trait_template.buffs[1].proc_chance then
		trait_template.buffs[1].proc_chance = backup_proc
	end
	
	return text
end

--[[
	Collect the trait proc data out of the local user.
]]--
mod.update_player_traits = function()
	local player = Managers.player and Managers.player:local_player()
	
	if player then
		local peer_id = tostring(player.peer_id)
		local profile_index = player.profile_index
		
		if profile_index and SPProfiles[profile_index] then
			local player_name = SPProfiles[profile_index].display_name
			
			if player_name then
				local loadout = backend_items._loadout[player_name]
				
				mod.player_traits[peer_id] = {
					["slot_melee"] = ScriptBackendItem.get_traits(loadout["slot_melee"]),
					["slot_ranged"] = ScriptBackendItem.get_traits(loadout["slot_ranged"])
				}
			end
		end
	end
end

-- ####################################################################################################################
-- ##### Hook #########################################################################################################
-- ####################################################################################################################
-- UPDATE 1.8.5 FUNCTION DOESN'T SEEM TO EXIST ANYMORE
mod:hook("IngamePlayerListUI.create_ui_elements", function (func, self)
	func(self)
	
	mod.create_equipment_widgets(self)
end)

mod:hook("IngamePlayerListUI.update_widgets", function (func, self)
	func(self)
	
	-- UPDATE 1.8.5 FIX
	if not self.player_list_equipment_widgets then
		mod.create_equipment_widgets(self)
	end
	
	mod:pcall(function()
	local players = self.players
	
	for i = 1, self.num_players, 1 do
		-- update this player's equipment icons.
		local player_unit = players[i].player.player_unit
		local inventory_extn = ScriptUnit.has_extension(player_unit, "inventory_system")
		local attachment_extn = ScriptUnit.has_extension(player_unit, "attachment_system")
		local widgets = self.player_list_equipment_widgets[i]
 
		for slot_name, widget in pairs(widgets) do
			local content = widget.content
 
			local slot_data = inventory_extn and inventory_extn:get_slot_data(slot_name)
			if not slot_data then
				slot_data = attachment_extn and attachment_extn._attachments.slots[slot_name]
			end
			local item_key = slot_data and slot_data.item_data.key
			local item = item_key and ItemMasterList[item_key]
			if item then
				--This code taken from _assign_widget_data in scripts/ui/quest_view/quest_view.lua
				local style = widget.style
				
				-- Color
				local item_color = Colors.get_table(item.rarity)
				style.item_reward_frame_texture.color = item_color
				style.tooltip_text.line_colors[1] = item_color
				
				-- Tooltip information
				content.tooltip_text, style.tooltip_text.line_colors = mod.generate_item_tooltip(
							item, item_key, style.tooltip_text, players[i].player, slot_name)
				
				if item.item_type ~= "bw_staff_firefly_flamewave" and
					(slot_name == "slot_ranged" or slot_name == "slot_melee") then
					content.item_reward_texture = "forge_icon_" .. item.item_type
				else
					content.item_reward_texture = item.inventory_icon
				end
			end
			content.has_item = not not item
		end
	end
	end)
end)
 
mod:hook("IngamePlayerListUI.draw", function (func, self, dt)
	func(self, dt)
 
	mod:pcall(function()
	local ui_renderer = self.ui_renderer
	local input_service = self.input_manager:get_service("player_list_input")
	
	UIRenderer.begin_pass(ui_renderer, self.ui_scenegraph, input_service, dt, nil, self.render_settings)
 
	-- draw the equipment icons.
	for i = 1, self.num_players, 1 do
		local widgets = self.player_list_equipment_widgets[i]
		
		for _, widget in pairs(widgets) do
			UIRenderer.draw_widget(ui_renderer, widget)
		end
	end
 
	UIRenderer.end_pass(ui_renderer)
	end)
end)
 
mod:hook("IngamePlayerListUI.set_active", function (func, self, active)
	func(self, active)
	
	if active then
		-- update the equipment icons in case the player has changed his equipment.
		self:update_widgets()
	end
end)

-- ####################################################################################################################
-- ##### Network ######################################################################################################
-- ####################################################################################################################
--[[
	Request:
		When we reload the mod
		When we start/join a game
	
	Respond:
		When we leave the inventory
]]--

--[[mod.send_local_traits = function(sender_id)
	local player = Managers.player:local_player()
	if player then
		local id = tostring(player.peer_id)
		
		if mod.player_traits[id] then
			for slot_name, player_trait in pairs(mod.player_traits[id]) do
				Mods.network.send_rpc(
					"rpc_player_list_enquiptment_response",
					sender_id, slot_name, player_trait
				)
			end
		end
	end
end

mod.send_local_traits_to_all = function()
	local local_player = Managers.player:local_player()
	local human_players = Managers.player:human_players()
	
	for _, player in pairs(human_players) do
		if local_player.peer_id ~= player.peer_id then
			mod.send_local_traits(player.peer_id)
		end
	end
end

mod.request_local_traits_to_all = function()
	local local_player = Managers.player:local_player()
	local human_players = Managers.player:human_players()
	
	for _, player in pairs(human_players) do
		if local_player.peer_id ~= player.peer_id then
			Mods.network.send_rpc("rpc_player_list_enquiptment_request", player.peer_id)
		end
	end
end

Mods.network.register("rpc_player_list_enquiptment_request", function(sender_id)
	mod:pcall(function()
		-- Update player traits list
		mod.update_player_traits()
		
		mod.send_local_traits(sender_id)
	end)
end)

Mods.network.register("rpc_player_list_enquiptment_response", function(sender_id, slot_name, player_trait)
	mod:pcall(function()
		local id = tostring(sender_id)
		
		if mod.player_traits[id] == nil then
			mod.player_traits[id] = {}
		end
		
		-- Update record
		local player = Managers.player:local_player()
		if player then
			if id ~= tostring(player.peer_id) then
				mod.player_traits[id][slot_name] = table.clone(player_trait)
			end
		end
	end)
end)

mod:hook("MatchmakingManager.update", function(func, ...)
	func(...)
	
	local player = Managers.player:local_player()
	if player then
		local id = tostring(player.peer_id)
		if mod.player_traits[id] == nil then
			mod.update_player_traits()
			
			if mod.player_traits[id] then
				mod.player_traits_event()
			end
		end
	end
end)

mod:hook("InventoryView.post_update_on_exit", function(func, ...)
	func(...)
	
	local player = Managers.player:local_player()
	if player then
		local id = tostring(player.peer_id)
		
		mod.player_traits[id] = nil
		mod.player_traits_event = function()
			mod.send_local_traits_to_all()
		end
	end
end)

--InventoryView.post_update_on_exit

mod:hook("StateInGameRunning.event_game_started", function(func, ...)
	func(...)
	
	local player = Managers.player:local_player()
	if player then
		local id = tostring(player.peer_id)
		
		mod.player_traits[id] = nil
		mod.player_traits_event = function()
			mod.send_local_traits_to_all()
			mod.request_local_traits_to_all()
		end
	end
end)--]]


--[[ 
	Hooks
]]--
mod.suspended = function()
	mod:disable_all_hooks()
end

mod.unsuspended = function()
	mod:enable_all_hooks()
end

-- Check for suspend setting
if mod:is_suspended() then
	mod.suspended()
end

-- ####################################################################################################################
-- ##### Start ########################################################################################################
-- ####################################################################################################################
mod:create_options({}, true, "Player List Equipment", "Displays players equipment in the TAB menu.")
mod.update_player_traits()
--mod.request_local_traits_to_all()
