local mod = get_mod("unreal_tournament")

-- A weapon's charge, shown on a copy of the game's overcharge bar where the ammo counter is, without the overcharge's icon and glow. The
-- game's own bar still shows the overcharge, which a wizard has from her staff while she holds another weapon.
--   mod.charge_bars[template_name] = function (player_unit): while the player holds a weapon of that template, the copy is drawn with
--       what this returns: { fraction = how full it is (0 to 1), marks = { first, second } (shares of the bar) or nil for none, color =
--       { red, green, blue } }.

local utils = mod.utils

local CONFIG = {
	-- The alpha of the bar's marks, as UIWidgets.create_overcharge_bar_widget makes them
	mark_alpha = 204,
}

mod.charge_bars = {}

-- Sets the copy's charge. Without marks, they are put at the end of the bar (the game sets the bar's alpha by them) and hidden.
local function show_charge(bar_ui, player)
	local unit = player and player.player_unit
	local charge_of = unit and utils.is_local_player_unit(unit) and mod.charge_bars[utils.wielded_template_name(unit)]
	local charge = charge_of and charge_of(unit)

	if not charge then
		return false
	end

	local style = bar_ui.charge_bar.style
	local marks = charge.marks
	local first_mark, second_mark = marks and marks[1] or 1, marks and marks[2] or 1

	-- (40 is the overcharge that makes the bar its full width: OverchargeBarUI.update_bar_size)
	bar_ui:update_bar_size(40, first_mark, second_mark)
	bar_ui:set_charge_bar_fraction(player, math.min(charge.fraction, 1), first_mark, second_mark, 0)

	for i = 1, 3 do
		style.bar_1.color[i + 1] = charge.color[i]
	end

	-- (the game sets the icon's and the glow's alpha by how far the bar is past its upper mark, every frame)
	style.icon.color[1] = 0

	if style.frame then
		style.frame.color[1] = 0
	end

	-- (the marks' alpha is set each frame: a build of the mod that hid them left them hidden on the same widget)
	for _, name in ipairs({ "min_threshold", "max_threshold" }) do
		if style[name] then
			style[name].color[1] = marks and CONFIG.mark_alpha or 0
		end
	end

	return true
end

local bar_definitions = local_require("scripts/ui/hud_ui/overcharge_bar_ui_definitions")
local keyboard_layout = local_require("scripts/ui/hud_ui/equipment_ui_definitions").scenegraph_definition
local gamepad_layout = local_require("scripts/ui/hud_ui/gamepad_equipment_ui_definitions").scenegraph_definition

-- The copy's nodes: its panel is placed as the equipment HUD places the ammo counter's panel (the same node, under the same root that the
-- HUD scale scales), and the bar is in the middle of it. Each equipment HUD places the counter its own way.
local function charge_bar_scenegraph(layout, root_name, panel_name)
	local panel = table.clone(layout[panel_name])

	panel.parent = root_name

	return {
		[root_name] = table.clone(layout[root_name]),
		panel = panel,
		charge_bar = {
			horizontal_alignment = "center",
			parent = "panel",
			vertical_alignment = "center",
			position = {
				0,
				0,
				1,
			},
			size = table.clone(bar_definitions.DEFAULT_BAR_SIZE),
		},
	}
end

-- Whether the HUD shows the gamepad's equipment HUD, as the two decide it (EquipmentUI._handle_gamepad)
local function uses_gamepad_layout()
	local gamepad_active = Managers.input:is_device_active("gamepad") or not IS_WINDOWS

	return (gamepad_active or UISettings.use_gamepad_hud_layout == "always") and UISettings.use_gamepad_hud_layout ~= "never"
end

-- The copies' renderer. The bar's fill is its material with how full it is set on the material (UIRenderer.draw_gradient_mask_texture),
-- and every bar a gui draws with that material in a frame gets the last one set. So the copies draw with a gui of their own, made as the
-- HUD's renderer is made (IngameUI.create_ui_renderer), whose material is not the game bar's, and the game's bar keeps its own fill.
local charge_bar_renderer, charge_bar_world

local function charge_bar_renderer_now()
	local world = Managers.world:has_world("level_world") and Managers.world:world("level_world")

	if not world then
		return
	end

	if charge_bar_world ~= world then
		charge_bar_renderer = IngameUI.create_ui_renderer(nil, world, false, false, Managers.mechanism:current_mechanism_name())
		charge_bar_world = world
	end

	return charge_bar_renderer
end

mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
	if charge_bar_renderer and Managers.world:has_world("level_world") and Managers.world:world("level_world") == charge_bar_world then
		UIRenderer.destroy(charge_bar_renderer, charge_bar_world)
	end

	charge_bar_renderer, charge_bar_world = nil, nil
end

-- The renderer's guis go with the level's world. The next level's world can be given the same handle, so it is forgotten when the level
-- ends, and the next one makes its own.
mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	charge_bar_renderer, charge_bar_world = nil, nil
end

-- Makes the copy of a player's overcharge bar, as the game makes the bar (OverchargeBarUI.create_ui_elements)
local function new_charge_bar(game_bar)
	local bar = setmetatable({}, getmetatable(game_bar))
	local definition = UIWidgets.create_overcharge_bar_widget("charge_bar", nil, nil, nil, nil, bar_definitions.DEFAULT_BAR_SIZE)

	bar.input_manager = game_bar.input_manager
	bar._side = game_bar._side
	bar.render_settings = {
		alpha_multiplier = 1,
		snap_pixel_positions = true,
	}
	bar.keyboard_scenegraph = UISceneGraph.init_scenegraph(charge_bar_scenegraph(keyboard_layout, "root_parent", "ammo_background_parent"))
	bar.gamepad_scenegraph = UISceneGraph.init_scenegraph(charge_bar_scenegraph(gamepad_layout, "root", "ammo_background"))
	bar.charge_bar = UIWidget.init(definition)

	return bar
end

-- Draws the copy as the game draws its bar (OverchargeBarUI.update), where the ammo counter is placed, as see-through as the game's bar is
local function draw_charge_bar(bar, game_bar, dt, player)
	bar.ui_scenegraph = uses_gamepad_layout() and bar.gamepad_scenegraph or bar.keyboard_scenegraph

	if not show_charge(bar, player) then
		return
	end

	local ui_renderer = charge_bar_renderer_now()

	if not ui_renderer then
		return
	end

	bar.ui_renderer = ui_renderer
	bar.render_settings.alpha_multiplier = game_bar.render_settings.alpha_multiplier

	UIRenderer.begin_pass(ui_renderer, bar.ui_scenegraph, bar.input_manager:get_service("ingame_menu"), dt, nil, bar.render_settings)
	UIRenderer.draw_widget(ui_renderer, bar.charge_bar)
	UIRenderer.end_pass(ui_renderer)
end

-- The copy of each of the game's bars, made by this load of the mod. The game's HUD lives on through a reload of the mod, so a copy kept
-- on the game's bar would be the one an older build made.
local charge_bar_copies = setmetatable({}, {
	__mode = "k",
})

-- The copy is drawn after the game's bar, every frame the HUD draws it, and goes with it
mod:hook(OverchargeBarUI, "update", function (func, self, dt, t, player, ...)
	func(self, dt, t, player, ...)

	charge_bar_copies[self] = charge_bar_copies[self] or new_charge_bar(self)

	draw_charge_bar(charge_bar_copies[self], self, dt, self._is_spectator and self._spectated_player or player)
end)
