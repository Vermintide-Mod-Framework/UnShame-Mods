local mod = get_mod("unreal_tournament")

-- Local test of a converted model: the Shock Rifle is held in front of you as soon as there is a player to hold it, linked
-- to the game's own first person unit (like its weapons are), and the game's weapon and arms are hidden.
--
-- It is placed so that it lands on the screen where UT2004 draws it (small weapons off). UT draws the mesh, moved by the
-- root bone of its animation, at DrawScale, tilted by PlayerViewPivot, at PlayerViewOffset scaled by 90 / DisplayFOV
-- (ShockRifle.uc, Pawn.CalcDrawOffset), and projects it with the field of view it is seen at. A point at (right, forward,
-- up) in UT's view lands in the same place of the screen in this game's view, with its field of view, at
-- (c * right, forward, c * up) * k, where c is the ratio of the tangents of the half field of views across the screen and
-- k is any distance scale: the gun is wider and taller across than it is long.
--
-- The animations are the ones of UT (Pickup when it comes up, Idle, Fire on the left button, AltFire on the right one,
-- PutDown). The chamber is animated as UT does it, the gel flowing (a flipbook of the texture) and glowing back in after
-- a shot (ShockRifle.RenderOverlays).
--
-- /shock [scale] [yaw] [pitch] [right] [forward] [up] [length] [width] [height] adjusts it from there (a "-" keeps a value),
-- /shock pickup, fire, alt, putdown plays an animation, /shock off puts it down and removes it until the next /shock.
-- Keys: mouse wheel = forward, arrows = right and up, page up / page down = scale, home / end = yaw, insert / delete =
-- pitch, numpad 7 / numpad 9 = length, numpad 4 / numpad 6 = width, numpad 1 / numpad 3 = height
local animations = mod:dofile("scripts/mods/unreal_tournament/asset_test_animations")
local UNIT_NAME = "units/ut/shock_rifle"
local HIDE_REASON = "ut_asset_test"
local GEL_MATERIAL_FORMAT = "units/ut/shock_rifle_power_%02d"
local GEL_FRAMES = 60
local GEL_LOOP_SECONDS = 10
local CHAMBER_OPACITY = 0.6
local FIRE_RATE = 0.7 -- seconds, ShockBeamFire and ShockProjFire
-- The field of view UT projects the weapon with, horizontal, fitted to a screenshot of UT2004 (the features of the model
-- land within about 10 pixels with it)
local UT_FIELD_OF_VIEW = math.rad(86.5)
-- ShockRifle.uc
local DRAW_SCALE = 0.7
local VIEW_OFFSET_FORWARD = 4 * 90 / 70
local VIEW_OFFSET_RIGHT = 8 * 90 / 70
local VIEW_OFFSET_UP = -2 * 90 / 70
local VIEW_PIVOT_PITCH = -1000 / 65536 * 360
-- The model is converted at this many meters per UT unit (psk2bsi), the distance scale is meters of forward per UT unit
local MODEL_METERS_PER_UNIT = 0.0125
local METERS_PER_UNIT = 0.01
local hold = {
	scale = 1,
	yaw = 0,
	pitch = VIEW_PIVOT_PITCH,
	right = 0,
	forward = 0,
	up = 0,
	length = 1,
	width = 1,
	height = 1,
}
local ORDER = {
	"scale",
	"yaw",
	"pitch",
	"right",
	"forward",
	"up",
	"length",
	"width",
	"height",
}
local COMMANDS = {
	pickup = "Pickup",
	fire = "Fire",
	alt = "AltFire",
	putdown = "PutDown",
}
local WHEEL_STEP = 0.01 -- meters of forward per wheel notch
local ARROW_SPEED = 0.2 -- meters per second
local SCALE_SPEED = 0.5 -- fraction of the scale per second
local ANGLE_SPEED = 30 -- degrees per second
local PRINT_INTERVAL = 0.3 -- seconds
local SCROLL_KEYS = {
	wield_scroll = true,
	wield_next = true,
	wield_prev = true,
}
local shown
local disabled = false
local changed_since_print, print_timer = false, 0
local buttons_down = {}

-- The wheel moves the gun, it doesn't change weapons
for _, name in ipairs({
	"get",
	"get_buffer",
}) do
	mod:hook("PlayerInputExtension", name, function (func, self, input_key, ...)
		if shown and SCROLL_KEYS[input_key] then
			return nil
		end

		return func(self, input_key, ...)
	end)
end

local function pressed(name)
	return Keyboard.button(Keyboard.button_index(name)) > 0.5 and 1 or 0
end

local function button_pressed(name)
	local down = Mouse.button(Mouse.button_index(name)) > 0.5
	local was_down = buttons_down[name]

	buttons_down[name] = down

	return down and not was_down
