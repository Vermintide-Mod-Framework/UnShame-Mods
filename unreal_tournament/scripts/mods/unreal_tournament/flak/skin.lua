local mod = get_mod("unreal_tournament")

-- Flak Cannon skin: how UT2004's Flak Cannon looks and sounds.
--
-- weapon_skin.lua does the model, its placement and animations, the bob and the third person. This file does what is the Flak Cannon's
-- own: the muzzle flash, the chunks and the shell in flight, their explosion and the sounds. The gameplay is in flak_cannon.lua. This
-- file only draws it, and is told what happens through the hook tables in hooks.lua.
--
-- The game's units of the chunks and the shell still fly, since they are the gameplay. Their own effects are dropped, and UT's are drawn at
-- them: the chunk mesh with its streak (FlakTrail), and the shell mesh with its gold glow and smoke (FlakShellTrail, FlakGlow). The
-- explosion is FlashExplosion, with the game's explosion played along with it. The blunderbuss's shot sound is in its animation, which is
-- not played on the player's own first person unit.
--
-- The assets were made with tools/asset_conversion.

local utils = mod.utils
local animations = mod:dofile("scripts/mods/unreal_tournament/flak/skin_animations")
local particles = mod.skin_particles

local TEMPLATE_NAME = mod.items.weapons.flak_cannon.template
local SETTING_ID = "flak_cannon"

-- The indexes, in the animations' list of bones, of the bone of the flak shell loaded in the chamber and of the hammer that pushes it
local SHELL_BONE
local HAMMER_BONE

for index, name in ipairs(animations.bones) do
	if name == "b_bone_flak01" then
		SHELL_BONE = index
	elseif name == "b_bone_hammer01" then
		HAMMER_BONE = index
	end
end

-- The frames of the Fire animation where the next shell slides into the chamber. Loading a shell into an empty chamber plays them.
local CHAMBER_LOAD_FIRST = 8
local CHAMBER_LOAD_LAST = 21

local CONFIG = {
	-- FlakMuzFlash1st is the flash of a shot. In UT it is a mesh 28 units across (DrawScale 2.2) that grows 7 a second. Here it is a sprite.
	muzzle_size = 90,
	muzzle_growth = 120,
	muzzle_life = 0.12,
	-- FlakMuzFlash1st in the player's own view is a mesh 56 units across, spiked like a star and pointing along the barrel. Its size
	-- is this many times the mesh at the start of its life and at the end of it, which is muzzle_life.
	flash_mesh_start = 2.6,
	flash_mesh_end = 3.8,
	flash_mesh_brightness = 1.5,
	-- FlakChunk is the mesh and FlakTrail. The trail is a piece of streak for each frame of the chunk's path. Each piece fades out in
	-- chunk_trail_seconds, so the trail follows the path and bends where the chunk bounces.
	chunk_trail_seconds = 0.1,
	chunk_scale = 0.75, -- scale of the converted mesh
	-- A piece is made at most this often, in seconds. A piece every frame would use up the particles at a high frame rate, and the
	-- trail would stop growing.
	chunk_trail_step = 1 / 60,
	chunk_trail_width = 0.1, -- m
	chunk_trail_intensity = 2,
	-- A piece stays at full brightness for this share of its life, and fades out over the rest of it
	chunk_trail_hold = 0.4,
	-- The glow around the chunk is drawn a little behind the chunk, so the chunk's mesh covers its middle. It is dim, so it stays a
	-- halo.
	chunk_glow_size = 0.6, -- m
	chunk_glow_intensity = 1.2,
	chunk_glow_behind = 0.08, -- m, away from the camera
	-- A chunk that has gone cold and landed stays on the ground for this many seconds (FlakChunk.Landed sets its life span to 1)
	chunk_lie_seconds = 1,
	-- FlakShell is the mesh, FlakGlow (a gold sprite) and FlakShellTrail (smoke that lasts 0.5 to 0.6 s, is 20 to 35 units wide, and
	-- grows 15 a second)
	shell_glow_size = 22, -- UT units, a little wider than the shell's mesh, so that a ring of glow shows around the mesh
	shell_glow_behind = 0.1, -- m, away from the camera, so that the mesh covers the middle of the glow
	shell_glow_color = {
		1,
		0.75,
		0.3,
	},
	shell_glow_intensity = 1.5,
	shell_smoke_interval = 0.02,
	shell_smoke_life = 0.55,
	shell_smoke_size = 40,
	shell_smoke_growth = 30,
	shell_smoke_color = {
		0.3,
		0.28,
		0.26,
	},
	shell_sound_seconds = 2.11, -- length of the shell's sound loop (BFlakCannonProjectile)
	-- FlashExplosion: 150 units wide, growing 500 a second, lasting 0.25 s
	explosion_flash_size = 150,
	explosion_flash_growth = 500,
	explosion_flash_life = 0.25,
	explosion_flash_intensity = 0.5,
	-- The game's own explosion, with its smoke and the mark it leaves, is played together with the flash
	explosion_effect = mod.effects.game_effect("fx/wpnfx_frag_grenade_impact"),
	-- Another player's shot is recognized by its first chunk. Chunks that start further apart than this many seconds are another shot.
	shot_gap = 0.25,
	inspect_pose_speed = 5, -- how fast the model moves to the inspect pose and back, per second
	inspect_sway = 5, -- degrees of yaw each way while inspecting
	inspect_sway_speed = 1.8, -- radians per second
}

