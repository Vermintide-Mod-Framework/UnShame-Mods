local mod = get_mod("unreal_tournament")

-- The effects of the Shock Rifle's skin. They are what UT2004's own rifle shows (XEffects: ShockMuzFlash, ShockBeamEffect,
-- ShockImpact*, ShockBall, ShockExplosion*, ShockCombo*), drawn with the particles of skin_particles.lua. UT's speeds and times are used
-- as they are, in UT units. The sizes of the xEmitters' sprites and discs are UT's (mSizeRange, and mGrowthRate a second), and each is
-- drawn utils.UT_SPRITE_SIDE times that across (SPRITE below). The textures are UT's own, converted
-- (tools/asset_conversion/make_fx_assets.py). The meshes (units/ut/fx, made by tools/asset_conversion/make_fx_meshes.py) are the beam's
-- coil and the combo's sphere and vortex.
--
-- skin.lua calls these functions, because it knows when and where an effect happens.

local utils = mod.utils
local particles = mod.skin_particles

local CONFIG = {
	-- The beam (ShockBeamEffect), an xEmitter of PT_Beam drawn as Engine.dll draws one (decompiled; see the Link Gun's skin): a point
	-- every beam_regen_dist (mRegenDist) from the start to the end, the last piece short, and beam_planes (mMaxParticles) flat ribbons
	-- through them, turned half a turn / beam_planes apart about the line, which don't turn (mSpinRange 0). The texture is once along
	-- each piece. While it fades (mAttenuate), each ribbon reaches beam_size[1] to each side at the start of its life and grows to
	-- beam_size[2] by the square of the share of its life gone (mSizeRange), and it is its colour times the square of the share left
	-- (its mAttenKa is not used). It is STY_Additive, which adds the colour times its alpha, faded the same: it shows the fourth power.
	-- It lasts beam_life (mLifeRange[0], and the actor's LifeSpan).
	beam_regen_dist = 150, -- UT units
	beam_planes = 3,
	beam_size = { 24, 48 }, -- UT units to each side
	beam_life = 0.75,
	-- The beam's coil (ShockBeamCoil) is a piece of the coil mesh (30 units long) every coil_piece_length along the beam. Each piece is
	-- scaled by coil_length_scale along the beam and coil_radius_scale across it, times a size from coil_size (mSizeRange). It turns
	-- about the beam coil_spin turns a second (mSpinRange 32000 out of 65536). coil_color is its brightness: UT's mColorRange is 50 out
	-- of 255, and here it is a little brighter.
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

	-- What the beam makes where it hits a surface: ShockImpactFlare, ShockImpactRing, the core and ShockImpactScorch.
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

	-- Muzzle flashes. A beam in the player's own view has ShockMuzFlash's sparkle at the weapon's effect start (ShockBeamEffect), and
	-- the flash on the model (fx.BEAM_FLASH); in a character's hand it has ShockMuzFlash3rd's sparkle instead, of size 65 growing 80 a
	-- second for 0.5 s, and no mesh. A ball has its flash on the model (fx.BALL_FLASH), or ShockProjMuzFlash3rd on the mesh in a
	-- character's hand (ShockAttachment.ThirdPersonEffects): one MinigunFlashMesh, of size 0.35 to 0.4 growing 3.2 a second, for 0.13 s,
	-- turned at random about the barrel, ShockMuzFlash3rdFinal times its mColorRange (50, 255, 255: the colour's fields that the class
	-- leaves out are xEmitter's 255). All are STY_Additive, which adds the colour times its alpha and fades by the square, or
	-- FB_Brighten for the meshes, which adds the colour times the texture's alpha and fades once (see muzzle_flash.lua).
	muzzle_sparkle_size = 50,
	muzzle_sparkle_growth = 50,
	muzzle_sparkle_life = 0.5,
	muzzle_3rd_size = 65,
	muzzle_3rd_growth = 80,
	muzzle_3rd_life = 0.5,
	ball_3rd_size = { 0.35, 0.4 },
	ball_3rd_growth = 3.2,
	ball_3rd_life = 0.13,
	ball_3rd_color = { 50 / 255, 1, 1 },

	-- The flying ball (ShockProjectile and ShockBall). The ball itself is a sprite that lasts as long as the ball does. There are
	-- ball_sprite_layers of them added together, and each turns its own way (up to ball_sprite_spin turns a second) so that the spikes
	-- of the texture move. Under them is a purple glow, because the texture alone is a dark disc with a rim, which looks like a ring.
	ball_sprite_size = 90, -- DrawScale 0.7 of the texture's 128 units
	ball_sprite_life = 10, -- the projectile's LifeSpan
	ball_sprite_layers = 3,
	ball_sprite_spin = 0.3,
	ball_fill_size = 85,
	ball_fill_intensity = 1.5,
	-- ShockBall's emitters. A particle is fully visible from fade_in until fade_out (UT's FadeInEndTime and FadeOutStartTime), and a
	-- new core starts every interval.
	ball_core_size = 45, -- UT's is 45 by 65 with UniformSize, which uses the 45 for both
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
	-- The speed of a spark in a random direction, in units a second. A spark goes out and comes back, so it gets as far from the ball
	-- as a quarter of its life times this speed. 250 gives about 22 units, the edge of the ball's core. UT's StartVelocityRange is only
	-- 70, which is about 6 units. 800 sent the sparks 70 units away, as dots in the air, which UT's ball does not have.
	ball_spark_speed = 250,

	-- The ball's explosion is ShockExplosionCore and ShockExplosion's dark sphere. In UT the sphere is EffectsSphere144 (48 units in
	-- radius). Here it is drawn with the combo's smoother sphere mesh (sphere_mesh_radius units in radius). It starts at
	-- explosion_sphere_size times its radius, grows explosion_sphere_growth of that a second, and fades in and out with ATF_ExpInOut
	-- (skin_particles.lua's exp_in_out) at explosion_sphere_attenuation.
	explosion_core_size = 40,
	explosion_core_growth = 100,
	explosion_core_life = 1,
	explosion_sphere_life = 0.6,
	explosion_sphere_size = 0.6,
	explosion_sphere_growth = 1.2,
	explosion_sphere_attenuation = 0.3,
	explosion_sphere_darkness = 0.2, -- UT's gray of 100 out of 255 is 0.39. It is fainter here.
	explosion_sphere_radius = 48,
	sphere_mesh_radius = 126.7,

	-- Lights. UT's lights have hue 195 (out of 255) and saturation 85 to 180, which is purple. LightRadius is in steps of 25 units: 4
	-- for the ball and for the rifle's shot, 5 for the ball's explosion (it dims and is gone at 0.5 s), and 10 for the combo. The combo
	-- has two lights. Its own light is on for the 0.9 s that the combo waits. The flash's light is more saturated and lasts 0.3 s.
	light_color = { 0.7, 0.4, 1 },
	ball_light_intensity = 1.5,
	ball_light_falloff = 2, -- meters
	explosion_light_intensity = 3,
	explosion_light_falloff = 2.5,
	explosion_light_life = 0.5,
	fire_light_falloff = 2,
	fire_light_life = 0.15,
	combo_light_intensity = 2,
	combo_light_falloff = 5,
	combo_light_life = 0.9,
	combo_flash_light_color = { 0.55, 0.2, 1 },
	combo_flash_light_intensity = 2,
	combo_flash_light_life = 0.3,

	-- The combo: ShockCombo and what it spawns
	combo_core_size = 50,
	combo_core_growth = 400,
	combo_core_life = 1.5,
	combo_flare_size = 85,
	combo_flare_growth = 260,
	combo_flare_life = 0.5,
	combo_flare_attenuation = 0.2,
	combo_flare_rate = 5, -- flares a second
	combo_flare_time = 0.9, -- how long flares keep coming. After that two big ones come.
	combo_big_flare_size = 150,
	combo_big_flare_growth = -500,
	combo_big_flare_life = 0.3,
	combo_flash_size = { 480, 660 },
	combo_flash_growth = 500,
	combo_flash_life = 0.25,
	combo_flash_attenuation = 0.2,
	-- ShockComboExpRing is one ring sprite that grows from nothing.
	combo_ring_growth = 500,
	combo_ring_life = 0.5,
	combo_ring_attenuation = 0.4,
	-- The wiggles (ShockComboWiggles): mSizeRange 120 and mSpeedRange 300. Here they are subtler, and they don't go as far as that speed
	-- would take them.
	combo_wiggle_count = 25,
	combo_wiggle_size = 120,
	combo_wiggle_intensity = 0.4,
	combo_wiggle_speed = 150,
	combo_wiggle_life = 0.75,

	-- The combo's two meshes (ShockComboSphereDark and ShockComboVortex) are MeshEffects. They last mesh_life. UT gives each an
	-- interpolation of how big it is (scale) and how much of it shows (fade). See interpolate below.
	mesh_life = 1,
	-- How many times bigger the mesh (UT's own Editor.TexPropSphere) is than UT's sphere
	sphere_scale = 1,
	-- The sphere is mostly see-through. The only part that shows is a bright band of bolts, lightning that sweeps over it. This is the
	-- tint of the bolts, which are blue and white in their texture:
	sphere_color = {
		0.55,
		0.65,
		1,
	},
	-- The most that the bolts, and the vortex (the jagged ring of lines that faces the camera), show. 1 is UT's amount.
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

	-- Turns a second of the things that spin. UT's mSpinRange is in units of its own.
	spin = 0.3,
}

local UNIT = utils.UT_UNIT
-- (the meters across an xEmitter's sprite or disc for each unit of its size)
local SPRITE = utils.UT_SPRITE_SIDE * UNIT

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
-- The Instagib Shock Rifle's effects are the same effects in red. ShockMuzFlashB, ShockImpactFlareB, ShockImpactRingB and
-- ShockExplosionCoreB use the color R235 G35 B35, and ShockBeamCoilB uses R150.
local RED = {
	235 / 255,
	35 / 255,
	35 / 255,
}
local RED_COIL = {
	150 / 255,
	0,
	0,
}

local random_between = utils.random_between
local random_direction = utils.random_direction

local function random_spin()
	return (math.random() * 2 - 1) * CONFIG.spin
end

-- UT's MeshEffect.InterpInterp. Over the effect's life (0 to 1) a value goes from start to mid during the first in_time, stays at mid
-- until out_time, and then goes to finish. Each of the two changes follows its own style (linear, exp, inv_exp or s).
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

-- UT's RotRand(): a random pitch and a random yaw, and no roll. It points the pole of a sphere in a random direction.
local function random_rotation()
	local pitch = Quaternion.axis_angle(Vector3(0, 1, 0), math.random() * math.pi * 2)
	local yaw = Quaternion.axis_angle(Vector3(0, 0, 1), math.random() * math.pi * 2)

	return Quaternion.multiply(yaw, pitch)
end

-- The brightness of a light that does not dim, which is a steady light in UT
local function steady()
	return 1
end

-- Muzzle flashes. `follow` is a function that returns where the muzzle is. `scale` is how many meters a UT unit is there, because the
-- gun's model is drawn at a scale of its own.

-- UT lights the weapon for 0.15 s with each shot, of the beam and of the ball (xWeaponAttachment.WeaponLight). It is the third person
-- attachment's light: UT's first person gun is not lit by it, and here a light at the first person muzzle lit the gun purple. So there is
-- none in the player's own first person view (locked).
local function fire_light(follow, locked)
	if locked then
		return
	end

	particles.light({
		brightness = steady,
		color = CONFIG.light_color,
		falloff = CONFIG.fire_light_falloff,
		follow = follow,
		intensity = utils.WEAPON_LIGHT_INTENSITY,
		life = CONFIG.fire_light_life,
	})
end

-- The flashes on the model in the player's own view, for mod.muzzle_flash (UT draws them on the weapon's tip, with its field of view,
-- at their own DrawScale of 1). ShockBeamMuzFlash: one ShockMuzFlash mesh for a shot, of size 0.5 growing 5 a second, for 0.14 s,
-- not turned. ShockProjMuzFlash: 3 MinigunMuzFlash1stMesh for a shot, with room for 6, of size 0.6 to 0.7, for 0.2 s, not turned, each
-- one of the 4 tiles of shock_muzflash_1st at random, kept (mRandTextures). Both fade from the start (mAttenKa 0), FB_Brighten.
fx.BEAM_FLASH = {
	angle = 0,
	attenuation = 0,
	color = { 1, 1, 1 },
	count = 1,
	growth = 5,
	life = { 0.14, 0.14 },
	linear = true,
	material = "units/ut/fx/fx_weapon_shock_beam_flash",
	max = 5,
	scale = { 0.5, 0.5 },
	tiles = 1,
	unit = "units/ut/fx/shock_flash_mesh",
}
fx.BALL_FLASH = {
	angle = 0,
	attenuation = 0,
	color = { 1, 1, 1 },
	count = 3,
	growth = 0,
	life = { 0.2, 0.2 },
	linear = true,
	material = "units/ut/fx/fx_weapon_shock_muzflash_1st_",
	max = 6,
	scale = { 0.6, 0.7 },
	still_tiles = true,
	unit = "units/ut/fx/minigun_flash_mesh",
}

-- The sparkles and the light of a shot (see CONFIG). `follow` returns the position. `locked` is used in the player's own first person
-- view: it returns a unit and a position in that unit (see skin_particles.lua). `rotation` returns the way the mesh in a character's
-- hand points (for the ball's flash there).
function fx.beam_muzzle_flash(follow, scale, locked, red)
	fire_light(follow, locked)

	local size = locked and CONFIG.muzzle_sparkle_size or CONFIG.muzzle_3rd_size
	local growth = locked and CONFIG.muzzle_sparkle_growth or CONFIG.muzzle_3rd_growth

	particles.sprite({
		attenuation = 0,
		color = red and RED or WHITE,
		fade_squared = true,
		follow = follow,
		locked = locked,
		growth = growth * utils.UT_SPRITE_SIDE * scale,
		life = locked and CONFIG.muzzle_sparkle_life or CONFIG.muzzle_3rd_life,
		size = size * utils.UT_SPRITE_SIDE * scale,
		spin = random_spin(),
		texture = "shock_sparkle",
	})
end

function fx.ball_muzzle_flash(follow, scale, locked, rotation)
	fire_light(follow, locked)

	if locked or not rotation then
		return
	end

	local life = CONFIG.ball_3rd_life
	local size = random_between(CONFIG.ball_3rd_size)

	-- (the mesh is made at 0.02 m a UT unit, so a scale of 1 is UT's size in the world; it points along its x, turned to the barrel)
	particles.mesh({
		brightness = function (fraction)
			return 1 - fraction
		end,
		color = CONFIG.ball_3rd_color,
		follow = follow,
		life = life,
		material = "units/ut/fx/fx_shock_muzflash_3rd",
		rotation = function ()
			local now = rotation()

			return now and Quaternion.multiply(now, Quaternion.axis_angle(Vector3(0, 0, 1), math.pi / 2)) or Quaternion.identity()
		end,
		scale = function (fraction)
			return (size + CONFIG.ball_3rd_growth * fraction * life) * scale / UNIT
		end,
		spin = 0,
		angle = math.random() * 360,
		spin_axis = Vector3(0, 1, 0),
		unit = "units/ut/fx/minigun_flash_3rd_mesh",
	})
end

-- What a beam makes where it hits a surface that faces the way `normal` points: flares, a ring, a core and a scorch mark.
local function impact(position, normal, red)
	local color = red and RED or WHITE
	local lifted = position + normal * (2 * UNIT)

	for _ = 1, CONFIG.impact_flare_count do
		particles.disc({
			attenuation = 0,
			color = color,
			fade_squared = true,
			growth = CONFIG.impact_flare_growth * SPRITE,
			life = CONFIG.impact_flare_life,
			normal = normal,
			position = lifted,
			size = random_between(CONFIG.impact_flare_size) * SPRITE,
			spin = random_spin(),
			texture = "shock_flare_a",
		})
	end

	particles.disc({
		attenuation = 0,
		color = color,
		fade_squared = true,
		growth = CONFIG.impact_ring_growth * SPRITE,
		life = CONFIG.impact_ring_life,
		normal = normal,
		position = lifted,
		size = CONFIG.impact_ring_size * SPRITE,
		spin = random_spin(),
		texture = "shock_ring_b",
	})
	particles.sprite({
		attenuation = 0,
		color = color,
		fade_squared = true,
		growth = CONFIG.impact_core_growth * SPRITE,
		life = CONFIG.impact_core_life,
		position = position + normal * (CONFIG.impact_core_offset * UNIT),
		size = CONFIG.impact_core_size * SPRITE,
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

-- The beam's coil (ShockBeamCoil) is pieces of a turning mesh along the beam.
local function coil(start, stop, red)
	local along = stop - start
	local length = Vector3.length(along)
	local direction = along * (1 / length)
	local up = math.abs(Vector3.dot(direction, Vector3.up())) > 0.99 and Vector3.right() or Vector3.up()
	local rotation = Quaternion.look(direction, up)
	local piece_length = CONFIG.coil_piece_length * UNIT
	local count = math.min(CONFIG.coil_max_pieces, math.ceil(length / piece_length))

	for i = 0, count - 1 do
		-- A vector can't be kept from one frame to the next, so the scale is made again each time it is asked for.
		local radius = CONFIG.coil_radius_scale * random_between(CONFIG.coil_size)
		-- The last piece is only as long as what is left of the beam, so the coil does not go past the end of the beam.
		local piece_scale = CONFIG.coil_length_scale * math.min(1, (length - i * piece_length) / piece_length)

		particles.mesh({
			brightness = function (fraction)
				return 1 - fraction
			end,
			color = red and RED_COIL or {
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

-- Draws the beam from `start` to `stop`, and what it makes where it hits a surface. `normal` is the zero vector if it hit nothing.
function fx.beam(start, stop, normal, red)
	local along = stop - start
	local length = Vector3.length(along)

	if length > 0.01 then
		coil(start, stop, red)

		-- The points: one every regen_dist, and the end
		local direction = along * (1 / length)
		local regen = CONFIG.beam_regen_dist * UNIT
		local points = {}

		for i = 0, math.floor(length / regen) do
			points[#points + 1] = Vector3Box(start + direction * (i * regen))
		end

		if length - (#points - 1) * regen > 0.001 then
			points[#points + 1] = Vector3Box(stop)
		end

		-- The axes across the line, as UE2 picks them (see the Link Gun's skin)
		local reference = math.abs(Vector3.z(direction)) > 0.57 and Vector3(1, 0, 0) or Vector3(0, 0, 1)
		local u_axis = Vector3.normalize(Vector3.cross(direction, reference))
		local v_axis = Vector3.cross(direction, u_axis)
		local born = Managers.time:time("game")
		local life = CONFIG.beam_life
		local low, high = CONFIG.beam_size[1] * UNIT, CONFIG.beam_size[2] * UNIT

		-- A strip has room for STRIP_POINTS points, so a long beam is drawn in pieces that share their ends
		local per_strip = particles.STRIP_POINTS - 1

		-- The Instagib beam is red and drawn twice, because SuperShockBeamEffect adds an ExtraRedBeam.
		for _ = 1, red and 2 or 1 do
			for plane = 1, CONFIG.beam_planes do
				local angle = (plane - 1) * math.pi / CONFIG.beam_planes
				local across = Vector3Box(v_axis * math.sin(angle) + u_axis * math.cos(angle))

				for first = 1, #points - 1, per_strip do
					local chunk = {}

					for i = first, math.min(first + per_strip, #points) do
						chunk[#chunk + 1] = points[i]
					end

					particles.strip({
						across = function ()
							local gone = math.min(1, (Managers.time:time("game") - born) / life)

							return across:unbox() * (low + (high - low) * gone * gone)
						end,
						brightness = function (fraction)
							local left = 1 - fraction

							return left * left * left * left
						end,
						color = red and RED or WHITE,
						life = life,
						points = function ()
							return chunk, #chunk
						end,
						size = 0,
						texture = "shock_beam",
					})
				end
			end
		end
	end

	if Vector3.length(normal) > 0.01 then
		impact(stop, Vector3.normalize(normal), red)
	end
end

-- The flying ball. new_ball makes the particles that last as long as the ball. update_ball makes the short-lived ones (the core, the
-- flares and the sparks) as the ball flies. `follow` is a function that returns the ball's position, or nothing once the ball is gone.
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

-- Makes the ball's short-lived particles for this frame. Returns false when the ball is gone.
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

		-- A spark goes out from the ball in a random direction. Its velocity is scaled down to the opposite of itself over the spark's
		-- life (VelocityScale), so it goes out and comes back to the ball, and it moves along with the ball.
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

-- The ball hits something and goes off. This makes a light, the dark sphere (ShockExplosion) and the core (ShockExplosionCore).
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
		brightness = function (fraction)
			return particles.exp_in_out(fraction, CONFIG.explosion_sphere_attenuation)
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
		fade_squared = true,
		growth = CONFIG.explosion_core_growth * SPRITE,
		life = CONFIG.explosion_core_life,
		position = position,
		size = CONFIG.explosion_core_size * SPRITE,
		texture = "shock_core",
	})
end

-- The combo's two meshes, as UT has them. The materials pan their textures themselves (see
-- tools/asset_conversion/make_combo_materials.py).
--   ShockComboSphereDark is a sphere, turned any way, with bolts that pan along it.
--   ShockComboVortex is a flat disc that always faces the camera, with lines that pan along it in a band.
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
		fade_squared = true,
		growth = CONFIG.combo_ring_growth * SPRITE,
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
		fade_squared = true,
		growth = CONFIG.combo_core_growth * SPRITE,
		life = CONFIG.combo_core_life,
		position = position,
		size = CONFIG.combo_core_size * SPRITE,
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
		attenuation = CONFIG.combo_flash_attenuation,
		color = WHITE,
		growth = CONFIG.combo_flash_growth * SPRITE,
		life = CONFIG.combo_flash_life,
		position = position,
		size = random_between(CONFIG.combo_flash_size) * SPRITE,
		spin = random_spin(),
		texture = "shock_combo_flash",
	})
end

-- Flares come at combo_flare_rate until combo_flare_time. Then two big ones come that shrink away.
local function combo_flares(position)
	local flares = math.floor(CONFIG.combo_flare_rate * CONFIG.combo_flare_time)

	for i = 0, flares - 1 do
		particles.sprite({
			attenuation = CONFIG.combo_flare_attenuation,
			color = WHITE,
			fade_squared = true,
			delay = i / CONFIG.combo_flare_rate,
			growth = CONFIG.combo_flare_growth * SPRITE,
			life = CONFIG.combo_flare_life,
			position = position,
			size = CONFIG.combo_flare_size * SPRITE,
			spin = random_spin(),
			texture = "shock_flare_a",
		})
	end

	for _ = 1, 2 do
		particles.sprite({
			attenuation = 0.9,
			color = WHITE,
			fade_squared = true,
			delay = CONFIG.combo_flare_time,
			growth = CONFIG.combo_big_flare_growth * SPRITE,
			life = CONFIG.combo_big_flare_life,
			position = position,
			size = CONFIG.combo_big_flare_size * SPRITE,
			spin = random_spin(),
			texture = "shock_flare_a",
		})
	end
end

local function combo_wiggles(position)
	for _ = 1, CONFIG.combo_wiggle_count do
		-- ShockComboWiggles' particles are discs that UT draws square to the view. They are sprites here, because discs fixed in
		-- one direction looked like lines.
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
			size = CONFIG.combo_wiggle_size * SPRITE,
			texture = "shock_sparkle",
			velocity = random_direction() * (CONFIG.combo_wiggle_speed * UNIT),
		})
	end
end

-- Draws the combo (ShockCombo): the ring, the core, the flash, the lights, the flares, the wiggles, the sphere and the vortex. UT's
-- ComboDecal, the mark on the floor, is not made. A flat disc only works on a flat floor, and the game's own effects that leave a mark
-- are whole effects.
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
