local mod = get_mod("unreal_tournament")

-- UT's MinigunMuzFlash1st, the first person flash of the Minigun. UT's AssaultMuzFlash1st is the same emitter at another DrawScale,
-- and the Assault Rifle and the classic Sniper Rifle (ClassicSniperFire.FlashEmitterClass) use it, so the three skins share this.
--   mod.minigun_muzzle_flash(emitter, follow, world_unit, draw_scale): shows the flash of one round. emitter is any value that names
--       the weapon's flash, so that each weapon's rounds replace only its own. follow returns the muzzle's position, or nil once the
--       flash should end. world_unit is the meters of a UT unit at the model. draw_scale is the emitter's DrawScale.

local utils = mod.utils
local particles = mod.skin_particles
local random_between = utils.random_between
local attenuation = particles.attenuation

local UNIT = utils.UT_UNIT

local CONFIG = {
	-- 5 meshes (MinigunMuzFlash1stMesh) at the muzzle for every round (mNumPerFlash), turned at random about the barrel, each lasting
	-- 0.1 to 0.15 seconds. A mesh's scale starts at 0.05 to 0.08 and grows by 3 a second (mSizeRange, mGrowthRate), times the
	-- emitter's DrawScale. It brightens until 0.2 of its life and dims after (mAttenKa).
	count = 5,
	scale = {0.05, 0.08},
	growth = 3, -- scale a second
	life = {0.1, 0.15},
	attenuation = 0.2,
	-- How xEmitter scales a mesh particle by its size is in UT's engine, not its scripts. The numbers above drew the flash twice as
	-- wide as pictures of UT2004 show it, so they are multiplied by this (fitted to those pictures).
	fit = 0.5,
}

-- The emitter has room for 5 meshes (mMaxParticles), as many as a round makes, so a round's meshes end when the next round's start.
-- This counts each emitter's rounds.
local rounds = {}

-- The flash is drawn with the model, in the material that uses the model's field of view (fx_weapon_*), so it is in front of the
-- barrels and not hidden by them. The texture is a sheet of 4 that UT picks from at random (mRandTextures). A mesh here keeps one of
-- them for its whole life, where UT also steps through them (mTileAnimation).
function mod.minigun_muzzle_flash(emitter, follow, world_unit, draw_scale)
	local _, camera_rotation = utils.camera_pose()

	if not camera_rotation then
		return
	end

	local round = (rounds[emitter] or 0) + 1

	rounds[emitter] = round

	-- The mesh is made at 0.02 m per UT unit
	local factor = world_unit / UNIT * draw_scale * CONFIG.fit

	for _ = 1, CONFIG.count do
		local tile = math.random(0, 3)
		local life = random_between(CONFIG.life)
		local start = random_between(CONFIG.scale)

		particles.mesh({
			-- FB_Brighten: the texture holds the hue and its alpha the strength (make_weapon_fx.py), so it is blended, not added
			additive = 0,
			brightness = function (fraction)
				return attenuation(fraction, CONFIG.attenuation)
			end,
			color = { 1, 1, 1 },
			follow = function ()
				return rounds[emitter] == round and follow() or nil
			end,
			life = life,
			material = "units/ut/fx/fx_weapon_minigun_burst_" .. tile,
			rotation = camera_rotation,
			scale = function (fraction)
				return (start + CONFIG.growth * fraction * life) * factor
			end,
			spin = 0,
			angle = math.random() * 360,
			spin_axis = Vector3(0, 1, 0),
			unit = "units/ut/fx/minigun_flash_mesh",
		})
	end
end
