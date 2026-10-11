local mod = get_mod("unreal_tournament")

-- The effects of the Shock Rifle's skin: what UT2004's own rifle shows (XEffects: ShockMuzFlash, ShockBeamEffect, ShockImpact*, ShockBall,
-- ShockExplosion*, ShockCombo*), drawn with the particles of skin_particles.lua. UT's sizes, speeds and times are used as they are, in
-- UT units. The textures are the game's own, converted (tools/asset_conversion/make_fx_assets.py). The meshes (units/ut/fx, made by
-- tools/asset_conversion/make_fx_meshes.py) are the beam's coil and the combo's sphere and vortex.
--
-- shock_rifle_skin.lua calls these functions: it knows when and where an effect happens.

local particles = mod.skin_particles

local CONFIG = {
	-- How many meters a UT unit is in the world (the same as in shock_rifle.lua: a player is 88 units high)
	meters_per_unit = 0.02,

	-- Beam (ShockBeamEffect): pieces of beam_piece_length, beam_width wide, that last beam_life
	beam_piece_length = 150,
	beam_width = 36,
	beam_life = 0.75,
	beam_attenuation = 0.1,
	-- Beam coil (ShockBeamCoil): a piece of the coil mesh (30 units long) every coil_piece_length along the beam, scaled coil_length_scale
	-- along it and coil_radius_scale across times a size from coil_size (mSizeRange), turning about the beam coil_spin turns a second
	-- (mSpinRange 32000 of 65536). coil_color is how bright it is (mColorRange 50 of 255, a little brighter here).
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

	-- What the beam makes where it hits a surface (ShockImpactFlare, ShockImpactRing, the core, ShockImpactScorch)
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

	-- Muzzle flashes: the beam's sparkle and flash (ShockMuzFlash, ShockBeamMuzFlash) and the ball's (ShockProjMuzFlash)
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

	-- The flying ball (ShockProjectile and ShockBall). The ball itself is a sprite that lasts as long as the ball does: ball_sprite_layers
	-- of them added up, each turning its own way (up to ball_sprite_spin turns a second) so that the spikes of the texture move. Under
	-- them is a purple glow, because the texture alone is a dark disc with a rim, which is seen as a ring.
	ball_sprite_size = 90, -- DrawScale 0.7 of the texture's 128 units
	ball_sprite_life = 10, -- the projectile's LifeSpan
	ball_sprite_layers = 3,
	ball_sprite_spin = 0.3,
	ball_fill_size = 85,
	ball_fill_intensity = 1.5,
	-- ShockBall's emitters. A particle is fully there from fade_in until fade_out (UT's FadeInEndTime and FadeOutStartTime), and a new core
	-- starts every interval.
	ball_core_size = 45, -- UT's is 45 by 65 with UniformSize, which takes the 45 for both
	ball_core_life = 0.35,
	ball_core_interval = 0.35,
	ball_core_fade_in = 0.05,
	ball_core_fade_out = 0.32,
	ball_flare_size = 60,
	ball_flare_life = 0.4,
	ball_flare_interval = 0.5,
	ball_flare_fade_in = 0.25,
	ball_flare_fade_out = 0.2,
	ball_spark_size = 26,
	ball_spark_intensity = 0.15,
	ball_spark_life = 0.35,
	ball_spark_fade_in = 0.1,
	ball_spark_fade_out = 0.3,
	ball_spark_interval = 0.025,
	-- Units a second, the speed of a spark in a random direction. A spark goes out and comes back, so it gets a quarter of its life times
	-- this far from the ball: 250 is about 22 units, the edge of the ball's core. (UT's StartVelocityRange is only 70, which is about
	-- 6 units; 800 sent the sparks 70 units away, as dots in the air, which UT's ball does not have.)
	ball_spark_speed = 250,

	-- The ball's explosion: ShockExplosionCore, and ShockExplosion's dark sphere. The sphere is EffectsSphere144 (48 units in radius) in UT; it
	-- is drawn with the combo's smoother sphere mesh (sphere_mesh_radius units in radius). It starts at explosion_sphere_size times its radius,
	-- grows explosion_sphere_growth of that a second, and is at its darkest explosion_sphere_attenuation of the way through its life.
	explosion_core_size = 40,
	explosion_core_growth = 100,
	explosion_core_life = 1,
	explosion_sphere_life = 0.6,
	explosion_sphere_size = 0.6,
	explosion_sphere_growth = 1.2,
	explosion_sphere_attenuation = 0.3,
	explosion_sphere_darkness = 0.2, -- UT's gray of 100 of 255 is 0.39: it is fainter here
	explosion_sphere_radius = 48,
	sphere_mesh_radius = 126.7,

	-- Lights. UT's lights have hue 195 (of 255) and saturation 85-180, which is purple. LightRadius is in steps of 25 units: 4 for the ball
	-- and for the rifle's shot, 5 for the ball's explosion (gone at 0.5 s, dimming), 10 for the combo. The combo has two lights: the
	-- combo's own (on for the 0.9 s that it waits) and the flash's, which is more saturated and lasts 0.3 s.
	light_color = { 0.7, 0.4, 1 },
	ball_light_intensity = 1.5,
	ball_light_falloff = 2, -- meters
	explosion_light_intensity = 3,
	explosion_light_falloff = 2.5,
	explosion_light_life = 0.5,
	fire_light_intensity = 1.5,
	fire_light_falloff = 2,
	fire_light_life = 0.15,
	combo_light_intensity = 2,
	combo_light_falloff = 5,
	combo_light_life = 0.9,
	combo_flash_light_color = { 0.55, 0.2, 1 },
	combo_flash_light_intensity = 2,
	combo_flash_light_life = 0.3,

	-- The combo (ShockCombo and what it spawns)
	combo_core_size = 50,
	combo_core_growth = 400,
	combo_core_life = 1.5,
	combo_flare_size = 85,
	combo_flare_growth = 260,
	combo_flare_life = 0.5,
	combo_flare_rate = 5, -- a second
	combo_flare_time = 0.9, -- how long they come: then there are two big ones
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
	-- The wiggles (ShockComboWiggles): UT's mSizeRange is 120 and its mSpeedRange 300, but a sprite's size is its radius there, so they look
	-- twice as big in UT; they are subtler, and do not go as far as that speed makes them
	combo_wiggle_count = 25,
	combo_wiggle_size = 240,
	combo_wiggle_intensity = 0.4,
	combo_wiggle_speed = 150,
	combo_wiggle_life = 0.75,

	-- The two meshes of the combo (ShockComboSphereDark, ShockComboVortex) are MeshEffects: they last mesh_life, and UT gives them
	-- interpolations of how big they are (scale) and how much of them there is (fade), see interpolate below.
	mesh_life = 1,
	-- How many times the mesh (UT's own Editor.TexPropSphere) is the sphere of UT
	sphere_scale = 1,
	-- The sphere is mostly see through, with a bright band of bolts (lightning that sweeps over it) that is all of it that shows. The tint
	-- of the bolts, which are blue and white in their texture:
	sphere_color = {
		0.55,
		0.65,
		1,
	},
	-- How much of the bolts and of the vortex (the jagged ring of lines that faces the camera) show at the most, 1 being UT's
	sphere_opacity = 1,
	vortex_opacity = 2.5,
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

	-- Turns a second of what spins (UT's mSpinRange is in units of its own)
	spin = 0.3,
}

local UNIT = CONFIG.meters_per_unit

local fx = {}

-- Colors for textures that are not used as they are
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

-- UT's MeshEffect.InterpInterp: a value that goes from start to mid over the first in_time of the effect's life (0 to 1), stays there until
-- out_time, and goes to finish from there, in the style of each
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

-- UT's RotRand(): a random pitch and a random yaw, and no roll, which turns the pole of a sphere any way
local function random_rotation()
	local pitch = Quaternion.axis_angle(Vector3(0, 1, 0), math.random() * math.pi * 2)
	local yaw = Quaternion.axis_angle(Vector3(0, 0, 1), math.random() * math.pi * 2)

	return Quaternion.multiply(yaw, pitch)
end

-- The brightness of a light that does not dim (a steady light of UT's)
local function steady()
	return 1
end

-- Muzzle flashes. `follow` is a function that returns where the muzzle is, `scale` is how many meters a UT unit is there (the gun's model
-- is drawn at a scale of its own).

-- UT lights the weapon for 0.15 s with each shot, the beam's and the ball's (xWeaponAttachment.WeaponLight)
local function fire_light(follow)
	particles.light({
		brightness = steady,
		color = CONFIG.light_color,
		falloff = CONFIG.fire_light_falloff,
		follow = follow,
		intensity = CONFIG.fire_light_intensity,
		life = CONFIG.fire_light_life,
	})
end

function fx.beam_muzzle_flash(follow, scale)
	fire_light(follow)

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
	fire_light(follow)

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

-- What a beam makes where it hits a surface that faces the way `normal` says: flares, a ring, a core and a scorch mark
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

-- The beam's coil (ShockBeamCoil): pieces of a turning mesh along it
local function coil(start, stop)
	local along = stop - start
	local length = Vector3.length(along)
	local direction = along * (1 / length)
	local up = math.abs(Vector3.dot(direction, Vector3.up())) > 0.99 and Vector3.right() or Vector3.up()
	local rotation = Quaternion.look(direction, up)
	local piece_length = CONFIG.coil_piece_length * UNIT
	local count = math.min(CONFIG.coil_max_pieces, math.ceil(length / piece_length))

	for i = 0, count - 1 do
		-- (a vector can't be kept from one frame to the next, so the scale is made each time it is asked for)
		local radius = CONFIG.coil_radius_scale * between(CONFIG.coil_size)
		-- The last piece is only as long as what is left of the beam, so that the coil does not go on past the end of the beam
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

-- The beam, from `start` to `stop`, and what it hits there if it hits a surface (`normal` is the vector of no length if it doesn't)
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

-- The flying ball: new_ball makes the particles that last as long as the ball, update_ball makes the short-lived ones (the core, the flares
-- and the sparks) as it goes. `follow` is a function that returns the ball's position, or nothing once the ball is gone.
function fx.new_ball(follow)
	particles.light({
		brightness = steady,
		color = CONFIG.light_color,
		falloff = CONFIG.ball_light_falloff,
		follow = follow,
		intensity = CONFIG.ball_light_intensity,
		life = CONFIG.ball_sprite_life,
	})

	particles.sprite({
		color = PURPLE,
		fade_in = 0,
		follow = follow,
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
			life = CONFIG.ball_sprite_life,
			size = CONFIG.ball_sprite_size * UNIT,
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

-- Returns false when the ball is gone
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

		-- A spark goes out from the ball in a random direction at a velocity that is scaled down to the opposite of itself over the spark's life
		-- (VelocityScale), so it goes out and comes back to the ball, which it moves with
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
			intensity = CONFIG.ball_spark_intensity,
			life = CONFIG.ball_spark_life,
			size = CONFIG.ball_spark_size * UNIT,
			texture = "shock_core",
		})
	end

	return true
end

-- The ball hits something and goes off: a light, the dark sphere (ShockExplosion) and the core (ShockExplosionCore)
function fx.ball_explosion(position)
	local life = CONFIG.explosion_sphere_life

	particles.light({
		color = CONFIG.light_color,
		falloff = CONFIG.explosion_light_falloff,
		intensity = CONFIG.explosion_light_intensity,
		life = CONFIG.explosion_light_life,
		position = position,
	})

	particles.mesh({
		additive = 0,
		-- (UT brings it in until explosion_sphere_attenuation of its life, and out after that)
		brightness = function (fraction)
			if fraction < CONFIG.explosion_sphere_attenuation then
				return fraction / CONFIG.explosion_sphere_attenuation
			end

			return (1 - fraction) / (1 - CONFIG.explosion_sphere_attenuation)
		end,
		color = { 0, 0, 0 },
		intensity = CONFIG.explosion_sphere_darkness,
		life = life,
		material = "units/ut/fx/fx_explosion_dark",
		position = position,
		rotation = random_rotation(),
		scale = function (fraction)
			return (CONFIG.explosion_sphere_size + CONFIG.explosion_sphere_growth * life * fraction)
				* CONFIG.explosion_sphere_radius / CONFIG.sphere_mesh_radius
		end,
		unit = "units/ut/fx/sphere",
	})

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

-- The combo's two meshes, as UT has them (the materials pan their textures themselves, see tools/asset_conversion/make_combo_materials.py):
--   ShockComboSphereDark: a sphere (turned any way) with the bolts that pan along it
--   ShockComboVortex: a flat disc that always faces the camera, with lines that pan along it in a band
local function combo_sphere_bolts(position)
	particles.mesh({
		additive = 1,
		brightness = function (fraction)
			return interpolate(CONFIG.sphere_fade_interp, fraction) * CONFIG.sphere_opacity
		end,
		color = CONFIG.sphere_color,
		life = CONFIG.mesh_life,
		material = "units/ut/fx/fx_combo_sphere",
		position = position,
		rotation = random_rotation(),
		scale = function (fraction)
			return interpolate(CONFIG.sphere_scale_interp, fraction) * CONFIG.sphere_scale
		end,
		unit = "units/ut/fx/sphere",
	})
end

local function combo_vortex(position)
	particles.mesh({
		additive = 1,
		brightness = function (fraction)
			return interpolate(CONFIG.vortex_fade_interp, fraction) * CONFIG.vortex_opacity
		end,
		face_camera = true,
		life = CONFIG.mesh_life,
		material = "units/ut/fx/fx_combo_vortex",
		position = position,
		rotation = Quaternion.identity(),
		scale = function (fraction)
			return interpolate(CONFIG.vortex_scale_interp, fraction)
		end,
		unit = "units/ut/fx/vortex",
	})
end

local function combo_ring(position)
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

local function combo_lights(position)
	particles.light({
		brightness = steady,
		color = CONFIG.light_color,
		falloff = CONFIG.combo_light_falloff,
		intensity = CONFIG.combo_light_intensity,
		life = CONFIG.combo_light_life,
		position = position,
	})
	particles.light({
		brightness = steady,
		color = CONFIG.combo_flash_light_color,
		falloff = CONFIG.combo_light_falloff,
		intensity = CONFIG.combo_flash_light_intensity,
		life = CONFIG.combo_flash_light_life,
		position = position,
	})
end

local function combo_flash(position)
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

-- Flares come at combo_flare_rate until combo_flare_time, then two big ones come that shrink away
local function combo_flares(position)
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
	for _ = 1, CONFIG.combo_wiggle_count do
		-- (ShockComboWiggles' particles are discs that UT draws square to the view, as sprites: fixed in one direction they looked like lines)
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

-- The combo (ShockCombo): the ring, the core, the flash, the lights, the flares, the wiggles, the sphere and the vortex. (UT's ComboDecal, the
-- mark on the floor, is not made: a flat disc only works on a flat floor, and the game's own effects that leave a mark are whole effects.)
function fx.combo(position)
	combo_ring(position)
	combo_core(position)
	combo_flash(position)
	combo_lights(position)
	combo_flares(position)
	combo_wiggles(position)
	combo_sphere_bolts(position)
	combo_vortex(position)
end

return fx
