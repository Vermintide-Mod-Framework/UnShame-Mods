local mod = get_mod("unreal_tournament")

-- Sniper Rifle skin: how UT2004's classic Sniper Rifle looks and sounds (UTClassic.ClassicSniperRifle).
--
-- weapon_skin.lua does the model, its placement and animations, the bob and the third person. This file does what is the rifle's own:
-- the shot's animation, flash, smoke and sound, the sparks and sound where the bullet hits, and the scope. The gameplay is in
-- sniper_rifle.lua, which tells this file about each shot (mod.sniper.shot_callbacks).
--
-- The assets were made with tools/asset_conversion (convert_weapon.py classic_sniper, convert_static.py classic_sniper_3rd and
-- classic_sniper_pickup, render_icon.py, make_sniper_scope.py, make_fx_assets.py and split_spark.py for the sparks, and make_bank.py
-- sniper_rifle).

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local animations = mod:dofile("scripts/mods/unreal_tournament/sniper/skin_animations")
local particles = mod.skin_particles

local CONFIG = {
	-- ClassicSniperFire.FireAnims and FireAnimRate: a shot plays one of the three at random, this much faster than its own rate
	fire_animations = { "Fire1", "Fire2", "Fire3" },
	fire_animation_rate = 1.5,
	-- AssaultMuzFlash1st at the end of the barrel (ClassicSniperFire.FlashEmitterClass): the Minigun's flash (MinigunMuzFlash1st) at
	-- DrawScale 1.2. See the Minigun's skin for what it is.
	flash_count = 5,
	flash_scale = { 0.05, 0.08 },
	flash_growth = 3,
	flash_draw_scale = 1.2,
	flash_fit = 0.5,
	flash_life = { 0.1, 0.15 },
	flash_attenuation = 0.2,
	-- AssaultMuzFlash3rd at the end of the rifle in a character's hand (ClassicSniperAttachment): drawn as the Minigun's third person
	-- flash, flames in a row along the shot, at its DrawScale of 0.6
	flame_offsets = { 8, 16, 24, 32 }, -- UT units from the muzzle
	flame_sizes = { 17, 12, 7, 4 }, -- UT units
	flame_life = 0.1,
	flame_scale = 0.6,
	-- ClassicSniperSmoke: 5 puffs within 12 units of where the shot was fired, which grow from 20 to 50 units across over their life
	-- (SizeScale 0.2 to 0.5 of 100), rise (Acceleration Z 20 units a second squared), and fade from 2 s until they are gone at 2.5 to
	-- 3 s. They are blended by their alpha. Here they rise at a speed instead, the one they have on average.
	-- In the player's own view they start in front of the eye (CollisionRadius 25 ahead, SmokeOffsetZ 10 up).
	smoke_count = 5,
	smoke_spread = 12, -- UT units
	smoke_size = { 20, 50 }, -- UT units across
	smoke_life = { 2.5, 3 },
	smoke_fade_out = 2,
	smoke_rise = 27, -- UT units a second
	smoke_ahead = 25,
	smoke_up = 10,
	-- WallSparks, where the bullet hits (SniperWallHitEffect): 8 lines at once, 0.5 to 0.8 s long, flying at 50 to 300 units a second
	-- off the surface, spread by 0.6 on each axis (mDirDev), up to 0.8 units out of place, 3 to 2 units wide (half widths, shrinking
	-- by 4 a second), 0.05 s of their travel long (mSpawnVecB.X 5), dimming from the start, added, twice as bright as the texture
	-- (ScaleGlow). They fall: xEmitter's code is not in UT's source, so the zone's gravity is used for all of them, without their mass.
	spark_count = 8,
	spark_life = { 0.5, 0.8 },
	spark_speed = { 50, 300 },
	spark_spread = 0.6,
	spark_position_spread = 0.8,
	spark_width = { 6, 4 }, -- UT units across
	spark_growth = -8, -- UT units across, a second
	spark_length = 0.05, -- seconds of travel
	spark_intensity = 2,
	spark_gravity = 950, -- UT units a second squared
	-- The scope (ClassicSniperRifle.RenderOverlays): pieces of its texture drawn black around the view, sized for a screen 1024 wide.
	-- It draws a charge bar too, but its place and size are never set, so it is not seen.
	scope_texture_size = 512,
	-- The inspect pose turns the rifle to show its left side, like the other weapons. These numbers are a guess.
	inspect_pose_speed = 5,
	inspect_sway = 5,
	inspect_sway_speed = 1.8,
}

