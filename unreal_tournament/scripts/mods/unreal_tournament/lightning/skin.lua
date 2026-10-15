local mod = get_mod("unreal_tournament")

-- Lightning Gun skin: how UT2004's Lightning Gun looks and sounds.
--
-- weapon_skin.lua does the model, its placement and animations, the bob and the third person. This file does what is the Lightning Gun's
-- own: the bolt and its arcs, the sparks where it hits, the charge at the tip, the sounds, and the scope. The gameplay is in
-- lightning_gun.lua. This file only draws it, and is told what happens through the hook tables in hooks.lua.
--
-- The assets were made with tools/asset_conversion (convert_weapon.py sniper, convert_static.py sniper_pickup, make_sniper_screen.py,
-- make_lightning_assets.py and make_bank.py lightning_gun).

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local animations = mod:dofile("scripts/mods/unreal_tournament/lightning/skin_animations")
local particles = mod.skin_particles

local CONFIG = {
	meters_per_uu = 0.02, -- meters in one Unreal unit of the world (a player is 88 units high)
	-- NewLightningBolt lasts half a second. It is drawn as a line of parts of the streak texture, each bolt_segment meters long and
	-- bolt_width wide. A part is out of line by bolt_jitter. UT's bolt is a thin bright line with small zigzags.
	bolt_width = 6, -- UT units
	bolt_life = 0.5,
	bolt_segment = 2,
	bolt_jitter = 0.04,
	bolt_intensity = 1.2,
	-- ChildLightningBolt: the arcs are 15 units wide, and jump about more
	arc_width = 4,
	arc_life = 0.5,
	arc_segment = 0.6,
	arc_jitter = 0.05,
	arc_intensity = 1.2,
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
	-- BlueSparks (20 particles of 0.8 to 1.2 s that fly out at 250 to 350 units a second) at the end of the bolt, and
	-- ChildBlueSparks (10 particles) at the end of an arc
	spark_count = 20,
	spark_life = {0.8, 1.2},
	spark_speed = {250, 350},
	spark_size = 12, -- UT units. UT's size is 1 to 2, of a line particle.
	spark_drag = 1.5, -- per second
	spark_intensity = 1.6,
	arc_spark_count = 10,
	-- LightningCharge: 10 sparks a second at the tip, each 0.2 s long and 5 units across, one of the four pictures of the texture,
	-- turned at random. They stop while the weapon cannot fire (its next shot is not yet due, or it has no ammo).
	-- The emitter is 30 units behind the muzzle (LightningCharge.RelativeLocation), inside the glass at the front, and each spark is up
	-- to 10 units from there along the barrel (mPosDev). It is attached to the model, so these are the model's units, with its DrawScale.
	charge_rate = 10,
	charge_life = 0.2,
	charge_size = 9,
	charge_back = 24,
	charge_spread = 20,
	charge_nearer = 0.8, -- share of the distance to the camera the sparks are drawn at (see update_charge)
	-- The glass's middle is this many units above the muzzle, and the sparks are this bright (fitted to a picture of UT2004)
	charge_up = 5,
	charge_intensity = 0.45,
	-- Where the bolt starts when the view is zoomed: SniperFire puts it at the player's middle (EffectOffset.Z, 26 units, below), so it
	-- comes from the bottom of the screen
	zoomed_start_down = 1, -- m below the camera
	-- The scope (SniperRifle.RenderOverlays). These are in the units of a screen of 640 by 480.
	scope_focus_x = 135,
	scope_focus_y = 105,
	scope_arrows_x = 42,
	scope_arrows_y = 42,
	scope_focus_color = { 215, 71, 90, 126 }, -- alpha, red, green, blue
	scope_arrow_color = { 255, 255, 0, 0 },
	scope_bar_origin_x = 600,
	scope_bar_origin_y = 330,
	scope_bar_width = 10,
	scope_bar_height = 180,
	-- How long a shot lights up the weapon's third person model
	inspect_pose_speed = 5, -- how fast the model moves to the inspect pose and back, per second
	inspect_sway = 5, -- degrees of yaw each way while inspecting
	inspect_sway_speed = 1.8, -- radians per second
}

local UNIT = CONFIG.meters_per_uu

