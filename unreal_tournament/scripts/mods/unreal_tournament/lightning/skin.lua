local mod = get_mod("unreal_tournament")

-- Lightning Gun skin: how UT2004's Lightning Gun looks and sounds.
--
-- weapon_skin.lua does the model, its placement and animations, the bob and the third person. This file does what is the Lightning Gun's
-- own: the bolt and its arcs, the sparks where it hits, the charge at the tip, the sounds, and the scope. The gameplay is in
-- lightning_gun.lua. This file only draws it, and is told what happens through the hook tables in hooks.lua.
--
-- The assets were made with tools/asset_conversion (convert_weapon.py sniper, convert_static.py sniper_pickup, make_sniper_screen.py,
-- make_lightning_assets.py and make_bank.py lightning_gun).

local utils = mod.utils
local animations = mod:dofile("scripts/mods/unreal_tournament/lightning/skin_animations")
local particles = mod.skin_particles

local CONFIG = {
	fire_animation_rate = 1.25, -- SniperFire.FireAnimRate: the Fire animation plays this much faster than its own rate
	-- NewLightningBolt (PT_Branch) is 30 particles of size 30, each out of place by up to 5 units (mPosDev). It is drawn as a line of
	-- parts of the streak texture (the upper half of LightningBoltT), each bolt_width units wide and bolt_stretch times that long, so the
	-- texture's zigzag is drawn out along the bolt. The corners between the parts are out of line by up to bolt_jitter units, about a
	-- quarter of a part, which makes the bolt ragged as in pictures of UT2004 (at mPosDev's 5, and parts twice as long as wide, the
	-- zigzag repeated evenly and tightly; set against those pictures). How PT_Branch lays the
	-- texture along the bolt is in UT's engine, not its scripts: one part for each of the 30 particles, squeezed along a short bolt,
	-- looked like a hatched band in pictures, not UT's thin ragged line. It is the same emitter as the flare, so it fades the same way
	-- (flare_life). In pictures of UT2004 its streaks look like the texture added once (white middles, thin blue edges), while the flare
	-- is 9 times the texture: the particles all add their flare at the start, but their streaks lie along the bolt.
	bolt_width = 30, -- UT units
	bolt_stretch = 8, -- a part's length, in widths
	bolt_jitter = 60, -- UT units
	bolt_intensity = 1,
	-- ChildLightningBolt: 10 particles of size 15, out of place by up to 15 units. In pictures of UT2004 an arc is the texture drawn out
	-- along a few long parts with gentle bends, so its parts are longer than the bolt's (set against those pictures).
	arc_width = 15,
	arc_stretch = 16, -- a part's length, in widths
	arc_jitter = 30,
	arc_life = 0.5,
	arc_intensity = 1,
	-- The flare where the bolt starts and ends (the lower half of LightningBoltT). It is 30 units wide, the size of NewLightningBolt's
	-- particles. In pictures of UT2004 taken 25 ms apart, it starts at 9 times the texture, which makes a white disk with a blue rim, and
	-- dims evenly until it is gone 0.4 s after the shot, showing the ring and the spikes on the way.
	flare_size = 30,
	flare_life = 0.4,
	flare_intensity = 9,
	-- Where the flare is in the player's view (right, forward, up, UT units from the eye) and how wide it is. SniperRifle.EffectOffset
	-- is (28, 100, -26), and these are fitted to a picture of UT2004, which has the eye's bob and the view's height in it too.
	flare_view_offset = {25, 100, -19.8},
	flare_view_size = 44,
	-- The flare in the player's view is drawn at this share of the distance to the weapon's muzzle. UT draws it in the world, behind the
	-- whole weapon.
	flare_view_depth = 1.2,
	-- ChildBlueSparks: each arc (ChildLightningBolt) throws 10 sparks from where it starts, which is where the bolt hit. They fly along
	-- the arc's hit normal, up to 0.6 off it in each axis (mDirDev), at 250 to 350 units a second, slowed by 0.2 of their speed a second
	-- (mAirResistance), and last 0.8 to 1.2 s. Each is a line (PT_Line) 2 to 3 units wide that thins by 3 units a second. Its length
	-- goes with its speed: spark_length seconds of its travel, which is UT's mSpawnVecB.X of 5 in hundredths of a second, fitted to
	-- pictures of UT2004. They are twice as bright as the texture (ScaleGlow).
	spark_count = 10,
	spark_life = {0.8, 1.2},
	spark_speed = {250, 350},
	spark_direction_spread = 0.6,
	spark_air_resistance = 0.2,
	-- They fall: xEmitter pulls a particle by the zone's gravity times its mass (mMassRange 1.5 to 2.5), as a negative mass makes smoke
	-- rise
	spark_gravity = 950, -- UT units a second squared (PhysicsVolume's)
	spark_mass = {1.5, 2.5},
	spark_width = {2, 3}, -- UT units
	spark_thinning = 3, -- UT units a second
	spark_length = 0.05, -- seconds of travel
	spark_attenuation = 0.1,
	spark_intensity = 2,
	-- LightningCharge: 10 sparks a second at the tip, each 0.2 s long, one of the four pictures of the texture, turned at random. They
	-- stop while the weapon cannot fire (its next shot is not yet due, or it has no ammo: here, it is locked out). The emitter is attached
	-- to the model's tip, 30 of the model's units behind it along the barrel (RelativeLocation, in the bone's frame), and its sparks move
	-- with it (mPosRelative). Its own numbers are in the units of the view, as the emitter isn't drawn at the model's DrawScale: each spark
	-- is up to 10 units from it along the barrel (mPosDev), so some are out in front of the tip, and 5 units in size (mSizeRange), a half
	-- width. So the sparks fill the cage and reach out past the tip, as in pictures of UT2004. They are a little smaller here (set in the
	-- game): at 10 across they came through the front of the gun.
	charge_rate = 10,
	charge_life = 0.2,
	charge_size = 4, -- half width, units of the view
	charge_back = 30, -- the model's units
	charge_spread = 10, -- units of the view
	-- How bright the sparks are (fitted to a picture of UT2004)
	charge_intensity = 0.45,
	-- Where the bolt starts when the view is zoomed: SniperFire puts it at the player's middle (EffectOffset.Z, 26 units, below), so it
	-- comes from the bottom of the screen
	zoomed_start_down = 1, -- m below the camera
	-- The scope (SniperRifle.RenderOverlays). These are in the units of a screen of 640 by 480.
	scope_focus_x = 135,
	scope_focus_y = 105,
	scope_arrows_x = 42,
	scope_arrows_y = 42,
	-- alpha, red, green, blue. FocusColor's alpha is 215, but RenderOverlays sets it to 255 before it draws.
	scope_focus_color = { 255, 71, 90, 126 },
	scope_arrow_color = { 255, 255, 0, 0 },
	scope_bar_origin_x = 600,
	scope_bar_origin_y = 330,
	scope_bar_width = 10,
	scope_bar_height = 180,
	-- How long a shot lights up the weapon's third person model
	inspect_pose_speed = 5, -- how fast the model moves to the inspect pose and back, per second
	-- While the gun is locked out by overheating, it is held turned on its side, low, as the Deepwood Staff is held across the view then
	-- (the mod's own: UT's gun doesn't overheat). It moves there and back at this rate a second.
	lockout_pose_speed = 4,
	inspect_sway = 5, -- degrees of yaw each way while inspecting
	inspect_sway_speed = 1.8, -- radians per second
}

local UNIT = utils.UT_UNIT

local lightning = mod.lightning

local TEMPLATES = {
	{
		id = "lightning_gun",
		setting_id = "lightning_gun",
	},
}

-- Whether the local player's gun is locked out by overheating (the Deepwood Staff's overheat, see lightning_gun.lua)
local function locked_out()
	local player = Managers.player and Managers.player:local_player()
	local unit = player and player.player_unit
	local overcharge_extension = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "overcharge_system")

	return overcharge_extension and overcharge_extension:are_you_locked_out() or false
end

local TEMPLATE_NAMES = {}
local skin_apis = {}

for _, variant in ipairs(TEMPLATES) do
	TEMPLATE_NAMES[mod.items.weapons[variant.setting_id].template] = true
end

local random_between = utils.random_between

-- The most parts a bolt is drawn with. A long bolt has longer parts instead, far away where they are small on the screen.
local MAX_BOLT_PARTS = 100

-- The bolt: a line of parts, each a streak of the texture stretch times as long as it is wide, out of line by a little. A part runs from
-- the end of the one before it.
local function draw_bolt(from, to, width, stretch, jitter, life, intensity)
	local offset = to - from
	local length = Vector3.length(offset)

	if length < 0.01 then
		return
	end

	local count = math.clamp(math.ceil(length / (stretch * width)), 1, MAX_BOLT_PARTS)
	local direction = offset * (1 / length)
	local across = Vector3.cross(direction, Vector3.up())

	if Vector3.length(across) < 0.01 then
		across = Vector3.cross(direction, Vector3.right())
	end

	across = Vector3.normalize(across)

	local other = Vector3.cross(direction, across)
	local previous = from

	for i = 1, count do
		local point = to

		if i < count then
			point = from + direction * (length * i / count) + across * ((math.random() * 2 - 1) * jitter) + other * ((math.random() * 2 - 1) * jitter)
		end

		particles.beam({
			attenuation = 0,
			color = {
				1,
				1,
				1,
			},
			from = previous,
			intensity = intensity,
			life = life,
			size = width,
			texture = "lightning_bolt",
			to = point,
		})

		previous = point
	end
end

-- A flare at a place. The material is the texture's own, or another one for the flare in the player's view (see show_bolt).
local function flare(position, size, material)
	particles.sprite({
		material = material,
		attenuation = 0,
		color = {
			1,
			1,
			1,
		},
		intensity = CONFIG.flare_intensity,
		life = CONFIG.flare_life,
		position = position,
		size = size,
		spin = (math.random() * 2 - 1) * 0.2,
		texture = "lightning_flare",
	})
end

-- The sparks an arc throws from where it starts (ChildBlueSparks), along the arc's hit normal. Each is a streak from where it is back
-- along its velocity, drawn as a beam that follows it.
local function sparks(position, normal)
	local spread = CONFIG.spark_direction_spread
	local air = CONFIG.spark_air_resistance

	for _ = 1, CONFIG.spark_count do
		local direction = Vector3.normalize(normal + Vector3(random_between({-spread, spread}), random_between({-spread, spread}), random_between({-spread, spread})))
		local velocity = Vector3Box(direction * (random_between(CONFIG.spark_speed) * UNIT))
		local start = Vector3Box(position)
		local born = Managers.time:time("game")
		local width = random_between(CONFIG.spark_width)
		-- (the pull of gravity on it, and the speed it would fall at in the air: gravity / air)
		local fall = CONFIG.spark_gravity * random_between(CONFIG.spark_mass) * UNIT
		local terminal = Vector3Box(Vector3(0, 0, -fall / air))

		particles.beam({
			attenuation = CONFIG.spark_attenuation,
			color = {
				1,
				1,
				1,
			},
			intensity = CONFIG.spark_intensity,
			life = random_between(CONFIG.spark_life),
			size = width * UNIT,
			growth = -CONFIG.spark_thinning * UNIT,
			texture = "blue_spark_line",
			-- The air slows it by air times its speed a second, and gravity pulls it down. With w the speed it falls at in the end
			-- (gravity / air), its velocity is w + (v - w) * e^(-air * t), and it has gone w * t + (v - w) * (1 - e^(-air * t)) / air.
			track = function ()
				local age = Managers.time:time("game") - born
				local speed_left = math.exp(-air * age)
				local w = terminal:unbox()
				local rest = velocity:unbox() - w
				local at = start:unbox() + w * age + rest * ((1 - speed_left) / air)
				local now = w + rest * speed_left

				return at - now * CONFIG.spark_length, at
			end,
		})
	end
end

local function first_person_api()
	return mod.weapon_skin.shown_skin(skin_apis)
end

local function third_person_muzzle(character)
	return mod.weapon_skin.held_muzzle(skin_apis, character)
end

-- Where the bolt of a character starts: the weapon in the player's own view, or the end of the weapon in the character's hand
local function bolt_start(owner_unit)
	if utils.is_local_player_unit(owner_unit) then
		local api = first_person_api()

		if api and not api.third_person.shows_weapon(owner_unit) then
			if lightning.zoom.zoomed then
				local camera_position, camera_rotation = utils.camera_pose()

				if camera_position then
					return camera_position - Quaternion.up(camera_rotation) * CONFIG.zoomed_start_down
				end
			end

			-- UT starts the bolt at EffectOffset from the eye, 100 units ahead, where it draws the flare. Here it starts that far ahead
			-- on the line through the flare's place on the screen (flare_view_offset, in a view of 90 degrees across), so that it comes
			-- out of the flare.
			local camera_position, camera_rotation = utils.camera_pose()
			local player = Managers.player:local_player()

			if camera_position and player then
				local offset = CONFIG.flare_view_offset
				-- (UT's view of 90 degrees across at 16 by 9 is 0.5625 of a tangent up and down)
				local scale = math.tan(Managers.state.camera:fov(player.viewport_name) / 2) / 0.5625
				local ray = Quaternion.forward(camera_rotation) + Quaternion.right(camera_rotation) * (offset[1] / offset[2] * scale) + Quaternion.up(camera_rotation) * (offset[3] / offset[2] * scale)

				return camera_position + ray * (offset[2] * UNIT)
			end

			return api.muzzle_position()
		end
	end

	return (third_person_muzzle(owner_unit))
end

-- Draws a bolt that was fired. It runs on the machine of the shooter and, with the same numbers, on the others.
local function show_bolt(owner_unit, end_position, hit_normal, arcs, arcs_start, arc_normals)
	local start = bolt_start(owner_unit)

	if not start then
		return
	end

	draw_bolt(start, end_position, CONFIG.bolt_width * UNIT, CONFIG.bolt_stretch, CONFIG.bolt_jitter * UNIT, CONFIG.flare_life, CONFIG.bolt_intensity)

	local camera_position = utils.camera_pose()
	local api = utils.is_local_player_unit(owner_unit) and first_person_api()
	-- (while zoomed the weapon isn't drawn, and the flare is where the bolt starts, below the view, as UT's)
	local muzzle = api and not api.third_person.shows_weapon(owner_unit) and not lightning.zoom.zoomed and api.muzzle_model_position()

	if muzzle and camera_position then
		-- In the player's own view UT spawns the bolt at EffectOffset from the eye (100 ahead, 28 to the right, 26 down, in a view of
		-- 90 degrees across), and draws the flare there at the front of the weapon. Here it is drawn with the field of view of the
		-- weapon's model, so that it is among the parts of the model, at the same place on the screen and as wide as UT's.
		local _, camera_rotation = utils.camera_pose()
		-- (UT's view of 90 degrees across at 16 by 9 is 0.5625 of a tangent up and down)
		local scale = math.tan(api.weapon_vertical_fov() / 2) / 0.5625
		local ahead = Vector3.dot(muzzle - camera_position, Quaternion.forward(camera_rotation)) * CONFIG.flare_view_depth
		local offset = CONFIG.flare_view_offset
		local position = camera_position + Quaternion.forward(camera_rotation) * ahead + Quaternion.right(camera_rotation) * (ahead * offset[1] / offset[2] * scale) + Quaternion.up(camera_rotation) * (ahead * offset[3] / offset[2] * scale)

		flare(position, ahead * CONFIG.flare_view_size / offset[2] * scale, "units/ut/fx/fx_weapon_lightning_flare")
	else
		flare(start, CONFIG.flare_size * UNIT)
	end

	-- The flare where the bolt ends. In UT it is drawn whole even where it reaches into the surface that was hit, so here it is moved
	-- towards the camera by half its size, which keeps the surface from cutting it.
	if Vector3.length(hit_normal) > 0.01 then
		local size = CONFIG.flare_size * UNIT
		local towards_camera = camera_position and Vector3.normalize(camera_position - end_position) or hit_normal

		flare(end_position + towards_camera * (size / 2), size)
	end

	-- Each arc throws its sparks from where it starts, along the normal of what the arc hit, or back along the arc if it hit nothing
	-- (SniperFire.DoTrace, which lightning_gun.lua works out)
	for i, arc_end in ipairs(arcs) do
		draw_bolt(arcs_start, arc_end, CONFIG.arc_width * UNIT, CONFIG.arc_stretch, CONFIG.arc_jitter * UNIT, CONFIG.arc_life, CONFIG.arc_intensity)

		local normal = arc_normals[i]

		if normal and Vector3.length(normal) > 0.01 then
			sparks(arcs_start, Vector3.normalize(normal))
		end
	end

	-- NewLightningBolt.PostBeginPlay plays the impact sound where the bolt starts
	skin_apis[1].play_sound_at("ut_lightning_impact_3d", start)
end

mod.lightning_bolt_callbacks.lightning_skin = function (owner_unit, end_position, hit_normal, arcs, arcs_start, arc_normals)
	if not skin_apis[1] then
		return
	end

	show_bolt(owner_unit, end_position, hit_normal, arcs, arcs_start, arc_normals or {})

	-- The shot's own sounds are played for the player in the shot's action (see below). For the others they come from the weapon.
	if not utils.is_local_player_unit(owner_unit) then
		local muzzle, api = third_person_muzzle(owner_unit)

		if muzzle then
			api.play_sound_at("ut_lightning_fire_3d", muzzle)
		end
	end
end

-- LightningCharge: sparks at the tip of the weapon while it is ready to fire
local charge_time = 0

local function ready_to_fire()
	local now = Managers.time:time("game")
	local last_fire = lightning.last_fire_time

	return (not last_fire or now - last_fire >= lightning.fire_rate) and not locked_out()
end

local function update_charge(skin, dt, api)
	-- While zoomed UT draws the scope instead of the weapon, and the charge with it (SniperRifle.RenderOverlays). The sparks belong
	-- to the model in the player's view, so they are not drawn while the view is not the first person one either.
	if not ready_to_fire() or lightning.zoom.zoomed or not api.shown_in_first_person() then
		charge_time = 0

		return
	end

	charge_time = charge_time + dt

	local interval = 1 / CONFIG.charge_rate

	while charge_time >= interval do
		charge_time = charge_time - interval

		-- (the spread is in the units of the view, so it is in the model's units divided by its DrawScale)
		local along = CONFIG.charge_back + (math.random() * 2 - 1) * CONFIG.charge_spread / api.draw_scale()
		local offset = Vector3Box(Vector3(0, -along, 0))

		-- A spark is linked to the first person unit at its place on the model, and drawn with the model's field of view (an fx_weapon_
		-- material), so it moves with the model and the parts of the model in front of it hide it. A random one of the four pictures of
		-- the texture.
		particles.sprite({
			attenuation = 0,
			color = {
				1,
				1,
				1,
			},
			-- (a spark ends as soon as the model isn't drawn: zoomed, or not in the first person view)
			locked = function ()
				if api.state() == skin and not lightning.zoom.zoomed and api.shown_in_first_person() then
					return api.model_point_in_view(nil, offset:unbox())
				end
			end,
			intensity = CONFIG.charge_intensity,
			life = CONFIG.charge_life,
			material = "units/ut/fx/fx_weapon_lightning_charge_" .. math.random(0, 3),
			size = 2 * CONFIG.charge_size * skin.view_across_scale,
		})
	end
end

local function scope_scale()
	local width, height = Application.resolution()

	return width / 640, height / 480, width, height
end

-- The scope is drawn over the player's view while zoomed: the lens and scan lines, the ring, the four arrows, and the bar at the right
-- that shows how long it is until the next shot (red to blue as it charges, green when ready).
-- It has a screen gui of its own in the level's world (utils.level_screen_gui).
local scope_gui_now = utils.level_screen_gui("ui/ut/lightning_scope")

local function draw_scope(ingame_ui)
	if not lightning.zoom.zoomed then
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

	local scale_x, scale_y, width, height = scope_scale()
	-- UT draws the scope with the weapon, before the HUD, so the HUD is over it. A low layer puts the game's HUD over it here.
	local layer = 1

	-- ZoomFB: the screen is darkened by the lens and the scan lines
	Gui.bitmap(gui, "ut_lightning_scope_lens", Vector3(0, 0, layer), Vector2(width, height), Color(255, 255, 255, 255))

	-- SniperFocus: 4 times the numbers of the class wide, centered, in the units of a screen of 640 wide for both directions
	local focus_width = 4 * CONFIG.scope_focus_x * scale_x
	local focus_height = 4 * CONFIG.scope_focus_y * scale_x
	local color = CONFIG.scope_focus_color

	Gui.bitmap(gui, "ut_lightning_scope_focus", Vector3((width - focus_width) / 2, (height - focus_height) / 2, layer + 1), Vector2(focus_width, focus_height), Color(color[1], color[2], color[3], color[4]))

	-- SniperArrows
	local arrows_width = 2 * CONFIG.scope_arrows_x * scale_x
	local arrows_height = 2 * CONFIG.scope_arrows_y * scale_y

	color = CONFIG.scope_arrow_color

	Gui.bitmap(gui, "ut_lightning_scope_arrows", Vector3((width - arrows_width) / 2, (height - arrows_height) / 2, layer + 2), Vector2(arrows_width, arrows_height), Color(color[1], color[2], color[3], color[4]))

	-- The charge bar fills from the bottom up as the next shot comes near
	local now = Managers.time:time("game")
	local last_fire = lightning.last_fire_time
	local charge = (not last_fire or now - last_fire >= lightning.fire_rate) and 1 or math.clamp((now - last_fire) / lightning.fire_rate, 0, 1)
	local bar_red, bar_green, bar_blue = 0, 0, 255

	if charge < 1 then
		bar_red = 255 * charge
	else
		bar_green = 255
		bar_blue = 0
	end

	local bar_width = CONFIG.scope_bar_width * scale_x
	local bar_height = CONFIG.scope_bar_height * scale_y * charge
	local bar_x = CONFIG.scope_bar_origin_x * scale_x
	-- The bar's origin is at its bottom, and it grows upwards
	local bar_bottom = height - CONFIG.scope_bar_origin_y * scale_y

	Gui.rect(gui, Vector3(bar_x, bar_bottom, layer + 3), Vector2(bar_width, bar_height), Color(255, bar_red, bar_green, bar_blue))
end

mod.ingame_ui_post_update_callbacks.lightning_scope = draw_scope

-- The skin definition
local function new_skin(variant)
	local definition = mod.items.weapons[variant.setting_id]
	local api

	api = mod.weapon_skin.new({
		id = variant.id,
		name = "lightning gun",
		template = definition.template,
		unit_name = "units/ut/lightning/lightning_gun",
		animations = animations,
		muzzle_node = "b_bone_flash",
		-- model_meters_per_unit is the meters per UT unit at which the model was converted (tools/asset_conversion/convert_weapon.py).
		-- meters_per_unit is the distance scale: the meters of forward in the view that one UT unit of the model takes up.
		model_meters_per_unit = 0.0125,
		meters_per_unit = 0.01,
		-- SniperRifle.uc
		display_fov = 60,
		draw_scale = 0.4,
		select_speed = 1.25, -- SniperRifle.SelectAnimRate
		offset_forward = 0,
		offset_right = 2.3,
		offset_up = 0,
		bob_damping = 2.3,
		-- The inspect pose turns the rifle to show its left side, like the other weapons. These numbers are a guess.
		inspect_pose_right = -2,
		inspect_pose_forward = 4,
		inspect_pose_up = 0,
		inspect_pose_roll = 10,
		inspect_pose_pitch = 4,
		inspect_pose_yaw = 55,
		inspect_turn_start = 0.35,
		inspect_pivot_right = 0,
		inspect_pivot_forward = 30,
		inspect_pivot_up = 0,
		-- The lockout pose (see lockout_pose_speed): turned on its side, lower and further right, in the corner of the view
		alt_pose_right = 2,
		alt_pose_forward = 0,
		alt_pose_up = -3,
		alt_pose_roll = -40,
		alt_pose_pitch = 0,
		alt_pose_yaw = 0,
		-- WeaponStaticMesh.SniperRiflePickup (DrawScale 0.45). The game links the staff to the left hand's node
		-- (AttachmentNodeLinking.one_handed_melee_weapon.left), whose forward points out to the hero's left. The mesh is turned a quarter
		-- from it, so it points ahead from the hand at her side.
		third_person = {
			id = variant.id,
			template = definition.template,
			unit_name = "units/ut/lightning/pickup",
			hand_node = "j_leftweaponattach",
			meters_per_unit = 0.009,
			scale = 0.5,
			grip_right = 0,
			grip_forward = 0,
			grip_up = -8,
			yaw = -90,
			pitch = 0,
			roll = 0,
			follow_game_unit = 3,
			follow_calibrate_seconds = 1,
			muzzle_right = 0,
			muzzle_forward = 76,
			muzzle_up = 0,
			menu_yaw = 180,
		},
		-- UT draws the scope in place of the weapon while zoomed (SniperRifle.RenderOverlays)
		hidden = function ()
			return lightning.zoom.zoomed
		end,
		on_create = function ()
			api.play_sound("ut_lightning_select")
		end,
		on_update = function (skin, dt)
			skin.inspect_pose = (skin.inspect_pose or 0) + ((skin.inspecting and 1 or 0) - (skin.inspect_pose or 0)) * math.min(1, CONFIG.inspect_pose_speed * dt)
			skin.alt_pose = (skin.alt_pose or 0) + ((locked_out() and 1 or 0) - (skin.alt_pose or 0)) * math.min(1, CONFIG.lockout_pose_speed * dt)
			skin.inspect_time = skin.inspecting and (skin.inspect_time or 0) + dt or 0
			skin.extra_yaw = skin.inspect_pose * CONFIG.inspect_sway * math.sin(skin.inspect_time * CONFIG.inspect_sway_speed)

			-- The zoom has its sound when it starts and when it ends
			local zoomed = lightning.zoom.zoomed

			if zoomed ~= skin.was_zoomed then
				if skin.was_zoomed ~= nil then
					api.play_sound(zoomed and "ut_lightning_zoom_in" or "ut_lightning_zoom_out")
				end

				skin.was_zoomed = zoomed
			end

			update_charge(skin, dt, api)
		end,
		on_level_exit = function ()
			charge_time = 0
		end,
	})

	skin_apis[#skin_apis + 1] = api

	return api
end

for _, variant in ipairs(TEMPLATES) do
	new_skin(variant)
end

-- The shot of the player: the animation and the sounds start when the shot's action starts, because the handgun shoots at once.
mod.handgun_start_callbacks.lightning_skin = function (action, new_action)
	if not new_action.ut_lightning_bolt then
		return
	end

	local owner_unit = action.owner_unit

	for _, api in ipairs(skin_apis) do
		local skin = api.state()

		if skin and utils.is_local_player_unit(owner_unit) then
			api.play("Fire", api.animation_duration("Fire") / CONFIG.fire_animation_rate)
			api.play_sound("ut_lightning_fire")

			-- SniperFire.PlayFiring: the charge up after the shot, if there is ammo for another. Here, if the gun is not locked out.
			if not locked_out() then
				api.play_sound("ut_lightning_charge")
			end
		end
	end
end

-- Inspecting is the game's own action, held with the key
mod.inspect_callbacks.lightning_skin = function (action, started)
	for _, api in ipairs(skin_apis) do
		local skin = api.state()

		if skin and utils.is_local_player_unit(action.owner_unit) then
			skin.inspecting = started
		end
	end
end

-- The staff's shot animation is the game's own, so it is not played on the player's own first person unit. The skin's model plays UT's
-- animations instead.
for template_name in pairs(TEMPLATE_NAMES) do
	mod.first_person_animation_filters[template_name] = function (event)
		return event == "attack_shoot" or event == "attack_shoot_last"
	end
end
