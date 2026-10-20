local mod = get_mod("unreal_tournament")

-- The Booster combo (ComboDefensive): the character gets 5 health every 0.9 s (its Timer, from the start; the game's health can't go
-- past full, where UT's goes on to 199 and then to the shield), and the game's wounds are healed as it starts. As well as UT's: stamina
-- back five times as fast, and started while knocked down it gets the character up. Everyone sees green crosses rising around the
-- character (RegenCrosses).

local utils = mod.utils
local combos = mod.combos
local particles = mod.skin_particles

local UNIT = utils.UT_UNIT

local CONFIG = {
	heal = 5,
	heal_interval = 0.9, -- s
	-- (a heal of the game that is permanent health and leaves the wounds as they are: the start heals them)
	heal_type = "health_regen",
	-- (and one that is temporary health, for a character whose healing becomes temporary health: the no_permanent_health perk of
	-- Natural Bond and the like, which the game's own heals look at too, as a bandage becomes bandage_temp_health)
	temporary_heal_type = "buff",
	stamina_regen = 4, -- added to the regeneration's multiplier of 1
	-- RegenCrosses: 10 crosses a second, each 6 units, from up to 35 units around the pawn's middle (45 up and down), for 2 s, brightest
	-- at the middle of its life (mAttenKa 0.5); each keeps the pawn's speed (mOwnerVelocityFactor 1), slowed by mAirResistance 2, and
	-- rises as gravity times its mMass -0.1 pulls it
	cross_rate = 10, -- a second
	cross_size = 6, -- units
	cross_spread = { 35, 35, 45 }, -- units
	cross_life = 2, -- s
	cross_attenuation = 0.5,
	cross_drag = 2, -- a second
	cross_rise = 0.1 * 950, -- units a second squared (UT's gravity, PhysicsVolume.Gravity 950)
	cross_texture = "green_cross",
}

local STAMINA_BUFF = "ut_combo_booster_stamina"

combos.buff({
	name = STAMINA_BUFF,
	multiplier = CONFIG.stamina_regen,
	stat_buff = "fatigue_regen",
})

-- Each character's: { buffs (on the host), next_heal (on the host), heal_wounds (on the host: once it is up), next_cross }
local boosted = {}

-- A cross, from where it starts, with the pawn's speed slowed by the drag, and the rise as a constant pull against it
local function cross(unit, velocity)
	local spread = CONFIG.cross_spread
	local offset = Vector3((math.random() * 2 - 1) * spread[1], (math.random() * 2 - 1) * spread[2], (math.random() * 2 - 1) * spread[3]) * UNIT
	local start = Vector3Box(combos.pawn_middle(unit) + offset)
	local speed = Vector3Box(velocity)
	local born = Managers.time:time("game")
	local k = CONFIG.cross_drag
	local rise = CONFIG.cross_rise * UNIT

	particles.sprite({
		attenuation = CONFIG.cross_attenuation,
		life = CONFIG.cross_life,
		size = CONFIG.cross_size * UNIT,
		texture = CONFIG.cross_texture,
		follow = function ()
			local t = Managers.time:time("game") - born
			local slowed = (1 - math.exp(-k * t)) / k

			-- (v' = rise - k v: the speed it starts with fades, and the rise builds up to rise / k)
			return start:unbox() + speed:unbox() * slowed + Vector3(0, 0, rise / k * (t - slowed))
		end,
	})
end

combos.kinds.booster = {
	start = function (unit)
		local entry = {
			next_heal = 0,
			next_cross = 0,
		}

		if combos.is_host() then
			-- (started while knocked down, it gets the character up: combos.lua lets only this combo start then. The game's revive takes
			-- a wound as it ends, so the wounds are healed once the character is up.)
			local status_extension = ScriptUnit.has_extension(unit, "status_system")

			if status_extension and status_extension:is_knocked_down() then
				mod.get_up(unit)

				entry.heal_wounds = true
			else
				StatusUtils.set_wounded_network(unit, false, "healed")
			end

			entry.buffs = combos.add_buffs(unit, { STAMINA_BUFF })
		end

		boosted[unit] = entry
	end,
	stop = function (unit)
		local entry = boosted[unit]

		boosted[unit] = nil

		if entry and entry.buffs and Unit.alive(unit) then
			combos.remove_buffs(unit, entry.buffs)
		end
	end,
	update = function (unit)
		local entry = boosted[unit]
		local t = Managers.time:time("game")

		if not entry then
			return
		end

		if entry.heal_wounds then
			local status_extension = ScriptUnit.has_extension(unit, "status_system")

			if status_extension and not status_extension:is_knocked_down() then
				entry.heal_wounds = nil

				StatusUtils.set_wounded_network(unit, false, "healed")
			end
		end

		if combos.is_host() and t >= entry.next_heal then
			entry.next_heal = t + CONFIG.heal_interval

			local buff_extension = ScriptUnit.has_extension(unit, "buff_system")
			local temporary = buff_extension and buff_extension:has_buff_perk("no_permanent_health")

			DamageUtils.heal_network(unit, unit, CONFIG.heal, temporary and CONFIG.temporary_heal_type or CONFIG.heal_type)
		end

		if t >= entry.next_cross then
			entry.next_cross = t + 1 / CONFIG.cross_rate

			local locomotion_extension = ScriptUnit.has_extension(unit, "locomotion_system")
			local velocity = locomotion_extension and locomotion_extension.current_velocity and locomotion_extension:current_velocity() or Vector3.zero()

			cross(unit, velocity)
		end
	end,
}

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(boosted)
end
