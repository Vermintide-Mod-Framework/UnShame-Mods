local mod = get_mod("nethash")

mod:echo("loaded")

BUILD = "debug"

local function create_banner_text_config()
	return {
		vertical_alignment = "center",
		horizontal_alignment = "center",
		localize = true,
		font_size = 28,
		font_type = "hell_shark",
		text_color = Colors.get_color_table_with_alpha("cheeseburger", 255)
	}
end

local scenegraph_definition = dofile("scripts/ui/views/start_game_view/windows/definitions/start_game_window_lobby_browser_definitions").scenegraph_definition

scenegraph_definition.nethash_stepper = {
	vertical_alignment = "top",
	parent = "distance_stepper",
	horizontal_alignment = "center",
	position = {
		0,
		-85,
		0
	},
	size = {
		240,
		40
	}
}

scenegraph_definition.nethash_banner = {
	parent = "nethash_stepper",
	position = {
		-45,
		30,
		1
	},
	size = {
		340,
		56
	}
}

local widget_definitions = {
	nethash_stepper = UIWidgets.create_stepper("nethash_stepper", scenegraph_definition.nethash_stepper.size),
	nethash_banner = UIWidgets.create_title_and_tooltip("nethash_banner", scenegraph_definition.nethash_banner.size, "nethash", "nethash", create_banner_text_config()),
}


local widgets = {}
local ui_scenegraph
local nethash_table = {
	"Vanilla",
	"Modded"
}
local selected_nethash_index = 1

local network_options = {
	project_hash = "bulldozer",
	config_file_name = "global",
	lobby_port = GameSettingsDevelopment.network_port,
	max_members = MAX_NUMBER_OF_PLAYERS
}

local function on_nethash_stepper_input(self, index_change, specific_index)
	local stepper = widgets.nethash_stepper
	local current_index = selected_nethash_index or 1
	local new_index = self:_on_stepper_input(stepper, nethash_table, current_index, index_change, specific_index)
	local nethash_text = nethash_table[new_index]
	stepper.content.setting_text = nethash_text
	selected_nethash_index = new_index
	self.search_timer = 0

	local project_hash = network_options.project_hash
	if new_index == 2 then
		project_hash = Application.make_hash(project_hash, "ouch")
	end
	local hash = LobbyAux.create_network_hash(network_options.config_file_name, project_hash)
	self.lobby_finder._network_hash = hash
	Managers.matchmaking.lobby_finder._network_hash = hash
	Managers.matchmaking._network_hash = hash
end

mod:hook_safe(StartGameWindowLobbyBrowser, "draw", function(self, dt) 
	if not ui_scenegraph then
		ui_scenegraph = UISceneGraph.init_scenegraph(scenegraph_definition)
		ui_scenegraph.window.local_position = self.ui_scenegraph.window.local_position
		widgets.nethash_stepper = UIWidget.init(widget_definitions.nethash_stepper)
		widgets.nethash_banner = UIWidget.init(widget_definitions.nethash_banner)
		on_nethash_stepper_input(self, 0, 1)
	end

	local ui_renderer = self.ui_renderer
	local input_service = self.parent:window_input_service()

	UIRenderer.begin_pass(ui_renderer, ui_scenegraph, input_service, dt, nil, self.render_settings)

	UIRenderer.draw_widget(ui_renderer, widgets.nethash_stepper)
	UIRenderer.draw_widget(ui_renderer, widgets.nethash_banner)

	UIRenderer.end_pass(ui_renderer)
end)

mod:hook_origin(LobbyAux, "create_network_hash", function (config_file_name, project_hash)
	local network_hash = Network.config_hash(config_file_name)
	local settings = Application.settings()
	local trunk_revision = settings and settings.content_revision
	local ignore_engine_revision = Development.parameter("ignore_engine_revision_in_network_hash")
	local engine_revision = (ignore_engine_revision and 0) or Application.build_identifier()
	local combined_hash = nil
	local use_trunk_revision = GameSettingsDevelopment.network_revision_check_enabled or (trunk_revision ~= nil and trunk_revision ~= "")

	if use_trunk_revision then
		assert(trunk_revision, "No trunk_revision even though it needs to exist!")

		combined_hash = Application.make_hash(network_hash, trunk_revision, engine_revision, project_hash)

		printf("[LobbyAux] Making combined_hash: %s from network_hash=%s, trunk_revision=%s, engine_revision=%s, project_hash=%s", tostring(combined_hash), tostring(network_hash), tostring(trunk_revision), tostring(engine_revision), tostring(project_hash))
	else
		combined_hash = Application.make_hash(network_hash, engine_revision, project_hash)

		printf("[LobbyAux] Making combined_hash: %s from network_hash=%s, engine_revision=%s, project_hash=%s", tostring(combined_hash), tostring(network_hash), tostring(engine_revision), tostring(project_hash))
	end

	mod:echo(combined_hash)

	return combined_hash
	
end)


mod:hook_safe(StartGameWindowLobbyBrowser, "_handle_input", function(self, dt, t)
	self:_handle_stepper_input("distance_stepper", widgets.nethash_stepper, function(...)
		on_nethash_stepper_input(self, ...)
	end)
end)

mod:hook_safe(MatchmakingManager, "find_game", function() mod:echo("tesssst") end)

mod:hook_origin(LobbyFinder, "update", function (self, dt)
	if self._refreshing then
		local lobby_browser = LobbyInternal.lobby_browser()
		local is_refreshing = lobby_browser:is_refreshing()

		if not is_refreshing then
			local lobbies = {}
			local num_lobbies = lobby_browser:num_lobbies()
			local max_num_lobbies = self._max_num_lobbies

			print(num_lobbies)

			if max_num_lobbies then
				num_lobbies = math.min(max_num_lobbies, num_lobbies)
			end

			for i = 0, num_lobbies - 1, 1 do
				local lobby = LobbyInternal.get_lobby(lobby_browser, i)

				if LobbyAux.verify_lobby_data(lobby) then
					lobbies[#lobbies + 1] = lobby

					if lobby.network_hash == self._network_hash then
						lobby.valid = true
					end

				end
			end

			self._cached_lobbies = lobbies
			self._refreshing = false
		end
	end
end)

mod:hook(StartGameWindowLobbyBrowser, "_create_filter_requirements", function(func, self) 
	local reqs = func(self)

	local only_show_valid_lobbies = not self._base_widgets_by_name.invalid_checkbox.content.checked
	local lobby_finder = self.lobby_finder
	if not only_show_valid_lobbies then
		reqs.filters.eac_authorized = nil
		reqs.filters.network_hash = {
			value = lobby_finder:network_hash(),
			comparison = LobbyComparison.EQUAL
		}
	end

	return reqs
end)