local UNIT = utils.UT_UNIT

local sniper = mod.sniper

local VARIANTS = { "sniper_rifle", "sniper_rifle_dr" }

local TEMPLATE_NAMES = {}
local skin_apis = {}

for _, setting_id in ipairs(VARIANTS) do
	TEMPLATE_NAMES[mod.items.weapons[setting_id].template] = true
end

local random_between = utils.random_between
local attenuation = particles.attenuation

-- The skin whose model the player sees, and the one whose mesh a character holds
local function first_person_api()
	for _, api in ipairs(skin_apis) do
		if api.state() then
			return api
		end
	end
end

local function third_person_api(character)
	for _, api in ipairs(skin_apis) do
		if api.third_person.muzzle_position(character) then
			return api
		end
	end
end

-- The flash at the end of the barrel in the player's view (as the Assault Rifle's: see the Minigun's skin)
local function first_person_flash(api)
	local skin = api.state()
	local _, camera_rotation = utils.camera_pose()

	if not skin or not camera_rotation then
		return
	end

	local world_unit = (skin.unit_scale or UNIT) / api.draw_scale()
	local factor = world_unit / UNIT * CONFIG.flash_draw_scale * CONFIG.flash_fit

	for _ = 1, CONFIG.flash_count do
		local tile = math.random(0, 3)
		local life = random_between(CONFIG.flash_life)
		local start = random_between(CONFIG.flash_scale)

		particles.mesh({
			additive = 0,
			brightness = function (fraction)
				return attenuation(fraction, CONFIG.flash_attenuation)
			end,
			color = { 1, 1, 1 },
			follow = function ()
				return api.state() == skin and api.muzzle_model_position() or nil
			end,
			life = life,
			material = "units/ut/fx/fx_weapon_minigun_burst_" .. tile,
			rotation = camera_rotation,
			scale = function (fraction)
				return (start + CONFIG.flash_growth * fraction * life) * factor
			end,
			spin = 0,
			angle = math.random() * 360,
			spin_axis = Vector3(0, 1, 0),
			unit = "units/ut/fx/minigun_flash_mesh",
		})
	end
end

-- The flash at the end of the rifle in a character's hand
local function third_person_flash(muzzle, direction)
	local scale = UNIT * CONFIG.flame_scale

	for i, offset in ipairs(CONFIG.flame_offsets) do
		particles.sprite({
			attenuation = 0,
			color = { 1, 1, 1 },
			life = CONFIG.flame_life,
			position = muzzle + direction * (offset * scale),
			size = CONFIG.flame_sizes[i] * scale,
			spin = (math.random() * 2 - 1) * 0.3,
			texture = "minigun_flame_" .. math.random(0, 15),
		})
	end
end

-- The smoke of a shot, around a place in the world
local function smoke(position)
	for _ = 1, CONFIG.smoke_count do
		local z, angle = math.random() * 2 - 1, math.random() * math.pi * 2
		local across = math.sqrt(1 - z * z)
		-- (on a sphere of the spread, as PTLS_Sphere puts them)
		local offset = Vector3(across * math.cos(angle), across * math.sin(angle), z) * CONFIG.smoke_spread
		local life = random_between(CONFIG.smoke_life)

		particles.sprite({
			additive = 0,
			color = { 1, 1, 1 },
			fade_out = CONFIG.smoke_fade_out,
			growth = (CONFIG.smoke_size[2] - CONFIG.smoke_size[1]) / life * UNIT,
			life = life,
			position = position + offset * UNIT,
			size = CONFIG.smoke_size[1] * UNIT,
			spin = math.random() * 0.1,
			texture = "smoke",
			velocity = Vector3(0, 0, CONFIG.smoke_rise * UNIT),
		})
	end
end

