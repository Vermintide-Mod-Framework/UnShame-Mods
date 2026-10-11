local mod = get_mod("unreal_tournament")

-- Shock Rifle skin (the Weapon Skins setting): the Shock Rifle is UT2004's, in the player's own first person view. The
-- gameplay is shock_rifle.lua's, this only draws it differently, and is told what happens through the hook tables of hooks.lua.
--
-- The game's weapon (the Beam Staff) and arms are hidden, and UT2004's model (NewWeapons2004.ShockRifle) is linked to the
-- first person unit, as the game's own weapons are. The model is drawn where UT2004 draws it: the mesh is moved by the root
-- bone of the animation it plays, drawn at DrawScale, tilted by PlayerViewPivot, at PlayerViewOffset scaled by
-- 90 / DisplayFOV (ShockRifle.uc, Pawn.CalcDrawOffset), and seen with the field of view UT2004 draws weapons with. A point
-- at (right, forward, up) in UT's view lands in the same place of the screen in this game's view, with its own field of
-- view, at (c * right, forward, c * up) * k, where c is the ratio of the tangents of the half field of views across the screen
-- and k is any distance scale: the gun is wider and taller across than it is long.
--
-- The animations are UT's (Pickup, Idle, Fire, AltFire), played with the timing of the game's: the pickup lasts as long as the
-- game's wield cooldown, a shot plays when the action of it starts. The game has no animation of putting a weapon down, so
-- the model is gone as the weapon is put away. The chamber is UT's: the gel flows (a flipbook of the texture, the pan, the
-- stretch and the colour of ShockPowerShader), and the glow comes back after a shot as long as it is until the next one
-- (ShockRifle.RenderOverlays).
--
-- The assets were made with unreal_tournament/tools/asset_conversion.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local animations = mod:dofile("scripts/mods/unreal_tournament/shock_rifle_skin_animations")
local fx = mod:dofile("scripts/mods/unreal_tournament/shock_rifle_skin_effects")
local third_person = mod:dofile("scripts/mods/unreal_tournament/shock_rifle_skin_third_person")

local TEMPLATE_NAME = "staff_blast_beam_template_1"
local SETTING_ID = "shock_rifle"
local HIDE_REASON = "ut_shock_rifle_skin"

local CONFIG = {
	unit_name = "units/ut/shock_rifle",
	-- The field of view UT draws the weapon with, horizontal, fitted to a screenshot of UT2004 (the features of the model land
	-- within about 10 pixels of it) with small weapons off
	field_of_view = math.rad(86.5),
	-- ShockRifle.uc
	draw_scale = 0.7,
	view_offset_forward = 4 * 90 / 70, -- PlayerViewOffset * 90 / DisplayFOV, in UT units
	view_offset_right = 8 * 90 / 70,
	view_offset_up = -2 * 90 / 70,
	view_pivot_pitch = -1000 / 65536 * 360, -- PlayerViewPivot, degrees (negative is down)
	-- The model was converted at this many meters per UT unit (tools/asset_conversion/psk2bsi.py), the distance scale is
	-- how many meters of forward are a UT unit of it in the view
	model_meters_per_unit = 0.0125,
	meters_per_unit = 0.01,
	-- Seconds in which one animation blends into the next
	blend_time = 0.1,
	-- The chamber: the frames of the gel (tools/asset_conversion/make_anim_assets.py), how long they take to go round, and the
	-- opacity of the chamber when the glow is all there
	gel_material_format = "units/ut/shock_rifle_power_%02d",
	gel_frame_count = 60,
	gel_loop_seconds = 10,
	chamber_opacity = 0.6,
	vent_pulse_speed = 14, -- radians per second, of the glow while the heat is vented
	-- Weapon bob (UT2004 Pawn.CheckBob and Pawn.WeaponBob, in UT units): both the sway and how fast it goes follow the speed
	-- of the player, as they do in UT (it is none when standing still). Bob is Pawn.Bob, which is 0.01 at most there: that is
	-- too much in this game's view, so a third of it is used. The damping is ShockRifle.BobDamping, and the speed a player
	-- runs at is taken to be UT's (GroundSpeed) at this game's own
	bob = 0.0035,
	bob_damping = 1.8,
	projectile_sound_seconds = 1.795, -- how long the sound of the ball (ShockRifleProjectile) is
	bob_smoothing = 10, -- per second, how fast the speed the bob follows catches up with the player's
	ut_ground_speed = 440,
}

