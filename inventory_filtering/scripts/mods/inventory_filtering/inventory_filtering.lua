--[[
	Author: Grundlid	
--]]

local mod = get_mod("inventory_filtering")
local gui = get_mod("gui")
local basic_gui = get_mod("basic_gui")


mod.filters = {}
mod.favs = {}
mod.hotkey = "r"
mod.any_screen_open = false
mod.force_refresh = false
mod.view_tab_changed = false

mod.focus_window = function(window)
	window:focus()
end

mod.rarity_order = {
	common = 4,
	promo = 6,
	plentiful = 5,
	exotic = 2,
	rare = 3,
	unique = 1
}

mod.sort_by_loadout_rarity_name = function(a, b)

	if a.equipped and not b.equipped then
		return true
	elseif b.equipped and not a.equipped then
		return false
	else
		if mod:is_favorite(a.backend_id) and not mod:is_favorite(b.backend_id) then
			return true
		elseif not mod:is_favorite(a.backend_id) and mod:is_favorite(b.backend_id) then
			return false
		else
			local a_rarity_order = mod.rarity_order[a.rarity]
			local b_rarity_order = mod.rarity_order[b.rarity]

			if a_rarity_order == b_rarity_order then
				local a_name = a.localized_name
				local b_name = b.localized_name

				if a_name == b_name then
					return a.backend_id < b.backend_id
				end

				return a_name < b_name
			else
				return a_rarity_order < b_rarity_order
			end
		end
	end

	return 
end

mod.sort_by_rarity_name = function(a, b)
	local a_rarity_order = mod.rarity_order[a.rarity]
	local b_rarity_order = mod.rarity_order[b.rarity]

	if a_rarity_order == b_rarity_order then
		local a_name = a.localized_name
		local b_name = b.localized_name

		if a_name == b_name then
			return a.backend_id < b.backend_id
		end

		return a_name < b_name
	else
		return a_rarity_order < b_rarity_order
	end

	return 
end

mod.filter_operators = {
	["find"] = {
		5,
		2,
		function (op1, op2)
			return (string.find(string.lower(op1), string.lower(string.gsub(tostring(op2), "_", " "))) ~= nil)
		end
	},
	["not"] = {
		4,
		1,
		function (op1)
			return not op1
		end
	},
	["<"] = {
		3,
		2,
		function (op1, op2)
			return op1 < op2
		end
	},
	[">"] = {
		3,
		2,
		function (op1, op2)
			return op2 < op1
		end
	},
	["<="] = {
		3,
		2,
		function (op1, op2)
			return op1 <= op2
		end
	},
	[">="] = {
		3,
		2,
		function (op1, op2)
			return op2 <= op1
		end
	},
	["~="] = {
		3,
		2,
		function (op1, op2)
			return op1 ~= op2
		end
	},
	["=="] = {
		3,
		2,
		function (op1, op2)
			return op1 == op2
		end
	},
	["and"] = {
		2,
		2,
		function (op1, op2)
			return op1 and op2
		end
	},
	["or"] = {
		1,
		2,
		function (op1, op2)
			return op1 or op2
		end
	}
}

