local mod = get_mod("unreal_tournament")

-- UT2004's effects where a bullet hits a wall (mod.hit_effects), which the weapon skins draw with mod.skin_particles:
--   hit_effects.wall_sparks(position, normal): WallSparks, the sparks of xHeavyWallHitEffect (the Minigun's primary fire) and of the
--       Sniper Rifle's SniperWallHitEffect.
--   hit_effects.impact_smoke(position, normal): pclImpactSmoke, the puffs of xHeavyWallHitEffect and ExploWallHit.
--   hit_effects.small_explosion(position, normal): SmallExplosion, the fire of ExploWallHit (the Minigun's alt fire).
-- They are xEmitters, drawn as Engine.dll draws them (decompiled): a sprite is a square turned 45 degrees, utils.UT_SPRITE_SIDE times
-- its size (mSizeRange) on a side, a particle is mColorRange times its fade (ScaleGlow does nothing to it), and it fades in until
-- mAttenKa of its life and out after (0.2 unless the class sets it). They start as xEmitter starts them (utils.ut_particle_velocity),
-- off the surface's normal. The air slows them by mAirResistance of their speed a second. The textures were made with
-- tools/asset_conversion (split_spark.py for the sparks, make_weapon_fx.py for the smoke and the fire).

local utils = mod.utils
local particles = mod.skin_particles

local CONFIG = {
	-- WallSparks: 8 lines at once (particles.line), 0.5 to 0.8 s long, flying at 50 to 300 units a second off the surface, spread by 0.6
	-- on each axis (mDirDev), up to 0.8 units out of place, 6 to 4 units wide (mSizeRange 3 to 2), shrinking by 8 a second, 0.03 s of
	-- their travel long (mSpawnVecB.Z) with a head of mSpawnVecB.X 5, dimming from the start, added. They fall by their mass of 1.5 to
	-- 2.5.
	spark_count = 8,
	spark_life = { 0.5, 0.8 },
	spark_speed = { 50, 300 },
	spark_spread = 0.6,
	spark_position_spread = 0.8,
	spark_width = { 6, 4 }, -- UT units across
	spark_growth = -8, -- UT units across, a second
	spark_length = 0.03, -- seconds of travel
	spark_head = 5, -- mSpawnVecB.X
	spark_mass = { 1.5, 2.5 },
	-- pclImpactSmoke: 7 puffs, each after up to 0.1 s (mDelayRange), for 0.5 to 1.5 s, flying at 10 to 60 units a second off the surface,
	-- spread by 0.15 on each axis, up to 8 units out of place, of size 10 to 25, turned at random, with a random
	-- tile of EmitSmoke_t. They are STY_Translucent (c + d * (1 - c)) and dark: mColorRange 20 to 40 of 255.
	smoke_count = 7,
	smoke_delay = { 0, 0.1 },
	smoke_life = { 0.5, 1.5 },
	smoke_speed = { 10, 60 },
	smoke_spread = 0.15,
	smoke_position_spread = 8, -- UT units
	smoke_size = { 10, 25 }, -- mSizeRange
	smoke_tiles = 16,
	smoke_brightness = { 20 / 255, 40 / 255 },
	-- SmallExplosion: a RocketExplosion of 4 pieces of fire (Rexpt), for 0.5 to 1 s, drifting at 3 to 10 units a second any way off the
	-- surface (mDirDev 1 on each axis), of size 20 to 40, turned at random, added
	explosion_count = 4,
	explosion_life = { 0.5, 1 },
	explosion_speed = { 3, 10 },
	explosion_spread = 1,
	explosion_size = { 20, 40 }, -- mSizeRange
	-- The puffs' and the fire's mAttenKa, and their mAirResistance
	attenuation = 0.2,
	air_resistance = 0.4, -- of the speed, a second
}

local UNIT = utils.UT_UNIT
-- (the meters across a sprite for each unit of an xEmitter's size)
local SPRITE = utils.UT_SPRITE_SIDE * UNIT

local random_between = utils.random_between

local hit_effects = {}
mod.hit_effects = hit_effects

-- A velocity off the normal, as an xEmitter starts one (utils.ut_particle_velocity): speed in UT units a second, spread its mDirDev
local function deviated(normal, spread, speed)
	return utils.ut_particle_velocity(normal, spread, speed * UNIT)
end

-- The position moved as an xEmitter moves a particle's place (utils.ut_particle_offset): spread is its mPosDev, in UT units
local function scattered(position, spread)
	return position + utils.ut_particle_offset(spread) * UNIT
end

-- The sparks where the bullet hits, off the surface
function hit_effects.wall_sparks(position, normal)
	for _ = 1, CONFIG.spark_count do
		particles.line({
			attenuation = 0,
			fall = utils.UT_PARTICLE_GRAVITY * random_between(CONFIG.spark_mass) * UNIT,
			growth = CONFIG.spark_growth * UNIT,
			head_size = CONFIG.spark_head * SPRITE,
			length = CONFIG.spark_length,
			life = random_between(CONFIG.spark_life),
			position = scattered(position, CONFIG.spark_position_spread),
			size = random_between(CONFIG.spark_width) * UNIT,
			texture = "wall_spark",
			velocity = deviated(normal, CONFIG.spark_spread, random_between(CONFIG.spark_speed)),
		})
	end
end

-- The dark puffs of dust that drift off the surface
function hit_effects.impact_smoke(position, normal)
	for _ = 1, CONFIG.smoke_count do
		particles.sprite({
			-- (STY_Translucent: its material brightens what is behind it by its luminance, see make_combo_materials.py, with no added
			-- part of its own)
			additive = 0,
			attenuation = CONFIG.attenuation,
			color = { 1, 1, 1 },
			delay = random_between(CONFIG.smoke_delay),
			drag = CONFIG.air_resistance,
			intensity = random_between(CONFIG.smoke_brightness),
			life = random_between(CONFIG.smoke_life),
			position = scattered(position, CONFIG.smoke_position_spread),
			size = random_between(CONFIG.smoke_size) * SPRITE,
			texture = "impact_smoke_" .. math.random(0, CONFIG.smoke_tiles - 1),
			velocity = deviated(normal, CONFIG.smoke_spread, random_between(CONFIG.smoke_speed)),
		})
	end
end

-- The fire of a small explosion on the surface
function hit_effects.small_explosion(position, normal)
	for _ = 1, CONFIG.explosion_count do
		particles.sprite({
			attenuation = CONFIG.attenuation,
			drag = CONFIG.air_resistance,
			life = random_between(CONFIG.explosion_life),
			position = position,
			size = random_between(CONFIG.explosion_size) * SPRITE,
			texture = "small_explosion",
			velocity = deviated(normal, CONFIG.explosion_spread, random_between(CONFIG.explosion_speed)),
		})
	end
end
