local mod = get_mod("unreal_tournament")

-- Beastmen standards (banners). A standard only takes damage from melee attacks and from a list of damage sources (bombs, torches). The
-- game's explosions don't look for it, because it is not an enemy. This lets the mod's weapons damage it:
--   standards.blow_up(position, attacker unit, radius, damage profile, power level, damage source): the host damages the standards
--     within the radius of the explosion. The damage of the explosion is not dropped. The item's other damage, such as a beam or a
--     projectile hitting a standard, is dropped.

local CONFIG = {
	-- Meters past the radius that still count. The game's overlap test is on the standard's body, and this measures to its position.
	margin = 1,
}

local standards = {}
mod.standards = standards
-- True while the damage of an explosion is being applied. The host applies it at once.
local exploding = false

if rawget(_G, "BeastmenStandardHealthExtension") then
	mod:hook(BeastmenStandardHealthExtension, "add_damage", function (func, self, attacker_unit, damage_amount, hit_zone_name, damage_type, hit_position, damage_direction, damage_source_name, ...)
		if exploding then
			return GenericHealthExtension.add_damage(self, attacker_unit, damage_amount, hit_zone_name, damage_type, hit_position, damage_direction, damage_source_name, ...)
		end

		return func(self, attacker_unit, damage_amount, hit_zone_name, damage_type, hit_position, damage_direction, damage_source_name, ...)
	end)
end

function standards.blow_up(impact_position, attacker_unit, radius, damage_profile, power_level, damage_source)
	if not Managers.player.is_server or not attacker_unit then
		return
	end

	-- The list is copied, because a standard leaves it when it dies.
	local alive = table.clone(Managers.state.conflict:alive_standards())

	for _, standard in ipairs(alive) do
		-- Not every unit is in POSITION_LOOKUP. The game's own explosion falls back to the unit's position the same way.
		local position = POSITION_LOOKUP[standard] or Unit.local_position(standard, 0)

		if HEALTH_ALIVE[standard] and Vector3.distance(position, impact_position) <= radius + CONFIG.margin then
			local direction = Vector3.normalize(position - impact_position)

			exploding = true

			-- An error must not leave the standards open to damage.
			local ok, error_message = pcall(DamageUtils.add_damage_network_player, damage_profile, 1, power_level, standard, attacker_unit, "full", position, direction, damage_source, nil, 0, false, nil, false, 0, 1, attacker_unit)

			exploding = false

			if not ok then
				error(error_message, 0)
			end
		end
	end
end