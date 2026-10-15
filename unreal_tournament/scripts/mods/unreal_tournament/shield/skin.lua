local mod = get_mod("unreal_tournament")

-- Shield Gun skin: how UT2004's Shield Gun looks and sounds.
--
-- weapon_skin.lua does the model, its placement and animations, the bob and the third person. This file does what is the Shield Gun's
-- own: the animations of the charge, the punch and the shield, and their sounds. The gameplay is in shield_gun.lua, which tells this file
-- what happens through mod.shield.
--
-- The assets were made with tools/asset_conversion (convert_weapon.py shield, convert_static.py shield_pickup, render_icon.py and
-- make_bank.py shield_gun).

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local animations = mod:dofile("scripts/mods/unreal_tournament/shield/skin_animations")
local particles = mod.skin_particles

local CONFIG = {
	-- ShieldGun.PlayerViewOffset (forward, right, up) and DisplayFOV, which CalcDrawOffset scales the offset by (0.9 / DisplayFOV * 100)
	view_offset = {2, -0.7, -2.7},
	display_fov = 60,
	-- ShieldGun.EffectOffset (forward, right, up): where GetEffectStart is from the weapon, and ShieldEffect's DrawScale
	effect_offset = {15, 5.5, 2},
	shield_draw_scale = 1.8,
	-- UT draws the effects at GetEffectStart before the gun, without depth (ShieldGun.RenderOverlays), so the gun covers them. Here they
	-- are drawn this many times further from the eye and this many times bigger, which looks the same, and that puts them behind the
	-- gun: they start 18 UT units ahead, and the gun reaches about 35 (the mesh is 79 units ahead of its origin, at DrawScale 0.4).
	-- A wall nearer than they are drawn hides them, so it is no more than it needs to be.
	behind_gun = 3,
	-- ForceRingA, the rings of a punch: 16 a second for 0.2 s, each 0.25 s long, flying forward at 100 units a second from GetEffectStart,
	-- 1 unit across and growing by 100 a second, dimming from the start (mAttenKa 0), added. Its colour is (B=32,R=32): the fields that
	-- a struct in defaultproperties leaves out keep the parent's, and xEmitter's is white, so green is 255. That makes the purple
	-- shock ring green.
	ring_rate = 16,
	ring_time = 0.2,
	ring_life = 0.25,
	ring_speed = 100, -- UT units a second
	ring_size = 1, -- UT units
	ring_growth = 100, -- UT units a second
	ring_color = { 32 / 255, 1, 32 / 255 },
	-- ShieldCharge, the sparks of the charge (ShieldFire.Timer): lines that appear up to 5 units from GetEffectStart (mPosDev) and fly
	-- towards it, at ChargeScale * 15 units a second, 20 + ChargeScale * 10 a second, each lasting max(ChargeScale / 30, 0.2) s, where
	-- ChargeScale is the time charged, up to FullyChargedTime. A line is 0.2 to 0.4 units wide and 0.05 s of its travel long (mSpawnVecB.X 5),
	-- green ((45, 220, 45) to (65, 250, 65)), added. The colours have an alpha of 25 to 200 (of 255), which dims them: pictures of UT2004 show
	-- them dim.
	charge_spread = 5, -- UT units
	charge_speed = 15, -- UT units a second, for each second of charge
	charge_rate = {20, 10}, -- a second: the first, and more for each second of charge
	charge_min_life = 0.2,
	charge_width = {0.2, 0.4}, -- UT units
	charge_length = 0.05, -- seconds of travel
	charge_colors = { { 45 / 255, 220 / 255, 45 / 255 }, { 65 / 255, 250 / 255, 65 / 255 } },
	charge_alpha = { 25 / 255, 200 / 255 },
	inspect_pose_speed = 5,
	inspect_sway = 5,
	inspect_sway_speed = 1.8,
}

local shield = mod.shield