local lightning = mod.lightning

local TEMPLATES = {
	{
		id = "lightning_gun",
		setting_id = "lightning_gun",
	},
	{
		id = "lightning_gun_dr",
		setting_id = "lightning_gun_dr",
	},
}

local TEMPLATE_NAMES = {}
local skin_apis = {}

for _, variant in ipairs(TEMPLATES) do
	TEMPLATE_NAMES[mod.items.weapons[variant.setting_id].template] = true
end

local function random_between(range)
	return range[1] + (range[2] - range[1]) * math.random()
end

local function random_direction()
	local direction = Vector3(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1)

	if Vector3.length(direction) < 0.001 then
		return Vector3.up()
	end

	return Vector3.normalize(direction)
end

-- The bolt: a line of parts, each a streak of the texture, out of line by a little. A part runs from the end of the one before it.
local function draw_bolt(from, to, width, segment_length, jitter, life, intensity)
	local offset = to - from
	local length = Vector3.length(offset)

	if length < 0.01 then
		return
	end

	local direction = offset * (1 / length)
	local across = Vector3.cross(direction, Vector3.up())

	if Vector3.length(across) < 0.01 then
		across = Vector3.cross(direction, Vector3.right())
	end

	across = Vector3.normalize(across)

	local other = Vector3.cross(direction, across)
	local count = math.max(1, math.ceil(length / segment_length))
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

-- The sparks that fly out from where the bolt or an arc ends, away from the surface it hit
local function sparks(position, normal, count)
	local up = Vector3.length(normal) > 0.01 and normal or Vector3.up()

	for _ = 1, count do
		local direction = Vector3.normalize(up + random_direction())

		particles.sprite({
			attenuation = 0.1,
			color = {
				1,
				1,
				1,
			},
			drag = CONFIG.spark_drag,
			intensity = CONFIG.spark_intensity,
			life = random_between(CONFIG.spark_life),
			position = position,
			size = CONFIG.spark_size * UNIT,
			growth = -CONFIG.spark_size * UNIT / 1.2,
			texture = "blue_spark",
			velocity = direction * (random_between(CONFIG.spark_speed) * UNIT),
		})
	end
end

-- Each template has a skin of its own, and a character holds the weapon of one of them. These find the skin that has the weapon in
-- the player's own view, and the one whose mesh a character holds.
local function first_person_api()
	for _, api in ipairs(skin_apis) do
		if api.state() then
			return api
		end
	end
end

local function third_person_muzzle(character)
	for _, api in ipairs(skin_apis) do
		local muzzle = api.third_person.muzzle_position(character)

		if muzzle then
			return muzzle, api
		end
	end
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

			return api.muzzle_position()
		end
	end

	return (third_person_muzzle(owner_unit))
end

-- Draws a bolt that was fired. It runs on the machine of the shooter and, with the same numbers, on the others.
local function show_bolt(owner_unit, end_position, hit_normal, arcs, arcs_start)
	local start = bolt_start(owner_unit)


	if not start then
		return
	end

	draw_bolt(start, end_position, CONFIG.bolt_width * UNIT, CONFIG.bolt_segment, CONFIG.bolt_jitter, CONFIG.bolt_life, CONFIG.bolt_intensity)

	local camera_position = utils.camera_pose()
	local api = utils.is_local_player_unit(owner_unit) and first_person_api()
	local muzzle = api and not api.third_person.shows_weapon(owner_unit) and api.muzzle_model_position()

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

	-- A bolt that hit something makes sparks and flares there
	if Vector3.length(hit_normal) > 0.01 then
		flare(end_position, CONFIG.flare_size * UNIT)
		sparks(end_position, hit_normal, CONFIG.spark_count)
	end

	for _, arc_end in ipairs(arcs) do
		draw_bolt(arcs_start, arc_end, CONFIG.arc_width * UNIT, CONFIG.arc_segment, CONFIG.arc_jitter, CONFIG.arc_life, CONFIG.arc_intensity)
		sparks(arc_end, Vector3.zero(), CONFIG.arc_spark_count)
	end

	-- NewLightningBolt.PostBeginPlay plays the impact sound where the bolt starts
	skin_apis[1].play_sound_at("ut_lightning_impact_3d", start)
