local mod = get_mod("unreal_tournament")

-- UT movement:
--   * Dodging launches the player into the air, keeping their momentum, and can go forward.
--   * One extra jump in the air, only near the apex of a jump (after a jump or a dodge launch).
--   * Wall dodges: dodging towards a wall in the air launches the player off it.
--   * Stronger gravity.
--   * Crouching players don't walk off ledges.

local CONFIG = {
	-- Gravity, relative to the game's (11 m/s^2). Jumps get lower and shorter with it.
	gravity_multiplier = 1.3,
	-- Air control, how fast the player can change direction in the air, relative to the game's
	air_control_multiplier = 0.7,
	-- Crouching: no walking off ledges. The center of the player may be this far past the edge,
	-- so about this much more than half of them hangs off. Further and the physics gets closer
	-- to making them slide off by themselves.
	crouch_ledge_overhang = 0.1, -- m
	-- The ground is looked for down to this far below their feet (so stairs are fine, drops are
	-- ledges).
	crouch_ledge_probe_depth = 0.7, -- m
	-- Moving towards ground is always fine: it is looked for this far ahead, which has to be more
	-- than the radius of the player, who can be that far past an edge (crouching there must not
	-- trap them).
	crouch_ledge_safe_reach = 0.4, -- m
	-- Regular jump, relative to the game's (4.25 m/s). The dodge launch and the double jump have
	-- their own speeds, the jump is kept higher than the dodge launch.
	jump_speed_multiplier = 1.35,
	-- UT2004: after landing from a dodge the next dodge is locked for this long
	dodge_landing_delay = 0.35, -- seconds
	-- Dodge launch
	dodge_launch_vertical_speed = 4.25, -- m/s, the same as a regular jump
	dodge_launch_horizontal_speed = 7, -- m/s added to the current horizontal speed, the peak speed of the regular dodge
	dodge_launch_max_speed = 9, -- m/s, the horizontal speed after adding the two together is limited to this
	-- Wall dodge
	wall_dodge_reach = 1, -- m, how far from the center of the player a wall can be
	-- UT2004: the speed along the dodge is 1.5 times the ground speed, the player's momentum across
	-- it is kept, there is no limit. The upward speed is set, whatever it was.
	wall_dodge_speed = 6, -- m/s in the direction of the dodge (1.5 * the run speed of 4)
	wall_dodge_vertical_speed = 4.25, -- m/s, the upward speed it sets, the same as the dodge launch
	-- Double jump, like in UT2004: once per airtime, only near the apex of the jump, and it sets
	-- the upward speed. UT allows it while the vertical speed is within 100 uu/s of zero, which is
	-- 29% of its jump speed (340 uu/s), the same share of this game's jump gives the window.
	double_jump_speed = 5, -- m/s, the upward speed it gives, a regular jump is 4.25 * jump_speed_multiplier
	double_jump_apex_speed = 1.7, -- m/s, it is allowed while the vertical speed is within this of zero
}

-- The Multidodge option: no limits on dodging
local function is_multidodge()
	return mod:get("multidodge")
end

-- What happened in the air since the player last was on the ground, per unit:
--   double_jumped: the extra jump was used
--   dodged: a dodge (on the ground or on a wall) was done, landing then locks dodging for a while
--   keep_speed: a dodge launch is in progress, its horizontal speed is kept
local air_state = setmetatable({}, {
	__mode = "k",
})

local function reset_air_state(self, unit)
	air_state[unit or self.unit] = nil
end

local function get_air_state(unit)
	local state = air_state[unit]

	if not state then
		state = {}
		air_state[unit] = state
	end

	return state
end

-- Until when dodging is locked, per unit
local dodge_unlocked_t = setmetatable({}, {
	__mode = "k",
})

-- Landing: the next time in the air is a new one, and having landed from a dodge locks dodging
-- for a while
for _, state in ipairs({
	PlayerCharacterStateWalking,
	PlayerCharacterStateStanding,
}) do
	mod:hook_safe(state, "on_enter", function (self, unit, input, dt, context, t)
		local air_state_before = air_state[unit]

		if air_state_before and air_state_before.dodged then
			dodge_unlocked_t[unit] = t + CONFIG.dodge_landing_delay
		end

		reset_air_state(self, unit)
	end)
end