local UNIT = utils.UT_UNIT

local skin_api

-- The projectiles in flight, each as { unit = the mesh, game_unit = the projectile's unit, projectile = its extension, kind, previous =
-- where it was }
local visuals = {}

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
end

local function update_visuals(dt)
	for i = #visuals, 1, -1 do
		local visual = visuals[i]
		local game_unit = visual.game_unit
		local projectile = visual.projectile
		local lying = projectile._ut_flak_cold and projectile._stop_impacts and Unit.alive(visual.unit)

		if lying then
			visual.lie_time = (visual.lie_time or CONFIG.chunk_lie_seconds) - dt
		end

		if (lying and visual.lie_time <= 0) or (not lying and (not Unit.alive(game_unit) or projectile._stop_impacts or not Unit.alive(visual.unit))) then
			destroy_visual(visual)
			table.remove(visuals, i)
		elseif not lying then
			local position = Unit.world_position(game_unit, 0)

			-- The game's unit may not be at its starting place yet when the visual is made, so the path starts from where the unit is on
			-- the first frame.
			if not visual.placed then
				visual.placed = true

				visual.previous:store(position)
				visual.trail_from:store(position)
			end

			local previous = visual.previous:unbox()
			local moved = position - previous

			visual.previous:store(position)
			Unit.set_local_position(visual.unit, 0, position)

			if Vector3.length(moved) > 0.0001 then
				visual.direction:store(Vector3.normalize(moved))
				visual.speed = Vector3.length(moved) / math.max(dt, 0.0001)
			end

			if visual.kind == "chunk" and not projectile._ut_flak_cold then
				visual.trail_time = visual.trail_time + dt

				if visual.trail_time >= CONFIG.chunk_trail_step then
					local trail_from = visual.trail_from:unbox()

					visual.trail_time = math.min(visual.trail_time - CONFIG.chunk_trail_step, CONFIG.chunk_trail_step)
					visual.trail_from:store(position)

					if Vector3.length(position - trail_from) > 0.0001 then
						particles.beam({
							color = {
								1,
								1,
								1,
							},
							fade_in = 0,
							fade_out = CONFIG.chunk_trail_seconds * CONFIG.chunk_trail_hold,
							from = trail_from,
							intensity = CONFIG.chunk_trail_intensity,
							life = CONFIG.chunk_trail_seconds,
							size = CONFIG.chunk_trail_width,
							texture = "flak_trail",
							to = position,
						})
					end
				end
			end

			local rotation = Quaternion.look(visual.direction:unbox(), Vector3.up())

			-- UT flies the shell upside down (FlakShell sets Roll = 32768)
			if visual.kind == "shell" then
				rotation = Quaternion.multiply(rotation, Quaternion.axis_angle(Vector3.forward(), math.pi))
			end

			Unit.set_local_rotation(visual.unit, 0, rotation)

			if visual.kind == "shell" then
				visual.smoke_time = visual.smoke_time - dt
				visual.sound_time = visual.sound_time - dt

				if visual.smoke_time <= 0 then
					visual.smoke_time = CONFIG.shell_smoke_interval

					particles.sprite({
						additive = 0,
						color = CONFIG.shell_smoke_color,
						growth = CONFIG.shell_smoke_growth * UNIT,
						intensity = 1.5,
						life = CONFIG.shell_smoke_life,
						position = position,
						size = CONFIG.shell_smoke_size * UNIT,
						spin = (math.random() * 2 - 1) * 0.3,
						texture = "smoke",
					})
				end

				if visual.sound_time <= 0 then
					visual.sound_time = CONFIG.shell_sound_seconds

					skin_api.play_sound_at("ut_flak_shell_3d", position)
				end
			end
		end
	end