-- The sparks where the bullet hits, off the surface. Each is a line along its way (the body of the texture) with a glow at its front.
local function wall_sparks(position, normal)
	local spread = CONFIG.spark_spread
	local now = Managers.time:time("game")

	for _ = 1, CONFIG.spark_count do
		local direction = Vector3.normalize(normal + Vector3(random_between({ -spread, spread }), random_between({ -spread, spread }), random_between({ -spread, spread })))
		local place = position + Vector3(random_between({ -1, 1 }), random_between({ -1, 1 }), random_between({ -1, 1 })) * (CONFIG.spark_position_spread * UNIT)
		local start = Vector3Box(place)
		local velocity = Vector3Box(direction * (random_between(CONFIG.spark_speed) * UNIT))
		local fall = CONFIG.spark_gravity * UNIT
		local width = random_between(CONFIG.spark_width) * UNIT
		local life = random_between(CONFIG.spark_life)

		-- Returns where the spark's head is, and where its tail is
		local function spark()
			local age = Managers.time:time("game") - now
			local moving = velocity:unbox() - Vector3(0, 0, fall * age)
			local head = start:unbox() + velocity:unbox() * age - Vector3(0, 0, 0.5 * fall * age * age)
			local speed = Vector3.length(moving)
			local heading = speed > 0.001 and moving * (1 / speed) or Vector3.up()

			return head, head - heading * math.max(width, speed * CONFIG.spark_length)
		end

		particles.beam({
			attenuation = 0,
			growth = CONFIG.spark_growth * UNIT,
			intensity = CONFIG.spark_intensity,
			life = life,
			size = width,
			texture = "wall_spark_body",
			track = function ()
				local head, tail = spark()

				return tail, head
			end,
		})
		particles.sprite({
			angle = 0,
			attenuation = 0,
			follow = function ()
				return (spark())
			end,
			growth = CONFIG.spark_growth * UNIT,
			intensity = CONFIG.spark_intensity,
			life = life,
			size = width,
			texture = "wall_spark_head",
		})
	end
end

-- A shot: the sparks and one of the six sounds where it hit, on every machine. The others also see the flash and the smoke at the rifle
-- in the character's hand, and hear the shot.
sniper.shot_callbacks.sniper_skin = function (owner_unit, hit_position, hit_normal)
	local api = skin_apis[1]

	if not api then
		return
	end

	if hit_position then
		wall_sparks(hit_position, hit_normal)
		api.play_sound_at("ut_sniper_impact_" .. math.random(1, 6) .. "_3d", hit_position)
	end

	if utils.is_local_player_unit(owner_unit) and first_person_api() and not api.third_person.shows_weapon(owner_unit) then
		return
	end

	local holder = third_person_api(owner_unit)
	local muzzle = holder and holder.third_person.muzzle_position(owner_unit)

	if muzzle then
		third_person_flash(muzzle, Quaternion.forward(holder.third_person.muzzle_rotation(owner_unit)))
		smoke(muzzle)
		holder.play_sound_at("ut_sniper_fire_3d", muzzle)
	end
end

