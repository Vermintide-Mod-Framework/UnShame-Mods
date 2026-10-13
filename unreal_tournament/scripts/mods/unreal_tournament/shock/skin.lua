local mod = get_mod("unreal_tournament")

-- Shock Rifle skin: how UT2004's Shock Rifle looks and sounds.
--
-- It has illusions (see items.lua): UT2004's model, and UT2003's old model (Weapons.ShockRifle_1st, which UT2004 still has and uses with
-- ShockRifle.bUseOldWeaponMesh). The UT2003 one is a look of this skin (see weapon_skin.lua) with its own model, placement and
-- animations. Everything else is the same.
--
-- weapon_skin.lua does the model, its placement and animations, the bob and the third person. This file does what is the Shock Rifle's
-- own: the chamber, the shots, the beam, the ball, the explosion and the combo. The gameplay is in shock_rifle.lua. This file only draws
-- it, and is told what happens through the hook tables in hooks.lua.
--
-- The chamber's gel flows as in UT (the rotation, stretch, pan and colour of ShockPowerShader, in the chamber's shader graph), and its
-- glow comes back after a shot as the time to the next one passes (ShockRifle.RenderOverlays). The game's own effects of the staff (the
-- fireball, its explosion, the beam's trail) are not made.
--
-- The assets were made with tools/asset_conversion.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local animations = mod:dofile("scripts/mods/unreal_tournament/shock/skin_animations")
local animations_2003 = mod:dofile("scripts/mods/unreal_tournament/shock/skin_animations_2003")
local fx = mod:dofile("scripts/mods/unreal_tournament/shock/skin_effects")

local TEMPLATE_NAME = mod.items.weapons.shock_rifle.template
local SETTING_ID = "shock_rifle"

local CONFIG = {
	-- The chamber is a shader graph that makes the flowing gel itself (tools/asset_conversion/make_chamber_material.py). This is how
	-- bright it is when its glow is all there. It lights itself, as UT's shader uses its diffuse as its self illumination.
	chamber_intensity = 1,
	-- The color of the overcharge bar between its thresholds. It is ShockControl's color (R192 G0 B255), the liquid's. The game's is orange.
	overcharge_bar_color = { 192, 0, 255 },
	shot_flash = 0.9, -- how much brighter the liquid is just after a shot, as a multiple of its brightness. It has settled by the next shot.
	vent_pulse_speed = 14, -- radians per second, of the liquid's brightness pulsing while the heat is vented
	vent_pulse_swing = 0.3, -- how much brighter and dimmer the liquid gets while pulsing, as a multiple of its brightness
	-- Overheating is the game's overcharge explosion, which lasts a few seconds before it goes off. During it the liquid pulses fast
	-- between its normal brightness and a brighter one, and the model is held sideways (the alt_pose_* values in the definition below).
	overheat_pulse_speed = 45, -- radians per second
	overheat_brightness_min = 1, -- as a multiple of the liquid's brightness
	overheat_brightness_max = 2.2,
	alt_pose_speed = 6, -- how fast the model moves to the sideways pose and back, per second
	-- UT2004 has no inspect animation. The rifle is brought in, turned to show its side, and sways slowly while the key is held.
	inspect_pose_speed = 5, -- how fast the model moves to the pose and back, per second
	inspect_sway = 5, -- degrees of yaw each way
	inspect_sway_speed = 1.8, -- radians per second
	projectile_sound_seconds = 1.795, -- length of the ball's sound (ShockRifleProjectile)
	-- How fast each shot's animation plays (WeaponFire.FireAnimRate). ShockProjFire says 1.5, and ShockBeamFire leaves the default 1.
	fire_animation_rates = {
		Fire = 1,
		AltFire = 1.5,
	},
}

local skin_api

-- The balls in flight, from every player, as this machine sees them. The parts of a ball are made as it flies (see skin_effects.lua).
local balls = {}

