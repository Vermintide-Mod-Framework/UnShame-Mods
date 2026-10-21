local mod = get_mod("unreal_tournament")

-- The particles of the weapon skins: sprites, discs and beams that add their light to the screen, like UT2004's emitters do.
-- The game's own particle effects can't be made in the SDK, so each particle is a unit with a quad (units/ut/fx/quad) and the material
-- of its texture (units/ut/fx/fx_<texture>, made by tools/asset_conversion/make_fx_assets.py, an unlit material that adds its color).
-- Every frame the particle is moved, turned, scaled and faded. The units are reused.
--
-- A spec is a table. Positions are in meters, colors are 0 to 1, and times are seconds.
--   texture: the name of the texture (shock_core, ...).
--   material: the name of a material of its own, instead of the texture. A mesh's material is given its "age" (how long the effect has
--       been going), which it uses for panning.
--   life: how long the particle lasts.
--   size, growth: the size of the sprite, and how much it changes in a second (a negative growth shrinks it).
--   color: { r, g, b }. intensity: the most light it gives (1 is the texture as it is).
--   attenuation: UT's mAttenKa, how far into its life the particle is brightest (0 is the start). It fades in before that and out
--       after it.
--   fade_in, fade_out: UT's FadeInEndTime and FadeOutStartTime, in seconds. The particle is fully visible from fade_in until fade_out.
--       They are used instead of attenuation.
--   size_by, color_by: functions of how far into its life the particle is (0 to 1) that return its size, and its color { r, g, b }, in
--       place of size and growth, and of color (UT's SizeScale and ColorScale).
--   spin: turns per second. The angle it starts at is random, or spec.angle in degrees (0 keeps a sprite upright on the screen).
--   position: where it is. velocity, drag: where it goes and how fast that slows down (per second).
--   follow: a function that returns where the particle is now, or nothing when it should end.
--   locked: used instead of follow. A function that returns a unit and the particle's position in that unit's frame. For the first
--       person unit the frame is its camera node's (utils.camera_node): at the camera, looking along y. The particle is linked to it and
--       placed in pre_render, so it
--       doesn't trail behind what it follows. It returns nothing when the particle should end. A beam's returns the unit and both of
--       its ends. A locked disc's normal and a locked mesh's rotation are in the unit's frame too.
--   late: the particle is placed in pre_render, after the mod's update, instead of in this file's update, which runs before the
--       weapons' updates. For a follow or track that reads what a weapon moves in its update this frame (the model's muzzle). It has no
--       velocity.
--   delay: seconds before the particle shows.
--   additive: 1 (the default) adds its color to the screen. 0 blends it as the transparency of its texture says (smoke).
--   falloff: how far a light reaches, in meters (only for particles.light).
-- The kinds:
--   particles.sprite(spec): faces the camera.
--   particles.disc(spec): lies on a surface. spec.normal is the way it faces, or a function that returns it each frame.
--   particles.light(spec): a point light (units/ut/fx/light) at spec.position or spec.follow. spec.color is its color, spec.intensity
--       how bright it is, and spec.falloff how far it reaches. It fades like the other particles.
--   particles.beam(spec): goes from spec.from to spec.to. spec.size is how wide it is, and it faces the camera around its length.
--       Instead of the two points, spec.track can be a function that returns from and to, or nothing when the beam should end.
--   particles.strip(spec): a beam along a line of points, as one piece (UT's PT_Beam), spec.size wide, facing the camera about the line
--       at each point. spec.points is a function that returns the points (a list of boxes) and how many there are (up to 65), or
--       nothing when it should end. The texture repeats once between two points.
--   particles.mesh(spec): a mesh (units/ut/fx/coil, sphere, vortex, made by tools/asset_conversion/make_fx_meshes.py) at spec.position.
--       It is turned by spec.rotation (or a function that returns it each frame), or it faces the camera with spec.face_camera (its z axis is the way it faces). It also turns by
--       spec.spin about spec.spin_axis, a vector in the mesh's own axes. spec.scale is a function of how far into its life the mesh
--       is (0 to 1) that returns its scale, either a number or a vector in the mesh's axes. spec.brightness is the same for how bright
--       it is, and replaces fade_in, fade_out and attenuation. spec.unit is the unit. For a mesh with frames, each a unit, spec.unit is the
--       unit of the first frame and spec.frame is a function of how far into its life the mesh is that returns the name of the unit to show.
--       spec.material_by is the same for its material, for a texture whose frames it steps through.
--
-- Vectors can't be kept from one frame to the next, so they are kept in boxes.

local utils = mod.utils

local particles = {}
mod.skin_particles = particles

local UNIT_NAME = "units/ut/fx/quad"
local LIGHT_UNIT_NAME = "units/ut/fx/light"
local MATERIAL_FORMAT = "units/ut/fx/fx_%s"
local MAX_PARTICLES = 800
-- (the sort orders that blended particles take in turn, see add)
local MAX_SORT_ORDER = 255
local blended_count = 0

local active = {}
-- The units that are not in use, grouped by the name of the unit. Each is { unit, world, material, unit_name }.
local free = {}

local function acquire(world, unit_name)
	free[unit_name] = free[unit_name] or {}

	local entry = table.remove(free[unit_name])

	if entry and Unit.alive(entry.unit) and entry.world == world then
		return entry
	end

	return {
		unit = World.spawn_unit(world, unit_name, Vector3(0, 0, 0)),
		unit_name = unit_name,
		world = world,
	}
end

-- The strip (units/ut/fx/beam_strip, tools/asset_conversion/make_fx_meshes.py's make_strip): this many points, each with two corners
-- that move with joints j_<2i> and j_<2i + 1> (from 0)
local STRIP_UNIT_NAME = "units/ut/fx/beam_strip"
local STRIP_POINTS = 65

-- The nodes of a strip's joints, in the order of its corners
local function strip_joints(entry)
	if not entry.joints then
		entry.joints = {}

		for k = 0, 2 * STRIP_POINTS - 1 do
			entry.joints[k + 1] = Unit.node(entry.unit, "j_" .. k)
		end
	end

	return entry.joints
end

local function release(particle)
	if particle.parent then
		-- The parent may be gone already, so check that before unlinking.
		if Unit.alive(particle.parent) then
			World.unlink_unit(particle.world, particle.entry.unit)
		end

		particle.parent = nil
	end

	if particle.kind == "light" then
		Light.set_enabled(particle.entry.light, false)
	else
		Unit.set_unit_visibility(particle.entry.unit, false)
	end

	local pool = free[particle.entry.unit_name]

	pool[#pool + 1] = particle.entry
end

local function add(kind, spec)
	if #active >= MAX_PARTICLES or not Managers.world:has_world("level_world") then
		return
	end

	local world = Managers.world:world("level_world")
	local entry = acquire(world, spec.unit or (kind == "light" and LIGHT_UNIT_NAME) or (kind == "strip" and STRIP_UNIT_NAME) or UNIT_NAME)
	local material

	if kind == "light" then
		entry.light = entry.light or Unit.light(entry.unit, "light")

		Light.set_falloff_start(entry.light, 0)
		Light.set_falloff_end(entry.light, spec.falloff)
		Light.set_enabled(entry.light, false)
	else
		local texture = spec.texture

		-- The smoke texture is a sheet of 16 puffs (made by tools/asset_conversion/split_smoke.py). Each particle shows one of them.
		if texture == "smoke" then
			texture = "smoke_" .. math.random(0, 15)
		end

		material = spec.material or MATERIAL_FORMAT:format(texture)

		if entry.material ~= material then
			entry.material = material

			Unit.set_material(entry.unit, "m_fx", material)
		end

		Unit.set_unit_visibility(entry.unit, false)

		-- Blended particles are drawn in the order they were made, as UT draws an emitter's: sorted by their distance, those close
		-- together traded places from frame to frame, which flickered where they overlap. Added ones look the same in any order.
		if spec.additive == 0 then
			blended_count = blended_count % MAX_SORT_ORDER + 1

			Unit.set_sort_order(entry.unit, blended_count)
		else
			Unit.set_sort_order(entry.unit, 0)
		end
	end

	local particle = {
		age = -(spec.delay or 0),
		angle = spec.angle and math.rad(spec.angle) or math.random() * math.pi * 2,
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
		locked = spec.locked,
		late = spec.late or spec.locked ~= nil,
		face_camera = spec.face_camera,
		frame = spec.frame,
		material_by = spec.material_by,
		material_name = material,
		scale = spec.scale,
		brightness_by = spec.brightness,
		size_by = spec.size_by,
		color_by = spec.color_by,
		growth = spec.growth or 0,
		additive = spec.additive or 1,
		own_material = spec.material ~= nil,
		intensity = spec.intensity or 1,
		track = spec.track,
		points = spec.points,
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

	if type(spec.normal) == "function" then
		particle.normal_by = spec.normal
	elseif spec.normal then
		particle.normal = Vector3Box(spec.normal)
	end

	if type(spec.rotation) == "function" then
		particle.rotation_by = spec.rotation
	elseif spec.rotation then
		particle.rotation = QuaternionBox(spec.rotation)
	end

	if spec.spin_axis then
		particle.spin_axis = Vector3Box(spec.spin_axis)
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

function particles.strip(spec)
	add("strip", spec)
end

function particles.mesh(spec)
	add("mesh", spec)
end

function particles.light(spec)
	add("light", spec)
end

-- Returns how bright a particle is at a fraction of its life. This is UT's attenuation: it brightens until ka and dims from there.
-- The skins use it for effects they draw themselves.
function particles.attenuation(fraction, ka)
	if ka <= 0 then
		return 1 - fraction
	elseif ka >= 1 then
		return fraction
	elseif fraction < ka then
		return fraction / ka
	end

	return (1 - fraction) / (1 - ka)
end

-- Returns how bright a particle is at its age. It uses the times when the particle is fully there and when it starts to go (UT's
-- FadeInEndTime and FadeOutStartTime, which multiply together), or else the attenuation.
local function brightness(particle)
	if not particle.fade_in and not particle.fade_out then
		return math.max(0, particles.attenuation(particle.age / particle.life, particle.attenuation))
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

-- Returns a rotation whose y axis is the way the quad's top points and whose z axis is as close as possible to the way it faces. A
-- beam's quad lies exactly along the beam and turns about it to face the camera.
local function facing(front, top)
	return Quaternion.look(top, front)
end

-- Returns whether the player sees their first person weapon. A locked particle is linked to the first person unit, which the game doesn't
-- hide when it hides the weapons (in a third person view, on a ladder, with /hud), so the particle is hidden whenever the skins' models
-- are (utils.first_person_weapon_shown).
local function first_person_shown()
	local player = Managers.player:local_player()
	local unit = player and player.player_unit
	local first_person_extension = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "first_person_system")

	return first_person_extension and utils.first_person_weapon_shown(first_person_extension) or false
end

local function place(particle, dt, camera_position, camera_rotation)
	local unit = particle.entry.unit
	local fraction = particle.age / particle.life
	local size = particle.size_by and particle.size_by(math.max(0, fraction)) or particle.size and math.max(0, particle.size + particle.growth * particle.age)

	local light = particle.intensity * (particle.brightness_by and particle.brightness_by(fraction) or brightness(particle))
	local position, rotation, scale, locked_to

	if particle.locked then
		local parent, local_position, other_end = particle.locked()

		if not parent then
			particle.age = particle.life

			return
		end

		if particle.parent ~= parent then
			if particle.parent and Unit.alive(particle.parent) then
				World.unlink_unit(particle.world, unit)
			end

			-- (a first person unit's camera node, which the skins' models are linked to too)
			World.link_unit(particle.world, unit, 0, parent, utils.camera_node(parent))

			particle.parent = parent
		end

		-- The position is in the parent's frame, which is the camera's, so the camera is at its origin.
		position = local_position
		locked_to = other_end
		camera_position = Vector3.zero()
		camera_rotation = Quaternion.identity()
	elseif particle.follow then
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

	if particle.kind == "light" then
		Unit.set_local_position(unit, 0, position)
		Light.set_color(particle.entry.light, Vector3(particle.color[1], particle.color[2], particle.color[3]))
		Light.set_intensity(particle.entry.light, light)
		Light.set_enabled(particle.entry.light, true)
		World.update_unit(particle.world, unit)

		return
	end

	if particle.kind == "mesh" then
		-- A mesh is placed at its position and turned as its rotation says, plus its spin about its axis. It is scaled by its scale
		-- function for how far into its life it is, and it shows the frame that the frame function names.
		local axis = particle.spin_axis and particle.spin_axis:unbox() or Vector3(0, 0, 1)
		-- A mesh that always faces the camera, like UT's bAlwaysFaceCamera, has its z axis pointing the way it faces, as a quad does.
		local base = particle.face_camera and facing(-Quaternion.forward(camera_rotation), Quaternion.up(camera_rotation)) or particle.rotation_by and particle.rotation_by() or particle.rotation:unbox()

		rotation = Quaternion.multiply(base, Quaternion.axis_angle(axis, particle.angle + particle.spin * particle.age))
		scale = particle.scale(fraction)

		if type(scale) == "number" then
			scale = Vector3(scale, scale, scale)
		end

		if particle.frame then
			local shown = particle.frame(fraction)

			-- Each frame is a unit of its own, so a new frame puts the unit of the last one back in the pool and takes the unit of the new
			-- one (the goop has over a hundred frames; hiding and showing the meshes of one unit did not draw anything).
			if shown ~= particle.shown then
				Unit.set_unit_visibility(particle.entry.unit, false)

				local pool = free[particle.entry.unit_name]

				pool[#pool + 1] = particle.entry

				local entry = acquire(particle.world, shown)

				if entry.material ~= particle.material_name then
					entry.material = particle.material_name

					Unit.set_material(entry.unit, "m_fx", particle.material_name)
				end

				particle.entry = entry
				unit = entry.unit
				particle.shown = shown
			end
		end

		if particle.material_by then
			local material = particle.material_by(fraction)

			if material ~= particle.entry.material then
				particle.entry.material = material
				particle.material_name = material

				Unit.set_material(unit, "m_fx", material)
			end
		end
	elseif particle.kind == "beam" then
		local from, to

		if particle.locked then
			from, to = position, locked_to
		elseif particle.track then
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
	elseif particle.kind == "strip" then
		local points, count = particle.points()

		if not points or count < 2 then
			particle.age = particle.life

			return
		end

		count = math.min(count, STRIP_POINTS)
		position = points[1]:unbox()
		rotation = Quaternion.identity()
		scale = Vector3(1, 1, 1)

		local joints = strip_joints(particle.entry)
		local half = size * 0.5

		-- Each point's two corners are across the line there, half the width to each side, turned about the line to face the camera
		for i = 1, STRIP_POINTS do
			local k = math.min(i, count)
			local point = points[k]:unbox()
			local before = points[math.max(k - 1, 1)]:unbox()
			local after = points[math.min(k + 1, count)]:unbox()
			local across = Vector3.cross(after - before, camera_position - point)

			if Vector3.length(across) > 0.000001 then
				across = Vector3.normalize(across) * half
			end

			-- (the points past the last are all at the last, so the rest of the strip has no size)
			if i > count then
				across = Vector3.zero()
			end

			Unit.set_local_position(unit, joints[2 * i - 1], point - across - position)
			Unit.set_local_position(unit, joints[2 * i], point + across - position)
		end
	elseif particle.kind == "disc" then
		local normal = particle.normal_by and particle.normal_by() or particle.normal:unbox()
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
	local color = particle.color_by and particle.color_by(math.max(0, fraction)) or particle.color

	Unit.set_vector3_for_materials(unit, "tint", Vector3(color[1], color[2], color[3]))
	Unit.set_scalar_for_materials(unit, "intensity", light)
	Unit.set_scalar_for_materials(unit, "additive", particle.additive)

	if particle.own_material then
		-- A material of its own pans its textures by how long the effect has been going.
		Unit.set_scalar_for_materials(unit, "age", particle.age)
	end

	Unit.set_unit_visibility(unit, not particle.locked or first_person_shown())
	World.update_unit(particle.world, unit)
end

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	if #active == 0 then
		return
	end

	local camera_position, camera_rotation = utils.camera_pose()

	for i = #active, 1, -1 do
		local particle = active[i]

		particle.age = particle.age + dt

		if particle.age >= particle.life or not camera_position then
			release(particle)
			table.remove(active, i)
		elseif particle.age >= 0 then
			-- Linked and late particles are placed in pre_render, after the skin has moved its model this frame.
			if not particle.late then
				place(particle, dt, camera_position, camera_rotation)
			end

			if particle.age >= particle.life then
				release(particle)
				table.remove(active, i)
			end
		end
	end
end

mod.pre_render_callbacks.skin_particles = function ()
	local camera_position, camera_rotation = utils.camera_pose()

	if not camera_position then
		return
	end

	for _, particle in ipairs(active) do
		if particle.late and particle.age >= 0 and particle.age < particle.life then
			place(particle, 0, camera_position, camera_rotation)
		end
	end
end

-- Lets go of everything before the level's world is taken down.
local function clear()
	for i = #active, 1, -1 do
		table.remove(active, i)
	end

	for _, pool in pairs(free) do
		for i = #pool, 1, -1 do
			local entry = pool[i]

			if Unit.alive(entry.unit) then
				World.destroy_unit(entry.world, entry.unit)
			end

			pool[i] = nil
		end
	end
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	-- The units in use are destroyed too, because the particles that are showing are in the world that goes away.
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