local mod = get_mod("unreal_tournament")

-- The effects of the Shock Rifle's skin: what UT2004's own shows (XEffects: ShockMuzFlash, ShockBeamEffect, ShockImpact*,
-- ShockBall, ShockExplosionCore, ShockCombo*), drawn with the particles of skin_particles.lua. UT's sizes, speeds and times are
-- used as they are, in UT units; the textures are the game's own, converted (tools/asset_conversion/make_fx_assets.py).
-- The meshes of the effects are the coil of the beam and the sphere and the vortex of the combo (units/ut/fx, tools/asset_conversion/make_fx_meshes.py).
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
	ball_grow_time = 0.25, -- seconds the core of the ball takes to grow to its size when it starts
	-- (FadeInEndTime and FadeOutStartTime of each: it is all there between, and the next core comes as one ends)
	ball_fill_size = 85, -- units across: as big as the rim of the texture of the ball is
	ball_fill_intensity = 1.5,
	ball_sprite_spin = 0.8, -- turns a second, the most a layer of the ball's sprite turns either way
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
	ball_spark_size = 18,
	ball_spark_life = 0.35,
	ball_spark_fade_in = 0.1,
	ball_spark_fade_out = 0.3,
	ball_spark_interval = 0.025,
	-- Units a second, the speed of a spark in a direction of any kind (UT's StartVelocityRange is 70 in each axis, which takes a spark about 6 units
	-- out). A spark goes out a quarter of its life times that: 250 takes it about 22 units out, to the edge of the core of the ball and not away
	-- from it (800 sent them 70 units away, as dots in the air, which UT's ball does not have)
	ball_spark_speed = 250,
	-- ShockProjectile's explosion: ShockExplosionCore
	explosion_core_size = 40,
	explosion_core_growth = 100,
	explosion_core_life = 1,
	-- ShockCombo and the effects it makes
	combo_core_size = 50,
	combo_core_growth = 400,
	combo_core_life = 1.5,
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
	-- ShockComboExpRing: one ring sprite that grows from nothing
	combo_ring_growth = 500,
	combo_ring_life = 0.5,
	combo_ring_attenuation = 0.4,
	combo_wiggle_count = 25,
	combo_wiggle_size = 240, -- (UT's mSizeRange is 120: they look twice as big in UT, as a sprite's size is its radius there)
	combo_wiggle_intensity = 0.4, -- (and subtler)
	combo_wiggle_speed = 150, -- (UT's mSpeedRange is 300: they do not go as far in UT as that makes them)
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
	-- them there is that UT gives them) (UT's ComboDecal, the mark on the floor, is not made: a flat disc is no good on anything but a flat floor,
	-- and the game's own effects that leave a mark are whole effects)
	mesh_life = 1,
	-- (how many times the mesh is the sphere of UT: the mesh is UT's own, Editor.TexPropSphere)
	sphere_scale = 1,
	-- The tint of the bolts (they are blue and white in their texture)
	sphere_color = {
		0.55,
		0.65,
		1,
	},
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
	-- (UT's sphere is mostly see through, with its bright band of bolts: the body is a little of this, and what is behind it shows through)
	sphere_fill_color = {
		0.45,
		0.3,
		1,
	},
	sphere_fill_intensity = 0.2,
	-- Which of the effects of the combo are drawn (the game's rings, shock_rifle.lua's, are not these)
	combo_shown = {
		core = true,
		flares = true,
		flash = true,
		ring = true,
		sphere_body = false,
		sphere_bolts = true,
		vortex = true,
		wiggles = true,
	},
	-- How much of the vortex (the jagged ring of lines that faces the camera) shows at the most, 1 being UT's
	vortex_opacity = 2.5,
	-- How much of the sphere's bolts show at the most, 1 being UT's (the bolts are a strip of lightning that sweeps over the sphere: the blue band)
	sphere_opacity = 1,
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

-- UT's RotRand(): a random pitch and a random yaw, and no roll (it is only with bRoll), which turns the pole of a sphere any way
local function random_rotation()
	local pitch = Quaternion.axis_angle(Vector3(0, 1, 0), math.random() * math.pi * 2)
	local yaw = Quaternion.axis_angle(Vector3(0, 0, 1), math.random() * math.pi * 2)

	return Quaternion.multiply(yaw, pitch)
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
		-- (the last piece is as long as what is left of the beam, so that it does not go on past where the beam ends: through a ball that it hits)
		local piece_scale = CONFIG.coil_length_scale * math.min(1, (length - i * piece_length) / piece_length)

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
				return Vector3(radius, piece_scale, radius)
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

-- The flying ball: new_ball creates its long-lived sprites, update_ball spawns the short-lived ones (core, flares, sparks) every frame.
-- `follow` is a function that returns the ball's position, or nil once the ball is gone.
function fx.new_ball(follow)
	-- (the projectile of UT is a sprite of its own: shock_core_low at DrawScale, all there as long as the ball lives)
	-- (UT draws it with a light of its own that makes it solid; layers of it add up to the same)
	-- (the texture of the ball is a dark disc with a rim and a bright middle, which on its own is seen as a ring: the sphere is filled with a
	-- purple glow under it)
	particles.sprite({
		color = PURPLE,
		fade_in = 0,
		follow = follow,
		grow_time = CONFIG.ball_grow_time,
		intensity = CONFIG.ball_fill_intensity,
		life = CONFIG.ball_sprite_life,
		size = CONFIG.ball_fill_size * UNIT,
		texture = "shock_mark_heat",
	})

	for _ = 1, CONFIG.ball_sprite_layers do
		particles.sprite({
			color = WHITE,
			fade_in = 0,
			follow = follow,
			grow_time = CONFIG.ball_grow_time,
			life = CONFIG.ball_sprite_life,
			size = CONFIG.ball_sprite_size * UNIT,
			-- (each layer turns its own way, so that the spikes of the texture move: made once and still, they stood out against the ones that
			-- UT makes again every 0.35 s)
			spin = (math.random() * 2 - 1) * CONFIG.ball_sprite_spin,
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

		-- (a spark of UT goes out from the ball at a velocity of its own, in each axis, which is scaled down to the opposite of it over its life
		-- (VelocityScale), so that it goes out and comes back to the ball, which it moves with: it is where the ball is and how far it has gone)
		local velocity = Vector3Box(random_direction() * (CONFIG.ball_spark_speed * UNIT))
		local started = Managers.time:time("game")

		particles.sprite({
			color = WHITE,
			fade_in = CONFIG.ball_spark_fade_in,
			fade_out = CONFIG.ball_spark_fade_out,
			follow = function ()
				local position = ball.follow()

				if not position then
					return nil
				end

				local age = Managers.time:time("game") - started

				return position + velocity:unbox() * (age - age * age / CONFIG.ball_spark_life)
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

-- The two meshes of the combo, as UT has them (MeshEffect: how big they are and how much of them there is are interpolated over mesh_life; the
-- materials pan their textures themselves, see tools/asset_conversion/make_combo_materials.py):
--   ShockComboSphereDark: a sphere (turned any way) with the bolts that pan along it, which are all there is of it: the rest is see through
--   ShockComboVortex: a flat disc that always faces the camera, with lines that pan along it in a band
local function combo_sphere_body(position)
	if not CONFIG.combo_shown.sphere_body then
		return
	end

	local life = CONFIG.mesh_life
	local sphere_scale = CONFIG.sphere_scale_interp
	local sphere_fade = CONFIG.sphere_fade_interp

	-- (the body of the sphere: a little purple that what is behind it shows through; blended, not added: added to the flash and the core that
	-- are in it, a solid color is blown out to white and pink)
	particles.mesh({
		additive = 0,
		brightness = function (fraction)
			return interpolate(sphere_fade, fraction)
		end,
		color = CONFIG.sphere_fill_color,
		intensity = CONFIG.sphere_fill_intensity,
		life = life,
		position = position,
		rotation = Quaternion.identity(),
		scale = function (fraction)
			return interpolate(sphere_scale, fraction) * CONFIG.sphere_scale
		end,
		texture = "shock_solid",
		unit = "units/ut/fx/sphere",
	})
end

local function combo_sphere_bolts(position)
	if not CONFIG.combo_shown.sphere_bolts then
		return
	end

	local life = CONFIG.mesh_life
	local sphere_scale = CONFIG.sphere_scale_interp
	local sphere_fade = CONFIG.sphere_fade_interp

	particles.mesh({
		additive = 1,
		brightness = function (fraction)
			return interpolate(sphere_fade, fraction) * CONFIG.sphere_opacity
		end,
		color = CONFIG.sphere_color,
		life = life,
		material = "units/ut/fx/fx_combo_sphere",
		position = position,
		rotation = random_rotation(),
		scale = function (fraction)
			return interpolate(sphere_scale, fraction) * CONFIG.sphere_scale
		end,
		unit = "units/ut/fx/sphere",
	})
end

local function combo_vortex(position)
	if not CONFIG.combo_shown.vortex then
		return
	end

	local life = CONFIG.mesh_life
	local vortex_scale = CONFIG.vortex_scale_interp
	local vortex_fade = CONFIG.vortex_fade_interp

	particles.mesh({
		additive = 1,
		brightness = function (fraction)
			return interpolate(vortex_fade, fraction) * CONFIG.vortex_opacity
		end,
		face_camera = true,
		life = life,
		material = "units/ut/fx/fx_combo_vortex",
		position = position,
		rotation = Quaternion.identity(),
		scale = function (fraction)
			return interpolate(vortex_scale, fraction)
		end,
		unit = "units/ut/fx/vortex",
	})
end

local function combo_ring(position)
	if not CONFIG.combo_shown.ring then
		return
	end

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
end

local function combo_core(position)
	if not CONFIG.combo_shown.core then
		return
	end

	particles.sprite({
		attenuation = 0,
		color = WHITE,
		growth = CONFIG.combo_core_growth * UNIT,
		life = CONFIG.combo_core_life,
		position = position,
		size = CONFIG.combo_core_size * UNIT,
		texture = "shock_core",
	})
end

local function combo_flash(position)
	if not CONFIG.combo_shown.flash then
		return
	end

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
end

local function combo_flares(position)
	if not CONFIG.combo_shown.flares then
		return
	end

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
end

local function combo_wiggles(position)
	if not CONFIG.combo_shown.wiggles then
		return
	end

	for _ = 1, CONFIG.combo_wiggle_count do
		-- (ShockComboWiggles is an emitter of PT_Disc, which UT draws square to the view, as a sprite: fixed to one way they were seen as lines)
		particles.sprite({
			attenuation = 0.3,
			color = {
				0.35,
				0.4,
				0.4,
			},
			drag = 0.8,
			intensity = CONFIG.combo_wiggle_intensity,
			life = CONFIG.combo_wiggle_life,
			position = position,
			size = CONFIG.combo_wiggle_size * UNIT,
			texture = "shock_sparkle",
			velocity = random_direction() * (CONFIG.combo_wiggle_speed * UNIT),
		})
	end
end

-- The combo (ShockCombo: the core, the ring, the flares, the flash and the wiggles, the sphere and the vortex, the mark on the floor), each of
-- which is shown or not by CONFIG.combo_shown
function fx.combo(position)
	combo_ring(position)
	combo_core(position)
	combo_flash(position)
	combo_flares(position)
	combo_wiggles(position)
	combo_sphere_body(position)
	combo_sphere_bolts(position)
	combo_vortex(position)
end

return fx