-- Climbing or hanging: the next time in the air is a new one
for _, state in ipairs({
	PlayerCharacterStateClimbingLadder,
	PlayerCharacterStateLedgeHanging,
}) do
	mod:hook_safe(state, "on_enter", function (self, unit)
		reset_air_state(self, unit)
	end)
end

-- Jumping: a jump from the ground starts a new time in the air (jumping out of falling doesn't
-- happen), and the jump is stronger. The state reads the speed of the jump from the player's
-- movement settings when it starts, so they are changed for the duration of that.
-- (One hook for both, the game has had trouble with more than one on the same function.)
mod:hook(PlayerCharacterStateJumping, "on_enter", function (func, self, unit, input, dt, context, t, previous_state, ...)
	if previous_state ~= "falling" then
		reset_air_state(self, unit)
	end

	local jump_settings = PlayerUnitMovementSettings.get_movement_settings_table(unit).jump
	local jump_speed = jump_settings.initial_vertical_speed

	jump_settings.initial_vertical_speed = jump_speed * CONFIG.jump_speed_multiplier

	func(self, unit, input, dt, context, t, previous_state, ...)

	jump_settings.initial_vertical_speed = jump_speed
end)

-- Forward dodge
-- The game never dodges forwards: forward input is rejected and a forward-sideways input
-- becomes a sideways dodge. Added here: a double tap on forward (like the sideways and backward
-- double taps, when the player has those turned on) and the dodge key with only forward pressed.
-- There is no animation for dodging forward, the dodge plays the backward one (the sound of the
-- dodge comes with the animation).
local FORWARD_TAP = "move_forward_pressed"

mod:hook(CharacterStateHelper, "check_to_start_dodge", function (func, unit, input_extension, status_extension, t)
	-- no dodging while crouching (the jump key then uncrouches and jumps), or right after
	-- landing from a dodge
	if status_extension:is_crouching() or dodge_unlocked_t[unit] and t < dodge_unlocked_t[unit] and not is_multidodge() then
		return false, Vector3(0, 0, 0)
	end

	local start_dodge, dodge_direction = func(unit, input_extension, status_extension, t)

	if start_dodge or status_extension:dodge_locked() or not status_extension:can_dodge(t) then
		return start_dodge, dodge_direction
	end

	local forward_dodge = false

	if input_extension.double_tap_dodge and input_extension:get(FORWARD_TAP) then
		if input_extension:was_double_tap(FORWARD_TAP, t, Application.user_setting("double_tap_dodge_threshold")) then
			forward_dodge = true
		end

		input_extension:clear_double_tap(FORWARD_TAP)

		if not forward_dodge then
			input_extension:start_double_tap(FORWARD_TAP, t)
		end
	end

	if not forward_dodge and input_extension:get("dodge") then
		local input = CharacterStateHelper.get_movement_input(input_extension)

		forward_dodge = input.y > 0 and math.abs(input.x) <= 0.707 * input.y
	end

	if not forward_dodge then
		return start_dodge, dodge_direction
	end

	dodge_direction = Vector3.forward()

	-- what the game does when it starts a dodge
	Managers.state.entity:system("play_go_tutorial_system"):register_dodge(dodge_direction)
	status_extension:add_fatigue_points("action_dodge")
	status_extension:set_dodge_locked(true)
	status_extension:add_dodge_cooldown()

	return true, dodge_direction
end)

