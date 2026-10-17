local mod = get_mod("unreal_tournament")

-- Rocket Launcher skin: how UT2004's Rocket Launcher looks and sounds.
--
-- weapon_skin.lua does the model, its placement and animations, the bob and the third person. This file does what is the Rocket
-- Launcher's own: the flash, the rocket in flight (its mesh, corona and smoke), the explosion and the sounds. The gameplay is in
-- rocket_launcher.lua. This file only draws it, and is told what happens through the hook tables in hooks.lua.
--
-- The game's unit of the rocket (the crossbow's bolt) still flies, since it is the gameplay. Its own effects are dropped, and UT's are
-- drawn at it. The crossbow's shot sound is in its animation, which is not played on the player's own first person unit.
--
-- The assets were made with tools/asset_conversion.

local utils = mod.utils
local animations = mod:dofile("scripts/mods/unreal_tournament/rocket/skin_animations")
local particles = mod.skin_particles

local TEMPLATE_NAME = mod.items.weapons.rocket_launcher.template
local SETTING_ID = "rocket_launcher"

local CONFIG = {
	-- RocketMuzFlash1st: a flash that lasts 0.15 s. UT draws it as meshes, and here it is a sprite.
	muzzle_size = 70,
	muzzle_growth = 80,
	muzzle_life = 0.15,
	-- RocketProj: the mesh spins. Its RotationRate roll is 50000 out of 65536 for a full turn, per second.
	rocket_turns_per_second = 50000 / 65536,
	-- RocketCorona (RocketFlare): 1.2 times the 128 units of its texture, pulsing between 0.9 and 1.5. It sits at the back of the mesh,
	-- and a little towards the camera so the mesh does not hide it.
	corona_size = 90,
	corona_intensity = 2.2, -- brightness, where 1 is the texture as it is
	corona_pulse_seconds = 0.2,
	corona_back = 0.2, -- m
	corona_toward_camera = 0.4, -- m
	-- RocketTrailSmoke: wisps, 90 a second, each lasting 1.25 s. They are 15 to 20 units wide, grow 13 units a second, and rise a little.
	smoke_interval = 1 / 90,
	smoke_life = 1.25,
	smoke_size = {
		15,
		20,
	},
	smoke_growth = 13,
	smoke_rise = 0.3, -- m/s
	smoke_color = {
		0.9,
		0.85,
		0.85,
	},
	rocket_sound_seconds = 1.87, -- length of the rocket's sound loop (RocketLauncherProjectile)
	-- The explosion (NewExplosionA) has the game's own explosion, with its smoke and the mark it leaves (only if the game has it
	-- loaded), a flash, and three fireballs. Each fireball plays a sheet of 16 frames. All three use the same sheet, one of two.
	explosion_effect = "fx/wpnfx_frag_grenade_impact",
	explosion_flash_size = 300,
	explosion_flash_growth = 500,
	explosion_flash_life = 0.25,
	explosion_flash_intensity = 0.5,
	explosion_fire_count = 3,
	explosion_fire_frames = 16, -- frames in a sheet. They run down its columns, not along its rows.
	explosion_fire_gap = 0.1, -- seconds between the fireballs starting (UT: 10 a second)
	-- A UE2 sprite is about twice as wide as its size number says. UT's explosion is as wide as its blast, 3 m of radius, and its
	-- three fireballs of size 50 to 70 only reach that width because of this.
	explosion_fire_size = {
		90,
		125,
	},
	explosion_fire_life = {
		0.4,
		0.6,
	},
	explosion_fire_spread = 36, -- units, the radius of the sphere the fireballs start in
	-- The frames are drawn in a colour brighter than white, which the game's lighting turns into a glow. The texture alone, at 1, looks
	-- dull grey in the game. The colour is yellow, and the frames' own colours make the middle of a fireball brighter than its edge.
	explosion_fire_intensity = 0.6, -- how solid the frames are: their transparency times this
	explosion_fire_color = {
		1.5,
		1.25,
		0.8,
	},
	explosion_lift = 20, -- units off the surface (NewExplosionA is spawned 20 units along the surface's normal)
	inspect_pose_speed = 5, -- how fast the model moves to the inspect pose and back, per second
	inspect_sway = 5, -- degrees of yaw each way while inspecting
	inspect_sway_speed = 1.8, -- radians per second
	-- Rockets of another player that start less than this far apart (in seconds) belong to the same shot
	shot_gap = 0.25,
	-- What follows a rocket being fired or loaded (RocketLauncher.uc, state AnimateLoad), in seconds after it: the barrel starts to
	-- turn, the load sound plays, and the plunger sound plays. The code turns the barrel, not the animations. It turns a third of a
	-- turn each time, at 2.95 thirds of a turn a second.
	barrel_delay = 0.15,
	load_sound_delay = 0.22,
	remote_second_load = 0.95, -- seconds after another player starts aiming that the second rocket is loaded (RocketMultiFire.FireRate)
	chamber_load_frame = 3, -- the frame of the load animation where a rocket slides in from the side (the shell is out at the side)
	shell_hide_frame = 2.5, -- the frame of the load animation where the rocket that the rod pushes has gone into the barrel
	plunger_sound_delay = 0.5, -- seconds until the plunger sound. The shell and the feed move then, at plunge_speed times the animation's speed.
	plunge_speed = 0.8,
	barrel_step = 120, -- degrees
	barrel_speed = 2.95 * 120, -- degrees per second
	-- The piston's rod, in the mesh's units: how long it is, and where its back is, to the right of the mesh's origin.
	rod_length = 11.45,
	rod_back = 15.55,
	-- The barrel turns about an axis along the mesh's own left, which is the way the barrels point before the animation's root turns
	-- the mesh. The axis goes through this point of the mesh (right, forward, up, in the mesh's units). The barrel turns anticlockwise
	-- as the player sees it.
	barrel_pivot = {
		-23.3,
		0.7,
		16,
	},
}

local UNIT = utils.UT_UNIT

-- The index of the barrel's bone in the animations' list of bones
local BARREL_BONE

-- The indexes of the bones that the load animation moves, the shell and the rod. The rod is UT's piston: its front goes out with the
-- animation and its back stays in place, so the skin stretches it. The shell is the rocket that is loaded in the chamber.
local PLUNGE_BONES = {}
local ROD_BONE
local SHELL_BONE

for index, name in ipairs(animations.bones) do
	if name == "b_bone_barrel" then
		BARREL_BONE = index
	elseif name == "b_bone_shell" or name == "b_bone_rod" then
		PLUNGE_BONES[#PLUNGE_BONES + 1] = index

		if name == "b_bone_rod" then
			ROD_BONE = index
		else
			SHELL_BONE = index
		end
	end
end

-- The parts of the load animation. They are played alone or one after the other. In "slide" a rocket slides in from the side. In
-- "push" the rod pushes the rocket in the chamber into the barrel, and the next one slides in. In "push_last" the pushed rocket is the
-- last one, so no other slides in, and the shell is hidden once it is in the barrel.
local LAST_LOAD_FRAME = #animations.animations.Load.frames - 1
local LOAD_PARTS = {
	slide = {
		from = CONFIG.chamber_load_frame,
		to = LAST_LOAD_FRAME,
		sound = "ut_rocket_load",
	},
	push = {
		from = 0,
		to = LAST_LOAD_FRAME,
		sound = "ut_rocket_plunger",
	},
	push_last = {
		from = 0,
		to = LAST_LOAD_FRAME,
		sound = "ut_rocket_plunger",
		hide_from = CONFIG.shell_hide_frame,
	},
}

-- Returns where the animation is after this many seconds, as the frame, the part and the part's place in the list. Returns nil when
-- the animation is over.
local function plunge_position(plunge)
	local frames = plunge.time * animations.animations.Load.rate

	for index, part in ipairs(plunge.parts) do
		local length = part.to - part.from

		if frames <= length then
			return part.from + frames, part, index
		end

		frames = frames - length
	end

	return nil
end

local skin_api

-- Sounds of another player's loading that are waiting for their time to play
local remote_sounds = utils.delayed_events()

-- The rockets in flight, each as { unit = the mesh, game_unit = the projectile's unit, projectile = its extension, ... }
local visuals = {}

-- Returns whether a rocket in flight is on its way to this enemy. rocket_launcher.lua keeps the lock while there is one.
function mod.rocket_homing_on(target)
	for _, visual in ipairs(visuals) do
		local locomotion_extension = Unit.alive(visual.game_unit) and ScriptUnit.has_extension(visual.game_unit, "projectile_locomotion_system")

		if locomotion_extension and locomotion_extension.target_unit == target then
			return true
		end
	end

	return false
end

local random_between = utils.random_between
local random_direction = utils.random_direction

local function destroy_visual(visual)
	if Unit.alive(visual.unit) then
		World.destroy_unit(visual.world, visual.unit)
	end
end

-- Destroys all the visuals when the level ends or the mod is unloaded. A unit of the mod's package that is still alive when the
-- package is unloaded crashes the game.
local function clear_visuals()
	for i = #visuals, 1, -1 do
		destroy_visual(visuals[i])
	end

	table.clear(visuals)
	remote_sounds.clear()
end

local function update_visuals(dt)
	remote_sounds.update(dt)

	for i = #visuals, 1, -1 do
		local visual = visuals[i]
		local game_unit = visual.game_unit

		if not Unit.alive(game_unit) or visual.projectile._stop_impacts or not Unit.alive(visual.unit) then
			destroy_visual(visual)
			table.remove(visuals, i)
		else
			local position = Unit.world_position(game_unit, 0)
			local previous = visual.previous:unbox()

			local moved = position - previous

			visual.previous:store(position)
			visual.time = visual.time + dt
			visual.smoke_time = visual.smoke_time - dt
			visual.sound_time = visual.sound_time - dt

			if Vector3.length(moved) > 0.0001 then
				visual.direction:store(Vector3.normalize(moved))
			end

			-- The rocket spins about its own length as it flies.
			local direction = visual.direction:unbox()
			local turn = Quaternion.axis_angle(Vector3(0, 1, 0), visual.time * CONFIG.rocket_turns_per_second * 2 * math.pi)

			Unit.set_local_position(visual.unit, 0, position)
			Unit.set_local_rotation(visual.unit, 0, Quaternion.multiply(Quaternion.look(direction, Vector3.up()), turn))

			while visual.smoke_time <= 0 do
				visual.smoke_time = visual.smoke_time + CONFIG.smoke_interval

				particles.sprite({
					additive = 0,
					color = CONFIG.smoke_color,
					growth = CONFIG.smoke_growth * UNIT,
					intensity = 0.9,
					life = CONFIG.smoke_life,
					position = position,
					size = random_between(CONFIG.smoke_size) * UNIT,
					spin = (math.random() * 2 - 1) * 0.3,
					texture = "smoke",
					velocity = Vector3(0, 0, CONFIG.smoke_rise),
				})
			end

			if visual.sound_time <= 0 then
				visual.sound_time = CONFIG.rocket_sound_seconds

				skin_api.play_sound_at("ut_rocket_projectile_3d", position)
			end
		end
	end
end

-- Adds the mesh of a rocket and its corona, drawn at the game's unit. The game's unit itself is not shown.
local function add_visual(projectile)
	local world = Managers.world:world("level_world")
	local game_unit = projectile._projectile_unit
	local position = Unit.world_position(game_unit, 0)
	local unit = World.spawn_unit(world, "units/ut/rocket/projectile", position)

	Unit.set_unit_visibility(game_unit, false)

	local visual = {
		direction = Vector3Box(Vector3.forward()),
		game_unit = game_unit,
		previous = Vector3Box(position),
		projectile = projectile,
		smoke_time = 0,
		sound_time = 0,
		time = 0,
		unit = unit,
		world = world,
	}

	visuals[#visuals + 1] = visual

	particles.sprite({
		color = {
			1,
			0.9,
			0.72,
		},
		fade_in = 0,
		intensity = CONFIG.corona_intensity,
		follow = function ()
			if Unit.alive(game_unit) and not projectile._stop_impacts then
				local position = Unit.world_position(game_unit, 0) - visual.direction:unbox() * CONFIG.corona_back
				local to_camera = Managers.state.camera:camera_position("player_1") - position
				local distance = Vector3.length(to_camera)

				if distance > 0.01 then
					position = position + to_camera * (math.min(CONFIG.corona_toward_camera, distance * 0.5) / distance)
				end

				return position
			end
		end,
		life = 8,
		size = CONFIG.corona_size * UNIT,
		texture = "rocket_flare",
		-- UT draws the corona wider than it is high, and always upright.
		angle = 0,
	})

	return visual
end

-- Shows a flash at the muzzle, either of the mesh in the character's hand or of the model in the player's own view.
local function muzzle_flash(follow, scale)
	particles.sprite({
		color = {
			1,
			0.9,
			0.7,
		},
		follow = follow,
		growth = CONFIG.muzzle_growth * scale,
		life = CONFIG.muzzle_life,
		size = CONFIG.muzzle_size * scale,
		spin = (math.random() * 2 - 1) * 0.2,
		texture = "rocket_muzzle",
	})
end

-- A shot by another player, as seen on this machine: the flash and the sound come from the end of the barrel of the mesh in their
-- hand. They play once for all the rockets of a shot that start together.
local last_remote_shot = {}

local function remote_shot(owner_unit)
	local now = Managers.time:time("game")

	if last_remote_shot[owner_unit] and now - last_remote_shot[owner_unit] < CONFIG.shot_gap then
		return
	end

	last_remote_shot[owner_unit] = now

	local muzzle = skin_api.third_person.muzzle_position(owner_unit)

	muzzle_flash(function ()
		return skin_api.third_person.muzzle_position(owner_unit)
	end, skin_api.third_person.meters_per_unit)

	if muzzle then
		skin_api.play_sound_at("ut_rocket_fire_3d", muzzle)
	end
end

skin_api = mod.weapon_skin.new({
	id = SETTING_ID,
	name = "rocket",
	template = TEMPLATE_NAME,
	unit_name = "units/ut/rocket/rocket_launcher",
	animations = animations,
	muzzle_node = "b_bone_flash",
	model_meters_per_unit = 0.0125,
	meters_per_unit = 0.01,
	-- RocketLauncher.uc turns the model a little: the pivot's yaw is 500 and its roll is 1000, out of 65536 for a full turn.
	display_fov = 60,
	draw_scale = 1,
	offset_forward = 0,
	offset_right = 8,
	offset_up = 0,
	pivot_yaw = 500 / 65536 * 360,
	-- The roll is the other way round from the other weapons', because that matches UT's picture.
	pivot_roll = -1000 / 65536 * 360,
	bob_damping = 1.5,
	idle_speed = 0.5, -- RocketLauncher.IdleAnimRate
	-- The inspect pose brings the launcher to the middle of the view and turns it to the left about its middle. It ends up across the
	-- view, with its left side (the display and the label) towards the player and the barrels pointing left. The turn goes with the move.
	inspect_pose_right = -28,
	inspect_pose_forward = -2,
	inspect_pose_up = 10,
	inspect_pose_roll = 10,
	inspect_pose_pitch = 4,
	inspect_pose_yaw = 70,
	inspect_turn_start = 0,
	inspect_pivot_right = 7,
	inspect_pivot_forward = 22,
	inspect_pivot_up = 12,
	-- WeaponStaticMesh.RocketLauncherPickup (DrawScale 0.45). Its barrels run along the mesh's own -Y, and the grip is under its back.
	third_person = {
		id = SETTING_ID,
		template = TEMPLATE_NAME,
		unit_name = "units/ut/rocket/pickup",
		-- The game links the crossbow, the blunderbuss and the Drakegun to the left hand's node (AttachmentNodeLinking.repeating_crossbow).
		hand_node = "j_leftweaponattach",
		meters_per_unit = 0.009,
		scale = 0.6,
		grip_right = -14,
		grip_forward = 0,
		grip_up = 4,
		yaw = 90,
		pitch = -15,
		roll = 0,
		-- In the world the launcher moves with the game's crossbow, which the game animates with the arms. It is turned from the
		-- crossbow's own axes and is not calibrated the way the Flak Cannon is, because the crossbow is still moving into place at the
		-- time of calibration.
		follow_game_unit = 2,
		follow_calibrate_seconds = 1,
		muzzle_right = 68,
		muzzle_forward = 0,
		muzzle_up = 8,
		menu_yaw = 0,
	},
	on_create = function ()
		skin_api.play_sound("ut_rocket_select")
	end,
	on_update = function (skin, dt)
		-- UT puts the weapon away when it has no ammo, but here it stays in hand. The last rocket is the one in the barrel, so with 1
		-- rocket of ammo, or none, there is no shell in the chamber. When ammo is picked up, the rockets are loaded: one slides in,
		-- is pushed into the barrel, and another slides in after it. If one rocket is already in the barrel, only one slides in.
		local previous_ammo = skin.ammo
		local ammo = utils.local_ranged_ammo()

		skin.ammo = ammo

		-- With no ammo there is nothing to load, so what a shot starts (the barrel turning, the sounds, the plunger) does not play.
		if ammo == 0 then
			skin.barrels = 1
			skin.load_cycle = nil
			skin.plunge = nil
		elseif ammo and previous_ammo and ammo > previous_ammo then
			if previous_ammo == 0 then
				skin.plunge = {
					time = 0,
					parts = ammo == 1 and {LOAD_PARTS.slide, LOAD_PARTS.push_last} or {LOAD_PARTS.slide, LOAD_PARTS.push, LOAD_PARTS.slide},
				}
			elseif previous_ammo <= (skin.barrels or 1) and not skin.load_cycle and not skin.plunge then
				skin.plunge = {
					time = 0,
					parts = {LOAD_PARTS.slide},
				}
			end
		end

		-- Moves the model towards the inspect pose and back, and sways it while it is there.
		skin.inspect_pose = (skin.inspect_pose or 0) + ((skin.inspecting and 1 or 0) - (skin.inspect_pose or 0)) * math.min(1, CONFIG.inspect_pose_speed * dt)
		skin.inspect_time = skin.inspecting and (skin.inspect_time or 0) + dt or 0
		skin.extra_yaw = skin.inspect_pose * CONFIG.inspect_sway * math.sin(skin.inspect_time * CONFIG.inspect_sway_speed)

		local cycle = skin.load_cycle

		if cycle then
			cycle.time = cycle.time + dt

			if not cycle.turned and cycle.time >= CONFIG.barrel_delay then
				cycle.turned = true
				skin.barrel_final = (skin.barrel_final or 0) + CONFIG.barrel_step

				if skin.barrel_final >= 360 then
					skin.barrel_final = skin.barrel_final - 360
					skin.barrel_angle = (skin.barrel_angle or 0) - 360
				end
			end

			if not cycle.loaded and cycle.time >= CONFIG.load_sound_delay then
				cycle.loaded = true
				skin_api.play_sound("ut_rocket_load")
			end

			if cycle.time >= CONFIG.plunger_sound_delay then
				skin.load_cycle = nil
				skin.plunge = {
					time = 0,
					parts = {(skin.ammo or math.huge) <= cycle.barrels and LOAD_PARTS.push_last or LOAD_PARTS.push},
				}
			end
		end

		local plunge = skin.plunge

		if plunge then
			plunge.time = plunge.time + dt * CONFIG.plunge_speed

			local position, part, index = plunge_position(plunge)

			if not position then
				skin.plunge = nil
			elseif plunge.sounded ~= index then
				plunge.sounded = index
				skin_api.play_sound(part.sound)
			end

			skin.shell_hidden = position ~= nil and part.hide_from ~= nil and position >= part.hide_from
		end

		-- While a load is still to come after a shot, the shell stays as it is.
		if not skin.plunge and not skin.load_cycle then
			skin.shell_hidden = ammo ~= nil and ammo <= (skin.barrels or 1)
		end

		if (skin.barrel_angle or 0) < (skin.barrel_final or 0) then
			skin.barrel_angle = math.min(skin.barrel_final, (skin.barrel_angle or 0) + CONFIG.barrel_speed * dt)
		end
	end,
	on_pose = function (skin, pose)
		-- The shell and the feed play the load animation by themselves, on top of the animation that is playing. UT blends it in on
		-- the bones of those two and leaves the rest alone.
		local plunge = skin.plunge
		local position = plunge and plunge_position(plunge)

		if position then
			local frames = animations.animations.Load.frames
			local index = math.floor(position)
			local fraction = position - index
			local first, second = frames[index + 1], frames[math.min(index + 2, #frames)]

			for _, bone in ipairs(PLUNGE_BONES) do
				local o = (bone - 1) * 7

				for i = 1, 7 do
					pose[o + i] = first[o + i] + (second[o + i] - first[o + i]) * fraction
				end
			end
		end

		skin.node_scales = skin.node_scales or {}
		skin.node_scales[SHELL_BONE] = skin.shell_hidden and Vector3(0.001, 0.001, 0.001) or nil

		-- The rod is stretched from its back, which stays in place, by as much as the animation moves its front. The mesh's right is
		-- the way back, so the move is negative.
		local rod = (ROD_BONE - 1) * 7
		local reach = -pose[rod + 5]

		pose[rod + 5], pose[rod + 6], pose[rod + 7] = 0, 0, 0

		if reach > 0.01 then
			local stretch = (CONFIG.rod_length + reach) / CONFIG.rod_length

			skin.node_scales = skin.node_scales or {}
			skin.node_scales[ROD_BONE] = Vector3(stretch, 1, 1)
			pose[rod + 5] = CONFIG.rod_back * (1 - stretch)
		elseif skin.node_scales then
			skin.node_scales[ROD_BONE] = nil
		end

		local angle = math.rad(skin.barrel_angle or 0)

		if angle == 0 then
			return
		end

		-- The barrel's own pose (a move and a turn about the mesh's origin) is turned about the barrel's axis, which goes through the
		-- pivot. The axis is the mesh's own left, but the turn here is about the mesh's right, which is the opposite direction.
		local o = (BARREL_BONE - 1) * 7
		local sin_half, cos_half = math.sin(angle / 2), math.cos(angle / 2)
		local x, y, z, w = pose[o + 1], pose[o + 2], pose[o + 3], pose[o + 4]
		local pivot = CONFIG.barrel_pivot

		pose[o + 1] = cos_half * x + sin_half * w
		pose[o + 2] = cos_half * y - sin_half * z
		pose[o + 3] = cos_half * z + sin_half * y
		pose[o + 4] = cos_half * w - sin_half * x

		local cos_angle, sin_angle = math.cos(angle), math.sin(angle)
		local py, pz = pose[o + 6] - pivot[2], pose[o + 7] - pivot[3]

		pose[o + 6] = py * cos_angle - pz * sin_angle + pivot[2]
		pose[o + 7] = py * sin_angle + pz * cos_angle + pivot[3]
	end,
	on_give_back = clear_visuals,
	on_update_always = update_visuals,
	on_level_exit = function ()
		clear_visuals()
		table.clear(last_remote_shot)
	end,
})

local third_person = skin_api.third_person

-- Starts a load. The barrel turns a third of a turn, and then the load and plunger sounds play (see on_update). A new load replaces
-- one that is not finished. "barrels" is how many rockets are in the barrels when the load is done, and a shot leaves one. If the
-- ammo is not more than that, there is no rocket for the rod to push next, so no shell slides in.
local function turn_barrel(skin, barrels)
	skin.barrels = barrels or 1
	skin.plunge = nil
	skin.load_cycle = {
		time = 0,
		barrels = skin.barrels,
	}
end

-- How many rockets the player has loaded, and how many can be loaded. The ammo can limit that to fewer than three.
local loaded_count = 1
local rocket_capacity = 3

-- Handles a shot of the player: plays the animation, the flash and the sound.
local function shot(action, new_action)
	local skin = skin_api.state()
	local owner_unit = action.owner_unit

	if not skin or not utils.is_local_player_unit(owner_unit) then
		return
	end

	skin.barrels = 1

	-- A shot cuts off a load that is still playing, such as the sliding in after picking up ammo, along with the sounds it has left.
	skin.plunge = nil

	-- A single rocket always turns the barrel. A salvo only turns it when the salvo is full.
	if not new_action.ut_rocket_salvo or loaded_count >= 3 then
		turn_barrel(skin)
	end

	local in_third_person = third_person.shows_weapon(owner_unit)

	skin_api.play(new_action.ut_rocket_salvo and "AltFire" or "Fire")
	skin_api.play_sound(new_action.ut_rocket_salvo and "ut_rocket_alt_fire" or "ut_rocket_fire")
	muzzle_flash(function ()
		if in_third_person then
			return third_person.muzzle_position(owner_unit)
		end

		return skin_api.state() == skin and skin_api.muzzle_position() or nil
	end, in_third_person and third_person.meters_per_unit or skin.unit_scale)
end

mod.crossbow_start_callbacks.rocket_skin = function (action, new_action)
	if new_action.ut_rocket or new_action.ut_rocket_salvo then
		shot(action, new_action)
	end
end

-- Inspecting is the game's own action, held with the key. The launcher is turned to show its side for as long as it lasts.
mod.inspect_callbacks.rocket_skin = function (action, started)
	local skin = skin_api.state()

	if skin and utils.is_local_player_unit(action.owner_unit) then
		skin.inspecting = started
	end
end

-- Plays the beep when a lock is made, and the lost-lock sound when it is lost.
mod.rocket_lock_callbacks.rocket_skin = function (owner_unit, locked)
	if skin_api.state() and utils.is_local_player_unit(owner_unit) then
		skin_api.play_sound(locked and "ut_rocket_lock" or "ut_rocket_seek_lost")
	end
end

-- When the aiming starts, the first rocket is loaded and the barrel turns.
mod.aim_start_callbacks.rocket_skin = function (self, new_action)
	local skin = skin_api.state()

	if new_action.ut_rocket_aim and skin and utils.is_local_player_unit(self.owner_unit) then
		loaded_count = 1
		rocket_capacity = math.min(3, self.ammo_extension and self.ammo_extension:current_ammo() or 3)

		-- One rocket is in the barrel already. With fewer than three rockets of ammo there is one load fewer, and the last load is the
		-- one that is cut. So there is no load to play for a single rocket, and one for two.
		skin.barrels = 1
		skin.plunge = nil

		if rocket_capacity >= 2 then
			turn_barrel(skin, 2)
		end
	end
end

-- Another rocket is loaded. The load animation plays for the second rocket when three can be loaded. UT's third rocket has none.
mod.rocket_load_callbacks.rocket_skin = function (owner_unit, loaded)
	local skin = skin_api.state()

	if skin and utils.is_local_player_unit(owner_unit) then
		loaded_count = loaded

		if loaded == 2 and rocket_capacity >= 3 then
			turn_barrel(skin, 3)
		end
	end
end

-- The crossbow's shot and reload sounds are in its animations, so those animations are not played on the player's own first person
-- unit. The skin's model plays UT's animations instead. UT's weapon has no reload, but the game still reloads when the weapon is
-- wielded.
mod.first_person_animation_filters[TEMPLATE_NAME] = function (event)
	return event == "attack_shoot" or event == "attack_shoot_last" or string.find(event, "reload", 1, true) ~= nil
end

-- Plays what other players' loading and shots sound like. In UT everyone hears the load sound and the plunger sound a little after a
-- rocket is loaded or fired. Here they are played where the other player is, from the animation events that the game sends over the
-- network.
local function remote_load_sounds(unit, delay)
	local function still_there()
		return Unit.alive(unit)
	end

	remote_sounds.schedule(delay + CONFIG.load_sound_delay, still_there, function ()
		skin_api.play_sound_at("ut_rocket_load_3d", Unit.world_position(unit, 0))
	end)
	remote_sounds.schedule(delay + CONFIG.plunger_sound_delay, still_there, function ()
		skin_api.play_sound_at("ut_rocket_plunger_3d", Unit.world_position(unit, 0))
	end)
end

mod.third_person_animation_filters[TEMPLATE_NAME] = function (event, unit)
	if unit and not utils.is_local_player_unit(unit) then
		if event == "to_zoom" then
			-- Aiming starts the loading, and the second rocket is loaded one salvo time later.
			remote_load_sounds(unit, 0)
			remote_load_sounds(unit, CONFIG.remote_second_load)
		elseif event == "attack_shoot" or event == "attack_shoot_last" then
			remote_load_sounds(unit, 0)
		end
	end

	-- The reload is not played on the characters, because the launcher has none.
	return string.find(event, "reload", 1, true) ~= nil
end

-- The crossbow's animations play these sounds on the characters, through the units' flow. They are muted, so the shot animation
-- plays without its sound.
local MUTED_SOUNDS = {
	player_combat_weapon_repeating_crossbow_fire = true,
	player_combat_weapon_repeating_crossbow_special_fire = true,
	player_combat_weapon_repeating_crossbow_reload = true,
}

mod.sound_event_filters[TEMPLATE_NAME] = function (event_name)
	return MUTED_SOUNDS[event_name] == true
end

-- These flow events would start the game's effects on the rocket's unit, so they are dropped.
mod.init_flow_event_filters.rocket = function (event_name)
	return event_name == "lua_projectile_init" or event_name == "lua_trail" or event_name == "vfx_critical_strike"
end

-- Adds a rocket's mesh, corona and smoke, on every machine.
mod.skin_init_callbacks.rocket = function (projectile)
	local owner_unit = projectile._owner_unit

	add_visual(projectile)

	if not utils.is_local_player_unit(owner_unit) then
		remote_shot(owner_unit)
	end
end

-- Returns the way the surface of an explosion faces. The rocket flew into the surface, so this is against its flight, or the normal
-- that a ray along the flight finds.
local function surface_normal(world, position, rotation)
	local forward = Quaternion.forward(rotation)
	local physics_world = World.get_data(world, "physics_world")
	local hit, _, _, normal = PhysicsWorld.immediate_raycast(physics_world, position - forward * 0.5, forward, 1, "closest", "collision_filter", "filter_ai_line_of_sight_check")

	if hit and normal and Vector3.length(normal) > 0.5 then
		return Vector3.normalize(normal)
	end

	return -forward
end

-- Draws the explosion of a rocket, on every machine. The game's own effects of it are not made. Like UT's, the explosion sits a
-- little way off the surface, or the surface would cut the fireballs.
mod.skin_explosion_callbacks.ut_rocket_explosion = function (world, position, rotation)
	local normal = surface_normal(world, position, rotation)
	local center = position + normal * (CONFIG.explosion_lift * UNIT)

	skin_api.play_sound_at("ut_rocket_explosion_3d", center)

	if CONFIG.explosion_effect then
		mod.effects.create(world, CONFIG.explosion_effect, position, rotation)
	end

	particles.sprite({
		attenuation = 0,
		color = {
			1,
			1,
			1,
		},
		growth = CONFIG.explosion_flash_growth * UNIT,
		intensity = CONFIG.explosion_flash_intensity,
		life = CONFIG.explosion_flash_life,
		position = center,
		size = CONFIG.explosion_flash_size * UNIT,
		spin = (math.random() * 2 - 1) * 0.12,
		texture = "explosion_flash",
	})

	-- The fireballs. Each plays the 16 frames of its sheet (one of two, the same for all three) as a sprite for each frame, one over
	-- the other. They start one after another.
	local sheet = math.random(2) == 1 and "explosion_a_" or "explosion_b_"
	local frames = CONFIG.explosion_fire_frames

	for index = 0, CONFIG.explosion_fire_count - 1 do
		local life = random_between(CONFIG.explosion_fire_life)
		local start = index * CONFIG.explosion_fire_gap
		local size = random_between(CONFIG.explosion_fire_size) * UNIT
		local fire_center = center + random_direction() * (CONFIG.explosion_fire_spread * UNIT)
		local angle = math.random() * 360

		for frame = 0, frames - 1 do
			-- The sprites are blended, not added to the screen, because the later frames are dark, the soot of the fire, and only
			-- blending shows that.
			-- A frame fades in over one frame's time on top of the previous frame. The previous frame stays until the new one is
			-- fully there, and then goes. So no frame is ever less than whole under the next, and the fireball is never thin. The
			-- last frame fades out.
			local frame_time = life / frames

			particles.sprite({
				additive = 0,
				angle = angle,
				color = CONFIG.explosion_fire_color,
				intensity = CONFIG.explosion_fire_intensity,
				delay = start + frame * frame_time,
				fade_in = frame_time,
				fade_out = frame == frames - 1 and frame_time or 2 * frame_time - 0.001,
				life = 2 * frame_time,
				position = fire_center,
				size = size,
				texture = sheet .. (frame % 4 * 4 + math.floor(frame / 4)),
			})
		end
	end
end