-- The state of the skin that is shown. Nothing when none is.
--   world, unit: the model
--   animation, time, speed: what is playing (the time is of the animation as it is in the file, speed makes it last as long
--       as it is to), blend_from, blend_left: the pose it blends from
--   cooldown_end, cooldown: when the glow is all back, and how long it took to come back
--   venting, vent_time: the heat is being vented
--   tip_node: the node of the model where the muzzle is, unit_scale: how many meters a UT unit of the model is in the world
--   gel_time, gel_frame, bob_speed, bob_time, walk_right, walk_up
local skin
local debug_enabled = false

-- The balls of the Shock Rifle that are flying (of every player's, as this machine sees them): what makes up the ball of
-- UT is made as it goes. { effect = the ball of shock_rifle_skin_effects }
local balls = {}

-- What the game's own effects and sounds of the explosions are taken away for while the skin is on (the skin draws and plays
-- them, see skin_explosion_callbacks): { template name, key of the explosion, what it was }
local explosion_overrides = {
	{ "ut_shock_ball_explosion", "effect_name" },
	{ "ut_shock_ball_explosion", "sound_event_name" },
	{ "ut_shock_combo_explosion", "sound_event_name" },
}

local function debug(text, ...)
	if debug_enabled then
		mod:echo("shock skin: " .. text, ...)
	end
end

-- Sounds (the events are in the bank of tools/asset_conversion/make_bank.py): from the head of the player, or from a place
local function play_sound(event)
	WwiseWorld.trigger_event(Managers.world:wwise_world(Managers.world:world("level_world")), event)
end

local function play_sound_at(event, position)
	WwiseUtils.trigger_position_event(Managers.world:world("level_world"), event, position)
end

local function local_first_person()
	local player = Managers.player and Managers.player:local_player()
	local owner = player and player.player_unit

	return owner and Unit.alive(owner) and ScriptUnit.has_extension(owner, "first_person_system")
end

local function item_template_name(item_data)
	return item_data and BackendUtils.get_item_template(item_data).name
end

-- Where the muzzle of the model is (the unit has to be alive: the skin goes before it)
local function muzzle_position()
	return skin and Unit.alive(skin.unit) and Unit.world_position(skin.unit, skin.tip_node) or nil
end

-- How long the game takes to wield a weapon: nothing can be done with the weapon for that long
local function wield_time()
	return rawget(Weapons, TEMPLATE_NAME).actions.action_wield.default.wield_cooldown
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

-- Animations

-- A pose: the rotation of the mesh (x, y, z, w) and its move (right, forward, up in UT units)
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

	for i = 1, 7 do
		pose[i] = first[i] + (second[i] - first[i]) * fraction
	end

	return pose
end

-- (the move is blended as it is, the rotations go the short way round and are made whole again)
local function blend_poses(from, to, fraction)
	local sign = (from[1] * to[1] + from[2] * to[2] + from[3] * to[3] + from[4] * to[4]) < 0 and -1 or 1
	local pose = {}

	for i = 1, 7 do
		pose[i] = from[i] + ((i <= 4 and sign or 1) * to[i] - from[i]) * fraction
	end

	local length = math.sqrt(pose[1] * pose[1] + pose[2] * pose[2] + pose[3] * pose[3] + pose[4] * pose[4])

	for i = 1, 4 do
		pose[i] = pose[i] / length
	end

	return pose
end

local function animation_duration(name)
	return #animations[name].frames / animations[name].rate
end

