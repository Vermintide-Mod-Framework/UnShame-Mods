local mod = get_mod("unreal_tournament")

-- UT's zoom of the sniper weapons (SniperZoom, which the Lightning Gun and the Sniper Rifle both have as their second fire, and
-- PlayerController.AdjustView and ToggleZoom): pressing the button starts zooming in, holding it zooms further, letting go keeps the zoom,
-- and pressing it again zooms out. The game's own aim action zooms to fixed fields of view and slows the player down. UT's zoom is
-- continuous, and the player moves at the same speed, so this is done here. It works on the camera's field of view, after the game has
-- set it for the frame. The state is of the player on this machine.
--   zoom.register(template_name): the weapon zooms this way while it is in the player's hands.
--   zoom.zoomed, zoom.magnification(): whether the view is zoomed, and how many times larger it is.
-- While the view is zoomed, the game's crosshair is not drawn: each weapon draws its scope.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")

local CONFIG = {
	-- The field of view goes from the normal 90 degrees down by 88 degrees for each second the button is held, until the zoom level
	-- reaches 0.9: 10.8 degrees.
	normal_fov = 90, -- degrees, horizontal
	degrees_per_second = 88,
	max_level = 0.9,
	min_fov = 1,
}

local zoom = {
	-- The zoom level (PlayerController.ZoomLevel) and whether the button is held to zoom in (PlayerController.bZooming)
	level = 0,
	zooming = false,
	zoomed = false,
}

local templates = {}

function zoom.register(template_name)
	templates[template_name] = true
end

local function end_zoom()
	zoom.level = 0
	zoom.zooming = false
	zoom.zoomed = false
end

-- The horizontal field of view that UT's zoom has now, in degrees
local function zoom_fov()
	return math.clamp(CONFIG.normal_fov - zoom.level * CONFIG.degrees_per_second, CONFIG.min_fov, 170)
end

function zoom.magnification()
	if not zoom.zoomed then
		return 1
	end

	return math.tan(math.rad(CONFIG.normal_fov / 2)) / math.tan(math.rad(zoom_fov() / 2))
end

local function local_wielding_zoom_weapon()
	local player = Managers.player and Managers.player:local_player_safe()
	local unit = player and player.player_unit

	if not unit or not Unit.alive(unit) then
		return nil
	end

	return templates[utils.wielded_template_name(unit)] and unit or nil
end

-- The game's camera takes a multiplier of its field of view for effects (CameraManager.set_additional_fov_multiplier). The zoom is made
-- with it. The multiplier works on the angle, so it is worked out from the tangent that the zoom is made in.
local zoom_fov_applied = false

local function apply_zoom_fov()
	local camera_manager = Managers.state and Managers.state.camera

	if not camera_manager then
		return
	end

	if zoom.zoomed then
		-- The field of view the camera has without the multiplier: the first person camera's, times the player's setting
		local base = math.rad(65) * camera_manager._fov_multiplier
		local zoomed = 2 * math.atan(math.tan(base / 2) / zoom.magnification())

		camera_manager:set_additional_fov_multiplier(zoomed / base)

		zoom_fov_applied = true
	elseif zoom_fov_applied then
		camera_manager:set_additional_fov_multiplier(1)

		zoom_fov_applied = false
	end
end

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	local unit = local_wielding_zoom_weapon()

	if not unit or not HEALTH_ALIVE[unit] then
		if zoom.zoomed then
			end_zoom()
		end

		apply_zoom_fov()

		return
	end

	local input_extension = ScriptUnit.extension(unit, "input_system")

	if input_extension:get("action_two") then
		if zoom.zoomed then
			-- Pressing the button while zoomed zooms out
			end_zoom()
		else
			-- ToggleZoom: StartZoom
			zoom.level = 0
			zoom.zooming = true
			zoom.zoomed = true
		end
	end

	if zoom.zooming then
		if input_extension:get("action_two_hold") then
			zoom.level = math.min(zoom.level + dt, CONFIG.max_level)
		else
			-- StopZoom: the zoom stays where it is
			zoom.zooming = false
		end
	end

	apply_zoom_fov()
end

local function reset_zoom()
	end_zoom()
	apply_zoom_fov()
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = reset_zoom
mod.disabled_callbacks[#mod.disabled_callbacks + 1] = reset_zoom
mod.unload_callbacks[#mod.unload_callbacks + 1] = reset_zoom

mod:hook(CrosshairUI, "draw", function (func, self, ...)
	if zoom.zoomed then
		return
	end

	return func(self, ...)
end)

return zoom
