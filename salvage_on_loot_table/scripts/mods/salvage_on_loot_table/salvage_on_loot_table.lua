--[[
	Author: IAmLupo
--]]

local mod = get_mod("salvage_on_loot_table")

mod.ui_scenegraph = {
	root = {
		is_root = true,
		position = {
			0,
			0,
			UILayer.hud
		},
		size = {
			1920,
			1080
		}
	},
	overlay = {
		vertical_alignment = "center",
		parent = "root",
		horizontal_alignment = "center",
		size = {
			1920,
			1080
		},
		position = {
			0,
			0,
			10
		}
	},
	salvage_button = {
		vertical_alignment = "bottom",
		parent = "overlay",
		horizontal_alignment = "center",
		size = {
			338,
			120
		},
		position = {
			200,
			70,
			400
		}
	}
}

mod.popup = {
	popup_id = nil,
	reward_ui = nil
}

mod.permanent = {

}

-- ####################################################################################################################
-- ##### Functionality ################################################################################################
-- ####################################################################################################################
mod.create_renderer = function()
	mod.permanent = {
		ui_renderer = mod.permanent.ui_renderer or UIRenderer.create(
			Managers.world:world("top_ingame_view"),
			"material", "materials/ui/ui_1080p_ingame_common",
		--	"material", "materials/ui/ui_1080p_ingame_postgame",
			"material", "materials/ui/ui_1080p_popup",
			"material", "materials/ui/ui_1080p_level_images",
			"material", "materials/fonts/gw_fonts"
		),

		ui_scenegraph = mod.permanent.ui_scenegraph or UISceneGraph.init_scenegraph(mod.ui_scenegraph),


		widgets =  mod.permanent.salvage_button or {
			salvage_button = UIWidget.init(UIWidgets.create_dice_game_button("salvage_button"))
		}
	}
end

mod.draw_widgets = function(reward_ui, dt)
	mod:pcall(function()
		local ui_renderer = mod.permanent.ui_renderer
		local ui_scenegraph = mod.permanent.ui_scenegraph
		local input_service = Managers.input:get_service("reward_ui")

		UIRenderer.begin_pass(ui_renderer, ui_scenegraph, input_service, dt, "root")

		-- Roll button
		reward_ui.ui_scenegraph.roll_button.position[1] = -200
		reward_ui.roll_button_widget.content.text_field = mod:localize("roll_button_text")

		-- Salvage button
		local salvage_button = mod.permanent.widgets.salvage_button
		salvage_button.content.text_field = mod:localize("salvage_button_text")
		if salvage_button.content.button_hotspot.on_release then
			if mod:get("popup") then
				mod.popup.popup_id = Managers.popup:queue_popup(
					mod:localize("popup_text2"),
					mod:localize("popup_title"),
					"accept", "Yes",
					"decline", "No"
				)
				mod.popup.reward_ui = reward_ui
			else
				mod.salvage_accept(reward_ui)
			end
		end

		UIRenderer.draw_widget(ui_renderer, salvage_button)

		UIRenderer.end_pass(ui_renderer)
	end)
end

mod.salvage_accept = function(reward_ui)
	local backend_id = reward_ui.reward_results.backend_id
	local melted, item_key, number_of_tokens = ForgeLogic.melt_item(nil, backend_id)

	if melted then
		local item = ItemMasterList[item_key]
		local item_type = Localize(item.item_type)
		local message = "Melted " .. item_type .. " and gained " .. number_of_tokens .. " tokens."

		mod:echo(message)
	end

	reward_ui.is_complete = true
end

-- ####################################################################################################################
-- ##### Hook #########################################################################################################
-- ####################################################################################################################
mod:hook_safe(RewardUI, "update", function (self, dt)

	if self.transition_name == "present_reward" then
		if not self.is_complete then
			if not self.ui_dice_animations.animate_reward_info then
				if (self.reroll_needed or (self.draw_roll_button and self.reward_entry_done)) then
					mod.draw_widgets(self, dt)
				end
			end
		end
	end
end)

mod:hook_safe(MatchmakingManager, "update", function(self)


	if mod.popup.popup_id then
		local result = Managers.popup:query_result(mod.popup.popup_id)

		if result then
			Managers.popup:cancel_popup(mod.popup.popup_id)

			mod.popup.popup_id = nil

			if result == "accept" then
				mod.salvage_accept(mod.popup.reward_ui)
			end
		end
	end
end)

-- ####################################################################################################################
-- ##### Development ##################################################################################################
-- ####################################################################################################################
--[[
	This inclease the time to stay in the loot table screen.
	Normally the limit was:
		roll_dice = 20 seconds
		reward_display = 25 seconds
		intro_description = 25 seconds
		vote_time = 180 seconds

-- Hour to vote for level
VoteTemplates.vote_for_level.duration = 3600

-- Force the reward_ui to never continui by itself
mod:hook(RewardUI, "update_continue_timer", function (func, self, dt)
	func(self, dt)
	self.continue_timer = 1337
	return false
end)
]]--

--[[
	Callback
--]]

mod.on_game_state_changed = function(status, state)
	if status == "enter" and state == "StateIngame" then
		mod.create_renderer()
	end
end