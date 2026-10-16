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
	-- ShieldEffect.Flash: how long the shield shows its other skin when it stops something (its timer)
	flash_time = 0.2, -- seconds
	-- UT draws the effects at GetEffectStart before the gun, without depth (ShieldGun.RenderOverlays), so the gun covers them. Here they
	-- are drawn this many times further from the eye and this many times bigger, which looks the same, and that puts them behind the
	-- gun: they start 18 UT units ahead, and the gun reaches about 35 (the mesh is 79 units ahead of its origin, at DrawScale 0.4).
	-- A wall nearer than they are drawn hides them, so it is no more than it needs to be.
	behind_gun = 3,
	-- ForceRingA, the rings of a punch: 16 a second for 0.2 s, each 0.25 s long, flying forward at 100 units a second from GetEffectStart,
	-- of size 1 and growing by 100 a second (xEmitter's sizes are a half width, so twice that across), dimming from the start (mAttenKa 0),
	-- added. Its colour is (B=32,R=32): the fields that
	-- a struct in defaultproperties leaves out keep the parent's, and xEmitter's is white, so green is 255. That makes the purple
	-- shock ring green.
	ring_rate = 16,
	ring_time = 0.2,
	ring_life = 0.25,
	ring_speed = 100, -- UT units a second
	ring_size = 2, -- UT units across
	ring_growth = 200, -- UT units across, a second
	ring_color = { 32 / 255, 1, 32 / 255 },
	-- ShieldCharge, the sparks of the charge (ShieldFire.Timer): lines that appear up to 5 units from GetEffectStart (mPosDev) and fly
	-- towards it, at ChargeScale * 15 units a second, 20 + ChargeScale * 10 a second, each lasting max(ChargeScale / 30, 0.2) s, where
	-- ChargeScale is the time charged, up to FullyChargedTime. A line is 0.2 to 0.4 units in size (xEmitter's sizes are a half width, so
	-- twice that wide) and 0.05 s of its travel long (mSpawnVecB.X 5), green ((45, 220, 45) to (65, 250, 65)), added. The colours' alpha
	-- (25 to 200) does nothing: STY_Additive adds the colour as it is.
	charge_spread = 5, -- UT units
	charge_speed = 15, -- UT units a second, for each second of charge
	charge_rate = {20, 10}, -- a second: the first, and more for each second of charge
	charge_min_life = 0.2,
	charge_width = {0.4, 0.8}, -- UT units
	charge_length = 0.05, -- seconds of travel
	charge_colors = { { 45 / 255, 220 / 255, 45 / 255 }, { 65 / 255, 250 / 255, 65 / 255 } },
	-- The length of shieldgun_charge, which loops while the gun charges (the bank's ut_shield_charge)
	charge_sound_length = 2.03, -- seconds
	-- The shove of a push (UT has no push). The gun and the shield move on a spring, which goes shove_frequency radians a second and is
	-- damped by shove_damping (1 is just enough not to swing past). They are pulled towards shove_forward ahead in the view (UT units) for
	-- shove_out seconds, which takes them out quickly and a little past it. While both buttons are held for a bash they settle back to
	-- shove_hold of the way, and the bash punches from there (its Fire animation and rings). Then they go home. The shield is up while they
	-- are out, but for the bash. These numbers are a guess. With them the shove is all the way out at 0.1 s, a tap is home by 0.2 s, and
	-- a hold has settled back by 0.2 s, before the bash can come at 0.4 s.
	shove_forward = 10,
	shove_out = 0.11,
	shove_hold = 0.65,
	shove_frequency = 32,
	shove_damping = 0.65,
	-- The colour of the charge on the overcharge bar (R, G, B): ShieldGun.HudColor (0, 188, 121) made as bright as it goes, its
	-- strongest part at 255, because the bar's texture darkens it (a choice)
	charge_bar_color = { 0, 255, 164 },
	-- The alpha of the bar's marks, as UIWidgets.create_overcharge_bar_widget makes them
	charge_mark_alpha = 204,
	inspect_pose_speed = 5,
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

-- Whether the player holds both buttons, which after a push makes a bash
local function local_player_holds_both()
	local player = Managers.player and Managers.player:local_player()
	local unit = player and player.player_unit
	local input_extension = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "input_system")

	return input_extension and input_extension:get("action_one_hold") and input_extension:get("action_two_hold") or false
end

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

				-- (from where the gun is: a bash punches from the end of the shove)
				return view_point(api, skin, forward + CONFIG.shove_forward * (skin.alt_pose or 0) + CONFIG.ring_speed * age, right, up)
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

		particles.beam({
			attenuation = 0.5,
			color = {
				color[1] + (other[1] - color[1]) * share,
				color[2] + (other[2] - color[2]) * share,
				color[3] + (other[3] - color[3]) * share,
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
-- A shield mesh with a material, for as long as life says and while the shield is up. brightness is a function that says how bright it is.
local function shield_mesh(api, skin, material, life, brightness)
	local mesh_unit = 0.02 -- meters of a UT unit of the mesh (make_fx_meshes.py)
	local forward, right, up = effect_start()

	particles.mesh({
		additive = 0,
		brightness = brightness,
		color = {
			1,
			1,
			1,
		},
		locked = function ()
			if not skin.shield_up then
				return nil
			end

			-- (the shove moves it ahead with the gun)
			return view_point(api, skin, forward + CONFIG.shove_forward * (skin.alt_pose or 0), right, up)
		end,
		-- (the mesh's dish faces along its y, which is the way the view looks in the frame of the first person unit, and it is not turned
		-- about anything else)
		angle = 0,
		rotation = Quaternion.identity(),
		life = life,
		material = material,
		scale = function ()
			local across = (skin.view_across_scale or 0.01) / mesh_unit * CONFIG.shield_draw_scale * CONFIG.behind_gun
			local along = (skin.view_forward_scale or 0.01) / mesh_unit * CONFIG.shield_draw_scale * CONFIG.behind_gun

			return Vector3(across, along, across)
		end,
		unit = "units/ut/fx/shield_mesh",
	})
end

-- The shield while it is up. It is not drawn while it flashes (below).
local function show_shield(api)
	local skin = api.state()

	if not skin then
		return
	end

	shield_mesh(api, skin, "units/ut/fx/fx_shield", math.huge, function ()
		return skin.flash_until and Managers.time:time("game") < skin.flash_until and 0 or 1
	end)
end

-- The shield stopping something (ShieldEffect.Flash): its other skin (fx_shield_rip) for flash_time, and BShieldReflection
local function flash_shield(api)
	local skin = api.state()

	if not skin or not skin.shield_up then
		return
	end

	skin.flash_until = Managers.time:time("game") + CONFIG.flash_time

	shield_mesh(api, skin, "units/ut/fx/fx_shield_rip", CONFIG.flash_time, function ()
		return 1
	end)
	api.play_sound("ut_shield_hit")
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

		-- (held on its last frame at the end, so that it doesn't go back to Idle before Charged is played below)
		skin.hold = true

		api.stop_sound(skin.charge_sound)

		skin.charge_sound = api.play_sound("ut_shield_charge")
		skin.charge_sound_time = CONFIG.charge_sound_length
	elseif charging and not skin.charged and skin.animation == "Charge" and skin.time >= api.animation_duration("Charge") then
		skin.charged = true

		api.play("Charged", nil, true)
	end

	-- The charge sound is UT's AmbientSound while the gun charges, which loops. The bank's sounds play once, so it is played again
	-- each time it ends. It stops when the charge does.
	if charging then
		skin.charge_sound_time = (skin.charge_sound_time or 0) - dt

		if skin.charge_sound_time <= 0 then
			skin.charge_sound = api.play_sound("ut_shield_charge")
			skin.charge_sound_time = skin.charge_sound_time + CONFIG.charge_sound_length
		end
	elseif skin.charge_sound then
		api.stop_sound(skin.charge_sound)

		skin.charge_sound = nil
	end

	if shield.last_punch and skin.seen_punch ~= shield.last_punch then
		skin.seen_punch = shield.last_punch

		api.stop_sound(skin.charge_sound)

		skin.charge_sound = nil

		api.play("Fire")
		api.play_sound("ut_shield_fire")
		force_rings(api)
	end

	-- The shove of a push, held out for a bash and through it. alt_pose moves the model (1 is the shove's distance), and the shield and
	-- the bash's rings follow it.
	local t = Managers.time:time("game")
	-- (a time after now is from before the game's clock started over, and is no push)
	local since_push = shield.last_push and t >= shield.last_push and t - shield.last_push or math.huge
	local since_bash = shield.last_bash and shield.last_push and shield.last_bash >= shield.last_push and t >= shield.last_bash and t - shield.last_bash or math.huge
	local bashing = since_bash < api.animation_duration("Fire")
	local holding = since_bash == math.huge and since_push < shield.bash_window_end and local_player_holds_both()
	local target = 0

	if since_push < CONFIG.shove_out then
		target = 1
	elseif holding or bashing then
		target = CONFIG.shove_hold
	end

	-- (the spring: pulled towards the target, held back by its speed; the step is kept small so that a long frame doesn't make it jump)
	local omega, damping = CONFIG.shove_frequency, CONFIG.shove_damping
	local shove, speed = skin.alt_pose or 0, skin.shove_speed or 0
	local left = math.min(dt, 0.1)

	while left > 0 do
		local step = math.min(left, 1 / 240)

		speed = speed + (omega * omega * (target - shove) - 2 * damping * omega * speed) * step
		shove = shove + speed * step
		left = left - step
	end

	skin.alt_pose, skin.shove_speed = shove, speed

	-- The shield is up while blocking, and while shoving or held out but for a bash. A bash's Fire animation is not cut short when it
	-- goes down.
	local shield_up = blocking or (since_push < CONFIG.shove_out or holding) and not bashing

	if shield_up ~= skin.shield_up then
		skin.shield_up = shield_up

		if shield_up then
			api.play("Shield", nil, true)
			show_shield(api)

			skin.shield_sound = api.play_sound("ut_shield_up")
		else
			api.stop_sound(skin.shield_sound)

			skin.shield_sound = nil

			if not charging and skin.animation ~= "Fire" then
				api.play("Idle")
			end
		end
	end
end

-- How the third person mesh sits in the hand (weapon_skin_third_person.lua), by the copy of the weapon: each hero holds it in the pose
-- of a weapon of their own (shield_gun.lua's pose_3p), which puts the hand differently. The mesh's origin is its grip, where UT holds it.
local GRIPS = {
	default = {
		grip_right = 0,
		grip_forward = 0,
		grip_up = 0,
		yaw = 0,
		pitch = 0,
		roll = 0,
		follow_game_unit = 1,
	},
	-- The grudge-raker's pose: the mesh is turned as the game's unit in the hand is, with no turn of its own, which holds it as the
	-- grudge-raker is held (and on the hero screen too, where it then moves with the hand)
	shield_gun_dr = {
		grip_right = 0,
		grip_forward = 0,
		grip_up = 0,
		yaw = 0,
		pitch = 0,
		roll = 0,
		follow_game_unit = 2,
	},
}

local function new_skin(setting_id)
	local definition = mod.items.weapons[setting_id]
	local grip = GRIPS[setting_id] or GRIPS.default
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
		-- The second place is the shove of a push (update_state)
		alt_pose_forward = CONFIG.shove_forward,
		-- The inspect pose brings the gun towards the middle of the view, level, and turns it to the left about its middle until it is nearly
		-- across the view, with its right side towards the player. It is still held: it runs off the bottom and the right of the view. The
		-- turn goes with the move, as the Rocket Launcher's does. The place was checked with preview_weapon.py shield: from 240 of 960
		-- across and 267 of 540 down, to both edges; it was lowered a little after that.
		inspect_pose_right = -16,
		inspect_pose_forward = 0,
		inspect_pose_up = 1,
		inspect_pose_roll = 0,
		inspect_pose_pitch = 0,
		inspect_pose_yaw = 75,
		inspect_turn_start = 0,
		inspect_pivot_right = 0,
		inspect_pivot_forward = 20,
		inspect_pivot_up = 0,
		-- Weapons.ShieldGun_3rd, ShieldAttachment's mesh (convert_static.py shield_3rd), at UT's size in a player's hand: it runs
		-- along its forward, with the emitter ahead. The game links a melee weapon to the right hand's node.
		third_person = {
			id = setting_id,
			template = definition.template,
			unit_name = "units/ut/shield/third_person",
			hand_node = "j_rightweaponattach",
			meters_per_unit = 0.02 * 0.4,
			scale = 1,
			grip_right = grip.grip_right,
			grip_forward = grip.grip_forward,
			grip_up = grip.grip_up,
			yaw = grip.yaw,
			pitch = grip.pitch,
			roll = grip.roll,
			follow_game_unit = grip.follow_game_unit,
			follow_calibrate_seconds = 1,
			muzzle_right = 0,
			muzzle_forward = 68,
			muzzle_up = 8,
			menu_yaw = -90,
		},
		on_create = function (skin)
			api.play_sound("ut_shield_select")

			-- (a punch from before the gun was put away is not played again when it is taken out, and the shield starts down, so that the
			-- first frame doesn't put it down and play Idle over the pickup)
			skin.seen_punch = shield.last_punch
			skin.shield_up = false
		end,
		on_update = function (skin, dt)
			-- (the inspect pose comes in and goes out, and holds still in between)
			skin.inspect_pose = (skin.inspect_pose or 0) + ((skin.inspecting and 1 or 0) - (skin.inspect_pose or 0)) * math.min(1, CONFIG.inspect_pose_speed * dt)

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

-- The third person: the Shield Gun of the other characters (players and bots), and the player's own in a third person view. The shield is
-- up while the character blocks, which every machine knows. The charge, the punch and the shield stopping something are told by the
-- machine that owns the character's actions (shield_gun.lua's events), which sends them to the others (ut_shield_3p). The effects are at
-- the end of the gun in the character's hand, and the sounds come from the character.
local THIRD_PERSON = {
	-- The meters of a UT unit in the world (shield_gun.lua's meters_per_uu). UT's effects are actors of their own, at the world's scale.
	meters_per_uu = 0.02,
	-- ShieldEffect3rd: UT's Shield mesh at DrawScale 3.2, ahead of the player along the aim. Here it is at the end of the gun, facing the
	-- way the gun points.
	shield_draw_scale = 3.2,
	-- ForceRing (ShieldAttachment.ThirdPersonEffects, at the gun's tip): 24 rings a second for 0.2 s, each 0.25 s long, flying out at 250
	-- units a second with the gun, of size 1 and growing by 200 a second (xEmitter's sizes are a half width, so twice that across)
	ring_rate = 24,
	ring_time = 0.2,
	ring_life = 0.25,
	ring_speed = 250, -- UT units a second
	ring_size = 2, -- UT units across
	ring_growth = 400, -- UT units across, a second
	-- The charge's sparks are the first person's, this many times larger (their spread, width and speed), so that they show from a few
	-- meters away (a choice)
	charge_scale = 3,
}

local events = shield.events

-- What each character's gun shows, as [unit] = { charge_started, spark_time, charge_sound, charge_sound_time, shield_up, shield_sound,
-- flash_until }
local characters = {}

local function now()
	return Managers.time:time("game")
end

-- The skin whose mesh the character holds in third person, or nil
local function third_person_api(unit)
	for _, api in ipairs(skin_apis) do
		if api.third_person.muzzle_position(unit) then
			return api
		end
	end
end

-- A sound that follows a character. Returns what is needed to stop it.
local function play_on_unit(event, unit)
	local id, _, wwise_world = WwiseUtils.trigger_unit_event(Managers.world:world("level_world"), event, unit)

	return id and {
		id = id,
		wwise_world = wwise_world,
	} or nil
end

local function stop_handle(handle)
	if handle then
		WwiseWorld.stop_event(handle.wwise_world, handle.id)
	end
end

local function forget(unit)
	local state = characters[unit]

	if state then
		stop_handle(state.charge_sound)
		stop_handle(state.shield_sound)

		characters[unit] = nil
	end
end

-- The shield: a mesh at the end of the gun, for as long as life says and while the shield is up
local function third_person_shield(api, unit, state, material, life, brightness)
	local scale = THIRD_PERSON.shield_draw_scale * THIRD_PERSON.meters_per_uu / 0.02 -- (0.02: the meters of a UT unit of the mesh)

	particles.mesh({
		additive = 0,
		angle = 0,
		brightness = brightness,
		color = {
			1,
			1,
			1,
		},
		follow = function ()
			if characters[unit] ~= state or not state.shield_up then
				return nil
			end

			return api.third_person.muzzle_position(unit)
		end,
		life = life,
		material = material,
		-- (the mesh's dish faces along its y, as the gun's mesh points)
		rotation = function ()
			return api.third_person.muzzle_rotation(unit) or Quaternion.identity()
		end,
		scale = function ()
			return Vector3(scale, scale, scale)
		end,
		unit = "units/ut/fx/shield_mesh",
	})
end

-- The rings of a punch, which fly ahead of the gun and move with it, and the punch's sound
local function third_person_rings(api, unit)
	local muzzle = api.third_person.muzzle_position(unit)
	local rotation = api.third_person.muzzle_rotation(unit)

	if not muzzle then
		return
	end

	local meters = THIRD_PERSON.meters_per_uu
	local count = math.floor(THIRD_PERSON.ring_rate * THIRD_PERSON.ring_time) + 1

	for i = 1, count do
		local delay = (i - 1) / THIRD_PERSON.ring_rate
		local born = now() + delay

		particles.disc({
			attenuation = 0,
			color = CONFIG.ring_color,
			delay = delay,
			follow = function ()
				local position = api.third_person.muzzle_position(unit)

				if not position then
					return nil
				end

				local age = math.max(0, now() - born)

				return position + Quaternion.forward(api.third_person.muzzle_rotation(unit)) * (THIRD_PERSON.ring_speed * age * meters)
			end,
			growth = THIRD_PERSON.ring_growth * meters,
			life = THIRD_PERSON.ring_life,
			material = "units/ut/fx/fx_force_ring",
			normal = Quaternion.forward(rotation),
			size = THIRD_PERSON.ring_size * meters,
			texture = "force_ring",
		})
	end

	api.play_sound_at("ut_shield_fire_3d", muzzle)
end

-- The sparks of the charge, made each frame while the gun charges: as the first person's, around the end of the gun, charge_scale times
-- the world's scale (UT shows no charge on another player; this is the mod's own)
local function third_person_sparks(api, unit, state, dt)
	local charged = math.min(now() - state.charge_started, shield.fully_charged_time)
	local interval = 1 / (CONFIG.charge_rate[1] + CONFIG.charge_rate[2] * charged)
	local meters = THIRD_PERSON.meters_per_uu * THIRD_PERSON.charge_scale

	state.spark_time = (state.spark_time or 0) + dt

	while state.spark_time >= interval do
		state.spark_time = state.spark_time - interval

		local spread = CONFIG.charge_spread
		local offset = Vector3(random_between({-spread, spread}), random_between({-spread, spread}), random_between({-spread, spread}))
		local distance = math.max(Vector3.length(offset), 0.001)
		local boxed = Vector3Box(offset * meters)
		local speed = CONFIG.charge_speed * charged
		local born = now()
		local color = CONFIG.charge_colors[1]
		local other = CONFIG.charge_colors[2]
		local share = math.random()

		particles.beam({
			attenuation = 0.5,
			color = {
				color[1] + (other[1] - color[1]) * share,
				color[2] + (other[2] - color[2]) * share,
				color[3] + (other[3] - color[3]) * share,
			},
			life = math.max(charged / 30, CONFIG.charge_min_life),
			material = "units/ut/fx/fx_shield_charge_spark",
			size = random_between(CONFIG.charge_width) * meters,
			texture = "shield_charge_spark",
			-- (it flies towards the end of the gun)
			track = function ()
				local center = api.third_person.muzzle_position(unit)

				if not center then
					return nil
				end

				local age = now() - born
				local at = math.max(0, distance - speed * age) / distance
				local tail = math.max(0, distance - speed * (age - CONFIG.charge_length)) / distance
				local reach = boxed:unbox()

				return center + reach * tail, center + reach * at
			end,
		})
	end
end

-- What a character's gun did, told on this machine
local function on_event(unit, event)
	local api = third_person_api(unit)

	if not api or not api.third_person.shows_weapon(unit) then
		return
	end

	local state = characters[unit] or {}

	characters[unit] = state

	if event == events.charge then
		stop_handle(state.charge_sound)

		state.charge_started = now()
		state.spark_time = 0
		state.charge_sound = play_on_unit("ut_shield_charge_3d", unit)
		state.charge_sound_time = CONFIG.charge_sound_length
	elseif event == events.charge_end or event == events.punch then
		stop_handle(state.charge_sound)

		state.charge_started = nil
		state.charge_sound = nil

		if event == events.punch then
			third_person_rings(api, unit)
		end
	elseif event == events.hit and state.shield_up then
		-- (its other skin for flash_time, as the first person's)
		state.flash_until = now() + CONFIG.flash_time

		third_person_shield(api, unit, state, "units/ut/fx/fx_shield_rip_world", CONFIG.flash_time, function ()
			return 1
		end)

		local muzzle = api.third_person.muzzle_position(unit)

		if muzzle then
			api.play_sound_at("ut_shield_hit_3d", muzzle)
		end
	end
end

-- On the machine that owns the character's actions: shown here, and sent to the others
shield.event_callbacks.skin_third_person = function (owner_unit, event)
	on_event(owner_unit, event)

	local go_id = Managers.state.unit_storage and Managers.state.unit_storage:go_id(owner_unit)

	if go_id then
		mod:network_send("ut_shield_3p", "others", go_id, event)
	end
end

mod:network_register("ut_shield_3p", function (_, go_id, event)
	local unit = Managers.state.unit_storage and Managers.state.unit_storage:unit(go_id)

	if unit and Unit.alive(unit) then
		on_event(unit, event)
	end
end)

-- Each frame: the shield of each character that blocks, and the charge's sparks and sound. A character that no longer holds the gun in
-- third person is forgotten.
mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	local players = Managers.player and Managers.player:human_and_bot_players()
	local seen = {}

	for _, player in pairs(players or {}) do
		local unit = player.player_unit
		local api = unit and Unit.alive(unit) and third_person_api(unit)

		if api and api.third_person.shows_weapon(unit) then
			local state = characters[unit] or {}
			local status_extension = ScriptUnit.has_extension(unit, "status_system")
			local blocking = status_extension and status_extension:is_blocking() or false

			characters[unit] = state
			seen[unit] = true

			if blocking ~= (state.shield_up or false) then
				state.shield_up = blocking

				if blocking then
					third_person_shield(api, unit, state, "units/ut/fx/fx_shield_world", math.huge, function ()
						return state.flash_until and now() < state.flash_until and 0 or 1
					end)

					state.shield_sound = play_on_unit("ut_shield_up_3d", unit)
				else
					stop_handle(state.shield_sound)

					state.shield_sound = nil
				end
			end

			-- (the charge sound loops as the first person's does)
			if state.charge_started then
				third_person_sparks(api, unit, state, dt)

				state.charge_sound_time = state.charge_sound_time - dt

				if state.charge_sound_time <= 0 then
					state.charge_sound = play_on_unit("ut_shield_charge_3d", unit)
					state.charge_sound_time = state.charge_sound_time + CONFIG.charge_sound_length
				end
			end
		end
	end

	for unit in pairs(characters) do
		if not seen[unit] then
			forget(unit)
		end
	end
end

local function forget_all()
	for unit in pairs(characters) do
		forget(unit)
	end
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = forget_all
mod.unload_callbacks[#mod.unload_callbacks + 1] = forget_all

-- A block stops something: the shield flashes, in first person for the player, and in third person for everyone who sees the character.
-- The machine that owns the character's actions tells the others: the player's own, and the host for its bots.
mod.block_callbacks.shield_skin = function (status_extension)
	local unit = status_extension.unit

	if utils.is_local_player_unit(unit) then
		for _, api in ipairs(skin_apis) do
			flash_shield(api)
		end
	end

	local player = Managers.player:owner(unit)
	local owned_here = utils.is_local_player_unit(unit) or player and player.bot_player and Managers.player.is_server

	if owned_here and shield.template_names[utils.wielded_template_name(unit)] then
		shield.event_callbacks.skin_third_person(unit, events.hit)
	end
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

-- The charge is shown on a copy of the game's overcharge bar. While the player holds the Shield Gun, the copy is the charge from empty to
-- full (FullyChargedTime), where the ammo counter is, in the Shield Gun's HudColor, without the overcharge's icon and glow. Its two marks
-- are where the punch becomes the next blow (shield.charge_marks). The game's own bar still shows the overcharge, which a wizard has from
-- her staff while she holds the Shield Gun. UT shows no charge; this is the mod's own.
local function show_charge_bar(bar_ui, player)
	local unit = player and player.player_unit
	local style = bar_ui.charge_bar.style

	bar_ui.ut_shield_charge = unit and utils.is_local_player_unit(unit) and shield.template_names[utils.wielded_template_name(unit)] or nil

	if not bar_ui.ut_shield_charge then
		return false
	end

	local charged = shield.charge_started and (Managers.time:time("game") - shield.charge_started) / shield.fully_charged_time or 0
	local first_mark, second_mark = shield.charge_marks[1], shield.charge_marks[2]

	-- (40 is the overcharge that makes the bar its full width: OverchargeBarUI.update_bar_size)
	bar_ui:update_bar_size(40, first_mark, second_mark)
	bar_ui:set_charge_bar_fraction(player, math.min(charged, 1), first_mark, second_mark, 0)

	for i = 1, 3 do
		style.bar_1.color[i + 1] = CONFIG.charge_bar_color[i]
	end

	-- (the game sets the icon's and the glow's alpha by how far the bar is past its upper mark, every frame)
	style.icon.color[1] = 0

	if style.frame then
		style.frame.color[1] = 0
	end

	-- (the marks as the widget is made with them, set each frame: a build of the mod that hid them left them hidden on the same widget)
	for _, name in ipairs({ "min_threshold", "max_threshold" }) do
		if style[name] then
			style[name].color[1] = CONFIG.charge_mark_alpha
		end
	end

	return true
end

local bar_definitions = local_require("scripts/ui/hud_ui/overcharge_bar_ui_definitions")
local keyboard_layout = local_require("scripts/ui/hud_ui/equipment_ui_definitions").scenegraph_definition
local gamepad_layout = local_require("scripts/ui/hud_ui/gamepad_equipment_ui_definitions").scenegraph_definition

-- The copy's nodes: its panel is placed as the equipment HUD places the ammo counter's panel (the same node, under the same root that the
-- HUD scale scales), and the bar is in the middle of it. Each equipment HUD places the counter its own way.
local function charge_bar_scenegraph(layout, root_name, panel_name)
	local panel = table.clone(layout[panel_name])

	panel.parent = root_name

	return {
		[root_name] = table.clone(layout[root_name]),
		panel = panel,
		charge_bar = {
			horizontal_alignment = "center",
			parent = "panel",
			vertical_alignment = "center",
			position = {
				0,
				0,
				1,
			},
			size = table.clone(bar_definitions.DEFAULT_BAR_SIZE),
		},
	}
end

-- Whether the HUD shows the gamepad's equipment HUD, as the two decide it (EquipmentUI._handle_gamepad)
local function uses_gamepad_layout()
	local gamepad_active = Managers.input:is_device_active("gamepad") or not IS_WINDOWS

	return (gamepad_active or UISettings.use_gamepad_hud_layout == "always") and UISettings.use_gamepad_hud_layout ~= "never"
end

-- The copies' renderer. The bar's fill is its material with how full it is set on the material (UIRenderer.draw_gradient_mask_texture),
-- and every bar a gui draws with that material in a frame gets the last one set. So the copies draw with a gui of their own, made as the
-- HUD's renderer is made (IngameUI.create_ui_renderer), whose material is not the game bar's, and the game's bar keeps its own fill.
local charge_bar_renderer, charge_bar_world

local function charge_bar_renderer_now()
	local world = Managers.world:has_world("level_world") and Managers.world:world("level_world")

	if not world then
		return
	end

	if charge_bar_world ~= world then
		charge_bar_renderer = IngameUI.create_ui_renderer(nil, world, false, false, Managers.mechanism:current_mechanism_name())
		charge_bar_world = world
	end

	return charge_bar_renderer
end

mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
	if charge_bar_renderer and Managers.world:has_world("level_world") and Managers.world:world("level_world") == charge_bar_world then
		UIRenderer.destroy(charge_bar_renderer, charge_bar_world)
	end

	charge_bar_renderer, charge_bar_world = nil, nil
end

-- The renderer's guis go with the level's world. The next level's world can be given the same handle, so it is forgotten when the level
-- ends, and the next one makes its own.
mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	charge_bar_renderer, charge_bar_world = nil, nil
end

-- Makes the copy of a player's overcharge bar, as the game makes the bar (OverchargeBarUI.create_ui_elements)
local function new_charge_bar(game_bar)
	local bar = setmetatable({}, getmetatable(game_bar))
	local definition = UIWidgets.create_overcharge_bar_widget("charge_bar", nil, nil, nil, nil, bar_definitions.DEFAULT_BAR_SIZE)

	bar.input_manager = game_bar.input_manager
	bar._side = game_bar._side
	bar.render_settings = {
		alpha_multiplier = 1,
		snap_pixel_positions = true,
	}
	bar.keyboard_scenegraph = UISceneGraph.init_scenegraph(charge_bar_scenegraph(keyboard_layout, "root_parent", "ammo_background_parent"))
	bar.gamepad_scenegraph = UISceneGraph.init_scenegraph(charge_bar_scenegraph(gamepad_layout, "root", "ammo_background"))
	bar.charge_bar = UIWidget.init(definition)

	return bar
end

-- Draws the copy as the game draws its bar (OverchargeBarUI.update), where the ammo counter is placed, as see-through as the game's bar is
local function draw_charge_bar(bar, game_bar, dt, player)
	bar.ui_scenegraph = uses_gamepad_layout() and bar.gamepad_scenegraph or bar.keyboard_scenegraph

	if not show_charge_bar(bar, player) then
		return
	end

	local ui_renderer = charge_bar_renderer_now()

	if not ui_renderer then
		return
	end

	bar.ui_renderer = ui_renderer
	bar.render_settings.alpha_multiplier = game_bar.render_settings.alpha_multiplier

	UIRenderer.begin_pass(ui_renderer, bar.ui_scenegraph, bar.input_manager:get_service("ingame_menu"), dt, nil, bar.render_settings)
	UIRenderer.draw_widget(ui_renderer, bar.charge_bar)
	UIRenderer.end_pass(ui_renderer)
end

-- The copy of each of the game's bars, made by this load of the mod. The game's HUD lives on through a reload of the mod, so a copy kept
-- on the game's bar would be the one an older build made.
local charge_bars = setmetatable({}, {
	__mode = "k",
})

-- The copy is drawn after the game's bar, every frame the HUD draws it, and goes with it
mod:hook(OverchargeBarUI, "update", function (func, self, dt, t, player, ...)
	func(self, dt, t, player, ...)

	charge_bars[self] = charge_bars[self] or new_charge_bar(self)

	draw_charge_bar(charge_bars[self], self, dt, self._is_spectator and self._spectated_player or player)
end)

-- The melee weapon's own swings are not played on the player's own first person unit: their sounds are in the animations. The skin's
-- model plays UT's. The push is the base weapon's own, so its animation is played for its sound (the arms are hidden).
for template_name in pairs(shield.template_names) do
	mod.first_person_animation_filters[template_name] = function (event)
		return event ~= "attack_push" and string.find(event, "attack", 1, true) ~= nil
	end
end
