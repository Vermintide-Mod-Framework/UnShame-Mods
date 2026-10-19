local mod = get_mod("unreal_tournament")

-- Assault Rifle skin: how UT2004's Assault Rifle looks and sounds, two at a time.
--
-- weapon_skin.lua does the models, their placement and animations, the bob and the third person. There are two skins of the weapon: the
-- rifle in the right hand, and the one in the left, which is the same model mirrored (AssaultRifle.RenderDualOverlay draws the weapon a
-- second time with its mesh, offset, yaw and roll turned to the other side). Both play the same animations, as UT's are one weapon drawn
-- twice. This file does what is the rifle's own: the flash of the rounds, the grenades in flight and their smoke, and the sounds. The
-- gameplay is in
-- assault_rifle.lua.
--
-- The assets were made with tools/asset_conversion (convert_weapon.py assault, convert_static.py assault_pickup and assault_grenade,
-- render_icon.py, make_assault_hud.py and make_bank.py assault_rifle).

local utils = mod.utils
local animations = mod:dofile("scripts/mods/unreal_tournament/assault/skin_animations")
local particles = mod.skin_particles

local SETTING_ID = "assault_rifle"
local TEMPLATE_NAME = mod.items.weapons[SETTING_ID].template
local assault = mod.assault

local CONFIG = {
	-- AssaultMuzFlash1st: the Minigun's flash at DrawScale 1.2 (see muzzle_flash.lua)
	flash_draw_scale = 1.2,
	-- Grenade: RandSpin(25000). It spins about a random axis at 25000 of UT's rotation units a second, where 65536 is a full turn.
	grenade_spin = 25000 / 65536,
	-- A bounce faster than this plays the impact sound (Grenade.HitWall)
	bounce_sound_speed = 250, -- UT units a second
	-- GrenadeSmokeTrail, which a grenade leaves while it moves, if the view is within 5500 units when it is thrown (Grenade.PostBeginPlay),
	-- and stops leaving when it comes to rest. It makes 30 puffs a second (mRegenRange). A puff lasts 1.3 to 1.5 s, starts 15 to 25 units
	-- across and grows by 10 a second, drifts at 2 to 15 units a second, and rises (its mass is -0.01 to -0.08: by the Minigun smoke's
	-- turning of mass into a rise, about 100 units a second for each 1 of it). It is a dark blue grey (mColorRange) at twice the light
	-- (ScaleGlow 2), blended by its alpha (STY_Alpha), and fades as xEmitter's do (mAttenKa 0.2). Each is a tile of SmokeTex at random.
	trail_view_range = 5500, -- UT units
	trail_rate = 30, -- puffs a second
	trail_life = { 1.3, 1.5 },
	trail_size = { 15, 25 }, -- UT units across
	trail_growth = 10, -- UT units across, a second
	trail_speed = { 2, 15 }, -- UT units a second
	trail_rise = { 1, 8 }, -- UT units a second
	trail_color = {
		{ 35 / 255, 45 / 255, 45 / 255 },
		{ 50 / 255, 65 / 255, 65 / 255 },
	},
	trail_intensity = 2,
	trail_attenuation = 0.2,
	trail_tiles = 16,
	-- The characters fire both modes as the pistols' alt attack: they take its stance (lock_target), play its shot (attack_shoot_fast)
	-- for each round and grenade, and leave the stance (attack_finished) this long after the last of them, once the rifle does nothing
	-- (a choice)
	stance_linger = 0.5, -- s
	-- In the stance the arms reach out and the pistols point along them, so both rifles are level with the pistols then (pitch and yaw 0
	-- from the hand's forward, where they are tipped down to lie along the forearm otherwise), turning there and back over this long
	-- (set in the game)
	stance_blend = 0.2, -- s
	-- The colour of the grenade's charge on the charge bar (R, G, B): white, as the Lightning Gun's bar (set in the game: the grenade's
	-- grey was hard to see)
	charge_bar_color = { 255, 255, 255 },
	-- AssaultRifle.NewDrawWeaponInfo: a white icon for each grenade (make_assault_hud.py), in a row from the right, each half an icon left
	-- of the last. UT draws them at the screen's right edge, 0.705 of its height down, 99 / 3200 of its width across. Here they are below
	-- the charge bar, which is below the ammo counter's numbers, from its right end, and 8 of them are as long as it (set in the game). A
	-- second row is for more than 8, which only two rifles' ammo has in UT (MaxAmmo doubles in bDualMode); these hold 8.
	icon_step = 0.5, -- of an icon
	icons_per_row = 8,
	inspect_pose_speed = 5,
	inspect_sway = 5,
	inspect_sway_speed = 1.8,
}

local UNIT = utils.UT_UNIT

local skin_apis = {}

-- The flash of a round at the muzzle of a rifle in the player's view (see the Minigun's skin)
local function flash(api)
	local skin = api.state()

	if not skin then
		return
	end

	mod.muzzle_flash(api, function ()
		return api.state() == skin and api.muzzle_model_position() or nil
	end, (skin.unit_scale or UNIT) / api.draw_scale(), CONFIG.flash_draw_scale)
