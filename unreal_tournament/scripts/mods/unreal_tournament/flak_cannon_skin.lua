local mod = get_mod("unreal_tournament")

-- Flak Cannon skin (the Weapon Skins setting): the Flak Cannon is UT2004's, in the player's own first person view and in the hand of
-- every character. The model (Weapons.Flak_1st, skeletal: the barrel, the hammer, the hydraulics, the teeth), its placement and
-- animations, the bob and the third person are weapon_skin.lua's; this file is what is the Flak Cannon's: the muzzle flash, the
-- chunks and the shell as they fly, their explosion, and the sounds. The gameplay is flak_cannon.lua's, this only draws it
-- differently, and is told what happens through the hook tables of hooks.lua.
--
-- The game's own units of the chunks and of the shell are what is flying (they are the gameplay), their effects are not started and
-- what UT has is drawn at them: the mesh of the chunk with its streak (FlakTrail), the mesh of the shell with its gold glow and smoke
-- (FlakShellTrail, FlakGlow). The explosion is FlakExplosion and FlashExplosion. The shot sound of the blunderbuss is made by its
-- animation, which is not played on the first person unit while the skin is on.
--
-- The assets were made with unreal_tournament/tools/asset_conversion.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local animations = mod:dofile("scripts/mods/unreal_tournament/flak_cannon_skin_animations")
local particles = mod.skin_particles

local TEMPLATE_NAME = "blunderbuss_template_1"
local SETTING_ID = "flak_cannon"

