local mod = get_mod("unreal_tournament")

-- The Shock Rifle's skin: the Shock Rifle is UT2004's, in the player's own first person view and in the hand of every character. It has no
-- other look: the Weapon Skins setting is for the other weapons (see utils.is_weapon_skin_enabled).
--
-- The model, its placement, its animations, the bob and the third person are weapon_skin.lua's. This file is what is the Shock Rifle's own:
-- the chamber, the shots, the beam, the ball, the explosion and the combo. The gameplay is shock_rifle.lua's: this only draws it, and is told
-- what happens through the hook tables of hooks.lua.
--
-- The animations are UT's (Pickup, Idle, Fire, AltFire). The chamber's gel flows as UT's does (the rotation, the stretch, the pan and the
-- colour of ShockPowerShader, in the chamber's shader graph), and its glow comes back after a shot as the time to the next one goes
-- (ShockRifle.RenderOverlays). The game's own effects of the staff (the fireball, its explosion, the beam's trail) are not made.
--
-- The assets were made with unreal_tournament/tools/asset_conversion.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local animations = mod:dofile("scripts/mods/unreal_tournament/shock_rifle_skin_animations")
local fx = mod:dofile("scripts/mods/unreal_tournament/shock_rifle_skin_effects")

local TEMPLATE_NAME = "staff_blast_beam_template_1"
local SETTING_ID = "shock_rifle"

