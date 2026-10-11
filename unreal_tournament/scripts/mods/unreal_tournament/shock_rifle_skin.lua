local mod = get_mod("unreal_tournament")

-- Shock Rifle skin (the Weapon Skins setting): the Shock Rifle is UT2004's, in the player's own first person view and in the hand of
-- every character. The model, its placement and animations, the bob and the third person are weapon_skin.lua's; this file is what is
-- the Shock Rifle's: the chamber, the shots, the beam, the ball, the explosion and the combo. The gameplay is shock_rifle.lua's, this only
-- draws it differently, and is told what happens through the hook tables of hooks.lua.
--
-- The animations are UT's (Pickup, Idle, Fire, AltFire), the chamber's gel flows (the rotation, the stretch, the pan and the colour of
-- ShockPowerShader, in the shader graph of the chamber), and the glow comes back after a shot as long as it is until the next one
-- (ShockRifle.RenderOverlays).
-- The game's effects of the Shock Rifle (the fireball, its explosion, the beam's trail) are not made while the skin is on.
--
-- The assets were made with unreal_tournament/tools/asset_conversion.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local animations = mod:dofile("scripts/mods/unreal_tournament/shock_rifle_skin_animations")
local fx = mod:dofile("scripts/mods/unreal_tournament/shock_rifle_skin_effects")

local TEMPLATE_NAME = "staff_blast_beam_template_1"
local SETTING_ID = "shock_rifle"

