local mod = get_mod("unreal_tournament")

-- The effects of the Shock Rifle's skin: what UT2004's own shows (XEffects: ShockMuzFlash, ShockBeamEffect, ShockImpact*,
-- ShockBall, ShockExplosionCore, ShockCombo*), drawn with the particles of skin_particles.lua. UT's sizes, speeds and times are
-- used as they are, in UT units; the textures are the game's own, converted (tools/asset_conversion/make_fx_assets.py).
-- What is not done: the meshes of the effects (the coil of the beam, the dark and vortex spheres of the combo), which only
-- add shape to what the sprites show.
--
-- The functions are called by shock_rifle_skin.lua, which knows when and where.

local particles = mod.skin_particles

local CONFIG = {
	-- How many meters a UT unit is in the world (the same as the Shock Rifle's own, a player is 88 units high)
	meters_per_unit = 0.02,
	-- ShockBeamEffect: the beam is made of pieces of mRegenDist, of width mSizeRange, it lasts LifeSpan
	beam_piece_length = 150,
	beam_width = 36,
	beam_life = 0.75,
	beam_attenuation = 0.1,
	-- ShockImpactFlare, ShockImpactRing, ShockExplosionCore, ShockImpactScorch
	impact_flare_count = 3,
	impact_flare_size = {
		50,
		60,
	},
	impact_flare_growth = 100,
	impact_flare_life = 0.5,
	impact_ring_size = 30,
	impact_ring_growth = 260,
	impact_ring_life = 0.5,
	impact_core_size = 40,
	impact_core_growth = 100,
	impact_core_life = 1,
	impact_core_offset = 8, -- units from the surface
	scorch_size = 64,
	scorch_life = 2.2,
	-- ShockMuzFlash (the sparkle of the beam), ShockBeamMuzFlash, ShockProjMuzFlash (the flash of the ball)
	muzzle_sparkle_size = 50,
	muzzle_sparkle_growth = 50,
	muzzle_sparkle_life = 0.5,
	muzzle_flash_size = 60,
	muzzle_flash_life = 0.14,
	ball_flash_count = 3,
	ball_flash_size = {
		40,
		60,
	},
	ball_flash_life = 0.2,
	-- ShockBall: the emitters of the ball: the core, the flares, and the sparks that gather on it
	ball_sprite_size = 90, -- ShockProjectile: DrawScale 0.7 of the 128 units of the texture
	ball_sprite_life = 10, -- its LifeSpan
	ball_sprite_layers = 3,
	-- (FadeInEndTime and FadeOutStartTime of each: it is all there between, and the next core comes as one ends)
	ball_core_size = 55,
	ball_core_life = 0.35,
	ball_core_interval = 0.35,
	ball_core_fade_in = 0.05,
	ball_core_fade_out = 0.32,
	ball_flare_size = 60,
	ball_flare_life = 0.4,
	ball_flare_interval = 0.5,
	ball_flare_fade_in = 0.25,
	ball_flare_fade_out = 0.2,
	ball_spark_size = 4.5,
	ball_spark_life = 0.35,
	ball_spark_fade_in = 0.1,
	ball_spark_fade_out = 0.3,
	ball_spark_interval = 0.025,
	ball_spark_distance = 25, -- units
	-- ShockProjectile's explosion: ShockExplosionCore
	explosion_core_size = 40,
	explosion_core_growth = 100,
	explosion_core_life = 1,
	-- ShockCombo and the effects it makes
	combo_core_size = 50,
	combo_core_growth = 400,
	combo_core_life = 1.5,
	combo_ring_growth = 500,
	combo_ring_life = 0.5,
	combo_ring_attenuation = 0.4,
	combo_flare_count = 5,
	combo_flare_size = 85,
	combo_flare_growth = 260,
	combo_flare_life = 0.5,
	combo_flare_rate = 5, -- a second
	combo_flare_time = 0.9, -- how long they come, then the two big ones
	combo_big_flare_size = 150,
	combo_big_flare_growth = -500,
	combo_big_flare_life = 0.3,
	combo_flash_size = 570,
	combo_flash_growth = 500,
	combo_flash_life = 0.25,
	combo_wiggle_count = 25,
	combo_wiggle_size = 120,
	combo_wiggle_speed = 300,
	combo_wiggle_life = 0.75,
	-- ShockBeamCoil: pieces of the coil mesh (30 long, units/ut/fx/coil) along the beam every coil_piece_length, scaled coil_length_scale along
	-- it and coil_radius_scale across times a size of coil_size (mSizeRange), turning about the beam coil_spin turns a second (mSpinRange 32000
	-- of 65536), as dim as mColorRange says (50 of 255, made a little brighter here), for coil_life
	coil_piece_length = 90,
	coil_length_scale = 3,
	coil_radius_scale = 15,
	coil_size = {
		0.3,
		0.6,
	},
	coil_spin = 32000 / 65536,
	coil_color = 0.3,
	coil_life = 0.75,
	coil_max_pieces = 30,
	-- ShockComboSphereDark and ShockComboVortex (MeshEffects, they last mesh_life, with the interpolations of their scale and of how much of
	-- them there is that UT gives them) and ComboDecal (the mark on the floor, as big as combo_scorch_size, if there is a floor within
	-- combo_scorch_reach below the combo)
	mesh_life = 1,
	sphere_scale = 2.7, -- how many times the mesh (EffectsSphere144, 47 units in radius) is the sphere of UT (Editor.TexPropSphere, 128)
	sphere_scale_interp = {
		start = 0.1,
		mid = 0.8,
		finish = 0,
		in_time = 0.3,
		out_time = 0.3,
		in_style = "inv_exp",
		out_style = "inv_exp",
	},
	sphere_fade_interp = {
		start = 0,
		mid = 1,
		finish = 0,
		in_time = 0.15,
		out_time = 0.75,
		in_style = "linear",
		out_style = "linear",
	},
	sphere_intensity = 0.8,
	sphere_color = {
		0.55,
		0.45,
		1,
	},
	vortex_scale_interp = {
		start = 0.4,
		mid = 1.6,
		finish = 0.2,
		in_time = 0.4,
		out_time = 0.4,
		in_style = "inv_exp",
		out_style = "inv_exp",
	},
	vortex_fade_interp = {
		start = 0,
		mid = 1,
		finish = 0,
		in_time = 0,
		out_time = 0.9,
		in_style = "linear",
		out_style = "linear",
	},
	vortex_frames = 56, -- the frames of ShockVortexMesh, and how many of them the unit has (every vortex_frame_step)
	vortex_frame_step = 3,
	vortex_color = {
		0.7,
		0.55,
		1,
	},
	combo_scorch_size = 260,
	combo_scorch_life = 6,
	combo_scorch_reach = 120,
	-- Turns a second of what spins (UT's mSpinRange is in the units of its own)
	spin = 0.3,
}

local UNIT = CONFIG.meters_per_unit

local fx = {}

-- (the colors the textures are not as they are)
local WHITE = {
	1,
	1,
	1,
}
local PURPLE = {
	0.8,
	0.55,
	1,
}

local function between(range)
	return range[1] + (range[2] - range[1]) * math.random()
end

local function random_direction()
	local direction = Vector3(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1)

	if Vector3.length(direction) < 0.001 then
		return Vector3.up()
	end

	return Vector3.normalize(direction)
end

local function random_spin()
	return (math.random() * 2 - 1) * CONFIG.spin
end

-- UT's MeshEffect.InterpInterp: a value that goes from start to mid over in_time of the life of the effect (0 to 1), stays there until
-- out_time, and goes to finish from there, by the style of each
local function interpolate(interp, t)
	local function style_value(style, u, from, to, going_in)
		if style == "linear" then
			return from + (to - from) * u
		elseif style == "exp" then
			u = going_in and u * u * u or 1 - (1 - u) * (1 - u) * (1 - u)
		elseif style == "inv_exp" then
			u = going_in and 1 - (1 - u) * (1 - u) * (1 - u) or u * u * u
		elseif style == "s" then
			u = u * u * (3 - 2 * u)
		else
			return going_in and from or to
		end

		return from + (to - from) * u
	end

	if t < interp.in_time then
		return style_value(interp.in_style, t / interp.in_time, interp.start, interp.mid, true)
	elseif t <= interp.out_time then
		return interp.mid
	end

	return style_value(interp.out_style, (t - interp.out_time) / (1 - interp.out_time), interp.mid, interp.finish, false)
end

local function random_rotation()
	return Quaternion.axis_angle(random_direction(), math.random() * math.pi * 2)
end

-- Muzzle flashes: follow gives where the muzzle is, scale how many meters a UT unit is there (the model of the gun is drawn
-- at a scale of its own)

function fx.beam_muzzle_flash(follow, scale)
	particles.sprite({
		attenuation = 0,
		color = WHITE,
		follow = follow,
		growth = CONFIG.muzzle_sparkle_growth * scale,
		life = CONFIG.muzzle_sparkle_life,
		size = CONFIG.muzzle_sparkle_size * scale,
		spin = random_spin(),
		texture = "shock_sparkle",
	})
	particles.sprite({
		attenuation = 0,
		color = WHITE,
		follow = follow,
		life = CONFIG.muzzle_flash_life,
		size = CONFIG.muzzle_flash_size * scale,
		spin = random_spin(),
		texture = "shock_flash",
	})
end

function fx.ball_muzzle_flash(follow, scale)
	for _ = 1, CONFIG.ball_flash_count do
		particles.sprite({
			attenuation = 0,
			color = PURPLE,
			follow = follow,
			life = CONFIG.ball_flash_life,
			size = between(CONFIG.ball_flash_size) * scale,
			spin = random_spin(),
			texture = "shock_flare_b",
		})
	end
end

-- What a beam hits: the flares, the ring, the core and the scorch mark, where the surface faces the way normal says
local function impact(position, normal)
	local lifted = position + normal * (2 * UNIT)

	for _ = 1, CONFIG.impact_flare_count do
		particles.disc({
			attenuation = 0,
			color = WHITE,
			growth = CONFIG.impact_flare_growth * UNIT,
			life = CONFIG.impact_flare_life,
			normal = normal,
			position = lifted,
			size = between(CONFIG.impact_flare_size) * UNIT,
			spin = random_spin(),
			texture = "shock_flare_a",
		})
	end

	particles.disc({
		attenuation = 0,
		color = WHITE,
		growth = CONFIG.impact_ring_growth * UNIT,
		life = CONFIG.impact_ring_life,
		normal = normal,
		position = lifted,
		size = CONFIG.impact_ring_size * UNIT,
		spin = random_spin(),
		texture = "shock_ring_b",
	})
	particles.sprite({
		attenuation = 0,
		color = WHITE,
		growth = CONFIG.impact_core_growth * UNIT,
		life = CONFIG.impact_core_life,
		position = position + normal * (CONFIG.impact_core_offset * UNIT),
		size = CONFIG.impact_core_size * UNIT,
		texture = "shock_core",
	})
	particles.disc({
		attenuation = 0.05,
		color = WHITE,
		life = CONFIG.scorch_life,
		normal = normal,
		position = position + normal * 0.02,
		size = CONFIG.scorch_size * UNIT,
		texture = "shock_mark_heat",
	})
end

-- The coil of the beam (ShockBeamCoil): pieces of a turning mesh along it
local function coil(start, stop)
	local along = stop - start
	local length = Vector3.length(along)
	local direction = along * (1 / length)
	local up = math.abs(Vector3.dot(direction, Vector3.up())) > 0.99 and Vector3.right() or Vector3.up()
	local rotation = Quaternion.look(direction, up)
	local piece_length = CONFIG.coil_piece_length * UNIT
	local count = math.min(CONFIG.coil_max_pieces, math.ceil(length / piece_length))

	for i = 0, count - 1 do
		-- (the scale is made each time it is asked for: a vector can't be kept from one frame to the next)
		local radius = CONFIG.coil_radius_scale * between(CONFIG.coil_size)

		particles.mesh({
			brightness = function (fraction)
				return 1 - fraction
			end,
			color = {
				CONFIG.coil_color,
				CONFIG.coil_color,
				CONFIG.coil_color,
			},
			life = CONFIG.coil_life,
			position = start + direction * (i * piece_length),
			rotation = rotation,
			scale = function ()
				return Vector3(radius, CONFIG.coil_length_scale, radius)
			end,
			spin = CONFIG.coil_spin,
			spin_axis = Vector3(0, 1, 0),
			texture = "shock_purple_line",
			unit = "units/ut/fx/coil",
		})
	end
end

-- The beam, from start to stop, and what it hits there if it hits a surface (normal is the vector of no length if it doesn't)
function fx.beam(start, stop, normal)
	local along = stop - start
	local length = Vector3.length(along)

	if length > 0.01 then
		coil(start, stop)

		local piece_length = CONFIG.beam_piece_length * UNIT
		local count = math.max(1, math.ceil(length / piece_length))

		for i = 0, count - 1 do
			particles.beam({
				attenuation = CONFIG.beam_attenuation,
				color = WHITE,
				from = start + along * (i / count),
				life = CONFIG.beam_life,
				size = CONFIG.beam_width * UNIT,
				texture = "shock_beam",
				to = start + along * ((i + 1) / count),
			})
		end
	end

	if Vector3.length(normal) > 0.01 then
		impact(stop, Vector3.normalize(normal))
	end
end

-- The ball: what makes it up, made as it goes. A ball is { follow, ... }, follow gives where the ball is (nothing once it is gone).
function fx.new_ball(follow)
	-- (the projectile of UT is a sprite of its own: shock_core_low at DrawScale, all there as long as the ball lives)
	-- (UT draws it with a light of its own that makes it solid; layers of it add up to the same)
	for _ = 1, CONFIG.ball_sprite_layers do
		particles.sprite({
			color = WHITE,
			fade_in = 0,
			follow = follow,
			life = CONFIG.ball_sprite_life,
			size = CONFIG.ball_sprite_size * UNIT,
			texture = "shock_core_low",
		})
	end

	return {
		core_time = 0,
		flare_time = 0,
		follow = follow,
		spark_time = 0,
	}
end

-- (false when the ball is gone)
function fx.update_ball(ball, dt)
	local position = ball.follow()

	if not position then
		return false
	end

	ball.core_time = ball.core_time - dt
	ball.flare_time = ball.flare_time - dt
	ball.spark_time = ball.spark_time - dt

	if ball.core_time <= 0 then
		ball.core_time = CONFIG.ball_core_interval

		particles.sprite({
			color = WHITE,
			fade_in = CONFIG.ball_core_fade_in,
			fade_out = CONFIG.ball_core_fade_out,
			follow = ball.follow,
			life = CONFIG.ball_core_life,
			size = CONFIG.ball_core_size * UNIT,
			spin = random_spin(),
			texture = "shock_core_low",
		})
	end

	if ball.flare_time <= 0 then
		ball.flare_time = CONFIG.ball_flare_interval

		particles.sprite({
			color = WHITE,
			fade_in = CONFIG.ball_flare_fade_in,
			fade_out = CONFIG.ball_flare_fade_out,
			follow = ball.follow,
			life = CONFIG.ball_flare_life,
			size = CONFIG.ball_flare_size * UNIT,
			spin = random_spin(),
			texture = "shock_flare_a",
		})
	end

	while ball.spark_time <= 0 do
		ball.spark_time = ball.spark_time + CONFIG.ball_spark_interval

		-- (the sparks come in to the ball from around it)
		local offset = Vector3Box(random_direction() * (CONFIG.ball_spark_distance * UNIT))

		particles.sprite({
			color = WHITE,
			fade_in = CONFIG.ball_spark_fade_in,
			fade_out = CONFIG.ball_spark_fade_out,
			follow = function ()
				local position = ball.follow()

				return position and position + offset:unbox()
			end,
			life = CONFIG.ball_spark_life,
			size = CONFIG.ball_spark_size * UNIT,
			texture = "shock_core",
		})
	end

	return true
end

-- The ball hits something and goes off (ShockExplosionCore)
function fx.ball_explosion(position)
	particles.sprite({
		attenuation = 0,
		color = WHITE,
		growth = CONFIG.explosion_core_growth * UNIT,
		life = CONFIG.explosion_core_life,
		position = position,
		size = CONFIG.explosion_core_size * UNIT,
		texture = "shock_core",
	})
end

-- The two meshes of the combo (ShockComboSphereDark and ShockComboVortex, MeshEffects): the sphere grows and goes, the vortex lies flat, grows
-- and closes (the frames of its mesh are shown one after the other over its life)
local function combo_meshes(position)
	local life = CONFIG.mesh_life
	local sphere_scale = CONFIG.sphere_scale_interp
	local sphere_fade = CONFIG.sphere_fade_interp

	particles.mesh({
		additive = 1,
		brightness = function (fraction)
			return interpolate(sphere_fade, fraction)
		end,
		color = CONFIG.sphere_color,
		intensity = CONFIG.sphere_intensity,
		life = life,
		position = position,
		rotation = random_rotation(),
		scale = function (fraction)
			return interpolate(sphere_scale, fraction) * CONFIG.sphere_scale
		end,
		texture = "shock_electricity",
		unit = "units/ut/fx/sphere",
	})

	local frames = {}

	for index = 0, CONFIG.vortex_frames - 1, CONFIG.vortex_frame_step do
		frames[#frames + 1] = string.format("g_f%02d", index)
	end

	if (CONFIG.vortex_frames - 1) % CONFIG.vortex_frame_step ~= 0 then
		frames[#frames + 1] = string.format("g_f%02d", CONFIG.vortex_frames - 1)
	end

	local vortex_scale = CONFIG.vortex_scale_interp
	local vortex_fade = CONFIG.vortex_fade_interp

	particles.mesh({
		brightness = function (fraction)
			return interpolate(vortex_fade, fraction)
		end,
		color = CONFIG.vortex_color,
		frame = function (fraction)
			-- (the last of the frames that is shown at or before the one the life is at)
			local index = math.min(math.floor(fraction * CONFIG.vortex_frames), CONFIG.vortex_frames - 1)

			if index == CONFIG.vortex_frames - 1 then
				return frames[#frames]
			end

			return string.format("g_f%02d", index - index % CONFIG.vortex_frame_step)
		end,
		frames = frames,
		life = life,
		position = position,
		rotation = Quaternion.identity(),
		scale = function (fraction)
			return interpolate(vortex_scale, fraction)
		end,
		texture = "shock_elec_a",
		unit = "units/ut/fx/vortex",
	})
end

-- The mark of the combo on the floor (ComboDecal) if there is a floor below it
local function combo_scorch(position)
	local world = Managers.world:world("level_world")
	local hit, hit_position, _, normal = PhysicsWorld.immediate_raycast(World.get_data(world, "physics_world"), position, Vector3(0, 0, -1), CONFIG.combo_scorch_reach * UNIT, "closest", "collision_filter", "filter_player_ray_projectile_static_only")

	if not hit then
		return
	end

	particles.disc({
		additive = 0,
		color = WHITE,
		fade_in = 0,
		fade_out = CONFIG.combo_scorch_life - 2,
		life = CONFIG.combo_scorch_life,
		normal = normal,
		position = hit_position + normal * 0.02,
		size = CONFIG.combo_scorch_size * UNIT,
		spin = 0,
		texture = "shock_combo_scorch",
	})
end

-- The combo (ShockCombo: the core, the ring, the flares, the flash and the wiggles, the sphere and the vortex, the mark on the floor)
function fx.combo(position)
	particles.sprite({
		attenuation = 0,
		color = WHITE,
		growth = CONFIG.combo_core_growth * UNIT,
		life = CONFIG.combo_core_life,
		position = position,
		size = CONFIG.combo_core_size * UNIT,
		texture = "shock_core",
	})
	particles.sprite({
		attenuation = CONFIG.combo_ring_attenuation,
		color = WHITE,
		growth = CONFIG.combo_ring_growth * UNIT,
		life = CONFIG.combo_ring_life,
		position = position,
		size = 0,
		spin = random_spin(),
		texture = "shock_ring_a",
	})
	particles.sprite({
		attenuation = 0.5,
		color = WHITE,
		growth = CONFIG.combo_flash_growth * UNIT,
		life = CONFIG.combo_flash_life,
		position = position,
		size = CONFIG.combo_flash_size * UNIT,
		spin = random_spin(),
		texture = "shock_combo_flash",
	})

	-- The flares come at a rate until combo_flare_time, then there are two big ones that shrink away
	local flares = math.floor(CONFIG.combo_flare_rate * CONFIG.combo_flare_time)

	for i = 0, flares - 1 do
		particles.sprite({
			attenuation = 0.4,
			color = WHITE,
			delay = i / CONFIG.combo_flare_rate,
			growth = CONFIG.combo_flare_growth * UNIT,
			life = CONFIG.combo_flare_life,
			position = position,
			size = CONFIG.combo_flare_size * UNIT,
			spin = random_spin(),
			texture = "shock_flare_a",
		})
	end

	for _ = 1, 2 do
		particles.sprite({
			attenuation = 0.9,
			color = WHITE,
			delay = CONFIG.combo_flare_time,
			growth = CONFIG.combo_big_flare_growth * UNIT,
			life = CONFIG.combo_big_flare_life,
			position = position,
			size = CONFIG.combo_big_flare_size * UNIT,
			spin = random_spin(),
			texture = "shock_flare_a",
		})
	end

	for _ = 1, CONFIG.combo_wiggle_count do
		particles.sprite({
			attenuation = 0.3,
			color = {
				0.35,
				0.4,
				0.4,
			},
			drag = 0.8,
			life = CONFIG.combo_wiggle_life,
			position = position,
			size = CONFIG.combo_wiggle_size * UNIT,
			texture = "shock_sparkle",
			velocity = random_direction() * (CONFIG.combo_wiggle_speed * UNIT),
		})
	end

	combo_meshes(position)
	combo_scorch(position)
end

return fx