end

local function print_hold()
	mod:echo("shock: scale %.3f, yaw %.1f, pitch %.1f, right %.3f, forward %.3f, up %.3f, length %.3f, width %.3f, height %.3f", hold.scale, hold.yaw, hold.pitch, hold.right, hold.forward, hold.up, hold.length, hold.width, hold.height)
end

local function local_first_person()
	local player = Managers.player and Managers.player:local_player()
	local owner = player and player.player_unit

	return owner and Unit.alive(owner) and ScriptUnit.has_extension(owner, "first_person_system")
end

local function hide_game_weapon(fp)
	fp:hide_weapons(HIDE_REASON, true)
	Unit.set_unit_visibility(fp.first_person_attachment_unit, false)
end

local function show_game_weapon(fp)
	fp:unhide_weapons(HIDE_REASON)
	Unit.set_unit_visibility(fp.first_person_attachment_unit, fp:first_person_mode_active())
end

local function clear()
	if not shown then
		return
	end

	local fp = local_first_person()

	if fp then
		show_game_weapon(fp)
	end

	if Unit.alive(shown.unit) then
		AttachmentUtils.unlink(shown.world, shown.unit)
		World.destroy_unit(shown.world, shown.unit)
	end

	shown = nil
end

local function play(name)
	shown.animation = name
	shown.animation_time = 0

	if name == "Fire" or name == "AltFire" then
		shown.cooldown_end = Managers.time:time("game") + FIRE_RATE
	end
end

local function show()
	local fp = local_first_person()

	if not fp or not Managers.world:has_world("level_world") then
		return
	end

	local world = Managers.world:world("level_world")
	local unit = World.spawn_unit(world, UNIT_NAME, Vector3(0, 0, 0))

	-- The root of the first person unit is where the camera is, and turns with it
	AttachmentUtils.link(world, fp.first_person_unit, unit, {
		{
			source = 0,
			target = 0,
		},
	})

	shown = {
		world = world,
		unit = unit,
		gel_time = 0,
		cooldown_end = 0,
	}

	play("Pickup")
end

mod:command("shock", "[scale] [yaw] [pitch] [right] [forward] [up] [length] [width] [height] | pickup, fire, alt, putdown | off - the test model; - keeps a value", function (...)
	local args = {
		...
	}

	if args[1] == "off" then
		if shown then
			shown.closing = true

			play("PutDown")
		end

		disabled = true

		return
	end

	disabled = false

	if COMMANDS[args[1]] then
		if not shown then
			show()
		end

		if shown then
			play(COMMANDS[args[1]])
		end

		return
	end

	for i, name in ipairs(ORDER) do
		local value = tonumber(args[i])

		if value then
			hold[name] = value
		end
	end

	print_hold()

	if not shown then
		show()
	end
end)

-- The transform of the animation at a time: a rotation and a move (in UT units) of the mesh, between the two frames
local function animation_pose(shown)
	local animation = animations[shown.animation]
	local frames = animation.frames
	local count = #frames
	local position = shown.animation_time * animation.rate
	local looping = shown.animation == "Idle"

	if position >= count - 1 and not looping then
		position = count - 1
	end

	local index = math.floor(position)
	local fraction = position - index
	local first = frames[index % count + 1]
	local second = frames[(looping and (index + 1) % count or math.min(index + 1, count - 1)) + 1]
	local rotation = Quaternion.lerp(Quaternion.from_elements(first[1], first[2], first[3], first[4]), Quaternion.from_elements(second[1], second[2], second[3], second[4]), fraction)

	return rotation, first[5] + (second[5] - first[5]) * fraction, first[6] + (second[6] - first[6]) * fraction, first[7] + (second[7] - first[7]) * fraction
end

-- Something finished playing: back to Idle, or the end of it if it was put down
local function advance_animation(dt)
	shown.animation_time = shown.animation_time + dt

	local animation = animations[shown.animation]
	local duration = #animation.frames / animation.rate

	if shown.animation == "Idle" then
		shown.animation_time = shown.animation_time % duration
	elseif shown.animation_time >= duration then
		if shown.animation == "PutDown" then
			clear()
		else
			play("Idle")
		end
	end
end

local function update_chamber(dt)
	local unit = shown.unit

	shown.gel_time = (shown.gel_time + dt) % GEL_LOOP_SECONDS

	local frame = math.floor(shown.gel_time / GEL_LOOP_SECONDS * GEL_FRAMES) % GEL_FRAMES

	if frame ~= shown.gel_frame then
		shown.gel_frame = frame

		Unit.set_material(unit, "m_power", string.format(GEL_MATERIAL_FORMAT, frame))
	end

	-- (ShockRifle.RenderOverlays: after a shot the glow comes back with the time until the next one)
	local charge = 1 - math.max(0, math.min(1, (shown.cooldown_end - Managers.time:time("game")) / FIRE_RATE))

	Material.set_scalar(Mesh.material(Unit.mesh(unit, "g_shock_1"), "m_power"), "opacity", CHAMBER_OPACITY * charge)
