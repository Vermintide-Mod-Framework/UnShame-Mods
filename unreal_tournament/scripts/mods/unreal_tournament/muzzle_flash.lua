local mod = get_mod("unreal_tournament")

-- UT's MinigunMuzFlash1st, the first person flash of the Minigun. UT's AssaultMuzFlash1st is the same emitter at another DrawScale,
-- and the Assault Rifle and the classic Sniper Rifle (ClassicSniperFire.FlashEmitterClass) use it. The Rocket Launcher's
-- RocketMuzFlash1st draws the same mesh with numbers of its own. The skins share this.
--   mod.muzzle_flash(emitter, follow, world_unit, draw_scale, locked, emitter_settings): shows the flash of one round. emitter is any
--       value that names the weapon's flash, which has room for a round's meshes of its own. follow returns the muzzle's position, or nil once
--       the flash should end. world_unit is the meters of a UT unit at the model. draw_scale is the emitter's DrawScale. locked, if it is
--       given, is used instead of follow: it returns the first person unit and the muzzle in its camera node's frame
--       (weapon_skin's model_point_in_view), so the flash is linked to the unit and stays on the muzzle as the view turns, as UT's is
--       attached to the weapon. emitter_settings, if it is given, are the numbers of another emitter that draws the same mesh, in the
--       form of CONFIG's (the Rocket Launcher's RocketMuzFlash1st). They can also name another mesh (unit), its materials (material:
--       the name of the first tile's material without its number), whether a mesh keeps the tile it starts at (still_tiles), how many
--       meshes the emitter has room for (max) (the Link Gun's LinkMuzFlashProj1st). tiles is how many tiles the material has (4 if not
--       given; with 1, material is the whole name). angle (degrees) is the turn about the barrel, for an emitter that doesn't turn its
--       meshes at random (mRandOrient).
-- All of these flashes are FinalBlends of FB_Brighten, which UE2 draws as the colour times the texture's alpha, added (D3DDrv.dll,
-- decompiled). An xEmitter's mesh is lit by its colour times its fade, as the ambient light, and by no other light: FDynamicActor::Render
-- doesn't give an xEmitter the lights near it (Engine.dll and D3DDrv.dll, decompiled). The texture's alpha is left as it is, so a mesh
-- fades once.
-- UT adds in gamma space and the game in linear space. Over the lit scene a flash is seen on, adding a little in gamma space is about
-- the same as adding it in linear space, so the colour and the fade are used as they are.

local utils = mod.utils
local particles = mod.skin_particles
local random_between = utils.random_between
local attenuation = particles.attenuation

local UNIT = utils.UT_UNIT

local CONFIG = {
	-- 5 meshes (MinigunMuzFlash1stMesh) at the muzzle for every round (mNumPerFlash), turned at random about the barrel, each lasting
	-- 0.1 to 0.15 seconds. A mesh's scale starts at 0.05 to 0.08 and grows by 3 a second (mSizeRange, mGrowthRate), times the
	-- emitter's DrawScale. It brightens until 0.2 of its life and dims after (mAttenKa). (It was once drawn at half its size: blended as
	-- FB_Translucent, which leaves out the alpha of Minigun_burst, 0 to 97 of 255, the whole texture showed, twice as wide as in pictures
	-- of UT2004.)
	count = 5,
	scale = {0.05, 0.08},
	growth = 3, -- scale a second
	life = {0.1, 0.15},
	attenuation = 0.2,
	color = { 1, 1, 1 }, -- mColorRange, of 255
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
	local factor = world_unit / UNIT * draw_scale

	local material = settings.material or "units/ut/fx/fx_weapon_minigun_burst_"
	local tiles = settings.tiles or TILES

	for _ = 1, math.min(settings.count, (settings.max or settings.count) - #ends) do
		local tile = math.random(0, tiles - 1)
		local life = random_between(settings.life)
		local start = random_between(settings.scale)

		ends[#ends + 1] = now + life

		particles.mesh({
			additive = 1,
			brightness = function (fraction)
				return attenuation(fraction, settings.attenuation)
			end,
			color = settings.color,
			follow = not locked and follow or nil,
			locked = locked or nil,
			life = life,
			material = tiles > 1 and material .. tile or material,
			material_by = tiles > 1 and not settings.still_tiles and function (fraction)
				return material .. (tile + math.min(math.floor(fraction * tiles), tiles - 1)) % tiles
			end or nil,
			rotation = rotation,
			scale = function (fraction)
				return (start + settings.growth * fraction * life) * factor
			end,
			spin = 0,
			-- (turned at random about the barrel, or not at all for an emitter without mRandOrient: settings.angle 0)
			angle = settings.angle or math.random() * 360,
			spin_axis = Vector3(0, 1, 0),
			unit = settings.unit or "units/ut/fx/minigun_flash_mesh",
		})
	end
end