end

-- Adds the mesh of a projectile, drawn at the game's unit. The unit itself is not shown.
local function add_visual(projectile, kind, unit_name)
	local world = Managers.world:world("level_world")
	local game_unit = projectile._projectile_unit
	local position = Unit.world_position(game_unit, 0)
	local unit = World.spawn_unit(world, unit_name, position)

	Unit.set_unit_visibility(game_unit, false)

	if kind == "chunk" then
		Unit.set_local_scale(unit, 0, Vector3(CONFIG.chunk_scale, CONFIG.chunk_scale, CONFIG.chunk_scale))
	end

	local visual = {
		direction = Vector3Box(Vector3.forward()),
		game_unit = game_unit,
		kind = kind,
		previous = Vector3Box(position),
		projectile = projectile,
		smoke_time = 0,
		sound_time = 0,
		speed = 0,
		trail_from = Vector3Box(position),
		trail_time = 0,
		unit = unit,
		world = world,
	}

	visuals[#visuals + 1] = visual

	return visual
end

-- Shows a flash at the muzzle, either of the mesh in the character's hand or of the model in the player's own view.
local function muzzle_flash(follow, scale)
	particles.sprite({
		color = {
			1,
			1,
			1,
		},
		follow = follow,
		growth = CONFIG.muzzle_growth * scale,
		life = CONFIG.muzzle_life,
		size = CONFIG.muzzle_size * scale,
		spin = (math.random() * 2 - 1) * 0.2,
		texture = "flak_muzzle",
	})
end

-- Shows the flash of the player's own view. It is UT's mesh, pointing the way the camera looks and turned by a random angle about
-- that direction.
local function first_person_flash(follow, scale)
	local _, camera_rotation = utils.camera_pose()

	if not camera_rotation then
		return muzzle_flash(follow, scale)
	end

	-- The mesh is made at 0.02 m per UT unit, and it is scaled to the size of the view's units.
	local factor = scale / UNIT

	particles.mesh({
		brightness = function (fraction)
			return CONFIG.flash_mesh_brightness * (1 - fraction)
		end,
		color = {
			1,
			1,
			1,
		},
		follow = follow,
		life = CONFIG.muzzle_life,
		rotation = camera_rotation,
		scale = function (fraction)
			return (CONFIG.flash_mesh_start + (CONFIG.flash_mesh_end - CONFIG.flash_mesh_start) * fraction) * factor
		end,
		spin = (math.random() * 2 - 1) * 0.5,
		spin_axis = Vector3(0, 1, 0),
		texture = "flak_flash",
		unit = "units/ut/fx/flak_flash_mesh",
	})
end

-- A shot by another player, as seen on this machine: the flash and the sound come from the end of the barrel of the mesh in their
-- hand. They play once for all the chunks of a shot that start together.
local remote_shots = utils.shot_grouping(CONFIG.shot_gap)

local function remote_shot(owner_unit, sound_event)
	if not remote_shots.is_new_shot(owner_unit) then
		return
	end

	local muzzle = skin_api.third_person.muzzle_position(owner_unit)

	muzzle_flash(function ()
		return skin_api.third_person.muzzle_position(owner_unit)
	end, skin_api.third_person.meters_per_unit)

	if muzzle then
		skin_api.play_sound_at(sound_event, muzzle)
	end
end

skin_api = mod.weapon_skin.new({
	id = SETTING_ID,
	name = "flak",
	template = TEMPLATE_NAME,
	unit_name = "units/ut/flak/flak_cannon",
	animations = animations,
	muzzle_node = "b_bone_flash",
	-- model_meters_per_unit is the meters per UT unit at which the model was converted (tools/asset_conversion/convert_weapon.py).
	-- meters_per_unit is the distance scale: the meters of forward in the view that one UT unit of the model takes up.
	model_meters_per_unit = 0.0125,
	meters_per_unit = 0.01,
	-- FlakCannon.uc. The mesh lies sideways, and the pivot's yaw turns it to the front.
	display_fov = 60,
	draw_scale = 1,
	offset_forward = -7,
	offset_right = 8,
	offset_up = 0,
	pivot_yaw = 16884 / 65536 * 360,
	pivot_roll = 200 / 65536 * 360,
	bob_damping = 1.4,
	-- The inspect pose brings the cannon forward and up, and then turns it to the left about the grip. It ends up across the view like
	-- the Shock Rifle: its left side towards the player, the muzzle pointing left and a little up, and the back lower and nearer. The grip
	-- is the point of the model that is in the hand (in UT units from the model's origin, in the view's axes). The turn starts when the
	-- cannon is 35% of the way there.
	inspect_pose_right = -6.2,
	inspect_pose_forward = 4,
	inspect_pose_up = 0.2,
	inspect_pose_roll = 16,
	inspect_pose_pitch = 4,
	inspect_pose_yaw = 55,
	inspect_turn_start = 0.35,
	inspect_pivot_right = 24.7,
	inspect_pivot_forward = 55,
	inspect_pivot_up = -38.7,
	-- UT's third person mesh of the weapon (FlakAttachment's Weapons.Flak_3rd) at UT's size in a player's hand (DrawScale 0.4). Its origin
	-- is the grip, and its barrel runs along its forward, to the muzzle (the mesh's tip bone).
	third_person = {
		id = SETTING_ID,
		template = TEMPLATE_NAME,
		unit_name = "units/ut/flak/third_person",
		-- The game links the blunderbuss, the crossbow and the Drakegun to the left hand's node (AttachmentNodeLinking.rifles).
		hand_node = "j_leftweaponattach",
		meters_per_unit = 0.02 * 0.4,
		scale = 1,
		-- (moved back and up from the mesh's origin, set in the game)
		grip_right = 0,
		grip_forward = 20,
		grip_up = -8,
		yaw = 0,
		pitch = 0,
		roll = 0,
		-- In the world the cannon is turned as the game's Blunderbuss in the hand is, which the game animates with the arms
		follow_game_unit = 2,
		follow_calibrate_seconds = 1,
		muzzle_right = 0,
		muzzle_forward = 98,
		muzzle_up = 8,
		menu_yaw = -90,
	},
	on_create = function ()
		skin_api.play_sound("ut_flak_select")
	end,
	on_update = function (skin, dt)
		-- UT puts the weapon away when it has no ammo, but here it stays in hand, with no shell in the chamber. When there is ammo
		-- again a shell is loaded: it slides in and the hammer follows, as the next shell does after a shot.
		local was_out_of_ammo = skin.out_of_ammo

		skin.out_of_ammo = utils.local_ranged_out_of_ammo()

		if was_out_of_ammo and not skin.out_of_ammo then
			skin.chamber_load = CHAMBER_LOAD_FIRST / animations.animations.Fire.rate

			skin_api.play_sound("ut_flak_load")
		elseif skin.chamber_load then
			skin.chamber_load = skin.chamber_load + dt

			if skin.chamber_load * animations.animations.Fire.rate >= CHAMBER_LOAD_LAST then
				skin.chamber_load = nil
			end
		end

		skin.inspect_pose = (skin.inspect_pose or 0) + ((skin.inspecting and 1 or 0) - (skin.inspect_pose or 0)) * math.min(1, CONFIG.inspect_pose_speed * dt)
		skin.inspect_time = skin.inspecting and (skin.inspect_time or 0) + dt or 0
		skin.extra_yaw = skin.inspect_pose * CONFIG.inspect_sway * math.sin(skin.inspect_time * CONFIG.inspect_sway_speed)
	end,
	on_pose = function (skin, pose)
		if skin.chamber_load then
			local fire = animations.animations.Fire
			local position = math.min(skin.chamber_load * fire.rate, #fire.frames - 1)
			local index = math.floor(position)
			local fraction = position - index
			local first, second = fire.frames[index + 1], fire.frames[math.min(index + 2, #fire.frames)]

			for _, bone in ipairs({ SHELL_BONE, HAMMER_BONE }) do
				local o = (bone - 1) * 7

				for i = 1, 7 do
					pose[o + i] = first[o + i] + (second[o + i] - first[o + i]) * fraction
				end
			end
		end

		-- With no ammo left the shot loads no next shell: from the frame where it would slide in, the shell and the hammer stay at rest
		local animation = animations.animations[skin.animation]

		if skin.out_of_ammo and animation and (skin.animation == "Fire" or skin.animation == "AltFire") and skin.time * animation.rate >= CHAMBER_LOAD_FIRST then
			local rest = animation.frames[#animation.frames]

			for _, bone in ipairs({ SHELL_BONE, HAMMER_BONE }) do
				local o = (bone - 1) * 7

				for i = 1, 7 do
					pose[o + i] = rest[o + i]
				end
			end
		end

		skin.node_scales = skin.node_scales or {}
		skin.node_scales[SHELL_BONE] = skin.out_of_ammo and Vector3(0.001, 0.001, 0.001) or nil
	end,
	on_give_back = clear_visuals,
	on_update_always = update_visuals,
	on_level_exit = function ()
		clear_visuals()
		remote_shots.clear()
	end,
})

local third_person = skin_api.third_person

-- Handles the player's shots. The animation, the flash and the sound all start when the shot's action starts, because the blunderbuss
-- shoots at once.
mod.shotgun_start_callbacks.flak_skin = function (action, new_action)
	local skin = skin_api.state()

	if not skin or not utils.is_local_player_unit(action.owner_unit) or not (new_action.ut_flak_chunks or new_action.ut_flak_shell) then
		return
	end

	local owner_unit = action.owner_unit
	local in_third_person = third_person.shows_weapon(owner_unit)

	skin_api.play(new_action.ut_flak_chunks and "Fire" or "AltFire")
	skin_api.play_sound(new_action.ut_flak_chunks and "ut_flak_fire" or "ut_flak_alt_fire")
	local flash = in_third_person and muzzle_flash or first_person_flash

	flash(function ()
		if in_third_person then
			return third_person.muzzle_position(owner_unit)
		end

		return skin_api.state() == skin and skin_api.muzzle_position() or nil
	end, in_third_person and third_person.meters_per_unit or skin.unit_scale)
end

-- The Blunderbuss's shot and reload sounds are part of its animations, so those animations are not played on the player's own first
-- person unit. The skin's model plays UT's animations instead. UT's weapon has no reload, but the game still reloads when ammo is
-- picked up or the weapon is wielded.
mod.first_person_animation_filters[TEMPLATE_NAME] = function (event)
	return event == "attack_shoot" or event == "attack_shoot_last" or string.find(event, "reload", 1, true) ~= nil
end

-- Inspecting is the game's own action, held with the key. The cannon is turned to show its side for as long as it lasts.
mod.inspect_callbacks.flak_skin = function (action, started)
	local skin = skin_api.state()

	if skin and utils.is_local_player_unit(action.owner_unit) then
		skin.inspecting = started
	end
end

-- The reload animation is not played on the characters, because the cannon has no reload.
mod.third_person_animation_filters[TEMPLATE_NAME] = function (event)
	return string.find(event, "reload", 1, true) ~= nil
end

-- The Blunderbuss's unit plays its shot sound in third person. It is muted, so the others hear the Flak Cannon's own sounds.
mod.sound_event_filters[TEMPLATE_NAME] = function (event_name)
	return event_name == "player_combat_weapon_blunderbuss_fire"
end

-- These flow events would start the game's effects on the chunks and the shell, so they are dropped.
mod.init_flow_event_filters.flak = function (event_name)
	return event_name == "lua_projectile_init" or event_name == "lua_trail" or event_name == "vfx_critical_strike"
end

-- Adds the mesh and the streak of a chunk, on every machine.
mod.skin_init_callbacks.ut_flak_chunk = function (projectile)
	local owner_unit = projectile._owner_unit
	local visual = add_visual(projectile, "chunk", "units/ut/flak/chunk")

	-- The chunks of a shell's explosion are not a shot from the muzzle, so they play no shot sound.
	if not utils.is_local_player_unit(owner_unit) and not projectile._current_action.ut_flak_burst then
		remote_shot(owner_unit, "ut_flak_fire_3d")
	end

	particles.sprite({
		color = {
			1,
			1,
			1,
		},
		fade_in = 0,
		follow = function ()
			if Unit.alive(visual.game_unit) and not visual.projectile._stop_impacts and not visual.projectile._ut_flak_cold then
				local position = Unit.world_position(visual.game_unit, 0)
				local camera_position = utils.camera_pose()

				if camera_position then
					position = position + Vector3.normalize(position - camera_position) * CONFIG.chunk_glow_behind
				end

				return position
			end
		end,
		intensity = CONFIG.chunk_glow_intensity,
		life = 2.7,
		size = CONFIG.chunk_glow_size,
		texture = "flak_chunk_glow",
	})
end

-- Adds the mesh of the shell, its gold glow and the smoke it leaves, on every machine.
mod.skin_init_callbacks.ut_flak_shell = function (projectile)
	local owner_unit = projectile._owner_unit
	local visual = add_visual(projectile, "shell", "units/ut/flak/shell")

	if not utils.is_local_player_unit(owner_unit) then
		remote_shot(owner_unit, "ut_flak_alt_fire_3d")
	end

	particles.sprite({
		color = CONFIG.shell_glow_color,
		fade_in = 0,
		follow = function ()
			if Unit.alive(visual.game_unit) and not visual.projectile._stop_impacts then
				local position = Unit.world_position(visual.game_unit, 0)
				local camera_position = utils.camera_pose()

				if camera_position then
					position = position + Vector3.normalize(position - camera_position) * CONFIG.shell_glow_behind
				end

				return position
			end
		end,
		intensity = CONFIG.shell_glow_intensity,
		life = 6,
		size = CONFIG.shell_glow_size * UNIT,
		texture = "flak_shell_glow",
	})
end

-- The explosion of the shell, on every machine. The game's own effects of it are not made (see flak_cannon.lua).
mod.skin_explosion_callbacks.ut_flak_shell_explosion = function (world, position, rotation)
	skin_api.play_sound_at("ut_flak_explosion_3d", position)
	mod.effects.create(world, CONFIG.explosion_effect, position, rotation)

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
		position = position,
		size = CONFIG.explosion_flash_size * UNIT,
		spin = (math.random() * 2 - 1) * 0.12,
		texture = "explosion_flash",
	})
end