local function current_pose()
	local pose = sample(skin.animation, skin.time, skin.animation == "Idle")

	if skin.blend_from and skin.blend_left > 0 then
		pose = blend_poses(skin.blend_from, pose, 1 - skin.blend_left / CONFIG.blend_time)
	end

	return pose
end

-- Plays an animation, from the pose of the one that is playing; for a time of its own if one is given
local function play(name, duration)
	debug("%s", name)

	if skin.animation then
		skin.blend_from = current_pose()
		skin.blend_left = CONFIG.blend_time
	end

	skin.animation = name
	skin.time = 0
	skin.speed = duration and animation_duration(name) / duration or 1
end

-- The skin

local function destroy(first_person_is_going)
	if not skin then
		return
	end

	local finished = skin

	skin = nil

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

	debug("gone")
end

local place

local function create(fp)
	destroy()

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

	skin = {
		bob_speed = 0,
		bob_time = 0,
		cooldown = 1,
		cooldown_end = 0,
		gel_time = 0,
		tip_node = Unit.node(unit, "tip"),
		unit_scale = CONFIG.draw_scale * CONFIG.meters_per_unit,
		walk_right = 0,
		walk_up = 0,
		world = world,
		unit = unit,
	}

	-- (the game has just shown its own weapon, which is the one that is wielded now)
	fp:hide_weapons(HIDE_REASON, true)
	hide_game_weapon(fp)
	play("Pickup", wield_time())
	play_sound("ut_shock_select")
	place(fp)
	Unit.set_unit_visibility(unit, game_shows_weapon(fp))
end

-- The game's own effect of the explosion of the ball is taken away while the skin is on, and given back when it is off
local function apply_template_overrides()
	local enabled = utils.is_weapon_skin_enabled(SETTING_ID)

	for _, override in ipairs(explosion_overrides) do
		local explosion = ExplosionTemplates[override[1]].explosion
		local key = override[2]

		if enabled and explosion[key] then
			override[3] = explosion[key]
			explosion[key] = nil
		elseif not enabled and override[3] then
			explosion[key] = override[3]
			override[3] = nil
		end
	end
end

-- Made when the setting or the weapon is switched, and when what is wielded is the Shock Rifle
local function refresh()
	local fp = local_first_person()

	apply_template_overrides()

	if not utils.is_weapon_skin_enabled(SETTING_ID) or not fp then
		destroy()

		return
	end

	if not skin and utils.wielded_template_name(fp.unit) == TEMPLATE_NAME then
		create(fp)
	end
end

