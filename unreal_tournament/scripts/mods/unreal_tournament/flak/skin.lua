local mod = get_mod("unreal_tournament")

-- Flak Cannon skin: the Flak Cannon always looks and sounds like UT2004's, in the player's own first person view and in the hand of every
-- character. The Weapon Skins setting does not apply to it.
-- The model (Weapons.Flak_1st), its placement, animations, bob and third person are handled by weapon_skin.lua. This file handles what is
-- specific to the Flak Cannon: the muzzle flash, the chunks and the shell in flight, their explosion and the sounds. The gameplay is in
-- flak_cannon.lua. This file only draws it, and is told what happens through the hook tables in hooks.lua.
--
-- The game's own units of the chunks and of the shell are what is flying (they are the gameplay), their effects are not started and
-- what UT has is drawn at them: the mesh of the chunk with its streak (FlakTrail), the mesh of the shell with its gold glow and smoke
-- (FlakShellTrail, FlakGlow). The explosion is FlashExplosion, with the game's own explosion played along with it. The shot sound of the blunderbuss is made by its
-- animation, which is not played on the first person unit while the skin is on.
--
-- The assets were made with unreal_tournament/tools/asset_conversion.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local animations = mod:dofile("scripts/mods/unreal_tournament/flak/skin_animations")
local particles = mod.skin_particles

local TEMPLATE_NAME = mod.items.weapons.flak_cannon.template
local SETTING_ID = "flak_cannon"

-- The place of the bone of the flak shell that is loaded in the chamber, and of the hammer that pushes it, in the animations' bones
local SHELL_BONE
local HAMMER_BONE

for index, name in ipairs(animations.bones) do
	if name == "b_bone_flak01" then
		SHELL_BONE = index
	elseif name == "b_bone_hammer01" then
		HAMMER_BONE = index
	end
end

-- The frames of the Fire animation in which the next shell slides into the chamber, which is what loading one into an empty chamber plays
local CHAMBER_LOAD_FIRST = 8
local CHAMBER_LOAD_LAST = 21