-- Updates the chamber's glow and the poses. It runs every frame.
local function update_chamber(skin, dt)
	-- In UT the chamber has no glow after a shot and gets it back as the time to the next shot passes. Here the liquid flashes
	-- brighter at the shot and settles back as the time to the next shot passes. It never goes dark.
	local since_shot = math.clamp((skin.cooldown_end - Managers.time:time("game")) / skin.cooldown, 0, 1)
	local brightness = 1 + CONFIG.shot_flash * since_shot * since_shot

	-- The liquid also pulses while the heat is vented.
	if skin.venting then
		skin.vent_time = skin.vent_time + dt
		brightness = brightness * (1 + CONFIG.vent_pulse_swing * math.sin(skin.vent_time * CONFIG.vent_pulse_speed))
	end

	local first_person_extension = skin_api.local_first_person()
	local status_extension = first_person_extension and ScriptUnit.has_extension(first_person_extension.unit, "status_system")
	local overheating = status_extension ~= nil and status_extension:is_overcharge_exploding()

	-- The model moves to the sideways pose while it overheats, and comes back afterwards.
	skin.alt_pose = (skin.alt_pose or 0) + ((overheating and 1 or 0) - (skin.alt_pose or 0)) * math.min(1, CONFIG.alt_pose_speed * dt)

	-- Moves the model towards the inspect pose and back, and sways it while it is there.
	skin.inspect_pose = (skin.inspect_pose or 0) + ((skin.inspecting and 1 or 0) - (skin.inspect_pose or 0)) * math.min(1, CONFIG.inspect_pose_speed * dt)
	skin.inspect_time = skin.inspecting and (skin.inspect_time or 0) + dt or 0
	skin.extra_yaw = skin.inspect_pose * CONFIG.inspect_sway * math.sin(skin.inspect_time * CONFIG.inspect_sway_speed)

	if overheating then
		skin.overheat_time = (skin.overheat_time or 0) + dt

		local pulse = 0.5 + 0.5 * math.sin(skin.overheat_time * CONFIG.overheat_pulse_speed)

		-- While overheating the liquid is as bright as it gets, however long ago the last shot was.
		brightness = CONFIG.overheat_brightness_min + (CONFIG.overheat_brightness_max - CONFIG.overheat_brightness_min) * pulse
	else
		skin.overheat_time = 0
	end

	-- The UT2003 model has no chamber of its own.
	if skin_api.config.chamber == false then
		return
	end

	local material = Mesh.material(Unit.mesh(skin.unit, "g_shock_1"), "m_power")

	Material.set_scalar(material, "intensity", CONFIG.chamber_intensity)
	Material.set_scalar(material, "brightness", brightness)
end

local function update_balls(dt)
	for i = #balls, 1, -1 do
		local ball = balls[i]

		-- The ball's sound is a loop in UT. It is played again each time it ends, from where the ball is.
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

-- The Instagib Shock Rifle (UT2004's SuperShockRifle) is the same rifle with a red chamber (its ShockControl color is the team's,
-- HUD.RedColor) and a red beam, coil, flash and impact (ShockBeamCoilB and the B effects).
local INSTAGIB_SKIN = "ut_shock_rifle_skin_instagib"

local THIRD_PERSON = {
	id = SETTING_ID,
	template = TEMPLATE_NAME,
	unit_name = "units/ut/shock/pickup",
	hand_node = "j_rightweaponattach",
	meters_per_unit = 0.011,
	scale = 0.65,
	grip_right = 0,
	grip_forward = -31,
	grip_up = 6,
	yaw = 0,
	pitch = 0,
	roll = 0,
	muzzle_right = 0,
	muzzle_forward = 51.7,
	muzzle_up = 10,
	-- The engine's fade near the camera does not reach the chamber's material, so the skin fades it by distance (see
	-- weapon_skin_third_person.lua).
	fade_mesh = "g_pickup_1",
	fade_material = "m_power",
}

local INSTAGIB_THIRD_PERSON = {}

for key, value in pairs(THIRD_PERSON) do
	INSTAGIB_THIRD_PERSON[key] = value
end

