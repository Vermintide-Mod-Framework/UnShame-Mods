local mod = get_mod("unreal_tournament")

-- The Speed combo (ComboSpeed): the character runs 1.4 times as fast and jumps 1.5 times as high (GroundSpeed and JumpZ), as buffs of the
-- game on their movement settings, which the mod's UT movement reads too. As well as UT's: no limit on dodging (the mod's Multidodge, for
-- this player). Everyone sees a trail at each foot (SpeedTrail, attached to the feet's bones).

local utils = mod.utils
local combos = mod.combos
local particles = mod.skin_particles

local UNIT = utils.UT_UNIT

local CONFIG = {
	run = 1.4,
	jump = 1.5,
	-- SpeedTrail: a stream of 10 particles a second, each 12 units wide, shrinking by 12 a second, for 0.65 s; drawn here as a beam from
	-- each one to the next
	trail_rate = 10, -- a second
	trail_size = 12, -- units
	trail_growth = -12, -- units a second
	trail_life = 0.65, -- s
	trail_texture = "speed_trail",
	feet = { "j_leftfoot", "j_rightfoot" },
}

local RUN_BUFF = "ut_combo_speed_run"
local JUMP_BUFF = "ut_combo_speed_jump"

combos.buff({
	name = RUN_BUFF,
	apply_buff_func = "apply_movement_buff",
	remove_buff_func = "remove_movement_buff",
	multiplier = CONFIG.run,
	path_to_movement_setting_to_modify = {
		"move_speed",
	},
})

combos.buff({
	name = JUMP_BUFF,
	apply_buff_func = "apply_movement_buff",
	remove_buff_func = "remove_movement_buff",
	multiplier = CONFIG.jump,
	path_to_movement_setting_to_modify = {
		"jump",
		"initial_vertical_speed",
	},
})

-- On the host, each character's buffs; and on every machine, where each foot's trail was last: [unit] = { buffs, points, next }
local speeding = {}

local function foot_position(unit, node_name)
	return Unit.has_node(unit, node_name) and Unit.world_position(unit, Unit.node(unit, node_name)) or nil
end

combos.kinds.speed = {
	start = function (unit, owner)
		speeding[unit] = {
			buffs = combos.is_host() and combos.add_buffs(unit, { RUN_BUFF, JUMP_BUFF }) or nil,
			points = {},
			next = 0,
		}

		if owner then
			mod.unlimited_dodge[unit] = true
		end
	end,
	stop = function (unit, owner)
		local entry = speeding[unit]

		speeding[unit] = nil

		if owner then
			mod.unlimited_dodge[unit] = nil
		end

		if entry and entry.buffs and Unit.alive(unit) then
			combos.remove_buffs(unit, entry.buffs)
		end
	end,
	update = function (unit)
		local entry = speeding[unit]
		local t = Managers.time:time("game")

		if not entry or t < entry.next then
			return
		end

		entry.next = t + 1 / CONFIG.trail_rate

		for i, node_name in ipairs(CONFIG.feet) do
			local position = foot_position(unit, node_name)
			local last = entry.points[i]

			if position and last then
				particles.beam({
					from = last:unbox(),
					to = position,
					growth = CONFIG.trail_growth * UNIT,
					life = CONFIG.trail_life,
					size = CONFIG.trail_size * UNIT,
					texture = CONFIG.trail_texture,
				})
			end

			entry.points[i] = position and Vector3Box(position) or nil
		end
	end,
}

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(speeding)
end
