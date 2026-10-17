local mod = get_mod("unreal_tournament")

-- The game's particle effects, played as they are or scaled. Playing an effect that isn't loaded crashes the game, so the mod only plays
-- effects from packages the game always loads: resource_packages/ingame, and the DLC packages, which boot.lua loads for every DLC
-- whether it is owned or not.

local utils = mod.utils

local CONFIG = {
	-- Particle effects are scaled by linking them to a unit that has a scale, so an effect that needs a size gets an invisible helper
	-- unit. Some effects ignore the scale.
	fx_unit_name = "units/hub_elements/empty",
	-- Scaled effects are destroyed after this long, in case they would never end.
	timed_effect_lifetime = 3, -- seconds
}

local effects = {}
mod.effects = effects

-- The game's effects that the mod plays, as a set of names. The extras mod's effects test checks that each is loaded.
effects.game_effects = {}

-- Names a game effect that the mod plays, and returns the name. Every game effect the mod plays is named with this.
effects.game_effect = function (effect_name)
	effects.game_effects[effect_name] = true

	return effect_name
end

-- Plays the effect as it is, at its own size.
effects.create = function (world, effect_name, position, rotation)
	World.create_particles(world, effect_name, position, rotation or Quaternion.identity())
end

local timed_effects = {}

local function destroy_timed_effect(effect)
	-- The effect or the world may already be gone, so errors are ignored.
	pcall(World.destroy_particles, effect.world, effect.effect_id)

	if Unit.alive(effect.unit) then
		Managers.state.unit_spawner:mark_for_deletion(effect.unit)
	end
end

-- Starts the effect at the scale and returns it. The effect goes on until effects.stop or effects.destroy.
effects.start = function (world, effect_name, position, scale, rotation)
	rotation = rotation or Quaternion.identity()

	local unit = Managers.state.unit_spawner:spawn_local_unit(CONFIG.fx_unit_name, position, Quaternion.identity())

	Unit.set_local_scale(unit, 0, Vector3(scale, scale, scale))

	local effect_id = World.create_particles(world, effect_name, position)

	-- With "stop", when the unit is deleted the effect stops spawning, and the particles already out fade on their own.
	World.link_particles(world, effect_id, unit, 0, Matrix4x4.from_quaternion(rotation), "stop")

	return {
		effect_id = effect_id,
		unit = unit,
		world = world,
	}
end

-- Stops the effect from spawning more particles. The ones already out fade on their own.
effects.stop = function (effect)
	if Unit.alive(effect.unit) then
		Managers.state.unit_spawner:mark_for_deletion(effect.unit)
	end
end

-- Removes the effect at once.
effects.destroy = destroy_timed_effect

-- Plays the effect at the scale.
effects.play = function (world, effect_name, position, scale, rotation)
	local effect = effects.start(world, effect_name, position, scale, rotation)

	effect.age = 0
	timed_effects[#timed_effects + 1] = effect
end

-- Plays an effect that is a ring in its own plane. The ring sits at the height above the effect's origin, at the scale, and is turned
-- to face the camera when it starts, so that it is seen from the front. A ring that is already playing is not turned: it keeps the
-- direction it started in. The ring is centered on the position.
effects.play_facing = function (world, effect_name, position, scale, height)
	local camera_position, camera_rotation = utils.camera_pose()

	if not camera_position then
		return
	end

	-- The effect's z axis is the way it faces, which is towards the camera.
	local front = Vector3.normalize(camera_position - position)
	local rotation = Quaternion.look(Quaternion.up(camera_rotation), front)

	-- The ring is above the effect's origin and is turned about that origin, so the origin is moved to put the ring on the position.
	effects.play(world, effect_name, position - Quaternion.rotate(rotation, Vector3(0, 0, height * scale)), scale, rotation)
end

effects.update = function (dt)
	for i = #timed_effects, 1, -1 do
		local effect = timed_effects[i]

		effect.age = effect.age + dt

		if effect.age >= CONFIG.timed_effect_lifetime then
			destroy_timed_effect(effect)
			table.remove(timed_effects, i)
		end
	end
end

effects.clear = function ()
	for i = #timed_effects, 1, -1 do
		destroy_timed_effect(timed_effects[i])

		timed_effects[i] = nil
	end
end

-- This file is loaded once, by unreal_tournament.lua. The effects are updated and cleared here, not by each weapon.
mod.update_callbacks[#mod.update_callbacks + 1] = effects.update
mod.unload_callbacks[#mod.unload_callbacks + 1] = effects.clear
mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = effects.clear