local mod = get_mod("unreal_tournament")

-- The Berserk combo (ComboBerserk). Every weapon attacks a third faster. UT shortens each fire's FireRate to 0.75
-- (WeaponFire.StartBerserk); here it is one buff of the game's attack speed, which all weapons follow (utils.attack_speed).
-- Stagger, push and melee cleave go up by the same third. UT has none of these; they are the mod's own. A Shield Gun punch into a wall
-- throws its player twice as far (shield_gun.lua). Everyone sees red rings flashing around the character (OffensiveEffect).

local combos = mod.combos
local particles = mod.skin_particles

local UNIT = mod.utils.UT_UNIT

local CONFIG = {
	-- Added to the attack speed's multiplier of 1: 1 / 0.75 times as fast
	attack_speed = 1 / 0.75 - 1,
	-- Added to the multipliers of stagger, push and melee cleave
	power = 1 / 0.75 - 1,
	-- OffensiveEffect: 3 rings a second, each for 1 s, 10 units from the pawn's middle (mPosDev: utils.ut_particle_offset), turned at
	-- random, 0.7 to 1.1 times
	-- the size of the mesh, fading in and out with ATF_ExpInOut (mAttenKa 0.5: see skin_particles.lua's exp_in_out)
	ring_rate = 3, -- a second
	ring_life = 1, -- s
	ring_spread = 10, -- units
	ring_size = { 0.7, 1.1 },
	ring_attenuation = 0.5,
	ring_color = { 250 / 255, 150 / 255, 150 / 255 },
	ring_unit = "units/ut/fx/tele_ring",
	ring_material = "units/ut/fx/fx_berserk_ring",
}

local BUFFS = {
	{ name = "ut_combo_berserk_attack_speed", multiplier = CONFIG.attack_speed, stat_buff = "attack_speed" },
	{ name = "ut_combo_berserk_stagger", multiplier = CONFIG.power, stat_buff = "power_level_impact" },
	{ name = "ut_combo_berserk_push", multiplier = CONFIG.power, stat_buff = "push_power" },
	{ name = "ut_combo_berserk_cleave", multiplier = CONFIG.power, stat_buff = "power_level_melee_cleave" },
}

local BUFF_NAMES = {}

for i, buff in ipairs(BUFFS) do
	combos.buff(buff)

	BUFF_NAMES[i] = buff.name
end

-- Each character's: { buffs (on the host), next_ring }
local berserking = {}

-- A rotation picked evenly from all rotations
local function random_rotation()
	local u1, u2, u3 = math.random(), math.random(), math.random()
	local a, b = math.sqrt(1 - u1), math.sqrt(u1)

	return Quaternion.from_elements(a * math.sin(2 * math.pi * u2), a * math.cos(2 * math.pi * u2), b * math.sin(2 * math.pi * u3), b * math.cos(2 * math.pi * u3))
end

-- A ring that moves with the character
local function ring(unit)
	local offset = Vector3Box(mod.utils.ut_particle_offset(CONFIG.ring_spread) * UNIT)
	local size = CONFIG.ring_size[1] + math.random() * (CONFIG.ring_size[2] - CONFIG.ring_size[1])

	particles.mesh({
		additive = 0,
		attenuation = CONFIG.ring_attenuation,
		exp_in_out = true,
		color = CONFIG.ring_color,
		life = CONFIG.ring_life,
		material = CONFIG.ring_material,
		rotation = random_rotation(),
		scale = function ()
			return size
		end,
		unit = CONFIG.ring_unit,
		follow = function ()
			if not Unit.alive(unit) then
				return nil
			end

			return combos.pawn_middle(unit) + offset:unbox()
		end,
	})
end

combos.kinds.berserk = {
	start = function (unit)
		berserking[unit] = {
			buffs = combos.is_host() and combos.add_buffs(unit, BUFF_NAMES) or nil,
			next_ring = 0,
		}
	end,
	stop = function (unit)
		local entry = berserking[unit]

		berserking[unit] = nil

		if entry and entry.buffs and Unit.alive(unit) then
			combos.remove_buffs(unit, entry.buffs)
		end
	end,
	update = function (unit)
		local entry = berserking[unit]
		local t = Managers.time:time("game")

		if not entry or t < entry.next_ring then
			return
		end

		entry.next_ring = t + 1 / CONFIG.ring_rate

		ring(unit)
	end,
}

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(berserking)
end
