--[[
	Adds a button to the Shrine of Solace's Offer page to lock selected traits before rerolling.
	This way you are guaranteed to get an item with desired traits.
	Author: UnShame
]]--

local mod = get_mod("lock_traits")


local definitions = mod:dofile("scripts/mods/lock_traits/lock_traits_definitions")
local widget_definitions = definitions.new_widget_definitions

-- Reroll page object - most likely will be found when an item is added to the wheel
mod.reroll_page = nil 

-- Currently locked traits by key
mod.locked_traits = {}
-- Currently locked traits by id
mod.highlighted_traits = {false, false, false, false}
-- Last rolled item will be exluded from next roll
mod.last_item = nil
-- Amount of possible trait combinations
mod.reroll_info = nil

mod.widgets = {}
mod.visible_widgets = {}

mod.animation_name_fade_in = "vmf_lock_trait_fade_in"
mod.animation_name_fade_out = "vmf_lock_trait_fade_out"

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
		mod.reroll_page = page
		mod.setup_animations()
		mod.setup_widgets()
	end
end

-- Copies and modifies reroll page animations to prevent locked traits from being un-highlighted
function mod.setup_animations()
	
	local animation_definitions = mod.reroll_page.ui_animator.animation_definitions

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

function mod.setup_widgets()
	definitions.scenegraph_definition.page_root.position = mod.reroll_page.scenegraph_definition.page_root.position
	mod.ui_scenegraph = UISceneGraph.init_scenegraph(definitions.scenegraph_definition)
	mod.widgets = {
		lock_button = UIWidget.init(widget_definitions.lock_button),
		reroll_stats = UIWidget.init(widget_definitions.reroll_stats)
	}
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
	for _,trait in ipairs(traits) do
		if trait == trait1 then has_trait1 = true end
		if trait == trait2 then has_trait2 = true end
	end
	return has_trait1 and has_trait2
end

-- Returns true if the item is exotic or rare and there's at least two unlocked traits
function mod.can_lock_traits()
	return 
		mod.reroll_page.active_item_data and 
		mod.reroll_page.active_item_data.rarity and
		(mod.reroll_page.active_item_data.rarity == "exotic" or mod.reroll_page.active_item_data.rarity == "rare") and
		mod.reroll_page.active_item_data.traits and 
		#mod.reroll_page.active_item_data.traits - 1 > #mod.locked_traits
end

