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

local utils = mod.utils
local animations = mod:dofile("scripts/mods/unreal_tournament/sniper/skin_animations")
local particles = mod.skin_particles

local CONFIG = {
	-- ClassicSniperFire.FireAnims and FireAnimRate: a shot plays one of the three at random, this much faster than its own rate
	fire_animations = { "Fire1", "Fire2", "Fire3" },
	fire_animation_rate = 1.5,
	-- AssaultMuzFlash1st at the end of the barrel (ClassicSniperFire.FlashEmitterClass): the Minigun's flash at DrawScale 1.2 (see
	-- muzzle_flash.lua), with MinigunMuzFlash1st's numbers at UT's size. The Minigun's own is drawn at half of it (its fit), which was
	-- fitted to pictures of UT with a blend that showed the flash bigger than it is; on this rifle that looked too small.
	flash_draw_scale = 1.2,
	muzzle_flash = {
		count = 5,
		scale = { 0.05, 0.08 },
		growth = 3,
		life = { 0.1, 0.15 },
		attenuation = 0.2,
		color = { 1, 1, 1 },
		fit = 1,
	},
	-- AssaultMuzFlash3rd at the end of the rifle in a character's hand (ClassicSniperAttachment, which sets its DrawScale to 1): one mesh
	-- (MinigunMuzFlash3rd's MinigunFlashMesh, as the Rocket Launcher's third person flash) for a shot, of a size of 0.05 to 0.08 that
	-- grows by 2.2 a second, for 0.15 to 0.2 s, turned at random about the barrel (mRandOrient). fit is the Minigun's (muzzle_flash.lua).
	muzzle_flash_3rd = {
		size = {0.05, 0.08},
		growth = 2.2,
		life = {0.15, 0.2},
		attenuation = 0.2,
		fit = 0.5,
	},
	-- ClassicSniperSmoke: 5 puffs within 12 units of where the shot was fired, which grow from 20 to 50 units across over their life
	-- (SizeScale 0.2 to 0.5 of 100), rise from still (Acceleration Z 20 units a second squared), and fade from 2 s until they are gone at
	-- 2.5 to 3 s. They are blended by their alpha.
	-- In the player's own view they start in front of the eye (CollisionRadius 25 ahead, SmokeOffsetZ 10 up).
	smoke_count = 5,
	smoke_spread = 12, -- UT units
	-- (a UE2 sprite's size is its radius, so they are drawn twice as wide; each is a frame of SmokeReOrdered at random)
	smoke_size = { 20, 50 }, -- UT units, radius
	smoke_life = { 2.5, 3 },
	smoke_fade_out = 2,
	smoke_rise = 20, -- UT units a second squared
	-- (set from pictures of UT, where the smoke starts at the eye's height, not the 10 above it of SmokeOffsetZ, and is an even light
	-- grey with faint darker spots: its texture's colour is moved half way to white, make_weapon_fx.py's LIGHTENED)
	smoke_ahead = 25,
	smoke_up = 0,
	smoke_color = { 0.85, 0.85, 0.85 },
	-- The weapon's light (xWeaponAttachment.WeaponLight): every shot turns it on for 0.15 s, at the rifle in a character's hand. There
	-- is none in the player's own first person view, where it would light the gun the player holds (as for the Lightning Gun).
	-- ClassicSniperAttachment's LightHue 30 of 255 and LightSaturation 170 (0 is all colour, 255 is white) are a pale orange, and
	-- LightRadius 5 is in steps of 25 units: 2.5 m.
	light_color = { 1, 0.9, 0.67 },
	light_falloff = 2.5, -- meters
	light_life = 0.15, -- s
	-- SniperWallHitEffect: the puffs where the bullet hits (pclImpactSmoke) are made when the local player's view is within 3000 units
	impact_smoke_range = 3000, -- UT units
	-- SniperWallHitEffect: a bullet that passes within 150 units of the middle of the local player's character (Pawn.Location, its
	-- collision's middle, CollisionHeight 44 above its feet) plays one of two sounds at the nearest point of its line. The line goes on
	-- past both ends, so the player who fires hears it too.
	whiz_distance = 150, -- UT units
	whiz_body_height = 44, -- UT units
	-- TracerProjectile, which UT spawns for another player's shot and a bot's: a flak chunk's mesh at DrawScale 5 (a flak chunk is 14,
	-- flak/skin.lua's chunk_scale 0.75) with a flak chunk's streak (FlakTrail), flying at 20000 units a second through what it hits but
	-- walls, for up to 2 s (see add_tracer for where it starts). The streak is drawn as the Flak Cannon's (flak/skin.lua).
	tracer_scale = 0.75 * 5 / 14,
	tracer_speed = 20000, -- UT units a second
	tracer_life = 2, -- s
	tracer_trail_seconds = 0.1,
	tracer_trail_step = 1 / 60,
	tracer_trail_width = 0.1, -- m
	tracer_trail_intensity = 2,
	tracer_trail_hold = 0.4,
	-- The scope (ClassicSniperRifle.RenderOverlays): pieces of its texture drawn black around the view, sized for a screen 1024 wide.
	-- It draws a charge bar too, but its place and size are never set, so it is not seen.
	scope_texture_size = 512,
	zoom_fade_time = 0.3, -- seconds, HudCDeathmatch.FadeTime
	-- The inspect pose turns the rifle to show its left side, like the other weapons. It sways less than the others (2 degrees, not
	-- 5): the rifle is long, so the same turn moves its ends far more.
	inspect_pose_speed = 5,
	inspect_sway = 2,
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

local function first_person_api()
	return mod.weapon_skin.shown_skin(skin_apis)
end

local function third_person_api(character)
	local _, api = mod.weapon_skin.held_muzzle(skin_apis, character)

	return api
end

-- The flash at the end of the barrel in the player's view (as the Assault Rifle's: see the Minigun's skin)
local function first_person_flash(api)
	local skin = api.state()

	if not skin then
		return
	end

	mod.muzzle_flash(api, function ()
		return api.state() == skin and api.muzzle_model_position() or nil
	end, (skin.unit_scale or UNIT) / api.draw_scale(), CONFIG.flash_draw_scale, nil, CONFIG.muzzle_flash)
end

-- The flash at the end of the rifle in a character's hand: the mesh is in UT units of the world, and points along the barrel, which runs
-- along the rifle mesh's forward, as the flash mesh's does
local function third_person_flash(owner_unit, holder)
	local third_person = holder.third_person
	local settings = CONFIG.muzzle_flash_3rd
	local life = random_between(settings.life)
	local size = random_between(settings.size)

	particles.mesh({
		additive = 0,
		brightness = function (fraction)
			return particles.attenuation(fraction, settings.attenuation)
		end,
		color = { 1, 1, 1 },
		follow = function ()
			return third_person.muzzle_position(owner_unit)
		end,
		life = life,
		material = "units/ut/fx/fx_minigun_flash_3rd",
		rotation = function ()
			return third_person.muzzle_rotation(owner_unit) or Quaternion.identity()
		end,
		scale = function (fraction)
			return (size + settings.growth * fraction * life) * settings.fit
		end,
		spin = 0,
		angle = math.random() * 360,
		spin_axis = Vector3(0, 1, 0),
		unit = "units/ut/fx/minigun_flash_3rd_mesh",
	})
end

-- The smoke of a shot, around a place in the world
local function smoke(position)
	for _ = 1, CONFIG.smoke_count do
		local z, angle = math.random() * 2 - 1, math.random() * math.pi * 2
		local across = math.sqrt(1 - z * z)
		-- (on a sphere of the spread, as PTLS_Sphere puts them)
		local offset = Vector3(across * math.cos(angle), across * math.sin(angle), z) * CONFIG.smoke_spread
		local life = random_between(CONFIG.smoke_life)
		local start = Vector3Box(position + offset * UNIT)
		local born = Managers.time:time("game")

		particles.sprite({
			additive = 0,
			color = CONFIG.smoke_color,
			fade_out = CONFIG.smoke_fade_out,
			follow = function ()
				local age = Managers.time:time("game") - born

				return start:unbox() + Vector3(0, 0, 0.5 * CONFIG.smoke_rise * age * age * UNIT)
			end,
			growth = 2 * (CONFIG.smoke_size[2] - CONFIG.smoke_size[1]) / life * UNIT,
			life = life,
			size = 2 * CONFIG.smoke_size[1] * UNIT,
			spin = math.random() * 0.1,
			texture = "sniper_smoke_" .. math.random(0, 15),
		})
	end
end

-- The light of a shot at the rifle in a character's hand
local function weapon_light(owner_unit, holder)
	particles.light({
		brightness = function ()
			return 1
		end,
		color = CONFIG.light_color,
		falloff = CONFIG.light_falloff,
		follow = function ()
			return holder.third_person.point_position(owner_unit, 0, 0, 0)
		end,
		intensity = utils.WEAPON_LIGHT_INTENSITY,
		life = CONFIG.light_life,
	})
end

-- The sound of a bullet passing the local player's character, at the nearest point of its line
local function whiz(api, start, direction)
	local player = Managers.player:local_player()
	local unit = player and player.player_unit

	if not unit or not Unit.alive(unit) then
		return
	end

	local middle = Unit.world_position(unit, 0) + Vector3(0, 0, CONFIG.whiz_body_height * UNIT)
	local nearest = start + direction * Vector3.dot(direction, middle - start)

	if Vector3.distance(middle, nearest) < CONFIG.whiz_distance * UNIT then
		api.play_sound_at("ut_sniper_whiz_" .. math.random(1, 2) .. "_3d", nearest)
	end
end

-- The tracers in flight, each { unit, world, from, to, travelled, length, trail_from, trail_time }
local tracers = {}

local function destroy_tracers()
	for _, tracer in ipairs(tracers) do
		if Unit.alive(tracer.unit) then
			World.destroy_unit(tracer.world, tracer.unit)
		end
	end

	table.clear(tracers)
end

-- A tracer of a bullet that started at start along direction. UT's starts where the bullet does, at the eye; here it starts at the
-- muzzle of the rifle in the shooter's hand when there is one, which shows where the shot came from, and flies to where UT's would end.
local function add_tracer(start, direction, muzzle)
	local world = Managers.world:has_world("level_world") and Managers.world:world("level_world")

	if not world then
		return
	end

	-- (it goes until it hits a wall: the level, not the characters)
	local reach = CONFIG.tracer_speed * CONFIG.tracer_life * UNIT
	local hit, _, distance = PhysicsWorld.immediate_raycast(World.physics_world(world), start, direction, reach, "closest", "collision_filter", "filter_player_ray_projectile_static_only")
	local finish = start + direction * (hit and distance or reach)

	if muzzle and Vector3.distance(muzzle, finish) > 0.01 then
		start = muzzle
		direction = Vector3.normalize(finish - muzzle)
	end

	local length = Vector3.distance(start, finish)
	local unit = World.spawn_unit(world, "units/ut/flak/chunk", start, Quaternion.look(direction, Vector3.up()))

	Unit.set_local_scale(unit, 0, Vector3(CONFIG.tracer_scale, CONFIG.tracer_scale, CONFIG.tracer_scale))

	-- (how many there have been, for the tests: one can be gone in a frame)
	sniper.tracers_made = (sniper.tracers_made or 0) + 1

	tracers[#tracers + 1] = {
		direction = Vector3Box(direction),
		from = Vector3Box(start),
		length = length,
		trail_from = Vector3Box(start),
		trail_time = 0,
		travelled = 0,
		unit = unit,
		world = world,
	}
end

local function update_tracers(dt)
	for i = #tracers, 1, -1 do
		local tracer = tracers[i]

		tracer.travelled = math.min(tracer.travelled + CONFIG.tracer_speed * UNIT * dt, tracer.length)

		local position = tracer.from:unbox() + tracer.direction:unbox() * tracer.travelled

		Unit.set_local_position(tracer.unit, 0, position)

		tracer.trail_time = tracer.trail_time + dt

		if tracer.trail_time >= CONFIG.tracer_trail_step or tracer.travelled >= tracer.length then
			tracer.trail_time = math.min(tracer.trail_time - CONFIG.tracer_trail_step, CONFIG.tracer_trail_step)

			particles.beam({
				color = { 1, 1, 1 },
				fade_in = 0,
				fade_out = CONFIG.tracer_trail_seconds * CONFIG.tracer_trail_hold,
				from = tracer.trail_from:unbox(),
				intensity = CONFIG.tracer_trail_intensity,
				life = CONFIG.tracer_trail_seconds,
				size = CONFIG.tracer_trail_width,
				texture = "flak_trail",
				to = position,
			})

			tracer.trail_from:store(position)
		end

		if tracer.travelled >= tracer.length then
			World.destroy_unit(tracer.world, tracer.unit)
			table.remove(tracers, i)
		end
	end
end

mod.update_callbacks[#mod.update_callbacks + 1] = update_tracers
mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = destroy_tracers
mod.unload_callbacks[#mod.unload_callbacks + 1] = destroy_tracers

-- A shot, on every machine: the sparks and one of the six sounds where it hit, with the puffs if the view is near, and the sound of the
-- bullet passing the local player. Another player's shot or a bot's has a tracer. The others also see the flash, the light and the smoke
-- at the rifle in the character's hand, and hear the shot.
sniper.shot_callbacks.sniper_skin = function (owner_unit, hit_position, hit_normal, start, direction)
	local api = skin_apis[1]

	if not api then
		return
	end

	if hit_position then
		mod.hit_effects.wall_sparks(hit_position, hit_normal)
		api.play_sound_at("ut_sniper_impact_" .. math.random(1, 6) .. "_3d", hit_position)

		local camera_position = utils.camera_pose()

		if camera_position and Vector3.distance(camera_position, hit_position) < CONFIG.impact_smoke_range * UNIT then
			mod.hit_effects.impact_smoke(hit_position, hit_normal)
		end
	end

	local holder = third_person_api(owner_unit)
	local muzzle = holder and holder.third_person.muzzle_position(owner_unit)

	if start then
		whiz(api, start, direction)

		if not utils.is_local_player_unit(owner_unit) then
			add_tracer(start, direction, muzzle)
		end
	end

	if utils.is_local_player_unit(owner_unit) and first_person_api() and not api.third_person.shows_weapon(owner_unit) then
		return
	end

	if muzzle then
		third_person_flash(owner_unit, holder)
		weapon_light(owner_unit, holder)
		smoke(muzzle)
		holder.play_sound_at("ut_sniper_fire_3d", muzzle)
	end
end

-- A shot while the zoom is in: the character aims again in third person once the shot is far enough along, as the base's zoomed shot
-- does (sniper_rifle.lua's rezoom_time). This is in either view.
local rezoom_at

mod.handgun_start_callbacks.sniper_rezoom = function (action, new_action)
	local animations = mod.sniper_zoom_animations[utils.wielded_template_name(action.owner_unit)]

	if new_action.ut_sniper_bullet and animations and animations.rezoom_time and mod.zoom.zoomed and utils.is_local_player_unit(action.owner_unit) then
		rezoom_at = Managers.time:time("game") + animations.rezoom_time
	end
end

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	if not rezoom_at or Managers.time:time("game") < rezoom_at then
		return
	end

	rezoom_at = nil

	local player = Managers.player:local_player()
	local unit = player and player.player_unit
	local animations = unit and Unit.alive(unit) and mod.sniper_zoom_animations[utils.wielded_template_name(unit)]

	if animations and mod.zoom.zoomed then
		Managers.state.network:anim_event(unit, animations.zoom_in)
	end
end

-- (the game's time starts again in each level)
mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	rezoom_at = nil
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

-- The scope, drawn over the player's view while zoomed. It has a screen gui of its own in the level's world (utils.level_screen_gui).
local scope_gui_now = utils.level_screen_gui("ui/ut/sniper_scope")

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
	if not mod.zoom.in_view() then
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

-- When the zoom goes in or out, the view fades in from black (ClassicSniperRifle.WantsZoomFade: HudCDeathmatch.ZoomFadeOut draws black
-- over the screen, from opaque to clear over its FadeTime), over the scope
local function draw_zoom_fade()
	local toggled_at = mod.zoom.toggled_at
	local passed = toggled_at and Managers.time:time("game") - toggled_at

	-- (a time ahead of now is not a fade, as ZoomFadeOut takes it: the game's time starts again in each level)
	if not passed or passed < 0 or passed >= CONFIG.zoom_fade_time then
		return
	end

	local player = Managers.player and Managers.player:local_player_safe()
	local unit = player and player.player_unit
	local first_person_extension = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "first_person_system")

	if not first_person_extension or not first_person_extension:first_person_mode_active() or not TEMPLATE_NAMES[utils.wielded_template_name(unit)] then
		return
	end

	local gui = scope_gui_now()

	if gui then
		local width, height = Application.resolution()

		Gui.rect(gui, Vector3(0, 0, 2), Vector2(width, height), Color(255 * (1 - passed / CONFIG.zoom_fade_time), 0, 0, 0))
	end
end

mod.ingame_ui_post_update_callbacks.sniper_zoom_fade = draw_zoom_fade

-- The skin of each of the two items
-- How the third person mesh sits in each copy's hand: Kruber's and Bardin's hold the handgun differently (set in the game)
local GRIPS = {
	sniper_rifle = { right = -5, forward = -65, up = -15, pitch = -7 },
	sniper_rifle_dr = { right = 3, forward = -40, up = -10, pitch = -7 },
}

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
		-- (the rifle is long: it is held further away and to the left, so that the receiver and the scope show, and turned less than
		-- the others, as its far side has no faces; it turns as it moves, about its middle; checked with preview_weapon.py)
		inspect_pose_right = -25,
		inspect_pose_forward = 25,
		inspect_pose_up = 2,
		inspect_pose_roll = 10,
		inspect_pose_pitch = 4,
		inspect_pose_yaw = 45,
		inspect_turn_start = 0,
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
			grip_right = GRIPS[setting_id].right,
			grip_forward = GRIPS[setting_id].forward,
			grip_up = GRIPS[setting_id].up,
			yaw = 0,
			pitch = GRIPS[setting_id].pitch,
			roll = 0,
			follow_game_unit = 2,
			-- (the middle of the end of the barrel, the front of the mesh)
			muzzle_right = -2,
			muzzle_forward = 209,
			muzzle_up = 15,
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

			-- The zoom's sounds are the Lightning Gun's (RenderOverlays plays LightningZoomIn and Out)
			local zoomed = mod.zoom.zoomed

			if zoomed ~= skin.was_aiming then
				-- The character aims as with the base weapon's zoom, in third person, which the other players see too
				if skin.was_aiming ~= nil then
					local player = Managers.player:local_player()
					local unit = player and player.player_unit
					local animations = unit and mod.sniper_zoom_animations[utils.wielded_template_name(unit)]

					if animations then
						Managers.state.network:anim_event(unit, zoomed and animations.zoom_in or animations.zoom_out)
					end
				end

				skin.was_aiming = zoomed
			end

			mod.zoom.sound(skin, api)
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

	-- The characters' shot animation would have the handgun's unit play its shot sound and muzzle flash, at the handgun's muzzle. The
	-- skin plays UT's.
	mod.third_person_weapons_hidden_from_flow[template_name] = true
end