mod.filter_macros = {
	trait_names =  function (item_data, backend_id)
		local trait_names = ""
		if item_data.traits then
			for _, trait_name in ipairs(item_data.traits) do
				trait_names = trait_names.." "..Localize(BuffTemplates[trait_name].display_name)
			end
		end
		return trait_names
	end,
	item_name = function (item_data, backend_id)
		return Localize(item_data.display_name).." "..Localize(item_data.item_type)
	end,
	trait_names_and_item_name =  function (item_data, backend_id)
		local trait_names = ""
		if item_data.traits then
			for _, trait_name in ipairs(item_data.traits) do
				trait_names = trait_names.." "..Localize(BuffTemplates[trait_name].display_name)
			end
		end
		return Localize(item_data.display_name).." "..Localize(item_data.item_type).." "..trait_names
	end,
	is_fav = function (item_data, backend_id)
		return mod:is_favorite(backend_id)
	end,
	are_traits_locked = function (item_data, backend_id)
		local slot_type = item_data.slot_type
		local is_trinket = slot_type == "trinket"
		if is_trinket or slot_type == "hat" then
			return false
		end
		local traits = item_data.traits
		local any_trait_unlocked = false
		if traits then
			for i = #traits, 1, -1 do
				local trait_name = traits[i]
				local trait_template = BuffTemplates[trait_name]

				if trait_template then
					any_trait_unlocked = any_trait_unlocked or (BackendUtils.item_has_trait(backend_id, trait_name) and true)
				end
			end
		end
		return not any_trait_unlocked
	end,
	item_key = function (item_data, backend_id)
		return item_data.key
	end,
	item_rarity = function (item_data, backend_id)
		return item_data.rarity
	end,
	slot_type = function (item_data, backend_id)
		return item_data.slot_type
	end,
	item_type = function (item_data, backend_id)
		return item_data.item_type
	end,
	trinket_as_hero = function (item_data, backend_id)
		if item_data.traits then
			for _, trait_name in ipairs(item_data.traits) do
				local trait_config = BuffTemplates[trait_name]
				local roll_dice_as_hero = trait_config.roll_dice_as_hero

				if roll_dice_as_hero then
					return true
				end
			end
		end

		return 
	end,
	equipped_by = function (item_data, backend_id)
		local hero = ScriptBackendItem.equipped_by(backend_id)

		return hero
	end,
	current_hero = function (item_data, backend_id)
		local profile_synchronizer = Managers.state.network.profile_synchronizer
		local player = Managers.player:local_player()
		local profile_index = profile_synchronizer.profile_by_peer(profile_synchronizer, player.network_id(player), player.local_player_id(player))
		local hero_data = SPProfiles[profile_index]
		local hero_name = hero_data.display_name

		return hero_name
	end,
	can_wield_bright_wizard = function (item_data, backend_id)
		local hero_name = "bright_wizard"
		local can_wield = item_data.can_wield

		return table.has_item(can_wield, hero_name)
	end,
	can_wield_dwarf_ranger = function (item_data, backend_id)
		local hero_name = "dwarf_ranger"
		local can_wield = item_data.can_wield

		return table.has_item(can_wield, hero_name)
	end,
	can_wield_empire_soldier = function (item_data, backend_id)
		local hero_name = "empire_soldier"
		local can_wield = item_data.can_wield

		return table.has_item(can_wield, hero_name)
	end,
	can_wield_witch_hunter = function (item_data, backend_id)
		local hero_name = "witch_hunter"
		local can_wield = item_data.can_wield

		return table.has_item(can_wield, hero_name)
	end,
	can_wield_wood_elf = function (item_data, backend_id)
		local hero_name = "wood_elf"
		local can_wield = item_data.can_wield

		return table.has_item(can_wield, hero_name)
	end,
	player_owns_item_key = function (item_data, backend_id)
		local all_items = ScriptBackendItem.get_all_backend_items()

		for backend_id, config in pairs(all_items) do
			if item_data.key == config.key then
				return true
			end
		end

		return false
	end
}

mod.element_settings = {
	height_spacing = 4.5,
	height = 115,
	width = 535
}