end

mod.lightning_bolt_callbacks.lightning_skin = function (owner_unit, end_position, hit_normal, arcs, arcs_start)
	if not skin_apis[1] then
		return
	end

	show_bolt(owner_unit, end_position, hit_normal, arcs, arcs_start)

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

	return (not last_fire or now - last_fire >= lightning.fire_rate) and not utils.local_ranged_out_of_ammo()
end

local function update_charge(skin, dt, api)

	if not ready_to_fire() then
		charge_time = 0

		return
	end

	charge_time = charge_time + dt

	local interval = 1 / CONFIG.charge_rate
	local world_unit = skin.unit_scale

	while charge_time >= interval do
		charge_time = charge_time - interval

		local along = CONFIG.charge_back + (math.random() * 2 - 1) * CONFIG.charge_spread

		-- (a random one of the four pictures of the texture)
		particles.sprite({
			attenuation = 0,
			color = {
				1,
				1,
				1,
			},
			follow = function ()
				local muzzle = api.state() == skin and api.muzzle_position()
				local camera_position, camera_rotation = utils.camera_pose()

				if not muzzle or not camera_rotation then
					return nil
				end

				-- UT draws the sparks over the glass at the front of the weapon. The point is moved towards the camera, and the sprite
				-- is made smaller by as much, so it is seen at the same place and size but in front of the model.
				local point = muzzle - Quaternion.forward(camera_rotation) * (along * world_unit) + Quaternion.up(camera_rotation) * (CONFIG.charge_up * world_unit)

				return camera_position + (point - camera_position) * CONFIG.charge_nearer
			end,
			intensity = CONFIG.charge_intensity,
			life = CONFIG.charge_life,
			-- The sprite's size is in world units, not the model's
			size = CONFIG.charge_size * world_unit / api.draw_scale() * CONFIG.charge_nearer,
			texture = "lightning_charge_" .. math.random(0, 3),
		})
	end
end

local function scope_scale()
	local width, height = Application.resolution()

	return width / 640, height / 480, width, height
end

-- The scope is drawn over the player's view while zoomed: the lens and scan lines, the ring, the four arrows, and the bar at the right
-- that shows how long it is until the next shot (red to blue as it charges, green when ready)
local scope_ready = false

-- The scope's materials are in the user interface's renderer of the level, which is made when the level starts. So the scope shows from
-- the next level, if the mod was loaded in the middle of one.
mod.items.add_material_set("ui/ut/lightning_scope")

mod.ingame_ui_init_callbacks.lightning_scope = function ()
	scope_ready = true
end

local function draw_scope(ingame_ui)
	if not lightning.zoom.zoomed then
		return
	end

	local player = Managers.player and Managers.player:local_player_safe()
	local unit = player and player.player_unit

	if not unit or not Unit.alive(unit) or not TEMPLATE_NAMES[utils.wielded_template_name(unit)] then
		return
	end

	local gui = ingame_ui.ui_renderer.gui
	local scale_x, scale_y, width, height = scope_scale()
	local layer = 990

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

-- A material that the user interface's renderer does not have yet is an error, which is until the next level if the mod was loaded in
-- the middle of one. So the scope is only drawn from the level after that.
mod.ingame_ui_post_update_callbacks.lightning_scope = function (ingame_ui)
	if scope_ready then
		draw_scope(ingame_ui)
	end
end

-- While the view is zoomed, the game's crosshair is not drawn: the scope has its own.
mod:hook(CrosshairUI, "draw", function (func, self, ...)
	if lightning.zoom.zoomed then
		return
	end

	return func(self, ...)
end)

-- Skin definitions, one for each of the two templates
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
		-- WeaponStaticMesh.SniperRiflePickup (DrawScale 0.45). The game links the handgun to the left hand's node
		-- (AttachmentNodeLinking.rifles), as it does the blunderbuss.
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
			yaw = -60,
			pitch = 0,
			roll = 0,
			follow_game_unit = 1,
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
			api.play("Fire")
			api.play_sound("ut_lightning_fire")

			-- SniperFire.PlayFiring: the charge up after the shot, if there is ammo for another
			if not utils.local_ranged_out_of_ammo() then
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