mod.setting_changed_callbacks[#mod.setting_changed_callbacks + 1] = function (changed_setting_id)
	if changed_setting_id == "weapon_skins" or changed_setting_id == SETTING_ID or changed_setting_id == "ut_weapons" then
		refresh()
	end
end

mod.enabled_callbacks[#mod.enabled_callbacks + 1] = refresh

-- (the mod is switched off or unloaded: the setting reads as it is, the game's effect is given back)
local function give_back()
	third_person.clear()
	destroy()

	for _, override in ipairs(explosion_overrides) do
		if override[3] then
			ExplosionTemplates[override[1]].explosion[override[2]] = override[3]
			override[3] = nil
		end
	end
end

mod.disabled_callbacks[#mod.disabled_callbacks + 1] = give_back
mod.unload_callbacks[#mod.unload_callbacks + 1] = give_back
mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(balls)
	third_person.clear()
	destroy(true)
end

mod.first_person_destroy_callbacks.shock_skin = function (first_person_extension)
	if skin and utils.is_local_player_unit(first_person_extension.unit) then
		destroy(true)
	end
end

-- The weapon that is wielded
mod.wield_callbacks.shock_skin = function (inventory_extension, equipment, slot_data)
	if slot_data and item_template_name(slot_data.item_data) == TEMPLATE_NAME and utils.is_weapon_skin_enabled(SETTING_ID) then
		create(inventory_extension.first_person_extension)
	end
end

-- The weapon that is put away: the model is gone, the arms are the game's again for the weapon that comes next
mod.unwield_callbacks.shock_skin = function (inventory_extension, equipment, previous_item_data)
	if skin and item_template_name(previous_item_data) == TEMPLATE_NAME then
		destroy()
	end
end

-- The shots (the animation plays as the action of the shot starts, and the glow comes back by the time the next one can
-- be fired)
local function shot(action, new_action, animation_name)
	if not skin or not utils.is_local_player_unit(action.owner_unit) then
		return
	end

	skin.cooldown = new_action.total_time
	skin.cooldown_end = Managers.time:time("game") + new_action.total_time

	play(animation_name)

	-- (the flash follows the muzzle of the model: it is the skin that follows the first person unit; in a third person view it
	-- is the mesh in the character's hand)
	local owner_unit = action.owner_unit
	local in_third_person = third_person.shows_weapon(owner_unit)
	local current = skin
	local function follow()
		if in_third_person then
			return third_person.muzzle_position(owner_unit)
		end

		return skin == current and muzzle_position() or nil
	end
	local scale = in_third_person and third_person.meters_per_unit or skin.unit_scale

	if animation_name == "Fire" then
		fx.beam_muzzle_flash(follow, scale)
	else
		fx.ball_muzzle_flash(follow, scale)
	end
end

mod.handgun_start_callbacks.shock_skin = function (action, new_action)
	if new_action.ut_shock_beam then
		shot(action, new_action, "Fire")
	end
end

mod.charged_projectile_start_callbacks.shock_skin = function (action, new_action)
	if new_action.ut_shock_ball then
		shot(action, new_action, "AltFire")
	end
end

-- The beam, of the player who plays (from the muzzle of the model) and of the others (from the staff's, until their model is
-- drawn too)
mod.shock_beam_callbacks.skin = function (owner_unit, start_position, end_position, hit_normal)
	local is_local = utils.is_local_player_unit(owner_unit)

	if is_local and skin and not third_person.shows_weapon(owner_unit) then
		start_position = muzzle_position() or start_position
	else
		-- (the character is seen holding the mesh: the beam starts at the end of its barrel, and the flash of the shot is made
		-- here for the others, the player's own is made when the shot starts)
		local muzzle = third_person.muzzle_position(owner_unit)

		start_position = muzzle or start_position

		if not is_local then
			fx.beam_muzzle_flash(function ()
				return third_person.muzzle_position(owner_unit)
			end, third_person.meters_per_unit)
		end
	end

	if not is_local then
		-- (the shot of the player is heard from the head, see hud_sound_callbacks)
		play_sound_at("ut_shock_fire_3d", start_position)
	end

	fx.beam(start_position, end_position, hit_normal)
end

-- The ball (every player's, on every machine): the game's own fireball is not started (the unit's effects are made by the
-- events the game sends it as the projectile is made), and the ball of UT is drawn where it is
local FIREBALL_FLOW_EVENTS = {
	lua_projectile_init = true,
	lua_trail = true,
	vfx_critical_strike = true,
}

mod.init_flow_event_filters.shock_ball = function (event_name)
	return utils.is_weapon_skin_enabled(SETTING_ID) and FIREBALL_FLOW_EVENTS[event_name] == true
end

mod.init_callbacks.shock_ball = function (projectile)
	if not utils.is_weapon_skin_enabled(SETTING_ID) then
		return
	end

	local unit = projectile._projectile_unit

	Unit.set_unit_visibility(unit, false)

	local owner_unit = projectile._owner_unit

	if not utils.is_local_player_unit(owner_unit) then
		play_sound_at("ut_shock_alt_fire_3d", Unit.world_position(unit, 0))
		fx.ball_muzzle_flash(function ()
			return third_person.muzzle_position(owner_unit)
		end, third_person.meters_per_unit)
	end

	balls[#balls + 1] = fx.new_ball(function ()
		if Unit.alive(unit) and not projectile._stop_impacts then
			return Unit.world_position(unit, 0)
		end
	end)

	debug("ball")
end

-- The shots of the player, which the game plays for the weapon and tells the others of (they hear them from the shot, see
-- shock_beam_callbacks and init_callbacks): the sounds of the staff are not played, the ones of UT are, from the head
local function take_over_shot_sound(event)
	return function (first_person_extension)
		if not utils.is_weapon_skin_enabled(SETTING_ID) or not utils.is_local_player_unit(first_person_extension.unit) then
			return false
		end

		if utils.wielded_template_name(first_person_extension.unit) ~= TEMPLATE_NAME then
			return false
		end

		play_sound(event)

		return true
	end
end

mod.hud_sound_callbacks.weapon_staff_fire_beam_end_shot = take_over_shot_sound("ut_shock_fire")
mod.hud_sound_callbacks.player_combat_weapon_staff_fireball_fire = take_over_shot_sound("ut_shock_alt_fire")

mod.skin_explosion_callbacks.ut_shock_ball_explosion = function (world, position)
	if utils.is_weapon_skin_enabled(SETTING_ID) then
		fx.ball_explosion(position)
		play_sound_at("ut_shock_explosion_3d", position)
	end
end

mod.skin_explosion_callbacks.ut_shock_combo_explosion = function (world, position)
	if utils.is_weapon_skin_enabled(SETTING_ID) then
		fx.combo(position)
		play_sound_at("ut_shock_combo_3d", position)

		debug("combo")
	end
end

-- Venting the heat is the game's own action, a UT2004 Shock Rifle has none: the glow of the chamber pulses while it lasts
mod.charge_start_callbacks.shock_skin = function (action, new_action)
	if skin and new_action.vent_overcharge and utils.is_local_player_unit(action.owner_unit) then
		skin.venting = true
		skin.vent_time = 0

		debug("vent")
	end
end

mod.charge_finish_callbacks.shock_skin = function (action, reason)
	if skin and action.current_action and action.current_action.vent_overcharge and utils.is_local_player_unit(action.owner_unit) then
		skin.venting = false

		debug("vent over (%s)", reason)
	end
end

-- Every frame

-- The chamber: the frame of the gel, and the glow
local function update_chamber(dt)
	skin.gel_time = (skin.gel_time + dt) % CONFIG.gel_loop_seconds

	local frame = math.floor(skin.gel_time / CONFIG.gel_loop_seconds * CONFIG.gel_frame_count) % CONFIG.gel_frame_count

	if frame ~= skin.gel_frame then
		skin.gel_frame = frame

		Unit.set_material(skin.unit, "m_power", string.format(CONFIG.gel_material_format, frame))
	end

	-- (a shock rifle in UT hasn't the glow of its chamber after it has fired, and gets it back as the time to the next shot goes)
	local charge = 1 - math.clamp((skin.cooldown_end - Managers.time:time("game")) / skin.cooldown, 0, 1)

	if skin.venting then
		skin.vent_time = skin.vent_time + dt
		charge = charge * (0.55 + 0.45 * math.sin(skin.vent_time * CONFIG.vent_pulse_speed))
	end

	Material.set_scalar(Mesh.material(Unit.mesh(skin.unit, "g_shock_1"), "m_power"), "opacity", CONFIG.chamber_opacity * charge)
end

-- Weapon bob (Pawn.CheckBob, Pawn.WeaponBob), in UT units: (right, up)
local function update_bob(owner_unit, dt)
	local locomotion_extension = ScriptUnit.extension(owner_unit, "locomotion_system")
	local move_speed = PlayerUnitMovementSettings.get_movement_settings_table(owner_unit).move_speed
	local speed = Vector3.length(Vector3.flat(locomotion_extension:current_velocity())) / move_speed * CONFIG.ut_ground_speed

	-- (the speed the bob follows is smoothed, and none in the air: the velocity this game gives for a frame jumps about when the
	-- player steps, lands or is pushed, and the phase of the sway is kept, so that the model doesn't jump with them)
	local target_speed = locomotion_extension:is_on_ground() and speed or 0

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

	local duration = animation_duration(skin.animation)

	if skin.animation == "Idle" then
		skin.time = skin.time % duration
	elseif skin.time >= duration then
		play("Idle")
	end
end

-- Where the model is, and how it is turned and scaled, in the first person unit's root
function place(fp)
	local resolution_width, resolution_height = Application.resolution()
	local tangent_vertical = math.tan(Camera.vertical_fov(fp:camera()) / 2)
	local across = tangent_vertical * resolution_width / resolution_height / math.tan(CONFIG.field_of_view / 2)
	local forward_scale = CONFIG.meters_per_unit
	local across_scale = forward_scale * across
	local pose = current_pose()
	local pitch = math.rad(CONFIG.view_pivot_pitch)

	-- The move of the animation is the mesh's, tilted by the pivot as everything of the mesh is (about the right axis)
	local tilted_forward = pose[6] * math.cos(pitch) - pose[7] * math.sin(pitch)
	local tilted_up = pose[6] * math.sin(pitch) + pose[7] * math.cos(pitch)
	local bob_right = CONFIG.bob_damping * skin.walk_right
	local bob_up = (0.45 + 0.55 * CONFIG.bob_damping) * skin.walk_up
	local position = Vector3(
		across_scale * (CONFIG.draw_scale * pose[5] + CONFIG.view_offset_right + bob_right),
		forward_scale * (CONFIG.draw_scale * tilted_forward + CONFIG.view_offset_forward),
		across_scale * (CONFIG.draw_scale * tilted_up + CONFIG.view_offset_up + bob_up)
	)
	local size = CONFIG.draw_scale / CONFIG.model_meters_per_unit
	local rotation = Quaternion.multiply(Quaternion.axis_angle(Vector3(1, 0, 0), pitch), Quaternion.from_elements(pose[1], pose[2], pose[3], pose[4]))

	Unit.set_local_position(skin.unit, 0, position)
	Unit.set_local_rotation(skin.unit, 0, rotation)
	Unit.set_local_scale(skin.unit, 0, Vector3(size * across_scale, size * forward_scale, size * across_scale))
	World.update_unit(skin.world, skin.unit)

	-- (a UT unit of the model, across: what is drawn on it is as big as the model is)
	skin.unit_scale = CONFIG.draw_scale * across_scale
end

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	for i = #balls, 1, -1 do
		local ball = balls[i]

		-- (the sound of the ball is a loop in UT: it is played again as it ends, from where the ball is)
		ball.sound_time = (ball.sound_time or 0) - dt

		if ball.sound_time <= 0 then
			local position = ball.follow()

			if position then
				play_sound_at("ut_shock_projectile_3d", position)

				ball.sound_time = CONFIG.projectile_sound_seconds
			end
		end

		if not fx.update_ball(ball, dt) then
			table.remove(balls, i)
		end
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

	update_animation(dt)
	update_bob(fp.unit, dt)
	update_chamber(dt)
	Unit.set_unit_visibility(skin.unit, game_shows_weapon(fp))
	place(fp)
end

-- (the game shows its weapon and its arms again at times of its own, after the mod's update)
mod.pre_render_callbacks.shock_skin = function ()
	third_person.hide_staffs()

	if skin then
		local fp = local_first_person()

		if fp then
			hide_game_weapon(fp)
		end
	end
end

-- Development: /shockskin debug prints what the skin does, /shockskin play <Pickup|Idle|Fire|AltFire> plays an animation
mod:command("shockskin", "debug | play <animation> | 3p <forward> <right> <up> <yaw> <pitch> <roll> - the Shock Rifle skin", function (command, name, ...)
	if command == "debug" then
		debug_enabled = not debug_enabled

		mod:echo("shock skin: debug %s", debug_enabled and "on" or "off")
	elseif command == "play" and skin and animations[name] then
		play(name)
	elseif command == "3p" then
		third_person.tune(name, ...)
	end
end)
