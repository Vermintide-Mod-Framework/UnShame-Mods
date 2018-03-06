local definitions = local_require("scripts/ui/altar_view/altar_trait_roll_ui_definitions")
local scenegraph_definition = definitions.scenegraph_definition

scenegraph_definition.lock_button = {
	vertical_alignment = "bottom",
	parent = "text_frame",
	horizontal_alignment = "center",
	size = {
		100,
		35
	},
	position = {
		160,
		135,
		5
	}
}

definitions.new_widget_definitions = {
	lock_button = {
		element = {
			passes = {
				{
					pass_type = "hotspot",
					content_id = "button_hotspot",
					content_check_function = function (content)
						return not content.disabled
					end
				},
				{
					texture_id = "texture_id",
					style_id = "texture",
					pass_type = "texture",
					content_check_function = function (content)
						local button_hotspot = content.button_hotspot

						return not button_hotspot.disabled and not button_hotspot.is_hover and 0 < button_hotspot.is_clicked and not button_hotspot.is_selected
					end
				},
				{
					texture_id = "texture_hover_id",
					style_id = "texture",
					pass_type = "texture",
					content_check_function = function (content)
						local button_hotspot = content.button_hotspot

						return not button_hotspot.disabled and not button_hotspot.is_selected and button_hotspot.is_hover and 0 < button_hotspot.is_clicked
					end
				},
				{
					texture_id = "texture_click_id",
					style_id = "texture",
					pass_type = "texture",
					content_check_function = function (content)
						local button_hotspot = content.button_hotspot

						return not button_hotspot.disabled and button_hotspot.is_clicked == 0
					end
				},
				{
					texture_id = "texture_selected_id",
					style_id = "texture",
					pass_type = "texture",
					content_check_function = function (content)
						local button_hotspot = content.button_hotspot

						return not button_hotspot.disabled and button_hotspot.is_selected and 0 < button_hotspot.is_clicked
					end
				},
				{
					texture_id = "texture_disabled_id",
					style_id = "texture",
					pass_type = "texture",
					content_check_function = function (content)
						local button_hotspot = content.button_hotspot

						return button_hotspot.disabled
					end
				},
				{
					style_id = "text",
					pass_type = "text",
					text_id = "text_field",
					content_check_function = function (content)
						local button_hotspot = content.button_hotspot

						return not button_hotspot.disabled and not button_hotspot.is_hover and not button_hotspot.is_selected and 0 < button_hotspot.is_clicked
					end
				},
				{
					style_id = "text_hover",
					pass_type = "text",
					text_id = "text_field",
					content_check_function = function (content)
						local button_hotspot = content.button_hotspot

						return not button_hotspot.disabled and not button_hotspot.is_selected and button_hotspot.is_hover and 0 < button_hotspot.is_clicked
					end
				},
				{
					style_id = "text_selected",
					pass_type = "text",
					text_id = "text_field",
					content_check_function = function (content)
						local button_hotspot = content.button_hotspot

						return not button_hotspot.disabled and (button_hotspot.is_selected or button_hotspot.is_clicked == 0)
					end
				},
				{
					style_id = "text_disabled",
					pass_type = "text",
					text_id = "text_field",
					content_check_function = function (content)
						local button_hotspot = content.button_hotspot

						return button_hotspot.disabled
					end
				},
				{
					pass_type = "hotspot",
					content_id = "tooltip_hotspot",
					content_check_function = function (ui_content)
						return not ui_content.disabled
					end
				},
				{
					style_id = "tooltip_text",
					pass_type = "tooltip_text",
					text_id = "tooltip_text",
					content_check_function = function (ui_content)
						return ui_content.tooltip_hotspot.is_hover
					end
				}
			}
		},

		content = {
			texture_click_id = "small_button_02_selected",
			texture_id = "small_button_02_normal",
			texture_hover_id = "small_button_02_hover",
			texture_selected_id = "small_button_02_hover",
			texture_disabled_id = "small_button_02_disabled",
			text_field = "",
			button_hotspot = {},
			tooltip_hotspot = {},
			tooltip_text = ""
		},
		style = {
			texture = {
				color = {
					255,
					255,
					255,
					255
				}
			},
			text = {
				font_size = 20,
				localize = false,
				horizontal_alignment = "center",
				vertical_alignment = "center",
				font_type = "hell_shark",
				offset = {
					0,
					0,
					2
				},
				text_color = Colors.get_color_table_with_alpha("cheeseburger", 255),
				text_color_enabled = table.clone(Colors.color_definitions.cheeseburger),
				text_color_disabled = table.clone(Colors.color_definitions.gray)
			},
			text_hover = {
				vertical_alignment = "center",
				font_type = "hell_shark",
				localize = false,
				font_size = 20,
				horizontal_alignment = "center",
				offset = {
					0,
					0,
					2
				},
				text_color = Colors.get_color_table_with_alpha("white", 255)
			},
			text_selected = {
				vertical_alignment = "center",
				font_type = "hell_shark",
				localize = false,
				font_size = 20,
				horizontal_alignment = "center",
				offset = {
					0,
					-2,
					2
				},
				text_color = Colors.get_color_table_with_alpha("cheeseburger", 255)
			},
			text_disabled = {
				vertical_alignment = "center",
				font_type = "hell_shark",
				localize = false,
				font_size = 20,
				horizontal_alignment = "center",
				offset = {
					0,
					0,
					2
				},
				text_color = Colors.get_color_table_with_alpha("gray", 255)
			},
			tooltip_text = {
				font_size = 24,
				max_width = 500,
				localize = false,
				horizontal_alignment = "left",
				vertical_alignment = "top",
				font_type = "hell_shark",
				text_color = Colors.get_color_table_with_alpha("white", 255),
				line_colors = {},
				offset = {
					0,
					0,
					50
				}
			}
		},
		scenegraph_id = "lock_button"
	},
		
	reroll_stats = UIWidgets.create_simple_text("", "text_frame_description", 18, Colors.get_color_table_with_alpha("white", 255), {
		font_size = 18,
		localize = false,
		word_wrap = true,
		pixel_perfect = true,
		horizontal_alignment = "left",
		vertical_alignment = "top",
		dynamic_font = false,
		font_type = "hell_shark",
		text_color = Colors.get_color_table_with_alpha("white", 255),
		offset = {
			0,
			40,
			2
		}
	})
}

return definitions