end

-- Plays an animation on both rifles
local function play_both(name, duration)
	for _, api in ipairs(skin_apis) do
		if api.state() then
			api.play(name, duration)
		end
	end
end

-- (the characters' shot and their stance, below)
local shot_animation, saw_stance

-- Called for each round, on every machine: the shooter is in the stance. If the player on this machine fired it, both rifles play the
-- fire animation, flash and sound. Otherwise the sound plays at the shooter's muzzle.
mod.assault_round_callbacks.assault_skin = function (owner_unit)
	local right = skin_apis[1]

	saw_stance(owner_unit)

	if not right then
		return
	end

	if utils.is_local_player_unit(owner_unit) and right.state() then
		play_both("Fire")
		right.play_sound("ut_assault_fire")

		for _, api in ipairs(skin_apis) do
			flash(api)
		end

		return
	end

	local hand = right.third_person.muzzle_position(owner_unit)

	if hand then
		right.play_sound_at("ut_assault_fire_3d", hand)
	end
end

-- The grenade models, by grenade id. Every machine spawns one for each grenade in flight and spins it as it flies.
local grenade_units = {}

local function destroy_grenade_unit(id)
	local entry = grenade_units[id]

	if entry and Unit.alive(entry.unit) then
		World.destroy_unit(entry.world, entry.unit)
	end

	grenade_units[id] = nil
end

mod.assault_grenade_callbacks.assault_skin = function (grenade)
	local api = skin_apis[1]
	local world = Managers.world:world("level_world")

	local camera_position = utils.camera_pose()
	local trail = camera_position ~= nil and Vector3.distance(camera_position, grenade.position:unbox()) < CONFIG.trail_view_range * UNIT

	grenade_units[grenade.id] = {
		axis = Vector3Box(Vector3.normalize(Vector3(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5))),
		grenade = grenade,
		trail = trail,
		trail_owed = 0,
		unit = World.spawn_unit(world, "units/ut/assault/grenade", grenade.position:unbox()),
		world = world,
	}

	saw_stance(grenade.owner_unit)

	if grenade.local_owner then
		shot_animation(grenade.owner_unit)
	end

	if utils.is_local_player_unit(grenade.owner_unit) and api.state() then
		play_both("AltFire", api.animation_duration("AltFire") / 0.5)
		api.play_sound("ut_assault_alt_fire")
		api.play_sound("ut_assault_grenade_load")
	else
		api.play_sound_at("ut_assault_alt_fire_3d", grenade.position:unbox())
	end
end

-- The characters' stance and shots (see stance_linger), sent from the machine that runs the character's actions, the player's or the
-- host's for a bot, as the game sends its own: [character] = when the rifle last did something
local in_stance = {}

-- Every machine sees the rounds and the grenades, and so when each character is in the stance, for the rifles' angles: [character] =
-- { last = when the rifle last did something, weight = how far the rifles are turned to level, 0 to 1 }. The charge is seen only by the
-- machine that runs the character, so the others turn the rifles at the throw.
local stances = {}

saw_stance = function (unit)
	local stance = stances[unit] or { weight = 0 }

	stance.last = Managers.time:time("game")
	stances[unit] = stance
end

shot_animation = function (unit)
	local network_manager = Managers.state.network

	if not network_manager or not Unit.alive(unit) then
		return
	end

	if not in_stance[unit] then
		network_manager:anim_event(unit, "lock_target")
	end

	in_stance[unit] = Managers.time:time("game")
	network_manager:anim_event(unit, "attack_shoot_fast")
end

mod.handgun_start_callbacks.assault_stance = function (action, new_action)
	if new_action.ut_assault then
		shot_animation(action.owner_unit)
	end
end

-- The charge takes the stance, and the grenade's throw is its shot
mod.dummy_start_callbacks.assault_stance = function (action, new_action)
	local unit = action.owner_unit

	if new_action.ut_assault_charge and not in_stance[unit] and Managers.state.network then
		Managers.state.network:anim_event(unit, "lock_target")

		in_stance[unit] = Managers.time:time("game")
	end

	if new_action.ut_assault_charge then
		saw_stance(unit)
	end
end

-- Whether the rifle in the character's hands is doing something (a round or the charge)
local function rifle_busy(unit)
	local inventory_extension = ScriptUnit.has_extension(unit, "inventory_system")
	local equipment = inventory_extension and inventory_extension:equipment()
	local weapon_unit = equipment and (equipment.right_hand_wielded_unit or equipment.left_hand_wielded_unit)
	local weapon_extension = weapon_unit and ScriptUnit.has_extension(weapon_unit, "weapon_system")

	return weapon_extension ~= nil and weapon_extension:has_current_action()
end

local function update_stances()
	local now = Managers.time:time("game")

	for unit, last in pairs(in_stance) do
		if not Unit.alive(unit) or utils.wielded_template_name(unit) ~= TEMPLATE_NAME then
			-- (the wield of another weapon plays its own stance)
			in_stance[unit] = nil
		elseif rifle_busy(unit) then
			in_stance[unit] = now

			saw_stance(unit)
		elseif now - last > CONFIG.stance_linger then
			in_stance[unit] = nil

			if Managers.state.network then
				Managers.state.network:anim_event(unit, "attack_finished")
			end
		end
	end
end

-- Turns each character's rifles towards level while it is in the stance, and back once it has left it
local function update_angles(dt)
	local now = Managers.time:time("game")
	local step = dt / CONFIG.stance_blend

	for unit, stance in pairs(stances) do
		local wanted = Unit.alive(unit) and now - stance.last <= CONFIG.stance_linger and 1 or 0

		stance.weight = math.clamp(stance.weight + (wanted > stance.weight and step or -step), 0, 1)

		if stance.weight == 0 and wanted == 0 then
			stances[unit] = nil
		end
	end
end

-- The angles of a rifle in a character's hand (weapon_skin_third_person.lua's angles_of)
local function angles_in_hand(character, pitch, roll, yaw)
	local stance = stances[character]
	local level = stance and stance.weight or 0

	return pitch * (1 - level), roll, yaw * (1 - level)
