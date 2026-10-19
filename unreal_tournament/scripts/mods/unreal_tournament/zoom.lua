local mod = get_mod("unreal_tournament")

-- UT's zoom of the sniper weapons (SniperZoom, which the Lightning Gun and the Sniper Rifle both have as their second fire, and
-- PlayerController.AdjustView and ToggleZoom): pressing the button starts zooming in, holding it zooms further, letting go keeps the zoom,
-- and pressing it again zooms out. The game's own aim action zooms to fixed fields of view and slows the player down. UT's zoom is
-- continuous, and the player moves at the same speed, so the zoom is an action of the weapon's own that does nothing but be held
-- (zoom.action), which this follows: the game starts it, ends it and keeps it from starting as it does the weapon's other actions (while
-- inspecting, say). It works on the camera's field of view, after the game has set it for the frame. The state is of the player on this
-- machine.
--   zoom.register(template_name): the weapon zooms this way while it is in the player's hands.
--   zoom.action(hand, allowed_chain_actions): the zoom's action, for the weapon's right button (action_two.default), on the hand of
--       its other actions. A shot should be able to chain into it (action_two at any time).
--   zoom.zoomed: whether the zoom is in. It stays in in a third person view (an inspection, the extras' /freecamera), where the view
--       itself is not zoomed: zoom.in_view() is whether the first person view is zoomed, and zoom.magnification() how many times
--       larger it is. zoom.toggled_at is the game time the zoom last went in or out, for a weapon that fades the view then.
--   zoom.sound(skin, api): the zoom's sounds, for the weapon's skin to call every frame with its skin api (weapon_skin.lua).
-- While the view is zoomed, each weapon draws its scope, and the game's crosshair stays on top of it.

local utils = mod.utils

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
mod.zoom = zoom

local templates = {}

function zoom.register(template_name)
	templates[template_name] = true
end

-- The game time, if there is a game
local function game_time()
	return Managers.time and Managers.time:has_timer("game") and Managers.time:time("game") or nil
end

local function end_zoom()
	-- (UT's EndZoom fades the view if it was zoomed: HUD.FadeZoom)
	if zoom.zoomed then
		zoom.toggled_at = game_time()
	end

	zoom.level = 0
	zoom.zooming = false
	zoom.zoomed = false
end

-- The zoom's action: a dummy action held with the button, which doesn't slow the player. Pressing the button starts it, and letting go
-- ends it (hold_input). It takes the press out of the input buffer as it starts, as the game's actions do: left there, the press started
-- the action again after a shot turned into it, and the zoom that had just ended began again.
function zoom.action(hand, allowed_chain_actions)
	return {
		kind = "dummy",
		weapon_action_hand = hand,
		hold_input = "action_two_hold",
		total_time = math.huge,
		allowed_chain_actions = allowed_chain_actions,
		enter_function = function (attacker_unit, input_extension)
			input_extension:clear_input_buffer()

			return input_extension:reset_release_input()
		end,
		ut_zoom = true,
	}
end

-- Pressing the button while not zoomed starts zooming in (UT's ToggleZoom calls StartZoom), and while zoomed zooms out
mod.dummy_start_callbacks.zoom = function (action, new_action)
	if not new_action.ut_zoom or not utils.is_local_player_unit(action.owner_unit) then
		return
	end

	if zoom.zoomed then
		end_zoom()
	else
		zoom.level = 0
		zoom.zooming = true
		zoom.zoomed = true
		zoom.toggled_at = game_time()
	end
end

-- Letting go of the button keeps the zoom where it is (UT's StopZoom), as does anything else that ends the action
mod.dummy_finish_callbacks.zoom = function (action)
	if action.current_action and action.current_action.ut_zoom and utils.is_local_player_unit(action.owner_unit) then
		zoom.zooming = false
	end
end

-- Inspecting the weapon ends the zoom
mod.inspect_callbacks.zoom = function (action, started)
	if started and utils.is_local_player_unit(action.owner_unit) then
		end_zoom()
	end
end

-- The horizontal field of view that UT's zoom has now, in degrees
local function zoom_fov()
	return math.clamp(CONFIG.normal_fov - zoom.level * CONFIG.degrees_per_second, CONFIG.min_fov, 170)
end

-- The player's unit while they wield a weapon that zooms
local function local_wielding_zoom_weapon()
	local player = Managers.player and Managers.player:local_player_safe()
	local unit = player and player.player_unit

	if not unit or not Unit.alive(unit) then
		return nil
	end

	return templates[utils.wielded_template_name(unit)] and unit or nil
end

function zoom.in_view()
	local unit = zoom.zoomed and local_wielding_zoom_weapon()
	local first_person_extension = unit and ScriptUnit.has_extension(unit, "first_person_system")

	return first_person_extension and first_person_extension:first_person_mode_active() or false
end

function zoom.magnification()
	if not zoom.in_view() then
		return 1
	end

	return math.tan(math.rad(CONFIG.normal_fov / 2)) / math.tan(math.rad(zoom_fov() / 2))
end

-- UT plays the zoom-in sound again every frame that the view narrows (the RenderOverlays of SniperRifle and ClassicSniperRifle play it
-- on SLOT_Misc while the field of view goes down), and the zoom-out sound when the view widens again. A sound played again on its slot
-- starts over, so while the zoom moves in its start repeats every frame, and once it stops (the button let go, or the zoom at its
-- most) the last one plays to its end. Here the last one is stopped as the next one starts. UT also plays the zoom-out sound when the
-- button is let go while the zoom is in, which keeps the zoom (this is in its engine, not its scripts: it is from playing it).
function zoom.sound(skin, api)
	if zoom.zoomed ~= skin.was_zoomed then
		if skin.was_zoomed and not zoom.zoomed then
			api.play_sound("ut_lightning_zoom_out")
		end

		skin.was_zoomed = zoom.zoomed
	end

	if zoom.zooming ~= skin.was_zooming then
		if skin.was_zooming and zoom.zoomed and zoom.in_view() then
			api.play_sound("ut_lightning_zoom_out")
		end

		skin.was_zooming = zoom.zooming
	end

	if zoom.zooming and zoom.level < CONFIG.max_level and zoom.in_view() then
		api.stop_sound(skin.zoom_sound)

		skin.zoom_sound = api.play_sound("ut_lightning_zoom_in")
	end
end

-- The game's camera takes a multiplier of its field of view for effects (CameraManager.set_additional_fov_multiplier). The zoom is made
-- with it. The multiplier works on the angle, so it is worked out from the tangent that the zoom is made in.
local zoom_fov_applied = false

local function apply_zoom_fov()
	local camera_manager = Managers.state and Managers.state.camera

	if not camera_manager then
		return
	end

	if zoom.in_view() then
		-- The field of view the camera has without the multiplier: the first person camera's, times the player's setting (which the game
		-- turns into its multiplier against the same camera's, OptionsView)
		local base = math.rad(CameraSettings.first_person._node.vertical_fov) * camera_manager._fov_multiplier
		local zoomed = 2 * math.atan(math.tan(base / 2) / zoom.magnification())

		camera_manager:set_additional_fov_multiplier(zoomed / base)

		zoom_fov_applied = true
	elseif zoom_fov_applied then
		camera_manager:set_additional_fov_multiplier(1)

		zoom_fov_applied = false
	end
end

-- The game blends the multiplier over a time for the Handmaiden's dash (set_additional_fov_multiplier_with_lerp_time), but never lets go
-- of a blend that is done: _update_additional_fov_multiplier sets its own copy of the blend to nil, not the camera's. So after a dash the
-- camera sets the multiplier back to the blend's end every frame, and the zoom no longer works. A blend that is done is ended here, at
-- its end value.
mod:hook_safe(CameraManager, "_update_additional_fov_multiplier", function (self)
	local data = self._additional_fov_multiplier_data

	if data and data.current_lerp_time >= data.total_lerp_time then
		self._additional_fov_multiplier = data.fov_multiplier
		self._additional_fov_multiplier_data = nil
	end
end)

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	local unit = local_wielding_zoom_weapon()

	if not unit or not HEALTH_ALIVE[unit] then
		if zoom.zoomed then
			end_zoom()
		end

		apply_zoom_fov()

		return
	end

	-- (while the zoom's action is held)
	if zoom.zooming then
		zoom.level = math.min(zoom.level + dt, CONFIG.max_level)
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