mod.execute_filter = function(textbox)
	if mod.any_screen_open then
		local button = textbox.window:get_widget("btn_clear_search")
		if textbox.text and #textbox.text > 0 then
			mod.filters = {}
			for term in string.gmatch(textbox.text, "%S+") do
				mod.filters[#mod.filters+1] = term
			end
			if button then button.visible = true end
		else
			mod.filters = {}
			if button then button.visible = false end
		end
		local favorites = textbox.window:get_widget("chk_favorites")
		if favorites and favorites.value then
			mod.filters[#mod.filters+1] = "favs"
		end
	end
end

mod.clear_filter = function(button)
	local textbox = button.window:get_widget("txt_search")
	if textbox then
		textbox.text = ""
		textbox:text_changed()
	end
	button.visible = false
end

mod.toggle_favorites = function(checkbox)
	mod:toggle_favorites_filter()
end

mod.reload_window = function(self)
	self:destroy_window()
	self:create_window()
end

mod.create_filter_window = function(func, ...)
	-- mod.any_screen_open = true
	-- view_tab_changed = true
	func(...)
	mod:reload_window()
end

mod.create_window = function(self)
	local screen_w = 1920
	local screen_h = 1080
	local window_position = {screen_w*0.35, screen_h*0.035}
	local window_size = {screen_w*0.3, screen_h*0.06}
	-- ##### Window ################################################################################
	self.filter_window = gui.create_window("inventory_filtering_window", window_position, window_size, nil, mod.focus_window, true)
	--self.filter_window:set("transparent", true)
	
	local size = {24, 24}
	local border = 5
	-- ##### Text ################################################################################
	local text = ""
	if mod.filters then
		for _, s in pairs(mod.filters) do
			if s ~= "favs" then	text = text..s.." " end
		end
	end

	local search_position = {border, border}
	local search_size = {window_size[1] - 40, size[2]}
	-- ##### Textbox ################################################################################
	local textbox = self.filter_window:create_textbox("txt_search", search_position, search_size, text, "Search ...", function(self)
		mod.execute_filter(self)
	end)
	local size_a = gui.adjust_to_fit_scale({window_size[1] - 40, 0})
	local size_b = gui.adjust_to_fit_scale({window_size[1] - 10, 0})
	textbox:set("after_update", function(self)
		if not self.text or self.text == "" then
			self.size[1] = size_b[1]
		else
			self.size[1] = size_a[1]
		end
	end)

	local clear_position = {window_size[1] - 30, border}
	-- ##### Clear search button ################################################################################
	local clear_button = self.filter_window:create_button("btn_clear_search", clear_position, size, "X", mod.clear_filter)
	clear_button:set("visible", text and #text > 0)
	clear_button:set("tooltip", "Clear search terms")

	local favorites = mod.filters and table.has_item(mod.filters, "favs")
	-- ##### Show favorites checkbox ################################################################################
	self.filter_window:create_checkbox("chk_favorites", {border, 35}, {size[1], size[2]}, "Show Favorites", favorites, mod.toggle_favorites)
	
	--self.filter_window.visible = true
	self.filter_window:init()
end

mod.destroy_window = function(self)
	if self.filter_window ~= nil then
		self.filter_window:destroy()
	end
end

mod.is_favorites_filter_active = function(self)
	return table.has_item(self.filters, "favs")
end

mod.save_favs = function(self)
	mod:set("favs", self.favs)
end

mod.load_favs = function(self)
	self.favs = table.clone(mod:get("favs") or {})
end

mod.refresh_ui = function(self, menu)
	if self.filters_last_update ~= self:filters_to_string() or self.force_refresh then
		self.force_refresh = false
		self.filters_last_update = self:filters_to_string()
		menu:refresh()
	end
end

mod.filters_to_string = function(self)
	local current_filter = "Current filter: "
	for i,v in ipairs(self.filters) do
		if i ~= 1 then
			current_filter = current_filter..", "
		end
		current_filter = current_filter..v
	end
	return current_filter
end

mod.get_filter = function(self)
	if not self.filters or #self.filters == 0 then
		return nil
	end

	local filter = ""
	for i,v in ipairs(self.filters) do
		if i > 1 then
			filter = filter.." and "
		end
		if v == "locked" then
			filter = filter.."true are_traits_locked =="
		elseif v == "favs" then
			filter = filter.."true is_fav =="
		else
			filter = filter..string.gsub(v, " ", "_").." trait_names_and_item_name find"
		end
	end
	return filter
end

mod.is_favorite = function(self, backend_id)
	return table.has_item(self.favs, backend_id)
end

mod.remove_from_favorites = function(self, backend_id)
	if table.has_item(self.favs, backend_id) then
		local new_my_favs = {}
		for i,v in ipairs(self.favs) do
			if v ~= backend_id then
				new_my_favs[#new_my_favs + 1] = v
			end
		end
		self.favs = new_my_favs
	end
end

mod.toggle_favorite = function(self, backend_id)
	if table.has_item(self.favs, backend_id) then
		self:remove_from_favorites(backend_id)
		self:save_favs()
		return
	end
	self.favs[#self.favs + 1] = backend_id
	self:save_favs()
end

mod.toggle_favorites_filter = function(self)
	if not self:is_favorites_filter_active() then
		self.filters[#self.filters+1] = "favs"
		return
	end

	local new_filter = {}
	for i,v in ipairs(self.filters) do
		if v ~= "favs" then
			new_filter[#new_filter+1] = v
		end
	end
	self.filters = new_filter
end


favorite_keymaps = {
	win32 = {
		fav = {"keyboard", mod.hotkey, "pressed"},
	}
}
favorite_keymaps.xb1 = favorite_keymaps.win32

mod:hook("InventoryItemsUI.update", function(func, self, ...)
	mod:refresh_ui(self)
	return func(self, ...)
end)

mod:hook("AltarItemsUI.update", function(func, self, ...)
	mod:refresh_ui(self)
	return func(self, ...)
end)

mod:hook("ForgeItemsUI.update", function(func, self, ...)
	mod:refresh_ui(self)
	return func(self, ...)
end)

mod:hook("BackendUtils.get_inventory_items", function(func, profile, slot, rarity)
	local item_id_list = ScriptBackendItem.get_items(profile, slot, rarity)
	local items = {}
	local unfiltered_items = {}

	local to_filter = {}

	for key, backend_id in pairs(item_id_list) do
		local item = BackendUtils.get_item_from_masterlist(backend_id)
		unfiltered_items[#unfiltered_items + 1] = item
		to_filter[backend_id] = item
	end

	if not mod:get_filter() then
		return unfiltered_items
	end

	local filtered_items = ScriptBackendCommon.filter_items(to_filter, nil)
	for _,v in ipairs(filtered_items) do
		items[#items + 1] = v
	end

	return items
end)

mod:hook("ScriptBackendCommon.filter_items", function(func, items, filter_infix)

	local input_filter_present = not not filter_infix

	if not input_filter_present and mod:get_filter() then
		filter_infix = mod:get_filter()
	end

	local filter_postfix = ScriptBackendCommon.filter_postfix_cache[filter_infix]

	if not filter_postfix then
		filter_postfix = ScriptBackendCommon.infix_to_postfix_item_filter(filter_infix)
		ScriptBackendCommon.filter_postfix_cache[filter_infix] = filter_postfix
	end

	local item_master_list = ItemMasterList
	local stack = {}
	local passed = {}

	for backend_id, item in pairs(items) do
		local key = item.key
		local item_data = item_master_list[key]

		table.clear(stack)

		for i = 1, #filter_postfix, 1 do
			local token = filter_postfix[i]

			if mod.filter_operators[token] then
				local num_params = mod.filter_operators[token][2]
				local op_func = mod.filter_operators[token][3]
				local op1 = table.remove(stack)

				if num_params == 1 then
					stack[#stack + 1] = op_func(op1)
				else
					local op2 = table.remove(stack)
					stack[#stack + 1] = op_func(op1, op2)
				end
			else
				local macro_func = mod.filter_macros[token]

				if macro_func then
					stack[#stack + 1] = macro_func(item_data, backend_id)
				else
					stack[#stack + 1] = token
				end
			end
		end

		if stack[1] == true then
			local clone_item_data = table.clone(item_data)
			clone_item_data.backend_id = backend_id
			passed[#passed + 1] = clone_item_data
		end
	end

	if input_filter_present and mod:get_filter() then
		local repass_these_items = {}
		for _, item in ipairs(passed) do
			repass_these_items[item.backend_id] = item
		end
		return ScriptBackendCommon.filter_items(repass_these_items)
	end

	return passed
end)

mod:hook("InventoryItemsList.draw", function(func, self, ...)
	for _,v in ipairs(self.item_widget_elements) do
		if not v.style.text_favorite then
			v.style.text_favorite = {
				font_size = 30,
				word_wrap = false,
				pixel_perfect = true,
				horizontal_alignment = "left",
				vertical_alignment = "center",
				dynamic_font = true,
				font_type = "hell_shark",
				text_color = Colors.get_color_table_with_alpha("dark_red", 255),
				size = {
					30,
					38
				},
				offset = {
					mod.element_settings.width - 225,
					12,
					6
				}
			}
		end
	end

	for _,v in ipairs(self.empty_widget_elements) do
		if not v.style.text_favorite then
			v.style.text_favorite = {
				font_size = 30,
				word_wrap = false,
				pixel_perfect = true,
				horizontal_alignment = "left",
				vertical_alignment = "center",
				dynamic_font = true,
				font_type = "hell_shark",
				text_color = Colors.get_color_table_with_alpha("dark_red", 255),
				size = {
					30,
					38
				},
				offset = {
					mod.element_settings.width - 225,
					12,
					6
				}
			}
		end
	end

	local text_favorite_pass_exists = false
	for _,pass in ipairs(self.widget_definitions.inventory_list_widget.element.passes[1].passes) do
		if pass.text_id == "text_favorite" then
			text_favorite_pass_exists = true
		end
	end
	if not text_favorite_pass_exists then
		local passes = self.widget_definitions.inventory_list_widget.element.passes[1].passes
		passes[#passes + 1] = {
						text_id = "text_favorite",
						pass_type = "text",
						style_id = "text_favorite",
						content_check_function = function(ui_content)
							if not ui_content.item then
								return false
							end
							return table.has_item(mod.favs, ui_content.item.backend_id)
						end,
					}
		
		self.create_ui_elements(self)
		self.populate_widget_list(self)
	end

	return func(self, ...)
end)

mod:hook("InventoryItemsList.update", function(func, self, ...)

	func(self, ...)

	if not Managers.input:get_input_service("favorite_input_service") then
		Managers.input:create_input_service("favorite_input_service", "favorite_keymaps")
		Managers.input:map_device_to_service("favorite_input_service", "keyboard")
		Managers.input:map_device_to_service("favorite_input_service", "mouse")
		Managers.input:map_device_to_service("favorite_input_service", "gamepad")
	end

	if mod.view_tab_changed then
		mod.view_tab_changed = false
		self.create_ui_elements(self)
		self.populate_widget_list(self)
		mod.force_refresh = true
		return
	end

	if mod.force_refresh then
		return
	end

	Managers.input:device_unblock_service("keyboard", 1, "favorite_input_service")
	local input_service = Managers.input:get_input_service("favorite_input_service")
	
	local item_list_widget = self.item_list_widget
	if item_list_widget.content.is_hover then
		local list_content = item_list_widget.content.list_content
		for i = 1, #list_content, 1 do
			local button_content = list_content[i]
			local button_hotspot = button_content.button_hotspot
			if button_hotspot.is_hover then
				if button_content then
					if button_content.item then
						local item = button_content.item
						if input_service:get("fav") then
							mod:toggle_favorite(item.backend_id)
							self.refresh_items_status(self)
						end
						local text = "Toggle Favorites\n"..
							"Press '"..mod.hotkey.."' to toggle "..item.localized_name.." as favorites.\n"..
							"Favorites will not show up on the salvage screen."
						basic_gui.tooltip(text)
					end
				end
			end
		end
	end
	
	return
end)

mod:hook("InventoryItemsList.populate_widget_list", function(func, self, list_start_index, sort_list)
	local items = self.stored_items

	if items then
		local item_list_widget = self.item_list_widget
		list_start_index = list_start_index or item_list_widget.style.list_style.list_start_index or 1
		local num_items_in_list = #items

		if num_items_in_list < list_start_index then
			return 
		end

		self._sync_item_list_equipped_status(self, items)

		if sort_list then
			if self.sort_by_equipment then
				table.sort(items, mod.sort_by_loadout_rarity_name)
			else
				table.sort(items, mod.sort_by_rarity_name)
			end
		end

		local settings = self.settings
		local new_backend_ids = ItemHelper.get_new_backend_ids()
		local disable_equipped_items = self.disable_equipped_items
		local accepted_rarity_list = self.accepted_rarity_list
		local disabled_backend_ids = self.disabled_backend_ids
		local tag_equipped_items = self.tag_equipped_items
		local selected_rarity = self.selected_rarity
		local num_item_slots = settings.num_list_items
		local num_draws = num_item_slots
		local list_content = {}
		local list_style = {
			vertical_alignment = "top",
			scenegraph_id = "item_list",
			size = settings.list_size,
			list_member_offset = {
				0,
				-(mod.element_settings.height + mod.element_settings.height_spacing),
				0
			},
			item_styles = {},
			columns = settings.columns,
			column_offset = settings.columns and mod.element_settings.width + settings.column_offset
		}
		local item_active_list = (self.item_active_list and table.clear(self.item_active_list)) or {}
		local index = 1

		for i = list_start_index, (list_start_index + num_draws) - 1, 1 do
			local item = items[i]

			if item then
				local is_equipped = item.equipped
				local is_locked = false
				local is_active = true
				local is_new = false
				local item_rarity = item.rarity
				local item_color = self.get_rarity_color(self, item_rarity)
				local item_backend_id = item.backend_id

				if new_backend_ids and new_backend_ids[item_backend_id] then
					is_new = true
				end

				if (selected_rarity and item_rarity ~= selected_rarity) or (disable_equipped_items and is_equipped) then
					is_active = false
				end

				if is_active and self.disable_non_trait_items then
					local item_traits = item.traits

					if not item_traits or #item_traits < 1 then
						is_active = false
					end
				end

				if accepted_rarity_list and not accepted_rarity_list[item_rarity] then
					is_active = false
				end

				if disabled_backend_ids[item_backend_id] then
					is_active = is_active and false
				end

				local item_element = self.item_widget_elements[index]
				local inventory_items_list_definitions = package.loaded["scripts/ui/views/inventory_items_list_definitions"]
				
				--mod.set_item_element_info(item_element, true, item, item_color, is_equipped, is_new, is_active, is_locked, not disable_equipped_items, self.ui_renderer)
				inventory_items_list_definitions.set_item_element_info(item_element, true, item, item_color, is_equipped, is_new, is_active, is_locked, not disable_equipped_items, self.ui_renderer)

				local content = item_element.content

				content.text_favorite = "FAV" -- ADDITION

				local style = item_element.style
				list_content[index] = content
				list_style.item_styles[index] = style
				item_active_list[item_backend_id] = is_active
				index = index + 1
			end
		end

		self.item_active_list = item_active_list
		list_style.start_index = 1
		list_style.list_start_index = list_start_index
		list_style.num_draws = num_draws
		item_list_widget.style.list_style = list_style
		item_list_widget.content.list_content = list_content
		item_list_widget.element.pass_data[1].num_list_elements = nil
		local list_content_n = #list_content
		self.number_of_real_items = num_items_in_list

		if list_content_n < num_draws then
			local padding_n = num_draws - #list_content%num_draws

			if padding_n < num_draws then
				for i = 1, padding_n, 1 do
					local empty_element = self.empty_widget_elements[i]
					local index = #list_content + 1
					empty_element.content.text_favorite = "FAV" -- ADDITION
					list_content[index] = empty_element.content
					list_style.item_styles[index] = empty_element.style
				end

				self.used_empty_elements = padding_n
			end
		end

		local selected_absolute_list_index = self.selected_absolute_list_index

		if selected_absolute_list_index then
			self.on_inventory_item_selected(self, selected_absolute_list_index)
		end
	end

	return
end)

mod:hook("ForgeView._apply_item_filter", function(func, self, item_filter, update_list)
	local ui_pages = self.ui_pages
	local items_page = ui_pages.items
	self.item_filter = item_filter
	local current_profile_name = items_page.current_profile_name(items_page)

	if item_filter and current_profile_name and current_profile_name ~= "all" then
		local can_wield_name = "can_wield_" .. current_profile_name
		item_filter = item_filter .. " and " .. can_wield_name .. " == true"
	end

	if ui_pages.melt.active then
		item_filter = item_filter.." and is_fav == false"
	end

	items_page.set_item_filter(items_page, item_filter)

	if update_list then
		local play_sound = false

		items_page.refresh(items_page)
		items_page.on_inventory_item_selected(items_page, 1, play_sound)
	end

	return 
end)

mod:hook("ForgeView.on_forge_selection_bar_index_changed", function(func, ...)
	mod.view_tab_changed = true
	return func(...)
end)

mod:hook("AltarView.on_forge_selection_bar_index_changed", function(func, ...)
	mod.view_tab_changed = true
	return func(...)
end)

mod:hook("ForgeView.on_enter", function(func, ...)
	mod.any_screen_open = true
	mod.view_tab_changed = true
	mod:reload_window()

	return func(...)
end)

mod:hook("ForgeView.on_exit", function(func, ...)
	func(...)
	mod.any_screen_open = false
	mod:destroy_window()
end)

mod:hook("AltarView.on_enter", function(func, ...)
	mod.any_screen_open = true
	mod.view_tab_changed = true
	mod:reload_window()

	return func(...)
end)

mod:hook("AltarView.on_exit", function(func, ...)
	func(...)
	mod.any_screen_open = false
	mod:destroy_window()
end)

mod:hook("InventoryItemsUI.on_enter", function (func, ...)
	mod.any_screen_open = true
	mod.view_tab_changed = true

	return func(...)
end)

mod:hook("InventoryItemsUI.on_exit", function(func, ...)
	func(...)
	mod.any_screen_open = false
end)

mod:hook("InventoryView.on_enter", mod.create_filter_window)
mod:hook("InventoryView.unsuspend", mod.create_filter_window)

mod:hook("ForgeView.unsuspend", mod.create_filter_window)
mod:hook("AltarView.unsuspend", mod.create_filter_window)

mod:hook("InventoryView.on_exit", function(func, ...)
	func(...)
	mod:destroy_window()
end)

mod:load_favs()
