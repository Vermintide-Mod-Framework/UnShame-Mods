--[[
	author: UnShame
--]]

local mod = get_mod("hud_toggle")

local setting_strings = {
	"ELEMENTS",
	"OBJECTIVES",
	"OUTLINES",
	"CROSSHAIR",
	"PING",
	"FEEDBACK",
	"WEAPON"
}

local options_widgets = {
	{
		["setting_name"] = "toggle_group",
		["widget_type"] = "group",
		["text"] = "Toggle Elements",
		["sub_widgets"] = {
			--[[ELEMENTS = ]]{
				["setting_name"] = setting_strings[1],
				["widget_type"] = "checkbox",
				["text"] = "HUD Elements",
				["tooltip"] = "HUD Elements\n" ..
					"Whether to display HUD elements like equipment, health bars, stamina and overcharge.",
				["default_value"] = true,
			},
			--[[OBJECTIVES = ]]{
				["setting_name"] = setting_strings[2],
				["widget_type"] = "checkbox",
				["text"] = "Objectives",
				["tooltip"] = "Objectives\n" ..
					"Whether to display objective banner, markers and button prompts.",
				["default_value"] = true,
			},
			--[[OUTLINES = ]]{
				["setting_name"] = setting_strings[3],
				["widget_type"] = "checkbox",
				["text"] = "Outlines",
				["tooltip"] = "Outlines\n" ..
					"Whether to display player, object and item outlines.\n" ..
					"Overrides Player Outlines Always On setting.",
				["default_value"] = true,
			},
			--[[CROSSHAIR = ]]{
				["setting_name"] = setting_strings[4],
				["widget_type"] = "checkbox",
				["text"] = "Crosshair",
				["tooltip"] = "Crosshair\n" ..
					"Whether to display crosshair.",
				["default_value"] = true,
			},
			--[[PING = ]]{
				["setting_name"] = setting_strings[5],
				["widget_type"] = "checkbox",
				["text"] = "Ping",
				["tooltip"] = "Ping\n" ..
					"Whether enemies, players and items can be pinged.",
				["default_value"] = true,
			},
			--[[FEEDBACK = ]]{
				["setting_name"] = setting_strings[6],
				["widget_type"] = "checkbox",
				["text"] = "Feedback",
				["tooltip"] = "Feedback\n" ..
					"Whether damage indicators, special kills and assists are shown.\n",
				["default_value"] = true,
			},
			--[[WEAPON = ]]{
				["setting_name"] = setting_strings[7],
				["widget_type"] = "checkbox",
				["text"] = "Weapon Model",
				["tooltip"] = "Weapon Model\n" ..
					"Whether to display weapon model and hands.",
				["default_value"] = true,
			},
		},
	},

	{
		["setting_name"] = "hud_toggle",
		["widget_type"] = "keybind",
		["text"] = "Toggle All",
		["default_value"] = {},
		["action"] = "toggle"
	},
	{
		["setting_name"] = "hud_more",
		["widget_type"] = "keybind",
		["text"] = "Show More",
		["tooltip"] = "Show more HUD elements",
		["default_value"] = {},
		["action"] = "more"
	},
	{
		["setting_name"] = "hud_less",
		["widget_type"] = "keybind",
		["text"] = "Show Less",
		["tooltip"] = "Show fewer HUD elements",
		["default_value"] = {},
		["action"] = "less"
	}
}


--[[
	Flags
]]--
mod.visible = true
mod.hud_set = false
mod.camera_set = false
mod.outlines_set = false
mod.should_suspend = false

mod.mode = 0

--[[
	Internal methods
]]--

function mod.set_setting_i(i, value)
	if setting_strings[i] then 
		mod:set(setting_strings[i], value)
	end
end

function mod.set_all_settings(value)
	mod.visible = value
	for i,v in ipairs(setting_strings) do
		mod:set(setting_strings[i], not not value, false)
	end
	mod.apply_settings()
end

function mod.apply_settings()

	--Hiding beta overlay
	if(Managers.beta_overlay) then
		if(mod:get("ELEMENTS")) then
			Managers.beta_overlay.widget.offset[1] = 0
		else
			Managers.beta_overlay.widget.offset[1] = 10000
		end
	end

	--Setting flags for update hooks
	mod.hud_set = false
	mod.camera_set = false
	mod.outlines_set = false
	mod.should_suspend = false
