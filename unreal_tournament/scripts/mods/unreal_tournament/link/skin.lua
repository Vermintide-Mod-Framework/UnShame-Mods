local mod = get_mod("unreal_tournament")

-- Link Gun skin: how UT2004's Link Gun looks and sounds.
--
-- weapon_skin.lua does the model, its placement and animations, the bob and the third person. This file does what is the Link Gun's own:
-- the flash, the bolts in flight, the beam and the sounds. The gameplay is in link_gun.lua. This file only draws it, and is told what
-- happens through the hook tables in hooks.lua (link_beam_callbacks for the beam).
--
-- The assets were made with tools/asset_conversion.

local utils = mod.utils
local animations = mod:dofile("scripts/mods/unreal_tournament/link/skin_animations")
local particles = mod.skin_particles

local TEMPLATE_NAME = mod.items.weapons.link_gun.template
local SETTING_ID = "link_gun"

local CONFIG = {
	-- LinkMuzFlash is the flash of a shot.
	muzzle_size = 45,
	muzzle_growth = 100,
	muzzle_life = 0.1,
	-- LinkProjectile is a green bolt, a mesh with a flare. Here it is sprites that follow the game's thorn.
	bolt_size = 40,
	bolt_glow_size = 70,
	bolt_color = {
		0.5,
		1,
		0.4,
	},
	-- LinkBeamEffect: the beam is the beam texture on each stretch of the curve. It is green, and gold while something is linked.
	beam_width = 0.18, -- m
	beam_life = 0.06, -- seconds. The beam is made again every frame.
	beam_sound_seconds = 1.26, -- length of the beam's sound (BLinkGunBeam)
	end_flare_size = 60,
	-- Bolts of another player that start less than this far apart (in seconds) belong to the same shot
	shot_gap = 0.1,
}

local UNIT = utils.UT_UNIT

local skin_api

local remote_shots = utils.shot_grouping(CONFIG.shot_gap)

-- The time at which each beam's sound is played again, for each beam state
local beam_sound_time = setmetatable({}, {
	__mode = "k",
})

-- Shows a flash at the muzzle, either of the mesh in the character's hand or of the model in the player's own view.
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
	-- WeaponStaticMesh.LinkGunPickup. Its barrel runs along the mesh's own -Y, and the grip is under its middle.
	third_person = {
		id = SETTING_ID,
		template = TEMPLATE_NAME,
		unit_name = "units/ut/link/pickup",
		-- The game links the Deepwood Staff to the left hand's node (AttachmentNodeLinking.one_handed_melee_weapon.left).
		hand_node = "j_leftweaponattach",
		meters_per_unit = 0.012,
		scale = 0.6,
		grip_right = -21,
		grip_forward = 0,
		grip_up = -30,
		yaw = 90,
		pitch = 0,
		roll = 0,
		-- In the world the gun follows the staff's unit, which the arms animate.
		follow_game_unit = 1,
		follow_calibrate_seconds = 1,
		muzzle_right = 54,
		muzzle_forward = 0,
		muzzle_up = 3,
		menu_yaw = 0,
	},
	on_create = function ()
		skin_api.play_sound("ut_link_select")
	end,
	on_level_exit = function ()
		remote_shots.clear()
	end,
})

local third_person = skin_api.third_person

-- These flow events would start the game's effects on the thorns, so they are dropped.
mod.init_flow_event_filters.link = function (event_name)
	return event_name == "lua_projectile_init" or event_name == "lua_trail" or event_name == "vfx_critical_strike"
end

-- Adds a bolt on every machine: a green blob and its glow follow the game's thorn. For the player's own shot this also plays the
-- animation, the flash and the sound. For another player's shot it plays the flash and the sound from their mesh.
mod.skin_init_callbacks.link_bolt = function (projectile)
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
	elseif remote_shots.is_new_shot(owner_unit) then
		muzzle_flash(function ()
			return third_person.muzzle_position(owner_unit)
		end, third_person.meters_per_unit)
		skin_api.play_sound_at("ut_link_fire_3d", Unit.world_position(game_unit, 0))
	end
end

-- When the beam starts, the alt fire animation plays.
mod.charge_start_callbacks.link_skin = function (action, new_action)
	if new_action.ut_charge_callback == "link" and skin_api.state() and utils.is_local_player_unit(action.owner_unit) then
		skin_api.play("AltFire")
	end
end

-- Returns where the beam starts: the end of the barrel of the model in the player's own view, or of the mesh in the character's hand.
mod.link_beam_callbacks.start_position = function (owner_unit)
	if utils.is_local_player_unit(owner_unit) and skin_api.state() and not third_person.shows_weapon(owner_unit) then
		return skin_api.muzzle_position()
	end

	return third_person.muzzle_position(owner_unit)
end

-- Draws the beam: UT's beam texture on every stretch of the curve, drawn again each frame, and a flare where it ends. It also plays
-- the beam's sound, again each time it ends, because it is a loop in UT.
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
