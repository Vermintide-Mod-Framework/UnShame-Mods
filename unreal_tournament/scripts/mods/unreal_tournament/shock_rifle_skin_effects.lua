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
	ball_core_size = 55,
	ball_core_life = 0.35,
	ball_core_interval = 0.3,
	ball_flare_size = 60,
	ball_flare_life = 0.4,
	ball_flare_interval = 0.5,
	ball_spark_size = 4.5,
	ball_spark_life = 0.35,
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

-- The beam, from start to stop, and what it hits there if it hits a surface (normal is the vector of no length if it doesn't)
function fx.beam(start, stop, normal)
	local along = stop - start
	local length = Vector3.length(along)

	if length > 0.01 then
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
			attenuation = 0.143,
			color = WHITE,
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
			attenuation = 0.4,
			color = WHITE,
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
		local offset = random_direction() * (CONFIG.ball_spark_distance * UNIT)

		particles.sprite({
			attenuation = 0.3,
			color = WHITE,
			follow = function ()
				return ball.follow() and ball.follow() + offset
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

-- The combo (ShockCombo: the core, the ring, the flares, the flash and the wiggles)
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
end

return fx