-- Dodge launch
-- The dodge has set itself up by the time this runs. Leaving the ground ends it (the dodge state
-- hands over to falling when the player isn't on the ground), so the horizontal speed of the dodge
-- has to be given as well.
mod:hook_safe(PlayerCharacterStateDodging, "on_enter", function (self, unit, input, dt, context, t)
	local locomotion_extension = self.locomotion_extension
	local first_person_extension = self.first_person_extension
	local flat_rotation = Quaternion.look(Vector3.flat(Quaternion.forward(first_person_extension:current_rotation())), Vector3.up())
	local direction = Quaternion.rotate(flat_rotation, self.dodge_direction:unbox())

	-- the dodge is added to the momentum the player had
	local horizontal_velocity = Vector3.flat(locomotion_extension:current_velocity()) + direction * CONFIG.dodge_launch_horizontal_speed
	local horizontal_speed = Vector3.length(horizontal_velocity)

	if horizontal_speed > CONFIG.dodge_launch_max_speed then
		horizontal_velocity = horizontal_velocity * (CONFIG.dodge_launch_max_speed / horizontal_speed)
	end

	local velocity = horizontal_velocity + Vector3(0, 0, CONFIG.dodge_launch_vertical_speed)

	locomotion_extension:set_maximum_upwards_velocity(CONFIG.dodge_launch_vertical_speed)
	locomotion_extension:force_on_ground(false)
	locomotion_extension:set_forced_velocity(velocity)
	locomotion_extension:set_wanted_velocity(velocity)

	air_state[unit] = {
		dodged = true,
		keep_speed = true,
	}
end)

-- The game's air movement limits the horizontal speed to the run speed, which would take the
-- speed of the dodge launch away at once. It is allowed to keep its speed (steering still works).
-- The speed it is given is how much the player can steer, which is scaled for the air control.
mod:hook(CharacterStateHelper, "move_in_air", function (func, first_person_extension, input_extension, locomotion_extension, speed, unit, ...)
	local state = air_state[unit]
	local speed_before = state and state.keep_speed and Vector3.length(Vector3.flat(locomotion_extension:current_velocity()))

	func(first_person_extension, input_extension, locomotion_extension, speed * CONFIG.air_control_multiplier, unit, ...)

	if speed_before then
		local wanted_flat = Vector3.flat(locomotion_extension.velocity_wanted:unbox())
		local wanted_speed = Vector3.length(wanted_flat)

		if wanted_speed > 0.001 and wanted_speed < speed_before then
			locomotion_extension:set_wanted_velocity(wanted_flat * (speed_before / wanted_speed))
		end
	end
end)

-- Wall dodge
-- In the air, a dodge input with a wall behind it launches the player off it. The inputs are the
-- same as for dodging on the ground: a double tap (if the player has turned those on), the dodge
-- key with a direction held, and the jump key with a sideways or backward direction held (the
-- game's default way to dodge). Without a wall that jump key is the double jump as usual.
-- Like in UT2004 it is one dodge per airtime: a dodge launch from the ground counts as well.
local WALL_DODGE_TAPS = {
	move_left_pressed = {
		-1,
		0,
	},
	move_right_pressed = {
		1,
		0,
	},
	move_back_pressed = {
		0,
		-1,
	},
	move_forward_pressed = {
		0,
		1,
	},
}

-- Returns the local direction the player wants to dodge in as x and y, and if the jump key
-- was the input, or nothing
local function read_air_dodge_input(input_extension, t)
	if input_extension.double_tap_dodge then
		for key, direction in pairs(WALL_DODGE_TAPS) do
			if input_extension:get(key) then
				local was_double_tap = input_extension:was_double_tap(key, t, Application.user_setting("double_tap_dodge_threshold"))

				for other_key in pairs(WALL_DODGE_TAPS) do
					input_extension:clear_double_tap(other_key)
				end

				if was_double_tap then
					return direction[1], direction[2], false
				end

				input_extension:start_double_tap(key, t)

				break
			end
		end
	end

	local jump_pressed = input_extension:get("jump") or input_extension:get("jump_only")

	if input_extension:get("dodge") or jump_pressed then
		local input = CharacterStateHelper.get_movement_input(input_extension)
		local length = Vector3.length(input)

		-- forward with the jump key is a jump, like on the ground
		if length > input_extension.minimum_dodge_input and (input_extension:get("dodge") or input.y <= 0) then
			return input.x / length, input.y / length, not input_extension:get("dodge")
		end
	end
end

-- The animation of a dodge in a local direction, the way the dodge state picks it. The sound of
-- dodging comes with the animation.
local function play_dodge_animation(unit, first_person_extension, x, y)
	local event

	if math.abs(y) > math.abs(x) then
		event = "dodge_bwd"
	elseif x > 0 then
		event = "dodge_left"
	else
		event = "dodge_right"
	end

	CharacterStateHelper.play_animation_event_with_variable_float(unit, event, "dodge_time", 0.5)
	CharacterStateHelper.play_animation_event_first_person(first_person_extension, event)
end

-- A wall is found by sweeping a sphere sideways at a few heights (a ray at one height can miss a
-- low wall, or slip through a gap). The game's collision with the level's static geometry for
-- projectiles is what is swept against, the player's mover filter is tried as well.
local WALL_FILTERS = {
	"filter_player_mover",
	"filter_player_ray_projectile_static_only",
}
local WALL_SWEEP_HEIGHTS = {
	0.3,
	0.9,
	1.5,
}
local WALL_SWEEP_RADIUS = 0.25

-- Returns if there is a wall in the given direction
local function find_wall(physics_world, position, direction)
	local found_hit

	for i = 1, #WALL_FILTERS do
		for j = 1, #WALL_SWEEP_HEIGHTS do
			local from = position + Vector3(0, 0, WALL_SWEEP_HEIGHTS[j])
			local to = from + direction * CONFIG.wall_dodge_reach
			local result = PhysicsWorld.linear_sphere_sweep(physics_world, from, to, WALL_SWEEP_RADIUS, 5, "collision_filter", WALL_FILTERS[i])
			local num_hits = result and #result or 0
			local wall_hit

			for k = 1, num_hits do
				local hit = result[k]

				-- floors and ceilings aren't walls
				if hit.normal and math.abs(hit.normal.z) <= 0.7 then
					wall_hit = hit

					break
				end
			end

			if not found_hit and wall_hit then
				found_hit = wall_hit
			end
		end
	end

	return found_hit ~= nil
end

-- Returns true if it dodged
local function try_wall_dodge(self, unit, t)
	local state = get_air_state(unit)
	local input_x, input_y = read_air_dodge_input(self.input_extension, t)

	if not input_x then
		return false
	end

	-- UT2004 doesn't dodge while crouching or about to, and dodges once in the air (unless
	-- multidodge is on)
	if state.dodged and not is_multidodge() or self.status_extension:is_crouching() then
		return false
	end

	local locomotion_extension = self.locomotion_extension
	local first_person_extension = self.first_person_extension

	if locomotion_extension:is_on_ground() or self.csm.state_next then
		return false
	end

	-- Like in UT2004 the wall has to be behind the dodge: dodging left needs a wall on the right,
	-- the player dodges off it (dodging into a wall does nothing)
	local flat_rotation = Quaternion.look(Vector3.flat(Quaternion.forward(first_person_extension:current_rotation())), Vector3.up())
	local direction = Quaternion.rotate(flat_rotation, Vector3(input_x, input_y, 0))
	local position = POSITION_LOOKUP[unit]

	if not find_wall(self.physics_world, position, -direction) then
		return false
	end

	-- the dodge goes in the direction of the input, the momentum across it is kept (UT2004:
	-- Velocity = DodgeSpeed * Dir + (Velocity dot Cross) * Cross)
	local velocity = locomotion_extension:current_velocity()
	local flat_velocity = Vector3.flat(velocity)
	local across = flat_velocity - direction * Vector3.dot(flat_velocity, direction)
	local horizontal_velocity = across + direction * CONFIG.wall_dodge_speed

	-- the upward speed is set, not added to what the player had (UT2004: Velocity.Z = DodgeSpeedZ)
	local dodge_velocity = horizontal_velocity + Vector3(0, 0, CONFIG.wall_dodge_vertical_speed)

	locomotion_extension:set_maximum_upwards_velocity(math.huge)
	locomotion_extension:set_forced_velocity(dodge_velocity)
	locomotion_extension:set_wanted_velocity(dodge_velocity)

	state.dodged = true
	state.keep_speed = true

	-- multidodge: every wall dodge gives the double jump back
	if is_multidodge() then
		state.double_jumped = nil
	end

	play_dodge_animation(unit, first_person_extension, input_x, input_y)

	return true
end

-- Double jump
local function try_double_jump(self, unit, t)
	local locomotion_extension = self.locomotion_extension
	local velocity = locomotion_extension:current_velocity()
	local input_extension = self.input_extension

	if not (input_extension:get("jump") or input_extension:get("jump_only")) then
		return
	end

	local state = get_air_state(unit)

	if state.double_jumped then
		return
	end

	if locomotion_extension:is_on_ground() or self.csm.state_next then
		return
	end

	-- only near the apex of the jump
	if math.abs(velocity.z) >= CONFIG.double_jump_apex_speed then
		return
	end

	local jump_velocity = Vector3(velocity.x, velocity.y, CONFIG.double_jump_speed)

	-- the jumping state limits how fast the player can go up, the falling state doesn't
	locomotion_extension:set_maximum_upwards_velocity(math.huge)
	locomotion_extension:set_forced_velocity(jump_velocity)
	locomotion_extension:set_wanted_velocity(jump_velocity)

	state.double_jumped = true

	self.first_person_extension:play_camera_effect_sequence("jump", t)
	Unit.flow_event(unit, "sfx_player_jump")
end

-- A jump key press that dodged off a wall isn't a double jump as well
mod:hook_safe(PlayerCharacterStateJumping, "update", function (self, unit, input, dt, context, t)
	if not try_wall_dodge(self, unit, t) then
		try_double_jump(self, unit, t)
	end
end)

mod:hook_safe(PlayerCharacterStateFalling, "update", function (self, unit, input, dt, context, t)
	if not try_wall_dodge(self, unit, t) then
		try_double_jump(self, unit, t)
	end
end)

-- Gravity
-- The player's gravity is applied while their movement is updated. It is multiplied only for the
-- duration of the update, other code changes the player's gravity scale too (levels, effects)
-- and sees its own value.
mod:hook(PlayerUnitLocomotionExtension, "update_script_driven_movement", function (func, self, ...)
	local gravity_scale = self._script_driven_gravity_scale

	self._script_driven_gravity_scale = gravity_scale * CONFIG.gravity_multiplier

	func(self, ...)

	self._script_driven_gravity_scale = gravity_scale
end)

-- Multidodge also takes away the game's own limit: the more dodges in a row, the shorter they get
-- (and after the first few they no longer dodge attacks). The game does the same for its
-- infinite dodge perk.
mod:hook(GenericStatusExtension, "add_dodge_cooldown", function (func, self, ...)
	if is_multidodge() then
		self.dodge_cooldown = 0

		return
	end

	return func(self, ...)
end)

-- Crouching: no walking off ledges (UT2004: crouching and walking pawns stay on ledges), unless the
-- game is keeping the player crouched
-- A step is blocked when there is no ground in the direction the player is moving in. Moving
-- along an edge still works: the parts of the movement along the world's axes are tried on
-- their own.
local GROUND_FILTERS = {
	"filter_player_mover",
	"filter_player_ray_projectile_static_only",
}

local function has_ground_at(physics_world, position)
	local from = position + Vector3(0, 0, 0.3)
	local to = position - Vector3(0, 0, CONFIG.crouch_ledge_probe_depth)

	for i = 1, #GROUND_FILTERS do
		local result = PhysicsWorld.linear_sphere_sweep(physics_world, from, to, 0.1, 1, "collision_filter", GROUND_FILTERS[i])

		if result and #result > 0 then
			return true
		end
	end

	return false
end

-- A step is fine when there is ground ahead (stepping back to safety, moving along an edge), or
-- when the center of the player isn't further past the edge than the overhang: the ground is
-- there behind them, in the direction they are not going.
local function has_ground_ahead(physics_world, position, movement)
	if Vector3.length(movement) < 0.001 then
		return true
	end

	local direction = Vector3.normalize(movement)

	return has_ground_at(physics_world, position + direction * CONFIG.crouch_ledge_safe_reach) or has_ground_at(physics_world, position - direction * CONFIG.crouch_ledge_overhang)
end

mod:hook(CharacterStateHelper, "move_on_ground", function (func, first_person_extension, input_extension, locomotion_extension, local_move_direction, speed, unit, ...)
	func(first_person_extension, input_extension, locomotion_extension, local_move_direction, speed, unit, ...)

	if not ScriptUnit.extension(unit, "status_system"):is_crouching() then
		return
	end

	-- The game keeps the player crouched when they can't stand up (a low ceiling), and the ledge
	-- guard would trap them. It only applies to a player who could stand up.
	if not CharacterStateHelper.can_uncrouch(unit) then
		return
	end

	local wanted = Vector3.flat(locomotion_extension.velocity_wanted:unbox())
	local physics_world = World.get_data(Managers.world:world("level_world"), "physics_world")
	local position = POSITION_LOOKUP[unit]

	if has_ground_ahead(physics_world, position, wanted) then
		return
	end

	-- at a ledge: what is left of the movement is what can be done along each axis
	local allowed = Vector3.zero()
	local along_x = Vector3(wanted.x, 0, 0)
	local along_y = Vector3(0, wanted.y, 0)

	if math.abs(wanted.x) > 0.001 and has_ground_ahead(physics_world, position, along_x) then
		allowed = allowed + along_x
	end

	if math.abs(wanted.y) > 0.001 and has_ground_ahead(physics_world, position, along_y) then
		allowed = allowed + along_y
	end

	locomotion_extension:set_wanted_velocity(allowed)
end)