INSTAGIB_THIRD_PERSON.materials = {
	m_power = "units/ut/shock/shock_rifle_power_instagib",
}

skin_api = mod.weapon_skin.new({
	id = SETTING_ID,
	name = "shock",
	template = TEMPLATE_NAME,
	unit_name = "units/ut/shock/shock_rifle",
	animations = {
		bones = {
			"root",
		},
		animations = animations,
	},
	muzzle_node = "tip",
	-- model_meters_per_unit is the meters per UT unit at which the model was converted (tools/asset_conversion/psk2bsi.py).
	-- meters_per_unit is the distance scale: the meters of forward in the view that one UT unit of the model takes up.
	model_meters_per_unit = 0.0125,
	meters_per_unit = 0.01,
	-- These come from ShockRifle.uc. The horizontal field of view that UT draws the weapon with was fitted to a screenshot of UT2004
	-- with small weapons off. With it the model's features land within about 10 pixels of the screenshot.
	display_fov = 70,
	field_of_view = math.rad(86.5),
	draw_scale = 0.7,
	offset_forward = 4,
	offset_right = 8,
	offset_up = -2,
	pivot_pitch = -1000 / 65536 * 360, -- PlayerViewPivot, degrees (negative is down)
	-- Weapon bob (Pawn.CheckBob and Pawn.WeaponBob). The sway and its speed both follow the player's speed, as in UT, so there is no
	-- bob when standing still. UT's Pawn.Bob is 0.01 at most, which is too much in this game's view, so a third of it is used. The
	-- damping is ShockRifle.BobDamping.
	bob = 0.0035,
	bob_damping = 1.8,
	-- The pose held while it overheats, sideways. These numbers are a guess. Try others with /skin shock_rifle set alt_pose_roll
	-- <degrees>, and so on.
	alt_pose_roll = 35,
	alt_pose_right = 4,
	alt_pose_forward = 0,
	alt_pose_up = -3,
	-- The inspect pose is held across the view, level, with the muzzle to the left, as the game's own weapons are inspected. That shows
	-- the left side. These numbers are a guess. Try others with /skin shock_rifle set inspect_pose_yaw <degrees>, and so on. The rifle
	-- is held further away, with its top turned towards the view, because seen from below it would show its underside, and UT's model
	-- has no faces there.
	inspect_pose_right = -2,
	inspect_pose_forward = 6,
	inspect_pose_up = 2,
	inspect_pose_roll = -20,
	inspect_pose_pitch = 6,
	inspect_pose_yaw = 65,
	third_person = THIRD_PERSON,

	looks = {
		[INSTAGIB_SKIN] = {
			chamber_material = "units/ut/shock/shock_rifle_fp_power_instagib",
			third_person = INSTAGIB_THIRD_PERSON,
		},
		-- These come from ShockRifle.uc with bUseOldWeaponMesh: OldMesh, OldPlayerViewOffset and OldPlayerViewPivot.
		-- Weapon.RenderOverlays draws it at OldDrawScale, which is 1.
		ut_shock_rifle_skin_2003 = {
			unit_name = "units/ut/shock2003/shock_rifle",
			animations = animations_2003,
			muzzle_node = "b_bone_flash01",
			chamber = false,
			draw_scale = 1,
			offset_forward = -15,
			offset_right = 0,
			offset_up = -5,
			pivot_pitch = 1000 / 65536 * 360,
			pivot_yaw = -800 / 65536 * 360,
			-- In this mod's conventions, the roll that fits a UT2004 screenshot has the opposite sign to OldPlayerViewPivot's roll.
			pivot_roll = 500 / 65536 * 360,
			-- Held across the view in the lower middle, with the whole model visible. The model turns about its own origin, which is
			-- far from its middle, so the offsets compensate for that.
			inspect_pose_right = -3.4,
			inspect_pose_forward = -67.7,
			inspect_pose_up = -3,
			inspect_pose_roll = -20,
			inspect_pose_pitch = 12,
			inspect_pose_yaw = 64,
			-- WeaponStaticMesh.ShockRiflePickup. Its barrel runs along the mesh's own Y, like the Flak Cannon's pickup. The hand
			-- holds the pistol grip.
			third_person = {
				id = SETTING_ID,
				template = TEMPLATE_NAME,
				unit_name = "units/ut/shock2003/pickup",
				hand_node = "j_rightweaponattach",
				meters_per_unit = 0.011,
				scale = 0.46,
				grip_right = 46,
				grip_forward = 0,
				grip_up = 4,
				yaw = -90,
				pitch = 0,
				roll = 0,
				muzzle_right = -86.2,
				muzzle_forward = 0,
				muzzle_up = 15,
				menu_yaw = 180,
			},
		},
	},
	on_create = function (skin)
		skin.cooldown = 1
		skin.cooldown_end = 0

		if skin_api.config.chamber_material then
			Unit.set_material(skin.unit, "m_power", skin_api.config.chamber_material)
		end

		skin_api.play_sound("ut_shock_select")
	end,
	on_update = update_chamber,
	on_update_always = update_balls,
	on_level_exit = function ()
		table.clear(balls)
	end,
})