local VARIANTS = {
	"shield_gun",
	"shield_gun_dr",
	"shield_gun_bw",
	"shield_gun_wh",
	"shield_gun_we",
	"shield_gun_priest",
}

local skin_apis = {}

-- Whether the player's own character is blocking, which is the shield being up
local function local_player_blocking()
	local player = Managers.player and Managers.player:local_player()
	local unit = player and player.player_unit
	local status_extension = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "status_system")

	return status_extension and status_extension:is_blocking() or false
end

-- A point of the player's view in UT units from the eye (forward, right, up), where the weapon's projection draws it, moved by the gun's
-- bob (weapon_skin.lua) and pushed back behind the gun (behind_gun). Effects that UT draws with the weapon (Canvas.DrawActor with
-- DisplayFOV) are placed with it and have the materials that draw with the weapon's field of view. It returns the first person unit, which
-- the gun is linked to, and the point in its frame, for particles that are linked to the unit (skin_particles.lua, locked), so that they
-- move with the gun. It returns nothing once the skin is gone.
local function view_point(api, skin, forward, right, up)
	if api.state() ~= skin then
		return nil
	end

	local parent, point = api.view_point_in_view(forward, right, up)

	if not parent then
		return nil
	end

	return parent, point * CONFIG.behind_gun
end

-- GetEffectStart: the weapon's place (PlayerViewOffset, scaled by CalcDrawOffset) and EffectOffset from it, as forward, right, up
local function effect_start()
	local offset_scale = 90 / CONFIG.display_fov

	return CONFIG.view_offset[1] * offset_scale + CONFIG.effect_offset[1], CONFIG.view_offset[2] * offset_scale + CONFIG.effect_offset[2], CONFIG.view_offset[3] * offset_scale + CONFIG.effect_offset[3]
end

local function random_between(range)
	return range[1] + (range[2] - range[1]) * math.random()
end

-- The rings of a punch (ForceRingA): discs that face the way the view looks and fly ahead
local function force_rings(api)
	local skin = api.state()

	if not skin then
		return
	end

	local forward, right, up = effect_start()
	local count = math.floor(CONFIG.ring_rate * CONFIG.ring_time) + 1
	local scale = (skin.view_across_scale or 0.01) * CONFIG.behind_gun

	for i = 1, count do
		local delay = (i - 1) / CONFIG.ring_rate
		local born = Managers.time:time("game") + delay

		particles.disc({
			attenuation = 0,
			color = CONFIG.ring_color,
			delay = delay,
			locked = function ()
				local age = math.max(0, Managers.time:time("game") - born)

				return view_point(api, skin, forward + CONFIG.ring_speed * age, right, up)
			end,
			growth = CONFIG.ring_growth * scale,
			life = CONFIG.ring_life,
			material = "units/ut/fx/fx_weapon_force_ring",
			-- (ahead, in the frame of the first person unit)
			normal = Vector3(0, 1, 0),
			size = CONFIG.ring_size * scale,
			texture = "force_ring",
		})
	end
end

