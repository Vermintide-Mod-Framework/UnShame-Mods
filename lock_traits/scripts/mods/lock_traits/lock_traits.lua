--[[
	Adds a button to the Shrine of Solace's Offer page to lock selected traits before rerolling.
	This way you are guaranteed to get an item with desired traits.
	Author: UnShame
]]--

local mod = get_mod("lock_traits")

-- Reroll page object - most likely will be found when an item is added to the wheel
mod.trait_reroll_page = nil 

-- Currently locked traits by key
mod.locked_traits = {}
-- Currently locked traits by id
mod.highlighted_traits = {false, false, false, false}
-- Last rolled item will be exluded from next roll
mod.last_item = nil
-- Amount of possible trait combinations
mod.reroll_info = nil

mod.animation_name_fade_in = "vmf_lock_trait_fade_in"
mod.animation_name_fade_out = "vmf_lock_trait_fade_out"

-- Debug output
local function print_traits(traits)
	for i, trait in ipairs(traits) do
		mod:echo(trait)
	end
	mod:echo("=======")
end

-- Safely get reroll page object
function mod.get_reroll_page()
	local ingame_ui = Managers.matchmaking and Managers.matchmaking.ingame_ui
	local altar_view = ingame_ui and ingame_ui.views and ingame_ui.views.altar_view
	local page = altar_view and altar_view.ui_pages and altar_view.ui_pages.trait_reroll or nil
	--mod:echo(tostring(page))
	return page
end

-- Saves a local pointer to the reroll page
-- Sets up animations
function mod.setup_reroll_page()
	local page = mod.get_reroll_page()
	--mod:echo(page)
	if page then
		mod.trait_reroll_page = page
		mod.setup_animations()
	end
end

-- Copies and modifies reroll page animations to prevent locked traits from being un-highlighted
function mod.setup_animations()
	
	local animation_definitions = mod.trait_reroll_page.ui_animator.animation_definitions

	animation_definitions[mod.animation_name_fade_in] = table.create_copy(animation_definitions[mod.animation_name_fade_in], animation_definitions.fade_in_window_1_corner_glow)
	animation_definitions[mod.animation_name_fade_out] = table.create_copy(animation_definitions[mod.animation_name_fade_out], animation_definitions.fade_out_window_1_corner_glow)
	
	animation_definitions[mod.animation_name_fade_in][3].update = function (ui_scenegraph, scenegraph_definition, widgets, local_progress, params)
		local alpha = local_progress*255
		for i = 1, 4, 1 do
			local widget_name = "trait_button_" .. i
			local widget = widgets[widget_name]
			local widget_style = widget.style
			local color = widget_style.texture_glow_id.color

			if not mod.highlighted_traits[i] then
				if color[1] < alpha then
					color[1] = alpha
				end
			end
		end
	end

	animation_definitions[mod.animation_name_fade_out][3].update = function (ui_scenegraph, scenegraph_definition, widgets, local_progress, params)
		local alpha = (local_progress - 1)*255
		for i = 1, 4, 1 do
			local widget_name = "trait_button_" .. i
			local widget = widgets[widget_name]
			local widget_style = widget.style
			local color = widget_style.texture_glow_id.color

			if not mod.highlighted_traits[i] then
				if alpha < color[1] then
					color[1] = alpha
				end
			end
		end
	end
end

-- Returns true if table of traits has both trait1 and trait2
function mod.has_traits(traits, trait1, trait2)
	local has_trait1 = false
	local has_trait2 = false
	if not trait1 then
		has_trait1 = true
	end
	if not trait2 then
		has_trait2 = true
	end
	for i,trait in ipairs(traits) do
		if trait == trait1 then has_trait1 = true end
		if trait == trait2 then has_trait2 = true end
	end
	return has_trait1 and has_trait2
end

