--[[
	Author: Grundlid	
--]]

local mod = get_mod("crosshair_customization")

local enlarge_off = 1
local enlarge_slightly = 2
local enlarge_heavily = 3

mod.options_widgets = {
	-- Crosshair color
	{
		["setting_name"] = "crosshair_group",
		["widget_type"] = "group",
		["text"] = "Crosshair Color",
		["sub_widgets"] = {			
			{
				["setting_name"] = "color_main_red",
				["widget_type"] = "numeric",
				["text"] = "Red",
				["tooltip"] = "Crosshair Red Value\n" ..
							"Changes the red color value of your crosshair.",
				["range"] = {0, 255},
				["default_value"] = 255,
			},
			{
				["setting_name"] = "color_main_green",
				["widget_type"] = "numeric",
				["text"] = "Green",
				["tooltip"] = "Crosshair Green Value\n" ..
							"Changes the green color value of your crosshair.",
				["range"] = {0, 255},
				["default_value"] = 255,
			},
			{
				["setting_name"] = "color_main_blue",
				["widget_type"] = "numeric",
				["text"] = "Blue",
				["tooltip"] = "Crosshair Blue Value\n" ..
							"Changes the blue color value of your crosshair.",
				["range"] = {0, 255},
				["default_value"] = 255,
			},
		}
	},

	-- HS Indicator
	{
		["setting_name"] = "hs",
		["widget_type"] = "checkbox",
		["text"] = "Headshot Indicator",
		["tooltip"] = "Headshot Indicator\n" ..
					"Adds a marker to the crosshair on headshots.",
		["default_value"] = false,
		["sub_widgets"] = {			
			{
				["setting_name"] = "color_hs_red",
				["widget_type"] = "numeric",
				["text"] = "Red",
				["tooltip"] = "Headshot Marker Red Value\n" ..
							"Changes the red color value of your headshot marker.",
				["range"] = {0, 255},
				["default_value"] = 255,
			},
			{
				["setting_name"] = "color_hs_green",
				["widget_type"] = "numeric",
				["text"] = "Green",
				["tooltip"] = "Headshot Marker Green Value\n" ..
							"Changes the green color value of your headshot marker.",
				["range"] = {0, 255},
				["default_value"] = 255,
			},
			{
				["setting_name"] = "color_hs_blue",
				["widget_type"] = "numeric",
				["text"] = "Blue",
				["tooltip"] = "Headshot Marker Blue Value\n" ..
							"Changes the blue color value of headshot marker.",
				["range"] = {0, 255},
				["default_value"] = 255,
			},
		}
	},

	-- Enlarge
	{
		["setting_name"] = "enlarge",
		["widget_type"] = "dropdown",
		["text"] = "Crosshair Size",
		["tooltip"] = "Crosshair Size\n" ..
				"Increases the size of your crosshair.",
		["options"] = {
			{text = "Normal (Small)", value = enlarge_off},
			{text = "Medium", value = enlarge_slightly},
			{text = "Large", value = enlarge_heavily},
		},
		["default_value"] = "Normal"
	},

	-- Dot
	{
		["setting_name"] = "dot_only",
		["widget_type"] = "checkbox",
		["text"] = "Dot Only",
		["tooltip"] = "Dot Only\n" ..
					"Forces the crosshair to remain as only a dot, even with ranged weapons.",
		["default_value"] = false
	},
	{
		["setting_name"] = "no_melee_dot",
		["widget_type"] = "checkbox",
		["text"] = "No Melee Dot",
		["tooltip"] = "No Melee Dot\n" ..
					"Disables the dot when you have your melee equipped.",
		["default_value"] = false
	},
}

mod.headshot_animations = {}
mod.headshot_widgets = {}

local widget_definitions = {
	crosshair_hit_1 = {
		scenegraph_id = "crosshair_hit_2",
		element = UIElements.RotatedTexture,
		content = {
			texture_id = "crosshair_01_hit"
		},
		style = {
			rotating_texture = {
				angle = math.pi*2,
				pivot = {
					0,
					0
				},
				offset = {
					-8,
					1,
					0
				},
				color = {
					0,
					255,
					255,
					255
				}
			}
		}
	},
	crosshair_hit_2 = {
		scenegraph_id = "crosshair_hit_1",
		element = UIElements.RotatedTexture,
		content = {
			texture_id = "crosshair_01_hit"
		},
		style = {
			rotating_texture = {
				angle = math.pi*1.5,
				pivot = {
					0,
					0
				},
				offset = {
					8,
					1,
					0
				},
				color = {
					0,
					255,
					255,
					255
				}
			}
		}
	},
	crosshair_hit_3 = {
		scenegraph_id = "crosshair_hit_4",
		element = UIElements.RotatedTexture,
		content = {
			texture_id = "crosshair_01_hit"
		},
		style = {
			rotating_texture = {
				angle = math.pi*1,
				pivot = {
					0,
					0
				},
				offset = {
					8,
					-1,
					0
				},
				color = {
					0,
					255,
					255,
					255
				}
			}
		}
	},
	crosshair_hit_4 = {
		scenegraph_id = "crosshair_hit_3",
		element = UIElements.RotatedTexture,
		content = {
			texture_id = "crosshair_01_hit"
		},
		style = {
			rotating_texture = {
				angle = math.pi*0.5,
				pivot = {
					0,
					0
				},
				offset = {
					-8,
					-1,
					0
				},
				color = {
					0,
					255,
					255,
					255
				}
			}
		}
	},
}