-- The shot of the player: the animation, the flash, the smoke and the sound start when the shot's action starts, because the handgun
-- shoots at once
mod.handgun_start_callbacks.sniper_skin = function (action, new_action)
	if not new_action.ut_sniper_bullet or not utils.is_local_player_unit(action.owner_unit) then
		return
	end

	local api = first_person_api()

	if not api or api.third_person.shows_weapon(action.owner_unit) then
		return
	end

	local name = CONFIG.fire_animations[math.random(1, #CONFIG.fire_animations)]

	api.play(name, api.animation_duration(name) / CONFIG.fire_animation_rate)
	api.play_sound("ut_sniper_fire")
	first_person_flash(api)

	-- (ClassicSniperAttachment: in front of the eye)
	local camera_position, camera_rotation = utils.camera_pose()

	if camera_position then
		local forward = Vector3.normalize(Vector3.flat(Quaternion.forward(camera_rotation)))

		smoke(camera_position + forward * (CONFIG.smoke_ahead * UNIT) + Vector3(0, 0, CONFIG.smoke_up * UNIT))
	end
end

-- The scope, drawn over the player's view while zoomed. It has a screen gui of its own in the level's world, as the Lightning Gun's
-- scope does (see its skin for why).
local scope_gui, scope_world

local function scope_gui_now()
	local world = Managers.world:has_world("level_world") and Managers.world:world("level_world")

	if not world then
		return
	end

	if scope_world ~= world then
		scope_gui = World.create_screen_gui(world, "immediate", "material", "ui/ut/sniper_scope")
		scope_world = world
	end

	return scope_gui
end

mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
	if scope_gui and Managers.world:has_world("level_world") and Managers.world:world("level_world") == scope_world then
		World.destroy_gui(scope_world, scope_gui)
	end

	scope_gui, scope_world = nil, nil
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	scope_gui, scope_world = nil, nil
end

-- Canvas.DrawTile: a piece of the texture (u, v, its width and height in texels, negative to flip it) drawn into a box of the screen
-- (x, y from the top left, width, height). The gui's y goes up from the bottom of the screen, and its texture's v down from the top, as
-- UT's does.
local function tile(gui, screen_height, x, y, width, height, u, v, u_size, v_size)
	local size = CONFIG.scope_texture_size
	local u0, u1 = u / size, (u + u_size) / size
	local v0, v1 = v / size, (v + v_size) / size

	Gui.bitmap_uv(gui, "ut_sniper_scope", Vector2(u0, v0), Vector2(u1, v1), Vector3(x, screen_height - y - height, 1), Vector2(width, height), Color(255, 0, 0, 0))
end

local function draw_scope()
	if not mod.zoom.zoomed then
		return
	end

	local player = Managers.player and Managers.player:local_player_safe()
	local unit = player and player.player_unit

	if not unit or not Unit.alive(unit) or not TEMPLATE_NAMES[utils.wielded_template_name(unit)] then
		return
	end

	local gui = scope_gui_now()

	if not gui then
		return
	end

	local width, height = Application.resolution()
	local s = width / 1024
	local cx, cy = width / 2, height / 2

	-- The crosshair: two halves of the ring, the second turned around
	tile(gui, height, cx - 169 * s, cy - 155 * s, 169 * s, 310 * s, 164, 35, 169, 310)
	tile(gui, height, cx, cy - 155 * s, 169 * s, 310 * s, 332, 345, -169, -310)

	-- The bars at the corners of the middle
	tile(gui, height, 160 * s, 160 * s, 111 * s, 111 * s, 0, 0, 111, 111)
	tile(gui, height, width - 271 * s, 160 * s, 111 * s, 111 * s, 111, 0, -111, 111)
	tile(gui, height, 160 * s, height - 271 * s, 111 * s, 111 * s, 0, 111, 111, -111)
	tile(gui, height, width - 271 * s, height - 271 * s, 111 * s, 111 * s, 111, 111, -111, -111)

	-- The four corners of the screen
	tile(gui, height, 0, 0, 160 * s, 160 * s, 0, 274, 159, -158)
	tile(gui, height, width - 160 * s, 0, 160 * s, 160 * s, 159, 274, -159, -158)
	tile(gui, height, 0, height - 160 * s, 160 * s, 160 * s, 0, 116, 159, 158)
	tile(gui, height, width - 160 * s, height - 160 * s, 160 * s, 160 * s, 159, 116, -159, 158)

	-- The borders along the top and the bottom, and the sides
	tile(gui, height, 160 * s, 0, width - 320 * s, 160 * s, 284, 512, 32, -160)
	tile(gui, height, 160 * s, height - 160 * s, width - 320 * s, 160 * s, 284, 352, 32, 160)
	tile(gui, height, 0, 160 * s, 160 * s, height - 320 * s, 0, 308, 160, 32)
	tile(gui, height, width - 160 * s, 160 * s, 160 * s, height - 320 * s, 160, 308, -160, 32)
end

mod.ingame_ui_post_update_callbacks.sniper_scope = draw_scope

-- The skin of each of the two items
local function new_skin(setting_id)
	local definition = mod.items.weapons[setting_id]
	local api

	api = mod.weapon_skin.new({
		id = setting_id,
		name = "sniper rifle",
		template = definition.template,
		unit_name = "units/ut/sniper/sniper_rifle",
		animations = animations,
		muzzle_node = "b_dummy01",
		-- model_meters_per_unit is the meters per UT unit at which the model was converted (tools/asset_conversion/convert_weapon.py).
		-- meters_per_unit is the distance scale: the meters of forward in the view that one UT unit of the model takes up.
		model_meters_per_unit = 0.0125,
		meters_per_unit = 0.01,
		-- ClassicSniperRifle.uc
		display_fov = 60,
		draw_scale = 0.48,
		select_speed = 0.75, -- SelectAnimRate
		offset_forward = 27.7,
		offset_right = 5.3,
		offset_up = -10.6,
		pivot_yaw = 90, -- PlayerViewPivot (Yaw=16384)
		bob_damping = 2.3,
		inspect_pose_right = -10,
		inspect_pose_forward = 2,
		inspect_pose_up = 2,
		inspect_pose_roll = 10,
		inspect_pose_pitch = 4,
		inspect_pose_yaw = 55,
		inspect_turn_start = 0.35,
		inspect_pivot_right = 0,
		inspect_pivot_forward = 30,
		inspect_pivot_up = 0,
		-- NewWeapons2004.Sniper3rd (ClassicSniperAttachment, DrawScale 0.16). The game links the handgun to the left hand's node
		-- (AttachmentNodeLinking.rifles), and the mesh turns with the game's handgun in that hand, as it is (checked on the hero screen and
		-- in third person for Kruber and Bardin).
		third_person = {
			id = setting_id,
			template = definition.template,
			unit_name = "units/ut/sniper/third_person",
			hand_node = "j_leftweaponattach",
			meters_per_unit = 0.02 * 0.16,
			scale = 1,
			grip_right = 0,
			grip_forward = 0,
			grip_up = 0,
			yaw = 0,
			pitch = 0,
			roll = 0,
			follow_game_unit = 2,
			follow_calibrate_seconds = 1,
			muzzle_right = 0,
			muzzle_forward = 209,
			muzzle_up = -35,
			menu_yaw = -90,
		},
		-- UT draws the scope in place of the weapon while zoomed (ClassicSniperRifle.RenderOverlays)
		hidden = function ()
			return mod.zoom.zoomed
		end,
		on_create = function ()
			api.play_sound("ut_sniper_select")
		end,
		on_update = function (skin, dt)
			skin.inspect_pose = (skin.inspect_pose or 0) + ((skin.inspecting and 1 or 0) - (skin.inspect_pose or 0)) * math.min(1, CONFIG.inspect_pose_speed * dt)
			skin.inspect_time = skin.inspecting and (skin.inspect_time or 0) + dt or 0
			skin.extra_yaw = skin.inspect_pose * CONFIG.inspect_sway * math.sin(skin.inspect_time * CONFIG.inspect_sway_speed)

			-- The zoom has its sound when it starts and when it ends: the Lightning Gun's (RenderOverlays plays LightningZoomIn and Out)
			local zoomed = mod.zoom.zoomed

			if zoomed ~= skin.was_zoomed then
				if skin.was_zoomed ~= nil then
					api.play_sound(zoomed and "ut_lightning_zoom_in" or "ut_lightning_zoom_out")
				end

				skin.was_zoomed = zoomed
			end
		end,
	})

	skin_apis[#skin_apis + 1] = api

	return api
end

for _, setting_id in ipairs(VARIANTS) do
	new_skin(setting_id)
end

-- Inspecting is the game's own action, held with the key
mod.inspect_callbacks.sniper_skin = function (action, started)
	for _, api in ipairs(skin_apis) do
		local skin = api.state()

		if skin and utils.is_local_player_unit(action.owner_unit) then
			skin.inspecting = started
		end
	end
end

-- The handgun's shot and reload sounds and animations are the game's own, so they are not played on the player's own first person unit.
-- The skin's model plays UT's animations instead.
for template_name in pairs(TEMPLATE_NAMES) do
	mod.first_person_animation_filters[template_name] = function (event)
		return event == "attack_shoot" or event == "attack_shoot_last" or string.find(event, "reload", 1, true) ~= nil or string.find(event, "zoom", 1, true) ~= nil
	end

	-- The reload animation is not played on the characters, because the weapon has no reload.
	mod.third_person_animation_filters[template_name] = function (event)
		return string.find(event, "reload", 1, true) ~= nil
	end
end