end

function mod.check_visibility()
	local visible = true
	for i,v in ipairs(setting_strings) do
		local value = mod:get(v)
		if not value then
			visible = false
			break
		end
	end
	mod.visible = visible
	return visible
end

--[[
	Extrenal methods
]]--

--Toggles hud
function mod.toggle()
	mod.set_all_settings(not mod.visible)
	mod.mode = mod.visible and 0 or #setting_strings
	mod.apply_settings()
end

--Hud +/-
function mod.more()
	local mode = mod.mode
	local decrease = mode == 6 and 2 or 1
	if mode <= 0 then decrease = 0 end	
	for i = mode - decrease + 1, #setting_strings do
		mod.set_setting_i(i, true)
	end
	mod.mode = mode - decrease
	mod.apply_settings()
end

function mod.less()
	local mode = mod.mode
	local increase = mode == 4 and 2 or 1
	if mode >= #setting_strings then increase = 0 end
	for i = 1, mode + increase do
		mod.set_setting_i(i, false)
	end
	mod.mode = mode + increase
	mod.apply_settings()
end


--[[
	Callback 
--]]

mod.on_setting_changed = function(setting_name)
	mod.apply_settings()
	return
end

mod.on_disabled = function()
	mod.should_suspend = true
end

mod.on_enabled = function()
	mod:enable_all_hooks()
	mod.apply_settings()
end


--[[
	Hooks
]]--

--Altering hud toggle function
mod:hook("IngameHud.set_visible", function(func, self, orig_visible)

	if mod:get("ELEMENTS") then
		return func(self, orig_visible)
	end
	
	local visible = false
	if self.player_inventory_ui then
		self.player_inventory_ui:set_visible(visible)
	end

	if self.unit_frames_handler then
		self.unit_frames_handler:set_visible(visible)
	end

	if self.game_timer_ui then
		self.game_timer_ui:set_visible(visible)
	end

	if self.endurance_badge_ui then
		self.endurance_badge_ui:set_visible(visible)
	end

	local difficulty_unlock_ui = self.difficulty_unlock_ui

	if difficulty_unlock_ui then
		difficulty_unlock_ui.set_visible(difficulty_unlock_ui, visible)
	end

	local difficulty_notification_ui = self.difficulty_notification_ui

	if difficulty_notification_ui then
		difficulty_notification_ui.set_visible(difficulty_notification_ui, visible)
	end

	if self.boon_ui then
		self.boon_ui:set_visible(visible)
	end

	if self.contract_log_ui then
		self.contract_log_ui:set_visible(visible)
	end

	if self.tutorial_ui then
		self.tutorial_ui:set_visible(visible)
	end

	local observer_ui = self.observer_ui

	if observer_ui then
		local observer_ui_visibility = self.is_own_player_dead(self) and not self.ingame_player_list_ui.active and orig_visible

		if observer_ui and observer_ui.is_visible(observer_ui) ~= observer_ui_visibility then
			observer_ui.set_visible(observer_ui, observer_ui_visibility)
		end
	end

end)

--Hiding things that might show up later
mod:hook("IngameUI.update", function(func, self, ...)
	func(self, ...)
	if not mod.hud_set then
		if self.ingame_hud and self.ingame_hud.set_visible then
			self.ingame_hud:set_visible(self, mod:get("ELEMENTS"))
			mod.hud_set = true
		end
	end
	if not mod:get("OBJECTIVES") and self.hud_visible then
		self.hud_visible = false
	end
end)

--Hiding contracts log
mod:hook("ContractLogUI.update", function (func, ...)
	if mod:get("ELEMENTS") then
		return func(...)
	end
end)

--Hiding stamina
mod:hook("FatigueUI.update", function (func, ...)
	if mod:get("ELEMENTS") then
		return func(...)
	end
end)

--Hiding overcharge bar
mod:hook("OverchargeBarUI.update", function (func, ...)
	if mod:get("ELEMENTS") then
		return func(...)
	end
end)

--Area indicators (?)
mod:hook("AreaIndicatorUI.update", function (func, ...)
	if mod:get("OBJECTIVES") then
		return func(...)
	end
end)

--Hiding interaction prompts
mod:hook("InteractionUI.update", function (func, ...)
	if mod:get("OBJECTIVES") then
		return func(...)
	end
end)

