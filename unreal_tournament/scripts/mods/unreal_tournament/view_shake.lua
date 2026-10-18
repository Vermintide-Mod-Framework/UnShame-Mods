local mod = get_mod("unreal_tournament")

-- UT's view shake of a weapon's shot (WeaponFire.ShakeOffsetMag, ShakeOffsetRate and ShakeOffsetTime; PlayerController.ShakeView,
-- ViewShake and CheckShake), for the player on this machine. It moves the camera, and the first person weapon with it: UT adds the
-- shake to where it draws the weapon too (Pawn.CalcDrawOffset adds CameraShake), so the weapon stays where it is on the screen while
-- the world shakes. weapon_skin.lua moves the model by view_shake.offset(), and turns it by view_shake.turn().
--   view_shake.start(magnitude, rate, time): magnitude and rate are { forward, right, up } in UT units and UT units a second, and time is
--       UT's ShakeOffsetTime. A new shake replaces the current one only if its magnitude is longer.
--   view_shake.offset(): how far the shake moves the camera now, in meters along the view's axes: right, forward, up.
--   view_shake.start_rotation(magnitude, rate, time): the turn of the shake (WeaponFire.ShakeRotMag, ShakeRotRate and ShakeRotTime):
--       magnitude and rate are { pitch, yaw, roll } in UT's units of a turn (65536 to a whole turn) and those a second. It is added to
--       the camera's turn (PlayerController.ShakeRot). It replaces the current turn of the shake only if its magnitude is bigger. UT
--       draws the weapon without it, so there the weapon shakes on the screen too. Here the weapon is turned with the camera, so that only
--       the world shakes and the weapon shakes only by its own animation.
--   view_shake.turn(): the turn of the shake now, in the view's axes, or nil.
-- On each axis the offset moves at the rate until it reaches its limit, then turns back. Each time it turns, the limit is multiplied
-- by (1 / time - 1), about -0.5 at first, and time goes down by a frame. Once time is down to 1, that axis stops. The turn does the same.

local utils = mod.utils

local UNIT = utils.UT_UNIT

local view_shake = {}
mod.view_shake = view_shake

-- The current shake: a table for each axis (forward, right, up) with its offset, limit (most), rate and time. Nil when there is no shake.
local axes
-- The current turn of the shake, the same for each axis (pitch, yaw, roll), in UT's units of a turn
local turn_axes

-- Returns new axes for a shake, or the current ones if they are bigger (as ShakeView compares the size of the two magnitudes)
local function shake_axes(current_axes, magnitude, rate, time)
	if current_axes then
		local current = 0
		local new = 0

		for i = 1, 3 do
			current = current + current_axes[i].most * current_axes[i].most
			new = new + magnitude[i] * magnitude[i]
		end

		if new <= current then
			return current_axes
		end
	end

	local new_axes = {}

	for i = 1, 3 do
		new_axes[i] = {
			offset = 0,
			most = magnitude[i],
			rate = rate[i],
			time = time,
		}
	end

	return new_axes
end

function view_shake.start(magnitude, rate, time)
	axes = shake_axes(axes, magnitude, rate, time)
end

function view_shake.start_rotation(magnitude, rate, time)
	turn_axes = shake_axes(turn_axes, magnitude, rate, time)
end

-- Moves one axis of the shake by a frame, as UT's CheckShake does. An axis of the turn wraps around a whole turn first, as
-- UpdateShakeRotComponent does with its whole number of UT's units.
local function update_axis(axis, dt, turn)
	if axis.rate == 0 then
		return
	end

	axis.offset = axis.offset + dt * axis.rate

	if turn then
		axis.offset = math.floor(axis.offset) % 65536

		if axis.offset > 32768 then
			axis.offset = axis.offset - 65536
		end
	end

	if math.abs(axis.offset) < math.abs(axis.most) then
		return
	end

	axis.offset = axis.most

	if axis.time > 1 then
		if axis.time * math.abs(axis.most / axis.rate) <= 1 then
			axis.most = axis.most * (1 / axis.time - 1)
		else
			axis.most = -axis.most
		end

		axis.time = axis.time - dt
		axis.rate = -axis.rate
	else
		axis.offset = 0
		axis.most = 0
		axis.rate = 0
	end
end

-- Moves the axes of a shake by a frame. Returns them, or nil once they have all stopped.
local function update_axes(shake, dt, turn)
	if not shake then
		return nil
	end

	local moving = false

	for i = 1, 3 do
		update_axis(shake[i], dt, turn)
		moving = moving or shake[i].rate ~= 0
	end

	return moving and shake or nil
end

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	axes = update_axes(axes, dt, false)
	turn_axes = update_axes(turn_axes, dt, true)
end

local TURN = 2 * math.pi / 65536 -- radians in UT's unit of a turn

-- The turn of the shake now, in the view's axes (pitch about its right, yaw about its up, roll about its forward), or nil
function view_shake.turn()
	if not turn_axes then
		return nil
	end

	local pitch = Quaternion.axis_angle(Vector3.right(), turn_axes[1].offset * TURN)
	local yaw = Quaternion.axis_angle(Vector3.up(), turn_axes[2].offset * TURN)
	local roll = Quaternion.axis_angle(Vector3.forward(), turn_axes[3].offset * TURN)

	return Quaternion.multiply(yaw, Quaternion.multiply(pitch, roll))
end

-- The game moves the camera by its offsets in this function, after its other effects. The shake is added at the same point: the
-- offset to its place, and the turn to its turn.
mod:hook_safe(CameraManager, "_apply_offset", function (self, camera_data)
	if axes then
		local rotation = camera_data.rotation
		local offset = Quaternion.forward(rotation) * axes[1].offset + Quaternion.right(rotation) * axes[2].offset + Quaternion.up(rotation) * axes[3].offset

		camera_data.position = camera_data.position + offset * UNIT
	end

	local turn = view_shake.turn()

	if turn then
		camera_data.rotation = Quaternion.multiply(camera_data.rotation, turn)
	end
end)

function view_shake.offset()
	if not axes then
		return Vector3.zero()
	end

	return Vector3(axes[2].offset, axes[1].offset, axes[3].offset) * UNIT
end

local function stop()
	axes = nil
	turn_axes = nil
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = stop