--[[
	Functions
--]] 

local function populate_defaults(crosshair_ui)
	if not mod.default_sizes then
		mod.default_sizes = {
			crosshair_dot = table.clone(crosshair_ui.ui_scenegraph.crosshair_dot.size),
			crosshair_up = table.clone(crosshair_ui.ui_scenegraph.crosshair_up.size),
			crosshair_down = table.clone(crosshair_ui.ui_scenegraph.crosshair_down.size),
			crosshair_left = table.clone(crosshair_ui.ui_scenegraph.crosshair_left.size),
			crosshair_right = table.clone(crosshair_ui.ui_scenegraph.crosshair_right.size),
		}
	end
end

local function reset_defaults(crosshair_ui)
	
	if not mod.default_sizes then return end

	for k,v in pairs(mod.default_sizes) do
		for i,v in ipairs(mod.default_sizes[k]) do
		  crosshair_ui.ui_scenegraph[k].size[i] = v
		end
	end

	for i,v in ipairs(mod.default_sizes.crosshair_dot) do
		crosshair_ui.ui_scenegraph.crosshair_dot.size[i] = v
	end
end

local function change_crosshair_color(crosshair_ui)
    local main_color = {255, mod:get('color_main_red'), mod:get('color_main_green'), mod:get('color_main_blue')}
    
    crosshair_ui.crosshair_dot.style.color = table.clone(main_color)
    crosshair_ui.crosshair_up.style.color = table.clone(main_color)
	crosshair_ui.crosshair_down.style.color = table.clone(main_color)
	crosshair_ui.crosshair_left.style.color = table.clone(main_color)
	crosshair_ui.crosshair_right.style.color = table.clone(main_color)

	if not crosshair_ui.hit_marker_animations[1] then
		for i,v in ipairs(crosshair_ui.hit_markers) do
		  v.style.rotating_texture.color = table.clone(main_color)
		  v.style.rotating_texture.color[1] = 0
		end
	end

	if mod.headshot_widgets[1] and not mod.headshot_animations[1] then
        local hs_color = {255, mod:get('color_hs_red'), mod:get('color_hs_green'), mod:get('color_hs_blue')}
		for i = 1, 4 do
			mod.headshot_widgets[i].style.rotating_texture.color = table.clone(hs_color)
			mod.headshot_widgets[i].style.rotating_texture.color[1] = 0
		end
	end
end

local function change_crosshair_scale(crosshair_ui)
	local crosshair_dot_scale = 1
	local crosshair_lines_scale = 1

	if mod:get('enlarge') == enlarge_slightly then
		crosshair_dot_scale = 1.5
		crosshair_lines_scale = 1.2
	elseif mod:get('enlarge') == enlarge_heavily then
		crosshair_dot_scale = 2
		crosshair_lines_scale = 1.5
	end

	for k,v in pairs(mod.default_sizes) do
		for i,v in ipairs(mod.default_sizes[k]) do
		  crosshair_ui.ui_scenegraph[k].size[i] = v * crosshair_lines_scale
		end
	end

	for i,v in ipairs(mod.default_sizes.crosshair_dot) do
		crosshair_ui.ui_scenegraph.crosshair_dot.size[i] = v * crosshair_dot_scale
	end
end

--[[
	Hooks
--]] 
mod:hook("CrosshairUI.draw", function (func, self, dt)
	func(self, dt)

	local ui_renderer = self.ui_renderer
	local ui_scenegraph = self.ui_scenegraph
	local input_service = self.input_manager:get_service("ingame_menu")

	UIRenderer.begin_pass(ui_renderer, ui_scenegraph, input_service, dt)
	for i = 1, 4 do
		UIRenderer.draw_widget(ui_renderer, mod.headshot_widgets[i])
	end
	UIRenderer.end_pass(ui_renderer)
end)

