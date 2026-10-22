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
	-- NewLightningBolt (PT_Branch) is 30 particles of size 30, each out of place by up to 5 units (mPosDev). Engine.dll (decompiled) draws
	-- a PT_Branch as quads between its particles, each widened by the size to each side along both axes of the screen (as a line's two
	-- quads are: particles.beam's screen_axis), so the bolt is twice its size wide, with the upper half of LightningBoltT across it.
	-- Here it is a line of parts, each bolt_part_length units long with the texture once along it, so the texture's zigzag is drawn out
	-- along the bolt (set against pictures of UT2004: shorter parts repeated the zigzag evenly and tightly). The corners between the
	-- parts are out of line by up to bolt_jitter units, UT's mPosDev. Where UT puts the particles along the bolt is not known here. It is
	-- the same emitter as the flare, so it fades the same way (flare_life). In pictures of UT2004 its streaks look like the texture added
	-- once (white middles, thin blue edges), while the flare is 9 times the texture.
	bolt_size = 30, -- mSizeRange: UT units to each side
	bolt_part_length = 480, -- UT units
	bolt_jitter = 5, -- UT units
	bolt_intensity = 1,
	-- ChildLightningBolt: 10 particles of size 15, out of place by up to 15 units (mPosDev). In pictures of UT2004 an arc is a different
	-- sight from the bolt: long drawn out zigzags with no line through them. A part is as long as a full arc (arc_range), so an arc is
	-- one part (set against those pictures).
	arc_size = 15, -- mSizeRange: UT units to each side
	arc_part_length = 300, -- UT units
	arc_jitter = 15, -- UT units
	arc_life = 0.5,
	arc_intensity = 1,
	-- The flares where the bolt starts and ends: PT_Branch draws a sprite of the lower half of LightningBoltT at the emitter, of size
	-- mSpawnVecB.X, and at the end, of size mSpawnVecB.Y, a square turned 45 degrees that doesn't turn (utils.UT_SPRITE_SIDE times the
	-- size across). NewLightningBolt's are 40 and 40; an arc has one of 20 where it starts (ChildLightningBolt's X) and none at its end.
	-- In pictures of UT2004 taken 25 ms apart, it starts at 9 times the texture, which makes a white disk with a blue rim, and dims evenly
	-- until it is gone 0.4 s after the shot, showing the ring and the spikes on the way.
	flare_size = 40, -- mSpawnVecB.X and Y
	arc_flare_size = 20, -- ChildLightningBolt's mSpawnVecB.X
	flare_life = 0.4,
	flare_intensity = 9,
	-- Where the flare is in the player's view (right, forward, up, UT units from the eye), fitted to a picture of UT2004, which has the eye's
	-- bob and the view's height in it too (SniperRifle.EffectOffset is (28, 100, -26)). It is drawn there at flare_size.
	flare_view_offset = {25, 100, -19.8},
	-- ChildBlueSparks: each arc (ChildLightningBolt) throws 10 sparks from 0.8 units around where it starts (mPosDev), which is where the
	-- bolt hit. They fly along the arc's hit normal, turned by 0.6 (mDirDev), at 250 to 350 units a second, slowed by 0.2 of their speed a second
	-- (mAirResistance), and last 0.8 to 1.2 s. Each is a line (particles.line) 6 to 4 units wide (mSizeRange 3 to 2) that thins by 6
	-- units a second, 0.05 s of its travel long (mSpawnVecB.Z, which ChildBlueSparks leaves at xEmitter's), with a head of mSpawnVecB.X
	-- 5. They fall by their mass (mMassRange 1.5 to 2.5).
	spark_count = 10,
	spark_life = {0.8, 1.2},
	spark_speed = {250, 350},
	spark_direction_spread = 0.6,
	spark_position_spread = 0.8, -- UT units
	spark_air_resistance = 0.2,
	spark_mass = {1.5, 2.5},
	spark_width = {6, 4}, -- UT units across
	spark_thinning = 6, -- UT units across, a second
	spark_length = 0.05, -- seconds of travel
	spark_head = 5, -- mSpawnVecB.X
	spark_attenuation = 0.1,
	-- LightningCharge: 10 sparks a second at the tip, each 0.2 s long, one of the four pictures of the texture, turned at random. They
	-- stop while the weapon cannot fire (its next shot is not yet due, or it has no ammo: here, it is locked out). The emitter is attached
	-- to the model's tip, 30 of the model's units behind it along the barrel (RelativeLocation, in the bone's frame), and its sparks move
	-- with it (mPosRelative). Its own numbers are in the units of the view, as the emitter isn't drawn at the model's DrawScale: each spark
	-- is up to 10 units from it along the barrel (mPosDev), so some are out in front of the tip, and 5 units in size (mSizeRange: a sprite
	-- utils.UT_SPRITE_SIDE times that across). So the sparks fill the cage and reach out past the tip, as in pictures of UT2004. (They
	-- were once drawn smaller than UT's numbers: at twice their size across, they came through the front of the gun.)
	charge_rate = 10,
	charge_life = 0.2,
	charge_size = 5, -- mSizeRange, units of the view
	charge_back = 30, -- the model's units
	charge_spread = 10, -- units of the view
	-- How bright the sparks are (fitted to a picture of UT2004)
	charge_intensity = 0.45,
	-- The sparks at the tip of the gun in a character's hands (LightningCharge3rd, attached to the mesh's tip). UT spawns them with the
	-- character's first shot. Here they show as soon as the gun is held, as the first person sparks do (the mod's choice). They don't
	-- stop when the gun can't fire: 40 a second, each 0.2 s long, 5 units in size
	-- (mSizeRange), up to 5 units from the emitter along the barrel, turned at random. The emitter is at RelativeLocation (-30, 3, 0)
	-- in the frame of the tip, taken in the mesh's units, as for the first person charge. The mesh has no bone named tip: it is taken to
	-- be Bone_Flash, where the muzzle is. That bone's frame is turned a quarter about the barrel from the mesh's (its parent Bone_weapon
	-- is), so its Y is the mesh's down: the emitter is 30 units behind the tip and 3 below it. Its own numbers are UT's world units, as
	-- the emitter is drawn at its own DrawScale of 1. They are as bright as the first person sparks, with the same texture, and fade near
	-- the camera with the character.
	third_person_charge_rate = 40,
	third_person_charge_life = 0.2,
	third_person_charge_size = 5, -- mSizeRange, UT units
	third_person_charge_spread = 5, -- UT units
	third_person_charge_back = 30, -- the mesh's units
	third_person_charge_down = 3, -- the mesh's units
	-- The weapon's light (xWeaponAttachment.WeaponLight): every shot turns it on for 0.15 s, at the gun in a character's hand (the held
	-- mesh's origin). There is none in the player's own first person view, where it would light the gun the player holds (as for the
	-- Minigun). LightHue 165 of 255 and LightSaturation 170 (0 is all colour, 255 is white) are a pale blue, and LightRadius 5 is in
	-- steps of 25 units: 2.5 m. It is steady (LT_Steady).
	light_color = { 0.67, 0.71, 1 },
	light_falloff = 2.5, -- meters
	light_life = 0.15,
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
	-- The color of the overcharge bar between its thresholds and above them, where the game's are orange and red: white, like the bolt
	overcharge_bar_color = { 255, 255, 255 },
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

-- The time between the local player's shots, shorter with the game's attack speed buffs (as lightning_gun.lua's ready_to_fire has it)
local function fire_rate()
	local player = Managers.player and Managers.player:local_player()
	local unit = player and player.player_unit

	return lightning.fire_rate / utils.attack_speed(unit and Unit.alive(unit) and unit or nil)
end

local TEMPLATE_NAMES = {}
local skin_apis = {}

for _, variant in ipairs(TEMPLATES) do
	local template_name = mod.items.weapons[variant.setting_id].template

	TEMPLATE_NAMES[template_name] = true
	mod.overcharge_bar_colors[template_name] = { color = CONFIG.overcharge_bar_color, above_max = true }
end

local random_between = utils.random_between

-- The most parts a bolt is drawn with. A long bolt has longer parts instead, far away where they are small on the screen.
local MAX_BOLT_PARTS = 100

-- A piece of the bolt from one place to another, as PT_Branch draws one: two quads, each widened by size to each side along one axis of
-- the screen
local function bolt_piece(from, to, size, life, intensity)
	for _, axis in ipairs({ "right", "up" }) do
		particles.beam({
			attenuation = 0,
			color = {
				1,
				1,
				1,
			},
			from = from,
			intensity = intensity,
			life = life,
			screen_axis = axis,
			size = 2 * size,
			texture = "lightning_bolt",
			to = to,
		})
	end
end

-- The bolt: a line of parts, each a streak of the texture part_length long, out of line by a little. A part runs from the end of the one
-- before it. With core, the texture is also drawn once along the whole bolt under them, drawn out into a nearly straight line that runs
-- through the zigzags, as in pictures of UT2004.
local function draw_bolt(from, to, size, part_length, jitter, life, intensity, core)
	local offset = to - from
	local length = Vector3.length(offset)

	if length < 0.01 then
		return
	end

	if core then
		bolt_piece(from, to, size, life, intensity)
	end

	local count = math.clamp(math.ceil(length / part_length), 1, MAX_BOLT_PARTS)
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

		bolt_piece(previous, point, size, life, intensity)

		previous = point
	end
end

-- A flare at a place, size across. The material is the texture's own, or another one for the flare in the player's view (see show_bolt).
-- intensity and life are the bolt's flare's unless given. (PT_Branch's sprite is a square turned 45 degrees, which doesn't turn.)
local function flare(position, size, material, intensity, life)
	particles.sprite({
		angle = 45,
		material = material,
		attenuation = 0,
		color = {
			1,
			1,
			1,
		},
		intensity = intensity or CONFIG.flare_intensity,
		life = life or CONFIG.flare_life,
		position = position,
		size = size,
		texture = "lightning_flare",
	})
end

-- The sparks an arc throws from where it starts (ChildBlueSparks), along the arc's hit normal, started as xEmitter starts them
-- (utils.ut_particle_velocity)
local function sparks(position, normal)
	for _ = 1, CONFIG.spark_count do
		particles.line({
			attenuation = CONFIG.spark_attenuation,
			drag = CONFIG.spark_air_resistance,
			fade_squared = true,
			fall = utils.UT_PARTICLE_GRAVITY * random_between(CONFIG.spark_mass) * UNIT,
			growth = -CONFIG.spark_thinning * UNIT,
			head_size = CONFIG.spark_head * utils.UT_SPRITE_SIDE * UNIT,
			length = CONFIG.spark_length,
			life = random_between(CONFIG.spark_life),
			position = position + utils.ut_particle_offset(CONFIG.spark_position_spread) * UNIT,
			size = random_between(CONFIG.spark_width) * UNIT,
			texture = "blue_spark",
			velocity = utils.ut_particle_velocity(normal, CONFIG.spark_direction_spread, random_between(CONFIG.spark_speed) * UNIT),
		})
	end
end

local function first_person_api()
	return mod.weapon_skin.shown_skin(skin_apis)
end

local function third_person_muzzle(character)
	return mod.weapon_skin.held_muzzle(skin_apis, character)
end

-- The mesh in a character's hands and the skin it belongs to, or nil if the character holds the game's weapon
local function held_mesh(character)
	for _, api in ipairs(skin_apis) do
		local unit = api.third_person.held_mesh(character)

		if unit then
			return unit, api
		end
	end
end

-- The light of a shot at the gun in the character's hands, while the character is seen holding it
local function weapon_light(owner_unit)
	local unit, api = held_mesh(owner_unit)

	if not unit or not api.third_person.shows_weapon(owner_unit) then
		return
	end

	particles.light({
		brightness = function ()
			return 1
		end,
		color = CONFIG.light_color,
		falloff = CONFIG.light_falloff,
		follow = function ()
			return api.third_person.point_position(owner_unit, 0, 0, 0)
		end,
		intensity = utils.WEAPON_LIGHT_INTENSITY,
		life = CONFIG.light_life,
	})
end

-- The sparks at the tip of the gun in each character's hands, for as long as it is held and seen: [character] = the part of a spark
-- owed
local third_person_charges = setmetatable({}, {
	__mode = "k",
})

local function third_person_charge_spark(character, api)
	local along = (math.random() * 2 - 1) * CONFIG.third_person_charge_spread * UNIT

	-- (the sparks move with the gun, mPosRelative, and start at a random angle. They dim over their life, mAttenKa 0.)
	particles.sprite({
		brightness = function (fraction)
			return (1 - fraction) * api.third_person.fade(character)
		end,
		color = {
			1,
			1,
			1,
		},
		follow = function ()
			local _, mesh_config = api.third_person.held_mesh(character)

			if not mesh_config or not api.third_person.shows_weapon(character) then
				return nil
			end

			local emitter = api.third_person.point_position(character, mesh_config.muzzle_right, mesh_config.muzzle_forward - CONFIG.third_person_charge_back, mesh_config.muzzle_up - CONFIG.third_person_charge_down)

			return emitter and emitter + Quaternion.forward(api.third_person.muzzle_rotation(character)) * along or nil
		end,
		intensity = CONFIG.charge_intensity,
		life = CONFIG.third_person_charge_life,
		size = utils.UT_SPRITE_SIDE * CONFIG.third_person_charge_size * UNIT,
		texture = "lightning_charge_" .. math.random(0, 3),
	})
end

local function update_third_person_charges(dt)
	local players = Managers.player and Managers.player:human_and_bot_players()

	if not players then
		return
	end

	local interval = 1 / CONFIG.third_person_charge_rate

	for _, player in pairs(players) do
		local character = player.player_unit
		local unit, api = nil, nil

		if character and Unit.alive(character) then
			unit, api = held_mesh(character)
		end

		if unit and api.third_person.shows_weapon(character) then
			local owed = (third_person_charges[character] or 0) + dt

			while owed >= interval do
				owed = owed - interval

				third_person_charge_spark(character, api)
			end

			third_person_charges[character] = owed
		elseif character then
			third_person_charges[character] = nil
		end
	end
end

mod.update_callbacks[#mod.update_callbacks + 1] = update_third_person_charges

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

	draw_bolt(start, end_position, CONFIG.bolt_size * UNIT, CONFIG.bolt_part_length * UNIT, CONFIG.bolt_jitter * UNIT, CONFIG.flare_life, CONFIG.bolt_intensity, true)

	local flare_size = CONFIG.flare_size * utils.UT_SPRITE_SIDE * UNIT

	local camera_position = utils.camera_pose()
	local api = utils.is_local_player_unit(owner_unit) and first_person_api()
	-- (while zoomed the weapon isn't drawn, and the flare is where the bolt starts, below the view, as UT's)
	local muzzle = api and not api.third_person.shows_weapon(owner_unit) and not lightning.zoom.zoomed and api.muzzle_model_position()

	local player = Managers.player:local_player()

	if muzzle and camera_position and player then
		-- In the player's own view UT spawns the bolt at EffectOffset from the eye (100 ahead, 28 to the right, 26 down, in a view of
		-- 90 degrees across), and draws the flare there in the world, behind the weapon. The flare is drawn where the bolt starts (see
		-- bolt_start), as wide on the screen as UT's, so the two stay together as the view moves.
		-- (UT's view of 90 degrees across at 16 by 9 is 0.5625 of a tangent up and down)
		local scale = math.tan(Managers.state.camera:fov(player.viewport_name) / 2) / 0.5625

		flare(start, flare_size * scale)
	else
		flare(start, flare_size)
	end

	-- The flare where the bolt ends, hit or not. In UT it is drawn whole even where it reaches into the surface that was hit, so here it
	-- is moved towards the camera by half its size, which keeps the surface from cutting it.
	local towards_camera = camera_position and Vector3.normalize(camera_position - end_position) or hit_normal

	flare(end_position + towards_camera * (flare_size / 2), flare_size)

	-- Each arc throws its sparks from where it starts, along the normal of what the arc hit, or back along the arc if it hit nothing
	-- (SniperFire.DoTrace, which lightning_gun.lua works out). It has its own flare where it starts, the texture added once.
	for i, arc_end in ipairs(arcs) do
		draw_bolt(arcs_start, arc_end, CONFIG.arc_size * UNIT, CONFIG.arc_part_length * UNIT, CONFIG.arc_jitter * UNIT, CONFIG.arc_life, CONFIG.arc_intensity)

		local arc_flare_size = CONFIG.arc_flare_size * utils.UT_SPRITE_SIDE * UNIT

		flare(arcs_start + towards_camera * (arc_flare_size / 2), arc_flare_size, nil, CONFIG.arc_intensity, CONFIG.arc_life)

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

	-- SniperAttachment.ThirdPersonEffects: the gun in the character's hands lights up
	weapon_light(owner_unit)

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

	return (not last_fire or now - last_fire >= fire_rate()) and not locked_out()
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
			size = utils.UT_SPRITE_SIDE * CONFIG.charge_size * skin.view_across_scale,
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
	if not lightning.zoom.in_view() then
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
	local rate = fire_rate()
	local charge = (not last_fire or now - last_fire >= rate) and 1 or math.clamp((now - last_fire) / rate, 0, 1)
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
		-- (to the right, so that the back of the gun, which the first person mesh doesn't have, stays off the screen as it turns)
		inspect_pose_right = 10,
		inspect_pose_forward = 4,
		inspect_pose_up = -3,
		inspect_pose_roll = 10,
		inspect_pose_pitch = 4,
		inspect_pose_yaw = 55,
		inspect_turn_start = 0.35,
		inspect_pivot_right = 0,
		inspect_pivot_forward = 30,
		inspect_pivot_up = 0,
		-- The lockout pose (see lockout_pose_speed): tipped up, raised and further right (set in the game)
		alt_pose_right = 2,
		alt_pose_forward = 0,
		alt_pose_up = 3,
		alt_pose_roll = 0,
		alt_pose_pitch = 40,
		alt_pose_yaw = 0,
		-- UT's third person mesh of the weapon (SniperAttachment's Weapons.Sniper_3rd) at UT's size in a player's hand (DrawScale 0.4). Its
		-- origin is by its grip, and its barrel runs along its forward, to the muzzle (the mesh's tip, convert_static.py). The game links
		-- the staff to the left hand's node (AttachmentNodeLinking.one_handed_melee_weapon.left), whose forward points out to the hero's
		-- left. The mesh is turned a quarter from it, so it points ahead from the hand at her side.
		third_person = {
			id = variant.id,
			template = definition.template,
			unit_name = "units/ut/lightning/third_person",
			hand_node = "j_leftweaponattach",
			meters_per_unit = 0.02 * 0.4,
			-- (a little smaller than UT's, where it is 70% of a player's height: it looked too big on Kerillian)
			scale = 0.85,
			-- (set in the game)
			grip_right = -4,
			grip_forward = -4,
			grip_up = 0,
			-- (turned right and up from the hand's own direction so that it points ahead: set in the game. The turns are about the hand's
			-- axes, so with the barrel along the hand's forward after the yaw, tipping it up is the roll.)
			yaw = -110,
			pitch = 0,
			roll = -25,
			follow_game_unit = 3,
			muzzle_right = -2.8,
			muzzle_forward = 116.4,
			muzzle_up = 9.6,
			menu_yaw = -90,
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

			lightning.zoom.sound(skin, api)

			update_charge(skin, dt, api)
		end,
		on_level_exit = function ()
			charge_time = 0

			table.clear(third_person_charges)
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
-- animations instead. The characters don't play it either: UT's characters only hold the gun when they fire. Venting the heat is an
-- action of its own (weapon_reload), whose animation is still played.
local function is_shot_animation(event)
	return event == "attack_shoot" or event == "attack_shoot_last"
end

for template_name in pairs(TEMPLATE_NAMES) do
	mod.first_person_animation_filters[template_name] = is_shot_animation
	mod.third_person_animation_filters[template_name] = is_shot_animation
end