end

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	update_stances()
	update_angles(dt)
end
mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(in_stance)
	table.clear(stances)
end

mod.assault_bounce_callbacks.assault_skin = function (grenade, position, speed)
	if speed > CONFIG.bounce_sound_speed then
		skin_apis[1].play_sound_at("ut_assault_grenade_bounce_3d", position)
	end
end

local random_between = utils.random_between

-- The puffs of a grenade's trail that are due, where the grenade is now
local function trail_puffs(entry, dt)
	entry.trail_owed = entry.trail_owed + CONFIG.trail_rate * dt

	local position = entry.grenade.position:unbox()

	while entry.trail_owed >= 1 do
		entry.trail_owed = entry.trail_owed - 1

		local life = random_between(CONFIG.trail_life)
		local share = math.random()
		local low, high = CONFIG.trail_color[1], CONFIG.trail_color[2]
		local drift = utils.random_direction() * random_between(CONFIG.trail_speed)

		particles.sprite({
			additive = 0,
			attenuation = CONFIG.trail_attenuation,
			color = { low[1] + (high[1] - low[1]) * share, low[2] + (high[2] - low[2]) * share, low[3] + (high[3] - low[3]) * share },
			growth = CONFIG.trail_growth * UNIT,
			intensity = CONFIG.trail_intensity,
			life = life,
			position = position,
			size = random_between(CONFIG.trail_size) * UNIT,
			texture = "muzzle_smoke_" .. math.random(0, CONFIG.trail_tiles - 1),
			velocity = (drift + Vector3(0, 0, random_between(CONFIG.trail_rise))) * UNIT,
		})
	end
