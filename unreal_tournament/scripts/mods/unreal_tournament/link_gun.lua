local mod = get_mod("unreal_tournament")

-- Link Gun: replaces the Deepwood Staff's (the Thornsister's, the template staff_life) actions in place.
-- The numbers are from UT2004 (XWeapons/LinkFire, LinkAltFire, LinkProjectile, LinkBeamEffect).
--   LMB: the staff's burst of thorns, which stun as well as hurt.
--   RMB (held): the link beam. What the aim is on is linked to: an ally does more damage for as long as the link
--               lasts (UT's link, a teammate), an enemy is held where it is and follows the aim along the
--               ground, a heavy one slower, with the beam hanging more.
-- What happens to enemies is done by the game that has them, the host's. The beam is drawn for the player who holds it,
-- as a curve from the staff in the hands; the player tells the others where it ends, and they draw a straight one from
-- the staff of the player's character.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local effects = mod.effects
local with_valid_positions = utils.with_valid_positions
local register_damage_profile = utils.register_damage_profile

local stagger_types = require("scripts/utils/stagger_types")

local TEMPLATE_NAME = "staff_life"

local CONFIG = {
	-- The default stance of both fire modes: the stance of the alt fire (its animation event). It is entered
	-- idle_pose_delay seconds after the staff is wielded (the raise plays until then), and the beam and venting end
	-- in it.
	idle_pose_event = "attack_charge_fireball",
	idle_pose_delay = 0.4,
	transition_pose_delay = 0.5, -- seconds after the weapons are shown again, after a ladder or the like, that the stance is entered again
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
	bolt_damage_scale = 1.6, -- how much more damage a bolt does than the staff's thorns did
	-- Beam (UT: TraceRange 1100 uu, 1.5 times that while linked; here the link holds until the beam is let go, or the
	-- target is further away than that)
	beam_range = 22, -- m
	linked_range_scale = 1.5,
	aim_dot = 0.985, -- how close to the aim a target has to be to be linked to, 1 is exactly
	beam_overcharge = 0.8, -- heat, added every beam_overcharge_interval seconds while the beam is held
	beam_overcharge_interval = 0.25,
	-- Ally: the damage it does is this much more while linked, the buff is kept up every buff_refresh seconds
	ally_damage_bonus = 0.5,
	ally_thp_multiplier = 2, -- the temporary health a linked ally gets from their attacks
	ally_buff_duration = 0.6, -- seconds
	ally_buff_refresh = 0.25, -- seconds
	bot_target_range = 80,
	bot_rescan_interval = 0.5, -- seconds, between looks for an enemy for a linked bot that has none near -- m, how far from a linked bot the enemy it is made to attack can be
	throw_wall_margin = 0.6, -- m, how far from a wall a yanked enemy that hit it lands
	throw_wall_height = 0.9, -- m above the feet of a yanked enemy, the height that a wall is looked for at
	openable_reach_margin = 10, -- m past the reach of the beam that a door or a chest can still be looked at (they are big)
	rescue_retry_interval = 0.5, -- seconds between the times that a yank gives a rescue again, until it has taken
	rescue_max_tries = 4,
	beam_aim_curve_gain = 1.3, -- what the aim bows the first half of the beam by, on top of beam_aim_curve
	beam_hang_share = 0.7, -- how much of what hangs and lags a beam bends the first half by
	ally_effect = "fx/thornsister_buff", -- what is seen on an ally that is linked, a burst again every ally_effect_interval
	ally_effect_interval = 0.8, -- seconds
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
	disabler_stagger_duration = 2, -- seconds a disabler is staggered for when a yank frees a player from it
	restagger_interval = 1,
	-- A linked enemy (and a monster) is poisoned: the game's own poison of poisoned arrows, dot_template, at
	-- dot_power_level (what its damage scales with), applied again every dot_interval seconds, which keeps it up
	-- while it is linked.
	dot_template = "arrow_poison_dot",
	dot_power_level = 500,
	dot_interval = 1,
	dot_overcharge = 1, -- heat of every application of it, on top of the heat of the beam
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
	-- What is picked to link to is the most important of what the aim is on, in this order: living things (enemies,
	-- monsters, players and bots), supplies and doors (within supply_aim_dot of the aim, they are small or thin),
	-- objects. What is linked stays linked until the beam is let go.
	-- Supplies (pickups) that the owner can pick up stay where they are while they are linked. Yanking one picks it up
	-- (the game's own interaction), tried again after supply_retry seconds.
	supply_aim_dot = 0.98,
	supply_retry = 0.6, -- seconds
	-- Doors and chests: yanking a door opens it, or closes it. The aim has to be on the door or the chest itself. The beam
	-- ends in the middle of it. A door that is broken or a chest that is opened isn't linked.
	-- The outline of an enemy that is held (alpha, red, green, blue)
	held_outline_color = {255, 60, 230, 190},
	-- Yanking costs heat on top of the heat of the beam: yank_free_overcharge for freeing an enemy from a vortex or a
	-- player from a disabler or a vortex, yank_rescue_overcharge for pulling a player up from a ledge or getting them
	-- up from being knocked down, yank_player_overcharge for launching a player (or a bot) at the owner,
	-- yank_door_overcharge for a door or a chest.
	yank_free_overcharge = 8,
	yank_rescue_overcharge = 10,
	yank_player_overcharge = 25,
	bot_yank_cost_scale = 0.1, -- yanking a bot costs this much of what yanking a player does (the cost is for griefing)
	yank_door_overcharge = 2,
	-- Objects: when nothing else is picked, a ragdoll or another object with a body that moves is held (no damage). It
	-- is held in the air where the aim is, the body that was linked is given object_pull per second of the way to
	-- there as speed, at most object_max_speed. An enemy that dies while it is held is held on as a corpse.
	object_collision_filter = "filter_explosion_overlap",
	object_pull = 20,
	object_max_speed = 35, -- m/s
	-- The beam: drawn as a curve (a cubic Bezier) from the staff to what it is on. A held enemy hangs it by
	-- its weight (sag_per_weight a meter per meter of beam, per unit of weight, at most sag_max), and bends it
	-- by how far the enemy is behind where it is being moved to (lag_bend).
	staff_end_node = "fx_muzzle", -- the node at the end of the staff unit, where the beam and the bolts start
	-- The beam effect is drawn with the field of view of the staff in the hands, not of the world (vertical, degrees: the
	-- world's is read from the camera, every frame). Measured from where the beam ended on screenshots, with a world fov of
	-- 85: the end was seen about 2.1 times as far from the middle of the screen as the target.
	effect_fov = 47.5,
	beam_aim_curve = 0.3, -- how far the beam bows towards the aim, as a share of its length at most: 0 is a straight line
	beam_segment_length = 0.2, -- m, about how far apart the points of the beam are (the particles)
	beam_min_segments = 2,
	beam_max_segments = 100,
	beam_sprite_copies = 3, -- how many copies of the effect at every point: the more, the denser the beam
	sag_per_weight = 0.015,
	sag_max = 2.5, -- m
	lag_bend = 0.5,
	lag_bend_max = 1.5, -- m
	-- The beam is drawn with a copy of this particle effect at every point of the curve (it has no settings, so it is only
	-- placed), the Thornsister's own, green.
	beam_effect = "fx/lifestaff_idle",
	-- The others: the end of the beam is told to them this often, and what they draw follows it (the share of the way to it
	-- covered in a second is 1 - e^-smoothing); a beam that has not been heard of for the timeout is over
	beam_send_interval = 0.05, -- seconds
	remote_beam_smoothing = 20,
	remote_beam_timeout = 0.5, -- seconds
	-- The beams of players that are not the host: what they can link to (the host works what it does out from what they say),
	-- and how long the host goes on with a beam it has heard nothing of
	remote_link_kinds = {ally = true},
	remote_input_timeout = 0.5, -- seconds
	remote_beam_segment_length = 0.15, -- m, beam_segment_length for the beam that is seen from the outside (it looks sparser there)
	-- The field of view (vertical, degrees) the effect of a beam that is seen from the outside is drawn with: found by eye with a
	-- world field of view of 65, the beam is then where it is seen. (effect_fov, above, is the staff in the hands seen from the
	-- holder's side: they are not the same.)
	remote_effect_fov = 55,
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

		-- (stronger than the thorns were)
		target.power_distribution_near.attack = target.power_distribution_near.attack * CONFIG.bolt_damage_scale
		target.power_distribution_far.attack = target.power_distribution_far.attack * CONFIG.bolt_damage_scale

		-- (the bolts poison, as the beam does)
		target.dot_template_name = CONFIG.dot_template
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

utils.register_network_lookup("buff_templates", ALLY_BUFF)

-- Weapon template
-- The template is shared game state: it is patched in place, what is touched is saved to be put back on disable.
-- It is put back when the mod is unloaded too (a reload would take the patched template for the original).
local saved = {}

-- The default stance. Delayed pose events: the animation event is only sent while is_valid() still holds, so
-- nothing is sent if the weapon was swapped or another action started in the meantime.
local pose = {}
local scheduler = utils.delayed_events()

pose.schedule = scheduler.schedule

-- (the staff isn't idle while an action runs, every action calls this when it starts)
function pose.clear()
	scheduler.clear()

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
function pose.enter(unit_1p, owner_unit)
	if pose.locked_out() then
		pose.waiting = unit_1p
		pose.waiting_owner = owner_unit

		return
	end

	pose.waiting = nil
	pose.entered = true

	Unit.animation_event(unit_1p, CONFIG.idle_pose_event)
	-- (the others see the stance too: the event is sent to the third person unit, the game doesn't send it for this)
	Managers.state.network:anim_event(owner_unit, CONFIG.idle_pose_event)
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

	if mod.draw_pending_beams then
		mod.draw_pending_beams()
	end
end)

local IGNORED_DAMAGE_TYPES = {
	aoe_poison_dot = true,
	arrow_poison_dot = true,
	buff = true,
	buff_shared_medpack = true,
	buff_shared_medpack_temp_health = true,
	burninating = true,
	damage_over_time = true,
	gas = true,
	heal = true,
	health_degen = true,
	level = true,
	life_drain = true,
	life_tap = true,
	plague_ground = true,
	poison = true,
	temporary_health_degen = true,
	volume_generic_dot = true,
	vomit_ground = true,
	warpfire_ground = true,
	wounded_dot = true,
}

function pose.update(dt)
	-- Taking damage plays a reaction that takes the staff out of the stance: it is entered again after it
	local health_extension = pose.health_extension

	if health_extension and pose.is_valid and pose.is_valid() and not pose.recovering then
		-- (the extension can be one that is gone, after a death or at the end of a level: it is then let go of)
		local ok, damage_datas, num_damages = pcall(health_extension.recent_damages, health_extension)

		if not ok then
			pose.health_extension = nil
			num_damages = 0
		end

		for i = 1, num_damages / DamageDataIndex.STRIDE do
			local offset = (i - 1) * DamageDataIndex.STRIDE

			-- (damage that is only a tick of something that goes on, the degrading of temporary health, poison, burning,
			-- doesn't play a reaction: the ones that the game's interactions don't mind either)
			if damage_datas[offset + DamageDataIndex.DAMAGE_AMOUNT] > 0 and not IGNORED_DAMAGE_TYPES[damage_datas[offset + DamageDataIndex.DAMAGE_TYPE]] then
				pose.recovering = true
				pose.entered = false

				pose.schedule(CONFIG.damage_recovery_delay, pose.is_valid, function ()
					pose.recovering = false

					pose.enter(pose.unit_1p, pose.owner_unit)
				end)

				break
			end
		end
	end

	if pose.waiting then
		if not pose.is_valid or not pose.is_valid() then
			pose.waiting = nil
		elseif not pose.locked_out() then
			pose.enter(pose.waiting, pose.waiting_owner)
		end
	end

	scheduler.update(dt)
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
	local original = saved.original
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not original or not template then
		return
	end

	local actions = template.actions

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

	local inspect = actions.action_inspect.action_inspect_hold

	inspect.anim_end_event = original.inspect_anim_end_event
	inspect.enter_function = original.inspect_enter_function

	actions.action_two.default = original.action_two_default

	saved.original = nil
end

-- The beam effect of the staff comes with the packages that the game only loads for the one who plays the Thornsister (for
-- the others it loads the staff of the third person only): the mod holds a reference to the staff in the hands and to
-- the Thornsister's while the weapon is enabled, so that the others can draw the beam.
local packages = utils.package_holder("unreal_tournament_link")
local BEAM_PACKAGES = {
	"units/weapons/player/wpn_we_life_staff_01/wpn_we_life_staff_01",
	"resource_packages/careers/we_thornsister",
}

local function apply_link_gun()
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not template or not has_staff then
		return
	end

	packages.load(BEAM_PACKAGES)

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

	saved.original = original

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

				pose.enter(weapon_extension.first_person_extension:get_first_person_unit(), (...))
			end

			if saved.enter_function then
				return saved.enter_function(...)
			end
		end
	end

	-- Inspecting ends in the stance too (the end event of the game takes the staff to its own idle)
	local inspect = actions.action_inspect.action_inspect_hold

	original.inspect_anim_end_event = inspect.anim_end_event
	original.inspect_enter_function = inspect.enter_function
	inspect.anim_end_event = CONFIG.idle_pose_event
	inspect.enter_function = function (...)
		pose.clear()

		pose.entered = true

		if original.inspect_enter_function then
			return original.inspect_enter_function(...)
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
			pose.enter(weapon_extension.first_person_extension:get_first_person_unit(), attacker_unit)
		end

		input_extension:reset_release_input()
		input_extension:clear_input_buffer()
	end
	beam.finish_function = nil
	beam.kind = "charge"
	beam.overcharge_interval = CONFIG.beam_overcharge_interval
	beam.overcharge_type = "ut_link_beam"
	beam.ut_charge_callback = "link"
	utils.set_lookup_data(beam, TEMPLATE_NAME, "action_two", "default")

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
local bot_targets = {} -- a bot that is linked: the enemy it is made to attack
local bot_scan_after = {} -- a bot that had no enemy near: when to look again

-- The middle of a character: its spine, else the nearest the model has to one (the target dummies have none by the
-- name of the others'), else the middle of its box. The first node of a unit is where it is placed, which isn't on
-- the model of everything.
local CHEST_NODES = {"c_spine", "j_spine1", "j_spine", "j_neck", "j_head"}

local function chest_position(unit)
	for i = 1, #CHEST_NODES do
		if Unit.has_node(unit, CHEST_NODES[i]) then
			return Unit.world_position(unit, Unit.node(unit, CHEST_NODES[i]))
		end
	end

	local pose = Unit.box(unit)

	return Matrix4x4.translation(pose)
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

-- A player (or bot) who is dead and waiting for someone to set them free
local function is_awaiting_rescue(unit)
	local status_extension = Unit.alive(unit) and ScriptUnit.has_extension(unit, "status_system")

	return status_extension ~= nil and status_extension ~= false and status_extension:is_ready_for_assisted_respawn() == true
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

-- (the target is seen if nothing is in the way until within tolerance of it: for a big thing like a chest, whose middle is
-- inside it, the tolerance is how far its surface is from there)
local function has_line_of_sight(physics_world, origin, target_position, tolerance)
	local offset = target_position - origin
	local distance = Vector3.length(offset)

	if distance < 0.1 then
		return true
	end

	local hit, _, hit_distance = PhysicsWorld.immediate_raycast(physics_world, origin, offset * (1 / distance), distance, "closest", "collision_filter", "filter_ai_line_of_sight_check")

	return not hit or hit_distance > distance - (tolerance or 0.5)
end

-- A supply: a pickup that is picked up, not moved about. A pickup that has a health of its own is a barrel.
local function is_supply(unit)
	return ScriptUnit.has_extension(unit, "pickup_system") ~= nil and ScriptUnit.has_extension(unit, "health_system") == nil
end

-- What is an object: a ragdoll, a barrel, anything that is not a character that is alive (the target dummies are
-- characters: they are linked as enemies, not moved about as objects)
local function is_object(unit)
	local breed = AiUtils.unit_breed(unit)

	if breed and (breed.is_player or breed.race == "dummy" or is_alive(unit)) then
		return false
	end

	-- (supplies and doors are linked as what they are, picked up and opened, not moved about; a barrel is a pickup with a
	-- health of its own, it is moved about)
	if is_supply(unit) or ScriptUnit.has_extension(unit, "door_system") then
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

-- Where a mesh of a door or a chest is now: the middle of its box, and how big it is. The meshes move with the door
-- when it opens (the box of the unit stays where the closed door was, and its bodies aren't where it is seen).
local function mesh_center(mesh)
	local ok, pose, half_extents = pcall(Mesh.box, mesh)

	if not ok or not pose then
		return nil
	end

	return Matrix4x4.translation(pose), math.max(half_extents.x, half_extents.y, half_extents.z)
end

-- The boxes of a door or a chest that the aim can be on: the box of its biggest mesh (the door itself, not the frame or
-- the hinges; it moves with the door), and for a chest the box of the unit too, which doesn't move. Each has the mesh it
-- is of, if it is of one (the beam ends in the middle of that).
local function openable_boxes(unit, with_unit_box)
	local boxes = {}
	local best_mesh, best_pose, best_half, best_size

	for i = 0, Unit.num_meshes(unit) - 1 do
		local mesh = Unit.mesh(unit, i)
		local ok, pose, half_extents

		if mesh then
			ok, pose, half_extents = pcall(Mesh.box, mesh)
		end

		if ok and pose then
			local size = math.max(half_extents.x, half_extents.y, half_extents.z)

			if not best_size or size > best_size then
				best_mesh = mesh
				best_pose = pose
				best_half = half_extents
				best_size = size
			end
		end
	end

	if best_mesh then
		boxes[#boxes + 1] = {
			half = best_half,
			mesh = best_mesh,
			pose = best_pose,
		}
	end

	if with_unit_box then
		local pose, half_extents = Unit.box(unit)

		boxes[#boxes + 1] = {
			half = half_extents,
			pose = pose,
		}
	end

	return boxes
end

-- How far along the aim it hits a box (a pose and half sizes), or nil if it doesn't: the box is what is seen, not a ball
-- around its middle
-- (one axis of it: where the ray is inside the slab of this half size, narrowing near and far; nil if it never is)
local function slab(o, d, h, near, far)
	if math.abs(d) < 0.000001 then
		if math.abs(o) > h then
			return nil
		end

		return near, far
	end

	local t1, t2 = (-h - o) / d, (h - o) / d

	near = math.max(near, math.min(t1, t2))
	far = math.min(far, math.max(t1, t2))

	if near > far then
		return nil
	end

	return near, far
end

local function ray_hits_box(origin, aim, pose, half)
	local inverse = Matrix4x4.inverse(pose)
	local from = Matrix4x4.transform(inverse, origin)
	local direction = Matrix4x4.transform(inverse, origin + aim) - from
	local near, far = slab(from.x, direction.x, half.x, 0, math.huge)

	if not near then
		return nil
	end

	near, far = slab(from.y, direction.y, half.y, near, far)

	if not near then
		return nil
	end

	near = slab(from.z, direction.z, half.z, near, far)

	return near
end

local openables = {} -- the doors and the chests near enough: the unit, is it a chest

-- What the aim is on, closest to it: an enemy that can be held or an ally, and failing those an object with a body
-- that moves (a ragdoll). Returns the unit and what it is, and for an object its body and how far it is.
local function find_target(owner_unit, physics_world, origin, aim)
	local side = Managers.state.side.side_by_unit[owner_unit]
	local range = CONFIG.beam_range
	local best_unit, best_kind, best_actor
	local best_dot = CONFIG.aim_dot

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

	-- A player waiting to be set free (the game leaves them out of the lists of the side, they aren't alive yet)
	for _, player in pairs(Managers.player:human_and_bot_players()) do
		local unit = player.player_unit

		if unit and unit ~= owner_unit and is_awaiting_rescue(unit) then
			consider(unit, "ally")
		end
	end

	-- The necromancer's skeletons are friendlies too: they are units of the heroes' side that the AI looks after
	if heroes then
		count = AiUtils.broadphase_query(origin + aim * (range / 2), range / 2 + 2, ai_units, heroes.broadphase_category)

		for i = 1, count do
			local unit = ai_units[i]
			local breed = HEALTH_ALIVE[unit] and AiUtils.unit_breed(unit)

			if breed and not breed.is_player and string.find(breed.name or "", "^pet_") then
				consider(unit, "ally")
			end
		end
	end

	-- Nothing living: supplies (what can be picked up) and doors, a little more forgiving of the aim, they are small
	-- or thin
	if not best_unit then
		best_dot = math.min(best_dot, CONFIG.supply_aim_dot)

		-- (what is further than the beam reaches, with room for how big a door is, isn't looked at: this runs every frame that
		-- nothing is linked, and the boxes of a door are worked out from its meshes)
		local reach_squared = (range + CONFIG.openable_reach_margin) * (range + CONFIG.openable_reach_margin)

		table.clear(openables)

		-- (one pass over the interactables: the supplies are considered, the chests kept for below)
		for unit in pairs(Managers.state.entity:get_entities("GenericUnitInteractableExtension")) do
			local position = POSITION_LOOKUP[unit] or Unit.world_position(unit, 0)

			if position and Vector3.distance_squared(position, origin) <= reach_squared and Unit.alive(unit) then
				if is_supply(unit) then
					consider(unit, "supply")
				elseif Unit.get_data(unit, "interaction_data", "interaction_type") == "chest" and not Unit.get_data(unit, "interaction_data", "used") then
					-- (a chest that has been opened is done with: the game marks it used, and takes the interaction away)
					local interactable_extension = ScriptUnit.has_extension(unit, "interactable_system")

					if interactable_extension and interactable_extension:is_enabled() then
						openables[unit] = true
					end
				end
			end
		end

		-- Doors and chests: the aim has to be on the thing, on the box of what is seen (the nearest one that it hits)
		if not best_unit then
			local best_distance

			for unit in pairs(Managers.state.entity:get_entities("DoorExtension")) do
				local position = POSITION_LOOKUP[unit] or Unit.world_position(unit, 0)
				local door_extension = position and Vector3.distance_squared(position, origin) <= reach_squared and ScriptUnit.has_extension(unit, "door_system")

				-- (a door that is broken is done with)
				if door_extension and not door_extension.dead then
					openables[unit] = false
				end
			end

			for unit, is_chest in pairs(openables) do
				if Unit.alive(unit) then
					local boxes = openable_boxes(unit, is_chest)

					for i = 1, #boxes do
						local distance = ray_hits_box(origin, aim, boxes[i].pose, boxes[i].half)

						if distance and distance <= range and (not best_distance or distance < best_distance) and has_line_of_sight(physics_world, origin, origin + aim * distance) then
							best_unit = unit
							best_kind = "openable"
							best_distance = distance
							best_actor = boxes[i].mesh
						end
					end
				end
			end
		end
	end

	if best_unit then
		return best_unit, best_kind, best_actor
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

-- Puts a body somewhere (used for the objects that physics doesn't drive, which are moved by the script)
local function place_body(pickup, body, position, rotation)
	-- (a body that can't be teleported is moved by moving its unit)
	if body and pcall(Actor.teleport_position, body, position) then
		if rotation then
			Actor.teleport_rotation(body, rotation)
		end

		if Actor.is_physical(body) then
			Actor.set_velocity(body, Vector3.zero())
			Actor.set_angular_velocity(body, Vector3.zero())
		end
	else
		Unit.set_local_position(pickup, 0, position)

		if rotation then
			Unit.set_local_rotation(pickup, 0, rotation)
		end
	end
end

-- A supply that is linked stays where it is, and is picked up when it is yanked: the game's own interaction, which the
-- owner starts, and which has the game do all of it (the checks, the inventory, the sounds, the removal of the
-- pickup). It is held by the button of the beam, which is down.
local function pick_up_supply(state, owner_unit, t)
	local pickup = state.target
	local interactor_extension, interaction_type = supply_interaction(owner_unit, pickup)

	if interactor_extension then
		interactor_extension:start_interaction("action_two_hold", pickup, interaction_type)
	end

	-- (the link is over, and doesn't come back to the same pickup while it is being picked up)
	state.picked_up = true
	state.link_block_until = t + CONFIG.supply_retry
end

-- The throw of a held enemy (primary): an arc from where it is to in front of the owner. An AI unit is moved by the
-- script for the flight (script driven, it would be put back on the navmesh by the game otherwise) and gets its own
-- movement and the ground back where it lands.
local throwing_units = {} -- the units that are in the air of a throw

local function finish_throw(state)
	local thrown = state.throw

	state.throw = nil

	local unit = state.target

	if unit then
		throwing_units[unit] = nil
	end

	if not thrown or not unit or not Unit.alive(unit) then
		return
	end

	local locomotion_extension = ScriptUnit.has_extension(unit, "locomotion_system")

	-- (not a unit that has died in the air: the game has taken its locomotion down, putting it back in the updates of
	-- the locomotion crashes the game)
	if locomotion_extension and locomotion_extension.teleport_to and HEALTH_ALIVE[unit] then
		local land = thrown.land:unbox()
		local nav_world = Managers.state.entity:system("ai_system"):nav_world()
		local on_navmesh, altitude = GwNavQueries.triangle_from_position(nav_world, land, 4, 4)

		if on_navmesh then
			land.z = altitude

			locomotion_extension:teleport_to(land)
		end

		locomotion_extension:set_movement_type(thrown.movement_type or "snap_to_navmesh")
	end
end

-- The yank of an enemy, simply: it lands where the owner is, on the navmesh, and flies there in a straight line, with
-- a lift that is only for looks. The landing is the nearest place of the navmesh to where it would be in front of
-- the owner (taken from far above or below, so it doesn't matter where the owner is in height), or else the place
-- of the navmesh the owner stands on. What is in between is checked as it flies (update_throw): a wall ends the flight.
local function start_throw(state, owner_unit, t)
	local unit = state.target
	local locomotion_extension = ScriptUnit.has_extension(unit, "locomotion_system")
	local is_ai = locomotion_extension ~= nil and locomotion_extension.teleport_to ~= nil
	local current = Unit.world_position(unit, 0)
	local aim_flat = state.flat_aim and state.flat_aim:unbox() or Vector3.forward()
	local owner_position = Unit.world_position(owner_unit, 0)
	local land = owner_position + aim_flat * CONFIG.yank_min_distance

	-- (what isn't an AI unit, a target dummy, lands where it is: there is no navmesh to look for)
	if is_ai then
		local nav_world = Managers.state.entity:system("ai_system"):nav_world()
		local owner_locomotion_extension = ScriptUnit.has_extension(owner_unit, "locomotion_system")
		local candidates = {
			land,
			owner_position,
			owner_locomotion_extension and owner_locomotion_extension.last_position_on_navmesh and owner_locomotion_extension:last_position_on_navmesh() or nil,
		}

		land = nil

		for i = 1, 3 do
			local candidate = candidates[i]

			if candidate then
				local on_navmesh, altitude = GwNavQueries.triangle_from_position(nav_world, candidate, 4, 4)

				if on_navmesh then
					land = Vector3(candidate.x, candidate.y, altitude)

					break
				end
			end
		end
	end

	if not land or Vector3.length(land - current) < 0.5 then
		state.hold_distance = CONFIG.yank_min_distance

		return
	end

	local lift = math.max(0.5, CONFIG.throw_height / state.weight)
	local distance = Vector3.length(land - current)

	if state.throw then
		finish_throw(state)
	end

	throwing_units[unit] = true

	state.throw = {
		duration = math.clamp(distance / (CONFIG.yank_speed / state.weight), CONFIG.throw_min_duration, CONFIG.throw_max_duration),
		land = Vector3Box(land),
		lift = lift,
		movement_type = is_ai and locomotion_extension.movement_type or nil,
		previous = Vector3Box(current),
		start = Vector3Box(current),
		t0 = t,
	}
	state.hold_distance = CONFIG.yank_min_distance
end

-- true while it is in the air
local function update_throw(state, t, physics_world)
	local thrown = state.throw
	local unit = state.target
	local progress = math.clamp((t - thrown.t0) / thrown.duration, 0, 1)
	local position = Vector3.lerp(thrown.start:unbox(), thrown.land:unbox(), progress) + Vector3(0, 0, thrown.lift * 4 * progress * (1 - progress))
	local locomotion_extension = ScriptUnit.has_extension(unit, "locomotion_system")

	-- A wall on the way from where it was a frame ago (at the height of the chest) ends the flight there: it lands on the
	-- navmesh a little before the wall
	local previous = thrown.previous:unbox()
	local offset = position - previous
	local distance = Vector3.length(offset)

	if distance > 0.01 then
		local chest = Vector3(0, 0, CONFIG.throw_wall_height)
		local direction = offset * (1 / distance)
		local hit, hit_position = PhysicsWorld.immediate_raycast(physics_world, previous + chest, direction, distance + CONFIG.throw_wall_margin, "closest", "collision_filter", "filter_player_ray_projectile_static_only")

		if hit then
			local nav_world = Managers.state.entity:system("ai_system"):nav_world()
			local stop = hit_position - direction * CONFIG.throw_wall_margin - chest
			local on_navmesh = GwNavQueries.triangle_from_position(nav_world, stop, 4, 4)

			thrown.land = Vector3Box(on_navmesh and stop or previous)
			finish_throw(state)

			return false
		end
	end

	thrown.previous:store(position)

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

-- A unit that is in the fall of the game while it is thrown (the game sees it falling) is moved by the script, which takes
-- its mover away, and the fall looks for the mover to see if it has landed. It waits while it is in the air of the throw,
-- and when the throw is over, the fall is over: left to wait for a mover it doesn't get back, the unit would hang in the
-- air in its falling pose.
local fall_action = rawget(_G, "BTFallAction")

if fall_action then
	mod:hook(fall_action, "run", function (func, self, unit, ...)
		if not Unit.mover(unit) then
			return throwing_units[unit] and "running" or "done"
		end

		return func(self, unit, ...)
	end)
end

-- The outline of an enemy that is held, in the teal of the beam: the game's outline of marked targets, with a color of
-- its own
local HELD_OUTLINE = {
	method = "always",
	priority = 16,
	flag = "outline_unit", -- (the game's flag of an outline that isn't seen through walls)
	outline_color = {
		pulsate = false,
		pulse_multiplier = 0,
		color = CONFIG.held_outline_color,
	},
}

local clear_held_outline = utils.clear_outline

local function add_held_outline(state)
	utils.add_outline(state, state.target, HELD_OUTLINE)
end

local function release_target(state)
	finish_throw(state)
	clear_held_outline(state)

	if state.target then
		bot_targets[state.target] = nil
	end

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
	elseif state.kind == "openable" then
		-- (the mesh of the door or chest that was linked, it moves with the door when it opens: not the point the unit is
		-- placed at, its hinge, and not the box of the unit, which stays where the closed door was)
		if state.actor then
			local position = mesh_center(state.actor)

			if position then
				return position
			end
		end

		local pose = Unit.box(state.target)

		return Matrix4x4.translation(pose)
	elseif state.kind == "supply" then
		-- (the middle of the model: the unit is placed at one point of it, not the middle)
		local pose = Unit.box(state.target)

		return Matrix4x4.translation(pose)
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

	-- (a corpse that had no ragdoll when it was linked: the body nearest to the chest, once it has them)
	if not state.node_index then
		local chest = chest_position(unit)
		local nearest_actor, nearest_distance

		for i = 0, Unit.num_actors(unit) - 1 do
			local actor = Unit.actor(unit, i)

			if actor and Actor.is_physical(actor) then
				local distance = Vector3.distance(Actor.position(actor), chest)

				if not nearest_actor or distance < nearest_distance then
					nearest_actor = actor
					nearest_distance = distance
				end
			end
		end

		state.actor = nearest_actor
		state.node_index = nearest_actor and Actor.node(nearest_actor) or nil

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

	if state.kind == "object" or state.kind == "supply" or state.kind == "openable" then
		if not Unit.alive(target) then
			return false
		end
	elseif not is_alive(target) and not is_awaiting_rescue(target) then
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

	local actor = state.actor
	local unit = state.target

	if state.corpse then
		-- A corpse. The body that was linked is given the speed, the rest of a ragdoll hangs from it: gravity and the
		-- speed of the limbs act on them as they would. (A ragdoll that has lain a while is put to sleep by the game:
		-- its bodies are woken while it is held. A body that is driven by animation, a corpse that hasn't started to
		-- ragdoll, isn't physical: it waits.)
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

		if actor and Actor.is_physical(actor) then
			Actor.set_velocity(actor, velocity)
		end
	elseif actor and Actor.is_physical(actor) then
		-- Another object that physics drives: it takes the speed.
		if Actor.is_sleeping(actor) then
			Actor.wake_up(actor)
		end

		Actor.set_velocity(actor, velocity)
	else
		-- An object that physics doesn't drive (a barrel that is where it is put) is moved by the script, and stays
		-- where it is when it is let go.
		place_body(unit, actor, target_position(state) + velocity * dt)
	end
end

-- A unit that is climbing a ledge is made to leave the climb: the game's climb action gives up when what it was started
-- for (the unit being in combat or not) isn't what it is now, and puts the unit's movement and gravity back as they
-- were. Stuck in the climb, a unit that is moved away stays in its climbing pose, in the air.
local function leave_climb(blackboard)
	if blackboard.climb_state ~= nil or blackboard.is_climbing then
		blackboard.climb_action_in_combat = {}
	end
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

		start_throw(state, owner_unit, t)
	end

	local throwing = state.throw ~= nil and update_throw(state, t, physics_world)
	local owner_position = Unit.world_position(owner_unit, 0)
	local wanted = owner_position + (state.flat_aim and state.flat_aim:unbox() or Vector3.forward()) * state.hold_distance
	local current = Unit.world_position(unit, 0)
	local delta = Vector3.flat(wanted - current)
	local distance = Vector3.length(delta)

	-- (a target dummy doesn't lag, it isn't moved)
	state.lag = is_ai and Vector3Box(delta) or nil

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
		end
		-- (a target dummy is not an AI unit, it stands where it is: it is linked and damaged, not moved about, the
		-- beam stays on it wherever the aim goes)
	end

	-- (climbing a ledge forbids being staggered, and keeps the unit in the climb and its animation: a held enemy is let
	-- out of it, the stagger takes it out of the climb)
	local held_blackboard = BLACKBOARDS[unit]

	if held_blackboard and (held_blackboard.stagger_prohibited or held_blackboard.climb_state) then
		held_blackboard.stagger_prohibited = nil
		state.next_stagger_t = nil

		leave_climb(held_blackboard)
	end

	if t >= (state.next_stagger_t or 0) then
		state.next_stagger_t = t + CONFIG.restagger_interval

		local blackboard = BLACKBOARDS[unit]
		local direction = Vector3.length(delta) > 0.01 and Vector3.normalize(delta) or Vector3.forward()

		if blackboard then
			-- (the game's statistics look at the positions of the units in the stagger, the mods' update runs before
			-- the game has made them current)
			with_valid_positions(AiUtils.stagger, unit, blackboard, owner_unit, direction, 1, stagger_types.heavy, CONFIG.stagger_duration, nil, t, 1, true, false)
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
-- ally_attack_grace seconds after): told to the game's add_charge, for the beam's heat (see mod.overcharge_callbacks)
local function link_beam_is_free(owner_unit)
	local state = states[owner_unit]

	if not state or not state.target then
		return true
	end

	if state.kind == "enemy" or state.kind == "monster" then
		return false
	end

	if state.kind == "object" or state.kind == "supply" or state.kind == "openable" then
		return true
	end

	return Managers.time:time("game") - (state.ally_attack_t or -math.huge) > CONFIG.ally_attack_grace
end

mod.overcharge_callbacks.ut_link_beam = function (self, overcharge_amount)
	if not link_beam_is_free(self.unit) then
		return overcharge_amount
	end
end

-- Heat is the owner's, added on the owner's machine: the host, which works out what the beam does to what it is linked to
-- for the beams of the others, tells the owner's game to add it
local function charge_owner(owner_unit, amount, overcharge_type)
	local owner_player = Managers.player:owner(owner_unit)

	if owner_player.local_player then
		local overcharge_extension = ScriptUnit.has_extension(owner_unit, "overcharge_system")

		if overcharge_extension and amount > 0 then
			overcharge_extension:add_charge(amount, nil, overcharge_type)
		end
	else
		mod:network_send("ut_link_heat", owner_player.peer_id, amount, overcharge_type)
	end
end

mod:network_register("ut_link_heat", function (_, amount, overcharge_type)
	local owner_unit = Managers.player:local_player().player_unit

	if owner_unit then
		charge_owner(owner_unit, amount, overcharge_type)
	end
end)

-- The damage over time of a linked enemy
local function damage_enemy(state, owner_unit, t)
	if t < (state.next_dot_t or 0) then
		return
	end

	state.next_dot_t = t + CONFIG.dot_interval

	local unit = state.target

	-- (every application costs heat)
	charge_owner(owner_unit, CONFIG.dot_overcharge, "ut_link_dot")

	-- The game's own poison, the one of poisoned arrows and the like: a buff on the enemy that does the damage over
	-- time and shows it as poisoned. It is applied again every dot_interval, which keeps it up while it is linked.
	Dots.poison_dot(CONFIG.dot_template, nil, nil, CONFIG.dot_power_level, unit, owner_unit, "torso", CONFIG.dot_damage_source, 1, false, owner_unit)
end

-- The look of the buff: the Thornsister's own buff effect (what she gets when health is converted), a burst at the ally that
-- follows them, again every ally_effect_interval seconds while they are linked
local function show_ally_buff(state, world, t)
	if t < (state.next_ally_effect_t or 0) or not world or not Unit.alive(state.target) then
		return
	end

	state.next_ally_effect_t = t + CONFIG.ally_effect_interval

	local unit = state.target
	local effect_id = World.create_particles(world, CONFIG.ally_effect, Unit.world_position(unit, 0), Quaternion.identity())

	World.link_particles(world, effect_id, unit, Unit.node(unit, "root_point"), Matrix4x4.identity(), "stop")
end

-- The temporary health an ally gets from their attacks (the game's heals that come from procs of hits and kills: the
-- leech of talents and weapons) is doubled while they are linked. The host works out the heals, where the buff is.
local THP_FROM_ATTACKS = {
	heal_from_proc = true,
	leech = true,
	proc = true,
}

mod:hook(DamageUtils, "heal_network", function (func, healed_unit, healer_unit, heal_amount, heal_type, ...)
	if THP_FROM_ATTACKS[heal_type] and Unit.alive(healed_unit) then
		local buff_extension = ScriptUnit.has_extension(healed_unit, "buff_system")

		if buff_extension and buff_extension:has_buff_type(ALLY_BUFF) then
			heal_amount = heal_amount * CONFIG.ally_thp_multiplier
		end
	end

	return func(healed_unit, healer_unit, heal_amount, heal_type, ...)
end)

-- A bot that is linked attacks the nearest enemy: the bots' own urgent target (what they attack first, from where they
-- are, as they do with a boss) is set to it. (Not the priority target: that is always about an ally that is held, and the bot
-- code looks for the ally.) The game works the urgent targets out again every frame, and takes this one away, so it is set
-- again after that, below.
local function apply_bot_target(bot_unit, enemy)
	local blackboard = BLACKBOARDS[bot_unit]
	local from = POSITION_LOOKUP[bot_unit]
	local to = POSITION_LOOKUP[enemy]

	if blackboard and from and to then
		blackboard.urgent_target_enemy = enemy
		blackboard.urgent_target_distance = Vector3.length(to - from)
		blackboard.revive_with_urgent_target = false
	end
end

local function force_bot_target(bot_unit)
	-- (a bot that has the enemy it is made to attack, and it is alive, keeps it: no looking for another)
	local current = bot_targets[bot_unit]

	if current and HEALTH_ALIVE[current] then
		apply_bot_target(bot_unit, current)

		return
	end

	if (bot_scan_after[bot_unit] or 0) > Managers.time:time("game") then
		return
	end

	local player = Managers.player:owner(bot_unit)
	local position = POSITION_LOOKUP[bot_unit]

	if not player or not player.bot_player or not position then
		return
	end

	local side = Managers.state.side.side_by_unit[bot_unit]
	local count = AiUtils.broadphase_query(position, CONFIG.bot_target_range, ai_units, side and side.enemy_broadphase_categories)
	local nearest, nearest_distance

	for i = 1, count do
		local unit = ai_units[i]
		local breed = HEALTH_ALIVE[unit] and AiUtils.unit_breed(unit)

		if breed and not breed.is_player and breed.race ~= "dummy" then
			local distance = Vector3.distance_squared(POSITION_LOOKUP[unit], position)

			if not nearest_distance or distance < nearest_distance then
				nearest = unit
				nearest_distance = distance
			end
		end
	end

	bot_targets[bot_unit] = nearest

	if nearest then
		apply_bot_target(bot_unit, nearest)
	else
		-- (nothing to attack near it: looked again in a moment, not every frame)
		bot_scan_after[bot_unit] = Managers.time:time("game") + CONFIG.bot_rescan_interval
	end
end

if rawget(_G, "AIBotGroupSystem") then
	mod:hook_safe(AIBotGroupSystem, "_update_urgent_targets", function (self)
		for bot_unit, enemy in pairs(bot_targets) do
			if HEALTH_ALIVE[bot_unit] and HEALTH_ALIVE[enemy] then
				apply_bot_target(bot_unit, enemy)
			else
				bot_targets[bot_unit] = nil
			end
		end
	end)
end

local function boost_ally(state, owner_unit, t)
	if is_ally_attacking(state.target) then
		state.ally_attack_t = t
	end

	force_bot_target(state.target)

	show_ally_buff(state, state.callback_world, t)

	if t < (state.next_buff_t or 0) then
		return
	end

	state.next_buff_t = t + CONFIG.ally_buff_refresh

	-- (synced, the ally's own game works out what they do)
	Managers.state.entity:system("buff_system"):add_buff_synced(state.target, ALLY_BUFF, BuffSyncType.All, {
		attacker_unit = owner_unit,
	})
end

-- The beam is a curve from the staff to the end of it (a cubic Bezier)
local function bezier(p0, p1, p2, p3, s)
	local a = p0 * ((1 - s) * (1 - s) * (1 - s))
	local b = p1 * (3 * (1 - s) * (1 - s) * s)
	local c = p2 * (3 * (1 - s) * s * s)
	local d = p3 * (s * s * s)

	return a + b + c + d
end

-- The beam as particles: a copy of the effect at every point of the curve, placed every frame and kept until the beam
-- ends, the effects are animated and one that is made again every so often is seen at its start, where it isn't there.
-- When it ends they stop spawning particles and what is out fades on its own, instead of vanishing at once.
local function destroy_sprites(state)
	if state.sprite_ids and state.world then
		for _, effect_id in ipairs(state.sprite_ids) do
			pcall(World.stop_spawning_particles, state.world, effect_id)
		end
	end

	state.sprite_ids = nil
	state.world = nil
end

-- The points of the beam, and the points as they are seen: kept, not made every frame
local beam_points = {}
local seen_points = {}

-- (the first `count` of the points)
local function draw_sprites(state, world, effect_name, points, count)
	local ids = state.sprite_ids

	if not ids then
		ids = {}
		state.sprite_ids = ids
	end

	state.world = world

	-- (beam_sprite_copies copies of the effect at every point of the curve: a longer beam gets more, a shorter one fewer)
	local copies = CONFIG.beam_sprite_copies
	local wanted = (count - 1) * copies

	for i = #ids + 1, wanted do
		ids[i] = World.create_particles(world, effect_name, points[math.floor((i - 1) / copies) + 2], Quaternion.identity())
	end

	for i = #ids, wanted + 1, -1 do
		pcall(World.destroy_particles, world, ids[i])

		ids[i] = nil
	end

	-- (all looking along the line from the staff to the end, not along the curve: the particles of the effect move along the
	-- way it faces, they flow towards the staff and not past the end)
	local offset = points[count] - points[1]
	local length = Vector3.length(offset)
	local rotation = length > 0.001 and Quaternion.look(offset * (1 / length)) or Quaternion.identity()

	for i = 2, count do
		local to = points[i]

		for copy = 1, copies do
			World.move_particles(world, ids[(i - 2) * copies + copy], to, rotation)
		end
	end
end

local function draw_beam(state, world, camera_position, start_position, rotation, end_position, weight, lag)
	local right = Quaternion.right(rotation)
	local up = Quaternion.up(rotation)
	local length = Vector3.length(end_position - start_position)
	-- (the beam leaves the staff bowed towards the aim and arrives at the target straight on, the way from the staff to
	-- the target: the part of the aim that is sideways to that way pushes the start of the curve, by up to
	-- beam_aim_curve of the length, so it is straight when the target is right on the aim and a gentle bow when it
	-- isn't, never a hook; the end of the effect points at the target, not past it)
	local first_control = start_position + (end_position - start_position) * (1 / 3)
	local second_control = start_position + (end_position - start_position) * (2 / 3)

	if length > 0.01 then
		local direction = (end_position - start_position) * (1 / length)
		local aim = Quaternion.forward(rotation)
		local sideways = aim - direction * Vector3.dot(aim, direction)

		first_control = first_control + sideways * (length * CONFIG.beam_aim_curve * CONFIG.beam_aim_curve_gain)
	end

	local sag = weight and math.min(CONFIG.sag_max, CONFIG.sag_per_weight * weight * length) or 0
	local bend = lag and lag * CONFIG.lag_bend or Vector3.zero()
	-- (what hangs or lags bends the first half only: the beam still arrives at the target straight on; and it is never bent
	-- by more than lag_bend_max, an enemy that is far from where the aim is, held by something else, isn't a bend of
	-- the whole beam)
	if Vector3.length(bend) > CONFIG.lag_bend_max then
		bend = Vector3.normalize(bend) * CONFIG.lag_bend_max
	end

	first_control = first_control + (bend - Vector3.up() * sag) * CONFIG.beam_hang_share

	-- (a point about every beam_segment_length of the beam, so a longer one has more particles)
	local segments = math.clamp(math.ceil(length / CONFIG.beam_segment_length), CONFIG.beam_min_segments, CONFIG.beam_max_segments)

	beam_points[1] = start_position

	for i = 1, segments do
		beam_points[i + 1] = bezier(start_position, first_control, second_control, end_position, i / segments)
	end

	local count = segments + 1

	-- The effect is drawn like the staff in the hands is, with a narrower field of view than the world: a point of the
	-- world is seen further from the middle of the screen (by the ratio of the two) than where it is. The beam starts at
	-- the staff, which is drawn the same way, and ends in the world: the points are pulled towards the aim, the more
	-- the further along the beam they are, so that the end is seen on the target.
	local world_fov = math.deg(Managers.state.camera:fov("player_1"))
	local scale = math.tan(math.rad(CONFIG.effect_fov) / 2) / math.tan(math.rad(world_fov) / 2)
	local forward = Quaternion.forward(rotation)

	for i = 1, count do
		local offset = beam_points[i] - camera_position
		local factor = 1 + (scale - 1) * ((i - 1) / math.max(count - 1, 1))

		seen_points[i] = camera_position + right * (Vector3.dot(offset, right) * factor) + up * (Vector3.dot(offset, up) * factor) + forward * Vector3.dot(offset, forward)
	end

	draw_sprites(state, world, CONFIG.beam_effect, seen_points, count)
end

local function end_beam(owner_unit)
	local state = states[owner_unit]

	if state then
		-- (the others stop drawing it, and the host stops doing what the link does if it is the one that does)
		local owner_go_id = (state.beam_sent or state.input_sent) and Unit.alive(owner_unit) and Managers.state.unit_storage:go_id(owner_unit)

		if owner_go_id then
			mod:network_send("ut_link_beam_end", "others", owner_go_id)

			if state.input_sent then
				mod:network_send("ut_link_input_end", "others", owner_go_id)
			end
		end

		finish_throw(state)
		clear_held_outline(state)
		destroy_sprites(state)

		if state.target then
			bot_targets[state.target] = nil
		end

		states[owner_unit] = nil
	end
end

-- What is linked to
local function link_target(state, owner_unit, unit, kind, actor, object_distance)
	state.target = unit
	state.kind = kind
	state.actor = actor
	state.weight = kind == "enemy" and enemy_weight(unit) or nil
	state.next_stagger_t = nil
	state.next_buff_t = nil
	state.next_dot_t = nil
	state.hold_distance = math.clamp(Vector3.length(Vector3.flat(Unit.world_position(unit, 0) - Unit.world_position(owner_unit, 0))), CONFIG.hold_min_distance, CONFIG.beam_range)

	if kind == "enemy" or kind == "monster" or kind == "supply" or kind == "openable" or kind == "object" then
		add_held_outline(state)
	end

	if kind == "monster" then
		state.monster_start = Vector3Box(Unit.world_position(unit, 0))
	elseif kind == "object" then
		state.hold_distance = math.clamp(object_distance, CONFIG.yank_min_distance, CONFIG.beam_range)
		state.node_index = Actor.node(actor)
		state.thawed = false
		state.corpse = AiUtils.unit_breed(unit) ~= nil

		if state.corpse then
			preserve_corpse(unit)
		end
	end
end

-- Yanking is pressing primary, once for every press: held down it isn't one
local function yank_pressed(state, owner_unit)
	local input_extension = ScriptUnit.has_extension(owner_unit, "input_system")
	local down = input_extension ~= nil and input_extension:get("action_one_hold") == true
	local pressed = down and not state.yank_was_down

	state.yank_was_down = down

	return pressed
end

-- Heat on top of the heat of the beam
local function add_heat(owner_unit, amount)
	charge_owner(owner_unit, amount, "ut_link_yank")
end

-- Yanking an enemy: out of a vortex if it is in one (at a cost), else it is thrown to the owner
local function yank_enemy(state, owner_unit)
	local blackboard = BLACKBOARDS[state.target]

	if blackboard and blackboard.in_vortex then
		blackboard.in_vortex = false
		blackboard.thornsister_vortex = nil

		add_heat(owner_unit, CONFIG.yank_free_overcharge)

		return
	end

	state.yank = true
end

-- Getting someone up by a yank is the game's own result of the interaction (what the game does when it is over), but
-- the other half is the animation of the one who is got up, which the interaction plays itself (the fall of being knocked
-- down is only left with it), and the state of the one who is got up isn't always ready to take the result when it is
-- given (in the middle of going down, say): it is given again, a few times, until it has taken it.
local pending_rescues = {} -- the unit: { kind, owner, next_t, tries }

local function give_rescue(unit, kind, owner_unit)
	if kind == "revive" then
		StatusUtils.set_revived_network(unit, true, owner_unit)
	else
		StatusUtils.set_pulled_up_network(unit, true, owner_unit)
	end

	CharacterStateHelper.play_animation_event(unit, "revive_complete")
end

local function update_pending_rescues(t)
	for unit, pending in pairs(pending_rescues) do
		local status_extension = Unit.alive(unit) and ScriptUnit.has_extension(unit, "status_system")
		local still_waiting = status_extension and (pending.kind == "revive" and status_extension:is_knocked_down() or pending.kind == "pull_up" and status_extension:get_is_ledge_hanging())

		if not still_waiting or pending.tries >= CONFIG.rescue_max_tries then
			pending_rescues[unit] = nil
		elseif t >= pending.next_t then
			pending.tries = pending.tries + 1
			pending.next_t = t + CONFIG.rescue_retry_interval

			give_rescue(unit, pending.kind, pending.owner)
		end
	end
end

-- Yanking a player or a bot: freed from what holds them, a disabler or a vortex; pulled up from a ledge; got up
-- from being knocked down; else launched at the owner (the state of being launched by the game's monsters). All at
-- a cost, the launch at a big one.
local function yank_ally(state, owner_unit, t)
	local unit = state.target
	local status_extension = ScriptUnit.has_extension(unit, "status_system")

	-- (the cost is high so that it isn't used to grief other players: a bot can't be griefed, it costs much less)
	local player = Managers.player:owner(unit)
	local cost_scale = player and player.bot_player and CONFIG.bot_yank_cost_scale or 1

	local game_add_heat = add_heat

	local function add_heat(owner, amount)
		return game_add_heat(owner, amount * cost_scale)
	end

	-- (waiting to be set free: the game's own way of doing it, with the owner as the one who did)
	if status_extension and status_extension:is_ready_for_assisted_respawn() then
		StatusUtils.set_respawned_network(unit, true, owner_unit)
		add_heat(owner_unit, CONFIG.yank_rescue_overcharge)

		return
	end

	if not status_extension or status_extension:is_dead() then
		return
	end

	local disabler_unit = utils.get_disabler(status_extension)

	if status_extension:is_hanging_from_hook() then
		-- (hung up on a hook by a pack master: let down, as the game's interaction does)
		StatusUtils.set_grabbed_by_pack_master_network("pack_master_dropping", unit, true, nil)
		add_heat(owner_unit, CONFIG.yank_free_overcharge)
	elseif disabler_unit then
		utils.release_from_disabler(disabler_unit, unit, t, CONFIG.disabler_stagger_duration)
		add_heat(owner_unit, CONFIG.yank_free_overcharge)
	elseif status_extension:is_in_vortex() then
		StatusUtils.set_in_vortex_network(unit, false, nil)
		add_heat(owner_unit, CONFIG.yank_free_overcharge)
	elseif status_extension:get_is_ledge_hanging() then
		give_rescue(unit, "pull_up", owner_unit)
		pending_rescues[unit] = {kind = "pull_up", owner = owner_unit, next_t = t + CONFIG.rescue_retry_interval, tries = 0}
		add_heat(owner_unit, CONFIG.yank_rescue_overcharge)
	elseif status_extension:is_knocked_down() then
		give_rescue(unit, "revive", owner_unit)
		pending_rescues[unit] = {kind = "revive", owner = owner_unit, next_t = t + CONFIG.rescue_retry_interval, tries = 0}
		add_heat(owner_unit, CONFIG.yank_rescue_overcharge)
	elseif not status_extension:is_disabled() then
		local flat = Vector3.flat(Unit.world_position(owner_unit, 0) - Unit.world_position(unit, 0))
		local distance = Vector3.length(flat)
		local direction = distance > 0.1 and flat * (1 / distance) or Vector3.forward()
		local velocity = direction * math.clamp(distance * CONFIG.monster_pull_per_meter, CONFIG.monster_pull_min_speed, CONFIG.monster_pull_max_speed)

		Vector3.set_z(velocity, CONFIG.monster_pull_up_speed)
		StatusUtils.set_catapulted_network(unit, true, velocity)
		add_heat(owner_unit, CONFIG.yank_player_overcharge)
	end
end

-- Yanking a door opens it, or closes it; a chest is opened by the game's own interaction, as a supply is picked up
local function yank_openable(state, owner_unit, t)
	local door_extension = ScriptUnit.has_extension(state.target, "door_system")

	if door_extension and door_extension.interacted_with then
		-- (the door looks at the position of whoever opens it, the mods' update runs before the game has made them current)
		with_valid_positions(door_extension.interacted_with, door_extension, owner_unit)
		add_heat(owner_unit, CONFIG.yank_door_overcharge)
	else
		local interactor_extension, interaction_type = supply_interaction(owner_unit, state.target)

		if interactor_extension then
			interactor_extension:start_interaction("action_two_hold", state.target, interaction_type)
			add_heat(owner_unit, CONFIG.yank_door_overcharge)

			-- (the link is over, and doesn't come back while the chest is being opened)
			release_target(state)

			state.link_block_until = t + CONFIG.supply_retry
		end
	end
end

-- What is linked to is chosen by the player who holds the beam, from what they see: the host's own beam picks it here,
-- the beam of someone else is picked by their game, which tells the host (see the inputs of the others below).
-- allowed_kinds limits what can be linked, nothing for everything.
local function select_target(state, owner_unit, origin, aim, t, physics_world, allowed_kinds)
	if state.target and state.kind == "object" then
		refresh_object(state)
	end

	if state.target and not is_link_valid(state, origin) then
		release_target(state)
	end

	-- What is linked stays linked, until the beam is let go: what is picked is the most important of what the aim
	-- is on (living things, supplies, doors, objects), and only when nothing is linked.
	if not state.target and t >= (state.link_block_until or 0) then
		local unit, kind, actor, object_distance = find_target(owner_unit, physics_world, origin, aim)

		-- A supply is only linked if the owner can pick it up
		if unit and kind == "supply" and not supply_interaction(owner_unit, unit) then
			state.link_block_until = t + CONFIG.supply_retry

			unit = nil
		end

		if unit and (not allowed_kinds or allowed_kinds[kind]) then
			link_target(state, owner_unit, unit, kind, actor, object_distance)
		end
	end
end

-- What happens while a beam is linked, done by the host, which has the enemies, the allies and the objects. It works from
-- where the owner's eye is, where it is aimed, and whether primary was pressed since the last frame (a yank): the owner's
-- own when the owner is the host, what the owner's game sends when it isn't (see the inputs of the others below).
local function run_link(state, owner_unit, origin, aim, yanked, dt, t, physics_world)
	if not state.target then
		return
	end

	if state.kind == "supply" then
		if yanked then
			pick_up_supply(state, owner_unit, t)
			release_target(state)
		end
	elseif state.kind == "openable" then
		if yanked then
			yank_openable(state, owner_unit, t)
		end
	elseif state.kind == "monster" then
		-- (a monster is too big to be held: the beam stays on it, and when it moves, or it is yanked, the
		-- owner is launched towards it and the link is over)
		local moved = Vector3.length(Vector3.flat(Unit.world_position(state.target, 0) - state.monster_start:unbox()))

		if yanked or moved >= CONFIG.monster_move_distance then
			launch_towards_monster(state, owner_unit, state.target, t)
			release_target(state)
		else
			damage_enemy(state, owner_unit, t)
		end
	elseif state.kind == "object" then
		state.yank = state.yank or yanked

		hold_object(state, aim, origin, dt)
	elseif state.kind == "enemy" then
		if yanked then
			yank_enemy(state, owner_unit)
		end

		hold_enemy(state, owner_unit, t, dt, aim, physics_world)
		damage_enemy(state, owner_unit, t)
	else
		local breed = AiUtils.unit_breed(state.target)

		if breed and not breed.is_player then
			-- (a skeleton: an AI unit, it is thrown to the owner like an enemy is)
			local flat_aim = Vector3.flat(aim)

			if Vector3.length(flat_aim) > 0.1 then
				state.flat_aim = Vector3Box(Vector3.normalize(flat_aim))
			end

			if yanked then
				state.weight = state.weight or 1

				start_throw(state, owner_unit, t)

				-- (let out of a climb, as a held enemy is: it can't be staggered in one, and the stagger takes it out)
				local blackboard = BLACKBOARDS[state.target]

				if blackboard and state.throw then
					blackboard.stagger_prohibited = nil
					leave_climb(blackboard)

					with_valid_positions(AiUtils.stagger, state.target, blackboard, owner_unit, Vector3.normalize(Vector3.flat(Unit.world_position(owner_unit, 0) - Unit.world_position(state.target, 0)) + Vector3(0.001, 0, 0)), 1, stagger_types.heavy, CONFIG.stagger_duration, nil, t, 1, true, false)
				end
			end

			if state.throw then
				update_throw(state, t, physics_world)
			end
		elseif yanked then
			yank_ally(state, owner_unit, t)
		end

		boost_ally(state, owner_unit, t)
	end
end

-- Whoever holds a beam on a machine that isn't the host picks what it is linked to, from what they see (so that what they see
-- is what is linked), and tells the host, with where the eye is and where it is aimed (the host holds an enemy where the aim
-- is) and when primary is pressed. The host checks the choice and does what the link does, and tells the owner's game when
-- the link is over on its side, when an ally attacks (the beam costs heat then) and the heat that the link costs.
local remote_inputs = {} -- on the host, for every owner that is not the host: { origin, aim (Vector3Boxes), yanked, received, link_request }

local function remote_input(owner_go_id)
	local owner_unit = Managers.player.is_server and Managers.state.unit_storage:unit(owner_go_id)

	if not owner_unit then
		return nil
	end

	local input = remote_inputs[owner_unit]

	if not input then
		input = {received = Application.time_since_launch()}
		remote_inputs[owner_unit] = input
	end

	return input, owner_unit
end

mod:network_register("ut_link_input", function (_, owner_go_id, x, y, z, aim_x, aim_y, aim_z, yanked)
	local input = remote_input(owner_go_id)

	if input then
		input.origin = Vector3Box(Vector3(x, y, z))
		input.aim = Vector3Box(Vector3(aim_x, aim_y, aim_z))
		-- (a yank that arrives is kept until the host has handled it, the next input doesn't take it back)
		input.yanked = input.yanked or yanked
		input.received = Application.time_since_launch()
	end
end)

-- What the owner has linked to (nothing if the game object is 0)
mod:network_register("ut_link_target", function (_, owner_go_id, target_go_id, kind)
	local input = remote_input(owner_go_id)

	if input then
		input.link_request = {kind = kind, target_go_id = target_go_id}
	end
end)

mod:network_register("ut_link_input_end", function (_, owner_go_id)
	local owner_unit = Managers.player.is_server and Managers.state.unit_storage:unit(owner_go_id)

	if owner_unit then
		remote_inputs[owner_unit] = nil

		end_beam(owner_unit)
	end
end)

-- What the host tells the owner: the link is over (the one to that game object, if it is still the one the owner has), and an
-- ally that is linked is attacking
mod:network_register("ut_link_released", function (_, target_go_id)
	local owner_unit = Managers.player:local_player().player_unit
	local state = owner_unit and states[owner_unit]

	if state and state.target and Unit.alive(state.target) and Managers.state.unit_storage:go_id(state.target) == target_go_id then
		release_target(state)
	end
end)

mod:network_register("ut_link_ally_attack", function ()
	local owner_unit = Managers.player:local_player().player_unit
	local state = owner_unit and states[owner_unit]

	if state then
		state.ally_attack_t = Managers.time:time("game")
	end
end)

-- The beams of the others that the host runs: what they do is what a beam of the host's does, from their inputs
local function update_remote_inputs(dt, t)
	if not next(remote_inputs) then
		return
	end

	local now = Application.time_since_launch()
	local world = Managers.world:world("level_world")
	local physics_world = World.physics_world(world)

	for owner_unit, input in pairs(remote_inputs) do
		if not Unit.alive(owner_unit) or now - input.received > CONFIG.remote_input_timeout then
			remote_inputs[owner_unit] = nil

			end_beam(owner_unit)
		elseif input.origin then
			local state = states[owner_unit]

			if not state then
				state = {}
				states[owner_unit] = state
			end

			local owner_peer_id = Managers.player:owner(owner_unit).peer_id
			local origin = input.origin:unbox()
			local yanked = input.yanked
			local request = input.link_request

			input.yanked = false
			input.link_request = nil
			state.callback_world = world

			-- What the owner has linked to: let go of what was linked, and link what they say if it is something that can be
			if request then
				release_target(state)

				local unit = request.target_go_id > 0 and Managers.state.unit_storage:unit(request.target_go_id)

				if unit and Unit.alive(unit) and CONFIG.remote_link_kinds[request.kind] then
					link_target(state, owner_unit, unit, request.kind)

					state.target_go_id = request.target_go_id
				end
			end

			-- The link is over if what is linked is gone or too far: the owner is told
			if state.target and not is_link_valid(state, origin) then
				release_target(state)

				mod:network_send("ut_link_released", owner_peer_id, state.target_go_id)
			end

			run_link(state, owner_unit, origin, input.aim:unbox(), yanked, dt, t, physics_world)

			-- An ally that attacks makes the beam cost heat, which is the owner's
			if state.kind == "ally" and state.ally_attack_t ~= state.noticed_ally_attack_t and t >= (state.next_ally_notice_t or 0) then
				state.noticed_ally_attack_t = state.ally_attack_t
				state.next_ally_notice_t = t + CONFIG.beam_send_interval

				mod:network_send("ut_link_ally_attack", owner_peer_id)
			end
		end
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

	state.callback_world = world

	-- Yanking: pressing primary, once for every press (the button being held isn't one). Looked at every frame, linked
	-- or not, so that a press is only one that happens after the button was up.
	local yanked = yank_pressed(state, owner_unit)

	if yanked and state.target and not pose.locked_out() then
		Unit.animation_event(first_person_extension:get_first_person_unit(), CONFIG.yank_animation_event)
	end

	if Managers.player.is_server then
		select_target(state, owner_unit, origin, aim, t, physics_world)
		run_link(state, owner_unit, origin, aim, yanked, dt, t, physics_world)
	else
		select_target(state, owner_unit, origin, aim, t, physics_world, CONFIG.remote_link_kinds)

		-- The host is told what is linked when it changes, and where the eye is and where it is aimed (a yank at once, the rest
		-- every beam_send_interval)
		if state.target ~= state.sent_target then
			state.sent_target = state.target

			local target_go_id = state.target and Unit.alive(state.target) and Managers.state.unit_storage:go_id(state.target) or 0

			mod:network_send("ut_link_target", "others", Managers.state.unit_storage:go_id(owner_unit), target_go_id, state.kind or "")
		end

		state.yank_unsent = state.yank_unsent or yanked

		if state.yank_unsent or t >= (state.next_input_send or 0) then
			state.next_input_send = t + CONFIG.beam_send_interval
			state.input_sent = true

			mod:network_send("ut_link_input", "others", Managers.state.unit_storage:go_id(owner_unit), origin.x, origin.y, origin.z, aim.x, aim.y, aim.z, state.yank_unsent)

			state.yank_unsent = false
		end
	end

	-- the end of the beam: what it is linked to, or where it hits
	local end_position

	if not (state.target and Unit.alive(state.target)) then
		local range = CONFIG.beam_range
		local hit, hit_position = PhysicsWorld.immediate_raycast(physics_world, origin, aim, range, "closest", "collision_filter", "filter_player_ray_projectile_static_only")

		end_position = hit and hit_position or origin + aim * range
	end

	-- (drawn when the world has been updated, see draw_pending_beams: the target and the staff have moved by then, the
	-- beam drawn here would be a frame behind them. The table is kept, and filled in again.)
	local pending = state.pending_draw

	if not pending then
		pending = {}
		state.pending_draw = pending
	end

	pending.ready = true
	pending.end_position = end_position
	pending.lag = state.kind == "enemy" and state.lag and state.lag:unbox() or nil
	pending.origin = origin
	pending.owner_unit = owner_unit
	pending.rotation = rotation
	pending.weight = state.kind == "enemy" and state.weight or nil
	pending.world = world

	-- the others are told where it ends
	local send_position = end_position or state.target and Unit.alive(state.target) and target_position(state)

	if send_position and t >= (state.next_beam_send or 0) then
		state.next_beam_send = t + CONFIG.beam_send_interval
		state.beam_sent = true

		mod:network_send("ut_link_beam", "others", Managers.state.unit_storage:go_id(owner_unit), send_position.x, send_position.y, send_position.z)
	end
end

-- The beams of the other players: where each ends, as it was told, and what is drawn, which follows it
local remote_beams = {} -- { [the unit of the player] = { sprite_ids, world, end_position, shown, received, drawn_at } }
local remote_points = {}

local function remove_remote_beam(owner_unit)
	local beam = remote_beams[owner_unit]

	if beam then
		destroy_sprites(beam)

		remote_beams[owner_unit] = nil
	end
end

mod:network_register("ut_link_beam", function (_, owner_go_id, x, y, z)
	local owner_unit = Managers.state.unit_storage:unit(owner_go_id)

	if not owner_unit then
		return
	end

	local beam = remote_beams[owner_unit]

	if not beam then
		beam = {}
		remote_beams[owner_unit] = beam
	end

	beam.end_position = Vector3Box(Vector3(x, y, z))
	beam.received = Application.time_since_launch()
end)

mod:network_register("ut_link_beam_end", function (_, owner_go_id)
	local owner_unit = Managers.state.unit_storage:unit(owner_go_id)

	if owner_unit then
		remove_remote_beam(owner_unit)
	end
end)

-- The end of the staff of the player's character: the one of the two hands' units that has the node the beam starts at
local function remote_staff_end(owner_unit)
	local inventory_extension = ScriptUnit.has_extension(owner_unit, "inventory_system")
	local equipment = inventory_extension and inventory_extension:equipment()

	if not equipment then
		return nil
	end

	for _, staff_unit in ipairs({equipment.left_hand_wielded_unit_3p, equipment.right_hand_wielded_unit_3p}) do
		if Unit.alive(staff_unit) and Unit.has_node(staff_unit, CONFIG.staff_end_node) then
			return Unit.world_position(staff_unit, Unit.node(staff_unit, CONFIG.staff_end_node))
		end
	end
end

local function draw_remote_beams()
	local now = Application.time_since_launch()
	local world = Managers.world:world("level_world")

	for owner_unit, beam in pairs(remote_beams) do
		local start_position = remote_staff_end(owner_unit)

		if not start_position or now - beam.received > CONFIG.remote_beam_timeout or not effects.is_available(CONFIG.beam_effect) then
			remove_remote_beam(owner_unit)
		else
			local target = beam.end_position:unbox()
			local shown = beam.shown and beam.shown:unbox() or target
			local blend = 1 - math.exp(-CONFIG.remote_beam_smoothing * (now - (beam.drawn_at or now)))

			shown = shown + (target - shown) * blend
			beam.shown = Vector3Box(shown)
			beam.drawn_at = now

			-- (a straight line, a point about every remote_beam_segment_length of it)
			local segments = math.clamp(math.ceil(Vector3.length(shown - start_position) / CONFIG.remote_beam_segment_length), CONFIG.beam_min_segments, CONFIG.beam_max_segments)

			-- The effect is drawn with the field of view of the staff in the hands, not of the world: every point of the beam is
			-- moved toward the middle of the screen by the ratio of the two, so that it is seen where it is
			local camera_manager = Managers.state.camera
			local camera_position = camera_manager:camera_position("player_1")
			local camera_rotation = camera_manager:camera_rotation("player_1")
			local right = Quaternion.right(camera_rotation)
			local up = Quaternion.up(camera_rotation)
			local forward = Quaternion.forward(camera_rotation)
			local scale = math.tan(math.rad(CONFIG.remote_effect_fov) / 2) / math.tan(camera_manager:fov("player_1") / 2)

			for i = 0, segments do
				local offset = start_position + (shown - start_position) * (i / segments) - camera_position

				remote_points[i + 1] = camera_position + right * (Vector3.dot(offset, right) * scale) + up * (Vector3.dot(offset, up) * scale) + forward * Vector3.dot(offset, forward)
			end

			draw_sprites(beam, world, CONFIG.beam_effect, remote_points, segments + 1)
		end
	end
end

-- The beams are drawn after the units have been updated, from where the staff and what it is linked to are now
function mod.draw_pending_beams()
	draw_remote_beams()

	for _, state in pairs(states) do
		local pending = state.pending_draw

		if pending and pending.ready then
			pending.ready = false

			local end_position = pending.end_position

			if not end_position then
				end_position = state.target and Unit.alive(state.target) and target_position(state)
			end

			local start_position = Unit.alive(pending.owner_unit) and staff_end_position(pending.owner_unit)

			if end_position and start_position then
				draw_beam(state, pending.world, pending.origin, start_position, pending.rotation, end_position, pending.weight, pending.lag)
			end
		end
	end
end

-- The beam ends when the button is let go (or it is left for something else)
mod:hook_safe(ActionCharge, "finish", function (self)
	local action = self.current_action

	if action and action.ut_charge_callback == "link" then
		end_beam(self.owner_unit)
	end
end)

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

	if item_template.name ~= TEMPLATE_NAME or not utils.is_weapon_enabled("link_gun") or not has_staff then
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
	pose.owner_unit = self._unit
	pose.unit_1p = unit_1p
	pose.recovering = false

	pose.schedule(CONFIG.idle_pose_delay, is_valid, function ()
		pose.enter(unit_1p, pose.owner_unit)
	end)
end

-- The first person weapons are hidden for a while by the game's transitions (ladders, interactions that are seen from the
-- third person, ledges, being knocked down, vortexes, being launched) and shown again when they are over, and the staff
-- is back in the idle of the game, not in the stance: it is entered again a moment after they are shown.
if PlayerUnitFirstPerson then
	mod:hook_safe(PlayerUnitFirstPerson, "unhide_weapons", function (self)
		if hand.first_person_extension ~= self or not pose.is_valid or not pose.is_valid() or not table.is_empty(self.hide_weapon_reasons) then
			return
		end

		pose.entered = false

		pose.schedule(CONFIG.transition_pose_delay, pose.is_valid, function ()
			pose.enter(pose.unit_1p, pose.owner_unit)
		end)
	end)
end

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	-- (there is no game time outside of a level)
	local t = Managers.time:time("game")

	if t then
		update_remote_inputs(dt, t)
	end

	pose.update(dt)
	hand.update()

	if next(pending_rescues) then
		update_pending_rescues(Managers.time:time("game"))
	end

	update_bolts()
end

local function clear_beams()
	for owner_unit in pairs(states) do
		end_beam(owner_unit)
	end

	for owner_unit in pairs(remote_beams) do
		remove_remote_beam(owner_unit)
	end

	table.clear(remote_inputs)

	restore_corpse()
	pose.clear()
	pose.health_extension = nil
	pose.overcharge_extension = nil
	pose.is_valid = nil
	hand.show()
	table.clear(bolts)
end

-- Enabling and disabling (the weapon can be switched off in the settings: the staff is then the game's own again)
utils.register_weapon("link_gun", apply_link_gun, function ()
	clear_beams()
	restore_staff()
	packages.unload()
end)

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	clear_beams()
end