-- The sparks of the charge (ShieldCharge), made each frame while the gun charges
local function charge_sparks(api, skin, dt)
	local charged = math.min(Managers.time:time("game") - shield.charge_started, shield.fully_charged_time)

	skin.spark_time = (skin.spark_time or 0) + dt

	local interval = 1 / (CONFIG.charge_rate[1] + CONFIG.charge_rate[2] * charged)
	local center_forward, center_right, center_up = effect_start()

	while skin.spark_time >= interval do
		skin.spark_time = skin.spark_time - interval

		local spread = CONFIG.charge_spread
		local x, y, z = random_between({-spread, spread}), random_between({-spread, spread}), random_between({-spread, spread})
		local distance = math.max(math.sqrt(x * x + y * y + z * z), 0.001)
		local speed = CONFIG.charge_speed * charged
		local born = Managers.time:time("game")
		local color = CONFIG.charge_colors[1]
		local other = CONFIG.charge_colors[2]
		local share = math.random()
		local alpha = random_between(CONFIG.charge_alpha)

		particles.beam({
			attenuation = 0.5,
			color = {
				(color[1] + (other[1] - color[1]) * share) * alpha,
				(color[2] + (other[2] - color[2]) * share) * alpha,
				(color[3] + (other[3] - color[3]) * share) * alpha,
			},
			life = math.max(charged / 30, CONFIG.charge_min_life),
			material = "units/ut/fx/fx_weapon_shield_charge_spark",
			size = random_between(CONFIG.charge_width) * (skin.view_across_scale or 0.01) * CONFIG.behind_gun,
			texture = "shield_charge_spark",
			-- (it flies towards the middle: ST_Explode with a speed below 0)
			locked = function ()
				local age = Managers.time:time("game") - born
				local at = math.max(0, distance - speed * age) / distance
				local tail = math.max(0, distance - speed * (age - CONFIG.charge_length)) / distance
				local parent, head = view_point(api, skin, center_forward + x * at, center_right + y * at, center_up + z * at)
				local _, back = view_point(api, skin, center_forward + x * tail, center_right + y * tail, center_up + z * tail)

				if not parent or not back then
					return nil
				end

				return parent, back, head
			end,
		})
	end
end

-- The shield while it is up (ShieldAltFire.DrawMuzzleFlash): UT's Shield mesh at GetEffectStart, turned as the view is, drawn with the weapon's
-- projection. Here it has the material that draws with the weapon's field of view (fx_shield), placed and scaled in the view as the model is
-- (weapon_skin.lua), and it pans its texture by its age. It ends when the shield goes down or the model is gone.
local function show_shield(api)
	local skin = api.state()

	if not skin then
		return
	end

	local mesh_unit = 0.02 -- meters of a UT unit of the mesh (make_fx_meshes.py)
	local forward, right, up = effect_start()

	particles.mesh({
		additive = 0,
		brightness = function ()
			return 1
		end,
		color = {
			1,
			1,
			1,
		},
		locked = function ()
			if not skin.blocking then
				return nil
			end

			return view_point(api, skin, forward, right, up)
		end,
		-- (the mesh's dish faces along its y, which is the way the view looks in the frame of the first person unit, and it is not turned
		-- about anything else)
		angle = 0,
		rotation = Quaternion.identity(),
		life = math.huge,
		material = "units/ut/fx/fx_shield",
		scale = function ()
			local across = (skin.view_across_scale or 0.01) / mesh_unit * CONFIG.shield_draw_scale * CONFIG.behind_gun
			local along = (skin.view_forward_scale or 0.01) / mesh_unit * CONFIG.shield_draw_scale * CONFIG.behind_gun

			return Vector3(across, along, across)
		end,
		unit = "units/ut/fx/shield_mesh",
	})
end

-- The animations follow what the gun does (ShieldFire and ShieldAltFire): the charge plays Charge over FullyChargedTime and then loops
-- Charged (PlayPreFire, ShieldGun.AnimEnd), the punch plays Fire, and the shield loops Shield while it is up.
local function update_state(api, skin, dt)
	local charging = shield.charge_started ~= nil
	local blocking = local_player_blocking()

	if charging then
		charge_sparks(api, skin, dt)
	else
		skin.spark_time = 0
	end

	if charging and skin.seen_charge ~= shield.charge_started then
		skin.seen_charge = shield.charge_started
		skin.charged = false

		api.play("Charge", shield.fully_charged_time)
		api.stop_sound(skin.charge_sound)

		skin.charge_sound = api.play_sound("ut_shield_charge")
	elseif charging and not skin.charged and skin.animation == "Charge" and skin.time >= api.animation_duration("Charge") then
		skin.charged = true

		api.play("Charged", nil, true)
	end

	if shield.last_punch and skin.seen_punch ~= shield.last_punch then
		skin.seen_punch = shield.last_punch

		api.stop_sound(skin.charge_sound)

		skin.charge_sound = nil

		api.play("Fire")
		api.play_sound("ut_shield_fire")
		force_rings(api)
	end

	if blocking ~= skin.blocking then
		skin.blocking = blocking

		if blocking then
			api.play("Shield", nil, true)
			show_shield(api)

			skin.shield_sound = api.play_sound("ut_shield_up")
		else
			api.stop_sound(skin.shield_sound)

			skin.shield_sound = nil

			if not charging then
				api.play("Idle")
			end
		end
	end
