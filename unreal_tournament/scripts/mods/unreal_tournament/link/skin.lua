local mod = get_mod("unreal_tournament")

-- Link Gun skin (the Weapon Skins setting): the Link Gun is UT2004's, in the player's own first person view and in the hand of every
-- character. The model (NewWeapons2004.FatLinkGun), its placement and animations, the bob and the third person are weapon_skin.lua's;
-- this file is what is the Link Gun's: the flash, the plasma bolts (the staff's thorns, as they fly), the beam (the curve that the gun draws
-- from its muzzle to what it is linked to, as UT's beam texture), and the sounds. The gameplay is link_gun.lua's, this only draws it
-- differently, and is told what happens through the hook tables of hooks.lua (link_beam_callbacks for the beam).
--
-- The assets were made with unreal_tournament/tools/asset_conversion.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local animations = mod:dofile("scripts/mods/unreal_tournament/link/skin_animations")
local particles = mod.skin_particles

local TEMPLATE_NAME = "staff_life"
local SETTING_ID = "link_gun"

local CONFIG = {
	meters_per_uu = 0.02, -- the Unreal unit of the world, in meters (a player is 88 units high)
	-- LinkMuzFlash (the flash of a shot)
	muzzle_size = 45,
	muzzle_growth = 100,
	muzzle_life = 0.1,
	-- LinkProjectile: a green bolt (a mesh with a flare), here sprites that follow the thorn of the game
	bolt_size = 40,
	bolt_glow_size = 70,
	bolt_color = {
		0.5,
		1,
		0.4,
	},
	-- LinkBeamEffect: the beam is the texture of the beam on each stretch of the curve, green, and gold while something is linked
	beam_width = 0.18, -- m
	beam_life = 0.06, -- seconds (it is made again every frame)
	beam_sound_seconds = 1.26, -- how long the sound of the beam (BLinkGunBeam) is
	end_flare_size = 60,
	-- A shot that another player's machine sees: more than this far apart in time is another shot
	shot_gap = 0.1,
}

local UNIT = CONFIG.meters_per_uu

local skin_api

local last_remote_shot = {}
-- When the sound of each beam is played again, by the state of the beam
local beam_sound_time = setmetatable({}, {
	__mode = "k",
})

-- A flash at the muzzle (where the character holds the mesh, or the model of the player's own view)
local function muzzle_flash(follow, scale)
	particles.sprite({
		color = {
			0.6,
			1,
			0.5,
		},
		follow = follow,
		growth = CONFIG.muzzle_growth * scale,
		life = CONFIG.muzzle_life,
		size = CONFIG.muzzle_size * scale,
		spin = (math.random() * 2 - 1) * 0.2,
		texture = "link_muz_green",
	})
end

skin_api = mod.weapon_skin.new({
	id = SETTING_ID,
	name = "link",
	template = TEMPLATE_NAME,
	unit_name = "units/ut/link/link_gun",
	animations = animations,
	muzzle_node = "b_bone_flasha",
	model_meters_per_unit = 0.0125,
	meters_per_unit = 0.01,
	-- LinkGun.uc
	display_fov = 60,
	draw_scale = 1,
	offset_forward = -5,
	offset_right = -3,
	offset_up = 0,
	pivot_yaw = 500 / 65536 * 360,
	bob_damping = 1.575,
	-- WeaponStaticMesh.LinkGunPickup: its barrel is along the mesh's own -Y, the grip is under the middle of it
	third_person = {
		id = SETTING_ID,
		template = TEMPLATE_NAME,
		unit_name = "units/ut/link/pickup",
		-- (the game links the Deepwood Staff to the left hand's node, AttachmentNodeLinking.one_handed_melee_weapon.left)
		hand_node = "j_leftweaponattach",
		meters_per_unit = 0.012,
		scale = 0.6,
		grip_right = -21,
		grip_forward = 0,
		grip_up = -30,
		yaw = 90,
		pitch = 0,
		roll = 0,
		muzzle_right = 54,
		muzzle_forward = 0,
		muzzle_up = 3,
	},
	on_create = function ()
		skin_api.play_sound("ut_link_select")
	end,
	on_level_exit = function ()
		table.clear(last_remote_shot)
	end,
})

local third_person = skin_api.third_person

-- The flow events of the game's units of the thorns start their effects as they are made: not while the skin is on
mod.init_flow_event_filters.link = function (event_name)
	return skin_api.enabled() and (event_name == "lua_projectile_init" or event_name == "lua_trail" or event_name == "vfx_critical_strike")
end

-- A bolt (on every machine): a green blob and its glow follow the game's thorn; the shot of the player is the animation, the flash and the
-- sound, the shot that is seen of another player is the flash and the sound from their mesh
mod.skin_init_callbacks.link_bolt = function (projectile)
	if not skin_api.enabled() then
		return
	end

	local game_unit = projectile._projectile_unit
	local owner_unit = projectile._owner_unit

	Unit.set_unit_visibility(game_unit, false)

	local function follow()
		if Unit.alive(game_unit) and not projectile._stop_impacts then
			return Unit.world_position(game_unit, 0)
		end
	end

	particles.sprite({
		color = CONFIG.bolt_color,
		fade_in = 0,
		follow = follow,
		life = 10,
		size = CONFIG.bolt_size * UNIT,
		spin = 0.2,
		texture = "link_muz_green",
	})
	particles.sprite({
		color = CONFIG.bolt_color,
		fade_in = 0,
		follow = follow,
		intensity = 0.5,
		life = 10,
		size = CONFIG.bolt_glow_size * UNIT,
		texture = "muzzle_white",
	})

	if utils.is_local_player_unit(owner_unit) then
		local skin = skin_api.state()

		if skin then
			local in_third_person = third_person.shows_weapon(owner_unit)

			skin_api.play("Fire")
			skin_api.play_sound("ut_link_fire")
			muzzle_flash(function ()
				if in_third_person then
					return third_person.muzzle_position(owner_unit)
				end

				return skin_api.state() == skin and skin_api.muzzle_position() or nil
			end, in_third_person and third_person.meters_per_unit or skin.unit_scale)
		end
	else
		local now = Managers.time:time("game")

		if not last_remote_shot[owner_unit] or now - last_remote_shot[owner_unit] >= CONFIG.shot_gap then
			last_remote_shot[owner_unit] = now

			muzzle_flash(function ()
				return third_person.muzzle_position(owner_unit)
			end, third_person.meters_per_unit)
			skin_api.play_sound_at("ut_link_fire_3d", Unit.world_position(game_unit, 0))
		end
	end
end

-- The beam starts: the animation of the alt fire
mod.charge_start_callbacks.link_skin = function (action, new_action)
	if new_action.ut_charge_callback == "link" and skin_api.state() and utils.is_local_player_unit(action.owner_unit) then
		skin_api.play("AltFire")
	end
end

-- Where the beam starts: the end of the barrel of the model of the player's own view, or of the mesh in the hand of the character
mod.link_beam_callbacks.start_position = function (owner_unit)
	if utils.is_local_player_unit(owner_unit) and skin_api.state() and not third_person.shows_weapon(owner_unit) then
		return skin_api.muzzle_position()
	end

	return third_person.muzzle_position(owner_unit)
end

-- The beam: the texture of UT's beam on every stretch of the curve, drawn again each frame, and a flare where it ends, and its sound,
-- played again as it ends (it is a loop in UT)
mod.link_beam_callbacks.draw = function (state, points, count)
	local linked = state.linked or state.target ~= nil
	local texture = linked and "link_beam_yellow" or "link_beam_green"
	local now = Managers.time:time("game")

	for i = 1, count - 1 do
		particles.beam({
			from = points[i],
			life = CONFIG.beam_life,
			size = CONFIG.beam_width,
			texture = texture,
			to = points[i + 1],
		})
	end

	particles.sprite({
		color = linked and {
			1,
			0.9,
			0.4,
		} or CONFIG.bolt_color,
		life = CONFIG.beam_life,
		position = points[count],
		size = CONFIG.end_flare_size * UNIT,
		texture = linked and "link_ring_yellow" or "link_ring_green",
	})

	if not beam_sound_time[state] or now >= beam_sound_time[state] then
		beam_sound_time[state] = now + CONFIG.beam_sound_seconds

		if state.received then
			skin_api.play_sound_at("ut_link_beam_3d", points[1])
		else
			skin_api.play_sound("ut_link_beam")
		end
	end
end