--Mission objectives
mod:hook("MissionObjectiveUI.update", function (func, ...)
	if mod:get("OBJECTIVES") then
		return func(...)
	end
end)

--Tutorial UI (?)
mod:hook("TutorialUI.update", function (func, ...)
	if mod:get("OBJECTIVES") then
		return func(...)
	end
end)

--Hiding crosshair
mod:hook("CrosshairUI.update", function(func, self, ...)
	if mod:get("CROSSHAIR") then
		return func(self, ...)
	end
end)


--Hiding hands and weapon
mod:hook("PlayerUnitFirstPerson.update", function (func, self, unit, input, dt, context, t)
	func(self, unit, input, dt, context, t)
	
	if not mod:get("WEAPON") and not mod.should_suspend then
		self.inventory_extension:show_first_person_inventory(false)
		self.inventory_extension:show_first_person_inventory_lights(false)
		Unit.set_unit_visibility(self.first_person_attachment_unit, false)

	elseif not mod.camera_set or mod.should_suspend then

		local player_unit = Managers.player:local_player().player_unit
		local first_person_system = player_unit and ScriptUnit.extension(player_unit, "first_person_system")
		if not first_person_system or not first_person_system.first_person_mode then return end

		local mod_third_person = get_mod("ThirdPerson")
		local is_third_person_mod = mod_third_person and not mod_third_person:is_suspended()
		local is_first_person = first_person_system.first_person_mode and not is_third_person_mod


		self.inventory_extension:show_first_person_inventory(is_first_person)
		self.inventory_extension:show_first_person_inventory_lights(is_first_person)
		Unit.set_unit_visibility(self.first_person_attachment_unit, is_first_person)

		mod.camera_set = true

		if mod.should_suspend then
			mod.should_suspend = false
			mod:disable_all_hooks()
		end
	end
end)

--Hiding outlines
mod:hook("OutlineSystem.update", function(func, self, ...)

	if mod:get("OUTLINES") then
		return func(self, ...)
	end

	if #self.units == 0 then
		return 
	end

	if script_data.disable_outlines then
		return 
	end

	local checks_per_frame = 4
	local current_index = self.current_index
	local units = self.units

	for i = 1, checks_per_frame, 1 do
		current_index = current_index + 1

		if not units[current_index] then
			current_index = 1
		end

		local unit = self.units[current_index]
		local extension = self.unit_extension_data[unit]

		if extension or false then
			local is_pinged = extension.pinged
			local method = "never"

			if self[method](self, unit, extension) then
				if not extension.outlined or extension.new_color or extension.reapply then
					local c = (is_pinged and OutlineSettings.colors.player_attention.channel) or extension.outline_color.channel
					local channel = Color(c[1], c[2], c[3], c[4])

					self.outline_unit(self, unit, extension.flag, channel, true, extension.apply_method, extension.reapply)

					extension.outlined = true
				end
			elseif extension.outlined or extension.new_color or extension.reapply then
				local c = extension.outline_color.channel
				local channel = Color(c[1], c[2], c[3], c[4])

				self.outline_unit(self, unit, extension.flag, channel, false, extension.apply_method, extension.reapply)

				extension.outlined = false
			end

			extension.new_color = false
			extension.reapply = false
		end
	end

	self.current_index = current_index
end)

--Disabling ping
mod:hook("ContextAwarePingExtension.update", function (func, ...)
	if mod:get("PING") then
		return func(...)
	end
end)

--Disabling positive reinforcement
mod:hook("PositiveReinforcementUI.update", function (func, ...)
	if mod:get("FEEDBACK") then
		return func(...)
	end
end)

--Hiding subtitles
mod:hook("SubtitleGui.update", function(func, self, ...)
	if mod:get("FEEDBACK") then
		return func(self, ...)
	end
end)

--Hide damage indicators
mod:hook("DamageIndicatorGui.update", function(func, self, ...)
	if mod:get("FEEDBACK") then
		return func(self, ...)
	end
end)


--[[
	Startup
--]]

-- Add option to mod settings menu (args: 1 = widget table, 2 = presence of checkbox in mod settings, 3 = descriptive name, 4 = description)
mod:create_options(options_widgets, true, "HUD Toggle", "Toggle elements of the HUD")

mod:init_state()