local CONFIG = {
	-- The chamber is a shader graph that makes the flowing gel itself (tools/asset_conversion/make_chamber_material.py). This is how bright it
	-- is when its glow is all there: it lights itself, as UT's shader uses its diffuse as its self illumination.
	chamber_intensity = 1,
	-- The color of the overcharge bar between its thresholds (ShockControl's color, R192 G0 B255, the liquid's; the game's is orange)
	overcharge_bar_color = { 192, 0, 255 },
	shot_flash = 0.9, -- how much brighter the liquid is just after a shot, times how bright it is (it has settled by the next shot)
	vent_pulse_speed = 14, -- radians per second, of the liquid's brightness while the heat is vented
	vent_pulse_swing = 0.3, -- how much brighter and dimmer than it is, times that
	-- Overheating (the game's overcharge explosion, which lasts a few seconds before it goes off): the liquid pulses fast between its
	-- brightness and brighter, and the model is held sideways (the alt_pose_* of the definition below)
	overheat_pulse_speed = 45, -- radians per second
	overheat_brightness_min = 1, -- times how bright it is
	overheat_brightness_max = 2.2,
	alt_pose_speed = 6, -- how fast the model moves to the sideways pose and back, per second
	-- Inspecting (UT2004 has no animation for it): the rifle is brought in and turned to show its side, and sways slowly while the key is held
	inspect_pose_speed = 5, -- how fast the model moves to the pose and back, per second
	inspect_sway = 5, -- degrees of yaw each way
	inspect_sway_speed = 1.8, -- radians per second
	projectile_sound_seconds = 1.795, -- how long the ball's sound (ShockRifleProjectile) is
	-- How fast each shot's animation plays (WeaponFire.FireAnimRate: ShockProjFire says 1.5, ShockBeamFire leaves the default 1)
	fire_animation_rates = {
		Fire = 1,
		AltFire = 1.5,
	},
}

local skin_api

-- The balls that are flying (every player's, as this machine sees them). What makes up a ball is made as it goes, see shock_rifle_skin_effects.
local balls = {}

-- Every frame: the chamber's glow
local function update_chamber(skin, dt)
	-- In UT the chamber has no glow after a shot and gets it back as the time to the next shot goes. Here the liquid flashes brighter at the
	-- shot and settles back as the time to the next one goes: it never goes away.
	local since_shot = math.clamp((skin.cooldown_end - Managers.time:time("game")) / skin.cooldown, 0, 1)
	local brightness = 1 + CONFIG.shot_flash * since_shot * since_shot

	-- It also pulses while the heat is vented
	if skin.venting then
		skin.vent_time = skin.vent_time + dt
		brightness = brightness * (1 + CONFIG.vent_pulse_swing * math.sin(skin.vent_time * CONFIG.vent_pulse_speed))
	end

	local first_person_extension = skin_api.local_first_person()
	local status_extension = first_person_extension and ScriptUnit.has_extension(first_person_extension.unit, "status_system")
	local overheating = status_extension ~= nil and status_extension:is_overcharge_exploding()

	-- The model goes to the sideways pose while it overheats, and comes back after
	skin.alt_pose = (skin.alt_pose or 0) + ((overheating and 1 or 0) - (skin.alt_pose or 0)) * math.min(1, CONFIG.alt_pose_speed * dt)

	-- The inspect pose, and the sway the rifle is turned with in it
	skin.inspect_pose = (skin.inspect_pose or 0) + ((skin.inspecting and 1 or 0) - (skin.inspect_pose or 0)) * math.min(1, CONFIG.inspect_pose_speed * dt)
	skin.inspect_time = skin.inspecting and (skin.inspect_time or 0) + dt or 0
	skin.extra_yaw = skin.inspect_pose * CONFIG.inspect_sway * math.sin(skin.inspect_time * CONFIG.inspect_sway_speed)

	if overheating then
		skin.overheat_time = (skin.overheat_time or 0) + dt

		local pulse = 0.5 + 0.5 * math.sin(skin.overheat_time * CONFIG.overheat_pulse_speed)

		-- As bright as it gets, however long it has been since the last shot
		brightness = CONFIG.overheat_brightness_min + (CONFIG.overheat_brightness_max - CONFIG.overheat_brightness_min) * pulse
	else
		skin.overheat_time = 0
	end

	local material = Mesh.material(Unit.mesh(skin.unit, "g_shock_1"), "m_power")

	Material.set_scalar(material, "intensity", CONFIG.chamber_intensity)
	Material.set_scalar(material, "brightness", brightness)
end

local function update_balls(dt)
	for i = #balls, 1, -1 do
		local ball = balls[i]

		-- The ball's sound is a loop in UT: it is played again as it ends, from where the ball is
		ball.sound_time = (ball.sound_time or 0) - dt

		if ball.sound_time <= 0 then
			local position = ball.follow()

			if position then
				skin_api.play_sound_at("ut_shock_projectile_3d", position)

				ball.sound_time = CONFIG.projectile_sound_seconds
			end
		end

		if not fx.update_ball(ball, dt) then
			table.remove(balls, i)
		end
	end
end

skin_api = mod.weapon_skin.new({
	id = SETTING_ID,
	name = "shock",
	template = TEMPLATE_NAME,
	unit_name = "units/ut/shock_rifle",
	animations = {
		bones = {
			"root",
		},
		animations = animations,
	},
	muzzle_node = "tip",
	-- The model was converted at this many meters per UT unit (tools/asset_conversion/psk2bsi.py). The distance scale is how many meters of
	-- forward a UT unit of it is in the view.
	model_meters_per_unit = 0.0125,
	meters_per_unit = 0.01,
	-- From ShockRifle.uc. The (horizontal) field of view UT draws the weapon with is fitted to a screenshot of UT2004, with small weapons
	-- off: the model's features land within about 10 pixels of it.
	display_fov = 70,
	field_of_view = math.rad(86.5),
	draw_scale = 0.7,
	offset_forward = 4,
	offset_right = 8,
	offset_up = -2,
	pivot_pitch = -1000 / 65536 * 360, -- PlayerViewPivot, degrees (negative is down)
	-- Weapon bob (Pawn.CheckBob and Pawn.WeaponBob): the sway and its speed both follow the player's speed, as in UT (there is none when
	-- standing still). Bob is Pawn.Bob, 0.01 at most there, which is too much in this game's view: a third of it is used. The damping is
	-- ShockRifle.BobDamping.
	bob = 0.0035,
	bob_damping = 1.8,
	-- Held sideways while it overheats (a guess: /skin shock_rifle set alt_pose_roll <degrees>, and the others, to try)
	alt_pose_roll = 35,
	alt_pose_right = 4,
	alt_pose_forward = 0,
	alt_pose_up = -3,
	-- Held across the view, level, with the muzzle to the left, as the game's own weapons are inspected, which shows its left side (a guess:
	-- /skin shock_rifle set inspect_pose_yaw <degrees>, and the others, to try). It is held further away, with its top turned to the view:
	-- from below it shows its underside, which UT's model has no faces for.
	inspect_pose_right = -2,
	inspect_pose_forward = 6,
	inspect_pose_up = 2,
	inspect_pose_roll = -20,
	inspect_pose_pitch = 6,
	inspect_pose_yaw = 65,
	third_person = {
		id = SETTING_ID,
		template = TEMPLATE_NAME,
		unit_name = "units/ut/shock_pickup",
		hand_node = "j_rightweaponattach",
		meters_per_unit = 0.011,
		scale = 0.65,
		grip_right = 0,
		grip_forward = -22,
		grip_up = 6,
		yaw = 0,
		pitch = 0,
		roll = 0,
		muzzle_right = 0,
		muzzle_forward = 51.7,
		muzzle_up = 10,
	},
	on_create = function (skin)
		skin.cooldown = 1
		skin.cooldown_end = 0

		skin_api.play_sound("ut_shock_select")
	end,
	on_update = update_chamber,
	on_update_always = update_balls,
	on_level_exit = function ()
		table.clear(balls)
	end,
})

local third_person = skin_api.third_person

-- The shots: the animation plays as the shot's action starts, and the glow comes back by the time the next shot can be fired
local function shot(action, new_action, animation_name)
	local skin = skin_api.state()

	if not skin or not utils.is_local_player_unit(action.owner_unit) then
		return
	end

	skin.cooldown = new_action.total_time
	skin.cooldown_end = Managers.time:time("game") + new_action.total_time

	skin_api.play(animation_name, skin_api.animation_duration(animation_name) / CONFIG.fire_animation_rates[animation_name])

	-- The flash follows the model's muzzle: the skin follows the first person unit. In a third person view it is the mesh in the character's hand.
	local owner_unit = action.owner_unit
	local in_third_person = third_person.shows_weapon(owner_unit)
	local function follow()
		if in_third_person then
			return third_person.muzzle_position(owner_unit)
		end

		return skin_api.state() == skin and skin_api.muzzle_position() or nil
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

-- The beam, of the player who plays (from the model's muzzle) and of the others (from the mesh in the hand)
mod.shock_beam_callbacks.skin = function (owner_unit, start_position, end_position, hit_normal)
	local is_local = utils.is_local_player_unit(owner_unit)

	if is_local and skin_api.state() and not third_person.shows_weapon(owner_unit) then
		start_position = skin_api.muzzle_position() or start_position
	else
		-- The character is seen holding the mesh: the beam starts at the end of its barrel. The shot's flash is made here for the others;
		-- the player's own is made when the shot starts.
		start_position = third_person.muzzle_position(owner_unit) or start_position

		if not is_local then
			fx.beam_muzzle_flash(function ()
				return third_person.muzzle_position(owner_unit)
			end, third_person.meters_per_unit)
		end
	end

	if not is_local then
		-- (the player's own shot is heard from the head, see take_over_sound)
		skin_api.play_sound_at("ut_shock_fire_3d", start_position)
	end

	fx.beam(start_position, end_position, hit_normal)
end

-- The ball (every player's, on every machine). The game's own fireball is not started: its effects are made by the flow events that the game
-- sends the unit as the projectile is made, and those are filtered out. UT's ball is drawn where the projectile is.
local FIREBALL_FLOW_EVENTS = {
	lua_projectile_init = true,
	lua_trail = true,
	vfx_critical_strike = true,
}

mod.init_flow_event_filters.shock_ball = function (event_name)
	return skin_api.enabled() and FIREBALL_FLOW_EVENTS[event_name] == true
end

mod.init_callbacks.shock_ball = function (projectile)
	if not skin_api.enabled() then
		return
	end

	local unit = projectile._projectile_unit

	Unit.set_unit_visibility(unit, false)

	local owner_unit = projectile._owner_unit

	if not utils.is_local_player_unit(owner_unit) then
		skin_api.play_sound_at("ut_shock_alt_fire_3d", Unit.world_position(unit, 0))
		fx.ball_muzzle_flash(function ()
			return third_person.muzzle_position(owner_unit)
		end, third_person.meters_per_unit)
	end

	balls[#balls + 1] = fx.new_ball(function ()
		if Unit.alive(unit) and not projectile._stop_impacts then
			return Unit.world_position(unit, 0)
		end
	end)

	skin_api.debug("ball")
end

-- The player's own shots, which the game plays for the weapon and tells the others about (the others hear them from the shot, see
-- shock_beam_callbacks and init_callbacks): the staff's sounds are not played, UT's are, from the head
skin_api.take_over_sound("weapon_staff_fire_beam_end_shot", "ut_shock_fire")
skin_api.take_over_sound("player_combat_weapon_staff_fireball_fire", "ut_shock_alt_fire")

-- The staff's fireball flash is in its animation, so while the skin is on, the ball's shot animation is not played on the player's own first
-- person unit (the skin's model plays UT's, with its own flash). The same goes for the animation of venting the heat: it has the staff's
-- puff of steam in it, which comes off where the game's staff is held, not off the skin's model.
mod.first_person_animation_filters[TEMPLATE_NAME] = function (event)
	return skin_api.enabled() and (event == "attack_shoot_fireball" or event == "cooldown_start")
end

mod.skin_explosion_callbacks.ut_shock_ball_explosion = function (world, position)
	if skin_api.enabled() then
		fx.ball_explosion(position)
		skin_api.play_sound_at("ut_shock_explosion_3d", position)
	end
end

mod.skin_explosion_callbacks.ut_shock_combo_explosion = function (world, position)
	if skin_api.enabled() then
		fx.combo(position)
		skin_api.play_sound_at("ut_shock_combo_3d", position)

		skin_api.debug("combo")
	end
end

-- Inspecting is the game's own action, held with the key: the rifle is turned to show its side as long as it lasts
mod.inspect_callbacks.shock_skin = function (action, started)
	local skin = skin_api.state()

	if skin and utils.is_local_player_unit(action.owner_unit) then
		skin.inspecting = started
	end
end

-- Venting the heat is the game's own action (a UT2004 Shock Rifle has none): the chamber's glow pulses while it lasts
mod.charge_start_callbacks.shock_skin = function (action, new_action)
	local skin = skin_api.state()

	if skin and new_action.vent_overcharge and utils.is_local_player_unit(action.owner_unit) then
		skin.venting = true
		skin.vent_time = 0

		skin_api.debug("vent")
	end
end

mod.charge_finish_callbacks.shock_skin = function (action, reason)
	local skin = skin_api.state()

	if skin and action.current_action and action.current_action.vent_overcharge and utils.is_local_player_unit(action.owner_unit) then
		skin.venting = false

		skin_api.debug("vent over (%s)", reason)
	end
end

-- The overcharge bar is orange between its thresholds for every Sienna: with the Shock Rifle it is purple, like its liquid. The bar's colors
-- are the game's own, set every frame after it has worked out the fraction, so this follows it.
mod:hook_safe(OverchargeBarUI, "set_charge_bar_fraction", function (self, player, _, min_threshold_fraction, max_threshold_fraction)
	if not utils.is_weapon_enabled(SETTING_ID) or utils.wielded_template_name(player.player_unit) ~= TEMPLATE_NAME then
		return
	end

	local fraction = self.charge_bar.content.internal_gradient_threshold

	if fraction <= min_threshold_fraction or fraction > max_threshold_fraction then
		return
	end

	local style = self.charge_bar.style
	local color = CONFIG.overcharge_bar_color

	for i = 1, 3 do
		style.bar_1.color[i + 1] = color[i]
		style.icon.color[i + 1] = color[i]
	end
end)