-- Locks currently selected trait
function mod.lock_trait()
	local trait_name = mod.reroll_page.selected_trait_name
	local trait_index = mod.reroll_page.selected_trait_index
	if trait_name and #mod.locked_traits < 2 and not table.contains(mod.locked_traits, trait_name) then
		mod.locked_traits[#mod.locked_traits + 1] = trait_name
	end
	if trait_index ~= nil then
		mod.highlight_trait(trait_index, 255)
	end
	mod.update_widgets()
	mod.reroll_page:_update_trait_cost_display()
end

-- Unlocks currently selected trait
function mod.unlock_trait()
	local trait_name = mod.reroll_page.selected_trait_name
	local trait_index = mod.reroll_page.selected_trait_index
	if trait_name and table.contains(mod.locked_traits, trait_name) then
		table.remove(mod.locked_traits, table.find(mod.locked_traits, trait_name))
	end
	if trait_index ~= nil then
		mod.highlight_trait(trait_index, 0)
	end
	mod.update_widgets()
	mod.reroll_page:_update_trait_cost_display()
end

-- Highlights or dehighlights a trait
function mod.highlight_trait(id, alpha)
	if not mod.reroll_page then return end

	local widgets = mod.reroll_page.widgets_by_name
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
function mod.highlight_locked_traits()
	for i=1,4 do
		if mod.highlighted_traits[i] then
			mod.highlight_trait(i, 255)
		end
	end
end

-- Shows the button if a trait can be locked\unlocked
-- Shows reroll info if it exists instead
function mod.update_widgets()
	mod.reset_widgets()

	local selected_trait = mod.reroll_page.selected_trait_name
	--mod:echo(selected_trait)

	if not selected_trait and not mod.reroll_info then 
		return 
	end

	if not mod.reroll_info then

		local trait_is_locked = mod.has_traits(mod.locked_traits, selected_trait)
		if not trait_is_locked and not mod.can_lock_traits() then
			mod.visible_widgets.lock_button = mod.widgets.lock_button
			mod.widgets.lock_button.content.button_hotspot.disabled = true
			local rarity = mod.reroll_page.active_item_data.rarity
			mod.widgets.lock_button.content.tooltip_text = mod:localize(rarity == "unique" and "button_lock_veteran_tooltip" or "button_lock_all_tooltip") or "NONE"
			return
		end
		
		mod.widgets.lock_button.content.text_field = mod:localize(trait_is_locked and "button_unlock_text" or "button_lock_text") or "NONE"
		mod.widgets.lock_button.content.tooltip_text = mod:localize(trait_is_locked and "button_unlock_tooltip" or "button_lock_tooltip") or "NONE"

		mod.lock_button_callback = trait_is_locked and mod.unlock_trait or mod.lock_trait

		mod.widgets.lock_button.content.button_hotspot.disabled = false
		mod.visible_widgets.lock_button = mod.widgets.lock_button

	else
		mod.visible_widgets.lock_button = nil
		mod.widgets.reroll_stats.content.text = mod.reroll_info or ""
		mod.visible_widgets.reroll_stats = mod.widgets.reroll_stats
	end
end

-- Destroys the window
function mod.reset_widgets()
	mod.visible_widgets.lock_button = nil
	mod.widgets.lock_button.content.text_field = mod:localize("button_lock_text") or "NONE"
	mod.visible_widgets.reroll_stats = nil
end

-- Resets locked traits
function mod.reset(should_reset_widgets, leave_info)
	--mod:echo("reset")
	if not mod.reroll_page then return end
	for i=1,4 do
		mod.highlight_trait(i, 0)
	end
	mod.locked_traits = {}
	mod.last_item = nil
	if not leave_info then
		mod.reroll_info = nil
	end
	if should_reset_widgets then 
		mod.reset_widgets()
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

mod:hook("AltarTraitRollUI.update", function (func, ...)
	func(...)
	if (
		mod.reroll_page and mod.reroll_page.active and 
		mod.widgets.lock_button.content.button_hotspot.on_release and 
		not	mod.widgets.lock_button.content.button_hotspot.disabled
	) then
		mod.lock_button_callback()
	end
end)

mod:hook("AltarTraitRollUI.draw", function (func, self, dt)
	func(self, dt)

	if mod.ui_scenegraph then
		local ui_top_renderer = self.ui_top_renderer
		local input_service = self.parent:page_input_service()

		UIRenderer.begin_pass(ui_top_renderer, mod.ui_scenegraph, input_service, dt, nil, self.render_settings)

		for _, widget in pairs(mod.visible_widgets) do
			UIRenderer.draw_widget(ui_top_renderer, widget)
		end

		UIRenderer.end_pass(ui_top_renderer)
	end
end)

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

	local re_rerolled = false
	if #all_of_item_type <= 1 then
		all_of_item_type = {}
		re_rerolled = true
		for key, data in pairs(ItemMasterList) do
			if data.item_type == item_type and data.rarity == rarity then
				all_of_item_type[#all_of_item_type + 1] = key
			end
		end
	end

	fassert(1 < #all_of_item_type, "Trying to reroll traits for item type %s and rarity %s, but there are only one such item", item_type, rarity)

	local old_item_key = item_data.key
	local new_item_key = nil

	mod.reroll_info = tostring(#all_of_item_type) .. " " .. (mod:localize("info_combinations_found") or "NONE")
	if re_rerolled then 
		mod.reroll_info = (mod:localize("info_no_combinations_found") or "NONE") .. " " .. mod.reroll_info .. "."	
		mod.reset(false, true)
	end

	mod.update_widgets()

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
	mod.update_widgets()
end)

-- Clear locked traits when a new item is selected
mod:hook("AltarTraitRollUI.add_item", function (func, self, ...)
	--mod:echo("add_item")
	if not mod.reroll_page then
		mod.setup_reroll_page()
	end
	mod.reset(false)
	return func(self, ...)
end)

-- Clear locked traits and destroy window when the wheel is emptied
mod:hook("AltarTraitRollUI.remove_item", function (func, self, ...)
	--mod:echo("remove_item")
	if not mod.reroll_page then
		mod.setup_reroll_page()
	end
	mod.reset(true)
	return func(self, ...)
end)

-- Clear locked traits and destroy window on exit
mod:hook("AltarView.exit", function (func, ...)
	func(...)
	mod.reset(true)
end)

mod:hook("AltarView.on_enter", function (func, ...)
	func(...)
	mod.reset(true)
end)

-- Rehighlighting locked traits
mod:hook("AltarTraitRollUI._clear_new_trait_slots", function (func, ...)
	func(...)
	mod.highlight_locked_traits()
end)
mod:hook("AltarTraitRollUI._set_glow_enabled_for_traits", function (func, ...)
	func(...)
	mod.highlight_locked_traits()
end)
mod:hook("AltarTraitRollUI._instant_fade_out_traits_options_glow", function (func, ...)
	func(...)
	mod.highlight_locked_traits()
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

mod.setup_reroll_page()

--[[mod:create_options(
	mod.options_widgets,
	true,
	"Shrine: Lock Traits",
	"Adds a button to the Shrine of Solace's Offer page to lock selected traits before rerolling.\n"..
	"This way you are guaranteed to get an item with desired traits."
)--]]