end

local function update_grenades(dt)
	for id, entry in pairs(grenade_units) do
		local grenade = entry.grenade

		if grenade.exploded or not Unit.alive(entry.unit) then
			destroy_grenade_unit(id)
		else
			if entry.trail and not grenade.stopped then
				trail_puffs(entry, dt)
			end

			local spin = grenade.stopped and 0 or grenade.age * CONFIG.grenade_spin * 2 * math.pi

			Unit.set_local_position(entry.unit, 0, grenade.position:unbox())
			Unit.set_local_rotation(entry.unit, 0, Quaternion.axis_angle(entry.axis:unbox(), spin))
			World.update_unit(entry.world, entry.unit)
		end
	end
end

local function clear_grenades()
	for id in pairs(grenade_units) do
		destroy_grenade_unit(id)
	end
end

-- The grenade's charge on the charge bar (charge_bar.lua), below the ammo counter's numbers: AssaultRifle.ChargeBar, the time held over
-- the time the speed takes to reach its most (AssaultGrenade.mHoldClampMax), which HudCDeathmatch draws as its RechargeBar. The grenades
-- left are the icons below it. The icon's material is added to the UI renderers, which draw it as a texture of its own.
local speed_min, speed_max, speed_gain = unpack(assault.grenade_speed)
local GRENADE_ICON = "ut_assault_grenade"

mod.items.add_material_set("ui/ut/assault_grenade")
UIAtlasHelper.add_standalone_texture_by_name(GRENADE_ICON)

mod.charge_bars[TEMPLATE_NAME] = function ()
	local held = assault.charge_started and Managers.time:time("game") - assault.charge_started or 0

	return {
		below_ammo = true,
		color = CONFIG.charge_bar_color,
		fraction = math.clamp(held / ((speed_max - speed_min) / speed_gain), 0, 1),
		icons = {
			count = math.min(assault.grenade_count, CONFIG.icons_per_row),
			fill = CONFIG.icons_per_row,
			step = CONFIG.icon_step,
			texture = GRENADE_ICON,
		},
	}
end

-- The grenade's explosion plays the Rocket Launcher's explosion and sound. UT's grenade explosion (NewExplosionB) looks much like the
-- rocket's (NewExplosionA).
mod.skin_explosion_callbacks[assault.explosion] = function (world, position, rotation, scale)
	local rocket = mod.skin_explosion_callbacks.ut_rocket_explosion

	if rocket then
		rocket(world, position, rotation, scale)
	end
end

