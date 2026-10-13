local mod = get_mod("unreal_tournament")

-- The weapon skins. A skin shows a UT2004 weapon: its first person model in the player's own view, and its pickup mesh in the hand of
-- every character. The gameplay is in the weapon's own file, and a skin only draws it differently. mod.weapon_skin.new(definition)
-- makes the skin of one weapon. The weapon's own skin file says what it does with the shots, projectiles, effects and sounds. This
-- file does what all the skins have in common.
--
-- The game's weapon and arms are hidden, and UT2004's model is linked to the first person unit, as the game's own weapons are. It is
-- drawn where UT2004 draws it. The root bone of the animation moves the mesh. The mesh is drawn at DrawScale, turned by
-- PlayerViewPivot, at PlayerViewOffset scaled by 90 / DisplayFOV (Pawn.CalcDrawOffset), and seen with the field of view UT2004 uses
-- for weapons. A point at (right, forward, up) in UT's view lands at the same place on the screen in this game's view, with its own
-- field of view, at (c * right, forward, c * up) * k. Here c is the ratio of the tangents of the half fields of view across the
-- screen, and k is any distance scale. So the gun is wider and taller across than it is long. The other bones of the animation (a
-- hammer, a barrel, a plunger) are poses of nodes of the unit, relative to the root's move.
--
-- The animations are UT's, timed like the game's: the pickup lasts as long as the game's wield cooldown, and a shot plays when its
-- action starts. The game has no animation for putting a weapon down, so the model just disappears when the weapon is put away.
--
-- A definition holds the numbers of the weapon's class in UT2004, and the files that tools/asset_conversion made:
--   id, name: the weapon's id (flak_cannon, used by /skin) and its name in messages. template: the game weapon template this is the
--       skin of.
--   unit_name, animations: the unit and its animations. animations is { bones = { "root", nodes... }, animations = { Name = { rate,
--       frames } } }. A frame is seven numbers for each bone: a rotation (x, y, z, w) and a move (right, forward, up in UT units).
--   muzzle_node: the node of the unit where the muzzle is
--   model_meters_per_unit: the meters per UT unit of the mesh as it was converted. meters_per_unit: the distance scale.
--   display_fov (DisplayFOV), draw_scale (DrawScale), offset_forward/right/up (PlayerViewOffset X, Y, Z), pivot_pitch/yaw/roll
--       (PlayerViewPivot, degrees), field_of_view (the horizontal one, if it is not the one DisplayFOV gives)
--   bob, bob_damping, bob_smoothing, ut_ground_speed: the weapon's sway (Pawn.CheckBob, Pawn.WeaponBob)
--   blend_time: seconds it takes one animation to blend into the next
--   idle_speed: how fast the idle animation plays compared to its own rate (the weapon's IdleAnimRate, or 1 if it has none)
--   alt_pose_right/forward/up (UT units) and alt_pose_roll/pitch/yaw (degrees): a second place for the model in the view, for example
--       held sideways. The roll puts the right side down, the pitch points the muzzle up, and the yaw points it to the left. The
--       weapon's file moves the model there with skin.alt_pose, from 0 (where UT has it) to 1.
--       inspect_pose_* is a third place, for inspecting, used with skin.inspect_pose. skin.extra_yaw adds a turn (in degrees) to
--       them, for things that move while the model is held there.
--   third_person: what weapon_skin_third_person.lua takes
--   looks: { [skin key] = { ... } }. Skins (illusions, see items.lua) that look different. While a weapon with that skin is wielded,
--       the values in its look replace the same values in the definition (the unit, its animations, where it is drawn, and so on).
--       A third_person in a look is that look's complete third person definition. The weapon's own skin is the definition itself.
--   on_create(skin), on_update(skin, dt), on_destroy(skin): the weapon's own code for the model that is shown
--   on_pose(skin, pose): runs every frame before the model is placed. It can change the pose of bones that the animations don't move
--       (UT sets some by code: the Rocket Launcher's barrel). pose is the row of numbers of a frame, and a bone's numbers start at
--       (index - 1) * 7 + 1. skin.node_scales[bone index] = Vector3 scales a node along its own axes (a part that stretches, like
--       the Rocket Launcher's rod).
--   on_update_always(dt): runs every frame, whether the skin is shown or not
--   on_give_back(), on_level_exit(): the weapon takes back and clears what is its own

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local third_person_module = mod:dofile("scripts/mods/unreal_tournament/weapon_skin_third_person")

-- The skins, by id (used by /skin)
local skins = {}

-- How much bigger a weapon's horizontal field of view is than tan(DisplayFOV / 2) at the reference aspect. 1.345 is the value that
-- fits UT2004's picture of the Shock Rifle (86.5 degrees for a DisplayFOV of 70).
local FIELD_OF_VIEW_FACTOR = 1.345

-- The aspect ratio of the screen that picture was taken on, and so of that horizontal field of view. This game keeps the view's
-- vertical field of view when the screen is wider or narrower, as UT2004 does. So the weapon has the same height and the same angle
-- from the middle of the view on any screen, and a wider screen just shows more beside it. The aspect of the screen it is seen on is
-- not used.
local REFERENCE_ASPECT = 16 / 9

-- The first person weapon materials are drawn with the game's custom FOV for weapons (see units/ut/weapon_standard.material). That is
-- a field of view of its own, not the camera's, so the model is placed for the field of view it is drawn with. It is not known where
-- the engine sets it, so this was fitted by eye. 65 (the first person camera's vertical_fov in settings/camera_settings.lua) drew the
-- weapon too big and too far out, 50 too small and too near the middle, and 60 was still not right, so it is between 50 and 60.
local WEAPON_VERTICAL_FOV = math.rad(55)

local function new(def)
	local CONFIG = {
		blend_time = 0.1,
		idle_speed = 1,
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

	-- BASE is a copy of the definition without any look. REPLACED holds the keys that the looks replace.
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

	-- Returns the look for a skin key, or nil if the skin key means the weapon's own look.
	local function look_of(skin_key)
		return skin_key and CONFIG.looks and CONFIG.looks[skin_key] and skin_key or nil
	end

	-- The name of the look that CONFIG has right now.
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

	-- The state of the skin that is shown. It is nil when no skin is shown. The fields are:
	--   world, unit: the model. nodes: the node of each bone.
	--   animation, time, speed: the animation that is playing. The time is in the animation's own timing, and the speed stretches
	--       it to last as long as it should. blend_from and blend_left describe the pose it blends from.
	--   muzzle_node: the node of the model where the muzzle is. unit_scale: how many meters a UT unit of the model is in the world.
	--   bob_speed, bob_time, walk_right, walk_up: the weapon bob.
	-- The weapon's own functions can add fields of their own.
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

	-- Sounds. The events are in the weapon's bank (see tools/asset_conversion/make_bank.py). play_sound plays from the player's head,
	-- and play_sound_at plays from a place in the world.
	function self.play_sound(event)
		WwiseWorld.trigger_event(Managers.world:wwise_world(Managers.world:world("level_world")), event)
	end

	function self.play_sound_at(event, position)
		local id = WwiseUtils.trigger_position_event(Managers.world:world("level_world"), event, position)

		-- If there is no id, the engine did not play the sound, because the event is not in a loaded bank.
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

	-- Returns the muzzle's position in the world, as the camera sees it. The model is drawn with its own, narrower field of view
	-- (WEAPON_VERTICAL_FOV), so this moves the point away from the view axis by the ratio of the tangents of the half angles. The
	-- camera draws the shot's effects, so they need this position.
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

	-- Returns the same point in the first person unit's frame (x right, y ahead, z up). It is worked out from the model's local pose,
	-- not its world position. It returns the unit and the point, for particles that are linked to the unit (skin_particles.lua).
	function self.muzzle_in_view()
		local fp = local_first_person()

		if not skin or not Unit.alive(skin.unit) or not fp then
			return nil
		end

		local at = Matrix4x4.transform(Unit.local_pose(skin.unit, 0), Unit.local_position(skin.unit, skin.muzzle_node))
		local ratio = math.tan(Managers.state.camera:fov("player_1") / 2) / math.tan(WEAPON_VERTICAL_FOV / 2)

		return fp.first_person_unit, Vector3(at.x * ratio, at.y, at.z * ratio)
	end

	-- Returns how long the game takes to wield the weapon. The weapon can't be used for that long.
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

	-- Returns whether the game would show its own weapon now. The game also hides the weapon for reasons of its own.
	local function game_shows_weapon(fp)
		for reason in pairs(fp.hide_weapon_reasons) do
			if reason ~= HIDE_REASON then
				return false
			end
		end

		return fp:first_person_mode_active() and fp:first_person_units_visible() and utils.character_animation_is_free(fp.unit)
	end

	-- Returns whether the player sees their own first person model, and not the mesh in the hand.
	function self.shown_in_first_person()
		return skin ~= nil and Unit.alive(skin.unit) and not third_person.shows_weapon(Managers.player:local_player().player_unit)
	end

	-- Animations

	-- Returns the pose of an animation at a time, as a row of numbers. Each bone has the rotation of what hangs off it (x, y, z, w)
	-- and its move (right, forward, up in UT units).
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
			-- Opposite rotations are the same turn, so this picks the short way round
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

	-- Blends two poses. The move is blended as it is. The rotations go the short way round and are normalized again.
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

	-- Plays an animation and blends into it from the pose of the one that is playing. If a duration is given, the animation lasts that long.
	function self.play(name, duration)
		self.debug("%s", name)

		if skin.animation then
			skin.blend_from = current_pose()
			skin.blend_left = CONFIG.blend_time
		end

		skin.animation = name
		skin.time = 0
		skin.speed = duration and self.animation_duration(name) / duration or name == (CONFIG.idle_animation or "Idle") and CONFIG.idle_speed or 1
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

		-- A new unit starts in the pose of the file, a big model at the camera. It stays hidden until it is placed.
		Unit.set_unit_visibility(unit, false)

		-- The root of the first person unit is where the camera is, and it turns with it
		AttachmentUtils.link(world, fp.first_person_unit, unit, {
			{
				source = 0,
				target = 0,
			},
		})

		-- The skin is stored before anything else is done with the unit. If something fails after this, destroy can still find the
		-- unit. A unit of the mod's package that is still alive when the package is unloaded on a mod reload crashes the game.
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

		-- The game has just shown its own weapon, which is the one that is wielded now, so it is hidden again here.
		fp:hide_weapons(HIDE_REASON, true)
		hide_game_weapon(fp)
		self.play(CONFIG.pickup_animation or "Pickup", wield_time())
		place(fp)
		Unit.set_unit_visibility(unit, game_shows_weapon(fp))
	end

	-- Makes the skin when the mod is switched on while the weapon is wielded.
	mod.enabled_callbacks[#mod.enabled_callbacks + 1] = function ()
		local fp = local_first_person()

		if fp and not skin and utils.wielded_template_name(fp.unit) == CONFIG.template then
			create(fp, utils.wielded_skin(fp.unit))
		end
	end

	-- When the mod is switched off or unloaded, this gives back what the skin took.
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

	-- Makes the skin when the weapon is wielded.
	mod.wield_callbacks[CONFIG.id] = function (inventory_extension, equipment, slot_data)
		if slot_data and item_template_name(slot_data.item_data) == CONFIG.template then
			create(inventory_extension.first_person_extension, slot_data.skin)
		end
	end

	-- Removes the model when the weapon is put away. The arms go back to the game for the next weapon.
	mod.unwield_callbacks[CONFIG.id] = function (inventory_extension, equipment, previous_item_data)
		if skin and item_template_name(previous_item_data) == CONFIG.template then
			destroy()
		end
	end

	-- Takes over a game sound that the player's own action plays and tells the others about. The skin plays its own sound instead.
	-- ut_event is the name of the skin's event, a function that returns it, or nil for no sound.
	function self.take_over_sound(game_event, ut_event)
		mod.hud_sound_callbacks[game_event] = mod.hud_sound_callbacks[game_event] or {}
		mod.hud_sound_callbacks[game_event][CONFIG.id] = function (first_person_extension)
			if not utils.is_local_player_unit(first_person_extension.unit) then
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

	-- Updates the weapon bob (Pawn.CheckBob and Pawn.WeaponBob), in UT units (right, up). It runs every frame.
	local function update_bob(owner_unit, dt)
		local locomotion_extension = ScriptUnit.extension(owner_unit, "locomotion_system")
		local movement_settings = PlayerUnitMovementSettings.get_movement_settings_table(owner_unit)
		local state = ScriptUnit.extension(owner_unit, "character_state_machine_system").state_machine.state_current
		local speed = 0

		-- The speed here is the one the game's walking state works out as it moves the player. That is the top speed for how the
		-- player walks (crouched, with the walk key, or normally), times whatever slows or quickens them, and how far they have
		-- accelerated towards it. It is not the velocity for a single frame, which jumps about when the player steps, lands or is
		-- pushed. There is no bob while the player is not walking on the ground.
		if state.name == "walking" and locomotion_extension:is_on_ground() then
			local status_extension = ScriptUnit.extension(owner_unit, "status_system")
			local is_walking = ScriptUnit.extension(owner_unit, "input_system"):get("walk")
			local top_speed = status_extension:is_crouching() and movement_settings.crouch_move_speed or is_walking and movement_settings.walk_move_speed or movement_settings.move_speed

			-- The speeds in the player's own table are the ones that an action's buffs change, for example venting the heat slows
			-- them. They are divided by the speed in the game's settings, which buffs don't change, so a slowed player bobs slower.
			speed = top_speed * status_extension:current_move_speed_multiplier() * state.current_movement_speed_scale / PlayerUnitMovementSettings.move_speed * CONFIG.ut_ground_speed
		end

		-- The speed that the bob follows is smoothed, and the phase of the sway is kept, so the model doesn't jump.
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

	-- Returns PlayerViewPivot as a turn in this game's axes. In UT a positive yaw turns to the right, a positive pitch turns up, and a
	-- positive roll puts the right side up. The turns are applied in the order roll, pitch, yaw.
	local function pivot_rotation()
		local yaw = Quaternion.axis_angle(Vector3(0, 0, 1), -math.rad(CONFIG.pivot_yaw))
		local pitch = Quaternion.axis_angle(Vector3(1, 0, 0), math.rad(CONFIG.pivot_pitch))
		local roll = Quaternion.axis_angle(Vector3(0, 1, 0), -math.rad(CONFIG.pivot_roll))

		return Quaternion.multiply(yaw, Quaternion.multiply(pitch, roll))
	end

	-- Places the model in the first person unit's root: where it is, and how it is turned and scaled. Also sets the pose of its other
	-- bones.
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

		-- The animation's move belongs to the mesh, so it is turned by the pivot like everything else on the mesh.
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

		-- The extra turns are applied about the view's axes, after the model's own turns. The roll is about the way the view looks,
		-- the pitch about its right, and the yaw about up. skin.extra_yaw is a turn in degrees that the weapon's own code can add.
		-- The inspect turn only starts once the inspect pose is inspect_turn_start of the way there, so the weapon comes forward
		-- first and is turned after.
		local inspect_turn = math.clamp((inspect - CONFIG.inspect_turn_start) / (1 - CONFIG.inspect_turn_start), 0, 1)
		local roll = alt * CONFIG.alt_pose_roll + inspect_turn * CONFIG.inspect_pose_roll
		local pitch = alt * CONFIG.alt_pose_pitch + inspect_turn * CONFIG.inspect_pose_pitch
		local yaw = alt * CONFIG.alt_pose_yaw + inspect_turn * CONFIG.inspect_pose_yaw + (skin.extra_yaw or 0)

		if roll ~= 0 or pitch ~= 0 or yaw ~= 0 then
			local turn = Quaternion.multiply(Quaternion.axis_angle(Vector3(0, 0, 1), math.rad(yaw)), Quaternion.multiply(Quaternion.axis_angle(Vector3(1, 0, 0), math.rad(pitch)), Quaternion.axis_angle(Vector3(0, 1, 0), math.rad(roll))))

			rotation = Quaternion.multiply(turn, rotation)

			-- The turn is about the point of the model given by inspect_pivot_* (UT units, in the axes of the view, from the model's
			-- origin), not about the origin, so that a long model turns about its middle.
			local pivot_point = Vector3(CONFIG.inspect_pivot_right, CONFIG.inspect_pivot_forward, CONFIG.inspect_pivot_up)
			local moved = pivot_point - Quaternion.rotate(turn, pivot_point)

			position = position + Vector3(moved.x * across_scale, moved.y * forward_scale, moved.z * across_scale)
		end

		-- The model's pose is the turn followed by the view's scale (across, forward, across). The scale has to be applied after the
		-- turn, in the view's axes. A node's own scale is applied before the turn, in the model's axes, and that only gives the same
		-- result when the model is not turned. The Flak Cannon lies sideways and is turned by its pivot, so this matters. The model's
		-- axes after the turn are the columns of the turn, each scaled by the view.
		local function image(axis)
			return Vector3(axis.x * across_scale, axis.y * forward_scale, axis.z * across_scale) * size
		end

		local right, forward, up = image(Quaternion.right(rotation)), image(Quaternion.forward(rotation)), image(Quaternion.up(rotation))

		Unit.set_local_pose(skin.unit, 0, Matrix4x4(right.x, right.y, right.z, forward.x, forward.y, forward.z, up.x, up.y, up.z, position.x, position.y, position.z))

		-- The other bones are posed relative to the root's move, in the meters of the mesh.
		for b = 2, bone_count do
			local o = (b - 1) * 7
			local node_rotation = Quaternion.from_elements(pose[o + 1], pose[o + 2], pose[o + 3], pose[o + 4])
			local node_position = Vector3(pose[o + 5], pose[o + 6], pose[o + 7]) * CONFIG.model_meters_per_unit
			local node_scale = skin.node_scales and skin.node_scales[b]

			if node_scale then
				-- The node is scaled along its own axes and then turned.
				local node_right = Quaternion.right(node_rotation) * node_scale.x
				local node_forward = Quaternion.forward(node_rotation) * node_scale.y
				local node_up = Quaternion.up(node_rotation) * node_scale.z

				Unit.set_local_pose(skin.unit, skin.nodes[b], Matrix4x4(
					node_right.x, node_right.y, node_right.z,
					node_forward.x, node_forward.y, node_forward.z,
					node_up.x, node_up.y, node_up.z,
					node_position.x, node_position.y, node_position.z
				))
			else
				Unit.set_local_pose(skin.unit, skin.nodes[b], Matrix4x4.from_quaternion_position(node_rotation, node_position))
			end
		end

		-- How many meters a UT unit of the model is across the view. Effects drawn on the model use it to be as big as the model.
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

		-- The weapon is not wielded any more. Upgrading or rerolling the held weapon makes the game rebuild the inventory without
		-- announcing that the weapon was put away, and the melee weapon would stay hidden.
		if utils.wielded_template_name(fp.unit) ~= CONFIG.template then
			destroy()

			return
		end

		-- A different skin was applied to the weapon that is held, on the Illusions page. Switch to its model.
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

	-- The game shows its weapon and arms again at times of its own, after the mod's update, so they are hidden again just before the
	-- frame is drawn.
	mod.pre_render_callbacks[CONFIG.id] = function ()
		third_person.hide_staffs()

		if skin then
			local fp = local_first_person()

			if fp then
				hide_game_weapon(fp)
			end
		end
	end

	-- Development commands (/skin): print what the skin does, play an animation, or set a number of the definition.
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
	-- The skins, by id
	skins = skins,
}
