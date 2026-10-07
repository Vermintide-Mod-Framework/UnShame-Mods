local mod = get_mod("unreal_tournament")

-- Link Gun: replaces the Deepwood Staff's (the Thornsister's, the template staff_life) actions in place.
-- The numbers are from UT2004 (XWeapons/LinkFire, LinkAltFire, LinkProjectile, LinkBeamEffect).
--   LMB: the staff's burst of thorns, which stun as well as hurt.
--   RMB (held): the link beam. What the aim is on is linked to: an ally does more damage for as long as the link
--               lasts (UT's link, a teammate), an enemy is held where it is and follows the aim along the
--               ground, a heavy one slower, with the beam hanging more.
-- What happens to enemies is done by the game that has them, the host's. The beam is only drawn for the player
-- who holds it.

local registration = mod:dofile("scripts/mods/unreal_tournament/registration")
local register_damage_profile = registration.register_damage_profile

local stagger_types = require("scripts/utils/stagger_types")

local TEMPLATE_NAME = "staff_life"

local CONFIG = {
	-- The default stance of both fire modes: the stance of the alt fire (its animation event). It is entered
	-- idle_pose_delay seconds after the staff is wielded (the raise plays until then), and the beam and venting end
	-- in it.
	idle_pose_event = "attack_charge_fireball",
	idle_pose_delay = 0.4,
	damage_recovery_delay = 0.5, -- seconds after damage that the stance is entered again (the reaction plays until then)
	-- The right arm isn't shown: this node of the first person unit is scaled to this (0 would break the skinning)
	hidden_arm_nodes = {
		"j_rightshoulder",
		"j_rightarm",
		"j_rightarmroll",
		"j_rightforearm",
		"j_rightforearmroll",
		"j_righthand",
		"j_righthandthumb1",
		"j_righthandthumb2",
		"j_righthandthumb3",
		"j_righthandindex1",
		"j_righthandindex2",
		"j_righthandindex3",
		"j_righthandmiddle1",
		"j_righthandmiddle2",
		"j_righthandmiddle3",
		"j_righthandmiddle4",
		"j_righthandring1",
		"j_righthandring2",
		"j_righthandring3",
		"j_righthandring4",
		"j_righthandpinky1",
		"j_righthandpinky2",
		"j_righthandpinky3",
		"j_righthandpinky4",
		"j_rightinhandthumb",
		"j_rightinhandindex",
		"j_rightinhandmiddle",
		"j_rightinhandring",
		"j_rightinhandpinky",
	},
	hidden_arm_scale = 0.2, -- (each node of the arm, down the chain they multiply)
	-- Primary: one bolt at a time while the button is held (UT's LinkAltFire: FireRate 0.2, and its LinkProjectile
	-- starts at Speed 1000 uu/s, speeds up by 3000 uu/s every second to MaxSpeed 4000, an uu is 0.02 m). The
	-- bolts are the staff's thorns, which start at the left hand's weapon node (the staff is in it) and a bit
	-- ahead of it, and blend into the aim from there. Their damage profile keeps the damage of the thorns, and their
	-- stagger is bolt_stagger_power (the damage's share of the power distribution is 0.12 near and 0.1 far, a
	-- stagger of this is a heavy one).
	bolt_fire_interval = 0.25, -- seconds
	bolt_speed = 20, -- m/s
	bolt_acceleration = 60, -- m/s^2
	bolt_max_speed = 80, -- m/s
	bolt_overcharge = 1, -- heat of a bolt (the staff's burst of four was 4)
	bolt_link_node = "j_leftweaponattach",
	bolt_forward_offset = 0.6, -- m ahead of the node
	bolt_stagger_power = 0.6,
	-- Beam (UT: TraceRange 1100 uu, 1.5 times that while linked; here the link holds until the beam is let go, or the
	-- target is further away than that)
	beam_range = 22, -- m
	linked_range_scale = 1.5,
	aim_dot = 0.985, -- how close to the aim a target has to be to be linked to, 1 is exactly
	beam_overcharge = 0.8, -- heat, added every beam_overcharge_interval seconds while the beam is held
	beam_overcharge_interval = 0.25,
	-- Ally: the damage it does is this much more while linked, the buff is kept up every buff_refresh seconds
	ally_damage_bonus = 0.5,
	ally_buff_duration = 0.6, -- seconds
	ally_buff_refresh = 0.25, -- seconds
	ally_attack_grace = 0.5, -- seconds the beam still costs heat after the ally's attack
	-- Enemy: it is held (staggered over and over, stagger_duration, every restagger_interval) and moved over the
	-- ground, towards the point the aim is on at the distance it was linked at, hold_speed m/s for the lightest, less
	-- by weight: speed = hold_speed / (mass / reference_mass) ^ weight_exponent. Enemies with a mass of more than
	-- max_mass can't be held, and neither can the big monsters and bosses.
	hold_speed = 9,
	hold_min_distance = 2.5, -- m
	-- Primary while an enemy is held lifts it and throws it to land in front of you, yank_min_distance from you,
	-- along an arc: it travels at yank_speed (the same weight rule as hold_speed, the flight is at least
	-- throw_min_duration and at most throw_max_duration) and rises throw_height (less by weight, at least 0.5). It
	-- is not thrown through walls or off the navmesh.
	yank_speed = 30, -- m/s
	yank_min_distance = 1.5, -- m
	throw_height = 3, -- m
	throw_min_duration = 0.35,
	throw_max_duration = 1.2,
	yank_animation_event = "attack_charge_fireball", -- the alt fire's own animation, played again every yank
	reference_mass = 1.5, -- a clan rat's
	weight_exponent = 0.5,
	max_mass = 30,
	stagger_duration = 1.5,
	restagger_interval = 1,
	-- A linked enemy (and a monster) is poisoned: the game's own poison of poisoned arrows, dot_template, at
	-- dot_power_level (what its damage scales with), applied again every dot_interval seconds, which keeps it up
	-- while it is linked. What can't have a buff takes dot_damage of dot_damage_type straight to its health instead.
	dot_template = "arrow_poison_dot",
	dot_power_level = 500,
	dot_interval = 1,
	dot_overcharge = 1, -- heat of every application of it, on top of the heat of the beam
	dot_damage = 2,
	dot_damage_type = "damage_over_time",
	dot_damage_source = "we_life_staff",
	-- A monster, an enemy too big to be held, is linked but not held: once it has moved monster_move_distance from
	-- where it was when it was linked, or the owner tries to yank it, the owner is launched towards it (the state of
	-- being launched by the game's monsters) at monster_pull_per_meter of its distance as speed (between the min and
	-- the max) and monster_pull_up_speed upwards, the link is over, and can't be made again for
	-- monster_link_cooldown seconds.
	monster_move_distance = 1, -- m
	monster_pull_per_meter = 1.5,
	monster_pull_min_speed = 10, -- m/s
	monster_pull_max_speed = 20, -- m/s
	monster_pull_up_speed = 5, -- m/s
	monster_link_cooldown = 2, -- seconds
	-- Supplies: when nothing living is linked, a supply (a pickup) that the aim is on, within supply_aim_dot, is
	-- linked if the owner can pick it up: it is pulled to them at supply_pull_speed, to supply_pull_height above
	-- their feet, and picked up when it is within supply_pickup_distance of that. Tried again after supply_retry
	-- seconds.
	supply_aim_dot = 0.98,
	supply_pull_speed = 12, -- m/s
	supply_pull_height = 1, -- m
	supply_pickup_distance = 0.7, -- m
	supply_retry = 0.6, -- seconds
	-- Objects: when nothing living is linked, a ragdoll or another object with a body that moves is held (no
	-- damage, living things come first). It is held in the air where the aim is, the body that was linked is given
	-- object_pull per second of the way to there as speed, at most object_max_speed.
	object_collision_filter = "filter_explosion_overlap",
	object_release_dot = 0.998, -- how exactly the aim has to be on something living for an object that is held to be let go for it
	object_pull = 20,
	object_max_speed = 35, -- m/s
	-- The beam: drawn as a curve (a quadratic Bezier) from the staff to what it is on. A held enemy hangs it by
	-- its weight (sag_per_weight a meter per meter of beam, per unit of weight, at most sag_max), and bends it
	-- by how far the enemy is behind where it is being moved to (lag_bend).
	staff_end_node = "fx_muzzle", -- the node at the end of the staff unit, where the beam and the bolts start (the hand's node if it has none)
	beam_aim_curve = 0.3, -- how far the beam bows towards the aim, as a share of its length at most: 0 is a straight line
	beam_segments = 16,
	sag_per_weight = 0.015,
	sag_max = 2.5, -- m
	lag_bend = 0.5,
	beam_thickness = 0.012, -- m, the beam is a few lines around its path
	beam_color = {
		255,
		90,
		255,
		120,
	},
	ally_beam_color = {
		255,
		255,
		210,
		60,
	},
	object_beam_color = {
		255,
		200,
		255,
		230,
	},
	held_beam_color = {
		255,
		190,
		255,
		190,
	},
}

local overcharge_values = PlayerUnitStatusSettings.overcharge_values

overcharge_values.ut_link_beam = CONFIG.beam_overcharge
overcharge_values.ut_link_bolt = CONFIG.bolt_overcharge

-- Damage profile of the thorns: the game's own with more stagger. The stagger is what stuns. (The staff and its
-- profile are the Winds of Magic's, without that DLC there is nothing to change.)
local has_staff = rawget(DamageProfileTemplates, "burst_thorn") ~= nil

if has_staff then
	register_damage_profile("ut_link_bolt", "burst_thorn", function (profile)
		local target = profile.default_target

		target.power_distribution_near.impact = CONFIG.bolt_stagger_power
		target.power_distribution_far.impact = CONFIG.bolt_stagger_power
	end)
end

-- The buff an ally gets while linked. The buffs go over the network by name, everyone in the game needs the mod.
local ALLY_BUFF = "ut_link_damage_boost"

BuffTemplates[ALLY_BUFF] = {
	buffs = {
		{
			duration = CONFIG.ally_buff_duration,
			max_stacks = 1,
			multiplier = CONFIG.ally_damage_bonus,
			name = ALLY_BUFF,
			refresh_durations = true,
			stat_buff = "power_level",
		},
	},
}

registration.register_network_lookup("buff_templates", ALLY_BUFF)

-- Weapon template
-- The template is shared game state: it is patched in place, what is touched is saved to be put back on disable.
-- The saved values are in a persistent table, so that a mod reload doesn't take the patched template for the
-- original.
local persistent = mod:persistent_table("link_gun")

-- (an earlier load of the mod wrapped the game's animation event function for logging: it is put back)
if persistent.animation_event then
	Unit.animation_event = persistent.animation_event
	persistent.animation_event = nil
end

-- The default stance. Delayed pose events: the animation event is only sent while is_valid() still holds, so
-- nothing is sent if the weapon was swapped or another action started in the meantime.
local pose = {}
local pending_poses = {}

function pose.schedule(delay, is_valid, callback)
	pending_poses[#pending_poses + 1] = {
		callback = callback,
		is_valid = is_valid,
		time_left = delay,
	}
end

-- (the staff isn't idle while an action runs, every action calls this when it starts)
function pose.clear()
	table.clear(pending_poses)

	pose.waiting = nil
	pose.recovering = false
end

-- The overcharge lockout has an animation of its own, which stays until the weapon has cooled down, through weapon
-- swaps as well: the stance doesn't replace it, it waits for the lockout to end.
function pose.locked_out()
	local overcharge_extension = pose.overcharge_extension

	return overcharge_extension ~= nil and overcharge_extension.lockout == true
end

-- (an action that starts before the stance was entered enters it itself, the shots have no animation of their own)
function pose.enter(unit_1p)
	if pose.locked_out() then
		pose.waiting = unit_1p

		return
	end

	pose.waiting = nil
	pose.entered = true

	Unit.animation_event(unit_1p, CONFIG.idle_pose_event)
end

-- The right arm is hidden from when the staff is wielded until anything else is: the node of its shoulder in the
-- first person unit is scaled down to a point (the arm hangs off it) every frame, before the world is updated and
-- again right after (some animations set the scale themselves), and the units are updated again for the new scale
-- before they are drawn.
local hand = {}

function hand.show()
	local first_person_extension = hand.first_person_extension

	if first_person_extension then
		hand.first_person_extension = nil

		local unit = first_person_extension:get_first_person_unit()

		if unit and Unit.alive(unit) then
			for _, name in ipairs(CONFIG.hidden_arm_nodes) do
				if Unit.has_node(unit, name) then
					Unit.set_local_scale(unit, Unit.node(unit, name), Vector3(1, 1, 1))
				end
			end
		end
	end
end

-- (until anything else is wielded: the first person unit is looked up every frame, not kept)
function hand.hide(first_person_extension)
	hand.show()

	hand.first_person_extension = first_person_extension
end

function hand.apply(world)
	local first_person_extension = hand.first_person_extension

	if not first_person_extension then
		return
	end

	local unit = first_person_extension:get_first_person_unit()

	if not unit or not Unit.alive(unit) then
		return
	end

	local scale = CONFIG.hidden_arm_scale

	for _, name in ipairs(CONFIG.hidden_arm_nodes) do
		if Unit.has_node(unit, name) then
			Unit.set_local_scale(unit, Unit.node(unit, name), Vector3(scale, scale, scale))
		end
	end

	if world then
		World.update_unit(world, unit)

		local mesh_unit = first_person_extension:get_first_person_mesh_unit()

		if mesh_unit and Unit.alive(mesh_unit) then
			World.update_unit(world, mesh_unit)
		end
	end
end

function hand.update()
	hand.apply()
end

mod:hook_safe(TransportationSystem, "world_updated", function (self, world)
	hand.apply(world)
end)

function pose.update(dt)
	-- Taking damage plays a reaction that takes the staff out of the stance: it is entered again after it
	local health_extension = pose.health_extension

	if health_extension and pose.is_valid and pose.is_valid() and not pose.recovering then
		local damage_datas, num_damages = health_extension:recent_damages()

		for i = 1, num_damages / DamageDataIndex.STRIDE do
			if damage_datas[(i - 1) * DamageDataIndex.STRIDE + DamageDataIndex.DAMAGE_AMOUNT] > 0 then
				pose.recovering = true
				pose.entered = false

				pose.schedule(CONFIG.damage_recovery_delay, pose.is_valid, function ()
					pose.recovering = false

					pose.enter(pose.unit_1p)
				end)

				break
			end
		end
	end

	if pose.waiting then
		if not pose.is_valid or not pose.is_valid() then
			pose.waiting = nil
		elseif not pose.locked_out() then
			pose.enter(pose.waiting)
		end
	end

	for i = #pending_poses, 1, -1 do
		local pending = pending_poses[i]

		pending.time_left = pending.time_left - dt

		if pending.time_left <= 0 then
			table.remove(pending_poses, i)

			if pending.is_valid() then
				pending.callback()
			end
		end
	end
end

-- The end of the staff itself (it moves with the animations), if the unit has the node
local function staff_end_position(owner_unit)
	local inventory_extension = ScriptUnit.has_extension(owner_unit, "inventory_system")
	local equipment = inventory_extension and inventory_extension:equipment()
	local staff_unit = equipment and (equipment.left_hand_wielded_unit or equipment.right_hand_wielded_unit)

	if staff_unit and Unit.alive(staff_unit) and Unit.has_node(staff_unit, CONFIG.staff_end_node) then
		return Unit.world_position(staff_unit, Unit.node(staff_unit, CONFIG.staff_end_node))
	end
end

-- The bolt: the staff's thorn, starting at the end of the staff and blending into its path from there (the game
-- blends it from a node of the first person unit, the left hand's: that is where it starts if the staff has no end)
local function bolt_projectile_info()
	local projectile_info = table.clone(Projectiles.lifestaff_light)

	projectile_info.anim_blend_settings.link_node = CONFIG.bolt_link_node
	projectile_info.anim_blend_settings.forward_offset = CONFIG.bolt_forward_offset
	projectile_info.ut_staff_end = true

	return projectile_info
end

-- (after the game has put a bolt where its blend says, it is put on the same blend from the end of the staff)
mod:hook_safe(PlayerProjectileUnitExtension, "update", function (self)
	if not self.projectile_info.ut_staff_end or not ALIVE[self._owner_unit] then
		return
	end

	local locomotion_extension = self.locomotion_extension
	local settings = self.projectile_info.anim_blend_settings
	local blend_t = math.min(settings.blend_func((locomotion_extension.time_lived or 0) / settings.blend_time), 1)

	if blend_t >= 1 then
		return
	end

	local start_position = staff_end_position(self._owner_unit)
	local real_position = locomotion_extension:current_position()

	if start_position and real_position then
		Unit.set_local_position(self._projectile_unit, 0, Vector3.lerp(start_position, real_position, blend_t))
	end
end)

-- The bolts speed up as they fly (UT's LinkProjectile: Speed, Acceleration, MaxSpeed). The path of a projectile
-- is its starting point plus its direction times its speed times the time it has flown, so the speed is changed
-- together with the starting point, by what keeps the bolt where it is. Every peer does this for the bolts it has.
local bolts = {}

mod.init_callbacks = mod.init_callbacks or {}
mod.init_callbacks.link_bolt = function (extension)
	bolts[#bolts + 1] = extension._projectile_unit
end

local function update_bolts()
	for i = #bolts, 1, -1 do
		local unit = bolts[i]
		local locomotion_extension = Unit.alive(unit) and ScriptUnit.has_extension(unit, "projectile_locomotion_system")

		if not locomotion_extension or locomotion_extension.stopped then
			table.remove(bolts, i)
		else
			local time_lived = locomotion_extension.time_lived or 0
			local speed = math.min(CONFIG.bolt_speed + CONFIG.bolt_acceleration * time_lived, CONFIG.bolt_max_speed) * 100
			local old_speed = locomotion_extension.speed

			if old_speed and speed ~= old_speed then
				local radians = locomotion_extension.radians
				local direction = locomotion_extension.target_vector_boxed:unbox() * math.cos(radians) + Vector3(0, 0, math.sin(radians))
				local initial_position = locomotion_extension.initial_position_boxed:unbox()

				locomotion_extension.initial_position_boxed:store(initial_position + direction * ((old_speed - speed) / 100) * time_lived)
				locomotion_extension.speed = speed
			end
		end
	end
end

local function restore_staff()
	local original = persistent.original
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not original or not template then
		return
	end

	local actions = template.actions

	if original.primary_actions then
		for name, saved in pairs(original.primary_actions) do
			local action = actions.action_one[name]

			-- (what the mod added is taken away, what it changed put back)
			for key in pairs(action) do
				if saved.fields[key] == nil then
					action[key] = nil
				end
			end

			for key, value in pairs(saved.fields) do
				action[key] = value
			end

			action.impact_data.damage_profile = saved.damage_profile
		end

		actions.weapon_reload.default.anim_end_event = original.reload_anim_end_event
		actions.weapon_reload.default.enter_function = original.reload_enter_function
		actions.weapon_reload.default.finish_function = original.reload_finish_function
	elseif original.primary then
		-- (what an earlier load of the mod saved, from before the bolts)
		for _, name in ipairs({
			"default",
			"default_chain",
		}) do
			local action = actions.action_one[name]
			local saved = original.primary[name]

			action.impact_data.damage_profile = saved.damage_profile
			action.anim_event = saved.anim_event
			action.anim_end_event = saved.anim_end_event
			action.enter_function = saved.enter_function
			action.finish_function = saved.finish_function
			action.on_shoot_particle_fx = saved.on_shoot_particle_fx
			action.ut_link_primary = nil
		end

		actions.weapon_reload.default.anim_end_event = original.reload_anim_end_event
		actions.weapon_reload.default.enter_function = original.reload_enter_function
		actions.weapon_reload.default.finish_function = original.reload_finish_function
	else
		-- (what an earlier load of the mod saved, from before the stance was added)
		actions.action_one.default.impact_data.damage_profile = original.default_damage_profile
		actions.action_one.default_chain.impact_data.damage_profile = original.chain_damage_profile
	end

	actions.action_two.default = original.action_two_default

	persistent.original = nil
end

local function apply_link_gun()
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not template or not has_staff then
		return
	end

	-- Already applied by a previous load of this mod, start over from the original
	restore_staff()

	local actions = template.actions
	local reload = actions.weapon_reload.default
	local original = {
		action_two_default = actions.action_two.default,
		primary_actions = {},
		reload_anim_end_event = reload.anim_end_event,
		reload_enter_function = reload.enter_function,
		reload_finish_function = reload.finish_function,
	}

	-- (the whole of an action is saved, its fields can be put back as they were)
	for _, name in ipairs({
		"default",
		"default_chain",
	}) do
		local action = actions.action_one[name]

		original.primary_actions[name] = {
			damage_profile = action.impact_data.damage_profile,
			fields = table.shallow_copy(action),
		}
	end

	persistent.original = original

	-- The thorns: one bolt at a time, again and again while the button is held, a stunning one that speeds up. The
	-- shot has no animation of its own (the staff stays in its stance, the hand doesn't cast).
	for _, name in ipairs({
		"default",
		"default_chain",
	}) do
		local action = actions.action_one[name]
		local saved = original.primary_actions[name].fields
		local chains = {
			{
				action = "action_one",
				input = "action_one_hold",
				start_time = CONFIG.bolt_fire_interval,
				sub_action = "default",
			},
		}

		-- (the chains to the other actions are open from the start, there is only the one bolt in an action)
		for _, chain in ipairs(saved.allowed_chain_actions) do
			if chain.action ~= "action_one" then
				local open_chain = table.clone(chain)

				open_chain.start_time = 0.1
				chains[#chains + 1] = open_chain
			end
		end

		action.allowed_chain_actions = chains
		action.anim_end_event = nil
		action.anim_event = nil
		action.buff_data = nil
		action.extra_shot_delay = nil
		action.impact_data.damage_profile = "ut_link_bolt"
		action.num_shots = 1
		action.overcharge_type = "ut_link_bolt"
		-- (the effect of the shot, at the hand and the staff in it: the game has it at the right hand)
		action.on_shoot_particle_fx = saved.on_shoot_particle_fx and {
			effect = saved.on_shoot_particle_fx.effect,
			node_name = CONFIG.bolt_link_node,
		} or nil
		action.projectile_info = bolt_projectile_info()
		action.speed = CONFIG.bolt_speed * 100
		action.total_time = CONFIG.bolt_fire_interval
		action.ut_init_callback = "link_bolt"
		action.enter_function = function (...)
			pose.clear()

			if not pose.entered then
				local weapon_extension = select(4, ...)

				pose.enter(weapon_extension.first_person_extension:get_first_person_unit())
			end

			if saved.enter_function then
				return saved.enter_function(...)
			end
		end
	end

	-- Venting also ends in the stance (venting right after wielding: the raise to the stance would play over it)
	reload.anim_end_event = CONFIG.idle_pose_event
	reload.enter_function = function (...)
		pose.clear()

		pose.entered = true

		if original.reload_enter_function then
			return original.reload_enter_function(...)
		end
	end

	-- The beam: a charge that is held, with the heat of the beam while it is, the rest is in the callback below
	local beam = table.clone(original.action_two_default)

	-- (no animation of its own, like the bolts: the stance stays)
	beam.anim_end_event = nil
	beam.anim_end_event_condition_func = nil
	beam.anim_event = nil
	beam.charge_time = 1000 -- (it is never "full")
	beam.enter_function = function (attacker_unit, input_extension, _, weapon_extension)
		pose.clear()

		if not pose.entered then
			pose.enter(weapon_extension.first_person_extension:get_first_person_unit())
		end

		input_extension:reset_release_input()
		input_extension:clear_input_buffer()
	end
	beam.finish_function = nil
	beam.kind = "charge"
	beam.overcharge_interval = CONFIG.beam_overcharge_interval
	beam.overcharge_type = "ut_link_beam"
	beam.ut_charge_callback = "link"
	beam.lookup_data = {
		item_template_name = TEMPLATE_NAME,
		action_name = "action_two",
		sub_action_name = "default",
	}

	-- (primary doesn't start an action while the beam is held: it yanks the enemy that is linked, in the callback below)
	local chains = {}

	for _, chain in ipairs(beam.allowed_chain_actions) do
		if chain.action ~= "action_one" then
			chains[#chains + 1] = chain
		end
	end

	beam.allowed_chain_actions = chains

	actions.action_two.default = beam
end


-- The beam
local ai_units = {}
local states = {} -- per unit that holds the beam: what it is linked to, and its line object

local function chest_position(unit)
	local node = Unit.has_node(unit, "c_spine") and Unit.node(unit, "c_spine") or 0

	return Unit.world_position(unit, node)
end

local function breed_mass(breed)
	local rank = Managers.state.difficulty:get_difficulty_rank()
	local counts = breed.hit_mass_counts

	return counts and (counts[rank] or counts[2]) or breed.hit_mass_count or 1
end

-- If the enemy can be held, and its weight (1 for the lightest)
-- (the target dummies have a health of their own that is not in HEALTH_ALIVE)
local function is_alive(unit)
	if not Unit.alive(unit) then
		return false
	end

	if HEALTH_ALIVE[unit] then
		return true
	end

	local health_extension = ScriptUnit.has_extension(unit, "health_system")

	return health_extension ~= nil and health_extension:is_alive()
end

local function enemy_weight(unit)
	local breed = is_alive(unit) and AiUtils.unit_breed(unit)

	if not breed or breed.is_player or breed.boss_staggers then
		return nil
	end

	local mass = breed_mass(breed)

	if mass > CONFIG.max_mass then
		return nil
	end

	return math.max(mass / CONFIG.reference_mass, 1) ^ CONFIG.weight_exponent
end

-- A monster: a living enemy that is too big to be held (the bosses, the big ones), which pulls the owner to it
local function is_monster(unit)
	local breed = is_alive(unit) and AiUtils.unit_breed(unit)

	return breed ~= nil and breed ~= false and not breed.is_player and breed.race ~= "dummy" and enemy_weight(unit) == nil
end

local function has_line_of_sight(physics_world, origin, target_position)
	local offset = target_position - origin
	local distance = Vector3.length(offset)

	if distance < 0.1 then
		return true
	end

	local hit, _, hit_distance = PhysicsWorld.immediate_raycast(physics_world, origin, offset * (1 / distance), distance, "closest", "collision_filter", "filter_ai_line_of_sight_check")

	return not hit or hit_distance > distance - 0.5
end

-- What is an object: a ragdoll, a barrel, anything that is not a character that is alive (a target dummy is an
-- object when it can't be held as an enemy, which it is first)
local function is_object(unit)
	local breed = AiUtils.unit_breed(unit)

	if breed and (breed.is_player or (breed.race ~= "dummy" and is_alive(unit))) then
		return false
	end

	return true
end

-- The corpse that is held, or was held last, isn't removed: the game removes the oldest of the corpses it has in its
-- death watch list when there are too many, so the corpse is taken out of that list, and put back (as the newest)
-- when another one is held or the mod is cleared.
local preserved

local function restore_corpse()
	local held = preserved

	preserved = nil

	if not held or not Unit.alive(held.unit) then
		return
	end

	local spawner = Managers.state and Managers.state.unit_spawner

	if not spawner or spawner.unit_death_watch_lookup[held.unit] then
		return
	end

	held.death_data.t = Managers.time:time("game")
	spawner.unit_death_watch_list_n = spawner.unit_death_watch_list_n + 1
	spawner.unit_death_watch_list[spawner.unit_death_watch_list_n] = held.death_data
	spawner.unit_death_watch_lookup[held.unit] = held.death_data
	spawner.unit_death_watch_list_dirty = true
end

local function preserve_corpse(unit)
	if preserved and preserved.unit == unit then
		return
	end

	restore_corpse()

	local spawner = Managers.state.unit_spawner
	local death_data = spawner and spawner.unit_death_watch_lookup[unit]

	if not death_data then
		return
	end

	local list = spawner.unit_death_watch_list
	local index = table.find(list, death_data)

	if not index then
		return
	end

	-- (as the game takes a unit out of the list when it deletes it)
	local last = list[spawner.unit_death_watch_list_n]

	list[index] = last
	spawner.unit_death_watch_lookup[last.unit] = list[index]
	list[spawner.unit_death_watch_list_n] = nil
	spawner.unit_death_watch_lookup[unit] = nil
	spawner.unit_death_watch_list_n = math.max(spawner.unit_death_watch_list_n - 1, 0)
	spawner.unit_death_watch_list_dirty = true

	preserved = {
		death_data = death_data,
		unit = unit,
	}
end

-- What the aim is on, closest to it: an enemy that can be held or an ally, and failing those an object with a body
-- that moves (a ragdoll). Returns the unit and what it is, and for an object its body and how far it is.
local function find_target(owner_unit, physics_world, origin, aim, min_dot)
	local side = Managers.state.side.side_by_unit[owner_unit]
	local range = CONFIG.beam_range
	local best_unit, best_kind
	local best_dot = min_dot or CONFIG.aim_dot

	local function consider(unit, kind)
		local offset = chest_position(unit) - origin
		local distance = Vector3.length(offset)

		if distance <= 0.1 or distance > range then
			return
		end

		local dot = Vector3.dot(aim, offset * (1 / distance))

		if dot > best_dot and has_line_of_sight(physics_world, origin, chest_position(unit)) then
			best_unit = unit
			best_kind = kind
			best_dot = dot
		end
	end

	local count = AiUtils.broadphase_query(origin + aim * (range / 2), range / 2 + 2, ai_units, side and side.enemy_broadphase_categories)

	for i = 1, count do
		if enemy_weight(ai_units[i]) then
			consider(ai_units[i], "enemy")
		elseif is_monster(ai_units[i]) then
			consider(ai_units[i], "monster")
		end
	end

	-- The target dummies are on the neutral side
	local neutral_categories = side and side.neutral_broadphase_categories

	if neutral_categories and next(neutral_categories) ~= nil then
		count = AiUtils.broadphase_query(origin + aim * (range / 2), range / 2 + 2, ai_units, neutral_categories)

		for i = 1, count do
			local breed = AiUtils.unit_breed(ai_units[i])

			if breed and breed.race == "dummy" and enemy_weight(ai_units[i]) then
				consider(ai_units[i], "enemy")
			end
		end
	end

	local heroes = Managers.state.side:get_side_from_name("heroes")

	if heroes then
		for _, unit in ipairs(heroes.PLAYER_AND_BOT_UNITS) do
			if unit ~= owner_unit and Unit.alive(unit) and HEALTH_ALIVE[unit] then
				consider(unit, "ally")
			end
		end
	end

	-- Nothing living: supplies (what can be picked up), a little more forgiving of the aim, they are small
	if not best_unit then
		best_dot = math.min(best_dot, CONFIG.supply_aim_dot)

		for unit in pairs(Managers.state.entity:get_entities("GenericUnitInteractableExtension")) do
			if Unit.alive(unit) and ScriptUnit.has_extension(unit, "pickup_system") then
				consider(unit, "supply")
			end
		end
	end

	if best_unit then
		return best_unit, best_kind
	end

	-- Nothing living: a ragdoll or another object with a body that moves, the first one the aim is on
	PhysicsWorld.prepare_actors_for_raycast(physics_world, origin, aim, 0.01, 0.5, range * range)

	local hits = PhysicsWorld.immediate_raycast(physics_world, origin, aim, range, "all", "collision_filter", CONFIG.object_collision_filter)

	for i = 1, hits and #hits or 0 do
		local hit = hits[i]
		local actor = hit[4]
		local unit = actor and Actor.unit(actor)

		if unit and unit ~= owner_unit then
			if not Actor.is_static(actor) and is_object(unit) then
				return unit, "object", actor, hit[2]
			elseif Actor.is_static(actor) then
				-- (a wall in the way ends the search, characters are skipped)
				break
			end
		end
	end
end

-- The owner is launched towards the monster, as a player is by the game's monsters (catapulted), and the link is
-- over: it can't link again for monster_link_cooldown seconds
local function launch_towards_monster(state, owner_unit, monster, t)
	local flat = Vector3.flat(Unit.world_position(monster, 0) - Unit.world_position(owner_unit, 0))
	local distance = Vector3.length(flat)
	local direction = distance > 0.1 and flat * (1 / distance) or Vector3.forward()
	local velocity = direction * math.clamp(distance * CONFIG.monster_pull_per_meter, CONFIG.monster_pull_min_speed, CONFIG.monster_pull_max_speed)

	Vector3.set_z(velocity, CONFIG.monster_pull_up_speed)
	StatusUtils.set_catapulted_network(owner_unit, true, velocity)

	state.link_block_until = t + CONFIG.monster_link_cooldown
end

-- A supply: the owner's interactor and the type of interaction for it, if they can pick it up (not with a full
-- slot, for one) at all
local function supply_interaction(owner_unit, pickup)
	local interactor_extension = ScriptUnit.has_extension(owner_unit, "interactor_system")
	local interaction_type = Unit.get_data(pickup, "interaction_data", "interaction_type")

	if interactor_extension and interaction_type and interactor_extension:can_interact(pickup, interaction_type) then
		return interactor_extension, interaction_type
	end
end

-- A supply that is linked is pulled to the owner, and picked up when it is there: the owner starts the game's
-- interaction with it, which has the game do all of it (the checks, the inventory, the sounds, the removal of the
-- pickup). The interaction is held by the button of the beam, which is down. Returns true when it is done.
local function pull_supply(state, owner_unit, dt)
	local pickup = state.target
	local goal = Unit.world_position(owner_unit, 0) + Vector3(0, 0, CONFIG.supply_pull_height)
	local offset = goal - Unit.world_position(pickup, 0)
	local distance = Vector3.length(offset)

	if distance <= CONFIG.supply_pickup_distance then
		local interactor_extension, interaction_type = supply_interaction(owner_unit, pickup)

		if interactor_extension then
			interactor_extension:start_interaction("action_two_hold", pickup, interaction_type)
		end

		return true
	end

	local position = Unit.world_position(pickup, 0) + offset * (math.min(distance, CONFIG.supply_pull_speed * dt) / distance)
	local actor = Unit.actor(pickup, "throw")

	if actor and Actor.is_physical(actor) then
		Actor.teleport_position(actor, position)
		Actor.set_velocity(actor, Vector3.zero())
	else
		Unit.set_local_position(pickup, 0, position)
	end

	return false
end

-- The throw of a held enemy (primary): an arc from where it is to in front of the owner. An AI unit is moved by the
-- script for the flight (script driven, it would be put back on the navmesh by the game otherwise) and gets its own
-- movement and the ground back where it lands.
local function finish_throw(state)
	local thrown = state.throw

	state.throw = nil

	local unit = state.target

	if not thrown or not unit or not Unit.alive(unit) then
		return
	end

	local locomotion_extension = ScriptUnit.has_extension(unit, "locomotion_system")

	-- (not a unit that has died in the air: the game has taken its locomotion down, putting it back in the updates of
	-- the locomotion crashes the game)
	if locomotion_extension and locomotion_extension.teleport_to and HEALTH_ALIVE[unit] then
		local land = thrown.land:unbox()
		local nav_world = Managers.state.entity:system("ai_system"):nav_world()
		local on_navmesh, altitude = GwNavQueries.triangle_from_position(nav_world, land, 1.5, 2)

		if on_navmesh then
			land.z = altitude

			locomotion_extension:teleport_to(land)
		end

		locomotion_extension:set_movement_type(thrown.movement_type or "snap_to_navmesh")
	end
end

local function start_throw(state, owner_unit, t, physics_world)
	local unit = state.target
	local locomotion_extension = ScriptUnit.has_extension(unit, "locomotion_system")
	local is_ai = locomotion_extension ~= nil and locomotion_extension.teleport_to ~= nil
	local current = Unit.world_position(unit, 0)
	local aim_flat = state.flat_aim and state.flat_aim:unbox() or Vector3.forward()
	local owner_position = Unit.world_position(owner_unit, 0)
	local nav_world = is_ai and Managers.state.entity:system("ai_system"):nav_world() or nil

	-- (where it lands: in front of the owner, and if that isn't walkable, as at a ledge, nearer to them)
	local land

	for _, landing_distance in ipairs({CONFIG.yank_min_distance, CONFIG.yank_min_distance * 0.6, CONFIG.yank_min_distance * 0.25, 0}) do
		local candidate = owner_position + aim_flat * landing_distance

		if not nav_world or GwNavQueries.triangle_from_position(nav_world, candidate, 1.5, 2) then
			land = candidate

			break
		end
	end

	if not land or Vector3.length(land - current) < 0.5 then
		state.hold_distance = CONFIG.yank_min_distance

		return
	end

	local distance = Vector3.length(land - current)
	local lift = math.max(0.5, CONFIG.throw_height / state.weight)

	-- (no throw through a wall: the arc is checked, from the enemy up to the top of it and down to where it lands,
	-- so that it goes over the edge of a ledge, and when it can't it is pulled in along the ground, as it is held)
	local height = Vector3(0, 0, 1)
	local apex = (current + land) * 0.5 + Vector3(0, 0, lift + 1)
	local points = {current + height, apex, land + height}

	for i = 1, #points - 1 do
		local ray_offset = points[i + 1] - points[i]
		local ray_distance = Vector3.length(ray_offset)

		if ray_distance > 0.01 and PhysicsWorld.immediate_raycast(physics_world, points[i], ray_offset * (1 / ray_distance), ray_distance, "closest", "collision_filter", "filter_player_ray_projectile_static_only") then
			state.hold_distance = CONFIG.yank_min_distance

			return
		end
	end

	if state.throw then
		finish_throw(state)
	end

	state.throw = {
		duration = math.clamp(distance / (CONFIG.yank_speed / state.weight), CONFIG.throw_min_duration, CONFIG.throw_max_duration),
		land = Vector3Box(land),
		lift = lift,
		movement_type = is_ai and locomotion_extension.movement_type or nil,
		start = Vector3Box(current),
		t0 = t,
	}
	state.hold_distance = CONFIG.yank_min_distance
end

-- true while it is in the air
local function update_throw(state, t)
	local thrown = state.throw
	local unit = state.target
	local progress = math.clamp((t - thrown.t0) / thrown.duration, 0, 1)
	local position = Vector3.lerp(thrown.start:unbox(), thrown.land:unbox(), progress) + Vector3(0, 0, thrown.lift * 4 * progress * (1 - progress))
	local locomotion_extension = ScriptUnit.has_extension(unit, "locomotion_system")

	if locomotion_extension and locomotion_extension.teleport_to then
		locomotion_extension:set_movement_type("script_driven")
		locomotion_extension:teleport_to(position)
	else
		Unit.set_local_position(unit, 0, position)
	end

	if progress >= 1 then
		finish_throw(state)

		return false
	end

	return true
end

local function release_target(state)
	finish_throw(state)

	state.target = nil
	state.kind = nil
	state.weight = nil
	state.actor = nil
end

-- Where the beam ends: on the chest of a character, on the body of an object (on its unit while it has none that
-- physics drives)
local function target_position(state)
	if state.kind == "object" then
		return state.actor and Actor.position(state.actor) or Unit.world_position(state.target, 0)
	end

	return chest_position(state.target)
end

-- The body of an object that is held is looked for again every frame: a body that has just died is driven by its
-- animation, and its ragdoll bodies are other ones when it starts
local function refresh_object(state)
	local unit = state.target

	if not Unit.alive(unit) then
		state.actor = nil

		return
	end

	-- (the body of the same bone as the one that was linked: it is the one that is held, wherever it came from. A bone
	-- can have more than one body, the middle of a body has a box that is hit and the body that falls: the one that
	-- physics drives is held)
	local best_actor

	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		if actor and not Actor.is_static(actor) and Actor.node(actor) == state.node_index then
			if Actor.is_physical(actor) then
				best_actor = actor

				break
			end

			best_actor = best_actor or actor
		end
	end

	state.actor = best_actor
end

-- The link holds wherever the aim goes, and through walls, until the beam is let go, the target is gone, or it is
-- further away than the beam reaches linked
local function is_link_valid(state, origin)
	local target = state.target

	if state.kind == "object" or state.kind == "supply" then
		if not Unit.alive(target) then
			return false
		end
	elseif not is_alive(target) then
		return false
	end

	return Vector3.length(target_position(state) - origin) <= CONFIG.beam_range * CONFIG.linked_range_scale
end

-- Holds an object that is linked where the aim is, in the air at the distance it was linked at (primary brings it to
-- yank_min_distance): the body that was linked is given the speed that takes it to the place. No damage.
local function hold_object(state, aim, origin, dt)
	if state.yank then
		state.yank = nil
		state.hold_distance = CONFIG.yank_min_distance
	end

	local wanted = origin + aim * state.hold_distance
	local velocity = (wanted - target_position(state)) * CONFIG.object_pull
	local speed = Vector3.length(velocity)

	if speed > CONFIG.object_max_speed then
		velocity = velocity * (CONFIG.object_max_speed / speed)
	end

	if state.actor then
		-- The body that was linked is given the speed, the rest of a ragdoll hangs from it: gravity and the speed of
		-- the limbs act on them as they would. (A ragdoll that has lain a while is put to sleep by the game: its
		-- bodies are woken while it is held. A body that is driven by animation, a corpse that hasn't started to
		-- ragdoll, isn't physical: it waits.)
		local actor = state.actor
		local unit = state.target

		-- The game freezes a ragdoll that has settled: its bodies are made kinematic, and a kinematic body doesn't
		-- take a speed. A ragdoll that is held is thawed, once.
		if not state.thawed then
			state.thawed = true

			for i = 0, Unit.num_actors(unit) - 1 do
				local body = Unit.actor(unit, i)

				if body and Actor.is_dynamic(body) and not Actor.is_physical(body) then
					Actor.set_kinematic(body, false)
				end
			end
		end

		for i = 0, Unit.num_actors(unit) - 1 do
			local body = Unit.actor(unit, i)

			if body and Actor.is_physical(body) and Actor.is_sleeping(body) then
				Actor.wake_up(body)
			end
		end

		if Actor.is_physical(actor) then
			Actor.set_velocity(actor, velocity)
		end

		-- TEMPORARY (log only): once a second, what the held body does with the speed it is given
		if Managers.time:time("game") >= (state.next_object_log_t or 0) then
			state.next_object_log_t = Managers.time:time("game") + 1

			mod:info("[object] holding: bone %s physical=%s sleeping=%s set_speed=%.1f speed_now=%.1f distance_to_wanted=%.1f", tostring(state.node_index), tostring(Actor.is_physical(actor)), tostring(Actor.is_sleeping(actor)), Vector3.length(velocity), Vector3.length(Actor.velocity(actor)), Vector3.length(wanted - Actor.position(actor)))
		end
	elseif state.moves_unit then
		-- a body that isn't driven by physics (a barrel that stays where it is put) goes with its unit
		local unit = state.target

		Unit.set_local_position(unit, 0, Unit.local_position(unit, 0) + velocity * dt)
	end

	-- (what has just died has no ragdoll yet: it is held, and moves once it has one)
end

-- Moves an enemy that is linked towards where the aim is, over the ground, and keeps it stunned
local function hold_enemy(state, owner_unit, t, dt, aim, physics_world)
	local unit = state.target
	local locomotion_extension = ScriptUnit.has_extension(unit, "locomotion_system")
	local is_ai = locomotion_extension ~= nil and locomotion_extension.teleport_to ~= nil

	local flat_aim = Vector3.flat(aim)
	local flat_length = Vector3.length(flat_aim)

	if flat_length > 0.1 then
		state.flat_aim = Vector3Box(flat_aim * (1 / flat_length))
	end

	local speed = CONFIG.hold_speed

	if state.yank then
		state.yank = nil

		start_throw(state, owner_unit, t, physics_world)
	end

	local throwing = state.throw ~= nil and update_throw(state, t)
	local owner_position = Unit.world_position(owner_unit, 0)
	local wanted = owner_position + (state.flat_aim and state.flat_aim:unbox() or Vector3.forward()) * state.hold_distance
	local current = Unit.world_position(unit, 0)
	local delta = Vector3.flat(wanted - current)
	local distance = Vector3.length(delta)

	state.lag = Vector3Box(delta)

	if not throwing and distance > 0.05 then
		local step = math.min(distance, speed / state.weight * dt)
		local new_position = current + delta * (step / distance)

		if is_ai then
			local nav_world = Managers.state.entity:system("ai_system"):nav_world()
			local on_navmesh, altitude = GwNavQueries.triangle_from_position(nav_world, new_position, 1.5, 2)

			-- (it doesn't leave the navmesh: that is the walls and the drops)
			if on_navmesh then
				new_position.z = altitude

				locomotion_extension:teleport_to(new_position)
			end
		else
			-- A unit that isn't an AI one, a target dummy, is moved as it is along the ground it stands on, and not
			-- through a wall
			local height = Vector3(0, 0, 1)
			local blocked = PhysicsWorld.immediate_raycast(physics_world, current + height, delta * (1 / distance), step + 0.5, "closest", "collision_filter", "filter_player_ray_projectile_static_only")

			if not blocked then
				Unit.set_local_position(unit, 0, new_position)
			end
		end
	end

	if t >= (state.next_stagger_t or 0) then
		state.next_stagger_t = t + CONFIG.restagger_interval

		local blackboard = BLACKBOARDS[unit]
		local direction = Vector3.length(delta) > 0.01 and Vector3.normalize(delta) or Vector3.forward()

		if blackboard then
			-- (the game's statistics look at the positions of the units in the stagger, the mods' update runs before
			-- the game has made them current)
			mod.with_valid_positions(AiUtils.stagger, unit, blackboard, owner_unit, direction, 1, stagger_types.heavy, CONFIG.stagger_duration, nil, t, 1, true, false)
		end
	end
end

-- Keeps the damage buff on an ally that is linked
-- Whether the ally is attacking (a primary action of their weapon is running)
local function is_ally_attacking(unit)
	local inventory_extension = ScriptUnit.has_extension(unit, "inventory_system")
	local equipment = inventory_extension and inventory_extension:equipment()
	local weapon_extension = equipment and (equipment.right_hand_weapon_extension or equipment.left_hand_weapon_extension)

	return weapon_extension ~= nil and weapon_extension.current_action_settings ~= nil and weapon_extension.current_action_name == "action_one"
end

-- Damage the ally deals counts as attacking too (the host gets all damage, the actions of other players' weapons
-- are only seen from their own game)
local function note_ally_damage(attacker_unit, source_attacker_unit)
	local t = Managers.time:time("game")

	for _, state in pairs(states) do
		if state.kind == "ally" and state.target and (state.target == attacker_unit or state.target == source_attacker_unit) then
			state.ally_attack_t = t
		end
	end
end

for _, extension_class in ipairs({GenericHealthExtension, TrainingDummyHealthExtension}) do
	mod:hook_safe(extension_class, "add_damage", function (self, attacker_unit, damage_amount, hit_zone_name, damage_type, hit_position, damage_direction, damage_source_name, hit_ragdoll_actor, source_attacker_unit)
		if next(states) then
			note_ally_damage(attacker_unit, source_attacker_unit)
		end
	end)
end

-- The beam only costs heat while it is linked to an enemy, or to an ally while they attack (and for
-- ally_attack_grace seconds after): asked by the game's add_charge, in bio_rifle.lua, for the beam's heat.
mod.link_beam_is_free = function (owner_unit)
	local state = states[owner_unit]

	if not state or not state.target then
		return true
	end

	if state.kind == "enemy" or state.kind == "monster" then
		return false
	end

	if state.kind == "object" or state.kind == "supply" then
		return true
	end

	return Managers.time:time("game") - (state.ally_attack_t or -math.huge) > CONFIG.ally_attack_grace
end

-- The damage over time of a linked enemy
local function damage_enemy(state, owner_unit, t)
	if t < (state.next_dot_t or 0) then
		return
	end

	state.next_dot_t = t + CONFIG.dot_interval

	local unit = state.target

	-- (every application costs heat)
	local overcharge_extension = ScriptUnit.has_extension(owner_unit, "overcharge_system")

	if overcharge_extension then
		overcharge_extension:add_charge(CONFIG.dot_overcharge, nil, "ut_link_dot")
	end

	if ScriptUnit.has_extension(unit, "buff_system") then
		-- The game's own poison, the one of poisoned arrows and the like: a buff on the enemy that does the damage over
		-- time and shows it as poisoned. It is applied again every dot_interval, which keeps it up while it is linked.
		Dots.poison_dot(CONFIG.dot_template, nil, nil, CONFIG.dot_power_level, unit, owner_unit, "torso", CONFIG.dot_damage_source, 1, false, owner_unit)
	else
		-- (what can't have a buff takes the damage directly; the game's statistics look at the positions of the
		-- units in a hit, the mods' update runs before the game has made them current)
		mod.with_valid_positions(DamageUtils.add_damage_network, unit, owner_unit, CONFIG.dot_damage, "torso", CONFIG.dot_damage_type, chest_position(unit), Vector3.up(), CONFIG.dot_damage_source, nil, owner_unit)
	end
end

local function boost_ally(state, owner_unit, t)
	if is_ally_attacking(state.target) then
		state.ally_attack_t = t
	end

	if t < (state.next_buff_t or 0) then
		return
	end

	state.next_buff_t = t + CONFIG.ally_buff_refresh

	-- (synced, the ally's own game works out what they do)
	Managers.state.entity:system("buff_system"):add_buff_synced(state.target, ALLY_BUFF, BuffSyncType.All, {
		attacker_unit = owner_unit,
	})
end

-- The beam, as lines: a curve from the staff to the end of it, a few lines around it for the thickness
local function bezier(p0, p1, p2, s)
	local a = p0 * ((1 - s) * (1 - s))
	local b = p1 * (2 * (1 - s) * s)
	local c = p2 * (s * s)

	return a + b + c
end

-- Where the beam starts: ahead of the left hand's node, where the bolts start (the staff is in the hand). If the
-- model doesn't have the node, ahead of the eye and to the left.
local function staff_position(owner_unit, first_person_extension, origin, rotation)
	-- the end of the staff itself, it moves with the animation (the yank swings it)
	local staff_end = staff_end_position(owner_unit)

	if staff_end then
		return staff_end
	end

	local unit_1p = first_person_extension:get_first_person_unit()

	if unit_1p and Unit.has_node(unit_1p, CONFIG.bolt_link_node) then
		local node_position = Unit.world_position(unit_1p, Unit.node(unit_1p, CONFIG.bolt_link_node))

		return node_position + Quaternion.forward(Unit.world_rotation(unit_1p, 0)) * CONFIG.bolt_forward_offset
	end

	return origin + Quaternion.forward(rotation) * 0.6 - Quaternion.right(rotation) * 0.25 - Quaternion.up(rotation) * 0.25
end

local function draw_beam(state, world, start_position, rotation, end_position, weight, lag, color_values)
	local line_object = state.line_object

	if not line_object then
		line_object = World.create_line_object(world)
		state.line_object = line_object
		state.world = world
	end

	LineObject.reset(line_object)

	local right = Quaternion.right(rotation)
	local up = Quaternion.up(rotation)
	local length = Vector3.length(end_position - start_position)
	local middle = (start_position + end_position) * 0.5
	-- (the beam bows towards the aim: the middle is pushed by the part of the aim that is sideways to the way to the
	-- target, by up to beam_aim_curve of the length, so it is straight when the target is right on the aim and a
	-- gentle bow when it isn't, never a hook)
	local curved_middle = middle

	if length > 0.01 then
		local direction = (end_position - start_position) * (1 / length)
		local aim = Quaternion.forward(rotation)
		local sideways = aim - direction * Vector3.dot(aim, direction)

		curved_middle = middle + sideways * (length * CONFIG.beam_aim_curve)
	end
	local sag = weight and math.min(CONFIG.sag_max, CONFIG.sag_per_weight * weight * length) or 0
	local bend = lag and lag * CONFIG.lag_bend or Vector3.zero()
	local control = curved_middle - Vector3.up() * sag + bend
	local color = Color(color_values[1], color_values[2], color_values[3], color_values[4])
	local thickness = CONFIG.beam_thickness
	local offsets = {
		Vector3.zero(),
		right * thickness,
		right * -thickness,
		up * thickness,
		up * -thickness,
	}
	local previous = start_position

	for i = 1, CONFIG.beam_segments do
		local point = bezier(start_position, control, end_position, i / CONFIG.beam_segments)

		for _, offset in ipairs(offsets) do
			LineObject.add_line(line_object, color, previous + offset, point + offset)
		end

		previous = point
	end

	LineObject.dispatch(world, line_object)
end

local function destroy_line_object(state)
	if state.line_object and state.world then
		-- (what was dispatched stays drawn until the line object is dispatched again, so it is emptied and
		-- dispatched before it goes, the world may be gone)
		pcall(LineObject.reset, state.line_object)
		pcall(LineObject.dispatch, state.world, state.line_object)
		pcall(World.destroy_line_object, state.world, state.line_object)
	end

	state.line_object = nil
	state.world = nil
end

local function end_beam(owner_unit)
	local state = states[owner_unit]

	if state then
		finish_throw(state)
		destroy_line_object(state)

		states[owner_unit] = nil
	end
end

mod.charge_update_callbacks.link = function (self, dt, t, world)
	local owner_unit = self.owner_unit
	local state = states[owner_unit]

	if not state then
		state = {}
		states[owner_unit] = state
	end

	local first_person_extension = ScriptUnit.extension(owner_unit, "first_person_system")
	local origin = first_person_extension:current_position()
	local rotation = first_person_extension:current_rotation()
	local aim = Quaternion.forward(rotation)
	local physics_world = self.physics_world

	if Managers.player.is_server then
		if state.target and state.kind == "object" then
			refresh_object(state)
		end

		if state.target and not is_link_valid(state, origin) then
			release_target(state)
		end

		-- (what is living comes first: an object that is held is let go for it as soon as the aim is on it)
		local unit, kind, actor, object_distance

		if (state.kind == "object" or not state.target) and t >= (state.link_block_until or 0) then
			unit, kind, actor, object_distance = find_target(owner_unit, physics_world, origin, aim, state.kind == "object" and CONFIG.object_release_dot or nil)

			-- (only for something living: an object that is held stays when the aim finds nothing, or another object)
			if state.kind == "object" and (kind == "enemy" or kind == "ally") then
				release_target(state)
			elseif state.target then
				unit = nil
			end
		end

		-- A supply is only linked if the owner can pick it up
		if unit and kind == "supply" and not state.target and not supply_interaction(owner_unit, unit) then
			state.link_block_until = t + CONFIG.supply_retry

			unit = nil
		end

		if unit and not state.target then
			state.target = unit
			state.kind = kind

			if kind == "monster" then
				state.monster_start = Vector3Box(Unit.world_position(unit, 0))
			end
			state.actor = actor
			state.weight = kind == "enemy" and enemy_weight(unit) or nil
			state.next_stagger_t = nil
			state.next_buff_t = nil
			state.next_dot_t = nil

			if kind == "object" then
				state.hold_distance = math.clamp(object_distance, CONFIG.yank_min_distance, CONFIG.beam_range)
				state.node_index = Actor.node(actor)
				state.thawed = false

				preserve_corpse(unit)
				state.moves_unit = not Actor.is_dynamic(actor) and AiUtils.unit_breed(unit) == nil

				-- TEMPORARY (log only)
				local dynamic_count = 0

				for i = 0, Unit.num_actors(unit) - 1 do
					local body = Unit.actor(unit, i)

					if body and Actor.is_dynamic(body) then
						dynamic_count = dynamic_count + 1
					end
				end

				local breed = AiUtils.unit_breed(unit)

				mod:info("[object] linked: breed=%s actors=%d dynamic=%d hit_dynamic=%s hit_static=%s distance=%.1f moves_unit=%s", tostring(breed and breed.name), Unit.num_actors(unit), dynamic_count, tostring(Actor.is_dynamic(actor)), tostring(Actor.is_static(actor)), object_distance, tostring(state.moves_unit))

				-- (the bodies of the bone that was hit, what each is)
				for i = 0, Unit.num_actors(unit) - 1 do
					local body = Unit.actor(unit, i)

					if body and Actor.node(body) == state.node_index then
						mod:info("[object]   body %d of the bone %s: physical=%s dynamic=%s static=%s sleeping=%s is_hit=%s", i, tostring(state.node_index), tostring(Actor.is_physical(body)), tostring(Actor.is_dynamic(body)), tostring(Actor.is_static(body)), tostring(Actor.is_sleeping(body)), tostring(body == actor))
					end
				end
			else
				state.hold_distance = math.clamp(Vector3.length(Vector3.flat(Unit.world_position(unit, 0) - Unit.world_position(owner_unit, 0))), CONFIG.hold_min_distance, CONFIG.beam_range)
			end
		end

		if state.target then
			if state.kind == "supply" then
				if pull_supply(state, owner_unit, dt) then
					release_target(state)

					state.link_block_until = t + CONFIG.supply_retry
				end
			elseif state.kind == "monster" then
				-- (a monster is too big to be held: the beam stays on it, and when it moves the owner is launched
				-- towards it and the link is over)
				-- Trying to yank it does the same at once.
				local moved = Vector3.length(Vector3.flat(Unit.world_position(state.target, 0) - state.monster_start:unbox()))
				local input_extension = ScriptUnit.has_extension(owner_unit, "input_system")
				local yanked = input_extension ~= nil and input_extension:get("action_one")

				if yanked and not pose.locked_out() then
					Unit.animation_event(first_person_extension:get_first_person_unit(), CONFIG.yank_animation_event)
				end

				if yanked or moved >= CONFIG.monster_move_distance then
					launch_towards_monster(state, owner_unit, state.target, t)
					release_target(state)
				else
					damage_enemy(state, owner_unit, t)
				end
			elseif state.kind == "object" then
				local input_extension = ScriptUnit.has_extension(owner_unit, "input_system")

				if input_extension and input_extension:get("action_one") then
					state.yank = true

					if not pose.locked_out() then
						Unit.animation_event(first_person_extension:get_first_person_unit(), CONFIG.yank_animation_event)
					end
				end

				hold_object(state, aim, origin, dt)
			elseif state.kind == "enemy" then
				local input_extension = ScriptUnit.has_extension(owner_unit, "input_system")

				if input_extension and input_extension:get("action_one") then
					state.yank = true

					if not pose.locked_out() then
						Unit.animation_event(first_person_extension:get_first_person_unit(), CONFIG.yank_animation_event)
					end
				end

				hold_enemy(state, owner_unit, t, dt, aim, physics_world)
				damage_enemy(state, owner_unit, t)
			else
				boost_ally(state, owner_unit, t)
			end
		end
	end

	-- the end of the beam: what it is linked to, or where it hits
	local end_position
	local color = CONFIG.beam_color

	if state.target and Unit.alive(state.target) then
		end_position = target_position(state)
		color = ((state.kind == "enemy" or state.kind == "monster") and CONFIG.held_beam_color) or ((state.kind == "object" or state.kind == "supply") and CONFIG.object_beam_color) or CONFIG.ally_beam_color
	else
		local range = CONFIG.beam_range
		local hit, hit_position = PhysicsWorld.immediate_raycast(physics_world, origin, aim, range, "closest", "collision_filter", "filter_player_ray_projectile_static_only")

		end_position = hit and hit_position or origin + aim * range
	end

	local lag = state.kind == "enemy" and state.lag and state.lag:unbox() or nil

	draw_beam(state, world, staff_position(owner_unit, first_person_extension, origin, rotation), rotation, end_position, state.kind == "enemy" and state.weight or nil, lag, color)
end

-- The beam ends when the button is let go (or it is left for something else)
mod:hook_safe(ActionCharge, "finish", function (self)
	local action = self.current_action

	if action and action.ut_charge_callback == "link" then
		end_beam(self.owner_unit)
	end
end)

-- Enabling and disabling
local function is_link_gun_enabled()
	return mod:get("ut_weapons") ~= false and mod:get("link_gun") ~= false
end

-- Wielding the staff: the stance is entered after a moment
mod.wield_callbacks.link = function (self, equipment, slot_data, unit_1p)
	if not slot_data then
		return
	end

	-- (whatever is wielded, what was going on with the staff's stance ends, and the arm is back)
	pose.clear()
	pose.entered = false
	hand.show()

	local item_template = BackendUtils.get_item_template(slot_data.item_data)

	if item_template.name ~= TEMPLATE_NAME or not is_link_gun_enabled() or not has_staff then
		return
	end

	local function is_valid()
		return equipment.wielded == slot_data.item_data
	end

	if self.first_person_extension then
		hand.hide(self.first_person_extension)
	end

	pose.overcharge_extension = ScriptUnit.has_extension(self._unit, "overcharge_system")
	pose.health_extension = ScriptUnit.has_extension(self._unit, "health_system")
	pose.is_valid = is_valid
	pose.unit_1p = unit_1p
	pose.recovering = false

	pose.schedule(CONFIG.idle_pose_delay, is_valid, function ()
		pose.enter(unit_1p)
	end)
end

local previous_on_enabled = mod.on_enabled
local previous_on_disabled = mod.on_disabled
local previous_on_setting_changed = mod.on_setting_changed
local previous_on_unload = mod.on_unload
local previous_update = mod.update

mod.update = function (dt, ...)
	if previous_update then
		previous_update(dt, ...)
	end

	pose.update(dt)
	hand.update()
	update_bolts()
end

mod.on_enabled = function (...)
	if previous_on_enabled then
		previous_on_enabled(...)
	end

	if is_link_gun_enabled() then
		apply_link_gun()
	end
end

local function clear_beams()
	for owner_unit in pairs(states) do
		end_beam(owner_unit)
	end

	restore_corpse()
	pose.clear()
	hand.show()
	table.clear(bolts)
end

mod.on_disabled = function (...)
	if previous_on_disabled then
		previous_on_disabled(...)
	end

	clear_beams()
	restore_staff()
end

mod.on_setting_changed = function (setting_id, ...)
	if previous_on_setting_changed then
		previous_on_setting_changed(setting_id, ...)
	end

	if setting_id == "link_gun" or setting_id == "ut_weapons" then
		if is_link_gun_enabled() then
			apply_link_gun()
		else
			clear_beams()
			restore_staff()
		end
	end
end

mod.on_unload = function (...)
	if previous_on_unload then
		previous_on_unload(...)
	end

	clear_beams()
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	clear_beams()
end