local third_person = skin_api.third_person

-- Handles the player's shots. The animation plays when the shot's action starts, and the chamber's glow is back by the time the next
-- shot can be fired.
local function shot(action, new_action, animation_name)
	local skin = skin_api.state()

	if not skin or not utils.is_local_player_unit(action.owner_unit) then
		return
	end

	skin.cooldown = new_action.total_time
	skin.cooldown_end = Managers.time:time("game") + new_action.total_time

	skin_api.play(animation_name, skin_api.animation_duration(animation_name) / CONFIG.fire_animation_rates[animation_name])

	-- The flash follows the model's muzzle, and the model follows the first person unit. In a third person view the flash follows the
	-- mesh in the character's hand instead.
	local owner_unit = action.owner_unit
	local in_third_person = third_person.shows_weapon(owner_unit)
	local function follow()
		if in_third_person then
			return third_person.muzzle_position(owner_unit)
		end

		return skin_api.state() == skin and skin_api.muzzle_position() or nil
	end
	local scale = in_third_person and third_person.meters_per_unit_of(owner_unit) or skin.unit_scale

	-- In the first person view the flash is linked to the first person unit, like the model.
	local locked

	if not in_third_person then
		function locked()
			if skin_api.state() == skin then
				return skin_api.muzzle_in_view()
			end
		end
	end

	if animation_name == "Fire" then
		fx.beam_muzzle_flash(follow, scale, locked, utils.wielded_skin(owner_unit) == INSTAGIB_SKIN)
	else
		fx.ball_muzzle_flash(follow, scale, locked)
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