mod:hook("CrosshairUI.update_hit_markers", function (func, self, dt)
	func(self, dt)

	if not mod.headshot_widgets[1] then
		for i=1,4 do
			mod.headshot_widgets[i] = UIWidget.init(widget_definitions["crosshair_hit_"..i])
		end
	end

	local hud_extension = ScriptUnit.extension(self.local_player.player_unit, "hud_system")
	if hud_extension.headshot_hit_enemy then
		hud_extension.headshot_hit_enemy = nil

		for i = 1, 4 do
			local hit_marker = mod.headshot_widgets[i]
			mod.headshot_animations[i] = UIAnimation.init(UIAnimation.function_by_time, hit_marker.style.rotating_texture.color, 1, 255, 0, UISettings.crosshair.hit_marker_fade, math.easeInCubic)
		end
	end

	if mod.headshot_animations[1] then
		for i = 1, 4 do
			UIAnimation.update(mod.headshot_animations[i], dt)
		end

		if UIAnimation.completed(mod.headshot_animations[1]) then
			for i = 1, 4 do
				mod.headshot_animations[i] = nil
			end
		end
	end
end)

mod:hook("CrosshairUI.draw_dot_style_crosshair", function(func, self, ...)
	populate_defaults(self)
	change_crosshair_scale(self)
	change_crosshair_color(self)
    
    if mod:get('no_melee_dot') then
        self.crosshair_dot.style.color[1] = 0;
	end

    return func(self, ...)
end)

mod:hook("CrosshairUI.draw_default_style_crosshair", function(func, self, ...)
	populate_defaults(self)
	change_crosshair_scale(self)
	change_crosshair_color(self)
    
    if mod:get('dot_only') then
        crosshair_ui.crosshair_up.style.color[1] = 0
        crosshair_ui.crosshair_down.style.color[1] = 0
        crosshair_ui.crosshair_left.style.color[1] = 0
        crosshair_ui.crosshair_right.style.color[1] = 0
	end

    return func(self, ...)
end)

mod:hook("DamageSystem.rpc_add_damage", function (func, self, sender, victim_unit_go_id, attacker_unit_go_id, attacker_is_level_unit, damage_amount, hit_zone_id, damage_type_id, damage_direction, damage_source_id, hit_ragdoll_actor_id)
	func(self, sender, victim_unit_go_id, attacker_unit_go_id, attacker_is_level_unit, damage_amount, hit_zone_id, damage_type_id, damage_direction, damage_source_id, hit_ragdoll_actor_id)

	if not mod:get('hs') then
		return
	end

	local victim_unit = self.unit_storage:unit(victim_unit_go_id)

	local attacker_unit = nil
	if attacker_is_level_unit then
		attacker_unit = LevelHelper:unit_by_index(self.world, attacker_unit_go_id)
	else
		attacker_unit = self.unit_storage:unit(attacker_unit_go_id)
	end

	if not Unit.alive(victim_unit) then
		return
	end

	if Unit.alive(attacker_unit) then
		if ScriptUnit.has_extension(attacker_unit, "hud_system") then
			local health_extension = ScriptUnit.extension(victim_unit, "health_system")
			local damage_source = NetworkLookup.damage_sources[damage_source_id]
			local should_indicate_hit = health_extension.is_alive(health_extension) and attacker_unit ~= victim_unit and damage_source ~= "wounded_degen"

			local hit_zone_name = NetworkLookup.hit_zones[hit_zone_id]

			if should_indicate_hit and (hit_zone_name == "head" or hit_zone_name == "neck") then
				local hud_extension = ScriptUnit.extension(attacker_unit, "hud_system")
				hud_extension.headshot_hit_enemy = true
			end
		end
	end
end)

mod:hook("GenericUnitDamageExtension.add_damage", function (func, self, attacker_unit, damage_amount, hit_zone_name, damage_type, damage_direction, damage_source_name, hit_ragdoll_actor, damaging_unit)
	func(self, attacker_unit, damage_amount, hit_zone_name, damage_type, damage_direction, damage_source_name, hit_ragdoll_actor, damaging_unit)

	if not mod:get('hs') then
		return
	end

	local victim_unit = self.unit
	if ScriptUnit.has_extension(attacker_unit, "hud_system") then
		local health_extension = ScriptUnit.extension(victim_unit, "health_system")
		local should_indicate_hit = health_extension.is_alive(health_extension) and attacker_unit ~= victim_unit and damage_source_name ~= "wounded_degen"

		if should_indicate_hit and (hit_zone_name == "head" or hit_zone_name == "neck") then
			local hud_extension = ScriptUnit.extension(attacker_unit, "hud_system")
			hud_extension.headshot_hit_enemy = true
		end
	end
end)

--[[
	Callback
--]] 

mod.suspended = function()
	mod.disable_all_hooks()
end

mod.unsuspended = function()
	mod:enable_all_hooks()
end

mod.unload = function()
	local ingame_ui = Managers.matchmaking and  Managers.matchmaking.ingame_ui
	local crosshair_ui = ingame_ui and ingame_ui.ingame_hud and ingame_ui.ingame_hud.crosshair
	if not crosshair_ui then return end
	reset_defaults(crosshair_ui)
end


--[[
	Execution
--]] 

mod:create_options(mod.options_widgets, true, "Crosshair Customization", "Customize color, size and shape of your crosshair and improve headshot indication.")

if mod:is_suspended() then
	mod.suspended()
end
