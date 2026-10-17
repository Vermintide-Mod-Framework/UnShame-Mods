local mod = get_mod("unreal_tournament")

-- UT's view shake of a weapon's shot (WeaponFire.ShakeOffsetMag, ShakeOffsetRate and ShakeOffsetTime; PlayerController.ShakeView,
-- ViewShake and CheckShake), for the player on this machine. It moves the camera, and the first person weapon with it: UT adds the
-- shake to where it draws the weapon too (Pawn.CalcDrawOffset adds CameraShake), so the weapon stays where it is on the screen while
-- the world shakes. weapon_skin.lua moves the model by view_shake.offset().
--   view_shake.start(magnitude, rate, time): magnitude and rate are { forward, right, up } in UT units and UT units a second, and time is
--       UT's ShakeOffsetTime. A shake replaces one that is smaller (by the length of its magnitude).
--   view_shake.offset(): how far the shake moves the camera now, in meters along the view's axes: right, forward, up.
-- On each axis the offset moves at the rate until it reaches the most it may be, then turns back. Each time it turns, the most is
-- multiplied by (1 / time - 1), about -0.5 at first, and time goes down by a frame. Once time is down to 1 that axis stops.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")

local UNIT = utils.UT_UNIT

local view_shake = {}

-- The shake now, as three axes of { offset, most, rate, time }, or nil
local axes

function view_shake.start(magnitude, rate, time)
	if axes then
		local current = 0
		local new = 0

		for i = 1, 3 do
			current = current + axes[i].most * axes[i].most
			new = new + magnitude[i] * magnitude[i]
		end

		if new <= current then
			return
		end
	end

	axes = {}

	for i = 1, 3 do
		axes[i] = {
			offset = 0,
			most = magnitude[i],
			rate = rate[i],
			time = time,
		}
	end
end

-- (CheckShake for one axis)
local function update_axis(axis, dt)
	if axis.rate == 0 then
		return
	end

	axis.offset = axis.offset + dt * axis.rate

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

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	if not axes then
		return
	end

	local moving = false

	for i = 1, 3 do
		update_axis(axes[i], dt)
		moving = moving or axes[i].rate ~= 0
	end

	if not moving then
		axes = nil
	end
end

-- (the game moves the camera by its offset here, after its other effects)
mod:hook_safe(CameraManager, "_apply_offset", function (self, camera_data)
	if not axes then
		return
	end

	local rotation = camera_data.rotation
	local offset = Quaternion.forward(rotation) * axes[1].offset + Quaternion.right(rotation) * axes[2].offset + Quaternion.up(rotation) * axes[3].offset

	camera_data.position = camera_data.position + offset * UNIT
end)

function view_shake.offset()
	if not axes then
		return Vector3.zero()
	end

	return Vector3(axes[2].offset, axes[1].offset, axes[3].offset) * UNIT
end

local function stop()
	axes = nil
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = stop

return view_shake
