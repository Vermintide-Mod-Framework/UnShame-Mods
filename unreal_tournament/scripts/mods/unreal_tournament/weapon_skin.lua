local mod = get_mod("unreal_tournament")

-- The weapon skins (the Weapon Skins setting): a UT2004 weapon's first person model, in the player's own first person view, and
-- the pickup mesh of it in every character's hand, played with the game's own events. The gameplay is the weapon's own file's: a
-- skin only draws it differently. mod.weapon_skin.new(definition) makes the skin of a weapon; its own file says what it does with
-- the shots, the projectiles, the effects and the sounds, and this file is what all of them do.
--
-- The game's weapon and arms are hidden, and UT2004's model is linked to the first person unit, as the game's own weapons are. It is
-- drawn where UT2004 draws it: the mesh is moved by the root bone of the animation it plays, drawn at DrawScale, turned by
-- PlayerViewPivot, at PlayerViewOffset scaled by 90 / DisplayFOV (Pawn.CalcDrawOffset), and seen with the field of view UT2004
-- draws weapons with. A point at (right, forward, up) in UT's view lands in the same place of the screen in this game's view, with its
-- own field of view, at (c * right, forward, c * up) * k, where c is the ratio of the tangents of the half field of views across the
-- screen and k is any distance scale: the gun is wider and taller across than it is long. The other bones of the animation
-- (a hammer, a barrel, a plunger) are the poses of nodes of the unit, against the root's move.
--
-- The animations are UT's, played with the timing of the game's: the pickup lasts as long as the game's wield cooldown, a shot
-- plays when the action of it starts. The game has no animation of putting a weapon down, so the model is gone as the weapon is
-- put away.
--
-- A definition (the numbers of the weapon's class in UT2004, the files tools/asset_conversion made):
--   id, name: the weapon's setting (flak_cannon) and its name in the messages, template: the game's weapon template it replaces
--   always: the weapon has no setting, the skin is always shown
--   unit_name, animations: the unit, and its animations ({ bones = { "root", nodes... }, animations = { Name = { rate, frames } } },
--       a frame is seven numbers for each bone: a rotation (x, y, z, w) and a move (right, forward, up in UT units))
--   muzzle_node: the node of the unit where the muzzle is
--   model_meters_per_unit: the meters a UT unit of the unit's mesh is as it was converted; meters_per_unit: the distance scale
--   display_fov (DisplayFOV), draw_scale (DrawScale), offset_forward/right/up (PlayerViewOffset X, Y, Z), pivot_pitch/yaw/roll
--       (PlayerViewPivot, degrees), field_of_view (the horizontal one, if it is not the one DisplayFOV gives)
--   bob, bob_damping, bob_smoothing, ut_ground_speed: the weapon's sway (Pawn.CheckBob, Pawn.WeaponBob)
--   blend_time: the seconds in which one animation blends into the next
--   alt_pose_right/forward/up (UT units), alt_pose_roll/pitch/yaw (degrees, the roll is the right side down, the pitch the muzzle up, the
--       yaw the muzzle to the left): a second place for the model in the view (held sideways, say), which the weapon's file moves it to
--       with skin.alt_pose, 0 (where UT has it) to 1. inspect_pose_* are a third, for the inspect, with skin.inspect_pose. skin.extra_yaw is
--       a turn that is added to them, degrees, for what moves while it is held there.
--   third_person: what weapon_skin_third_person.lua takes
--   looks: { [skin key] = { ... } } skins (illusions, see items.lua) that look different. While the weapon with that skin is wielded,
--       the values in the look replace the same values of the definition above (the unit, its animations, where it is drawn, ...).
--       A third_person in a look is that look's full third person definition. The weapon's own skin is the definition itself.
--   on_create(skin), on_update(skin, dt), on_destroy(skin): what is the weapon's own of the model that is shown
--   on_pose(skin, pose): every frame before the model is placed, to change the pose of the bones that the animations don't (UT sets some
--       by code: the barrel of the Rocket Launcher). pose is the row of numbers of a frame (a bone's are at (index - 1) * 7 + 1).
--   on_update_always(dt): every frame, shown or not; on_refresh(): when the setting or the weapon is switched; on_give_back(),
--   on_level_exit(): what is its own to take back and to clear

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local third_person_module = mod:dofile("scripts/mods/unreal_tournament/weapon_skin_third_person")

-- The skins, by setting id (for /skin)
local skins = {}

-- The factor that the horizontal field of view of a weapon is of tan(DisplayFOV / 2) at this aspect: the one that UT2004's picture
-- of the Shock Rifle fits (86.5 degrees for a DisplayFOV of 70)
local FIELD_OF_VIEW_FACTOR = 1.345

-- The aspect ratio of the screen that picture was of (and so of that horizontal field of view): this game keeps the vertical field of view
-- of the view when the screen is wider or narrower, as UT2004 does, so the weapon is the same height and the same angle from the middle of
-- the view on any screen, and a wider one shows more beside it. The aspect of the screen it is seen on is not used.
local REFERENCE_ASPECT = 16 / 9

-- The materials of the first person weapons are drawn with the game's custom FOV for weapons (see units/ut/weapon_standard.material), which
-- is a field of view of its own, not the camera's: the model is placed for the field of view it is drawn with. It is not known where the
-- engine sets it, so this is fitted to how the weapon looked before the change (65, the first person camera's vertical_fov in
-- settings/camera_settings.lua, drew it too big and too far out, 50 too small and too near the middle of the view, and 60 still not right: it
-- is between 50 and 60).
local WEAPON_VERTICAL_FOV = math.rad(55)

local function new(def)
	local CONFIG = {
		blend_time = 0.1,
		bob = 0.0035,
		bob_damping = 1.5,
		bob_smoothing = 10,
		meters_per_unit = 0.01,
		offset_forward = 0,
		offset_right = 0,
		offset_up = 0,
		pivot_pitch = 0,
		pivot_roll = 0,
		pivot_yaw = 0,
		ut_ground_speed = 440,
		alt_pose_forward = 0,
		alt_pose_pitch = 0,
		alt_pose_right = 0,
		alt_pose_roll = 0,
		alt_pose_up = 0,
		alt_pose_yaw = 0,
		inspect_pose_forward = 0,
		inspect_pose_pitch = 0,
		inspect_pose_right = 0,
		inspect_pose_roll = 0,
		inspect_pose_up = 0,
		inspect_pose_yaw = 0,
		inspect_turn_start = 0,
		inspect_pivot_forward = 0,
		inspect_pivot_right = 0,
		inspect_pivot_up = 0,
	}

	for key, value in pairs(def) do
		CONFIG[key] = value
	end

	local HIDE_REASON = "ut_skin_" .. CONFIG.id
	local bones = CONFIG.animations.bones
	local animations = CONFIG.animations.animations
	local bone_count = #bones

	-- A copy of the definition without any look, and the keys that looks replace.
	local BASE = {}
	local REPLACED = {}
	local third_person_looks

	for key, value in pairs(CONFIG) do
		BASE[key] = value
	end

	for skin_key, look in pairs(CONFIG.looks or {}) do
		third_person_looks = third_person_looks or {}
		third_person_looks[skin_key] = look.third_person

		for key in pairs(look) do
			REPLACED[key] = true
		end
	end

	-- Returns the look for a skin key, or nothing for the weapon's own look.
	local function look_of(skin_key)
		return skin_key and CONFIG.looks and CONFIG.looks[skin_key] and skin_key or nil
	end

	-- The look CONFIG currently has.
	local current_look

	local function set_look(name)
		if name == current_look then
			return
		end

		current_look = name

		for key in pairs(REPLACED) do
			CONFIG[key] = BASE[key]
		end

		for key, value in pairs(name and CONFIG.looks[name] or {}) do
			CONFIG[key] = value
		end

		bones = CONFIG.animations.bones
		animations = CONFIG.animations.animations
		bone_count = #bones
	end

	local self = {}

	-- The state of the skin that is shown. Nothing when none is.
	--   world, unit: the model, nodes: the node of each bone
	--   animation, time, speed: what is playing (the time is of the animation as it is in the file, speed makes it last as long
	--       as it is to), blend_from, blend_left: the pose it blends from
	--   muzzle_node: the node of the model where the muzzle is, unit_scale: how many meters a UT unit of the model is in the world
	--   bob_speed, bob_time, walk_right, walk_up
	-- and what the weapon's own functions put in it
	local skin
	local debug_enabled = false

	local third_person = third_person_module.new(BASE.third_person, third_person_looks)

	self.third_person = third_person
	self.look_of = look_of
	self.config = CONFIG

	function self.debug(text, ...)
		if debug_enabled then
			mod:echo(CONFIG.name .. " skin: " .. text, ...)
		end
	end

	function self.state()
		return skin
	end

	function self.enabled()
		return CONFIG.always or utils.is_weapon_skin_enabled(CONFIG.id)
	end

	-- Sounds (the events are in the weapon's bank, see tools/asset_conversion/make_bank.py): from the head of the player, or from a place
	function self.play_sound(event)
		WwiseWorld.trigger_event(Managers.world:wwise_world(Managers.world:world("level_world")), event)
	end

	function self.play_sound_at(event, position)
		local id = WwiseUtils.trigger_position_event(Managers.world:world("level_world"), event, position)

		-- (no id means the engine did not play it: the event is not in a loaded bank)
		self.debug("sound %s at %s: id %s", event, tostring(position), tostring(id))
	end

	local function local_first_person()
		local player = Managers.player and Managers.player:local_player()
		local owner = player and player.player_unit

		return owner and Unit.alive(owner) and ScriptUnit.has_extension(owner, "first_person_system")
	end

	self.local_first_person = local_first_person

	local function item_template_name(item_data)
		return item_data and BackendUtils.get_item_template(item_data).name
	end

	-- The muzzle's position in the world, as the camera sees it. The model is drawn with its own, narrower field of view (WEAPON_VERTICAL_FOV),
	-- so the point is moved away from the view axis by the ratio of the tangents of the half angles. The camera draws the shot's effects.
	function self.muzzle_position()
		if not skin or not Unit.alive(skin.unit) then
			return nil
		end

		local position = Unit.world_position(skin.unit, skin.muzzle_node)
		local camera_manager = Managers.state.camera
		local camera_position = camera_manager:camera_position("player_1")
		local camera_rotation = camera_manager:camera_rotation("player_1")
		local ratio = math.tan(camera_manager:fov("player_1") / 2) / math.tan(WEAPON_VERTICAL_FOV / 2)
		local right, forward, up = Quaternion.right(camera_rotation), Quaternion.forward(camera_rotation), Quaternion.up(camera_rotation)
		local offset = position - camera_position

		return camera_position + right * (Vector3.dot(offset, right) * ratio) + forward * Vector3.dot(offset, forward) + up * (Vector3.dot(offset, up) * ratio)
	end

	-- The same point in the first person unit's frame (x right, y ahead, z up), from the model's local pose, not its world position. Returns the
	-- unit and the point, for particles linked to the unit (skin_particles.lua).
	function self.muzzle_in_view()
		local fp = local_first_person()

		if not skin or not Unit.alive(skin.unit) or not fp then
			return nil
		end

		local at = Matrix4x4.transform(Unit.local_pose(skin.unit, 0), Unit.local_position(skin.unit, skin.muzzle_node))
		local ratio = math.tan(Managers.state.camera:fov("player_1") / 2) / math.tan(WEAPON_VERTICAL_FOV / 2)

		return fp.first_person_unit, Vector3(at.x * ratio, at.y, at.z * ratio)
	end

	-- How long the game takes to wield a weapon: nothing can be done with the weapon for that long
	local function wield_time()
		return rawget(Weapons, CONFIG.template).actions.action_wield.default.wield_cooldown
	end

	-- The game's weapon and arms

	local function hide_game_weapon(fp)
		if not fp.hide_weapon_reasons[HIDE_REASON] then
			fp:hide_weapons(HIDE_REASON, true)
		end

		Unit.set_unit_visibility(fp.first_person_attachment_unit, false)
	end

	local function show_game_weapon(fp)
		fp:unhide_weapons(HIDE_REASON)
		Unit.set_unit_visibility(fp.first_person_attachment_unit, fp:first_person_mode_active())
	end

	-- If the game would show its own weapon now (it hides it for the reasons of its own too)
	local function game_shows_weapon(fp)
		for reason in pairs(fp.hide_weapon_reasons) do
			if reason ~= HIDE_REASON then
				return false
			end
		end

		return fp:first_person_mode_active() and fp:first_person_units_visible() and utils.character_animation_is_free(fp.unit)
	end

	-- If the player's own model is the one that is seen (the first person view): not the mesh in the hand
	function self.shown_in_first_person()
		return skin ~= nil and Unit.alive(skin.unit) and not third_person.shows_weapon(Managers.player:local_player().player_unit)
	end

	-- Animations

	-- A pose: for each bone the rotation of what hangs off it (x, y, z, w) and its move (right, forward, up in UT units), in a row
	local function sample(name, time, looping)
		local animation = animations[name]
		local frames = animation.frames
		local count = #frames
		local position = time * animation.rate

		if not looping then
			position = math.min(position, count - 1)
		end

		local index = math.floor(position)
		local fraction = position - index
		local first = frames[index % count + 1]
		local second = frames[(looping and (index + 1) % count or math.min(index + 1, count - 1)) + 1]
		local pose = {}

		for b = 0, bone_count - 1 do
			local o = b * 7
			-- (the rotations of two frames are the same turn if they are opposite: the short way)
			local sign = (first[o + 1] * second[o + 1] + first[o + 2] * second[o + 2] + first[o + 3] * second[o + 3] + first[o + 4] * second[o + 4]) < 0 and -1 or 1

			for i = 1, 4 do
				pose[o + i] = first[o + i] + (sign * second[o + i] - first[o + i]) * fraction
			end

			for i = 5, 7 do
				pose[o + i] = first[o + i] + (second[o + i] - first[o + i]) * fraction
			end
		end

		return pose
	end

	-- (the move is blended as it is, the rotations go the short way round and are made whole again)
	local function blend_poses(from, to, fraction)
		local pose = {}

		for b = 0, bone_count - 1 do
			local o = b * 7
			local sign = (from[o + 1] * to[o + 1] + from[o + 2] * to[o + 2] + from[o + 3] * to[o + 3] + from[o + 4] * to[o + 4]) < 0 and -1 or 1

			for i = 1, 7 do
				pose[o + i] = from[o + i] + ((i <= 4 and sign or 1) * to[o + i] - from[o + i]) * fraction
			end

			local length = math.sqrt(pose[o + 1] * pose[o + 1] + pose[o + 2] * pose[o + 2] + pose[o + 3] * pose[o + 3] + pose[o + 4] * pose[o + 4])

			for i = 1, 4 do
				pose[o + i] = pose[o + i] / length
			end
		end

		return pose
	end

	function self.animation_duration(name)
		return #animations[name].frames / animations[name].rate
	end

	local function current_pose()
		local pose = sample(skin.animation, skin.time, skin.animation == (CONFIG.idle_animation or "Idle"))

		if skin.blend_from and skin.blend_left > 0 then
			pose = blend_poses(skin.blend_from, pose, 1 - skin.blend_left / CONFIG.blend_time)
		end

		return pose
	end

	-- Plays an animation, from the pose of the one that is playing; for a time of its own if one is given
	function self.play(name, duration)
		self.debug("%s", name)

		if skin.animation then
			skin.blend_from = current_pose()
			skin.blend_left = CONFIG.blend_time
		end

		skin.animation = name
		skin.time = 0
		skin.speed = duration and self.animation_duration(name) / duration or 1
	end

	-- The skin

	local function destroy(first_person_is_going)
		if not skin then
			return
		end

		local finished = skin

		skin = nil

		if CONFIG.on_destroy then
			CONFIG.on_destroy(finished)
		end

		if Unit.alive(finished.unit) then
			AttachmentUtils.unlink(finished.world, finished.unit)
			World.destroy_unit(finished.world, finished.unit)
		end

		if not first_person_is_going then
			local fp = local_first_person()

			if fp then
				show_game_weapon(fp)
			end
		end

		self.debug("gone")
	end

	local place

	local function create(fp, skin_key)
		destroy()
		set_look(look_of(skin_key))

		local world = Managers.world:world("level_world")
		local unit = World.spawn_unit(world, CONFIG.unit_name, Vector3(0, 0, 0))

		-- (a new unit has the pose of the file, a big model at the camera, until it is placed: it is not shown before that)
		Unit.set_unit_visibility(unit, false)

		-- The root of the first person unit is where the camera is, and it turns with it
		AttachmentUtils.link(world, fp.first_person_unit, unit, {
			{
				source = 0,
				target = 0,
			},
		})

		-- (the skin is kept before anything else is asked of the unit, so that a failure leaves it where destroy finds it: a unit of
		-- the mod's package that is alive when the package is unloaded, with the mod being reloaded, crashes the game)
		skin = {
			look = current_look,
			bob_speed = 0,
			bob_time = 0,
			nodes = {},
			unit = unit,
			unit_scale = CONFIG.draw_scale * CONFIG.meters_per_unit,
			walk_right = 0,
			walk_up = 0,
			world = world,
		}

		for b = 2, bone_count do
			skin.nodes[b] = Unit.node(unit, bones[b])
		end

		skin.muzzle_node = Unit.node(unit, CONFIG.muzzle_node)

		if CONFIG.on_create then
			CONFIG.on_create(skin)
		end

		-- (the game has just shown its own weapon, which is the one that is wielded now)
		fp:hide_weapons(HIDE_REASON, true)
		hide_game_weapon(fp)
		self.play(CONFIG.pickup_animation or "Pickup", wield_time())
		place(fp)
		Unit.set_unit_visibility(unit, game_shows_weapon(fp))
	end

	-- Made when the setting or the weapon is switched, and when what is wielded is the weapon
	local function refresh()
		local fp = local_first_person()

		if CONFIG.on_refresh then
			CONFIG.on_refresh()
		end

		if not self.enabled() or not fp then
			destroy()

			return
		end

		if not skin and utils.wielded_template_name(fp.unit) == CONFIG.template then
			create(fp, utils.wielded_skin(fp.unit))
		end
	end

	mod.setting_changed_callbacks[#mod.setting_changed_callbacks + 1] = function (changed_setting_id)
		if changed_setting_id == "weapon_skins" or changed_setting_id == CONFIG.id or changed_setting_id == "ut_weapons" then
			refresh()
		end
	end

	mod.enabled_callbacks[#mod.enabled_callbacks + 1] = refresh

	-- (the mod is switched off or unloaded: the setting reads as it is, what the weapon took is given back)
	local function give_back()
		destroy()
		third_person.clear()

		if CONFIG.on_give_back then
			CONFIG.on_give_back()
		end
	end

	mod.disabled_callbacks[#mod.disabled_callbacks + 1] = give_back
	mod.unload_callbacks[#mod.unload_callbacks + 1] = give_back
	mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
		destroy(true)
		third_person.clear()

		if CONFIG.on_level_exit then
			CONFIG.on_level_exit()
		end
	end

	mod.first_person_destroy_callbacks[CONFIG.id] = function (first_person_extension)
		if skin and utils.is_local_player_unit(first_person_extension.unit) then
			destroy(true)
		end
	end

	-- The weapon that is wielded
	mod.wield_callbacks[CONFIG.id] = function (inventory_extension, equipment, slot_data)
		if slot_data and item_template_name(slot_data.item_data) == CONFIG.template and self.enabled() then
			create(inventory_extension.first_person_extension, slot_data.skin)
		end
	end

	-- The weapon that is put away: the model is gone, the arms are the game's again for the weapon that comes next
	mod.unwield_callbacks[CONFIG.id] = function (inventory_extension, equipment, previous_item_data)
		if skin and item_template_name(previous_item_data) == CONFIG.template then
			destroy()
		end
	end

	-- A sound of the game's that the player's own action plays (and tells the others of) is taken over by one of the skin's:
	-- ut_event is the name of the event of the skin, a function that gives it, or nothing for none
	function self.take_over_sound(game_event, ut_event)
		mod.hud_sound_callbacks[game_event] = mod.hud_sound_callbacks[game_event] or {}
		mod.hud_sound_callbacks[game_event][CONFIG.id] = function (first_person_extension)
			if not self.enabled() or not utils.is_local_player_unit(first_person_extension.unit) then
				return false
			end

			if utils.wielded_template_name(first_person_extension.unit) ~= CONFIG.template then
				return false
			end

			local event = type(ut_event) == "function" and ut_event() or ut_event

			if event then
				self.play_sound(event)
			end

			return true
		end
	end

	-- Every frame

	-- Weapon bob (Pawn.CheckBob and Pawn.WeaponBob), in UT units: (right, up)
	local function update_bob(owner_unit, dt)
		local locomotion_extension = ScriptUnit.extension(owner_unit, "locomotion_system")
		local movement_settings = PlayerUnitMovementSettings.get_movement_settings_table(owner_unit)
		local state = ScriptUnit.extension(owner_unit, "character_state_machine_system").state_machine.state_current
		local speed = 0

		-- (the speed that the game's own walking state works out for the player, as it moves it: the top speed of how it walks (crouched, with the
		-- walk key, or not), times what slows or quickens it and how far it has got up to it. It is not the velocity this game gives for a frame,
		-- which jumps about when the player steps, lands or is pushed. The bob is none while the player is not walking on the ground)
		if state.name == "walking" and locomotion_extension:is_on_ground() then
			local status_extension = ScriptUnit.extension(owner_unit, "status_system")
			local is_walking = ScriptUnit.extension(owner_unit, "input_system"):get("walk")
			local top_speed = status_extension:is_crouching() and movement_settings.crouch_move_speed or is_walking and movement_settings.walk_move_speed or movement_settings.move_speed

			-- (the speeds of the player's own table are the ones that the buffs of an action change, venting the heat slows them: against the
			-- speed of the game's settings, which they do not change, a slowed player is slower)
			speed = top_speed * status_extension:current_move_speed_multiplier() * state.current_movement_speed_scale / PlayerUnitMovementSettings.move_speed * CONFIG.ut_ground_speed
		end

		-- (the speed the bob follows is smoothed, and the phase of the sway is kept, so that the model doesn't jump)
		local target_speed = speed

		skin.bob_speed = skin.bob_speed + (target_speed - skin.bob_speed) * math.min(1, CONFIG.bob_smoothing * dt)
		skin.bob_time = skin.bob_time + dt * (skin.bob_speed < 10 and 0.2 or 0.3 + 0.7 * skin.bob_speed / CONFIG.ut_ground_speed)
		skin.walk_right = CONFIG.bob * skin.bob_speed * math.sin(8 * skin.bob_time)
		skin.walk_up = 0.75 * CONFIG.bob * skin.bob_speed * math.sin(16 * skin.bob_time)
	end

	local function update_animation(dt)
		skin.time = skin.time + dt * skin.speed

		if skin.blend_left then
			skin.blend_left = skin.blend_left - dt
		end

		local duration = self.animation_duration(skin.animation)

		if skin.animation == (CONFIG.idle_animation or "Idle") then
			skin.time = skin.time % duration
		elseif skin.time >= duration then
			self.play(CONFIG.idle_animation or "Idle")
		end
	end

	-- PlayerViewPivot as a turn in this game's axes: UT's yaw turns to the right, its pitch up and its roll the right side up, and
	-- the order is roll, pitch, yaw
	local function pivot_rotation()
		local yaw = Quaternion.axis_angle(Vector3(0, 0, 1), -math.rad(CONFIG.pivot_yaw))
		local pitch = Quaternion.axis_angle(Vector3(1, 0, 0), math.rad(CONFIG.pivot_pitch))
		local roll = Quaternion.axis_angle(Vector3(0, 1, 0), -math.rad(CONFIG.pivot_roll))

		return Quaternion.multiply(yaw, Quaternion.multiply(pitch, roll))
	end

	-- Where the model is, and how it is turned and scaled, in the first person unit's root, and the pose of its other bones
	function place(fp)
		local tangent_vertical = math.tan(WEAPON_VERTICAL_FOV / 2)
		local field_of_view = CONFIG.field_of_view or 2 * math.atan(math.tan(math.rad(CONFIG.display_fov) / 2) * FIELD_OF_VIEW_FACTOR)
		local across = tangent_vertical * REFERENCE_ASPECT / math.tan(field_of_view / 2)
		local forward_scale = CONFIG.meters_per_unit
		local across_scale = forward_scale * across
		local pose = current_pose()

		if CONFIG.on_pose then
			CONFIG.on_pose(skin, pose)
		end

		local pivot = pivot_rotation()
		local offset_scale = 90 / CONFIG.display_fov

		-- The move of the animation is the mesh's, turned by the pivot as everything of the mesh is
		local move = Quaternion.rotate(pivot, Vector3(pose[5], pose[6], pose[7]))
		local bob_right = CONFIG.bob_damping * skin.walk_right
		local bob_up = (0.45 + 0.55 * CONFIG.bob_damping) * skin.walk_up
		local alt = skin.alt_pose or 0
		local inspect = skin.inspect_pose or 0
		local position = Vector3(
			across_scale * (CONFIG.draw_scale * move.x + CONFIG.offset_right * offset_scale + bob_right + alt * CONFIG.alt_pose_right + inspect * CONFIG.inspect_pose_right),
			forward_scale * (CONFIG.draw_scale * move.y + CONFIG.offset_forward * offset_scale + alt * CONFIG.alt_pose_forward + inspect * CONFIG.inspect_pose_forward),
			across_scale * (CONFIG.draw_scale * move.z + CONFIG.offset_up * offset_scale + bob_up + alt * CONFIG.alt_pose_up + inspect * CONFIG.inspect_pose_up)
		)
		local size = CONFIG.draw_scale / CONFIG.model_meters_per_unit
		local rotation = Quaternion.multiply(pivot, Quaternion.from_elements(pose[1], pose[2], pose[3], pose[4]))

		-- (turned about the way the view looks, after everything of the model's own: the roll about the way it looks, the pitch about
		-- the way it is to the right, the yaw about up; skin.extra_yaw is a turn of the weapon's own, degrees, as it plays)
		-- (the inspect turn starts when the inspect pose is inspect_turn_start of the way: the weapon is brought forward first, then turned)
		local inspect_turn = math.clamp((inspect - CONFIG.inspect_turn_start) / (1 - CONFIG.inspect_turn_start), 0, 1)
		local roll = alt * CONFIG.alt_pose_roll + inspect_turn * CONFIG.inspect_pose_roll
		local pitch = alt * CONFIG.alt_pose_pitch + inspect_turn * CONFIG.inspect_pose_pitch
		local yaw = alt * CONFIG.alt_pose_yaw + inspect_turn * CONFIG.inspect_pose_yaw + (skin.extra_yaw or 0)

		if roll ~= 0 or pitch ~= 0 or yaw ~= 0 then
			local turn = Quaternion.multiply(Quaternion.axis_angle(Vector3(0, 0, 1), math.rad(yaw)), Quaternion.multiply(Quaternion.axis_angle(Vector3(1, 0, 0), math.rad(pitch)), Quaternion.axis_angle(Vector3(0, 1, 0), math.rad(roll))))

			rotation = Quaternion.multiply(turn, rotation)

			-- The turn is about the point of the model that the inspect_pivot_* say (UT units, in the axes of the view, from the model's
			-- origin), not about its origin, so a long model turns about its middle
			local pivot_point = Vector3(CONFIG.inspect_pivot_right, CONFIG.inspect_pivot_forward, CONFIG.inspect_pivot_up)
			local moved = pivot_point - Quaternion.rotate(turn, pivot_point)

			position = position + Vector3(moved.x * across_scale, moved.y * forward_scale, moved.z * across_scale)
		end

		-- The model's pose is the turn, then the scale of the view (across, forward, across): a scale that is applied after the turn, in the
		-- axes of the view (a node's own scale is applied before it, in the axes of the model, which is the same only when the model is
		-- not turned: the Flak Cannon lies sideways and is turned by its pivot). The images of the model's axes are the columns of the turn,
		-- each scaled by the view.
		local function image(axis)
			return Vector3(axis.x * across_scale, axis.y * forward_scale, axis.z * across_scale) * size
		end

		local right, forward, up = image(Quaternion.right(rotation)), image(Quaternion.forward(rotation)), image(Quaternion.up(rotation))

		Unit.set_local_pose(skin.unit, 0, Matrix4x4(right.x, right.y, right.z, forward.x, forward.y, forward.z, up.x, up.y, up.z, position.x, position.y, position.z))

		-- (the other bones are against the root's move, in the meters of the mesh)
		for b = 2, bone_count do
			local o = (b - 1) * 7

			Unit.set_local_pose(skin.unit, skin.nodes[b], Matrix4x4.from_quaternion_position(
				Quaternion.from_elements(pose[o + 1], pose[o + 2], pose[o + 3], pose[o + 4]),
				Vector3(pose[o + 5], pose[o + 6], pose[o + 7]) * CONFIG.model_meters_per_unit
			))
		end

		-- (a UT unit of the model, across: what is drawn on it is as big as the model is)
		skin.unit_scale = CONFIG.draw_scale * across_scale
	end

	mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
		if CONFIG.on_update_always then
			CONFIG.on_update_always(dt)
		end

		third_person.update()

		if not skin then
			return
		end

		local fp = local_first_person()

		if not fp then
			destroy(true)

			return
		end

		-- The weapon is no longer wielded. Upgrading or rerolling the held weapon makes the game rebuild the inventory without announcing the
		-- put away, which would leave the melee weapon hidden.
		if utils.wielded_template_name(fp.unit) ~= CONFIG.template then
			destroy()

			return
		end

		-- A different skin was applied to the weapon being held (on the Illusions page): switch to its model.
		local skin_key = utils.wielded_skin(fp.unit)

		if look_of(skin_key) ~= skin.look then
			create(fp, skin_key)

			return
		end

		update_animation(dt)
		update_bob(fp.unit, dt)

		if CONFIG.on_update then
			CONFIG.on_update(skin, dt)
		end

		Unit.set_unit_visibility(skin.unit, game_shows_weapon(fp))
		place(fp)
	end

	-- (the game shows its weapon and its arms again at times of its own, after the mod's update)
	mod.pre_render_callbacks[CONFIG.id] = function ()
		third_person.hide_staffs()

		if skin then
			local fp = local_first_person()

			if fp then
				hide_game_weapon(fp)
			end
		end
	end

	-- Development (/skin): what it does is told, an animation is played, a number of the definition is set
	function self.command(command, name, value)
		if command == "debug" then
			debug_enabled = not debug_enabled

			mod:echo("%s skin: debug %s", CONFIG.name, debug_enabled and "on" or "off")
		elseif command == "play" and skin and animations[name] then
			self.play(name)
		elseif command == "set" and CONFIG[name] ~= nil and tonumber(value) then
			CONFIG[name] = tonumber(value)

			mod:echo("%s skin: %s is %s", CONFIG.name, name, tostring(CONFIG[name]))
		elseif command == "report" then
			third_person.report()
		elseif command == "3p" and tonumber(value) then
			third_person.set(name, tonumber(value))

			mod:echo("%s skin, third person: %s is %s", CONFIG.name, name, value)
		else
			mod:echo("%s skin: debug | report | play <animation> | set <number> <value> | 3p <number> <value>", CONFIG.name)
		end
	end

	skins[CONFIG.id] = self

	return self
end

mod:command("skin", "<weapon> debug | report | play <animation> | set <number> <value> | 3p <number> <value> - the weapon skins", function (id, ...)
	local skin = id and skins[id]

	if skin then
		skin.command(...)
	else
		local names = {}

		for name in pairs(skins) do
			names[#names + 1] = name
		end

		table.sort(names)
		mod:echo("skin: one of %s", table.concat(names, ", "))
	end
end)

return {
	new = new,
	-- By setting id
	skins = skins,
}
