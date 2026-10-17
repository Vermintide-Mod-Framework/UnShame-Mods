local mod = get_mod("unreal_tournament")

-- UT2004's effects where a bullet hits a wall (mod.hit_effects), which the weapon skins draw with mod.skin_particles:
--   hit_effects.wall_sparks(position, normal): WallSparks, the sparks of xHeavyWallHitEffect (the Minigun's primary fire) and of the
--       Sniper Rifle's SniperWallHitEffect.
--   hit_effects.impact_smoke(position, normal): pclImpactSmoke, the puffs of xHeavyWallHitEffect and ExploWallHit.
--   hit_effects.small_explosion(position, normal): SmallExplosion, the fire of ExploWallHit (the Minigun's alt fire).
-- They are xEmitters, whose code is not in UT's source: a particle's size (mSizeRange) is taken as half its width, as a UE2 sprite's
-- size is its radius, and it fades out from mAttenKa of its life (0.2 unless the class sets it). Their directions are the surface's
-- normal turned by a random share of mDirDev on each axis, and their places are moved by a random share of mPosDev.
-- The textures were made with tools/asset_conversion (make_fx_assets.py and split_spark.py for the sparks, make_weapon_fx.py for the
-- smoke and the fire).

local utils = mod.utils
local particles = mod.skin_particles

local CONFIG = {
	-- WallSparks: 8 lines at once, 0.5 to 0.8 s long, flying at 50 to 300 units a second off the surface, spread by 0.6 on each axis
	-- (mDirDev), up to 0.8 units out of place, 3 to 2 units wide (half widths, shrinking by 4 a second), 0.05 s of their travel long
	-- (mSpawnVecB.X 5), dimming from the start, added, twice as bright as the texture (ScaleGlow). They fall: the zone's gravity is used
	-- for all of them, without their mass.
	spark_count = 8,
	spark_life = { 0.5, 0.8 },
	spark_speed = { 50, 300 },
	spark_spread = 0.6,
	spark_position_spread = 0.8,
	spark_width = { 6, 4 }, -- UT units across
	spark_growth = -8, -- UT units across, a second
	spark_length = 0.05, -- seconds of travel
	spark_intensity = 2,
	spark_gravity = 950, -- UT units a second squared
	-- pclImpactSmoke: 7 puffs, each after up to 0.1 s (mDelayRange), for 0.5 to 1.5 s, flying at 10 to 60 units a second off the surface,
	-- spread by 0.15 on each axis, up to 8 units out of place, 10 to 25 units in size (20 to 50 across), turned at random, with a random
	-- tile of EmitSmoke_t. They are STY_Translucent (c + d * (1 - c)) and dark: mColorRange 20 to 40 of 255, twice that (ScaleGlow).
	smoke_count = 7,
	smoke_delay = { 0, 0.1 },
	smoke_life = { 0.5, 1.5 },
	smoke_speed = { 10, 60 },
	smoke_spread = 0.15,
	smoke_position_spread = 8, -- UT units
	smoke_size = { 10, 25 }, -- UT units (half widths)
	smoke_tiles = 16,
	smoke_brightness = { 20 / 255 * 2, 40 / 255 * 2 },
	-- SmallExplosion: a RocketExplosion of 4 pieces of fire (Rexpt), for 0.5 to 1 s, drifting at 3 to 10 units a second any way off the
	-- surface (mDirDev 1 on each axis), 20 to 40 units in size (40 to 80 across), turned at random, added
	explosion_count = 4,
	explosion_life = { 0.5, 1 },
	explosion_speed = { 3, 10 },
	explosion_spread = 1,
	explosion_size = { 20, 40 }, -- UT units (half widths)
	-- xEmitter's mAttenKa: the share of a particle's life after which it fades
	attenuation = 0.2,
}

local UNIT = utils.UT_UNIT

local random_between = utils.random_between

local hit_effects = {}
mod.hit_effects = hit_effects

-- The normal turned by a random share of spread on each axis
local function deviated(normal, spread)
	return Vector3.normalize(normal + Vector3(random_between({ -spread, spread }), random_between({ -spread, spread }), random_between({ -spread, spread })))
end

-- A random place within spread (UT units) of the position on each axis
local function scattered(position, spread)
	return position + Vector3(random_between({ -1, 1 }), random_between({ -1, 1 }), random_between({ -1, 1 })) * (spread * UNIT)
end

-- The sparks where the bullet hits, off the surface. Each is a line along its way (the body of the texture) with a glow at its front.
function hit_effects.wall_sparks(position, normal)
	local now = Managers.time:time("game")

	for _ = 1, CONFIG.spark_count do
		local start = Vector3Box(scattered(position, CONFIG.spark_position_spread))
		local velocity = Vector3Box(deviated(normal, CONFIG.spark_spread) * (random_between(CONFIG.spark_speed) * UNIT))
		local fall = CONFIG.spark_gravity * UNIT
		local width = random_between(CONFIG.spark_width) * UNIT
		local life = random_between(CONFIG.spark_life)

		-- Returns where the spark's head is, and where its tail is
		local function spark()
			local age = Managers.time:time("game") - now
			local moving = velocity:unbox() - Vector3(0, 0, fall * age)
			local head = start:unbox() + velocity:unbox() * age - Vector3(0, 0, 0.5 * fall * age * age)
			local speed = Vector3.length(moving)
			local heading = speed > 0.001 and moving * (1 / speed) or Vector3.up()

			return head, head - heading * math.max(width, speed * CONFIG.spark_length)
		end

		particles.beam({
			attenuation = 0,
			growth = CONFIG.spark_growth * UNIT,
			intensity = CONFIG.spark_intensity,
			life = life,
			size = width,
			texture = "wall_spark_body",
			track = function ()
				local head, tail = spark()

				return tail, head
			end,
		})
		particles.sprite({
			angle = 0,
			attenuation = 0,
			follow = function ()
				return (spark())
			end,
			growth = CONFIG.spark_growth * UNIT,
			intensity = CONFIG.spark_intensity,
			life = life,
			size = width,
			texture = "wall_spark_head",
		})
	end
end

-- The dark puffs of dust that drift off the surface
function hit_effects.impact_smoke(position, normal)
	for _ = 1, CONFIG.smoke_count do
		particles.sprite({
			-- (the texture holds the hue and its alpha the strength, see make_weapon_fx.py, so it is blended, not added)
			additive = 0,
			attenuation = CONFIG.attenuation,
			color = { 1, 1, 1 },
			delay = random_between(CONFIG.smoke_delay),
			intensity = random_between(CONFIG.smoke_brightness),
			life = random_between(CONFIG.smoke_life),
			position = scattered(position, CONFIG.smoke_position_spread),
			size = 2 * random_between(CONFIG.smoke_size) * UNIT,
			texture = "impact_smoke_" .. math.random(0, CONFIG.smoke_tiles - 1),
			velocity = deviated(normal, CONFIG.smoke_spread) * (random_between(CONFIG.smoke_speed) * UNIT),
		})
	end
end

-- The fire of a small explosion on the surface
function hit_effects.small_explosion(position, normal)
	for _ = 1, CONFIG.explosion_count do
		particles.sprite({
			attenuation = CONFIG.attenuation,
			life = random_between(CONFIG.explosion_life),
			position = position,
			size = 2 * random_between(CONFIG.explosion_size) * UNIT,
			texture = "small_explosion",
			velocity = deviated(normal, CONFIG.explosion_spread) * (random_between(CONFIG.explosion_speed) * UNIT),
		})
	end
end
