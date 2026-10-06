local mod = get_mod("unreal_tournament")

-- Registration of new named game data, shared by the weapons.
-- The data has to exist on every peer in the same order, everyone in the game needs the mod.

local registration = {}

-- Adds a name to a NetworkLookup table (the names are sent over the network as numbers)
registration.register_network_lookup = function (lookup_name, key)
	local lookup = NetworkLookup[lookup_name]

	if rawget(lookup, key) then
		return
	end

	local index = #lookup + 1

	lookup[index] = key
	lookup[key] = index
end

-- A copy of an existing damage profile, changed by modify(profile)
registration.register_damage_profile = function (name, source_name, modify)
	local profile = table.clone(DamageProfileTemplates[source_name])

	profile.name = name

	if modify then
		modify(profile)
	end

	-- Mirrors the _no_damage variants generated in damage_profile_templates.lua,
	-- explosions fall back to them when the target is immune
	local no_damage_name = name .. "_no_damage"
	local no_damage_profile = table.clone(profile)

	no_damage_profile.name = no_damage_name

	if no_damage_profile.targets then
		for _, target in ipairs(no_damage_profile.targets) do
			if target.power_distribution then
				target.power_distribution.attack = 0
			end
		end
	end

	if no_damage_profile.default_target.power_distribution then
		no_damage_profile.default_target.power_distribution.attack = 0
	end

	DamageProfileTemplates[name] = profile
	DamageProfileTemplates[no_damage_name] = no_damage_profile

	registration.register_network_lookup("damage_profiles", name)
	registration.register_network_lookup("damage_profiles", no_damage_name)
end

registration.register_explosion_template = function (name, template)
	template.name = name
	ExplosionTemplates[name] = template

	registration.register_network_lookup("explosion_templates", name)
end

-- Damage scales linearly with the power distribution, armor modifiers and range falloff of a
-- damage profile, so the weapons share those and only differ in the power factor. Everything is
-- flat (no range falloff), like in UT, and there is no burning.
local BASE_ARMOR_MODIFIER = table.clone(DamageProfileTemplates.beam_shot.armor_modifier_near)

registration.make_flat = function (profile, attack_power, impact_power)
	local target = profile.default_target

	target.power_distribution = {
		attack = attack_power,
		impact = impact_power,
	}
	target.power_distribution_near = nil
	target.power_distribution_far = nil
	target.range_modifier_settings = nil
	target.dot_template_name = nil
	target.dot_balefire_variant = nil

	profile.armor_modifier = table.clone(BASE_ARMOR_MODIFIER)
	profile.armor_modifier_near = nil
	profile.armor_modifier_far = nil
end

-- The power factors of the shock rifle's beam are the reference for the damage in UT2004's units:
-- its 45 damage is an attack power of 0.7 and an impact power of 0.3
registration.UT_REFERENCE_DAMAGE = 45
registration.REFERENCE_ATTACK_POWER = 0.7
registration.REFERENCE_IMPACT_POWER = 0.3

registration.attack_power_for = function (ut_damage)
	return registration.REFERENCE_ATTACK_POWER * ut_damage / registration.UT_REFERENCE_DAMAGE
end

registration.impact_power_for = function (ut_damage)
	return registration.REFERENCE_IMPACT_POWER * ut_damage / registration.UT_REFERENCE_DAMAGE
end

-- Damage to the player who set off an explosion. The game scales friendly fire damage, which
-- includes the damage to yourself, by a number that is 0 on the lower difficulties, so the damage
-- is applied directly: max_damage at the center of the explosion, falling off in the same way as
-- the explosion's damage does (explosion is the "explosion" table of the explosion template).
registration.apply_explosion_self_damage = function (owner_unit, position, item_name, explosion, max_damage)
	local body_position = Unit.world_position(owner_unit, 0) + Vector3.up() * 0.9
	local offset = body_position - position
	local distance = Vector3.length(offset)
	local full_radius = explosion.max_damage_radius
	local falloff_range = explosion.radius - full_radius

	if distance >= explosion.radius or not HEALTH_ALIVE[owner_unit] then
		return
	end

	local factor = distance <= full_radius and 1 or 1 - (distance - full_radius) / falloff_range
	local direction = distance > 0.01 and offset * (1 / distance) or Vector3.up()

	DamageUtils.add_damage_network(owner_unit, owner_unit, max_damage * factor, "torso", "drakegun", position, direction, item_name, nil, owner_unit, nil, nil, false, nil, nil, nil, nil, nil, 1)
end

return registration