end

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	local fp = local_first_person()

	if not fp then
		if shown then
			clear()
		end

		return
	end

	if not shown then
		if not disabled then
			show()
		end

		return
	end

	if Window.has_focus() then
		local wheel = Vector3.y(Mouse.axis(Mouse.axis_index("wheel")))
		local sideways = pressed("right") - pressed("left")
		local vertical = pressed("up") - pressed("down")
		local grow = pressed("page up") - pressed("page down")
		local turn = pressed("home") - pressed("end")
		local tilt = pressed("insert") - pressed("delete")
		local stretch = pressed("numpad 9") - pressed("numpad 7")
		local widen = pressed("numpad 6") - pressed("numpad 4")
		local heighten = pressed("numpad 3") - pressed("numpad 1")

		if wheel ~= 0 or sideways ~= 0 or vertical ~= 0 or grow ~= 0 or turn ~= 0 or tilt ~= 0 or stretch ~= 0 or widen ~= 0 or heighten ~= 0 then
			hold.forward = hold.forward + wheel * WHEEL_STEP
			hold.right = hold.right + sideways * ARROW_SPEED * dt
			hold.up = hold.up + vertical * ARROW_SPEED * dt
			hold.scale = math.max(0.01, hold.scale * (1 + grow * SCALE_SPEED * dt))
			hold.yaw = hold.yaw + turn * ANGLE_SPEED * dt
			hold.pitch = hold.pitch + tilt * ANGLE_SPEED * dt
			hold.length = math.max(0.1, hold.length * (1 + stretch * SCALE_SPEED * dt))
			hold.width = math.max(0.1, hold.width * (1 + widen * SCALE_SPEED * dt))
			hold.height = math.max(0.1, hold.height * (1 + heighten * SCALE_SPEED * dt))
			changed_since_print = true
		end

		local fire = button_pressed("left")
		local alt_fire = button_pressed("right")

		if not shown.closing and shown.animation ~= "Pickup" then
			if fire then
				play("Fire")
			elseif alt_fire then
				play("AltFire")
			end
		end
	end

	print_timer = print_timer - dt

	if changed_since_print and print_timer <= 0 then
		print_hold()

		changed_since_print, print_timer = false, PRINT_INTERVAL
	end

	advance_animation(dt)

	if not shown then
		return
	end

	-- (the game shows its arms again on its own now and then)
	hide_game_weapon(fp)
	update_chamber(dt)

	-- Across the screen, how much further out this game's view sees than UT's does at the weapon's field of view
	local resolution_width, resolution_height = Application.resolution()
	local tangent_vertical = math.tan(Camera.vertical_fov(fp:camera()) / 2)
	local across = tangent_vertical * resolution_width / resolution_height / math.tan(UT_FIELD_OF_VIEW / 2)
	local forward_scale = hold.scale * METERS_PER_UNIT
	local across_scale = forward_scale * across

	-- The animation's move of the mesh, tilted by the pivot, as everything of the mesh is (about the right axis)
	local animation_rotation, move_right, move_forward, move_up = animation_pose(shown)
	local pitch = math.rad(hold.pitch)
	local tilted_forward = move_forward * math.cos(pitch) - move_up * math.sin(pitch)
	local tilted_up = move_forward * math.sin(pitch) + move_up * math.cos(pitch)
	local position = Vector3(
		across_scale * (DRAW_SCALE * move_right + VIEW_OFFSET_RIGHT) + hold.right,
		forward_scale * (DRAW_SCALE * tilted_forward + VIEW_OFFSET_FORWARD) + hold.forward,
		across_scale * (DRAW_SCALE * tilted_up + VIEW_OFFSET_UP) + hold.up
	)
	local size = DRAW_SCALE / MODEL_METERS_PER_UNIT
	local pivoted = Quaternion.axis_angle(Vector3(1, 0, 0), pitch)
	local turned = Quaternion.multiply(pivoted, Quaternion.multiply(Quaternion.axis_angle(Vector3.up(), math.rad(hold.yaw)), animation_rotation))

	-- (relative to the node it is linked to)
	Unit.set_local_position(shown.unit, 0, position)
	Unit.set_local_rotation(shown.unit, 0, turned)
	Unit.set_local_scale(shown.unit, 0, Vector3(size * across_scale * hold.width, size * forward_scale * hold.length, size * across_scale * hold.height))
	World.update_unit(shown.world, shown.unit)
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = clear
mod.unload_callbacks[#mod.unload_callbacks + 1] = clear