-- Draws the beam. The local player's beam starts at the model's muzzle, and the others' beams start at the mesh in their hand.
mod.shock_beam_callbacks.skin = function (owner_unit, start_position, end_position, hit_normal)
	local is_local = utils.is_local_player_unit(owner_unit)

	if is_local and skin_api.state() and not third_person.shows_weapon(owner_unit) then
		start_position = skin_api.muzzle_position() or start_position
	else
		-- The character is seen holding the mesh, so the beam starts at the end of its barrel. The shot's flash is made here for
		-- the other players. The player's own flash is made when the shot starts.
		start_position = third_person.muzzle_position(owner_unit) or start_position

		if not is_local then
			fx.beam_muzzle_flash(function ()
				return third_person.muzzle_position(owner_unit)
			end, third_person.meters_per_unit_of(owner_unit), nil, utils.wielded_skin(owner_unit) == INSTAGIB_SKIN)
		end
	end

	if not is_local then
		-- (the player's own shot is heard from the head, see take_over_sound)
		skin_api.play_sound_at("ut_shock_fire_3d", start_position)
	end

	fx.beam(start_position, end_position, hit_normal, utils.wielded_skin(owner_unit) == INSTAGIB_SKIN)
end

-- The ball, from every player, on every machine. The game's own fireball is not started: its effects come from the flow events that
-- the game sends the unit as the projectile is made, and those are filtered out. UT's ball is drawn where the projectile is.
local FIREBALL_FLOW_EVENTS = {
	lua_projectile_init = true,
	lua_trail = true,
	vfx_critical_strike = true,
}

mod.init_flow_event_filters.shock_ball = function (event_name)
	return FIREBALL_FLOW_EVENTS[event_name] == true
end

mod.init_callbacks.shock_ball = function (projectile)
	local unit = projectile._projectile_unit

	Unit.set_unit_visibility(unit, false)

	local owner_unit = projectile._owner_unit

	if not utils.is_local_player_unit(owner_unit) then
		skin_api.play_sound_at("ut_shock_alt_fire_3d", Unit.world_position(unit, 0))
		fx.ball_muzzle_flash(function ()
			return third_person.muzzle_position(owner_unit)
		end, third_person.meters_per_unit_of(owner_unit))
	end

	-- The ball is gone as soon as it has hit something. The game only notices a hit in its next update, by which time the projectile
	-- has moved a frame further (past the surface). So the frame's impacts are checked as well as the game's own stop.
	local impact_extension = projectile._impact_extension

	balls[#balls + 1] = fx.new_ball(function ()
		if not Unit.alive(unit) or projectile._stop_impacts then
			return nil
		end

		if impact_extension and select(2, impact_extension:recent_impacts()) > 0 then
			return nil
		end

		return Unit.world_position(unit, 0)
	end)

	skin_api.debug("ball")
end

-- These are the sounds of the player's own shots. The game plays them for the weapon and tells the others about them. The staff's
-- sounds are not played: UT's play instead, from the player's head. The others hear the shot from where it is (see shock_beam_callbacks
-- and init_callbacks).
skin_api.take_over_sound("weapon_staff_fire_beam_end_shot", "ut_shock_fire")
skin_api.take_over_sound("player_combat_weapon_staff_fireball_fire", "ut_shock_alt_fire")

-- The staff's fireball flash is in its animation, so the ball's shot animation is not played on the player's own first person unit.
-- The skin's model plays UT's animation, with its own flash. The animation of venting the heat is dropped too, because it has the
-- staff's puff of steam in it, which would come off where the game's staff is held and not off the skin's model.
mod.first_person_animation_filters[TEMPLATE_NAME] = function (event)
	return event == "attack_shoot_fireball" or event == "cooldown_start"
end

-- The staff's left hand plays a fire loop from its unit's flow. The Shock Rifle has none, so it is muted.
mod.sound_event_filters[TEMPLATE_NAME] = function (event_name)
	return event_name == "player_combat_fireball_loop"
end

mod.skin_explosion_callbacks.ut_shock_ball_explosion = function (world, position)
	fx.ball_explosion(position)
	skin_api.play_sound_at("ut_shock_explosion_3d", position)
end

mod.skin_explosion_callbacks.ut_shock_combo_explosion = function (world, position)
	fx.combo(position)
	skin_api.play_sound_at("ut_shock_combo_3d", position)

	skin_api.debug("combo")
end

-- Inspecting is the game's own action, held with the key. The rifle is turned to show its side for as long as it lasts.
mod.inspect_callbacks.shock_skin = function (action, started)
	local skin = skin_api.state()

	if skin and utils.is_local_player_unit(action.owner_unit) then
		skin.inspecting = started
	end
end

-- Venting the heat is the game's own action, and a UT2004 Shock Rifle has none. The chamber's glow pulses while it lasts.
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

-- The overcharge bar is orange between its thresholds for every Sienna. With the Shock Rifle it is purple, like its liquid. The game
-- sets the bar's colors every frame after it works out the fraction, so this hook runs after that and changes them.
mod:hook_safe(OverchargeBarUI, "set_charge_bar_fraction", function (self, player, _, min_threshold_fraction, max_threshold_fraction)
	if utils.wielded_template_name(player.player_unit) ~= TEMPLATE_NAME then
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
