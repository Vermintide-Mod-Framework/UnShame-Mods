local mod = get_mod("unreal_tournament")

-- UT's MinigunMuzFlash1st, the first person flash of the Minigun. UT's AssaultMuzFlash1st is the same emitter at another DrawScale,
-- and the Assault Rifle and the classic Sniper Rifle (ClassicSniperFire.FlashEmitterClass) use it. The Rocket Launcher's
-- RocketMuzFlash1st draws the same mesh with numbers of its own. The four skins share this.
--   mod.muzzle_flash(emitter, follow, world_unit, draw_scale, locked, emitter_settings): shows the flash of one round. emitter is any
--       value that names the weapon's flash, which has room for a round's meshes of its own. follow returns the muzzle's position, or nil once
--       the flash should end. world_unit is the meters of a UT unit at the model. draw_scale is the emitter's DrawScale. locked, if it is
--       given, is used instead of follow: it returns the first person unit and the muzzle in its camera node's frame
--       (weapon_skin's model_point_in_view), so the flash is linked to the unit and stays on the muzzle as the view turns, as UT's is
--       attached to the weapon. emitter_settings, if it is given, are the numbers of another emitter that draws the same mesh, in the
--       form of CONFIG's (the Rocket Launcher's RocketMuzFlash1st).

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
	color = { 1, 1, 1 }, -- mColorRange, of 255
	-- How xEmitter scales a mesh particle by its size is in UT's engine, not its scripts. The numbers above drew the flash twice as
	-- wide as pictures of UT2004 show it, so they are multiplied by this (fitted to those pictures, and checked again side by side).
	-- This flash gets most of its size from growing, as the Rocket Launcher's third person one does, which also looks right halved.
	-- The Rocket Launcher's first person flash does not grow and is drawn at its size as it is, so the halving is probably how UT
	-- grows a particle.
	fit = 0.5,
}

-- The emitter has room for 5 meshes (mMaxParticles). A round asks for 5 more (MinigunMuzFlash1st.Trigger), and gets as many as there is
-- room for: the meshes that are there live out their life. This keeps when each emitter's meshes end.
local mesh_ends = {}

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(mesh_ends)
end

-- The flash is drawn with the model, in the material that uses the model's field of view (fx_weapon_*), so it is in front of the
-- barrels and not hidden by them. The texture is a sheet of 4 (mNumTileColumns and mNumTileRows 2): a mesh starts at one of them at
-- random (mRandTextures) and steps through them over its life (mTileAnimation).
local TILES = 4
function mod.muzzle_flash(emitter, follow, world_unit, draw_scale, locked, emitter_settings)
	local settings = emitter_settings or CONFIG
	local _, camera_rotation = utils.camera_pose()

	if not camera_rotation then
		return
	end

	-- A linked mesh is turned in the camera node's frame, where it faces ahead as it is
	local rotation = locked and Quaternion.identity() or camera_rotation

	local now = Managers.time:time("game")
	local ends = mesh_ends[emitter] or {}

	mesh_ends[emitter] = ends

	for i = #ends, 1, -1 do
		if ends[i] <= now then
			table.remove(ends, i)
		end
	end

	-- The mesh is made at 0.02 m per UT unit
	local factor = world_unit / UNIT * draw_scale * settings.fit

	for _ = 1, settings.count - #ends do
		local tile = math.random(0, 3)
		local life = random_between(settings.life)
		local start = random_between(settings.scale)

		ends[#ends + 1] = now + life

		particles.mesh({
			-- (FB_Brighten: its material brightens what is behind it as FB_Brighten does, see make_combo_materials.py, with no added part
			-- of its own)
			additive = 0,
			brightness = function (fraction)
				return attenuation(fraction, settings.attenuation)
			end,
			color = settings.color,
			follow = not locked and follow or nil,
			locked = locked or nil,
			life = life,
			material = "units/ut/fx/fx_weapon_minigun_burst_" .. tile,
			material_by = function (fraction)
				return "units/ut/fx/fx_weapon_minigun_burst_" .. (tile + math.min(math.floor(fraction * TILES), TILES - 1)) % TILES
			end,
			rotation = rotation,
			scale = function (fraction)
				return (start + settings.growth * fraction * life) * factor
			end,
			spin = 0,
			angle = math.random() * 360,
			spin_axis = Vector3(0, 1, 0),
			unit = "units/ut/fx/minigun_flash_mesh",
		})
	end
end