end

local function new_skin(setting_id)
	local definition = mod.items.weapons[setting_id]
	local api

	api = mod.weapon_skin.new({
		id = setting_id,
		name = "shield gun",
		template = definition.template,
		unit_name = "units/ut/shield/shield_gun",
		animations = animations,
		muzzle_node = "b_bone_flash",
		-- model_meters_per_unit is the meters per UT unit at which the model was converted (tools/asset_conversion/convert_weapon.py).
		-- meters_per_unit is the distance scale: the meters of forward in the view that one UT unit of the model takes up.
		model_meters_per_unit = 0.0125,
		meters_per_unit = 0.01,
		-- ShieldGun.uc
		display_fov = 60,
		draw_scale = 0.4,
		select_speed = 1.3636, -- Weapon's default SelectAnimRate
		offset_forward = 2,
		offset_right = -0.7,
		offset_up = -2.7,
		pivot_pitch = 500 / 65536 * 360,
		pivot_yaw = 500 / 65536 * 360,
		bob_damping = 2.2,
		-- The inspect pose turns the gun to show its side, like the other weapons. These numbers are a guess.
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
		-- WeaponStaticMesh.ShieldGunPickup. The game links a melee weapon to the right hand's node.
		third_person = {
			id = setting_id,
			template = definition.template,
			unit_name = "units/ut/shield/pickup",
			hand_node = "j_rightweaponattach",
			meters_per_unit = 0.01,
			scale = 0.5,
			grip_right = 0,
			grip_forward = 0,
			grip_up = 0,
			yaw = -60,
			pitch = 0,
			roll = 0,
			follow_game_unit = 1,
			follow_calibrate_seconds = 1,
			muzzle_right = 0,
			muzzle_forward = 30,
			muzzle_up = 0,
			menu_yaw = 180,
		},
		on_create = function ()
			api.play_sound("ut_shield_select")
		end,
		on_update = function (skin, dt)
			skin.inspect_pose = (skin.inspect_pose or 0) + ((skin.inspecting and 1 or 0) - (skin.inspect_pose or 0)) * math.min(1, CONFIG.inspect_pose_speed * dt)
			skin.inspect_time = skin.inspecting and (skin.inspect_time or 0) + dt or 0
			skin.extra_yaw = skin.inspect_pose * CONFIG.inspect_sway * math.sin(skin.inspect_time * CONFIG.inspect_sway_speed)

			update_state(api, skin, dt)
		end,
		on_destroy = function (skin)
			api.stop_sound(skin.charge_sound)
			api.stop_sound(skin.shield_sound)
		end,
	})

	skin_apis[#skin_apis + 1] = api

	return api
end

for _, setting_id in ipairs(VARIANTS) do
	new_skin(setting_id)
end

-- Inspecting is the game's own action, held with the key
mod.inspect_callbacks.shield_skin = function (action, started)
	for _, api in ipairs(skin_apis) do
		local skin = api.state()

		if skin and utils.is_local_player_unit(action.owner_unit) then
			skin.inspecting = started
		end
	end
end

-- The melee weapon's own swings are not played on the player's own first person unit: their sounds are in the animations. The skin's
-- model plays UT's.
for template_name in pairs(shield.template_names) do
	mod.first_person_animation_filters[template_name] = function (event)
		return string.find(event, "attack", 1, true) ~= nil
	end
end
