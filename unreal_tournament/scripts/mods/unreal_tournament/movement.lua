local mod = get_mod("unreal_tournament")

-- UT movement:
--   * Dodging launches the player into the air, keeping their momentum, and can go forward.
--   * One extra jump in the air, only near the apex of a jump (after a jump or a dodge launch).
--   * Wall dodges: dodging towards a wall in the air launches the player off it.
--   * Stronger gravity.
--   * Crouching players don't walk off ledges.

local CONFIG = {
	-- The gravity, relative to the game's (11 m/s^2). Jumps get lower and shorter with it.
	gravity_multiplier = 1.3,
	-- The air control, which is how fast the player can change direction in the air, relative to the game's
	air_control_multiplier = 0.7,
	-- After the player climbs off the top of a ladder the gravity and the air control are the game's for this long. The climb ends a
	-- little above the platform, and the player is in the air for a moment. With the stronger gravity and the weaker air control they
	-- fall back down the ladder before they can move onto the platform.
	ladder_exit_grace = 1, -- seconds
	-- A crouching player does not walk off ledges. The center of the player may be this far past the edge, so a bit more
	-- than half of them hangs off. Further out, the physics starts to make them slide off by themselves.
	crouch_ledge_overhang = 0.1, -- m
	-- The ground is looked for down to this far below the player's feet. Stairs count as ground, and drops count as ledges.
	crouch_ledge_probe_depth = 0.7, -- m
	-- Moving towards ground is always allowed. The ground is looked for this far ahead. This has to be more than the radius of
	-- the player, who can be that far past an edge, so that crouching there does not trap them.
	crouch_ledge_safe_reach = 0.4, -- m
	-- The regular jump, relative to the game's (4.25 m/s). The dodge launch and the double jump have their own speeds. The
	-- jump is kept higher than the dodge launch.
	jump_speed_multiplier = 1.35,
	-- Like in UT2004, after landing from a dodge the next dodge is locked for this long.
	dodge_landing_delay = 0.35, -- seconds
	-- Dodge launch
	dodge_launch_vertical_speed = 4.25, -- m/s, the same as a regular jump
	dodge_launch_horizontal_speed = 7, -- m/s added to the current horizontal speed, the peak speed of the regular dodge
	dodge_launch_max_speed = 9, -- m/s, the horizontal speed after adding the two together is limited to this
	-- Wall dodge
	wall_dodge_reach = 1, -- m, how far from the center of the player a wall can be
	-- Like in UT2004, the speed along the dodge is 1.5 times the ground speed, and the player's momentum across the dodge is
	-- kept with no limit. The upward speed is set, whatever it was.
	wall_dodge_speed = 6, -- m/s in the direction of the dodge (1.5 * the run speed of 4)
	wall_dodge_vertical_speed = 4.25, -- m/s, the upward speed it sets, the same as the dodge launch
	-- The double jump works like in UT2004. It can be used once per airtime, only near the apex of the jump, and it sets the
	-- upward speed. UT allows it while the vertical speed is within 100 uu/s of zero, which is 29% of its jump speed
	-- (340 uu/s). The same share of this game's jump speed gives the window.
	double_jump_speed = 5, -- m/s, the upward speed it gives, a regular jump is 4.25 * jump_speed_multiplier
	double_jump_apex_speed = 1.7, -- m/s, it is allowed while the vertical speed is within this of zero
	-- A wall is found by sweeping a sphere of this radius sideways at these heights above the feet.
	wall_sweep_heights = {0.3, 0.9, 1.5}, -- m
	wall_sweep_radius = 0.25, -- m
	-- Momentum damage: melee hits do more damage the faster the player is moving. There is no bonus up to momentum_min_speed,
	-- which is about running speed (the game's is 4 m/s). The bonus then rises to momentum_damage_bonus at momentum_full_speed
	-- (a dodge launch is 9 m/s at most), and keeps rising above that. A speed still counts for momentum_grace seconds after it
	-- is lost, so that slowing down (a hit, the end of a dodge) does not take the bonus away at once.
	momentum_min_speed = 4.5, -- m/s
	momentum_full_speed = 9, -- m/s
	momentum_damage_bonus = 0.25, -- the bonus at full speed: 0.25 is 25% more damage
	momentum_grace = 0.1, -- seconds
	-- Fall damage, as UT's Pawn.TakeFallingDamage: landing faster than MaxFallSpeed hurts 100 * (speed - MaxFallSpeed) / MaxFallSpeed,
	-- however far the fall was. UT speeds are turned into this game's by the ratio of the jumps (UT's JumpZ against this mod's jump), as
	-- the weapon jumps are. That makes MaxFallSpeed about 20 m/s, a fall of about 14 m with the gravity above.
	ut_max_fall_speed = 1200, -- UT units a second
	ut_jump_speed = 340, -- UT units a second
}

-- The Movement option switches off all the movement in this file. The hooks then do what the game does.
local function is_movement_enabled()
	return mod:get("ut_movement") ~= false
end

-- The Multidodge option removes the limits on dodging.
local function is_multidodge()
	return is_movement_enabled() and mod:get("multidodge")
end

-- What has happened in the air since the player was last on the ground, for each unit:
--   double_jumped: the extra jump was used.
--   dodged: a dodge was done, on the ground or on a wall. Landing then locks dodging for a while.
--   keep_speed: a dodge launch is in progress, and its horizontal speed is kept.
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

-- The time until which dodging is locked, for each unit
local dodge_unlocked_t = setmetatable({}, {
	__mode = "k",
})

-- Landing starts a new time in the air for the next jump. Landing from a dodge also locks dodging for a while.
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

-- Climbing or hanging also starts a new time in the air. Hanging is reported by the shared ledge hook in hooks.lua, because a
-- function can only be hooked once.
mod:hook_safe(PlayerCharacterStateClimbingLadder, "on_enter", function (self, unit, input, dt, context, t, previous_state)
	reset_air_state(self, unit)
end)

-- Leaving a ladder at the top. The game only climbs off when the player is above the ladder's box and moving up. How fast the player
-- climbs depends on which way they look, so looking down at the platform while pressing forward gives no upward speed, and the game
-- then drops the player back on the ladder (it does that without this mod too, and the stronger gravity and the weaker air control
-- make it worse). A player that is above the height where the game lets them climb off, and out of the ladder's box, climbs off
-- whichever way they are moving.
mod:hook(PlayerCharacterStateClimbingLadder, "update", function (func, self, unit, ...)
	if is_movement_enabled() and not self.position_lerp_timer and not self.csm.state_next then
		local movement_settings_table = PlayerUnitMovementSettings.get_movement_settings_table(unit)
		local above_climb_off_height = self.jump_off_height - movement_settings_table.ladder.leaving_ladder_height_below_get_of_node <= Vector3.z(Unit.world_position(unit, 0))

		if above_climb_off_height and not CharacterStateHelper.is_colliding_with_gameplay_collision_box(self.world, unit, "filter_ladder_collision") then
			local params = self.temp_params

			params.ladder_unit = self.ladder_unit

			self.csm:change_state("leaving_ladder_top", params)

			return
		end
	end

	return func(self, unit, ...)
end)

-- When the player last climbed off the top of a ladder, for each unit.
local ladder_exit_t = setmetatable({}, {
	__mode = "k",
})

local function recently_left_ladder(unit)
	local exit_t = ladder_exit_t[unit]

	return exit_t ~= nil and Managers.time:time("game") - exit_t < CONFIG.ladder_exit_grace
end

mod:hook_safe(PlayerCharacterStateLeavingLadderTop, "on_exit", function (self, unit, input, dt, context, t, next_state)
	ladder_exit_t[unit] = t
end)

mod.ledge_hang_callbacks.movement = function (unit)
	reset_air_state(nil, unit)
end

-- A jump from the ground starts a new time in the air, and the jump is stronger. A jump out of falling does not start a new one.
-- The jumping state reads the jump speed from the player's movement settings when it starts, so the settings are changed while
-- it starts. One hook does both, because the game has had trouble with more than one hook on the same function.
mod:hook(PlayerCharacterStateJumping, "on_enter", function (func, self, unit, input, dt, context, t, previous_state, ...)
	if not is_movement_enabled() then
		return func(self, unit, input, dt, context, t, previous_state, ...)
	end

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
-- The game never dodges forwards. It rejects forward input, and a forward-sideways input becomes a sideways dodge. This adds a
-- forward dodge on a double tap of forward, when the player has the other double taps turned on, and on the dodge key with only
-- forward pressed. There is no animation for dodging forward, so the dodge plays the backward one. The dodge sound comes with
-- the animation.
local FORWARD_TAP = "move_forward_pressed"

mod:hook(CharacterStateHelper, "check_to_start_dodge", function (func, unit, input_extension, status_extension, t)
	if not is_movement_enabled() then
		return func(unit, input_extension, status_extension, t)
	end

	-- There is no dodging while crouching, because the jump key then uncrouches and jumps. There is also none right after
	-- landing from a dodge.
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

	-- This is what the game does when it starts a dodge.
	Managers.state.entity:system("play_go_tutorial_system"):register_dodge(dodge_direction)
	status_extension:add_fatigue_points("action_dodge")
	status_extension:set_dodge_locked(true)
	status_extension:add_dodge_cooldown()

	return true, dodge_direction
end)

-- Dodge launch
-- The dodge has set itself up by the time this runs. Leaving the ground ends the dodge, because the dodge state hands over to
-- falling when the player is not on the ground. So the horizontal speed of the dodge has to be set as well.
mod:hook_safe(PlayerCharacterStateDodging, "on_enter", function (self, unit, input, dt, context, t)
	if not is_movement_enabled() then
		return
	end

	local locomotion_extension = self.locomotion_extension
	local first_person_extension = self.first_person_extension
	local flat_rotation = Quaternion.look(Vector3.flat(Quaternion.forward(first_person_extension:current_rotation())), Vector3.up())
	local direction = Quaternion.rotate(flat_rotation, self.dodge_direction:unbox())

	-- The dodge is added to the momentum the player had.
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

-- The game's air movement limits the horizontal speed to the run speed, which would take the speed of the dodge launch away at
-- once. This lets a dodge launch keep its speed, and steering still works. The speed passed to the air movement is how much the
-- player can steer, and it is scaled by the air control.
mod:hook(CharacterStateHelper, "move_in_air", function (func, first_person_extension, input_extension, locomotion_extension, speed, unit, ...)
	if not is_movement_enabled() then
		return func(first_person_extension, input_extension, locomotion_extension, speed, unit, ...)
	end

	if recently_left_ladder(unit) then
		return func(first_person_extension, input_extension, locomotion_extension, speed, unit, ...)
	end

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
-- In the air, a dodge input with a wall behind it launches the player off the wall. The inputs are the same as for dodging on
-- the ground: a double tap if the player has turned those on, the dodge key with a direction held, and the jump key with a
-- sideways or backward direction held, which is the game's default way to dodge. Without a wall, that jump key is the double
-- jump as usual. Like in UT2004, there is one dodge per airtime, and a dodge launch from the ground counts as that dodge.
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

-- Returns the local direction the player wants to dodge in as x and y, and whether the jump key was the input. Returns nothing
-- if the player does not want to dodge.
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

		-- Forward with the jump key is a jump, like on the ground.
		if length > input_extension.minimum_dodge_input and (input_extension:get("dodge") or input.y <= 0) then
			return input.x / length, input.y / length, not input_extension:get("dodge")
		end
	end
end

-- Plays the animation of a dodge in a local direction, picked the way the dodge state picks it. The dodge sound comes with the
-- animation.
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

-- A wall is found by sweeping a sphere sideways at a few heights, because a ray at one height can miss a low wall or slip
-- through a gap. The sweep tests against the game's collision with the level's static geometry for projectiles, and also against
-- the player's mover filter.
local WALL_FILTERS = {
	"filter_player_mover",
	"filter_player_ray_projectile_static_only",
}

-- Returns whether there is a wall in the given direction.
local function find_wall(physics_world, position, direction)
	local found_hit

	for i = 1, #WALL_FILTERS do
		for j = 1, #CONFIG.wall_sweep_heights do
			local from = position + Vector3(0, 0, CONFIG.wall_sweep_heights[j])
			local to = from + direction * CONFIG.wall_dodge_reach
			local result = PhysicsWorld.linear_sphere_sweep(physics_world, from, to, CONFIG.wall_sweep_radius, 5, "collision_filter", WALL_FILTERS[i])
			local num_hits = result and #result or 0
			local wall_hit

			for k = 1, num_hits do
				local hit = result[k]

				-- Floors and ceilings are not walls.
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

-- Dodges off a wall if the player asks for it. Returns true if it dodged.
local function try_wall_dodge(self, unit, t)
	local state = get_air_state(unit)
	local input_x, input_y = read_air_dodge_input(self.input_extension, t)

	if not input_x then
		return false
	end

	-- UT2004 does not dodge while crouching or about to crouch, and allows one dodge in the air, unless multidodge is on.
	if state.dodged and not is_multidodge() or self.status_extension:is_crouching() then
		return false
	end

	local locomotion_extension = self.locomotion_extension
	local first_person_extension = self.first_person_extension

	if locomotion_extension:is_on_ground() or self.csm.state_next then
		return false
	end

	-- Like in UT2004, the wall has to be behind the dodge. Dodging left needs a wall on the right, and the player dodges off it.
	-- Dodging into a wall does nothing.
	local flat_rotation = Quaternion.look(Vector3.flat(Quaternion.forward(first_person_extension:current_rotation())), Vector3.up())
	local direction = Quaternion.rotate(flat_rotation, Vector3(input_x, input_y, 0))
	local position = POSITION_LOOKUP[unit]

	if not find_wall(self.physics_world, position, -direction) then
		return false
	end

	-- The dodge goes in the direction of the input, and the momentum across it is kept. UT2004 does this with
	-- Velocity = DodgeSpeed * Dir + (Velocity dot Cross) * Cross.
	local velocity = locomotion_extension:current_velocity()
	local flat_velocity = Vector3.flat(velocity)
	local across = flat_velocity - direction * Vector3.dot(flat_velocity, direction)
	local horizontal_velocity = across + direction * CONFIG.wall_dodge_speed

	-- The upward speed is set, not added to what the player had. UT2004 does this with Velocity.Z = DodgeSpeedZ.
	local dodge_velocity = horizontal_velocity + Vector3(0, 0, CONFIG.wall_dodge_vertical_speed)

	locomotion_extension:set_maximum_upwards_velocity(math.huge)
	locomotion_extension:set_forced_velocity(dodge_velocity)
	locomotion_extension:set_wanted_velocity(dodge_velocity)

	state.dodged = true
	state.keep_speed = true

	-- With multidodge, every wall dodge gives the double jump back.
	if is_multidodge() then
		state.double_jumped = nil
	end

	play_dodge_animation(unit, first_person_extension, input_x, input_y)

	return true
end

-- Double jump: gives the player the extra jump if they ask for it near the apex of a jump.
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

	-- The double jump is only allowed near the apex of the jump.
	if math.abs(velocity.z) >= CONFIG.double_jump_apex_speed then
		return
	end

	local jump_velocity = Vector3(velocity.x, velocity.y, CONFIG.double_jump_speed)

	-- The jumping state limits how fast the player can go up, and the falling state does not.
	locomotion_extension:set_maximum_upwards_velocity(math.huge)
	locomotion_extension:set_forced_velocity(jump_velocity)
	locomotion_extension:set_wanted_velocity(jump_velocity)

	state.double_jumped = true

	self.first_person_extension:play_camera_effect_sequence("jump", t)
	Unit.flow_event(unit, "sfx_player_jump")
end

-- A jump key press that dodged off a wall is not also a double jump.
mod:hook_safe(PlayerCharacterStateJumping, "update", function (self, unit, input, dt, context, t)
	if is_movement_enabled() and not try_wall_dodge(self, unit, t) then
		try_double_jump(self, unit, t)
	end
end)

-- UT's cheats "fly" and "walk" (CheatManager.Fly and Walk, and PlayerController's state PlayerFlying): the player flies the way they
-- look, forward, back and to the sides, with no gravity, and stops when no key is held. They still collide with the level. The speed is
-- UT's AirSpeed, which is its GroundSpeed (440), so this game's run speed. "walk" lands them again. The fall from where the flight ends
-- is the only one that counts. It works whether the Movement option is on or not.
-- UT's cheat "ghost" (CheatManager.Ghost) is the same flight through walls: the player is moved by the game's own movement without the
-- mover (update_script_driven_no_mover_movement), which nothing blocks, and the mover is kept with them.
local flying_unit
local ghost = false

-- The velocity of the flight now
local function flight_velocity(unit)
	local input_extension = ScriptUnit.extension(unit, "input_system")
	local first_person_extension = ScriptUnit.extension(unit, "first_person_system")
	local move = CharacterStateHelper.get_movement_input(input_extension)
	local rotation = first_person_extension:current_rotation()
	local direction = Quaternion.forward(rotation) * Vector3.y(move) + Quaternion.right(rotation) * Vector3.x(move)

	if Vector3.length(direction) < 0.01 then
		return Vector3.zero()
	end

	return Vector3.normalize(direction) * PlayerUnitMovementSettings.get_movement_settings_table(unit).move_speed
end

local function fly(unit)
	local locomotion_extension = ScriptUnit.extension(unit, "locomotion_system")
	local velocity = flight_velocity(unit)

	-- (a flight up from the ground leaves it, which makes the player fall: the falling state then keeps the flight going)
	if locomotion_extension:is_on_ground() and Vector3.z(velocity) > 0.01 then
		locomotion_extension:force_on_ground(false)
	end

	locomotion_extension:set_maximum_upwards_velocity(math.huge)

	-- (the movement without the mover takes only the wanted velocity, and a forced one would be left for the first move after the ghost)
	if not ghost then
		locomotion_extension:set_forced_velocity(velocity)
	end

	locomotion_extension:set_wanted_velocity(velocity)

	-- (the height a fall is measured from is where the flight is; on the ground it would also start a landing every frame)
	if not locomotion_extension:is_on_ground() then
		ScriptUnit.extension(unit, "status_system"):set_falling_height(true, POSITION_LOOKUP[unit].z)
	end
end

mod:command("fly", "- you fly the way you look, with no gravity, until /walk (UT's fly)", function ()
	local player = Managers.player:local_player_safe()
	local unit = player and player.player_unit

	if unit and Unit.alive(unit) then
		flying_unit = unit
		ghost = false

		mod:echo("You feel much lighter")
	end
end)

mod:command("ghost", "- you fly the way you look, through walls, until /walk (UT's ghost)", function ()
	local player = Managers.player:local_player_safe()
	local unit = player and player.player_unit

	if unit and Unit.alive(unit) then
		flying_unit = unit
		ghost = true

		mod:echo("You feel ethereal")
	end
end)

mod:command("walk", "- ends /fly and /ghost", function ()
	flying_unit = nil
	ghost = false
end)

-- The flight is the player's own character's. It ends with that character (a death, a new level).
mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	if not flying_unit then
		return
	end

	local player = Managers.player:local_player_safe()

	if not player or player.player_unit ~= flying_unit or not Unit.alive(flying_unit) then
		flying_unit = nil
		ghost = false
	end
end

-- The flight goes on in the states of the character's movement, where the input of the frame is read (it is gone by the mod's update).
-- On the ground it is the walking and standing states, which it leaves when it goes up.
for _, state in ipairs({
	PlayerCharacterStateWalking,
	PlayerCharacterStateStanding,
}) do
	mod:hook_safe(state, "update", function (self, unit)
		if unit == flying_unit then
			fly(unit)
		end
	end)
end

mod:hook_safe(PlayerCharacterStateFalling, "update", function (self, unit, input, dt, context, t)
	-- (after the falling state has set the speed it wants, the flight sets its own)
	if unit == flying_unit then
		fly(unit)

		return
	end

	if is_movement_enabled() and not try_wall_dodge(self, unit, t) then
		try_double_jump(self, unit, t)
	end
end)

-- The player's upward speed in the air, last time their movement was updated, for each unit
local fall_speeds = setmetatable({}, {
	__mode = "k",
})

-- Gravity
-- The player's gravity is applied while their movement is updated. It is multiplied only during that update. Other code, such as
-- levels and effects, also changes the player's gravity scale, and it must see its own value.
--
-- Blocked upward speed
-- In the air, the game keeps the upward speed it worked out, not the one the player actually moved. So when a weapon jump throws
-- the player into a ceiling or an overhang, the player stays pressed against it until gravity has used that speed up. UT2004
-- takes away the speed that goes into what the player hit. Here the upward speed is cut to what the player moved when the mover
-- hit something, as the game already does for the speed sideways.
mod:hook(PlayerUnitLocomotionExtension, "update_script_driven_movement", function (func, self, unit, dt, t, calculate_fall_velocity, ...)
	-- (a ghost moves without the mover, which is put where they are, see /ghost)
	if unit == flying_unit and ghost then
		self:update_script_driven_no_mover_movement(unit, dt, t)
		Mover.set_position(Unit.mover(unit), Unit.local_position(unit, 0))

		return
	end

	-- (a flight has no gravity, see /fly)
	if unit == flying_unit then
		local gravity_scale = self._script_driven_gravity_scale

		self._script_driven_gravity_scale = 0

		func(self, unit, dt, t, calculate_fall_velocity, ...)

		self._script_driven_gravity_scale = gravity_scale

		return
	end

	if not is_movement_enabled() then
		return func(self, unit, dt, t, calculate_fall_velocity, ...)
	end

	if recently_left_ladder(self.unit) then
		return func(self, unit, dt, t, calculate_fall_velocity, ...)
	end

	local gravity_scale = self._script_driven_gravity_scale
	-- The game scales its dt by this inside the update, and clears it
	local moved_dt = dt * (self._script_movement_time_scale or 1)
	local start_z = Unit.local_position(unit, 0).z
	local speed_before = self.velocity_current:unbox().z

	self._script_driven_gravity_scale = gravity_scale * CONFIG.gravity_multiplier

	func(self, unit, dt, t, calculate_fall_velocity, ...)

	self._script_driven_gravity_scale = gravity_scale

	local velocity = self.velocity_current:unbox()
	local mover = Unit.mover(unit)

	-- The upward speed in the air before the player lands, for the fall damage below. The game's velocity is how far the mover moved
	-- in the frame, and the floor cuts the move of the frame that reaches it short. That frame's speed is the one the player came
	-- down with, and this frame's gravity.
	if not self:is_on_ground() then
		if Mover.collides_down(mover) then
			local gravity = PlayerUnitMovementSettings.get_movement_settings_table(unit).gravity_acceleration

			fall_speeds[unit] = speed_before - gravity * gravity_scale * CONFIG.gravity_multiplier * moved_dt
		else
			fall_speeds[unit] = velocity.z
		end
	end

	if not calculate_fall_velocity or velocity.z <= 0 or moved_dt <= 0 then
		return
	end

	if not Mover.collides_up(mover) and not Mover.collides_sides(mover) then
		return
	end

	local moved_z = (Unit.local_position(unit, 0).z - start_z) / moved_dt

	if moved_z < velocity.z then
		velocity.z = math.max(moved_z, 0)

		self.velocity_current:store(velocity)
	end
end)

-- Multidodge also removes the game's own limit. Normally the more dodges in a row, the shorter they get, and after the first few
-- they no longer avoid attacks. The game removes the same limit for its infinite dodge perk.
mod:hook(GenericStatusExtension, "add_dodge_cooldown", function (func, self, ...)
	if is_multidodge() then
		self.dodge_cooldown = 0

		return
	end

	return func(self, ...)
end)

-- UT's fall damage (see ut_max_fall_speed) in place of the game's, which goes by how far the player fell. The game's is taken away by
-- the flag that removes the next landing's damage, set on every update. The landing is the game's (GenericStatusExtension.update_falling,
-- on the player's own machine), with the same exceptions: bots, the Keep and riding in a transport take none. The Shield Gun's shield
-- can take some of it (mod.shield.absorb_fall).
local function take_falling_damage(status_extension)
	local unit = status_extension.unit
	local speed = fall_speeds[unit]

	fall_speeds[unit] = nil

	if not speed or status_extension.is_bot or global_is_inside_inn or status_extension.inside_transport_unit then
		return
	end

	local jump_speed = PlayerUnitMovementSettings.get_movement_settings_table(unit).jump.initial_vertical_speed * CONFIG.jump_speed_multiplier
	local max_speed = CONFIG.ut_max_fall_speed * jump_speed / CONFIG.ut_jump_speed

	if -speed <= max_speed then
		return
	end

	local damage = 100 * (-speed - max_speed) / max_speed

	if mod.shield and mod.shield.absorb_fall then
		damage = mod.shield.absorb_fall(unit, damage)
	end

	if damage > 0 then
		DamageUtils.add_damage_network(unit, unit, damage, "full", "kinetic", nil, Vector3.up(), "ground_impact", nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 1)
	end
end

mod:hook(GenericStatusExtension, "update_falling", function (func, self, ...)
	if is_movement_enabled() then
		self.ignore_next_fall_damage = true

		if self.locomotion_extension:is_on_ground() and not self.on_ladder then
			take_falling_damage(self)
		end
	end

	return func(self, ...)
end)

-- Crouching players do not walk off ledges, like UT2004's crouching and walking pawns. The exception is when the game is keeping
-- the player crouched. A step is blocked when there is no ground in the direction the player is moving. Moving along an edge
-- still works, because the parts of the movement along each of the world's axes are tried on their own.
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

-- Returns whether a step is allowed. A step is fine when there is ground ahead, for example when stepping back to safety or
-- moving along an edge. It is also fine when the center of the player is not further past the edge than the overhang, because
-- then the ground is behind them, in the direction they are not going.
local function has_ground_ahead(physics_world, position, movement)
	if Vector3.length(movement) < 0.001 then
		return true
	end

	local direction = Vector3.normalize(movement)

	return has_ground_at(physics_world, position + direction * CONFIG.crouch_ledge_safe_reach) or has_ground_at(physics_world, position - direction * CONFIG.crouch_ledge_overhang)
end

mod:hook(CharacterStateHelper, "move_on_ground", function (func, first_person_extension, input_extension, locomotion_extension, local_move_direction, speed, unit, ...)
	func(first_person_extension, input_extension, locomotion_extension, local_move_direction, speed, unit, ...)

	if not is_movement_enabled() or not ScriptUnit.extension(unit, "status_system"):is_crouching() then
		return
	end

	-- The game keeps the player crouched when they cannot stand up, for example under a low ceiling, and the ledge guard would
	-- trap them there. So the guard only applies to a player who could stand up.
	if not CharacterStateHelper.can_uncrouch(unit) then
		return
	end

	local wanted = Vector3.flat(locomotion_extension.velocity_wanted:unbox())
	local physics_world = World.get_data(Managers.world:world("level_world"), "physics_world")
	local position = POSITION_LOOKUP[unit]

	if has_ground_ahead(physics_world, position, wanted) then
		return
	end

	-- At a ledge, the movement that is left is the part that can be done along each axis.
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

-- The barriers option removes each barrier that is turned on in its settings: invisible walls, kill zones and ledges.
local function is_barrier_removed(setting_id)
	return mod:get("no_barriers") and mod:get(setting_id) ~= false
end

-- Invisible walls
-- The player's movement collides with the level through a collision profile, called a mover filter. The level's walls that keep
-- heroes in belong to groups that the heroes' profile collides with and the dark pact players' profile does not, because the game
-- has a separate group of blockers for each of them. With the option on, the player moves with the dark pact players' profile.
-- This only affects the player's own character and changes nothing in the level.
local INVISIBLE_WALL_MOVER_FILTER = "filter_player_mover_pactsworn"

local function is_passing_invisible_walls()
	return is_barrier_removed("no_invisible_walls")
end

-- When no mode such as a ladder is active, the game uses the locomotion's default filter. That default is replaced only during
-- the call that sets the filter.
mod:hook(PlayerUnitLocomotionExtension, "set_mover_filter_property", function (func, self, ...)
	local default_filter = self._default_mover_filter

	if is_passing_invisible_walls() and self.player and not self.player.remote then
		self._default_mover_filter = INVISIBLE_WALL_MOVER_FILTER
	end

	func(self, ...)

	self._default_mover_filter = default_filter
end)

-- The filter is set again when the option is changed and when the player has a new unit.
local applied_unit
local applied_enabled = false

local function update_mover_filter()
	local player = Managers.player:local_player_safe()
	local unit = player and player.player_unit

	if not unit or not Unit.alive(unit) then
		applied_unit = nil
		applied_enabled = false

		return
	end

	local enabled = not not is_passing_invisible_walls()

	if applied_unit == unit and applied_enabled == enabled then
		return
	end

	local locomotion_extension = ScriptUnit.has_extension(unit, "locomotion_system")
	local modes = locomotion_extension and locomotion_extension._mover_modes

	if modes then
		-- This sets the filter for the modes the player is in now.
		locomotion_extension:set_mover_filter_property("ladder", modes.ladder)

		applied_unit = unit
		applied_enabled = enabled
	end
end

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	update_mover_filter()
end

-- The game's own filter comes back when the mod is reloaded or switched off.
mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
	applied_unit = nil
end

mod.disabled_callbacks[#mod.disabled_callbacks + 1] = function ()
	update_mover_filter()
end

mod.setting_changed_callbacks[#mod.setting_changed_callbacks + 1] = function (setting_id)
	if setting_id == "no_barriers" or setting_id == "no_invisible_walls" then
		applied_unit = nil
	end
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	applied_unit = nil
	applied_enabled = false
end

-- Kill zones: entering one kills the player, because the health extension is told about it.
mod:hook(PlayerUnitHealthExtension, "entered_kill_volume", function (func, self, ...)
	if is_barrier_removed("no_kill_zones") then
		return
	end

	return func(self, ...)
end)

-- Lifts and moving platforms: while one moves, a player who is on it but has left its box is put back on it.
mod:hook(LinkerTransportationExtension, "_update_local_player_position", function (func, self, ...)
	if is_barrier_removed("no_lifts") then
		return
	end

	return func(self, ...)
end)

-- Ledges: the player hangs from a ledge they fall past, until they are pulled up.
mod:hook(CharacterStateHelper, "is_ledge_hanging", function (func, ...)
	if is_barrier_removed("no_ledges") then
		return false
	end

	return func(...)
end)

mod:hook(CharacterStateHelper, "will_be_ledge_hanging", function (func, ...)
	if is_barrier_removed("no_ledges") then
		return false
	end

	return func(...)
end)

-- Momentum damage (see momentum_* in CONFIG). The damage of a melee hit comes from the power level the attacker sends with it.
-- That power level is what gets scaled, both for the hit and for the prediction of the hit.

-- Returns how much of the full-speed bonus the speed gives. It is 0 up to the minimum speed, 1 at full speed, and keeps rising
-- above that.
local function momentum_share(speed)
	return math.max((speed - CONFIG.momentum_min_speed) / (CONFIG.momentum_full_speed - CONFIG.momentum_min_speed), 0)
end

-- Grace: the player's fastest recent speed is kept for momentum_grace seconds. It is tracked while the player moves, for the
-- local player's unit.
local recent = {
	speed = 0,
	t = 0,
}

local function update_recent_speed()
	local player = Managers.player:local_player_safe()
	local unit = player and player.player_unit
	local locomotion_extension = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "locomotion_system")

	if not locomotion_extension then
		recent.unit = nil

		return
	end

	local t = Managers.time:time("game")
	local speed = Vector3.length(locomotion_extension:current_velocity())

	if recent.unit ~= unit or speed >= recent.speed or t - recent.t > CONFIG.momentum_grace then
		recent.unit = unit
		recent.speed = speed
		recent.t = t
	end
end

-- Returns how fast the unit is moving, counting the speed it had a moment ago.
local function momentum_speed(unit, locomotion_extension)
	local speed = Vector3.length(locomotion_extension:current_velocity())

	if recent.unit == unit and Managers.time:time("game") - recent.t <= CONFIG.momentum_grace then
		speed = math.max(speed, recent.speed)
	end

	return speed
end

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	update_recent_speed()
end

local function momentum_damage_multiplier(owner_unit)
	if not is_movement_enabled() or not mod:get("momentum_damage") then
		return 1
	end

	local locomotion_extension = Unit.alive(owner_unit) and ScriptUnit.has_extension(owner_unit, "locomotion_system")

	if not locomotion_extension then
		return 1
	end

	local speed = momentum_speed(owner_unit, locomotion_extension)
	local share = momentum_share(speed)

	return 1 + CONFIG.momentum_damage_bonus * share
end

mod:hook(ActionSweep, "_send_attack_hit", function (func, self, t, damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id, hit_position, attack_direction, damage_profile_id, ...)
	local num_args = select("#", ...)
	local args = {
		...,
	}

	for i = 1, num_args - 1 do
		if args[i] == "power_level" then
			args[i + 1] = args[i + 1] * momentum_damage_multiplier(self.owner_unit)

			break
		end
	end

	return func(self, t, damage_source_id, attacker_unit_id, hit_unit_id, hit_zone_id, hit_position, attack_direction, damage_profile_id, unpack(args, 1, num_args))
end)

mod:hook(ActionSweep, "_play_character_impact", function (func, self, is_server, attacker_unit, hit_unit, breed, hit_position, hit_zone_name, current_action, damage_profile, target_index, power_level, ...)
	return func(self, is_server, attacker_unit, hit_unit, breed, hit_position, hit_zone_name, current_action, damage_profile, target_index, power_level * momentum_damage_multiplier(attacker_unit), ...)
end)