local CONFIG = {
	meters_per_uu = 0.02, -- the Unreal unit of the world, in meters (a player is 88 units high)
	-- FlakMuzFlash1st: the flash of a shot (a mesh of 28 units across, DrawScale 2.2, growing 7 a second; here a sprite)
	muzzle_size = 90,
	muzzle_growth = 120,
	muzzle_life = 0.12,
	-- FlakChunk: the mesh and FlakTrail (additive, 0.1 s of the path of the chunk, 2 to 3 units wide)
	chunk_trail_seconds = 0.1,
	chunk_trail_length_max = 3, -- m
	chunk_trail_width = 0.1, -- m
	-- FlakShell: the mesh, FlakGlow (a gold sprite) and FlakShellTrail (smoke, 0.5 to 0.6 s, 20 to 35 units, growing 15 a second)
	shell_glow_size = 40,
	shell_glow_color = {
		1,
		0.75,
		0.3,
	},
	shell_smoke_interval = 0.04,
	shell_smoke_life = 0.55,
	shell_smoke_size = 20,
	shell_smoke_growth = 15,
	shell_smoke_color = {
		0.55,
		0.5,
		0.45,
	},
	shell_sound_seconds = 2.11, -- how long the loop of the shell (BFlakCannonProjectile) is
	-- FlakExplosion (5 puffs of smoke, 91 to 161 units, 0.9 to 1.8 s, rising) and FlashExplosion (150 units, growing 500, 0.25 s)
	explosion_puffs = 5,
	explosion_puff_size = {
		91,
		161,
	},
	explosion_puff_life = {
		0.9,
		1.8,
	},
	explosion_puff_spread = 55, -- units
	explosion_puff_rise = 0.4, -- m/s
	explosion_flash_size = 150,
	explosion_flash_growth = 500,
	explosion_flash_life = 0.25,
	explosion_star_size = 100,
	explosion_star_growth = 200,
	explosion_star_life = 0.5,
	-- A shot that is seen of another player, by the first chunk of it: more than this far apart in time is another shot
	shot_gap = 0.25,
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

		if not Unit.alive(game_unit) or visual.projectile._stop_impacts or not Unit.alive(visual.unit) then
			destroy_visual(visual)
			table.remove(visuals, i)
		else
			local position = Unit.world_position(game_unit, 0)
			local previous = visual.previous:unbox()
			local moved = position - previous

			visual.previous:store(position)
			Unit.set_local_position(visual.unit, 0, position)

			if Vector3.length(moved) > 0.0001 then
				visual.direction:store(Vector3.normalize(moved))
				visual.speed = Vector3.length(moved) / math.max(dt, 0.0001)
			end

			Unit.set_local_rotation(visual.unit, 0, Quaternion.look(visual.direction:unbox(), Vector3.up()))

			if visual.kind == "shell" then
				visual.smoke_time = visual.smoke_time - dt
				visual.sound_time = visual.sound_time - dt

				if visual.smoke_time <= 0 then
					visual.smoke_time = CONFIG.shell_smoke_interval

					particles.sprite({
						additive = 0,
						color = CONFIG.shell_smoke_color,
						growth = CONFIG.shell_smoke_growth * UNIT,
						intensity = 0.8,
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

	local visual = {
		direction = Vector3Box(Vector3.forward()),
		game_unit = game_unit,
		kind = kind,
		previous = Vector3Box(position),
		projectile = projectile,
		smoke_time = 0,
		sound_time = 0,
		speed = 0,
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
	-- WeaponStaticMesh.FlakCannonPickup (DrawScale 0.55): its barrel is along the mesh's own Y, and the grip is under the back of it
	third_person = {
		id = SETTING_ID,
		template = TEMPLATE_NAME,
		unit_name = "units/ut/flak/pickup",
		hand_node = "j_rightweaponattach",
		meters_per_unit = 0.011,
		scale = 0.5,
		grip_right = 45,
		grip_forward = 0,
		grip_up = -10,
		yaw = -90,
		pitch = 0,
		roll = 0,
		muzzle_right = -56,
		muzzle_forward = 0,
		muzzle_up = 12,
	},
	on_create = function ()
		skin_api.play_sound("ut_flak_select")
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
	muzzle_flash(function ()
		if in_third_person then
			return third_person.muzzle_position(owner_unit)
		end

		return skin_api.state() == skin and skin_api.muzzle_position() or nil
	end, in_third_person and third_person.meters_per_unit or skin.unit_scale)
end

-- The shot sounds of the blunderbuss are in its animation: while the skin is on the animations of the shots are not played on the
-- player's own first person unit (the model of the skin plays UT's)
mod.first_person_animation_filters[TEMPLATE_NAME] = function (event)
	return skin_api.enabled() and (event == "attack_shoot" or event == "attack_shoot_last")
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

	if not utils.is_local_player_unit(owner_unit) then
		remote_shot(owner_unit, "ut_flak_fire_3d")
	end

	particles.beam({
		color = {
			1,
			1,
			1,
		},
		life = 2.7,
		size = CONFIG.chunk_trail_width,
		texture = "flak_trail",
		track = function ()
			if not Unit.alive(visual.game_unit) or visual.projectile._stop_impacts then
				return nil
			end

			local position = Unit.world_position(visual.game_unit, 0)
			local length = math.min(visual.speed * CONFIG.chunk_trail_seconds, CONFIG.chunk_trail_length_max)

			return position - visual.direction:unbox() * length, position
		end,
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
				return Unit.world_position(visual.game_unit, 0)
			end
		end,
		life = 6,
		size = CONFIG.shell_glow_size * UNIT,
		texture = "muzzle_white",
	})
end

-- The explosion of the shell, on every machine: the game's own effects of it are not made while the skin is on (see flak_cannon.lua)
mod.skin_explosion_callbacks.ut_flak_shell_explosion = function (world, position)
	if not skin_api.enabled() then
		return
	end

	skin_api.play_sound_at("ut_flak_explosion_3d", position)

	particles.sprite({
		attenuation = 0,
		color = {
			1,
			1,
			1,
		},
		growth = CONFIG.explosion_flash_growth * UNIT,
		life = CONFIG.explosion_flash_life,
		position = position,
		size = CONFIG.explosion_flash_size * UNIT,
		spin = (math.random() * 2 - 1) * 0.12,
		texture = "explosion_flash",
	})

	for _ = 1, 3 do
		particles.sprite({
			attenuation = 0.1,
			color = {
				1,
				0.85,
				0.6,
			},
			growth = CONFIG.explosion_star_growth * UNIT,
			life = CONFIG.explosion_star_life,
			position = position,
			size = CONFIG.explosion_star_size * UNIT,
			spin = (math.random() * 2 - 1) * 0.3,
			texture = "flak_muzzle",
		})
	end

	for _ = 1, CONFIG.explosion_puffs do
		local offset = random_direction() * (math.random() * CONFIG.explosion_puff_spread * UNIT)

		particles.sprite({
			attenuation = 0.2,
			color = {
				1,
				0.9,
				0.8,
			},
			growth = 10 * UNIT,
			intensity = 1.5,
			life = random_between(CONFIG.explosion_puff_life),
			position = position + offset,
			size = random_between(CONFIG.explosion_puff_size) * UNIT,
			spin = (math.random() * 2 - 1) * 0.5,
			texture = "flak_explosion",
			velocity = Vector3(0, 0, CONFIG.explosion_puff_rise),
		})
	end
end
