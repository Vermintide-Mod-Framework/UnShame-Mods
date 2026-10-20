local mod = get_mod("unreal_tournament")

-- Link Gun skin: how UT2004's Link Gun looks and sounds, on each hero's copy.
--
-- weapon_skin.lua does the model, its placement and animations, the bob and the third person. This file does what is the Link Gun's own:
-- the flashes, the bolts in flight and where they hit, the beam and the sounds. The gameplay is in link_gun.lua, which keeps the links
-- and the beams (mod.link_new) that this file draws.
--
-- The model, its animations, the textures and the sounds are the old Link Gun's (link/), made with tools/asset_conversion.

local utils = mod.utils
local animations = mod:dofile("scripts/mods/unreal_tournament/link/skin_animations")
local particles = mod.skin_particles
local link = mod.link_new

local UNIT = utils.UT_UNIT

local VARIANTS = { "link_new", "link_new_dr", "link_new_wh", "link_new_bw", "link_new_we" }

local TEMPLATE_NAMES = {}
local skin_apis = {}

for _, setting_id in ipairs(VARIANTS) do
	TEMPLATE_NAMES[mod.items.weapons[setting_id].template] = true
end

local CONFIG = {
	-- LinkMuzFlashProj1st, the flash of a bolt: green, or gold with links
	muzzle_size = 45,
	muzzle_growth = 100,
	muzzle_life = 0.1,
	-- LinkAltFire.FireAnimRate: the Fire animation plays at this much of its speed
	fire_animation_rate = 0.75,
	-- LinkProjectile: a green plasma bolt, gold with links (LinkAdjust). Here it is sprites that follow the game's projectile.
	bolt_size = 40,
	bolt_glow_size = 70,
	bolt_color = { 0.5, 1, 0.4 },
	linked_color = { 1, 0.85, 0.3 },
	-- LinkProjSparks where a bolt ends
	spark_size = 60,
	spark_growth = 150,
	spark_life = 0.2,
	-- LinkBeamEffect: the beam texture from the muzzle to where the beam ends, green, gold with links, and blue while it links an ally
	-- (the team colors are red and blue; the heroes are one team, as UT's blue). It is made again every frame.
	beam_width = 0.18, -- m
	beam_life = 0.06, -- s
	end_flare_size = 60,
	link_color = { 0.4, 0.6, 1 },
	-- Bolts of another player that start less than this far apart (in seconds) belong to the same shot
	shot_gap = 0.1,
}

-- How the third person mesh sits in each hero's hand: the hand the game links the base weapon to, and the point of the mesh in the hand
-- (UT units) and its turn. They are a start, to be set in the game.
--   follow_game_unit 2: the mesh turns with the base weapon's unit, which the arms animate (the guns). 3: with the hand's node, turned
--   by yaw, pitch and roll (the Deepwood Staff, as the Lightning Gun's). nil: level, the way the character faces (the Beam Staff, as the
--   Shock Rifle's).
local GRIPS = {
	link_new = { hand_node = "j_leftweaponattach", right = 0, forward = 0, up = 0, yaw = 0, pitch = 0, roll = 0, follow = 2 },
	link_new_dr = { hand_node = "j_leftweaponattach", right = 0, forward = 0, up = 0, yaw = 0, pitch = 0, roll = 0, follow = 2 },
	link_new_wh = { hand_node = "j_leftweaponattach", right = 0, forward = 0, up = 0, yaw = 0, pitch = 0, roll = 0, follow = 2 },
	link_new_bw = { hand_node = "j_rightweaponattach", right = 0, forward = 5, up = 4, yaw = 0, pitch = 0, roll = 0, follow = nil },
	link_new_we = { hand_node = "j_leftweaponattach", right = -4, forward = -4, up = 0, yaw = -110, pitch = 0, roll = -25, follow = 3 },
}

-- The skin whose model the player sees now
local function first_person_api()
	return mod.weapon_skin.shown_skin(skin_apis)
end

-- The skin of the mesh in a character's hand, and where its barrel ends
local function held_muzzle(character)
	return mod.weapon_skin.held_muzzle(skin_apis, character)
end

-- Where a character's shots and beam start: the end of the barrel of the model in the player's own view, or of the mesh in the hand
local function muzzle_of(character)
	local api = first_person_api()

	if utils.is_local_player_unit(character) and api and not api.third_person.shows_weapon(character) then
		return api.muzzle_position(), api.state() and api.state().unit_scale
	end

	local muzzle, holder = held_muzzle(character)

	return muzzle, holder and holder.third_person.meters_per_unit
end

local function color_of(character)
	return link.links_of(character) > 0 and CONFIG.linked_color or CONFIG.bolt_color
end

local function muzzle_flash(character)
	local _, scale = muzzle_of(character)

	if not scale then
		return
	end

	local gold = link.links_of(character) > 0

	particles.sprite({
		color = { 1, 1, 1 },
		follow = function ()
			return (muzzle_of(character))
		end,
		growth = CONFIG.muzzle_growth * scale,
		life = CONFIG.muzzle_life,
		size = CONFIG.muzzle_size * scale,
		spin = (math.random() * 2 - 1) * 0.2,
		texture = gold and "link_muz_yellow" or "link_muz_green",
	})
end

local function new_skin(setting_id)
	local definition = mod.items.weapons[setting_id]
	local grip = GRIPS[setting_id]
	local api

	api = mod.weapon_skin.new({
		id = setting_id,
		name = "link",
		template = definition.template,
		unit_name = "units/ut/link/link_gun",
		animations = animations,
		muzzle_node = "b_bone_flasha",
		-- model_meters_per_unit is the meters per UT unit at which the model was converted (tools/asset_conversion/convert_weapon.py).
		-- meters_per_unit is the distance scale: the meters of forward in the view that one UT unit of the model takes up.
		model_meters_per_unit = 0.0125,
		meters_per_unit = 0.01,
		-- LinkGun.uc: DisplayFOV, PlayerViewOffset and PlayerViewPivot
		display_fov = 60,
		draw_scale = 1,
		offset_forward = -5,
		offset_right = -3,
		offset_up = 0,
		pivot_yaw = 500 / 65536 * 360,
		bob_damping = 1.575,
		-- UT's third person mesh (LinkAttachment's NewLinkGun_3rd) at UT's size in a player's hand (DrawScale 0.4). Its origin is by its
		-- grip, and its barrel runs along its forward to the muzzle (its upper flash bone).
		third_person = {
			id = setting_id,
			template = definition.template,
			unit_name = "units/ut/link/third_person",
			hand_node = grip.hand_node,
			meters_per_unit = 0.02 * 0.4,
			scale = 1,
			grip_right = grip.right,
			grip_forward = grip.forward,
			grip_up = grip.up,
			yaw = grip.yaw,
			pitch = grip.pitch,
			roll = grip.roll,
			follow_game_unit = grip.follow,
			muzzle_right = 0,
			muzzle_forward = 75.5,
			muzzle_up = 8.9,
			menu_yaw = -90,
		},
		on_create = function ()
			api.play_sound("ut_link_select")
		end,
	})

	skin_apis[#skin_apis + 1] = api
end

for _, setting_id in ipairs(VARIANTS) do
	new_skin(setting_id)
end

-- The bolts

-- These flow events would start the game's effects on the projectile, so they are dropped
mod.init_flow_event_filters.link_new = function (event_name)
	return event_name == "lua_projectile_init" or event_name == "lua_trail" or event_name == "vfx_critical_strike"
end

-- The bolts in flight, each { unit = the game's projectile, extension, position (a box), color, sound }
local bolts = {}

-- A shot by another player, as seen on this machine: the flash and the sound come from the mesh in their hand, once for the bolt of a shot
local remote_shots = utils.shot_grouping(CONFIG.shot_gap)

-- Adds a bolt on every machine: a green blob and its glow follow the game's projectile, gold with links (LinkAdjust), and its hum
-- (LinkProjectile's AmbientSound). For the player's own shot this also plays the animation, the flash and the sound. For another
-- player's it plays the flash and the sound from their mesh.
mod.skin_init_callbacks.link_new_bolt = function (projectile)
	local game_unit = projectile._projectile_unit
	local owner_unit = projectile._owner_unit
	local links = projectile._current_action and projectile._current_action.ut_link_new_links or 0
	local color = links > 0 and CONFIG.linked_color or CONFIG.bolt_color

	Unit.set_unit_visibility(game_unit, false)

	local bolt = {
		unit = game_unit,
		extension = projectile,
		position = Vector3Box(Unit.world_position(game_unit, 0)),
		color = color,
		sound = utils.play_on_unit("ut_link_projectile_3d", game_unit),
	}

	bolts[#bolts + 1] = bolt

	local function follow()
		if Unit.alive(game_unit) and not projectile._stop_impacts then
			return Unit.world_position(game_unit, 0)
		end
	end

	particles.sprite({
		color = color,
		fade_in = 0,
		follow = follow,
		life = 10,
		size = CONFIG.bolt_size * UNIT,
		spin = 0.2,
		texture = links > 0 and "link_muz_yellow" or "link_muz_green",
	})
	particles.sprite({
		color = color,
		fade_in = 0,
		follow = follow,
		intensity = 0.5,
		life = 10,
		size = CONFIG.bolt_glow_size * UNIT,
		texture = "muzzle_white",
	})

	-- (a bolt that a shield reflected is not a shot)
	if projectile._ut_reflected_by then
		return
	end

	if utils.is_local_player_unit(owner_unit) then
		local api = first_person_api()

		if api then
			if not api.third_person.shows_weapon(owner_unit) then
				api.play("Fire", api.animation_duration("Fire") / CONFIG.fire_animation_rate)
			end

			api.play_sound(links > 0 and "ut_link_linked" or "ut_link_fire")
		end

		muzzle_flash(owner_unit)
	elseif remote_shots.is_new_shot(owner_unit) then
		local muzzle, holder = held_muzzle(owner_unit)

		if muzzle then
			muzzle_flash(owner_unit)
			holder.play_sound_at("ut_link_fire_3d", muzzle)
		end
	end
end

-- Follows the bolts, and puts sparks where one ends (LinkProjectile.Explode: LinkProjSparks, yellow with links)
local function update_bolts()
	for i = #bolts, 1, -1 do
		local bolt = bolts[i]
		local alive = Unit.alive(bolt.unit) and not bolt.extension._stop_impacts

		if alive then
			bolt.position:store(Unit.world_position(bolt.unit, 0))
		else
			particles.sprite({
				color = bolt.color,
				growth = CONFIG.spark_growth * UNIT,
				life = CONFIG.spark_life,
				position = bolt.position:unbox(),
				size = CONFIG.spark_size * UNIT,
				spin = (math.random() * 2 - 1) * 0.5,
				texture = bolt.color == CONFIG.bolt_color and "link_spark_green" or "link_spark_yellow",
			})

			if bolt.sound and Managers.world:has_world("level_world") then
				utils.stop_sound(bolt.sound)
			end

			table.remove(bolts, i)
		end
	end
end

-- The beams

-- The sound of each beam that is drawn, by its character: { the player's own (an id of the skin's play_sound) or another's on their
-- character (a handle of utils.play_on_unit), api }
local beam_sounds = {}

local function stop_beam_sound(character)
	local entry = beam_sounds[character]

	beam_sounds[character] = nil

	if not entry or not Managers.world:has_world("level_world") then
		return
	end

	if entry.id then
		entry.api.stop_sound(entry.id)
	else
		utils.stop_sound(entry.handle)
	end
end

-- Draws each beam: UT's beam texture from the muzzle to where it ends, and a flare there. Its sound (LinkFire's BeamSounds) loops while it
-- is drawn.
local function draw_beams()
	for character, beam in pairs(link.beams) do
		local start = Unit.alive(character) and muzzle_of(character)

		if start then
			local finish = beam.end_position:unbox()
			local linking = link.locked[character] ~= nil
			local gold = link.links_of(character) > 0
			local texture = (linking or gold) and "link_beam_yellow" or "link_beam_green"

			particles.beam({
				color = linking and CONFIG.link_color or nil,
				from = start,
				life = CONFIG.beam_life,
				size = CONFIG.beam_width,
				texture = texture,
				to = finish,
			})
			particles.sprite({
				color = linking and CONFIG.link_color or gold and CONFIG.linked_color or CONFIG.bolt_color,
				life = CONFIG.beam_life,
				position = finish,
				size = CONFIG.end_flare_size * UNIT,
				texture = (linking or gold) and "link_ring_yellow" or "link_ring_green",
			})

			if not beam_sounds[character] then
				local api = first_person_api()

				if utils.is_local_player_unit(character) and api then
					beam_sounds[character] = { id = api.play_sound("ut_link_beam"), api = api }
				else
					beam_sounds[character] = { handle = utils.play_on_unit("ut_link_beam_3d", character) }
				end
			end
		end
	end

	for character in pairs(beam_sounds) do
		if not link.beams[character] then
			stop_beam_sound(character)
		end
	end
end

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	if not Managers.world:has_world("level_world") then
		return
	end

	update_bolts()
	draw_beams()
end

local function clear()
	for character in pairs(beam_sounds) do
		stop_beam_sound(character)
	end

	for _, bolt in ipairs(bolts) do
		if bolt.sound and Managers.world:has_world("level_world") then
			utils.stop_sound(bolt.sound)
		end
	end

	table.clear(bolts)
	remote_shots.clear()
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = clear
mod.disabled_callbacks[#mod.disabled_callbacks + 1] = clear
mod.unload_callbacks[#mod.unload_callbacks + 1] = clear

-- The base's own shot, reload and zoom animations are not played on the player's own first person unit: the skin's model plays UT's.
-- The characters' shot animation would have the base's unit play its shot sound and flash: the skin plays UT's.
for template_name in pairs(TEMPLATE_NAMES) do
	mod.first_person_animation_filters[template_name] = function (event)
		local actions = Weapons[template_name] and Weapons[template_name].actions
		local shot = actions and actions.action_one and actions.action_one.default

		return shot ~= nil and (event == shot.anim_event or event == shot.anim_event_last_ammo) or string.find(event, "reload", 1, true) ~= nil or string.find(event, "zoom", 1, true) ~= nil
	end

	mod.third_person_animation_filters[template_name] = function (event)
		return string.find(event, "reload", 1, true) ~= nil
	end

	mod.third_person_weapons_hidden_from_flow[template_name] = true
end