local CONFIG = {
	-- The chamber is a shader graph that makes the flowing gel itself (tools/asset_conversion/make_chamber_material.py); this is the
	-- light of it when the glow is all there (it is lit by itself, as UT's shader has its diffuse as its self illumination)
	chamber_intensity = 1,
	vent_pulse_speed = 14, -- radians per second, of the glow while the heat is vented
	-- Overheating (the game's overcharge explosion, which lasts a few seconds before it goes off): the chamber pulses fast and bright, and the
	-- model is held sideways (alt_pose_* of the definition below)
	overheat_pulse_speed = 45, -- radians per second
	overheat_pulse_floor = 0.2, -- how dim the glow gets between pulses
	overheat_peak = 1.6, -- how bright it is at a pulse, times the glow when all there
	alt_pose_speed = 6, -- how fast the model moves to the sideways pose and back, per second
	-- Inspecting (UT2004 has no animation of it): the rifle is brought in and turned to show its side, and sways slowly while the key is held
	inspect_pose_speed = 5, -- how fast the model moves to the pose and back, per second
	inspect_sway = 12, -- degrees of yaw each way
	inspect_sway_speed = 1.8, -- radians per second
	projectile_sound_seconds = 1.795, -- how long the sound of the ball (ShockRifleProjectile) is
	-- How fast each shot's animation plays (WeaponFire.FireAnimRate: ShockProjFire says 1.5, ShockBeamFire leaves the default 1)
	fire_animation_rates = {
		Fire = 1,
		AltFire = 1.5,
	},
}

local skin_api

-- The balls of the Shock Rifle that are flying (of every player's, as this machine sees them): what makes up the ball of
-- UT is made as it goes (shock_rifle_skin_effects)
local balls = {}

-- What the game's own effects and sounds of the explosions are taken away for while the skin is on (the skin draws and plays
-- them, see skin_explosion_callbacks): { template name, key of the explosion, what it was }
local explosion_overrides = {
	{ "ut_shock_ball_explosion", "effect_name" },
	{ "ut_shock_ball_explosion", "sound_event_name" },
	{ "ut_shock_combo_explosion", "sound_event_name" },
}

-- The game's own effect of the explosion is taken away while the skin is on, and given back when it is off
local function apply_template_overrides()
	local enabled = skin_api.enabled()

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

local function give_back_overrides()
	for _, override in ipairs(explosion_overrides) do
		if override[3] then
			ExplosionTemplates[override[1]].explosion[override[2]] = override[3]
			override[3] = nil
		end
	end
end

-- Every frame

-- The chamber: the glow
local function update_chamber(skin, dt)
	-- (a shock rifle in UT hasn't the glow of its chamber after it has fired, and gets it back as the time to the next shot goes)
	local charge = 1 - math.clamp((skin.cooldown_end - Managers.time:time("game")) / skin.cooldown, 0, 1)

	if skin.venting then
		skin.vent_time = skin.vent_time + dt
		charge = charge * (0.55 + 0.45 * math.sin(skin.vent_time * CONFIG.vent_pulse_speed))
	end

	local first_person_extension = skin_api.local_first_person()
	local status_extension = first_person_extension and ScriptUnit.has_extension(first_person_extension.unit, "status_system")
	local overheating = status_extension ~= nil and status_extension:is_overcharge_exploding()

	-- (the model goes to the sideways pose while it overheats, and comes back after)
	skin.alt_pose = (skin.alt_pose or 0) + ((overheating and 1 or 0) - (skin.alt_pose or 0)) * math.min(1, CONFIG.alt_pose_speed * dt)

	-- (the inspect pose, and the sway it turns the rifle with)
	skin.inspect_pose = (skin.inspect_pose or 0) + ((skin.inspecting and 1 or 0) - (skin.inspect_pose or 0)) * math.min(1, CONFIG.inspect_pose_speed * dt)
	skin.inspect_time = skin.inspecting and (skin.inspect_time or 0) + dt or 0
	skin.extra_yaw = skin.inspect_pose * CONFIG.inspect_sway * math.sin(skin.inspect_time * CONFIG.inspect_sway_speed)

	if overheating then
		skin.overheat_time = (skin.overheat_time or 0) + dt

		local pulse = 0.5 + 0.5 * math.sin(skin.overheat_time * CONFIG.overheat_pulse_speed)

		charge = CONFIG.overheat_peak * (CONFIG.overheat_pulse_floor + (1 - CONFIG.overheat_pulse_floor) * pulse)
	else
		skin.overheat_time = 0
	end

	Material.set_scalar(Mesh.material(Unit.mesh(skin.unit, "g_shock_1"), "m_power"), "intensity", CONFIG.chamber_intensity * charge)
end

local function update_balls(dt)
	for i = #balls, 1, -1 do
		local ball = balls[i]

		-- (the sound of the ball is a loop in UT: it is played again as it ends, from where the ball is)
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
	-- The model was converted at this many meters per UT unit (tools/asset_conversion/psk2bsi.py), the distance scale is how many
	-- meters of forward are a UT unit of it in the view
	model_meters_per_unit = 0.0125,
	meters_per_unit = 0.01,
	-- ShockRifle.uc. The field of view UT draws the weapon with, horizontal, is fitted to a screenshot of UT2004 (the features of
	-- the model land within about 10 pixels of it) with small weapons off
	display_fov = 70,
	field_of_view = math.rad(86.5),
	draw_scale = 0.7,
	offset_forward = 4,
	offset_right = 8,
	offset_up = -2,
	pivot_pitch = -1000 / 65536 * 360, -- PlayerViewPivot, degrees (negative is down)
	-- Weapon bob (Pawn.CheckBob and Pawn.WeaponBob): both the sway and how fast it goes follow the speed of the player, as they do in
	-- UT (it is none when standing still). Bob is Pawn.Bob, which is 0.01 at most there: that is too much in this game's view, so a
	-- third of it is used. The damping is ShockRifle.BobDamping
	bob = 0.0035,
	bob_damping = 1.8,
	-- Held sideways while it overheats (a guess, /skin shock_rifle set alt_pose_roll <degrees> and the others to try)
	alt_pose_roll = 35,
	alt_pose_right = 4,
	alt_pose_forward = 0,
	alt_pose_up = -3,
	-- Brought in and turned to show its side while it is inspected (a guess, /skin shock_rifle set inspect_pose_roll <degrees> and the others)
	inspect_pose_right = -4,
	inspect_pose_forward = -3,
	inspect_pose_up = 1,
	inspect_pose_roll = -35,
	inspect_pose_pitch = 12,
	inspect_pose_yaw = 25,
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
	end,
	on_update = update_chamber,
	on_update_always = update_balls,
	on_refresh = apply_template_overrides,
	on_give_back = give_back_overrides,
	on_level_exit = function ()
		table.clear(balls)
	end,
})

local third_person = skin_api.third_person

-- The shots (the animation plays as the action of the shot starts, and the glow comes back by the time the next one can
-- be fired)
local function shot(action, new_action, animation_name)
	local skin = skin_api.state()

	if not skin or not utils.is_local_player_unit(action.owner_unit) then
		return
	end

	skin.cooldown = new_action.total_time
	skin.cooldown_end = Managers.time:time("game") + new_action.total_time

	skin_api.play(animation_name, skin_api.animation_duration(animation_name) / CONFIG.fire_animation_rates[animation_name])

	-- (the flash follows the muzzle of the model: it is the skin that follows the first person unit; in a third person view it
	-- is the mesh in the character's hand)
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

-- The beam, of the player who plays (from the muzzle of the model) and of the others (from the mesh in the hand)
mod.shock_beam_callbacks.skin = function (owner_unit, start_position, end_position, hit_normal)
	local is_local = utils.is_local_player_unit(owner_unit)

	if is_local and skin_api.state() and not third_person.shows_weapon(owner_unit) then
		start_position = skin_api.muzzle_position() or start_position
	else
		-- (the character is seen holding the mesh: the beam starts at the end of its barrel, and the flash of the shot is made
		-- here for the others, the player's own is made when the shot starts)
		start_position = third_person.muzzle_position(owner_unit) or start_position

		if not is_local then
			fx.beam_muzzle_flash(function ()
				return third_person.muzzle_position(owner_unit)
			end, third_person.meters_per_unit)
		end
	end

	if not is_local then
		-- (the shot of the player is heard from the head, see take_over_sound)
		skin_api.play_sound_at("ut_shock_fire_3d", start_position)
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

-- The shots of the player, which the game plays for the weapon and tells the others of (they hear them from the shot, see
-- shock_beam_callbacks and init_callbacks): the sounds of the staff are not played, the ones of UT are, from the head
skin_api.take_over_sound("weapon_staff_fire_beam_end_shot", "ut_shock_fire")
skin_api.take_over_sound("player_combat_weapon_staff_fireball_fire", "ut_shock_alt_fire")

-- The flash of the staff's fireball is in its animation: while the skin is on the animation of the ball's shot is not played on the player's
-- own first person unit (the model of the skin plays UT's, with its own flash)
mod.first_person_animation_filters[TEMPLATE_NAME] = function (event)
	return skin_api.enabled() and event == "attack_shoot_fireball"
end

mod.skin_explosion_callbacks.ut_shock_ball_explosion =function (world, position)
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

-- The inspect is the game's own action, held with the key: the rifle is turned to show its side as long as it lasts
mod.inspect_callbacks.shock_skin = function (action, started)
	local skin = skin_api.state()

	if skin and utils.is_local_player_unit(action.owner_unit) then
		skin.inspecting = started
	end
end

-- Venting the heat is the game's own action, a UT2004 Shock Rifle has none: the glow of the chamber pulses while it lasts
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