-- Returns true if the item is exotic or rare and there's at least two unlocked traits
function mod.can_lock_traits()
	return 
		mod.trait_reroll_page.active_item_data and 
		mod.trait_reroll_page.active_item_data.rarity and
		(mod.trait_reroll_page.active_item_data.rarity == "exotic" or mod.trait_reroll_page.active_item_data.rarity == "rare") and
		mod.trait_reroll_page.active_item_data.traits and 
		#mod.trait_reroll_page.active_item_data.traits - 1 > #mod.locked_traits
end

-- Locks currently selected trait
function mod.lock_trait()
	local trait_name = mod.trait_reroll_page.selected_trait_name
	local trait_index = mod.trait_reroll_page.selected_trait_index
	if trait_name and #mod.locked_traits < 2 and not table.has_item(mod.locked_traits, trait_name) then
		mod.locked_traits[#mod.locked_traits + 1] = trait_name
	end
	if trait_index ~= nil then
		mod.highlight_trait(trait_index, 255)
	end
	mod.create_window()
	mod.trait_reroll_page:_update_trait_cost_display()
end

-- Unlocks currently selected trait
function mod.unlock_trait()
	local trait_name = mod.trait_reroll_page.selected_trait_name
	local trait_index = mod.trait_reroll_page.selected_trait_index
	if trait_name and table.has_item(mod.locked_traits, trait_name) then
		table.remove(mod.locked_traits, table_index_of(mod.locked_traits, trait_name))
	end
	if trait_index ~= nil then
		mod.highlight_trait(trait_index, 0)
	end
	mod.create_window()
	mod.trait_reroll_page:_update_trait_cost_display()
end

-- Highlights or dehighlights a trait
function mod.highlight_trait(id, alpha)
	if not mod.trait_reroll_page then return end

	local widgets = mod.trait_reroll_page.widgets_by_name
	if not widgets then return end

	local widget_name = "trait_button_" .. id
	local widget = widgets[widget_name]
	if not widget then return end

	local widget_style = widget.style
	local color = widget_style.texture_glow_id.color
	color[1] = alpha

	mod.highlighted_traits[id] = alpha ~= 0
end

-- Re-highlights locked traits 
function mod.highlight_locked_trairs()
	for i=1,4 do
		if mod.highlighted_traits[i] then
			mod.highlight_trait(i, 255)
		end
	end
end

-- Lazy way of showing the button - we recreate the parent window and the button each time we wanna modify it
-- Shows the button if a trait can be locked\unlocked
-- Shows reroll info if it exists instead
function mod.create_window()
	mod.destroy_window()

	local selected_trait = mod.trait_reroll_page.selected_trait_name
	--mod:echo(selected_trait)

	if not selected_trait and not mod.reroll_info then return end

	local window_size = {0, 0}
	local window_position = {0, 0}

	--mod:echo(tostring(window_position[1]) .. " " .. tostring(window_position[2]))

	mod.window = get_mod("gui").create_window("lock_traits", window_position, window_size, nil, function() end, true)
	if not mod.reroll_info then

		local trait_is_locked = mod.has_traits(mod.locked_traits, selected_trait)
		if not trait_is_locked and not mod.can_lock_traits() then
			mod.destroy_window()
			return
		end
		local button_size = {100, 31}
		local button_position = {453, 447}
		local button_text = trait_is_locked and "Unlock" or "Lock"

		local button = mod.window:create_button("lock_traits_lock_unlock", button_position, button_size, button_text)
		button:set("on_click", trait_is_locked and mod.unlock_trait or mod.lock_trait)

		local textbox = mod.window:create_textbox("txt_search", {100, 100}, {100, 20}, "Test", "Search ...", function(self)	end)
	else
		local label_size = {100, 35}
		local label_position = {192, 443}
		local label_text = mod.reroll_info
		local label = mod.window:create_label("lock_traits_info", label_position, label_size, label_text)
	end
	mod.window:init()
end

-- Destroys the window
function mod.destroy_window()
	if mod.window then
		mod.window:destroy()
		mod.window = nil
	end
end

-- Resets locked traits
function mod.reset(should_destroy_window)
	--mod:echo("reset")
	for i=1,4 do
		mod.highlight_trait(i, 0)
	end
	mod.locked_traits = {}
	mod.last_item = nil
	mod.reroll_info = nil
	if should_destroy_window then 
		mod.destroy_window()
	end
end

-- Returns increased reroll cost based on locked traits
function mod.modify_reroll_cost(cost)
	local num_locked = #mod.locked_traits
	if num_locked == 0 then
		return cost
	elseif num_locked == 1 then
		return cost*2
	else
		return cost*6
	end
end

-- Adding trait filters when rerolling
mod:hook("ForgeLogic.reroll_traits", function (func, self, backend_id, item_is_equipped)

	local item_info = ScriptBackendItem.get_item_from_id(backend_id)
	local item_data = ItemMasterList[item_info.key]

	table.dump(item_data, "reroll traits item_data")

	local rarity = item_data.rarity
	local settings = AltarSettings.reroll_traits[rarity]

	BackendUtils.remove_tokens(Vault.withdraw_single(VaultAltarRerollTraitsCostKeyTable[rarity].cost, mod.modify_reroll_cost(settings.cost)), settings.token_type)

	local item_type = item_data.item_type
	local all_of_item_type = {}

	for key, data in pairs(ItemMasterList) do
		if data.item_type == item_type and data.rarity == rarity and mod.has_traits(data.traits, mod.locked_traits[1], mod.locked_traits[2]) then
			all_of_item_type[#all_of_item_type + 1] = key
		end
	end

	if #all_of_item_type <= 1 then
		mod:echo("No items found, rerolling normally")
		for key, data in pairs(ItemMasterList) do
			if data.item_type == item_type and data.rarity == rarity then
				all_of_item_type[#all_of_item_type + 1] = key
			end
		end
	end

	fassert(1 < #all_of_item_type, "Trying to reroll traits for item type %s and rarity %s, but there are only one such item", item_type, rarity)

	local old_item_key = item_data.key
	local new_item_key = nil

	mod.reroll_info = tostring(#all_of_item_type) .. " trait combinations found"
	mod.create_window()

	while not new_item_key do
		local new = all_of_item_type[Math.random(#all_of_item_type)]

		if new ~= old_item_key and (not mod.last_item or #all_of_item_type < 3 or new ~= mod.last_item) then
			new_item_key = new
		end
	end

	mod.last_item = new_item_key

	local hero, slot = ScriptBackendItem.equipped_by(backend_id)
	self._reroll_trait_data = {
		state = 1,
		new_item_key = new_item_key,
		old_backend_id = backend_id,
		hero = hero,
		slot = slot
	}

	Managers.backend:commit()

	return 
end)

-- Recreate window when selecting a trait
mod:hook("AltarTraitRollUI._set_selected_trait", function (func, self, selected_index)
	--mod:echo("_set_selected_trait " .. tostring(selected_index))
	func(self, selected_index)
	mod.create_window()
end)

-- Clear locked traits when a new item is selected
mod:hook("AltarTraitRollUI.add_item", function (func, self, ...)
	--mod:echo("add_item")
	if not mod.trait_reroll_page then
		mod.setup_reroll_page()
	end
	mod.reset(false)
	return func(self, ...)
end)

-- Clear locked traits and destroy window when the wheel is emptied
mod:hook("AltarTraitRollUI.remove_item", function (func, self, ...)
	--mod:echo("remove_item")
	if not mod.trait_reroll_page then
		mod.setup_reroll_page()
	end
	mod.reset(true)
	return func(self, ...)
end)

-- Clear locked traits and destroy window on exit
mod:hook("AltarView.exit", function (func, self, return_to_game)
	if self.menu_locked then
		if not self.popup_id then
			local text = Localize("dlc1_1_trait_roll_error_description")
			self.popup_id = Managers.popup:queue_popup(text, Localize("dlc1_1_trait_roll_error_topic"), "cancel_popup", Localize("popup_choice_ok"))
		end

		return 
	end

	mod.reset(true)

	local exit_transition = (return_to_game and "exit_menu") or "ingame_menu"

	self.ingame_ui:transition_with_fade(exit_transition)
	self.play_sound(self, "Play_hud_reroll_traits_window_minimize")

	self.exiting = true

	self.ui_pages.items:on_focus_lost()

	return 
end)

-- Rehighlighting locked traits
mod:hook("AltarTraitRollUI._clear_new_trait_slots", function (func, ...)
	func(...)
	mod.highlight_locked_trairs()
end)
mod:hook("AltarTraitRollUI._set_glow_enabled_for_traits", function (func, ...)
	func(...)
	mod.highlight_locked_trairs()
end)
mod:hook("AltarTraitRollUI._instant_fade_out_traits_options_glow", function (func, ...)
	func(...)
	mod.highlight_locked_trairs()
end)

-- Returns increased reroll cost based on locked traits
mod:hook("AltarTraitRollUI._get_upgrade_cost", function (func, self)
	local item_data = self.active_item_data

	if item_data then
		local rarity = item_data.rarity
		local reroll_traits = AltarSettings.reroll_traits
		local rarity_settings = reroll_traits[rarity]
		local token_type = rarity_settings.token_type
		local traits_cost = mod.modify_reroll_cost(rarity_settings.cost)
		local texture = rarity_settings.token_texture

		return token_type, traits_cost, texture
	end
end)

-- Play modified animations instead of standard ones
mod:hook("AltarTraitRollUI._on_preview_window_1_button_hovered", function (func, self)
	local params = {
		wwise_world = self.wwise_world
	}

	if self.window_2_corner_glow_anim_id then
		self.window_2_corner_glow_anim_id = self.ui_animator:start_animation("fade_out_window_2_corner_glow", self.widgets_by_name, self.scenegraph_definition, params)
	end

	self.window_1_corner_glow_anim_id = self.ui_animator:start_animation(mod.animation_name_fade_in, self.widgets_by_name, self.scenegraph_definition, params)
	self.trait_window_selection_index = 1
	local preview_window_1_button = self.widgets_by_name.preview_window_1_button
	preview_window_1_button.content.disable_input_icon = false

	return 
end)
mod:hook("AltarTraitRollUI._on_preview_window_2_button_hovered", function (func, self)
	local params = {
		wwise_world = self.wwise_world
	}

	if self.window_1_corner_glow_anim_id then
		self.window_1_corner_glow_anim_id = self.ui_animator:start_animation(mod.animation_name_fade_out, self.widgets_by_name, self.scenegraph_definition, params)
	end

	self.window_2_corner_glow_anim_id = self.ui_animator:start_animation("fade_in_window_2_corner_glow", self.widgets_by_name, self.scenegraph_definition, params)
	self.trait_window_selection_index = 2
	local preview_window_2_button = self.widgets_by_name.preview_window_2_button
	preview_window_2_button.content.disable_input_icon = false

	return 
end)
mod:hook("AltarTraitRollUI._on_preview_window_1_button_hover_exit", function (func, self)
	local params = {
		wwise_world = self.wwise_world
	}

	if self.window_1_corner_glow_anim_id then
		self.window_1_corner_glow_anim_id = self.ui_animator:start_animation(mod.animation_name_fade_out, self.widgets_by_name, self.scenegraph_definition, params)
	end

	if self.trait_window_selection_index == 1 then
		self.trait_window_selection_index = nil
	end

	local preview_window_1_button = self.widgets_by_name.preview_window_1_button
	preview_window_1_button.content.disable_input_icon = true

	return 
end)

--[[
	Callback
--]] 

mod.game_state_changed = function(status, state)
	mod.setup_reroll_page()
end

--[[mod:create_options(
	mod.options_widgets, 
	true, 
	"Shrine: Lock Traits", 
	"Adds a button to the Shrine of Solace's Offer page to lock selected traits before rerolling.\n".. 
	"This way you are guaranteed to get an item with desired traits."
)--]]