local CONFIG = {
	meters_per_uu = 0.02, -- the Unreal unit of the world, in meters (a player is 88 units high)
	-- FlakMuzFlash1st: the flash of a shot (a mesh of 28 units across, DrawScale 2.2, growing 7 a second; here a sprite)
	muzzle_size = 90,
	muzzle_growth = 120,
	muzzle_life = 0.12,
	-- FlakMuzFlash1st (the flash of the player's own view): a mesh of 56 units across, spiked like a star and pointing along the barrel. It is
	-- this many times the mesh at the start and at the end of its life, which is muzzle_life.
	flash_mesh_start = 2.6,
	flash_mesh_end = 3.8,
	flash_mesh_brightness = 1.5,
	-- FlakChunk: the mesh and FlakTrail. The trail is a piece of streak for each frame of the chunk's path, which fades out in
	-- chunk_trail_seconds, so it follows the path and bends where the chunk bounces.
	chunk_trail_seconds = 0.1,
	chunk_scale = 0.75, -- of the converted mesh
	-- A piece is made at most this often (seconds). One for every frame would use up the particles when the frame rate is high, and the
	-- trail would stop growing.
	chunk_trail_step = 1 / 60,
	chunk_trail_width = 0.1, -- m
	chunk_trail_intensity = 2,
	-- A piece stays at full brightness for this share of its life, and fades out over the rest
	chunk_trail_hold = 0.4,
	-- The glow around the chunk: it is drawn a little behind the chunk, so the chunk's mesh covers its middle, and is dim so that it
	-- stays a halo
	chunk_glow_size = 0.6, -- m
	chunk_glow_intensity = 1.2,
	chunk_glow_behind = 0.08, -- m, away from the camera
	-- A chunk that has gone cold and landed stays on the ground this long (FlakChunk.Landed sets its life span to 1)
	chunk_lie_seconds = 1,
	-- FlakShell: the mesh, FlakGlow (a gold sprite) and FlakShellTrail (smoke, 0.5 to 0.6 s, 20 to 35 units, growing 15 a second)
	shell_glow_size = 22, -- UT units, a little wider than the shell's mesh so that a ring of it shows around the mesh
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
	shell_sound_seconds = 2.11, -- how long the loop of the shell (BFlakCannonProjectile) is
	-- FlashExplosion (150 units, growing 500, 0.25 s)
	explosion_flash_size = 150,
	explosion_flash_growth = 500,
	explosion_flash_life = 0.25,
	explosion_flash_intensity = 0.5,
	-- The game's own explosion, with its smoke and the mark it leaves, played with the flash (only if the game has it loaded)
	explosion_effect = "fx/wpnfx_frag_grenade_impact",
	-- A shot that is seen of another player, by the first chunk of it: more than this far apart in time is another shot
	shot_gap = 0.25,
	inspect_pose_speed = 5, -- how fast the model moves to the inspect pose and back, per second
	inspect_sway = 5, -- degrees of yaw each way while inspecting
	inspect_sway_speed = 1.8, -- radians per second
}

local UNIT = CONFIG.meters_per_uu

local skin_api

-- What the game's own sound of the explosion is taken away for while the skin is on (the skin plays its own)
local explosion_override = {
	"ut_flak_shell_explosion",
	"sound_event_name",
}

local function apply_template_overrides()
	local explosion = ExplosionTemplates[explosion_override[1]].explosion
	local key = explosion_override[2]

	if skin_api.enabled() and explosion[key] then
		explosion_override[3] = explosion[key]
		explosion[key] = nil
	elseif not skin_api.enabled() and explosion_override[3] then
		explosion[key] = explosion_override[3]
		explosion_override[3] = nil
	end
end

local function give_back_overrides()
	if explosion_override[3] then
		ExplosionTemplates[explosion_override[1]].explosion[explosion_override[2]] = explosion_override[3]
		explosion_override[3] = nil
	end
end

-- What flies: { unit = the mesh, game_unit = the projectile's, projectile = its extension, kind, previous = where it was }
local visuals = {}

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

local function destroy_visual(visual)
	if Unit.alive(visual.unit) then
		World.destroy_unit(visual.world, visual.unit)
	end
end

-- All of them go with the level, and with the mod (a unit of the mod's package that is alive when the package is unloaded crashes the game)
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

			-- The game's unit may not be where it starts out when the visual is made, so the path starts from where it is on the first frame
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

			-- (FlakShell.PostBeginPlay flies the shell upside down: Roll = 32768)
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

-- The mesh of a projectile, drawn at the game's unit (the unit itself is not shown)
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

-- A flash at the muzzle (where the character holds the mesh, or the model of the player's own view)
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

-- The flash of the player's own view: UT's mesh, pointing the way the camera looks, turned by a random angle about it
local function first_person_flash(follow, scale)
	local _, camera_rotation = utils.camera_pose()

	if not camera_rotation then
		return muzzle_flash(follow, scale)
	end

	-- (the mesh is made at 0.02 m to a UT unit, and is sized as the view's units are)
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

-- A shot that another player's machine sees: the flash and the sound from the end of the barrel of the mesh in their hand, once for the
-- chunks of a shot that come together
local last_remote_shot = {}

local function remote_shot(owner_unit, sound_event)
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
		skin_api.play_sound_at(sound_event, muzzle)
	end
end

skin_api = mod.weapon_skin.new({
	id = SETTING_ID,
	-- There is no setting for this: the skin is always on.
	always = true,
	name = "flak",
	template = TEMPLATE_NAME,
	unit_name = "units/ut/flak/flak_cannon",
	animations = animations,
	muzzle_node = "b_bone_flash",
	-- The model was converted at this many meters per UT unit (tools/asset_conversion/convert_weapon.py), the distance scale is how
	-- many meters of forward are a UT unit of it in the view
	model_meters_per_unit = 0.0125,
	meters_per_unit = 0.01,
	-- FlakCannon.uc: the mesh lies sideways, which the yaw of the pivot turns to the front
	display_fov = 60,
	draw_scale = 1,
	offset_forward = -7,
	offset_right = 8,
	offset_up = 0,
	pivot_yaw = 16884 / 65536 * 360,
	pivot_roll = 200 / 65536 * 360,
	bob_damping = 1.4,
	-- The inspect pose: the cannon is brought forward and up, and then turned to the left about the grip, until it is across the view like the
	-- Shock Rifle's: its left side to the view, the muzzle to the left and a little up, the back lower and nearer. The grip is the point of
	-- the model that is in the hand (UT units from its origin, in the axes of the view). The turn starts when the cannon is 35% of the way.
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
	-- WeaponStaticMesh.FlakCannonPickup (DrawScale 0.55): its barrel is along the mesh's own Y, and the grip is under the back of it
	third_person = {
		id = SETTING_ID,
		always = true,
		template = TEMPLATE_NAME,
		unit_name = "units/ut/flak/pickup",
		-- (the game links the blunderbuss, the crossbow and the Drakegun to the left hand's node, AttachmentNodeLinking.rifles)
		hand_node = "j_leftweaponattach",
		meters_per_unit = 0.011,
		-- UT's third person mesh is as long as the pickup's would be without its DrawScale: about half of the height of a player's mesh
		-- (113 units against 233), which is 0.85 m for a character of 1.8 m
		scale = 0.7,
		grip_right = 42,
		grip_forward = 0,
		grip_up = -6,
		yaw = -60,
		pitch = 0,
		roll = 0,
		-- In the world the cannon moves with the game's Blunderbuss, which the game animates with the arms. It is placed as pointing the way the
		-- character faces first (as the hero screen is), and the unit's turn from that is taken a second after it is held. With the character
		-- not standing as it should then, /skin flak_cannon 3p follow_recalibrate 1 takes it again, and follow_game_unit 0 turns it off.
		follow_game_unit = 1,
		follow_calibrate_seconds = 1,
		muzzle_right = -56,
		muzzle_forward = 0,
		muzzle_up = 12,
		menu_yaw = 180,
	},
	on_create = function ()
		skin_api.play_sound("ut_flak_select")
	end,
	on_update = function (skin, dt)
		-- UT puts the weapon away when it has no ammo, here it is carried on: there is no shell in the chamber then. When there is ammo again
		-- a shell is loaded: it slides in and the hammer follows, as the next shell does after a shot.
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

		-- With no ammo left the shot does not load the next shell: from the frame where it would slide in, the shell and the hammer are
		-- as the animation ends
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
	on_refresh = apply_template_overrides,
	on_give_back = function ()
		give_back_overrides()
		clear_visuals()
	end,
	on_update_always = update_visuals,
	on_level_exit = function ()
		clear_visuals()
		table.clear(last_remote_shot)
	end,
})

local third_person = skin_api.third_person

-- The shots: the animation and the flash as the action of the shot starts (the blunderbuss shoots at once), the sound with them
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

-- The Blunderbuss's shot and reload sounds are part of its animations. The shot and reload animations are not played on the player's own
-- first person unit (the skin's model plays UT's animations instead). UT's weapon has no reload, but the game still reloads when ammo is
-- picked up or the weapon is wielded.
mod.first_person_animation_filters[TEMPLATE_NAME] = function (event)
	return skin_api.enabled() and (event == "attack_shoot" or event == "attack_shoot_last" or string.find(event, "reload", 1, true) ~= nil)
end

-- Also skip them on the character's own unit, which other players hear.
-- Inspecting is the game's own action, held with the key: the cannon is turned to show its side as long as it lasts
mod.inspect_callbacks.flak_skin = function (action, started)
	local skin = skin_api.state()

	if skin and utils.is_local_player_unit(action.owner_unit) then
		skin.inspecting = started
	end
end

mod.third_person_animation_filters[TEMPLATE_NAME] = function (event)
	return string.find(event, "reload", 1, true) ~= nil
end

-- The Blunderbuss's shot sound is played by its unit's flow as its animation plays on the characters: the others hear the Flak Cannon's
-- own sounds instead (see the remote shots)
mod.sound_event_filters[TEMPLATE_NAME] = function (event_name)
	return event_name == "player_combat_weapon_blunderbuss_fire"
end

-- The flow events of the game's units of the chunks and the shell start their effects as they are made: not while the skin is on
mod.init_flow_event_filters.flak = function (event_name)
	return skin_api.enabled() and (event_name == "lua_projectile_init" or event_name == "lua_trail" or event_name == "vfx_critical_strike")
end

-- A chunk (on every machine): the mesh and its streak
mod.skin_init_callbacks.ut_flak_chunk = function (projectile)
	if not skin_api.enabled() then
		return
	end

	local owner_unit = projectile._owner_unit
	local visual = add_visual(projectile, "chunk", "units/ut/flak/chunk")

	-- (the chunks of a shell's explosion are not a shot from the muzzle)
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

-- The shell (on every machine): the mesh, the gold glow and the smoke it leaves
mod.skin_init_callbacks.ut_flak_shell = function (projectile)
	if not skin_api.enabled() then
		return
	end

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

-- The explosion of the shell, on every machine: the game's own effects of it are not made while the skin is on (see flak_cannon.lua)
mod.skin_explosion_callbacks.ut_flak_shell_explosion = function (world, position, rotation)
	if not skin_api.enabled() then
		return
	end

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
