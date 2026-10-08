local mod = get_mod("unreal_tournament")

-- Particle effects that can be scaled. The effects of the game are only loaded together with the
-- characters and weapons that use them, playing one that isn't loaded crashes the game, so an
-- effect is only played when it is available.

local CONFIG = {
	-- Particle effects are scaled by linking them to a unit with a scale, so effects that need
	-- a size get an invisible helper unit. Some effects ignore the scale.
	fx_unit_name = "units/hub_elements/empty",
	-- Scaled effects are destroyed after a while, in case they would never end
	timed_effect_lifetime = 3, -- seconds
}

local effects = {}

effects.is_available = function (effect_name)
	local ok, available = pcall(Application.can_get, "particles", effect_name)

	return ok and available
end

-- Plays the effect as it is (at its own size) if it is available, returns if it was
effects.create = function (world, effect_name, position, rotation)
	if not effects.is_available(effect_name) then
		return false
	end

	World.create_particles(world, effect_name, position, rotation or Quaternion.identity())

	return true
end

local timed_effects = {}

local function destroy_timed_effect(effect)
	-- the effect or the world may already be gone
	pcall(World.destroy_particles, effect.world, effect.effect_id)

	if Unit.alive(effect.unit) then
		Managers.state.unit_spawner:mark_for_deletion(effect.unit)
	end
end

-- Plays the effect at the scale if it is available, returns if it was
effects.play = function (world, effect_name, position, scale, rotation)
	if not effects.is_available(effect_name) then
		return false
	end

	rotation = rotation or Quaternion.identity()

	local unit = Managers.state.unit_spawner:spawn_local_unit(CONFIG.fx_unit_name, position, Quaternion.identity())

	Unit.set_local_scale(unit, 0, Vector3(scale, scale, scale))

	local effect_id = World.create_particles(world, effect_name, position)

	-- "stop": when the unit is deleted the effect stops spawning and the particles already out fade on their own
	World.link_particles(world, effect_id, unit, 0, Matrix4x4.from_quaternion(rotation), "stop")

	timed_effects[#timed_effects + 1] = {
		age = 0,
		effect_id = effect_id,
		unit = unit,
		world = world,
	}

	return true
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

-- (loaded once, by unreal_tournament.lua: the effects are kept here, and updated and cleared here, not by each weapon)
mod.update_callbacks[#mod.update_callbacks + 1] = effects.update
mod.unload_callbacks[#mod.unload_callbacks + 1] = effects.clear
mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = effects.clear

return effects
