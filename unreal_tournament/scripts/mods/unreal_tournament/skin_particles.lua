local mod = get_mod("unreal_tournament")

-- The particles of the weapon skins: sprites, discs and beams that add their light to the screen, like UT2004's emitters do.
-- The game's own particle effects can't be made in the SDK, so each particle is a unit with a quad (units/ut/fx/quad) and the
-- material of its texture (units/ut/fx/fx_<texture>, made by tools/asset_conversion/make_fx_assets.py, an unlit material that
-- adds its color), moved, turned, scaled and faded every frame. The units are reused.
--
-- A spec is a table (positions are in meters, the colors are 0 to 1, the times are seconds):
--   texture: the name of the texture (shock_core, ...)
--   life: how long it lasts
--   size, growth: the size of the sprite and how much it changes in a second (a negative growth shrinks it)
--   color: { r, g, b }, intensity: the most light it gives (1 is the texture as it is)
--   attenuation: UT's mAttenKa: how far into its life it is the brightest (0 is at the start), it fades in before that and
--       out after it
--   fade_in, fade_out: UT's FadeInEndTime and FadeOutStartTime, in seconds: it is all there from fade_in until fade_out (used
--       instead of the attenuation)
--   spin: turns per second (the angle it starts at is random)
--   position: where it is; velocity, drag: where it goes and how fast that slows (per second); follow: a function that gives
--       where it is now, nothing when it is to end
--   delay: seconds before it shows
--   additive: 1 (the default) adds its color to the screen, 0 blends it as the transparency of its texture says (smoke)
-- The kinds:
--   particles.sprite(spec): faces the camera
--   particles.disc(spec): lies on a surface, spec.normal is the way it faces
--   particles.beam(spec): from spec.from to spec.to, spec.size is how wide it is, and it faces the camera around its length;
--       spec.track, a function that gives from and to (nothing when it is to end), instead of the two points
--
-- (Vectors can't be kept from one frame to the next, so they are kept in boxes.)

local particles = {}

local UNIT_NAME = "units/ut/fx/quad"
local MATERIAL_FORMAT = "units/ut/fx/fx_%s"
local MAX_PARTICLES = 400

local active = {}
local free = {} -- units that are not used, { unit, world, material }

local function camera_pose()
	local player = Managers.player and Managers.player:local_player()
	local camera_manager = Managers.state and Managers.state.camera

	if not player or not camera_manager or not camera_manager:has_viewport(player.viewport_name) then
		return
	end

	return camera_manager:camera_position(player.viewport_name), camera_manager:camera_rotation(player.viewport_name)
end

local function acquire(world)
	local entry = table.remove(free)

	if entry and Unit.alive(entry.unit) and entry.world == world then
		return entry
	end

	return {
		unit = World.spawn_unit(world, UNIT_NAME, Vector3(0, 0, 0)),
		world = world,
	}
end

local function release(particle)
	Unit.set_unit_visibility(particle.entry.unit, false)

	free[#free + 1] = particle.entry
end

local function add(kind, spec)
	if #active >= MAX_PARTICLES or not Managers.world:has_world("level_world") then
		return
	end

	local world = Managers.world:world("level_world")
	local entry = acquire(world)
	local material = MATERIAL_FORMAT:format(spec.texture)

	if entry.material ~= material then
		entry.material = material

		Unit.set_material(entry.unit, "m_fx", material)
	end

	Unit.set_unit_visibility(entry.unit, false)

	local particle = {
		age = -(spec.delay or 0),
		angle = math.random() * math.pi * 2,
		attenuation = spec.attenuation or 0,
		color = spec.color or {
			1,
			1,
			1,
		},
		drag = spec.drag or 0,
		entry = entry,
		fade_in = spec.fade_in,
		fade_out = spec.fade_out,
		follow = spec.follow,
		growth = spec.growth or 0,
		additive = spec.additive or 1,
		intensity = spec.intensity or 1,
		track = spec.track,
		kind = kind,
		life = spec.life,
		size = spec.size,
		spin = (spec.spin or 0) * math.pi * 2,
		world = world,
	}

	if spec.position then
		particle.position = Vector3Box(spec.position)
	end

	if spec.velocity then
		particle.velocity = Vector3Box(spec.velocity)
	end

	if spec.normal then
		particle.normal = Vector3Box(spec.normal)
	end

	if spec.from then
		particle.from = Vector3Box(spec.from)
		particle.to = Vector3Box(spec.to)
	end

	active[#active + 1] = particle
end

function particles.sprite(spec)
	add("sprite", spec)
end

function particles.disc(spec)
	add("disc", spec)
end

function particles.beam(spec)
	add("beam", spec)
end

-- How bright a particle is a fraction of its life in (UT's attenuation: it comes up until ka, and goes down from there)
local function fade(fraction, ka)
	if ka <= 0 then
		return 1 - fraction
	elseif ka >= 1 then
		return fraction
	elseif fraction < ka then
		return fraction / ka
	end

	return (1 - fraction) / (1 - ka)
end

-- How bright a particle is at its age: by when it is all there and when it starts to go (UT's FadeInEndTime and
-- FadeOutStartTime, which together multiply), or by the attenuation
local function brightness(particle)
	if not particle.fade_in and not particle.fade_out then
		return math.max(0, fade(particle.age / particle.life, particle.attenuation))
	end

	local result = 1

	if particle.fade_in and particle.age < particle.fade_in then
		result = particle.age / particle.fade_in
	end

	if particle.fade_out and particle.age > particle.fade_out then
		result = result * (particle.life - particle.age) / (particle.life - particle.fade_out)
	end

	return math.max(0, result)
end

-- A rotation whose z axis is the way the quad faces, and whose y axis is the way its top is (as near as can be)
local function facing(front, top)
	return Quaternion.look(top, front)
end

local function place(particle, dt, camera_position, camera_rotation)
	local unit = particle.entry.unit
	local size = math.max(0, particle.size + particle.growth * particle.age)
	local light = particle.intensity * brightness(particle)
	local position, rotation, scale

	if particle.follow then
		position = particle.follow()

		if not position then
			particle.age = particle.life

			return
		end

		particle.position = Vector3Box(position)
	elseif particle.position then
		position = particle.position:unbox()

		if particle.velocity then
			local velocity = particle.velocity:unbox()

			position = position + velocity * dt

			particle.position:store(position)
			particle.velocity:store(velocity * math.max(0, 1 - particle.drag * dt))
		end
	end

	if particle.kind == "beam" then
		local from, to

		if particle.track then
			from, to = particle.track()

			if not from then
				particle.age = particle.life

				return
			end
		else
			from, to = particle.from:unbox(), particle.to:unbox()
		end

		local along = to - from
		local length = Vector3.length(along)

		position = (from + to) * 0.5
		rotation = facing(camera_position - position, along)
		scale = Vector3(size, math.max(length, 0.001), 1)
	elseif particle.kind == "disc" then
		local normal = particle.normal:unbox()
		local side = Vector3.cross(normal, Vector3.up())

		if Vector3.length(side) < 0.1 then
			side = Vector3.cross(normal, Vector3.right())
		end

		rotation = Quaternion.multiply(facing(normal, Vector3.cross(side, normal)), Quaternion.axis_angle(Vector3(0, 0, 1), particle.angle + particle.spin * particle.age))
		scale = Vector3(size, size, 1)
	else
		rotation = Quaternion.multiply(facing(-Quaternion.forward(camera_rotation), Quaternion.up(camera_rotation)), Quaternion.axis_angle(Vector3(0, 0, 1), particle.angle + particle.spin * particle.age))
		scale = Vector3(size, size, 1)
	end

	Unit.set_local_position(unit, 0, position)
	Unit.set_local_rotation(unit, 0, rotation)
	Unit.set_local_scale(unit, 0, scale)
	Unit.set_vector3_for_materials(unit, "tint", Vector3(particle.color[1], particle.color[2], particle.color[3]))
	Unit.set_scalar_for_materials(unit, "intensity", light)
	Unit.set_scalar_for_materials(unit, "additive", particle.additive)
	Unit.set_unit_visibility(unit, true)
	World.update_unit(particle.world, unit)
end

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	if #active == 0 then
		return
	end

	local camera_position, camera_rotation = camera_pose()

	for i = #active, 1, -1 do
		local particle = active[i]

		particle.age = particle.age + dt

		if particle.age >= particle.life or not camera_position then
			release(particle)
			table.remove(active, i)
		elseif particle.age >= 0 then
			place(particle, dt, camera_position, camera_rotation)

			if particle.age >= particle.life then
				release(particle)
				table.remove(active, i)
			end
		end
	end
end

-- Everything is let go of before the level's world is taken down
local function clear()
	for i = #active, 1, -1 do
		table.remove(active, i)
	end

	for i = #free, 1, -1 do
		local entry = free[i]

		if Unit.alive(entry.unit) then
			World.destroy_unit(entry.world, entry.unit)
		end

		free[i] = nil
	end
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	-- (what is in use is destroyed as well: the units of the particles that are showing are in the world that goes)
	for i = #active, 1, -1 do
		local entry = active[i].entry

		if Unit.alive(entry.unit) then
			World.destroy_unit(entry.world, entry.unit)
		end
	end

	clear()
end

mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
	for i = #active, 1, -1 do
		local entry = active[i].entry

		if Unit.alive(entry.unit) then
			World.destroy_unit(entry.world, entry.unit)
		end
	end

	clear()
end

return particles