local function new_skin(id, mirror)
	local api

	api = mod.weapon_skin.new({
		id = id,
		name = mirror and "assault rifle (left)" or "assault rifle",
		template = TEMPLATE_NAME,
		unit_name = mirror and "units/ut/assault/assault_rifle_left" or "units/ut/assault/assault_rifle",
		animations = animations,
		muzzle_node = "b_bone_flash_a",
		-- model_meters_per_unit is the meters per UT unit at which the model was converted (tools/asset_conversion/convert_weapon.py).
		-- meters_per_unit is the distance scale: the meters of forward in the view that one UT unit of the model takes up.
		model_meters_per_unit = 0.0125,
		meters_per_unit = 0.01,
		mirror = mirror,
		-- AssaultRifle.uc
		display_fov = 70,
		draw_scale = 0.8,
		select_speed = 1.3636, -- Weapon's default SelectAnimRate
		offset_forward = 4,
		offset_right = 5.5,
		offset_up = -6,
		pivot_pitch = 400 / 65536 * 360,
		bob_damping = 1.7,
		-- The inspect pose turns the rifle to show its side, like the other weapons. These numbers are a guess.
		inspect_pose_right = -2,
		inspect_pose_forward = 4,
		inspect_pose_up = 0,
		inspect_pose_roll = 10,
		inspect_pose_pitch = 4,
		inspect_pose_yaw = 55,
		inspect_turn_start = 0.35,
		inspect_pivot_right = 0,
		inspect_pivot_forward = 20,
		inspect_pivot_up = 0,
		-- UT's third person mesh of the weapon (AssaultAttachment's NewWeapons2004.NewAssaultRifle_3rd) at UT's size in a player's hand
		-- (AssaultAttachment's DrawScale 0.3, which AssaultRifle.AttachToPawn keeps for two). There is one in each hand, where the game puts
		-- the brace of pistols (AttachmentNodeLinking). Its origin is by its grip, and its barrel runs along its forward, as the Minigun's
		-- does, so it is not turned, as the Minigun's copy of the repeater pistol is not in the same hand. The muzzle is the rifle's
		-- Bone_Flash (Bone_Flash02, below it, is the grenade launcher's).
		third_person = {
			id = id,
			template = TEMPLATE_NAME,
			unit_name = "units/ut/assault/third_person",
			hand_node = mirror and "j_leftweaponattach" or "j_rightweaponattach",
			meters_per_unit = 0.02 * 0.3,
			scale = 1,
			grip_right = 0,
			grip_forward = 0,
			-- (tipped down from the hand's forward, so that it lies along the forearm, a little in for the left: set in the game for each)
			grip_up = mirror and 2 or 7,
			yaw = mirror and -10 or 0,
			pitch = mirror and -25 or -45,
			roll = 0,
			follow_game_unit = 2,
			-- (level in the stance, see stance_blend)
			angles_of = function (character, pitch, roll, yaw)
				return angles_in_hand(character, pitch, roll, yaw)
			end,
			muzzle_right = 0,
			muzzle_forward = 49.3,
			muzzle_up = 17.9,
			menu_yaw = -90,
		},
		on_create = function ()
			if not mirror then
				api.play_sound("ut_assault_select")
			end
		end,
		on_update = function (skin, dt)
			skin.inspect_pose = (skin.inspect_pose or 0) + ((skin.inspecting and 1 or 0) - (skin.inspect_pose or 0)) * math.min(1, CONFIG.inspect_pose_speed * dt)
			skin.inspect_time = skin.inspecting and (skin.inspect_time or 0) + dt or 0
			skin.extra_yaw = skin.inspect_pose * CONFIG.inspect_sway * math.sin(skin.inspect_time * CONFIG.inspect_sway_speed)
		end,
		on_update_always = not mirror and update_grenades or nil,
		on_level_exit = not mirror and clear_grenades or nil,
		on_give_back = not mirror and clear_grenades or nil,
	})

	skin_apis[#skin_apis + 1] = api

	return api
end

new_skin(SETTING_ID, false)
new_skin(SETTING_ID .. "_left", true)

mod.unload_callbacks[#mod.unload_callbacks + 1] = clear_grenades

-- Inspecting is the game's own action, held with the key
mod.inspect_callbacks.assault_skin = function (action, started)
	for _, api in ipairs(skin_apis) do
		local skin = api.state()

		if skin and utils.is_local_player_unit(action.owner_unit) then
			skin.inspecting = started
		end
	end
end

-- The first person unit does not play the pistols' shot and reload animations. The skin's models play UT's animations instead.
mod.first_person_animation_filters[TEMPLATE_NAME] = function (event)
	return string.find(event, "attack", 1, true) ~= nil or string.find(event, "reload", 1, true) ~= nil or event == "lock_target"
end

mod.third_person_animation_filters[TEMPLATE_NAME] = function (event)
	return string.find(event, "reload", 1, true) ~= nil
end
