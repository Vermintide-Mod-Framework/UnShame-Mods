local mod = get_mod("unreal_tournament")

-- Link Gun: a copy of the Thornsister's Deepwood Staff with fire modes of its own.
-- The numbers are from UT2004 (XWeapons/LinkFire, LinkAltFire, LinkProjectile and LinkBeamEffect).
--   LMB: fires the staff's burst of thorns, which stun as well as hurt.
--   RMB (held): fires the link beam. The beam links to what the aim is on, one thing at a time, and the link stays until the
--               beam is let go.
--               What gets linked, in order of preference: an ally first (a player, a bot, or less so a necromancer's pet), then an
--               enemy (a special before another elite before the rest), then a monster. If there is none of those, something that
--               is not alive is linked: a pickup, a door, a chest, a lever or another interaction of the game, something that can
--               be broken down, a ragdoll, or another object that is moved by physics. An open door is only linked when there is
--               nothing else.
--               What the link does:
--                 * An ally does more damage and gets their stamina back faster for as long as the link lasts. This is UT's link
--                   on a teammate.
--                 * An enemy is poisoned and held where the aim is. It follows the aim along the ground, staggered over and over.
--                   A heavy enemy follows more slowly, and the beam hangs more.
--                 * A monster is too big to be held. The link launches the owner to it.
--                 * Anything else is held in the air, or stays where it is.
--   Primary while linked (a yank):
--                 * An enemy is thrown, the way the game lets an enemy out of the Thornsister's vortex, to land in front of the
--                   owner. If the enemy is near, or the game does not put it in a vortex, it is pushed instead. An enemy that is in
--                   a vortex is let out of it.
--                 * An ally is freed from what holds them, got up, pulled up from a ledge, or launched to the owner. This costs
--                   heat, and for a player it costs the whole bar.
--                 * A critter (a rat) is killed, because it has no stagger and is not put in a vortex.
--                 * An object is pulled to the owner. Something that hangs and is held to something, such as a lantern, is hit,
--                   which brings it down.
--                 * A pickup is picked up, a door is opened or closed, a chest or a lever is used, and a barricade is broken in a
--                   few blows.
-- Who does what: the player who holds the beam picks what is linked, from what they see. Anything that depends on the player's
-- own machine is done by their own game: their pickups, doors, chests, interactions, the objects of the level, and the heat of
-- the staff. What happens to the enemies, the allies and the networked objects is done by the game that has them, which is the
-- host's. The host is told what is linked and where the player aims. The beam is drawn for the player who holds it, as a curve
-- from the staff in the hands. The player tells the others where it ends, and they draw it from the staff of the player's
-- character. They also hear a drone while something is linked, and a gust for every yank.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local effects = mod.effects
local with_valid_positions = utils.with_valid_positions
local register_damage_profile = utils.register_damage_profile

local stagger_types = require("scripts/utils/stagger_types")

mod.items.register("link_gun", {
	key = "ut_link_gun",
	template = "ut_link_gun_template",
	base_item = "we_life_staff",
	deus_copy = "deus_we_life_staff",
	name = "UT2004 Link Gun",
	type_name = "Link Gun",
	description = "Riordan Dynamic Weapon Systems combines the best of weapon design in the Advanced Plasma Rifle v23, commonly known as the Link Gun. Its secondary mode is a switchable energy matrix: on a teammate it becomes a harmless carrier stream that boosts the output of any targeted player also using the Link.",
	keywords = { "weapon_keyword_rapid_fire", "weapon_keyword_crowd_control", "weapon_keyword_damage_over_time", "weapon_keyword_overheat" },
	icon = "ut_link_gun_icon",
	icon_package = "resource_packages/unreal_tournament/icons",
	icon_materials = "ui/ut/link_gun_icon",
})

local TEMPLATE_NAME = mod.items.weapons.link_gun.template

local CONFIG = {
	-- The event that puts the staff in its stance. Inspecting and venting end with it.
	idle_pose_event = "attack_charge_fireball",
	-- Primary: one bolt at a time while the button is held. UT's LinkAltFire has FireRate 0.2. Its LinkProjectile starts at Speed
	-- 1000 uu/s and speeds up by 3000 uu/s every second to MaxSpeed 4000, where an uu is 0.02 m. The bolts are the staff's thorns.
	-- They start at the left hand's weapon node, which has the staff in it, and a bit ahead of it, and they blend into the aim from
	-- there. Their damage profile keeps the damage of the thorns. Their stagger is bolt_stagger_power, where the damage's share of
	-- the power distribution is 0.12 near and 0.1 far, so a stagger of this size is a heavy one.
	bolt_fire_interval = 0.25, -- seconds
	bolt_speed = 20, -- m/s
	bolt_acceleration = 60, -- m/s^2
	bolt_max_speed = 80, -- m/s
	bolt_overcharge = 1, -- the heat of a bolt, where the staff's burst of four was 4
	bolt_link_node = "j_leftweaponattach",
	bolt_forward_offset = 0.6, -- m ahead of the node
	bolt_stagger_power = 0.6,
	bolt_damage_scale = 1.6, -- how much more damage a bolt does than the staff's thorns did
	-- Beam. UT has TraceRange 1100 uu, and 1.5 times that while linked. Here the link holds until the beam is let go, or until the
	-- target is further away than that.
	beam_range = 22, -- m
	linked_range_scale = 1.5,
	aim_dot = 0.985, -- how close to the aim a target has to be to be linked to, where 1 is exactly on it
	beam_overcharge = 0.8, -- the heat added every beam_overcharge_interval seconds while the beam is held
	beam_overcharge_interval = 0.25,
	-- Ally: the damage it does is this much more while linked. The buff stays until ally_buff_linger seconds after the link ends.
	ally_damage_bonus = 0.5,
	ally_buff_max_stacks = 4, -- the buff stacks once for each Link Gun that has the ally linked, and the party has four
	ally_stamina_regen_bonus = 1, -- the stamina the ally gets back is this much more, and the delay before it starts is less
	ally_thp_multiplier = 2, -- the temporary health a linked ally gets from their attacks
	ally_buff_linger = 0.6, -- seconds
	ally_buff_icon = "kerillian_thornsister_avatar", -- the icon of the buff in the ally's buff bar
	bot_target_range = 80, -- m, how far from a linked bot the enemy it is made to attack can be
	bot_rescan_interval = 0.5, -- seconds between looks for an enemy for a linked bot that has none near
	openable_reach_margin = 10, -- m past the reach of the beam that a door or a chest can still be looked at, because they are big
	openable_box_scale = 0.7, -- the share of the size of the box of a door or a chest that the aim has to be on
	rescue_retry_interval = 0.5, -- seconds between the times a yank tries a rescue again, until it has taken
	rescue_max_tries = 4,
	beam_aim_curve_gain = 1.3, -- how much the aim bows the first half of the beam, on top of beam_aim_curve
	beam_hang_share = 0.7, -- how much of what hangs and lags a beam bends the first half by
	ally_effect = "fx/thornsister_buff", -- what is seen on a linked ally, played again every ally_effect_interval
	ally_effect_interval = 0.8, -- seconds
	ally_attack_grace = 0.5, -- seconds the beam still costs heat after the ally's attack
	-- Enemy: it is held by being staggered over and over, with stagger_duration for each stagger. Each new stagger is given when
	-- the one before is over, and at least restagger_interval later. The stagger moves the enemy over the ground towards the point
	-- the aim is on, at the distance it was linked at. The stagger's length is hold_stagger_per_meter of the distance to that
	-- point, at least hold_stagger_min and at most hold_stagger_max. It is less for a heavy enemy, by
	-- (mass / reference_mass) ^ weight_exponent. Enemies with a mass of more than max_mass cannot be held, and neither can the
	-- big monsters and bosses.
	hold_stagger_per_meter = 0.5,
	hold_stagger_min = 0.05,
	hold_stagger_max = 3,
	hold_min_distance = 2.5, -- m
	-- The primary while an enemy is held throws it to land in front of the player, throw_land_distance away, the way the game lets
	-- an enemy out of the Thornsister's vortex. The flight lasts as long as the distance takes at yank_speed, with the same weight
	-- rule as the hold, and at least throw_min_duration and at most throw_max_duration. The flight is a real one, with gravity and
	-- the walls. The enemy's behavior puts it on the navmesh where it lands, and an enemy that lands where there is no navmesh
	-- dies.
	yank_speed = 30, -- m/s
	yank_min_distance = 1.5, -- m
	-- How far in front of the player a thrown enemy is aimed to land. It goes on a little after it lands. Where there is no
	-- navmesh there, such as past a ledge, it lands on the ground that is found by looking down from throw_ground_lift above the
	-- player's feet, at most throw_ground_depth deep, and it dies there.
	throw_land_distance = 5.5, -- m
	throw_ground_lift = 1, -- m
	throw_ground_depth = 40, -- m
	throw_min_duration = 0.35,
	throw_max_duration = 1.2,
	-- The enemy takes up the vortex on its next turn. A throw that has not begun after throw_enter_timeout seconds is called off.
	-- A throw in the air that is not over throw_land_timeout seconds after it should be lets the enemy out of the vortex.
	throw_enter_timeout = 0.6,
	throw_land_timeout = 3,
	-- An enemy that is nearer than throw_min_distance to where it would land, or that the game does not put in a vortex (the leech
	-- and the sorcerers), is staggered towards there instead. The stagger's length is yank_stagger_per_meter of the distance, at
	-- most yank_stagger_max.
	throw_min_distance = 4, -- m
	yank_stagger_per_meter = 1,
	yank_stagger_max = 4,
	throw_lift = 0.4, -- m, the enemy is lifted this high before it is let out of the vortex, so it is not on the ground then
	yank_animation_event = "attack_charge_fireball", -- the alt fire's own animation, played again on every yank
	-- The sounds are events of the game's. Everyone hears them from the player who holds the beam. They are the wind of the Sister
	-- of the Thorn's vortex, which has a start and a stop. A drone plays while something is linked. Every yank plays a short gust
	-- of it for yank_sound_duration seconds, on a source of its own, because stopping a source ends everything that plays on it.
	link_sound_start = "weapon_life_staff_thorn_lift_wind_loop_start",
	link_sound_stop = "weapon_life_staff_thorn_lift_wind_loop_end",
	yank_sound_duration = 0.6,
	reference_mass = 1.5, -- a clan rat's mass
	weight_exponent = 0.5,
	max_mass = 30,
	stagger_duration = 1.5,
	disabler_stagger_duration = 2, -- seconds a disabler is staggered for when a yank frees a player from it
	restagger_interval = 0.25, -- the least seconds between two staggers of a held enemy, which are given when the one it has is over
	-- A linked enemy or monster is poisoned. This is the game's own poison of poisoned arrows, dot_template, at dot_power_level,
	-- which its damage scales with. It is applied again every dot_interval seconds, which keeps it up while the enemy is linked.
	dot_template = "arrow_poison_dot",
	dot_power_level = 500,
	dot_interval = 1,
	dot_overcharge = 1, -- the heat of every application of the poison, on top of the heat of the beam
	dot_damage_source = mod.items.weapons.link_gun.key,
	-- A monster is an enemy too big to be held, so it is linked but not held. Once it has moved monster_move_distance from where it
	-- was when it was linked, or the owner tries to yank it, the owner is launched towards it. This is the state of being launched
	-- by the game's monsters. The launch speed is monster_pull_per_meter of the monster's distance, between the min and the max
	-- speed, and the owner also gets monster_pull_up_speed upwards. The link is then over, and it cannot be made again for
	-- monster_link_cooldown seconds.
	monster_move_distance = 1, -- m
	monster_pull_per_meter = 1.5,
	monster_pull_min_speed = 10, -- m/s
	monster_pull_max_speed = 20, -- m/s
	monster_pull_up_speed = 5, -- m/s
	monster_link_cooldown = 2, -- seconds
	-- The link goes to the most important of the things the aim is on, in this order: living things (enemies, monsters, players
	-- and bots), then supplies and doors, then objects. Supplies and doors are small or thin, so the aim only has to be within
	-- supply_aim_dot of them. What is linked stays linked until the beam is let go.
	-- Supplies (pickups) that the owner can pick up stay where they are while they are linked. Yanking one picks it up, using the
	-- game's own interaction, and tries again after supply_retry seconds.
	supply_aim_dot = 0.98,
	supply_retry = 0.6, -- seconds
	-- Doors and chests: yanking a door opens it or closes it. The aim has to be on the door or the chest itself, and the beam ends
	-- in the middle of it. A door that is broken or a chest that is opened is not linked.
	-- The outline of a held enemy (alpha, red, green, blue)
	held_outline_color = {255, 60, 230, 190},
	-- Yanking costs heat on top of the heat of the beam. yank_free_overcharge is for freeing an enemy from a vortex or a player
	-- from a disabler or a vortex. yank_rescue_overcharge is for pulling a player up from a ledge or getting them up from being
	-- knocked down. yank_player_overcharge is for launching a player or a bot at the owner. yank_door_overcharge is for a door or
	-- a chest. A negative cost is a share of the whole bar, where -1 is all of it.
	yank_free_overcharge = 8,
	yank_rescue_overcharge = 10,
	yank_player_overcharge = -1,
	yank_bot_overcharge = 25, -- launching a bot, before bot_yank_cost_scale
	bot_yank_cost_scale = 0.1, -- yanking a bot costs this share of what the cost says, because the full cost is for griefing
	yank_door_overcharge = 2,
	-- A unit that is yanked out of a vortex cannot be pulled into one for this long.
	vortex_immunity = 3, -- seconds
	-- Objects: when nothing else is picked, a ragdoll or another object with a body that moves is held, and it takes no damage. It
	-- is held in the air where the aim is. The body that was linked gets object_pull per second of the way to there as speed, at
	-- most object_max_speed. An enemy that dies while it is held is held on as a corpse.
	object_collision_filter = "filter_explosion_overlap",
	-- A ragdoll or object that someone else holds, and that this machine cannot tell by its id, is found as the one nearest to where
	-- it lay for them when they linked it, within object_search_radius. It is looked for every object_search_interval seconds.
	object_search_radius = 6, -- m
	object_search_interval = 0.1,
	-- A networked object such as a barrel is moved by the host. On the other machines it is a copy that moves by itself, and the
	-- game corrects it only now and then. So while the object is held, and for barrel_settle_time seconds after, the host tells
	-- the others where it is every beam_send_interval, and they move their copy there.
	barrel_settle_time = 3, -- seconds
	-- A yank of an object that has no health is only a hit that brings it down, like a lantern, if it is held to something. That
	-- means it is further than anchored_distance from where it is pulled to, anchor_check_delay seconds after the yank.
	anchor_check_delay = 0.4, -- seconds
	anchored_distance = 1, -- m
	-- A yank of something to break down, such as a barricade, deals its health in break_hits blows, break_hit_interval seconds apart.
	break_hits = 4,
	break_hit_interval = 0.15, -- seconds
	object_holder_timeout = 0.3, -- seconds, a holder of a prop that has not been seen holding it for this long does not count
	object_pull = 20,
	object_max_speed = 35, -- m/s
	-- The beam is drawn as a curve (a cubic Bezier) from the staff to what it is on. A held enemy makes it hang by the enemy's
	-- weight, by sag_per_weight meters for each meter of beam and each unit of weight, at most sag_max. The beam also bends by how
	-- far the enemy is behind where it is being moved to (lag_bend).
	staff_end_node = "fx_muzzle", -- the node at the end of the staff unit, where the beam and the bolts start
	beam_aim_curve = 0.3, -- how far the beam bows towards the aim, as a share of its length at most, where 0 is a straight line
	beam_segment_length = 0.1, -- m, about how far apart the points of the beam are (the particles)
	beam_min_segments = 2,
	beam_max_segments = 220,
	sag_per_weight = 0.015,
	sag_max = 2.5, -- m
	lag_bend = 0.5,
	lag_bend_max = 1.5, -- m
	-- The other players are told where the end of the beam is this often, and what they draw follows it. The share of the way to
	-- the end that they cover in a second is 1 - e^-smoothing. A beam that they have not heard of for the timeout is over.
	beam_send_interval = 0.05, -- seconds
	remote_beam_smoothing = 20,
	remote_beam_timeout = 0.5, -- seconds
	-- The beams of players that are not the host: these are the kinds of things they can link to, because the host works out what
	-- it does from what they say. The timeout is how long the host goes on with a beam it has heard nothing of.
	remote_link_kinds = {ally = true, enemy = true, monster = true, object = true},
	-- A player that is not the host links to these kinds and does everything with them themselves, and the host has nothing to do
	-- with it. They depend on the player's own interactions and on the ragdolls and objects of their own game.
	local_link_kinds = {object = true, openable = true, supply = true},
	remote_input_timeout = 0.5, -- seconds
}

local overcharge_values = PlayerUnitStatusSettings.overcharge_values

overcharge_values.ut_link_beam = CONFIG.beam_overcharge
overcharge_values.ut_link_bolt = CONFIG.bolt_overcharge

-- The damage profile of the thorns is the game's own with more stagger. The stagger is what stuns. The staff and its profile
-- belong to the Winds of Magic DLC. Without that DLC there is nothing to change.
local has_staff = rawget(DamageProfileTemplates, "burst_thorn") ~= nil

if has_staff then
	register_damage_profile("ut_link_bolt", "burst_thorn", function (profile)
		local target = profile.default_target

		target.power_distribution_near.impact = CONFIG.bolt_stagger_power
		target.power_distribution_far.impact = CONFIG.bolt_stagger_power

		-- The bolts do more damage than the thorns did.
		target.power_distribution_near.attack = target.power_distribution_near.attack * CONFIG.bolt_damage_scale
		target.power_distribution_far.attack = target.power_distribution_far.attack * CONFIG.bolt_damage_scale

		-- The bolts poison, as the beam does.
		target.dot_template_name = CONFIG.dot_template
	end)
end

-- The buff an ally gets while linked is more damage and faster stamina. Buffs go over the network by name, so everyone in the game
-- needs the mod. There are two versions of the buff (see update_ally_buffs). One has no duration and is used while the link
-- lasts, so the buff bar shows its icon with no timer. The other has a duration and is used after the link ends, so it shows the
-- timer. They have the same name, which is how the buff bar tells buffs apart, so it shows one icon that gets its timer. The icon
-- is the Thornsister's own, like the icons of the buffs she gives.
local ALLY_BUFF = "ut_link_damage_boost"
local ALLY_BUFF_FADING = "ut_link_damage_boost_fading"

local function ally_buff_template(duration)
	return {
		buffs = {
			{
				duration = duration,
				icon = CONFIG.ally_buff_icon,
				-- There is one stack for every Link Gun that has the ally linked (see update_ally_buffs).
				max_stacks = CONFIG.ally_buff_max_stacks,
				multiplier = CONFIG.ally_damage_bonus,
				name = ALLY_BUFF,
				-- This changes the damage that is dealt, not the power level. The game scales a power level on a curve and caps it
				-- by difficulty, so more power level would be little more damage for a player.
				stat_buff = "damage_dealt",
			},
			{
				duration = duration,
				max_stacks = CONFIG.ally_buff_max_stacks,
				multiplier = CONFIG.ally_stamina_regen_bonus,
				-- This buff has a name of its own, because the stacks are counted by name. It has no icon, because the other buff
				-- shows one.
				name = ALLY_BUFF .. "_stamina",
				stat_buff = "fatigue_regen",
			},
		},
	}
end

BuffTemplates[ALLY_BUFF] = ally_buff_template(nil)
BuffTemplates[ALLY_BUFF_FADING] = ally_buff_template(CONFIG.ally_buff_linger)

utils.register_network_lookup("buff_templates", ALLY_BUFF)
utils.register_network_lookup("buff_templates", ALLY_BUFF_FADING)

-- Weapon template
-- The template is shared game state, so it is patched in place. What is changed is saved, and it is put back when the mod is
-- disabled or unloaded.
local saved = {}

-- The overcharge lockout has an animation that stays until the weapon has cooled down, even after a weapon swap. This is the
-- overcharge extension of the player who wields the staff.
local wielder_overcharge_extension

local function locked_out()
	return wielder_overcharge_extension ~= nil and wielder_overcharge_extension.lockout == true
end

mod:hook_safe(TransportationSystem, "world_updated", function (self, world)
	if mod.draw_pending_beams then
		mod.draw_pending_beams()
	end
end)

-- Returns where the beam starts: the muzzle of the model or the mesh, or else the end node of the staff.
local function staff_end_position(owner_unit)
	local position = mod.link_beam_callbacks.start_position(owner_unit)

	if position then
		return position
	end

	local inventory_extension = ScriptUnit.has_extension(owner_unit, "inventory_system")
	local equipment = inventory_extension and inventory_extension:equipment()
	local staff_unit = equipment and (equipment.left_hand_wielded_unit or equipment.right_hand_wielded_unit)

	if staff_unit and Unit.alive(staff_unit) and Unit.has_node(staff_unit, CONFIG.staff_end_node) then
		return Unit.world_position(staff_unit, Unit.node(staff_unit, CONFIG.staff_end_node))
	end
end

-- The bolt is the staff's thorn. It starts at the end of the staff and blends into its path from there. The game blends it from a
-- node of the first person unit, the left hand's, and that is where it starts if the staff has no end.
local function bolt_projectile_info()
	local projectile_info = table.clone(Projectiles.lifestaff_light)

	projectile_info.anim_blend_settings.link_node = CONFIG.bolt_link_node
	projectile_info.anim_blend_settings.forward_offset = CONFIG.bolt_forward_offset
	projectile_info.ut_staff_end = true

	return projectile_info
end

-- After the game has put a bolt where its blend says, the bolt is put on the same blend from the end of the staff.
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

-- The bolts speed up as they fly, like UT's LinkProjectile (Speed, Acceleration and MaxSpeed). The path of a projectile is its
-- starting point plus its direction times its speed times the time it has flown. So when the speed changes, the starting point
-- is changed together with it by the amount that keeps the bolt where it is. Every peer does this for the bolts it has.
local bolts = {}

mod.init_callbacks.link_bolt = function (extension)
	bolts[#bolts + 1] = extension._projectile_unit
end

-- Where each bolt was a frame ago, to tell the Bio Rifle's goop which way it went (bolts set off goop, as they do in UT).
local last_bolt_positions = setmetatable({}, {
	__mode = "k",
})

local function update_bolts()
	for i = #bolts, 1, -1 do
		local unit = bolts[i]
		local locomotion_extension = Unit.alive(unit) and ScriptUnit.has_extension(unit, "projectile_locomotion_system")

		if not locomotion_extension or locomotion_extension.stopped then
			table.remove(bolts, i)
		else
			local position = Unit.world_position(unit, 0)
			local last_position = last_bolt_positions[unit]

			if last_position and mod.bio_goop then
				mod.bio_goop.detonate_segment(last_position:unbox(), position)
			end

			last_bolt_positions[unit] = Vector3Box(position)

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

		-- What the mod added is taken away, and what it changed is put back.
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

	local inspect = actions.action_inspect.action_inspect_hold

	inspect.anim_end_event = original.inspect_anim_end_event

	actions.action_two.default = original.action_two_default

	saved.original = nil
end

-- The beam effect of the staff comes with packages that the game only loads for the player who plays the Thornsister. For the
-- other players it loads only the third person staff. So the mod holds a reference to the staff in the hands and to the
-- Thornsister's packages, so that the other players can draw the beam.
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

	-- The stat chart, from 0 to 7. The bolts are the light attack, and the beam is the heavy one.
	template.weapon_diagram = {
		light_attack = {
			[DamageTypes.ARMOR_PIERCING] = 2,
			[DamageTypes.CLEAVE] = 3,
			[DamageTypes.SPEED] = 6,
			[DamageTypes.STAGGER] = 5,
			[DamageTypes.DAMAGE] = 3,
		},
		heavy_attack = {
			[DamageTypes.ARMOR_PIERCING] = 1,
			[DamageTypes.CLEAVE] = 2,
			[DamageTypes.SPEED] = 3,
			[DamageTypes.STAGGER] = 4,
			[DamageTypes.DAMAGE] = 4,
		},
	}

	local actions = template.actions
	local reload = actions.weapon_reload.default
	local original = {
		action_two_default = actions.action_two.default,
		primary_actions = {},
		reload_anim_end_event = reload.anim_end_event,
	}

	-- The whole action is saved, so its fields can be put back as they were.
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

	-- The thorns are one stunning bolt at a time that speeds up, fired again and again while the button is held. The shot has no
	-- animation of its own. The staff stays in its stance, and the hand does not cast.
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

		-- The chains to the other actions are open from the start, because an action has only the one bolt.
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
		-- The effect of the shot is played at the hand that holds the staff. The game has it at the right hand.
		action.on_shoot_particle_fx = saved.on_shoot_particle_fx and {
			effect = saved.on_shoot_particle_fx.effect,
			node_name = CONFIG.bolt_link_node,
		} or nil
		action.projectile_info = bolt_projectile_info()
		action.speed = CONFIG.bolt_speed * 100
		action.total_time = CONFIG.bolt_fire_interval
		action.ut_init_callback = "link_bolt"
		action.ut_init_flow_event_filter = "link"
		action.ut_skin_init_callback = "link_bolt"
	end

	-- Inspecting ends in the stance.
	local inspect = actions.action_inspect.action_inspect_hold

	original.inspect_anim_end_event = inspect.anim_end_event
	inspect.anim_end_event = CONFIG.idle_pose_event

	-- Venting ends in the stance too.
	reload.anim_end_event = CONFIG.idle_pose_event

	-- The beam is a charge that is held, and it adds the heat of the beam while it is held. The rest is in the callback below.
	local beam = table.clone(original.action_two_default)

	-- The beam has no animation of its own, like the bolts, so the stance stays.
	beam.anim_end_event = nil
	beam.anim_end_event_condition_func = nil
	beam.anim_event = nil
	beam.charge_time = 1000 -- the charge is never "full"
	beam.enter_function = function (attacker_unit, input_extension)
		input_extension:reset_release_input()
		input_extension:clear_input_buffer()
	end
	beam.finish_function = nil
	beam.kind = "charge"
	beam.overcharge_interval = CONFIG.beam_overcharge_interval
	beam.overcharge_type = "ut_link_beam"
	beam.ut_charge_callback = "link"
	utils.set_lookup_data(beam, TEMPLATE_NAME, "action_two", "default")

	-- The primary does not start an action while the beam is held. It yanks what is linked, in the callback below.
	local chains = {}

	for _, chain in ipairs(beam.allowed_chain_actions) do
		if chain.action ~= "action_one" then
			chains[#chains + 1] = chain
		end
	end

	beam.allowed_chain_actions = chains

	actions.action_two.default = beam
end


-- The sounds. The drone of a link is started when something is linked and stopped when nothing is. It is played by the unit of
-- the player who holds the beam, on every machine. The whoosh of a yank is played once.
local drones = {} -- { [the unit of the player] = { wwise_world, source } }

local function stop_drone(owner_unit)
	local drone = drones[owner_unit]

	if drone then
		drones[owner_unit] = nil

		WwiseWorld.trigger_event(drone.wwise_world, CONFIG.link_sound_stop, drone.source)
	end
end

local function set_drone(owner_unit, linked)
	if not linked then
		stop_drone(owner_unit)
	elseif not drones[owner_unit] then
		local wwise_world = Managers.world:wwise_world(Managers.world:world("level_world"))
		local source = WwiseWorld.make_auto_source(wwise_world, owner_unit)

		WwiseWorld.trigger_event(wwise_world, CONFIG.link_sound_start, source)

		drones[owner_unit] = {source = source, wwise_world = wwise_world}
	end
end

local yank_sounds = {} -- the gusts that are playing: { wwise_world, source, stop_at }

local function play_yank_sound(owner_unit)
	local _, source, wwise_world = WwiseUtils.trigger_position_event(Managers.world:world("level_world"), CONFIG.link_sound_start, Unit.world_position(owner_unit, 0))

	yank_sounds[#yank_sounds + 1] = {
		source = source,
		stop_at = Application.time_since_launch() + CONFIG.yank_sound_duration,
		wwise_world = wwise_world,
	}
end

mod:network_register("ut_link_yank", function (_, owner_go_id)
	local owner_unit = Managers.state.unit_storage:unit(owner_go_id)

	if owner_unit then
		play_yank_sound(owner_unit)
	end
end)

-- A player who is gone takes their sound with them, and a gust is stopped when its time is up.
mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	for owner_unit in pairs(drones) do
		if not Unit.alive(owner_unit) then
			drones[owner_unit] = nil
		end
	end

	local now = Application.time_since_launch()

	for i = #yank_sounds, 1, -1 do
		local gust = yank_sounds[i]

		if now >= gust.stop_at then
			WwiseWorld.trigger_event(gust.wwise_world, CONFIG.link_sound_stop, gust.source)
			table.remove(yank_sounds, i)
		end
	end
end

-- The beam
local ai_units = {}
local states = {} -- for each unit that holds the beam: what it is linked to, and its line object
local bot_targets = {} -- for each bot that is linked: the enemy it is made to attack
local bot_scan_after = {} -- for each bot that had no enemy near: when to look again

-- The middle of a character is its spine. Failing that it is the nearest the model has to one, because the target dummies have
-- none under the name the others use. Failing that it is the middle of the character's box. The first node of a unit is where
-- it is placed, which is not on the model of everything.
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

-- Returns whether the unit is alive. The target dummies have a health of their own that is not in HEALTH_ALIVE, so it is asked
-- for as well.
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

-- Returns whether the unit is a player or bot who is dead and waiting for someone to set them free.
local function is_awaiting_rescue(unit)
	local status_extension = Unit.alive(unit) and ScriptUnit.has_extension(unit, "status_system")

	return status_extension ~= nil and status_extension ~= false and status_extension:is_ready_for_assisted_respawn() == true
end

-- Returns the weight of the enemy, where 1 is the lightest, or nil if the enemy cannot be held.
local function enemy_weight(unit)
	local breed = is_alive(unit) and AiUtils.unit_breed(unit)

	-- A boss is not held, whether it can be staggered or not. The lords can be staggered, but they are held no more than the
	-- monsters are.
	if not breed or breed.is_player or breed.boss or breed.boss_staggers then
		return nil
	end

	local mass = breed_mass(breed)

	if mass > CONFIG.max_mass then
		return nil
	end

	return math.max(mass / CONFIG.reference_mass, 1) ^ CONFIG.weight_exponent
end

-- Returns whether the unit is a monster. A monster is a living enemy that is too big to be held, such as the bosses and the big
-- ones, and it pulls the owner to it.
local function is_monster(unit)
	local breed = is_alive(unit) and AiUtils.unit_breed(unit)

	return breed ~= nil and breed ~= false and not breed.is_player and breed.race ~= "dummy" and enemy_weight(unit) == nil
end

-- Returns whether the target is seen. It is seen if nothing is in the way until within the tolerance of it. For a big thing like
-- a chest, whose middle is inside it, the tolerance is how far its surface is from there.
local function has_line_of_sight(physics_world, origin, target_position, tolerance)
	local offset = target_position - origin
	local distance = Vector3.length(offset)

	if distance < 0.1 then
		return true
	end

	local hit, _, hit_distance = PhysicsWorld.immediate_raycast(physics_world, origin, offset * (1 / distance), distance, "closest", "collision_filter", "filter_ai_line_of_sight_check")

	return not hit or hit_distance > distance - (tolerance or 0.5)
end

-- Returns whether the unit is a supply, which is a pickup that is picked up and not moved about. A pickup that has a health of its
-- own is a barrel.
local function is_supply(unit)
	return ScriptUnit.has_extension(unit, "pickup_system") ~= nil and ScriptUnit.has_extension(unit, "health_system") == nil
end

-- Returns whether the unit is an object, which is a ragdoll, a barrel, or anything that is not a character that is alive. The
-- target dummies are characters, so they are linked as enemies and not moved about as objects.
local function is_object(unit)
	local breed = AiUtils.unit_breed(unit)

	if breed and (breed.is_player or breed.race == "dummy" or is_alive(unit)) then
		return false
	end

	-- Supplies and doors are linked as what they are: they are picked up and opened, and not moved about. A barrel is a pickup
	-- with a health of its own, and it is moved about.
	if is_supply(unit) or ScriptUnit.has_extension(unit, "door_system") then
		return false
	end

	return true
end

-- Every machine has the units that die, and they are the same units. But each machine simulates a ragdoll by itself, so the
-- ragdolls do not lie in the same place. A corpse can be identified by the id of the game object its unit had when it was alive.
-- That id is kept when the unit is put among the corpses, because the game takes the id away after that. A held ragdoll or
-- object is described to the other players by this id.
local corpse_ids = setmetatable({}, {__mode = "k"}) -- { [the unit] = the id }
local corpse_units = {} -- { [the id] = the unit }

mod:hook_safe(UnitSpawner, "push_unit_to_death_watch_list", function (self, unit)
	local go_id = Managers.state.unit_storage:go_id(unit)

	if go_id then
		corpse_ids[unit] = go_id
		corpse_units[go_id] = unit
	end
end)

-- Returns the id of a ragdoll or an object that is held. The id of a corpse is the one kept above. The id of a networked unit,
-- such as a barrel, is its game object id. The id of something placed in the level, such as a prop, is its number in the level,
-- which is the same on every machine, made negative as -1 minus the number. An id of 0 means none, and the object is then looked
-- for by where it lay.
local function object_id_of(unit)
	local id = corpse_ids[unit] or Managers.state.unit_storage:go_id(unit)

	if id then
		return id
	end

	local ok, level_index = pcall(Level.unit_index, LevelHelper:current_level(Managers.world:world("level_world")), unit)

	return ok and level_index and -1 - level_index or 0
end

-- Returns whether the unit is an object that is a networked unit, such as a barrel. Its position is the host's. The host holds it
-- according to what the holder says, and everybody sees it move as they see any networked unit move. A ragdoll and a prop of the
-- level are each machine's own, so each machine holds them itself (see update_object_mirrors).
local function is_networked_object(unit)
	return Managers.state.unit_storage:go_id(unit) ~= nil and AiUtils.unit_breed(unit) == nil
end

local function object_unit_of(object_id)
	if object_id < 0 then
		return Level.unit_by_index(LevelHelper:current_level(Managers.world:world("level_world")), -1 - object_id)
	elseif object_id == 0 then
		return nil
	end

	local unit = corpse_units[object_id]

	if unit and Unit.alive(unit) then
		return unit
	end

	return Managers.state.unit_storage:unit(object_id)
end

-- The corpse that is held, or was held last, must not be removed. The game removes the oldest of the corpses in its death watch
-- list when there are too many. So the held corpse is taken out of that list, and it is put back as the newest when another
-- corpse is held or the mod is cleared.
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

	-- This takes the unit out of the list the same way the game does when it deletes a unit.
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

-- Returns where a mesh of a door or a chest is, which is the middle of its box, and how big it is. A door does not move when it
-- opens, because the game turns its collision on and off. So the result is the same wherever and whenever it is looked at.
local function mesh_center(mesh)
	local ok, pose, half_extents = pcall(Mesh.box, mesh)

	if not ok or not pose then
		return nil
	end

	return Matrix4x4.translation(pose), math.max(half_extents.x, half_extents.y, half_extents.z)
end

-- Returns the boxes of a door or a chest that the aim can be on. One is the box of its biggest mesh, which is the door itself and
-- not the frame or the hinges. For a chest, the box of the unit is another. Each box has the mesh it belongs to, if it belongs to
-- one, and the beam ends in the middle of that mesh.
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

-- Returns how far along the aim it hits a box, or nil if it does not. The box is given as a pose and half sizes. The box is what
-- is seen, not a ball around its middle.
-- This function does one axis of the box. It narrows near and far to where the ray is inside the slab of this half size, and
-- returns nil if the ray is never inside it.
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

-- Interactions of the game that are done to people, not to things in the level. They are not linked, because they are the game's
-- own interactions between players.
local PEOPLE_INTERACTIONS = {
	assisted_respawn = true,
	give_item = true,
	heal = true,
	player_generic = true,
	pull_up = true,
	release_from_hook = true,
	revive = true,
}

-- Returns whether the unit is a door. A door is opened by the door system's own interacted_with and is not broken, whatever
-- health it has. A unit of the door system that players cannot interact with is not a door. An example is a barricade that the
-- enemies break down, which has a health and the door's extension but no interaction.
local function is_door(unit)
	local door_extension = ScriptUnit.has_extension(unit, "door_system")

	return door_extension ~= nil and door_extension.interacted_with ~= nil and ScriptUnit.has_extension(unit, "interactable_system") ~= nil
end

-- Returns whether the unit is a lever, a button, a chest, or anything else the game lets a player interact with. Pickups are
-- supplies and doors are doors, so they do not count.
local function is_interactable(unit, owner_unit)
	local interactable_extension = ScriptUnit.has_extension(unit, "interactable_system")

	-- The type the game goes by is the extension's. The unit's data is only what the type started as.
	local interaction_type = interactable_extension and interactable_extension:interaction_type()

	-- A unit with nothing to see is only a place where the game has the interaction. A character that is talked to has one next to
	-- them. It is not linked, because there is nothing to look at.
	if Unit.num_meshes(unit) == 0 then
		return false
	end

	if not interaction_type or PEOPLE_INTERACTIONS[interaction_type] or not InteractionDefinitions[interaction_type] or Unit.get_data(unit, "interaction_data", "used") or is_door(unit) then
		return false
	end

	if not interactable_extension:is_enabled() then
		return false
	end

	-- This is what the game does to offer an interaction. The owner has to be able to do it now, or the game says why they cannot,
	-- and it shows that reason.
	local interactor_extension = ScriptUnit.has_extension(owner_unit, "interactor_system")

	if not interactor_extension then
		return false
	end

	local can_interact, fail_reason = interactor_extension:can_interact(unit, interaction_type)

	return can_interact or fail_reason ~= nil
end

-- Returns whether the unit is a thing in the level that is broken down by hitting it, such as a barricade, a window or a crate.
-- It is a unit placed in the level that has a health and is not a character, a door, or anything that is interacted with. Doors
-- are opened and not broken, whatever health they have. The game must also let players hurt it with this kind of attack.
local function is_breakable(unit)
	local health_extension = ScriptUnit.has_extension(unit, "health_system")

	if not health_extension or not health_extension:is_alive() or not Managers.state.network:level_object_id(unit) then
		return false
	end

	if is_door(unit) or ScriptUnit.has_extension(unit, "interactable_system") or AiUtils.unit_breed(unit) then
		return false
	end

	-- A barricade of the door system says it takes no ranged damage, which means a shot. The enemies and a melee hit break it, and
	-- a yank is dealt like a melee hit.
	local is_barricade = ScriptUnit.has_extension(unit, "door_system") ~= nil

	return not Unit.get_data(unit, "no_damage_from_players") and not Unit.get_data(unit, "filter_damage_source") and (is_barricade or Unit.get_data(unit, "allow_ranged_damage") ~= false)
end

-- Returns whether the game would offer the interaction with a unit to someone looking along the aim. The game checks this with a
-- ray that uses the filter of the interactions and hits an actor of the unit, which is the actor the unit names, if it names one.
-- An interaction that is disabled in the level, such as a keep character that stands at another place, has no actor to hit and is
-- not offered by the game, but it is still an enabled interactable.
local function interaction_is_offered(physics_world, origin, aim, unit, range)
	local hits = PhysicsWorld.immediate_raycast(physics_world, origin, aim, range, "all", "collision_filter", "filter_ray_interaction")
	local interact_actor = Unit.get_data(unit, "interaction_data", "interact_actor")

	for i = 1, hits and #hits or 0 do
		local actor = hits[i][4]

		if actor and Actor.unit(actor) == unit and (not interact_actor or Unit.actor(unit, interact_actor) == actor) then
			return true
		end
	end

	return false
end

-- These three tables are scratch tables. They are cleared and filled again every time find_target looks, and nothing is remembered
-- between looks. So what the game says now is what is used, and a door that someone else opens is open for the next look.
local openables = {} -- the doors, chests, levers and things to break that are near enough: the unit, and whether the aim looks at its box too
local open_doors = {} -- the doors of them that the game says are open
local interactables = {} -- the ones of them that are interactions of the game. Only the ones the game would offer are linked.

-- Returns the first ragdoll or other object with a body that moves that the aim is on, as its unit, its body and how far away it
-- is. A wall in the way ends the search.
local function find_object(owner_unit, physics_world, origin, aim)
	local range = CONFIG.beam_range

	PhysicsWorld.prepare_actors_for_raycast(physics_world, origin, aim, 0.01, 0.5, range * range)

	local hits = PhysicsWorld.immediate_raycast(physics_world, origin, aim, range, "all", "collision_filter", CONFIG.object_collision_filter)

	for i = 1, hits and #hits or 0 do
		local hit = hits[i]
		local actor = hit[4]
		local unit = actor and Actor.unit(actor)

		if unit and unit ~= owner_unit then
			if not Actor.is_static(actor) and is_object(unit) then
				return unit, actor, hit[2]
			elseif Actor.is_static(actor) then
				-- A wall in the way ends the search, and characters are skipped.
				break
			end
		end
	end
end

-- Returns the unit of the ragdoll or object nearest to a place, within a radius. This is for the machine of another player when
-- it has no copy that it can tell by the id of what is held there.
local function find_object_near(physics_world, position, radius)
	local actors, num_actors = PhysicsWorld.immediate_overlap(physics_world, "shape", "sphere", "position", position, "size", radius, "types", "both", "collision_filter", CONFIG.object_collision_filter)
	local nearest_unit
	local nearest_distance

	for i = 1, num_actors or 0 do
		local actor = actors[i]
		local unit = actor and Actor.unit(actor)

		if unit and not Actor.is_static(actor) and is_object(unit) then
			local distance = Vector3.distance(Actor.position(actor), position)

			if not nearest_distance or distance < nearest_distance then
				nearest_unit = unit
				nearest_distance = distance
			end
		end
	end

	return nearest_unit
end

-- Finds what the aim is on. It prefers an ally if there is one. Otherwise it prefers an enemy that can be held: a special before
-- another elite before the rest, and of the same kind the one that is closest to the aim. Failing those, it takes an object with
-- a body that moves, such as a ragdoll. Returns the unit and what it is, and for an object also its body and how far away it is.
local function find_target(owner_unit, physics_world, origin, aim)
	local side = Managers.state.side.side_by_unit[owner_unit]
	local range = CONFIG.beam_range
	local best_unit, best_kind, best_actor
	local best_dot, best_tier
	local aim_dot_limit = CONFIG.aim_dot -- how near the aim a unit has to be. A smaller unit is looked at with less.
	local best_ally_unit
	local best_ally_dot = CONFIG.aim_dot

	-- This ranks the enemies when more than one is on the aim. The specials come first, then the other elites, which are worth
	-- more than the rest because they are heavier, then the rest: the common enemies, the monsters and the necromancer's
	-- skeletons. Among enemies of the same rank, the one closest to the aim wins.
	local function tier_of(unit, kind)
		local breed = kind == "enemy" and AiUtils.unit_breed(unit)

		if breed and breed.special then
			return 1
		elseif breed and breed.elite then
			return 2
		end

		return 3
	end

	-- An unprioritized ally is looked at together with the enemies. The necromancer's skeletons are not placed before the enemies.
	local function consider(unit, kind, unprioritized)
		local offset = chest_position(unit) - origin
		local distance = Vector3.length(offset)

		if distance <= 0.1 or distance > range then
			return
		end

		local dot = Vector3.dot(aim, offset * (1 / distance))

		-- The allies are looked at apart, and they come before everything else.
		if kind == "ally" and not unprioritized then
			if dot > best_ally_dot and has_line_of_sight(physics_world, origin, chest_position(unit)) then
				best_ally_unit = unit
				best_ally_dot = dot
			end
		else
			local tier = tier_of(unit, kind)

			if dot > aim_dot_limit and (not best_unit or tier < best_tier or tier == best_tier and dot > best_dot) and has_line_of_sight(physics_world, origin, chest_position(unit)) then
				best_unit = unit
				best_kind = kind
				best_dot = dot
				best_tier = tier
			end
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

	-- The target dummies are on the neutral side.
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

	-- A player waiting to be set free is not alive yet, so the game leaves them out of the lists of the side.
	for _, player in pairs(Managers.player:human_and_bot_players()) do
		local unit = player.player_unit

		if unit and unit ~= owner_unit and is_awaiting_rescue(unit) then
			consider(unit, "ally")
		end
	end

	-- The necromancer's skeletons are friendlies too. They are units of the heroes' side that the AI looks after.
	if heroes then
		count = AiUtils.broadphase_query(origin + aim * (range / 2), range / 2 + 2, ai_units, heroes.broadphase_category)

		for i = 1, count do
			local unit = ai_units[i]
			local breed = HEALTH_ALIVE[unit] and AiUtils.unit_breed(unit)

			if breed and not breed.is_player and string.find(breed.name or "", "^pet_") then
				consider(unit, "ally", true)
			end
		end
	end

	-- An ally that is on the aim is linked before an enemy or anything else, whatever is closer to the aim.
	if best_ally_unit then
		return best_ally_unit, "ally"
	end

	-- This is how far along the aim the door or chest is, used below.
	local best_distance

	-- An open door is linked when there is nothing else the aim is on, such as an object, a chest or a lever. The nearest open door
	-- is the one that is linked. Whether a door is open is asked of the game, with door_extension:is_open(), on every look.
	-- Yanking an open door closes it, which is seldom what is wanted when it is in the way of something else.
	local open_door_unit, open_door_distance, open_door_actor

	-- With nothing living on the aim, supplies (what can be picked up) and doors are looked at. They are small or thin, so the aim
	-- is a little more forgiving.
	if not best_unit then
		aim_dot_limit = math.min(aim_dot_limit, CONFIG.supply_aim_dot)

		-- What is further than the beam reaches, with room for how big a door is, is not looked at. This runs every frame that
		-- nothing is linked, and the boxes of a door are worked out from its meshes.
		local reach_squared = (range + CONFIG.openable_reach_margin) * (range + CONFIG.openable_reach_margin)

		table.clear(openables)
		table.clear(interactables)
		table.clear(open_doors)

		-- One pass over the interactables considers the supplies and keeps the chests for below.
		for unit in pairs(Managers.state.entity:get_entities("GenericUnitInteractableExtension")) do
			local position = POSITION_LOOKUP[unit] or Unit.world_position(unit, 0)

			if position and Vector3.distance_squared(position, origin) <= reach_squared and Unit.alive(unit) then
				if is_supply(unit) then
					consider(unit, "supply")
				elseif is_interactable(unit, owner_unit) then
					-- A chest that has been opened is done with. The game marks it used and takes the interaction away.
					openables[unit] = true
					interactables[unit] = true
				end
			end
		end

		-- These are the things that are broken down: the units with a health that are not characters. The characters have a
		-- blackboard, which is checked first because there are many of them. Every kind of health extension is looked at, because
		-- the things that are shot at in the level, such as a lantern that hangs, have kinds of their own.
		for unit in pairs(Managers.state.entity:system("health_system").unit_extensions) do
			if not BLACKBOARDS[unit] and Unit.alive(unit) then
				local position = POSITION_LOOKUP[unit] or Unit.world_position(unit, 0)

				if Vector3.distance_squared(position, origin) <= reach_squared and is_breakable(unit) then
					openables[unit] = true
				end
			end
		end

		-- Doors and chests: the aim has to be on the box of what is seen. The nearest box that the aim hits is the one that counts.
		if not best_unit then
			for unit in pairs(Managers.state.entity:get_entities("DoorExtension")) do
				local position = POSITION_LOOKUP[unit] or Unit.world_position(unit, 0)
				local door_extension = position and Vector3.distance_squared(position, origin) <= reach_squared and ScriptUnit.has_extension(unit, "door_system")

				-- A door that is broken is done with.
				if door_extension and not door_extension.dead then
					openables[unit] = false
					open_doors[unit] = door_extension:is_open() or nil
				end
			end

			for unit, is_chest in pairs(openables) do
				if Unit.alive(unit) then
					local boxes = openable_boxes(unit, is_chest)

					for i = 1, #boxes do
						local distance = ray_hits_box(origin, aim, boxes[i].pose, boxes[i].half * CONFIG.openable_box_scale)

						if open_doors[unit] then
							if distance and distance <= range and (not open_door_distance or distance < open_door_distance) and has_line_of_sight(physics_world, origin, origin + aim * distance) then
								open_door_unit = unit
								open_door_distance = distance
								open_door_actor = boxes[i].mesh
							end
						elseif distance and distance <= range and (not best_distance or distance < best_distance) and has_line_of_sight(physics_world, origin, origin + aim * distance) and (not interactables[unit] or interaction_is_offered(physics_world, origin, aim, unit, range)) then
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

	-- This looks for a ragdoll or another object with a body that moves, the first one the aim is on. A door or a chest is not
	-- chosen over an object that is nearer along the aim, because their boxes are big.
	local unit, actor, distance = find_object(owner_unit, physics_world, origin, aim)

	if best_unit and not (best_kind == "openable" and unit and distance < best_distance) then
		return best_unit, best_kind, best_actor
	end

	if unit then
		return unit, "object", actor, distance
	end

	if open_door_unit then
		return open_door_unit, "openable", open_door_actor
	end
end

-- Launches the owner towards the monster, the way the game's monsters catapult a player. The link is then over, and the owner
-- cannot link again for monster_link_cooldown seconds.
local function launch_towards_monster(state, owner_unit, monster, t)
	local flat = Vector3.flat(Unit.world_position(monster, 0) - Unit.world_position(owner_unit, 0))
	local distance = Vector3.length(flat)
	local direction = distance > 0.1 and flat * (1 / distance) or Vector3.forward()
	local velocity = direction * math.clamp(distance * CONFIG.monster_pull_per_meter, CONFIG.monster_pull_min_speed, CONFIG.monster_pull_max_speed)

	Vector3.set_z(velocity, CONFIG.monster_pull_up_speed)
	StatusUtils.set_catapulted_network(owner_unit, true, velocity)

	state.link_block_until = t + CONFIG.monster_link_cooldown
end

-- Returns the owner's interactor and the type of interaction for a supply, if the owner can pick it up at all. They cannot, for
-- example, with a full slot.
local function supply_interaction(owner_unit, pickup)
	local interactor_extension = ScriptUnit.has_extension(owner_unit, "interactor_system")
	local interaction_type = Unit.get_data(pickup, "interaction_data", "interaction_type")

	if interactor_extension and interaction_type and interactor_extension:can_interact(pickup, interaction_type) then
		return interactor_extension, interaction_type
	end
end

-- Puts a body somewhere. This is used for the objects that physics does not drive, which are moved by the script.
local function place_body(pickup, body, position, rotation)
	-- A body that cannot be teleported is moved by moving its unit.
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

-- A supply that is linked stays where it is and is picked up when it is yanked. The pickup is the game's own interaction, which
-- the owner starts, and the game does all of it: the checks, the inventory, the sounds and the removal of the pickup. The
-- interaction is held by the button of the beam, which is down.
local function pick_up_supply(state, owner_unit, t)
	local pickup = state.target
	local interactor_extension, interaction_type = supply_interaction(owner_unit, pickup)

	if interactor_extension then
		interactor_extension:start_interaction("action_two_hold", pickup, interaction_type)
	end

	-- The link is over, and it does not come back to the same pickup while it is being picked up.
	state.picked_up = true
	state.link_block_until = t + CONFIG.supply_retry
end

-- The throw of a held enemy (the primary). The enemy is put in the state the game puts an enemy in when it is let out of the
-- Thornsister's vortex. That is the behavior tree's own action for being in a vortex, which moves the unit by script with no
-- navigation. The enemy is also given the velocity that takes it to where it lands. Its own behavior flies it with the game's
-- gravity and the walls, puts it on the navmesh when it is down, and plays its landing, as it does for any enemy that is let out
-- of a vortex. The game moves it as it moves any enemy, so the other machines see it fly without the mod telling them. A unit
-- that is not an AI unit, such as a target dummy, is not thrown, and it is not moved when it is held either.
local THROW_GRAVITY = 9.82 -- the game's own gravity, used in the action of the vortex

local function finish_throw(state)
	local thrown = state.throw

	state.throw = nil

	local unit = state.target

	if not thrown or not unit or not Unit.alive(unit) then
		return
	end

	-- A throw that has not begun is called off, and the unit is let out of the action it was put in. A throw that is in the air
	-- goes on and lands by itself.
	if thrown.phase == "entering" then
		local blackboard = BLACKBOARDS[unit]

		if blackboard then
			blackboard.in_vortex = false
		end
	end
end

-- Returns where a unit that is thrown lands. It lands in front of the owner, on the navmesh where there is one near. Failing
-- that it lands on the owner, and failing that where the owner last stood on the navmesh. If there is none, it returns nothing.
-- For the beam of a player who is not the host, the owner's game works this out from where they are and where they aim, because
-- what the host sees of them is a little behind.
local function throw_landing(owner_unit, aim_flat)
	local nav_world = Managers.state.entity:system("ai_system"):nav_world()
	local owner_position = Unit.world_position(owner_unit, 0)
	local owner_locomotion_extension = ScriptUnit.has_extension(owner_unit, "locomotion_system")
	local in_front = owner_position + aim_flat * CONFIG.throw_land_distance
	local candidates = {
		in_front,
		owner_position,
		-- The game only keeps this on the host.
		Managers.player.is_server and owner_locomotion_extension and owner_locomotion_extension.last_position_on_navmesh and owner_locomotion_extension:last_position_on_navmesh() or nil,
	}

	for i = 1, 3 do
		local candidate = candidates[i]

		if candidate then
			local on_navmesh, altitude = GwNavQueries.triangle_from_position(nav_world, candidate, 4, 4)

			if on_navmesh then
				return Vector3(candidate.x, candidate.y, altitude)
			end
		end

		-- Where there is no navmesh in front, such as past a ledge, the enemy lands on the ground wherever that is. An enemy
		-- that lands where there is no navmesh dies, so it is thrown off the ledge.
		if i == 1 then
			local physics_world = World.get_data(Managers.world:world("level_world"), "physics_world")
			local from = Vector3(in_front.x, in_front.y, owner_position.z + CONFIG.throw_ground_lift)
			local hit, ground = PhysicsWorld.immediate_raycast(physics_world, from, Vector3.down(), CONFIG.throw_ground_depth, "closest", "collision_filter", "filter_player_ray_projectile_static_only")

			if hit then
				return ground
			end
		end
	end
end

-- The shield warrior (the bulwark) takes a stagger in its own way. The value of a stagger is added to a count that it keeps,
-- which runs down with time. The stagger only plays when the value reaches the least that its shield blocks, and a value of 1
-- does not. The count it leaves in blackboard.stagger is not the stagger that plays. blackboard.stagger_activated is. For this
-- enemy the stagger value is twice that least value, because the count of its hits is halved for a ranged hit. A stagger plays
-- while it is activated.
local function stagger_value(blackboard)
	local tweaks = blackboard.breed.stagger_difficulty_tweak_index

	if not tweaks then
		return 1
	end

	return tweaks[Managers.state.difficulty:get_difficulty_rank()].shield_block_threshold * 2
end

local function is_staggered(blackboard)
	if blackboard.breed.stagger_difficulty_tweak_index then
		return blackboard.stagger_activated == true
	end

	return blackboard.stagger ~= nil and blackboard.stagger ~= false and blackboard.stagger ~= 0
end

-- Pushes an enemy towards the owner instead of throwing it. This is for an enemy that is near enough for a throw to be too much,
-- and for one that the game does not put in a vortex, such as the leech and the sorcerers. The enemy is staggered towards the
-- place it would have landed in, as far as the distance to that place says.
local function stagger_towards(state, owner_unit, t, blackboard, place)
	local unit = state.target
	local delta = Vector3.flat(place - Unit.world_position(unit, 0))
	local distance = Vector3.length(delta)
	local direction = distance > 0.01 and delta * (1 / distance) or Vector3.forward()
	local length = math.clamp(distance * CONFIG.yank_stagger_per_meter / state.weight, CONFIG.hold_stagger_min, CONFIG.yank_stagger_max)

	-- The game's statistics look at the positions of the units in the stagger, and the mods' update runs before the game has made
	-- those positions current.
	with_valid_positions(AiUtils.stagger, unit, blackboard, owner_unit, direction, length, stagger_types.heavy, CONFIG.stagger_duration, nil, t, stagger_value(blackboard), true, false)

	state.next_stagger_t = t + CONFIG.restagger_interval
end

local function start_throw(state, owner_unit, t)
	local unit = state.target
	local blackboard = BLACKBOARDS[unit]
	local locomotion_extension = ScriptUnit.has_extension(unit, "locomotion_system")
	local aim_flat = state.flat_aim and state.flat_aim:unbox() or Vector3.forward()

	state.hold_distance = CONFIG.yank_min_distance

	-- A unit that is not an AI unit, such as a target dummy, is not thrown.
	if not blackboard or not locomotion_extension or not locomotion_extension.teleport_to then
		state.yank_land = nil

		return
	end

	-- The place the owner's game has worked out, if it has sent one
	local land = state.yank_land and state.yank_land:unbox() or throw_landing(owner_unit, aim_flat)

	state.yank_land = nil

	-- These are pushed instead of thrown. One is an enemy that the game does not put in a vortex, such as the leech and the
	-- sorcerers, which may not do what a vortex asks of it or may not live through it. It is pushed wherever it is. The other is an
	-- enemy that is near, where a throw over that distance is not worth it.
	if not blackboard.breed.vortexable or land and Vector3.length(land - Unit.world_position(unit, 0)) < CONFIG.throw_min_distance then
		stagger_towards(state, owner_unit, t, blackboard, land or Unit.world_position(owner_unit, 0))

		return
	end

	if not land then
		return
	end

	if state.throw then
		finish_throw(state)
	end

	-- The unit is put in the vortex, and the behavior takes it up on its next turn (see update_throw). It is not put in as the
	-- Thornsister's vortex, because the behavior sets a unit that has landed from the other vortexes to be driven by its
	-- animation. That unit stays where it is and does not slide on with the speed of the throw.
	blackboard.in_vortex_state = "in_vortex_init"
	blackboard.in_vortex = true

	state.throw = {
		duration = math.clamp(Vector3.length(land - Unit.world_position(unit, 0)) / (CONFIG.yank_speed / state.weight), CONFIG.throw_min_duration, CONFIG.throw_max_duration),
		land = Vector3Box(land),
		phase = "entering",
		started = t,
	}
end

-- Returns true while the unit is in the air, or about to be.
local function update_throw(state, t)
	local thrown = state.throw
	local unit = state.target
	local blackboard = BLACKBOARDS[unit]

	-- A unit that has died in the air, or is gone, is left to the game.
	if not Unit.alive(unit) or not blackboard or not HEALTH_ALIVE[unit] then
		finish_throw(state)

		return false
	end

	if thrown.phase == "entering" then
		-- The behavior has taken the unit up when it is in the vortex, which means its first turn is done. The unit is lifted off
		-- the ground, because the behavior lands a unit as soon as it sees the ground under it. It is let out on the next turn.
		if blackboard.in_vortex_state == "in_vortex" then
			blackboard.locomotion_extension:teleport_to(Unit.world_position(unit, 0) + Vector3(0, 0, CONFIG.throw_lift))

			thrown.phase = "lifted"
		elseif t - thrown.started > CONFIG.throw_enter_timeout then
			finish_throw(state)

			return false
		end

		return true
	end

	-- The unit is let out of the vortex with the velocity of a ballistic flight to where it lands, lasting the duration. The
	-- behavior flies it from there.
	if thrown.phase == "lifted" then
		local delta = thrown.land:unbox() - Unit.world_position(unit, 0)
		local flight = thrown.duration
		local velocity = Vector3(delta.x / flight, delta.y / flight, delta.z / flight + 0.5 * THROW_GRAVITY * flight)
		local locomotion_extension = blackboard.locomotion_extension

		locomotion_extension:set_wanted_velocity(velocity)
		locomotion_extension:set_affected_by_gravity(true)
		locomotion_extension:set_movement_type("constrained_by_mover")

		local ejected_from_vortex = blackboard.ejected_from_vortex or Vector3Box()

		ejected_from_vortex:store(velocity)

		blackboard.ejected_from_vortex = ejected_from_vortex
		blackboard.in_vortex_state = "ejected_from_vortex"
		thrown.phase = "flying"
		thrown.flying_since = t

		return true
	end

	-- When the unit is down, the behavior keeps the velocity it had for as long as it plays the landing, which would carry it far
	-- after a throw. So the velocity is set to zero, and the unit stops where it landed.
	if blackboard.in_vortex_state == "waiting_to_land" and not thrown.landed then
		thrown.landed = true

		blackboard.locomotion_extension:set_wanted_velocity(Vector3.zero())
	end

	-- The unit is in the air until the behavior has landed it and the unit has left the vortex. If that has not happened after a
	-- long while, the unit is let out of the vortex.
	if not blackboard.in_vortex then
		state.throw = nil

		return false
	end

	if t - thrown.flying_since > thrown.duration + CONFIG.throw_land_timeout then
		blackboard.in_vortex = false
		state.throw = nil

		return false
	end

	return true
end

-- A unit that is in the game's fall action while it is held has no mover, because the script moves it and takes the mover away.
-- The fall action looks for the mover to see if the unit has landed. So the fall is ended here, or the unit would hang in the
-- air in its falling pose.
local fall_action = rawget(_G, "BTFallAction")

if fall_action then
	mod:hook(fall_action, "run", function (func, self, unit, ...)
		if not Unit.mover(unit) then
			return "done"
		end

		return func(self, unit, ...)
	end)
end

-- The outline of an enemy that is held, in the teal of the beam. It is the game's outline of marked targets, with a color of its
-- own.
local HELD_OUTLINE = {
	method = "always",
	priority = 16,
	flag = "outline_unit", -- the game's flag for an outline that is not seen through walls
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

-- The networked objects, such as a barrel, that the host has let go of. The host goes on telling the others their pose until they
-- are at rest.
local barrel_settling = {} -- { unit, stop_at }

-- This is called when what is held is let go of, either because the target is released or because the beam ends.
local function track_released_object(state)
	if Managers.player.is_server and state.kind == "object" and state.target and Unit.alive(state.target) and is_networked_object(state.target) then
		barrel_settling[#barrel_settling + 1] = {
			stop_at = Application.time_since_launch() + CONFIG.barrel_settle_time,
			unit = state.target,
		}
	end
end

local function release_target(state)
	finish_throw(state)
	clear_held_outline(state)

	if state.target then
		bot_targets[state.target] = nil
	end

	track_released_object(state)

	state.target = nil
	state.kind = nil
	state.weight = nil
	state.actor = nil
end

-- Returns the body of an object that is held, if the unit still has it. A body is gone when the unit changes, for example a
-- lantern that is broken has other bodies. The body that was kept then cannot be asked anything until the object is looked at
-- again.
local function held_actor(state)
	local actor = state.actor

	if not actor then
		return nil
	end

	for i = 0, Unit.num_actors(state.target) - 1 do
		if Unit.actor(state.target, i) == actor then
			return actor
		end
	end

	return nil
end

-- Returns where the beam ends. That is the chest of a character, or the body of an object. For an object it is the unit while the
-- object has no body that physics drives.
local function target_position(state)
	if state.kind == "object" then
		local actor = held_actor(state)

		return actor and Actor.position(actor) or Unit.world_position(state.target, 0)
	elseif state.kind == "openable" then
		-- This is the middle of the mesh of the door or chest that was linked, worked out when it was linked. It is not the
		-- point the unit is placed at, which is its hinge.
		return state.openable_position:unbox()
	elseif state.kind == "supply" then
		-- This is the middle of the model. The unit is placed at one point of it, not the middle.
		local pose = Unit.box(state.target)

		return Matrix4x4.translation(pose)
	end

	return chest_position(state.target)
end

-- The body of an object that is held is looked for again every frame. A body that has just died is driven by its animation, and
-- its ragdoll bodies are other bodies when the ragdoll starts. With allow_any, a body that physics does not drive is taken when
-- there is none that physics does drive. An example is the copy of a ragdoll on another machine that the game has frozen. It is
-- held all the same, and it is thawed when it is held.
local function refresh_object(state, allow_any)
	local unit = state.target

	if not Unit.alive(unit) then
		state.actor = nil

		return
	end

	-- A corpse that had no ragdoll when it was linked gets the body nearest to the chest, once it has bodies.
	if not state.node_index then
		local chest = chest_position(unit)
		local nearest_actor, nearest_distance
		local any_actor, any_distance

		for i = 0, Unit.num_actors(unit) - 1 do
			local actor = Unit.actor(unit, i)

			if actor and not Actor.is_static(actor) then
				local distance = Vector3.distance(Actor.position(actor), chest)

				if Actor.is_physical(actor) and (not nearest_actor or distance < nearest_distance) then
					nearest_actor = actor
					nearest_distance = distance
				end

				if allow_any and (not any_actor or distance < any_distance) then
					any_actor = actor
					any_distance = distance
				end
			end
		end

		nearest_actor = nearest_actor or any_actor
		state.actor = nearest_actor
		state.node_index = nearest_actor and Actor.node(nearest_actor) or nil

		return
	end

	-- The body that is held is the body of the same bone as the one that was linked, wherever it came from. A bone can have more
	-- than one body: one is a box that is hit, and another is the body that falls. The one that physics drives is held.
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

-- Returns whether the link still holds. The link holds wherever the aim goes, and through walls, until the beam is let go, the
-- target is gone, or the target is further away than the beam reaches when linked.
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

-- Holds an object that is linked where the aim is, in the air at the distance it was linked at. The primary brings it to
-- yank_min_distance. The body that was linked is given the speed that takes it to that place. The object takes no damage.
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

	-- The game freezes a ragdoll that has settled. Its bodies are made kinematic, and a kinematic body does not take a speed. A
	-- ragdoll that is held is thawed once, and then it is moved by physics like the rest. A prop is not thawed, because the
	-- kinematic bodies of a prop are what it is fixed by, such as a corpse that hangs from its hinge or a lantern. Thawing them
	-- takes the prop off its hinge. A prop is held by the body that is linked, which is already one that physics drives. A
	-- networked unit such as a barrel is not thawed either, because it is the host's and is kept where it is put.
	if not state.thawed and (state.corpse or not is_networked_object(unit)) then
		state.thawed = true

		for i = 0, Unit.num_actors(unit) - 1 do
			local body = Unit.actor(unit, i)

			if state.corpse and body and Actor.is_dynamic(body) and not Actor.is_physical(body) then
				Actor.set_kinematic(body, false)
			end

			-- The body must collide with the world and be found by whatever looks for bodies. A copy of a prop on a machine that
			-- is far from it, which is the host's, can have its bodies set not to, and then it falls through the floor when it
			-- is let go.
			if body then
				Actor.set_collision_enabled(body, true)
				Actor.set_scene_query_enabled(body, true)
			end
		end
	end

	if state.corpse then
		-- This is a corpse. The body that was linked is given the speed, and the rest of the ragdoll hangs from it, so gravity and
		-- the speed of the limbs act on them as they would. The game puts a ragdoll that has lain a while to sleep, so its bodies
		-- are woken while it is held. A body that is driven by animation, which is a corpse that has not started to ragdoll, is
		-- not physical, and it waits.
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
		-- An object that physics does not drive, such as a barrel that is where it is put, is moved by the script. It stays where
		-- it is when it is let go.
		place_body(unit, actor, target_position(state) + velocity * dt)
	end
end

-- Makes a unit that is climbing a ledge leave the climb. The game's climb action gives up when the reason it was started for,
-- which is whether the unit was in combat, is not the case any more, and it puts the unit's movement and gravity back as they
-- were. A unit that is stuck in the climb and is moved away stays in its climbing pose, in the air.
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

	if state.yank then
		state.yank = nil

		start_throw(state, owner_unit, t)
	end

	local throwing = state.throw ~= nil and update_throw(state, t)
	local owner_position = Unit.world_position(owner_unit, 0)
	local wanted = owner_position + (state.flat_aim and state.flat_aim:unbox() or Vector3.forward()) * state.hold_distance
	local current = Unit.world_position(unit, 0)
	local delta = Vector3.flat(wanted - current)
	local distance = Vector3.length(delta)

	-- A target dummy does not lag, because it is not moved. It is not an AI unit, so it stands where it is. It is linked and
	-- damaged but not moved about, and the beam stays on it wherever the aim goes.
	state.lag = is_ai and Vector3Box(delta) or nil

	-- A unit that is thrown is not staggered. The vortex it is in forbids being staggered, and the behavior flies and lands it.
	if throwing then
		return
	end

	-- Climbing a ledge forbids being staggered, and it keeps the unit in the climb and its animation. A held enemy is let out of
	-- the climb, so the stagger takes it out of the climb.
	local held_blackboard = BLACKBOARDS[unit]

	if held_blackboard and (held_blackboard.stagger_prohibited or held_blackboard.climb_state) then
		held_blackboard.stagger_prohibited = nil
		state.next_stagger_t = nil

		leave_climb(held_blackboard)
	end

	-- The enemy is staggered again when the stagger it has is over. The game counts staggers in the blackboard and the behavior
	-- ends them. A stagger that is given while one plays starts it over in the middle of its animation.
	local blackboard = BLACKBOARDS[unit]
	if blackboard and not is_staggered(blackboard) and t >= (state.next_stagger_t or 0) then
		state.next_stagger_t = t + CONFIG.restagger_interval

		local direction = distance > 0.01 and Vector3.normalize(delta) or Vector3.forward()
		-- The stagger is what moves the enemy. The game moves a staggered enemy over the ground, as far as the length says, the
		-- way it is pushed, with the walls and the navmesh in the way, and the other machines see it do that. The length is how
		-- far the enemy needs to go, and it is less for a heavy enemy.
		local length = math.clamp(distance * CONFIG.hold_stagger_per_meter / state.weight, CONFIG.hold_stagger_min, CONFIG.hold_stagger_max)

		-- The game's statistics look at the positions of the units in the stagger, and the mods' update runs before the game has
		-- made those positions current.
		with_valid_positions(AiUtils.stagger, unit, blackboard, owner_unit, direction, length, stagger_types.heavy, CONFIG.stagger_duration, nil, t, stagger_value(blackboard), true, false)
	end
end

-- The damage buff on a linked ally is kept up below.
-- Returns whether the ally is attacking, which means a primary action of their weapon is running.
local function is_ally_attacking(unit)
	local inventory_extension = ScriptUnit.has_extension(unit, "inventory_system")
	local equipment = inventory_extension and inventory_extension:equipment()
	local weapon_extension = equipment and (equipment.right_hand_weapon_extension or equipment.left_hand_weapon_extension)

	return weapon_extension ~= nil and weapon_extension.current_action_settings ~= nil and weapon_extension.current_action_name == "action_one"
end

-- Damage the ally deals counts as attacking too. The host gets all damage, while the actions of other players' weapons are only
-- seen from their own game.
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

-- Returns whether the beam is free. The beam only costs heat while it is linked to an enemy, or to an ally while they attack and
-- for ally_attack_grace seconds after. This is told to the game's add_charge for the beam's heat (see mod.overcharge_callbacks).
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

-- Heat is the owner's and is added on the owner's machine. The host works out what the beam does to what it is linked to for the
-- beams of the other players, and it tells the owner's game to add the heat.
local function charge_owner(owner_unit, amount, overcharge_type)
	local owner_player = Managers.player:owner(owner_unit)

	if owner_player.local_player then
		local overcharge_extension = ScriptUnit.has_extension(owner_unit, "overcharge_system")

		if overcharge_extension then
			-- A negative amount is a share of the whole bar. How much the whole bar holds depends on the staff and the buffs.
			if amount < 0 then
				amount = -amount * overcharge_extension:get_max_value()
			end

			if amount > 0 then
				overcharge_extension:add_charge(amount, nil, overcharge_type)
			end
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

-- The critters, which are the rats and the other ambient animals, are not poisoned by the beam or the bolts. Both use the staff's
-- damage source.
mod:hook(Dots, "poison_dot", function (func, dot_template_name, damage_profile, target_index, power_level, target_unit, attacker_unit, hit_zone_name, damage_source, ...)
	local breed = AiUtils.unit_breed(target_unit)

	if damage_source == CONFIG.dot_damage_source and breed and breed.race == "critter" then
		return false
	end

	return func(dot_template_name, damage_profile, target_index, power_level, target_unit, attacker_unit, hit_zone_name, damage_source, ...)
end)

-- Applies the damage over time to a linked enemy.
local function damage_enemy(state, owner_unit, t)
	if t < (state.next_dot_t or 0) then
		return
	end

	state.next_dot_t = t + CONFIG.dot_interval

	local unit = state.target

	-- Every application costs heat.
	charge_owner(owner_unit, CONFIG.dot_overcharge, "ut_link_dot")

	-- This is the game's own poison, the one of poisoned arrows and the like. It is a buff on the enemy that does the damage over
	-- time and shows the enemy as poisoned. It is applied again every dot_interval, which keeps it up while the enemy is linked.
	Dots.poison_dot(CONFIG.dot_template, nil, nil, CONFIG.dot_power_level, unit, owner_unit, "torso", CONFIG.dot_damage_source, 1, false, owner_unit)
end

-- The look of the buff is the Thornsister's own buff effect, which she gets when health is converted. It is a burst at the ally
-- that follows them, played again every ally_effect_interval seconds while they are linked. Everyone sees it, because the host,
-- which makes the link work, tells the others each time.
local function play_ally_effect(world, unit)
	-- An effect that is not loaded crashes the game.
	if not effects.is_available(CONFIG.ally_effect) then
		return
	end

	local effect_id = World.create_particles(world, CONFIG.ally_effect, Unit.world_position(unit, 0), Quaternion.identity())

	World.link_particles(world, effect_id, unit, Unit.node(unit, "root_point"), Matrix4x4.identity(), "stop")
end

mod:network_register("ut_link_ally_effect", function (_, target_go_id)
	local unit = Managers.state.unit_storage:unit(target_go_id)

	if unit and Unit.alive(unit) then
		play_ally_effect(Managers.world:world("level_world"), unit)
	end
end)

local function show_ally_buff(state, world, t)
	if t < (state.next_ally_effect_t or 0) or not world or not Unit.alive(state.target) then
		return
	end

	state.next_ally_effect_t = t + CONFIG.ally_effect_interval

	play_ally_effect(world, state.target)
	mod:network_send("ut_link_ally_effect", "others", Managers.state.unit_storage:go_id(state.target))
end

-- The temporary health an ally gets from their attacks is doubled while they are linked. These are the game's heals that come
-- from procs of hits and kills, such as the leech of talents and weapons. The host works out the heals, and the buff is there.
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

-- A bot that is linked attacks the nearest enemy. The bots' own urgent target, which is what they attack first from where they
-- are, as they do with a boss, is set to that enemy. It is not the priority target, because that is always about an ally that is
-- held, and the bot code looks for the ally. The game works the urgent targets out again every frame and takes this one away, so
-- it is set again after that, below.
local function apply_bot_target(bot_unit, enemy)
	local blackboard = BLACKBOARDS[bot_unit]
	local from = Unit.alive(bot_unit) and Unit.world_position(bot_unit, 0)
	local to = Unit.alive(enemy) and Unit.world_position(enemy, 0)

	if blackboard and from and to then
		blackboard.urgent_target_enemy = enemy
		blackboard.urgent_target_distance = Vector3.length(to - from)
		blackboard.revive_with_urgent_target = false
	end
end

local function force_bot_target(bot_unit)
	-- A bot that has the enemy it is made to attack, as long as the enemy is alive, keeps it and does not look for another.
	local current = bot_targets[bot_unit]

	if current and HEALTH_ALIVE[current] then
		apply_bot_target(bot_unit, current)

		return
	end

	if (bot_scan_after[bot_unit] or 0) > Managers.time:time("game") then
		return
	end

	local player = Managers.player:owner(bot_unit)
	-- The position is read from the unit, because the bot's entry in POSITION_LOOKUP is not a vector the broadphase takes.
	local position = Unit.alive(bot_unit) and Unit.world_position(bot_unit, 0)

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
			local distance = Vector3.distance_squared(Unit.world_position(unit, 0), position)

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
		-- There is nothing to attack near the bot. It looks again in a moment, not every frame.
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
end

-- The host looks at the buff of the allies every frame, for every unit that has buffs, by asking the unit what it has.
--   * A unit that is linked has as many of the buff with no duration as there are Link Guns that have it linked, at most
--     ally_buff_max_stacks, and none of the timed buff.
--   * A unit that has more of them than that loses one. The last one is exchanged for the one that lasts ally_buff_linger seconds,
--     which runs out by itself.
--   * A unit that has the timed buff, or none, is left alone.
-- This takes care of whatever ended the link: a beam that is let go of, an ally that was swapped for another or that left, or
-- the beam of a player that has gone. The buffs are synced, and the ally's own game works out what they do. A unit changes by one
-- buff a frame, so it gets to the right number in a few frames.
local function add_ally_buff(unit, owner_unit, template_name)
	Managers.state.entity:system("buff_system"):add_buff_synced(unit, template_name, BuffSyncType.All, {
		attacker_unit = owner_unit,
	})
end

local function remove_ally_buff(unit, buff)
	Managers.state.entity:system("buff_system"):remove_buff_synced(unit, buff.id)
end

-- Who has each unit linked: how many players do, and one of them
local link_counts = {} -- { [the unit that is linked] = number of beams }
local link_owners = {} -- { [the unit that is linked] = the unit of one that holds a beam on it }

-- Returns the first of the unit's buffs that has a duration, or the first that has none.
local function first_stack(stacks, timed)
	for i = 1, #stacks do
		if (stacks[i].duration ~= nil) == timed then
			return stacks[i]
		end
	end
end

local function update_ally_buffs()
	table.clear(link_counts)

	for owner_unit, state in pairs(states) do
		if state.kind == "ally" and state.target then
			link_counts[state.target] = (link_counts[state.target] or 0) + 1
			link_owners[state.target] = owner_unit
		end
	end

	for unit, buff_extension in pairs(Managers.state.entity:get_entities("BuffExtension")) do
		-- The buffs of the allies have the one name, which is the type of the buff. A timed one has a duration.
		local stacks = buff_extension:get_stacking_buff(ALLY_BUFF)
		local wanted = math.min(link_counts[unit] or 0, CONFIG.ally_buff_max_stacks)

		if stacks or wanted > 0 then
			stacks = stacks or {}

			local timed = first_stack(stacks, true)
			local permanent = first_stack(stacks, false)
			local num_permanent = 0

			for i = 1, #stacks do
				if stacks[i].duration == nil then
					num_permanent = num_permanent + 1
				end
			end

			if wanted > 0 and timed then
				remove_ally_buff(unit, timed)
			elseif num_permanent < wanted then
				add_ally_buff(unit, link_owners[unit], ALLY_BUFF)
			elseif num_permanent > wanted then
				remove_ally_buff(unit, permanent)

				if wanted == 0 and num_permanent == 1 then
					add_ally_buff(unit, nil, ALLY_BUFF_FADING)
				end
			end
		end
	end
end

-- Takes all the ally buffs away when the beams are cleared.
local function clear_ally_buffs()
	for unit, buff_extension in pairs(Managers.state.entity:get_entities("BuffExtension")) do
		local buff = buff_extension:get_buff_type(ALLY_BUFF)

		while buff do
			remove_ally_buff(unit, buff)

			buff = buff_extension:get_buff_type(ALLY_BUFF)
		end
	end
end

-- The beam is a curve from the staff to the end of the beam, a cubic Bezier.
local function bezier(p0, p1, p2, p3, s)
	local a = p0 * ((1 - s) * (1 - s) * (1 - s))
	local b = p1 * (3 * (1 - s) * (1 - s) * s)
	local c = p2 * (3 * (1 - s) * s * s)
	local d = p3 * (s * s * s)

	return a + b + c + d
end

-- The points of the beam are kept between frames. The skin draws the beam (link_beam_callbacks.draw).
local beam_points = {}

-- Fills `points` with the points of the beam, from the first entry on, as a curve from the start to the end, and returns how many
-- points there are. The aim is the way the holder is aiming. The weight is what hangs from the beam, and the lag is how far what
-- is held is behind where it is being moved to. Both are nil when there is none.
local function beam_curve(points, start_position, end_position, aim, weight, lag, segment_length)
	local length = Vector3.length(end_position - start_position)
	-- The beam leaves the staff bowed towards the aim and arrives at the target straight on, along the way from the staff to the
	-- target. The part of the aim that is sideways to that way pushes the start of the curve by up to beam_aim_curve of the
	-- length. So the beam is straight when the target is right on the aim, and it is a gentle bow when it is not, and never a
	-- hook. The end of the effect points at the target, not past it.
	local first_control = start_position + (end_position - start_position) * (1 / 3)
	local second_control = start_position + (end_position - start_position) * (2 / 3)

	if length > 0.01 then
		local direction = (end_position - start_position) * (1 / length)
		local sideways = aim - direction * Vector3.dot(aim, direction)

		first_control = first_control + sideways * (length * CONFIG.beam_aim_curve * CONFIG.beam_aim_curve_gain)
	end

	local sag = weight and math.min(CONFIG.sag_max, CONFIG.sag_per_weight * weight * length) or 0
	local bend = lag and lag * CONFIG.lag_bend or Vector3.zero()
	-- What hangs or lags bends only the first half, so the beam still arrives at the target straight on. The bend is also never
	-- more than lag_bend_max, so an enemy that is far from where the aim is, held by something else, does not bend the whole beam.
	if Vector3.length(bend) > CONFIG.lag_bend_max then
		bend = Vector3.normalize(bend) * CONFIG.lag_bend_max
	end

	first_control = first_control + (bend - Vector3.up() * sag) * CONFIG.beam_hang_share

	-- There is a point about every segment_length of the beam, so a longer beam has more particles.
	local segments = math.clamp(math.ceil(length / segment_length), CONFIG.beam_min_segments, CONFIG.beam_max_segments)

	points[1] = start_position

	for i = 1, segments do
		points[i + 1] = bezier(start_position, first_control, second_control, end_position, i / segments)
	end

	return segments + 1
end

-- The beam sets off the Bio Rifle's goop along its length (the link gun's beam has bDetonatesGoop in UT).
local function beam_sets_off_goop(points, count)
	local detonate = mod.bio_goop and mod.bio_goop.detonate_segment

	if detonate then
		for i = 1, count - 1 do
			detonate(points[i], points[i + 1])
		end
	end
end

local function draw_beam(state, start_position, rotation, end_position, weight, lag)
	local count = beam_curve(beam_points, start_position, end_position, Quaternion.forward(rotation), weight, lag, CONFIG.beam_segment_length)

	beam_sets_off_goop(beam_points, count)
	mod.link_beam_callbacks.draw(state, beam_points, count)
end

local function end_beam(owner_unit)
	local state = states[owner_unit]

	if state then
		-- The others stop drawing the beam, and the host stops doing what the link does, if the host is the one that does it.
		local owner_go_id = (state.beam_sent or state.input_sent) and Unit.alive(owner_unit) and Managers.state.unit_storage:go_id(owner_unit)

		if owner_go_id then
			mod:network_send("ut_link_beam_end", "others", owner_go_id)

			if state.input_sent then
				mod:network_send("ut_link_input_end", "others", owner_go_id)
			end
		end

		finish_throw(state)
		clear_held_outline(state)
		stop_drone(owner_unit)
		track_released_object(state)

		if state.target then
			bot_targets[state.target] = nil
		end

		states[owner_unit] = nil
	end
end

-- Links the beam to a target.
local function link_target(state, owner_unit, unit, kind, actor, object_distance)
	state.target = unit
	state.kind = kind
	state.actor = actor
	state.weight = kind == "enemy" and enemy_weight(unit) or nil
	state.next_stagger_t = nil
	state.next_dot_t = nil
	state.hold_distance = math.clamp(Vector3.length(Vector3.flat(Unit.world_position(unit, 0) - Unit.world_position(owner_unit, 0))), CONFIG.hold_min_distance, CONFIG.beam_range)

	if kind == "enemy" or kind == "monster" or kind == "supply" or kind == "openable" or kind == "object" then
		add_held_outline(state)
	end

	if kind == "monster" then
		state.monster_start = Vector3Box(Unit.world_position(unit, 0))
	elseif kind == "openable" then
		state.openable_position = Vector3Box(actor and mesh_center(actor) or Matrix4x4.translation(Unit.box(unit)))
	elseif kind == "object" then
		state.hold_distance = math.clamp(object_distance, CONFIG.yank_min_distance, CONFIG.beam_range)
		-- There is no body when the host links what the owner's game has picked, so the body is looked for from the unit.
		state.node_index = actor and Actor.node(actor) or nil
		-- This is where the object lay when it was linked. The others look for their copy of it there, because it is not there for
		-- long.
		state.link_position = actor and Vector3Box(Actor.position(actor)) or Vector3Box(Unit.world_position(unit, 0))
		state.thawed = false
		-- This is when the object was linked. Of two players who hold a prop, the one that linked it last has it.
		state.link_time = Application.time_since_launch()
		state.corpse = AiUtils.unit_breed(unit) ~= nil

		if state.corpse then
			preserve_corpse(unit)
		end
	end
end

-- Returns whether the primary was just pressed. Yanking is pressing primary once for every press, and holding it down is not a
-- yank.
local function yank_pressed(state, owner_unit)
	local input_extension = ScriptUnit.has_extension(owner_unit, "input_system")
	local down = input_extension ~= nil and input_extension:get("action_one_hold") == true
	local pressed = down and not state.yank_was_down

	state.yank_was_down = down

	return pressed
end

-- Adds heat on top of the heat of the beam.
local function add_heat(owner_unit, amount)
	charge_owner(owner_unit, amount, "ut_link_yank")
end

-- A unit that is yanked out of a vortex is not pulled into one for vortex_immunity seconds. Otherwise it would be pulled in at
-- once while it is yanked. The vortices do not let in a unit that is immune, whether it is a player or a unit of the AI. The
-- value stored for a unit is the time its immunity ends.
local vortex_immunity = setmetatable({}, {__mode = "k"}) -- { [the unit] = the time it ends }

local function is_vortex_immune(unit)
	local ends = vortex_immunity[unit]

	return ends ~= nil and Managers.time:time("game") < ends
end

mod:hook(StatusUtils, "set_in_vortex_network", function (func, affected_unit, in_vortex, ...)
	-- This is what puts a player in a vortex. If it is refused, the vortex goes on to the next target.
	if in_vortex and is_vortex_immune(affected_unit) then
		return false
	end

	return func(affected_unit, in_vortex, ...)
end)

-- A player or a bot that is immune is not a target of a vortex at all. A vortex pulls the units that are not in it towards it and
-- holds the ones it thinks it has, and refusing to set them in it again does not stop that. A vortex lets go of a unit that stops
-- being a target, and so does the state of being in a vortex.
mod:hook(GenericStatusExtension, "is_valid_vortex_target", function (func, self, ...)
	if is_vortex_immune(self.unit) then
		return false
	end

	return func(self, ...)
end)

-- A vortex pulls in the enemies that are outside it if they are near. The ones that are immune are marked as inside it while the
-- vortex looks for them, so that it does not pull them in.
if rawget(_G, "VortexExtension") then
	mod:hook(VortexExtension, "_update_attract_outside_ai", function (func, self, vortex_data, ...)
		local ai_units_inside = vortex_data.ai_units_inside
		local immune = FrameTable.alloc_table()

		for unit in pairs(vortex_immunity) do
			if Unit.alive(unit) and not ai_units_inside[unit] and is_vortex_immune(unit) then
				ai_units_inside[unit] = true
				immune[#immune + 1] = unit
			end
		end

		func(self, vortex_data, ...)

		for i = 1, #immune do
			ai_units_inside[immune[i]] = nil
		end
	end)
end

-- Yanking an enemy lets it out of a vortex if it is in one, at a cost, and it is then immune to vortices for a time. Otherwise the
-- enemy is thrown to the owner.
local function yank_enemy(state, owner_unit)
	-- An enemy that is already in the air of a throw is not thrown again, and it is not in one of the game's vortices.
	if state.throw then
		return
	end

	local blackboard = BLACKBOARDS[state.target]

	if blackboard and blackboard.in_vortex then
		blackboard.in_vortex = false
		blackboard.thornsister_vortex = nil
		-- The vortex it was in lets it go. The vortex takes a unit that has landed out of the ones it holds, and no longer
		-- controls it.
		blackboard.in_vortex_state = "landed"
		vortex_immunity[state.target] = Managers.time:time("game") + CONFIG.vortex_immunity

		add_heat(owner_unit, CONFIG.yank_free_overcharge)

		return
	end

	state.yank = true
end

-- Getting someone up by a yank gives the game's own result of the interaction, which is what the game does when the interaction
-- is over. The other half is the animation of the player who is got up, which the interaction plays itself, and the fall of being
-- knocked down is only left with it. The state of the player who is got up is not always ready to take the result when it is
-- given, for example in the middle of going down. So the result is given again, a few times, until the player has taken it.
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

-- Yanking a player or a bot does the first of these that applies. The player or bot is freed from what holds them, which is a
-- disabler or a vortex. Or they are pulled up from a ledge. Or they are got up from being knocked down. Otherwise they are
-- launched at the owner, in the state of being launched by the game's monsters. All of these cost heat, and the launch costs a
-- lot.
local function yank_ally(state, owner_unit, t)
	local unit = state.target
	local status_extension = ScriptUnit.has_extension(unit, "status_system")

	-- The cost is high so that the yank is not used to grief other players. A bot cannot be griefed, so it costs much less.
	local player = Managers.player:owner(unit)
	local cost_scale = player and player.bot_player and CONFIG.bot_yank_cost_scale or 1

	local game_add_heat = add_heat

	local function add_heat(owner, amount)
		return game_add_heat(owner, amount * cost_scale)
	end

	-- A player who is waiting to be set free is set free the game's own way, with the owner as the one who did it.
	if status_extension and status_extension:is_ready_for_assisted_respawn() then
		StatusUtils.set_respawned_network(unit, true, owner_unit)
		-- This is also what the game's interaction records, so the rescue counts as the owner's.
		StatisticsUtil.register_assisted_respawn(owner_unit, unit, Managers.player:statistics_db())
		add_heat(owner_unit, CONFIG.yank_rescue_overcharge)

		return
	end

	if not status_extension or status_extension:is_dead() then
		return
	end

	local disabler_unit = utils.get_disabler(status_extension)

	if status_extension:is_hanging_from_hook() then
		-- A player hung up on a hook by a pack master is let down, as the game's interaction does it.
		StatusUtils.set_grabbed_by_pack_master_network("pack_master_dropping", unit, true, nil)
		add_heat(owner_unit, CONFIG.yank_free_overcharge)
	elseif disabler_unit then
		utils.release_from_disabler(disabler_unit, unit, t, CONFIG.disabler_stagger_duration)
		add_heat(owner_unit, CONFIG.yank_free_overcharge)
	elseif status_extension:is_in_vortex() then
		StatusUtils.set_in_vortex_network(unit, false, nil)
		vortex_immunity[unit] = Managers.time:time("game") + CONFIG.vortex_immunity
		add_heat(owner_unit, CONFIG.yank_free_overcharge)
	elseif status_extension:get_is_ledge_hanging() then
		give_rescue(unit, "pull_up", owner_unit)
		StatisticsUtil.register_pull_up(owner_unit, unit, Managers.player:statistics_db())
		pending_rescues[unit] = {kind = "pull_up", owner = owner_unit, next_t = t + CONFIG.rescue_retry_interval, tries = 0}
		add_heat(owner_unit, CONFIG.yank_rescue_overcharge)
	elseif status_extension:is_knocked_down() then
		give_rescue(unit, "revive", owner_unit)
		StatisticsUtil.register_revive(owner_unit, unit, Managers.player:statistics_db())
		pending_rescues[unit] = {kind = "revive", owner = owner_unit, next_t = t + CONFIG.rescue_retry_interval, tries = 0}
		add_heat(owner_unit, CONFIG.yank_rescue_overcharge)
	elseif not status_extension:is_disabled() and not status_extension:is_catapulted() then
		-- A player who is already flying to the owner is not launched again.
		local flat = Vector3.flat(Unit.world_position(owner_unit, 0) - Unit.world_position(unit, 0))
		local distance = Vector3.length(flat)
		local direction = distance > 0.1 and flat * (1 / distance) or Vector3.forward()
		local velocity = direction * math.clamp(distance * CONFIG.monster_pull_per_meter, CONFIG.monster_pull_min_speed, CONFIG.monster_pull_max_speed)

		Vector3.set_z(velocity, CONFIG.monster_pull_up_speed)
		StatusUtils.set_catapulted_network(unit, true, velocity)
		add_heat(owner_unit, player and player.bot_player and CONFIG.yank_bot_overcharge or CONFIG.yank_player_overcharge)
	end
end

-- Breaks down something that can be broken (see is_breakable). Its health is dealt as damage in break_hits blows, break_hit_interval
-- seconds apart, the way the game deals the damage of a hit to a thing in the level. The game sends the damage to the host when
-- this is not the host. The level answers each blow with the flow event of a hit, which carries the health that is left. A thing
-- that breaks in stages shows them. A single blow that takes all of the health would have the level go from whole to gone.
local function break_down(state, owner_unit, t)
	state.break_hits = CONFIG.break_hits
	state.break_next_t = t

	add_heat(owner_unit, CONFIG.yank_door_overcharge)
end

local function update_break(state, owner_unit, t)
	if t < state.break_next_t then
		return
	end

	local unit = state.target
	local health_extension = Unit.alive(unit) and ScriptUnit.has_extension(unit, "health_system")

	if not health_extension or not health_extension:is_alive() then
		state.break_hits = nil

		release_target(state)

		state.link_block_until = t + CONFIG.supply_retry

		return
	end

	local direction = Vector3.normalize(Unit.world_position(unit, 0) - Unit.world_position(owner_unit, 0))

	-- Each blow deals a share of the health that is left, and the last blow deals all of it.
	local damage = health_extension:current_health() / state.break_hits

	state.break_hits = state.break_hits - 1
	state.break_next_t = t + CONFIG.break_hit_interval

	DamageUtils.add_damage_network(unit, owner_unit, damage, "full", "destructible_level_object_hit", nil, direction, CONFIG.dot_damage_source, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, 1)

	if state.break_hits <= 0 then
		state.break_hits = nil

		release_target(state)

		state.link_block_until = t + CONFIG.supply_retry
	end
end

-- Does what the game does when a shot hits a unit that has no health. Such a unit is not only one placed in the level, because the
-- game spawns some. The game sets what it knows about the hit as flow variables of the unit and gives the unit the flow event,
-- which the level answers. For example, a lantern comes down.
local function give_simple_damage(unit, actor, position, direction)
	Unit.set_flow_variable(unit, "hit_actor", actor)
	Unit.set_flow_variable(unit, "hit_direction", direction)
	Unit.set_flow_variable(unit, "hit_position", position)
	Unit.flow_event(unit, "lua_simple_damage")
end

-- The flow event is the machine's own. A prop that is not a networked unit is on every machine, and what happens to it happens on
-- the machine that gives the event. The other players are told what was hit, by its id, or by where it is if it has no id, and
-- they give the event too.
local function simple_damage(state, owner_unit)
	local unit = state.target

	local actor = held_actor(state)

	if ScriptUnit.has_extension(unit, "health_system") or Unit.get_data(unit, "allow_ranged_damage") == false or not actor then
		return
	end

	local position = Actor.position(actor)
	local direction = Vector3.normalize(position - Unit.world_position(owner_unit, 0))

	give_simple_damage(unit, actor, position, direction)
	mod:network_send("ut_link_simple_damage", "others", object_id_of(unit), position.x, position.y, position.z, direction.x, direction.y, direction.z)
end

mod:network_register("ut_link_simple_damage", function (_, object_id, x, y, z, direction_x, direction_y, direction_z)
	local position = Vector3(x, y, z)
	local unit = object_unit_of(object_id)

	-- A prop that has no id on this machine is the one that is where the owner hit it.
	if not unit then
		unit = find_object_near(World.get_data(Managers.world:world("level_world"), "physics_world"), position, CONFIG.object_search_radius)
	end

	if not unit or not Unit.alive(unit) then
		return
	end

	-- The body that is hit is the one nearest to where the prop was hit.
	local nearest_actor, nearest_distance

	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		if actor then
			local distance = Vector3.distance(Actor.position(actor), position)

			if not nearest_distance or distance < nearest_distance then
				nearest_actor = actor
				nearest_distance = distance
			end
		end
	end

	if nearest_actor then
		give_simple_damage(unit, nearest_actor, position, Vector3(direction_x, direction_y, direction_z))
	end
end)

-- This is the time until which an owner cannot yank or link anything, after an interaction was started for them. Starting an
-- interaction stops the weapon's action, because the game stops the actions of the weapons while a player interacts. That ends the
-- beam and its state. The beam then starts again with a new state while the buttons are still down, and the yank button that is
-- still held counts as a new press on the door that is still in front of it. The door was then opened and closed, and the heat was
-- paid, once for each, until the button was let go of. The state is gone by then, so this time is kept by the owner.
local interaction_block = setmetatable({}, {__mode = "k"}) -- { [the unit of the owner] = the time it ends }

-- Yanking a door opens it or closes it, yanking a chest opens it, and yanking a lever uses it. All of these use the game's own
-- interaction, the same way a supply is picked up, for the host and for the others alike. The game sends the interaction to every
-- machine, and each toggles its door once. It also lets only one player at a time interact with a door. A door that is toggled by
-- the script on one machine only, or twice at once by two players, ends up a different door on each machine.
local function yank_openable(state, owner_unit, t)
	local interactor_extension, interaction_type = supply_interaction(owner_unit, state.target)

	if interactor_extension then
		interactor_extension:start_interaction("action_two_hold", state.target, interaction_type)
		add_heat(owner_unit, CONFIG.yank_door_overcharge)

		-- The link is over, and it does not come back while the chest is being opened.
		release_target(state)

		state.link_block_until = t + CONFIG.supply_retry
		interaction_block[owner_unit] = t + CONFIG.supply_retry
	elseif is_breakable(state.target) then
		break_down(state, owner_unit, t)
	end
end

-- What is linked to is chosen by the player who holds the beam, from what they see. The host's own beam picks it here. The beam of
-- another player is picked by their game, which tells the host (see the inputs of the others below). The allowed_kinds argument
-- limits what can be linked, and nil allows everything.
local function select_target(state, owner_unit, origin, aim, t, physics_world, allowed_kinds)
	if state.target and state.kind == "object" then
		refresh_object(state)
	end

	if state.target and not is_link_valid(state, origin) then
		release_target(state)
	end

	-- What is linked stays linked until the beam is let go. A new target is only picked when nothing is linked, and it is the most
	-- important of what the aim is on: living things, then supplies, doors and objects.
	if not state.target and t >= (state.link_block_until or 0) then
		local unit, kind, actor, object_distance = find_target(owner_unit, physics_world, origin, aim)

		-- A supply is only linked if the owner can pick it up
		if unit and kind == "supply" and not supply_interaction(owner_unit, unit) then
			state.link_block_until = t + CONFIG.supply_retry

			unit = nil
		end

		-- The prop that another player took from this beam is not linked again until the beam is let go of (see run_link).
		if unit and unit == state.avoid_unit then
			unit = nil
		end

		if unit and (not allowed_kinds or allowed_kinds[kind]) then
			link_target(state, owner_unit, unit, kind, actor, object_distance)
		end
	end
end

-- This records who holds a prop (not a ragdoll) on this machine. The holders are this machine's own beam and the copies it has of
-- the beams of the other players. Each holder is stored with when it was last seen holding the prop and since when it has held it.
-- The prop is moved by every hold on every machine that has it. When more than one beam holds it, they pull it different ways, and
-- each machine has its own hold win. The player who linked the prop last takes it, which steals the link, and the one who had it
-- is let go of, on every machine. If two players linked it in the same moment, the one whose character has the lowest game object
-- id takes it.
local object_holders = {} -- { [the unit of the prop] = { [the unit of the holder] = { seen, since } } }

local function note_object_holder(unit, owner_unit, now, since)
	local holders = object_holders[unit]

	if not holders then
		holders = {}
		object_holders[unit] = holders
	end

	local holder = holders[owner_unit]

	if not holder then
		holder = {}
		holders[owner_unit] = holder
	end

	holder.seen = now
	holder.since = since
end

local function object_hold_counts(unit, owner_unit, now)
	local holders = object_holders[unit]
	local unit_storage = Managers.state.unit_storage
	local own_since = holders[owner_unit].since
	local own_id = unit_storage:go_id(owner_unit)

	for other_unit, holder in pairs(holders) do
		if other_unit ~= owner_unit then
			if not Unit.alive(other_unit) or now - holder.seen > CONFIG.object_holder_timeout then
				holders[other_unit] = nil
			elseif holder.since > own_since or holder.since == own_since and unit_storage:go_id(other_unit) < own_id then
				return false
			end
		end
	end

	return true
end

-- This does what happens while a beam is linked. The host does it, because the host has the enemies, the allies and the objects.
-- It works from where the owner's eye is, where it is aimed, and whether the primary was pressed since the last frame, which is a
-- yank. Those are the owner's own when the owner is the host. When the owner is not the host, they are what the owner's game
-- sends. See the inputs of the others below.
local function run_link(state, owner_unit, origin, aim, yanked, dt, t, physics_world)
	if not state.target then
		return
	end

	-- Something that is being broken down is only that, until it is done.
	if state.break_hits then
		update_break(state, owner_unit, t)

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
		-- A monster is too big to be held. The beam stays on it, and when it moves, or it is yanked, the owner is launched
		-- towards it and the link is over.
		local moved = Vector3.length(Vector3.flat(Unit.world_position(state.target, 0) - state.monster_start:unbox()))

		if yanked or moved >= CONFIG.monster_move_distance then
			launch_towards_monster(state, owner_unit, state.target, t)
			release_target(state)
		else
			damage_enemy(state, owner_unit, t)
		end
	elseif state.kind == "object" and yanked and is_breakable(state.target) then
		-- An object that is something to break down, such as a lantern that hangs, is a body that physics moves, and it is linked
		-- as one. A yank breaks it, which is what shooting it does.
		break_down(state, owner_unit, t)
	elseif state.kind == "object" then
		-- Some things in the level are hit by what is shot at them and have no health, for example a lantern that hangs. The level
		-- itself does what is to be done when such a thing is hit. It does this from the flow event that the game gives the thing
		-- when a shot hits it, which says where the hit was and where it came from. This is only for what is held to something. A
		-- yank pulls the object to the owner. A free object, such as a bottle that breaks when it is hit, comes to the owner. An
		-- object that is hung stays where the chain lets it be. Which of these happened is checked anchor_check_delay seconds
		-- after the yank.
		if yanked then
			state.anchor_check_t = t + CONFIG.anchor_check_delay
		end

		if state.anchor_check_t and t >= state.anchor_check_t then
			state.anchor_check_t = nil

			local actor = held_actor(state)

			if actor and Vector3.distance(Actor.position(actor), origin + aim * state.hold_distance) > CONFIG.anchored_distance then
				simple_damage(state, owner_unit)
			end
		end

		-- An object that is already being pulled in is not yanked again. It is held where a yank would hold it.
		state.yank = state.yank or yanked and state.hold_distance > CONFIG.yank_min_distance

		-- The body that is held is looked for every frame. The host's own beam does this when it picks, but a beam of another
		-- player that the host holds an object for does not.
		refresh_object(state)

		-- A prop that more than one beam holds is moved by one of them, the same one on every machine. That is the last beam to
		-- link it, which takes the prop from the one that had it.
		local now = Application.time_since_launch()

		note_object_holder(state.target, owner_unit, now, state.link_time or now)

		if state.corpse or object_hold_counts(state.target, owner_unit, now) then
			hold_object(state, aim, origin, dt)
		else
			-- The prop is let go of and not linked again by this beam. Otherwise this beam would take it back at once, and the two
			-- beams would take it from each other every frame, until the beam is let go of and pressed again.
			state.avoid_unit = state.target

			release_target(state)
		end
	elseif state.kind == "enemy" then
		local breed = AiUtils.unit_breed(state.target)

		-- A critter, such as a rat that runs about the level, has no stagger and is not put in a vortex, so it can be neither
		-- pushed nor thrown. A yank kills it. This is the game's own kill of a unit and not damage that the owner does.
		if yanked and breed and breed.race == "critter" then
			AiUtils.kill_unit(state.target)
			release_target(state)

			return
		end

		if yanked then
			yank_enemy(state, owner_unit)
		end

		hold_enemy(state, owner_unit, t, dt, aim, physics_world)
		damage_enemy(state, owner_unit, t)
	else
		local breed = AiUtils.unit_breed(state.target)

		if breed and not breed.is_player then
			-- A skeleton is an AI unit, and it is thrown to the owner like an enemy.
			local flat_aim = Vector3.flat(aim)

			if Vector3.length(flat_aim) > 0.1 then
				state.flat_aim = Vector3Box(Vector3.normalize(flat_aim))
			end

			-- A unit that is already in the air of a throw is not thrown again.
			if yanked and not state.throw then
				state.weight = state.weight or 1

				start_throw(state, owner_unit, t)

				-- It is let out of a climb, like a held enemy. The vortex it is put in takes it out of the behavior of climbing.
				local blackboard = BLACKBOARDS[state.target]

				if blackboard and state.throw then
					leave_climb(blackboard)
				end
			end

			if state.throw then
				update_throw(state, t)
			end
		elseif yanked then
			yank_ally(state, owner_unit, t)
		end

		boost_ally(state, owner_unit, t)
	end
end

-- Whoever holds a beam on a machine that is not the host picks what it is linked to, from what they see, so that what they see is
-- what is linked. They tell the host what they picked, with where the eye is and where it is aimed, because the host holds an
-- enemy where the aim is. They also tell the host when the primary is pressed. The host checks the choice and does what the link
-- does. It tells the owner's game when the link is over on its side, when an ally attacks (the beam costs heat then), and the heat
-- that the link costs.
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

mod:network_register("ut_link_input", function (_, owner_go_id, x, y, z, aim_x, aim_y, aim_z, yanked, has_land, land_x, land_y, land_z)
	local input = remote_input(owner_go_id)

	if input then
		input.origin = Vector3Box(Vector3(x, y, z))
		input.aim = Vector3Box(Vector3(aim_x, aim_y, aim_z))
		-- A yank that arrives is kept until the host has handled it, and the next input does not take it back. The place that a
		-- thrown unit lands in is kept with it, if the owner has worked one out.
		if yanked then
			input.yanked = true
			input.yank_land = has_land and Vector3Box(Vector3(land_x, land_y, land_z)) or nil
		end

		input.received = Application.time_since_launch()
	end
end)

-- What the owner has linked to. A game object id of 0 means nothing.
mod:network_register("ut_link_target", function (_, owner_go_id, target_go_id, kind, hold_distance)
	local input = remote_input(owner_go_id)

	if input then
		input.link_request = {hold_distance = hold_distance, kind = kind, target_go_id = target_go_id}
	end
end)

mod:network_register("ut_link_input_end", function (_, owner_go_id)
	local owner_unit = Managers.player.is_server and Managers.state.unit_storage:unit(owner_go_id)

	if owner_unit then
		remote_inputs[owner_unit] = nil

		end_beam(owner_unit)
	end
end)

-- What the host tells the owner: that the link is over, which applies to the link to that game object if it is still the one the
-- owner has, and that a linked ally is attacking
mod:network_register("ut_link_released", function (_, target_go_id, block_seconds)
	local owner_unit = Managers.player:local_player().player_unit
	local state = owner_unit and states[owner_unit]

	if state and state.target and Unit.alive(state.target) and Managers.state.unit_storage:go_id(state.target) == target_go_id then
		-- A networked prop such as a barrel can be taken from this beam by another player linking it later. This beam does not link
		-- it again until the beam is let go of, or the two beams would take it from each other every frame.
		if state.kind == "object" then
			state.avoid_unit = state.target
		end

		release_target(state)

		-- The owner does not link again at once if the host says it cannot, for example after a monster has pulled the owner to it.
		state.link_block_until = Managers.time:time("game") + block_seconds
	end
end)

mod:network_register("ut_link_ally_attack", function ()
	local owner_unit = Managers.player:local_player().player_unit
	local state = owner_unit and states[owner_unit]

	if state then
		state.ally_attack_t = Managers.time:time("game")
	end
end)

-- The host works out how far a held enemy is behind where it is being moved to, and that bends the beam.
mod:network_register("ut_link_lag", function (_, x, y, z)
	local owner_unit = Managers.player:local_player().player_unit
	local state = owner_unit and states[owner_unit]

	if state then
		state.lag = Vector3Box(Vector3(x, y, z))
	end
end)

-- Runs the beams of the other players on the host. They do what a beam of the host's does, using their inputs.
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

			-- This is where a thrown unit lands, as the owner works it out. It is used when the throw starts.
			state.yank_land = yanked and input.yank_land or nil
			input.yanked = false
			input.yank_land = nil
			input.link_request = nil
			state.callback_world = world

			-- What the owner has linked to: let go of what was linked, and link what they say if it is something that can be linked.
			if request then
				release_target(state)

				state.target_go_id = nil

				local unit = request.target_go_id > 0 and Managers.state.unit_storage:unit(request.target_go_id)

				-- Nothing is linked while a link is blocked, which is what a monster does after pulling the owner to it.
				if unit and Unit.alive(unit) and CONFIG.remote_link_kinds[request.kind] and t >= (state.link_block_until or 0) then
					link_target(state, owner_unit, unit, request.kind, nil, request.hold_distance)

					state.target_go_id = request.target_go_id
				end
			end

			-- The link is over if what is linked is gone or too far
			if state.target and not is_link_valid(state, origin) then
				release_target(state)
			end

			run_link(state, owner_unit, origin, input.aim:unbox(), yanked, dt, t, physics_world)

			-- A link that the host has ended, for any reason, is told to the owner. If linking is blocked, the owner is also told
			-- how long it cannot be made again.
			if not state.target and state.target_go_id then
				mod:network_send("ut_link_released", owner_peer_id, state.target_go_id, math.max((state.link_block_until or 0) - t, 0))

				state.target_go_id = nil
			end

			-- An ally that attacks makes the beam cost heat, which is the owner's
			if state.kind == "ally" and state.ally_attack_t ~= state.noticed_ally_attack_t and t >= (state.next_ally_notice_t or 0) then
				state.noticed_ally_attack_t = state.ally_attack_t
				state.next_ally_notice_t = t + CONFIG.beam_send_interval

				mod:network_send("ut_link_ally_attack", owner_peer_id)
			end

			-- An enemy that is held lags behind the aim, the owner's beam bends by it
			if state.kind == "enemy" and state.lag and t >= (state.next_lag_notice_t or 0) then
				state.next_lag_notice_t = t + CONFIG.beam_send_interval

				local lag = state.lag:unbox()

				mod:network_send("ut_link_lag", owner_peer_id, lag.x, lag.y, lag.z)
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

	-- Yanking is pressing the primary, once for every press. Holding the button is not a press. The button is looked at every
	-- frame, linked or not, so that a press is only one that happens after the button was up.
	local yanked = yank_pressed(state, owner_unit)

	-- Nothing is yanked after an interaction was started for the owner (see interaction_block). A press only counts if this beam
	-- has seen it.
	if (interaction_block[owner_unit] or 0) > t then
		yanked = false
		state.link_block_until = math.max(state.link_block_until or 0, interaction_block[owner_unit])
	end

	if yanked and state.target and not locked_out() and utils.is_local_player_unit(owner_unit) and utils.wielded_template_name(owner_unit) == TEMPLATE_NAME then
		Unit.animation_event(first_person_extension:get_first_person_unit(), CONFIG.yank_animation_event)
		play_yank_sound(owner_unit)
		mod:network_send("ut_link_yank", "others", Managers.state.unit_storage:go_id(owner_unit))
	end

	if Managers.player.is_server then
		select_target(state, owner_unit, origin, aim, t, physics_world)
		run_link(state, owner_unit, origin, aim, yanked, dt, t, physics_world)
	else
		select_target(state, owner_unit, origin, aim, t, physics_world)

		-- An object that is a networked unit is the host's, whatever its kind says. The other objects are this game's own.
		local own_kind = CONFIG.local_link_kinds[state.kind] and not (state.kind == "object" and is_networked_object(state.target))

		-- This game does what the link does itself if the target is one of the kinds that depend on this game. Otherwise the host does it.
		if own_kind then
			run_link(state, owner_unit, origin, aim, yanked, dt, t, physics_world)
		end

		-- The host is told what is linked when it changes, if the host does something for it. The host is also told where the eye
		-- is and where it is aimed. A yank is sent at once, and the rest every beam_send_interval.
		local hosts_target = not own_kind and state.target or nil

		if hosts_target ~= state.sent_target then
			state.sent_target = hosts_target

			local target_go_id = hosts_target and Unit.alive(hosts_target) and Managers.state.unit_storage:go_id(hosts_target) or 0

			mod:network_send("ut_link_target", "others", Managers.state.unit_storage:go_id(owner_unit), target_go_id, hosts_target and state.kind or "", hosts_target and state.hold_distance or 0)
		end

		-- A yank of an enemy throws it to the owner. Where it lands is worked out here, from where the owner is and aims now, and
		-- it is sent with the yank. The host moves the enemy, but what it sees of the owner is a little behind.
		if yanked and state.kind == "enemy" then
			local flat_aim = Vector3.flat(aim)

			if Vector3.length(flat_aim) > 0.1 then
				local land = throw_landing(owner_unit, Vector3.normalize(flat_aim))

				state.yank_land_unsent = land and Vector3Box(land) or nil
			end
		end

		state.yank_unsent = state.yank_unsent or yanked

		if state.yank_unsent or t >= (state.next_input_send or 0) then
			state.next_input_send = t + CONFIG.beam_send_interval
			state.input_sent = true

			local land_box = state.yank_unsent and state.yank_land_unsent
			local land = land_box and land_box:unbox() or Vector3.zero()

			mod:network_send("ut_link_input", "others", Managers.state.unit_storage:go_id(owner_unit), origin.x, origin.y, origin.z, aim.x, aim.y, aim.z, state.yank_unsent, land_box and true or false, land.x, land.y, land.z)

			state.yank_unsent = false
			state.yank_land_unsent = nil
		end
	end

	local linked = state.target ~= nil and Unit.alive(state.target)

	set_drone(owner_unit, linked)

	-- The end of the beam is what it is linked to, or where it hits.
	local end_position

	if not linked then
		local range = CONFIG.beam_range
		local hit, hit_position = PhysicsWorld.immediate_raycast(physics_world, origin, aim, range, "closest", "collision_filter", "filter_player_ray_projectile_static_only")

		end_position = hit and hit_position or origin + aim * range
	end

	-- The beam is drawn when the world has been updated (see draw_pending_beams). The target and the staff have moved by then,
	-- and a beam drawn here would be a frame behind them. The table is kept and filled in again.
	local pending = state.pending_draw

	if not pending then
		pending = {}
		state.pending_draw = pending
	end

	pending.ready = true
	pending.end_position = end_position
	pending.lag = state.kind == "enemy" and state.lag and state.lag:unbox() or nil
	pending.owner_unit = owner_unit
	pending.rotation = rotation
	pending.weight = state.kind == "enemy" and state.weight or nil

	-- The other players are told where the beam ends.
	local send_position = end_position or state.target and Unit.alive(state.target) and target_position(state)

	if send_position and t >= (state.next_beam_send or 0) then
		state.next_beam_send = t + CONFIG.beam_send_interval
		state.beam_sent = true

		-- It is sent with what bends the beam: the aim, and what hangs from it and lags behind, with 0 and nothing for none.
		local lag = pending.lag or Vector3.zero()

		-- For a ragdoll or an object that is held, it is also sent with which one it is (its id), the bone of the body that is held,
		-- where the eye is, and how far in front of the eye the object is held. The other players use these to hold it the same
		-- way on their machines. 0 means none. An object that is a networked unit is not sent, because the host holds that one and
		-- it is not held on each machine.
		local is_object_held = state.kind == "object" and Unit.alive(state.target) and not is_networked_object(state.target)
		local hold_distance = is_object_held and state.hold_distance or 0
		local object_id = is_object_held and object_id_of(state.target) or 0
		local linked_at = is_object_held and state.link_position and state.link_position:unbox() or Vector3.zero()

		mod:network_send("ut_link_beam", "others", Managers.state.unit_storage:go_id(owner_unit), send_position.x, send_position.y, send_position.z, aim.x, aim.y, aim.z, pending.weight or 0, lag.x, lag.y, lag.z, origin.x, origin.y, origin.z, hold_distance, object_id, state.node_index or -1, linked_at.x, linked_at.y, linked_at.z, linked)
	end
end

-- The beams of the other players: where each ends, as it was told, and what is drawn, which follows that end
local remote_beams = {} -- { [the unit of the player] = { end_position, aim, weight, lag, shown, received, drawn_at } }
local remote_points = {} -- the points of a beam

local function remove_remote_beam(owner_unit)
	local beam = remote_beams[owner_unit]

	if beam then
		stop_drone(owner_unit)

		remote_beams[owner_unit] = nil
	end
end

mod:network_register("ut_link_beam", function (_, owner_go_id, x, y, z, aim_x, aim_y, aim_z, weight, lag_x, lag_y, lag_z, origin_x, origin_y, origin_z, hold_distance, object_id, node_index, linked_x, linked_y, linked_z, linked)
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
	beam.aim = Vector3Box(Vector3(aim_x, aim_y, aim_z))
	beam.weight = weight > 0 and weight or nil
	beam.lag = Vector3Box(Vector3(lag_x, lag_y, lag_z))
	beam.origin = Vector3Box(Vector3(origin_x, origin_y, origin_z))
	beam.hold_distance = hold_distance > 0 and hold_distance or nil
	beam.object_id = object_id
	beam.node_index = node_index >= 0 and node_index or nil
	beam.link_position = Vector3Box(Vector3(linked_x, linked_y, linked_z))
	beam.linked = linked
	beam.received = Application.time_since_launch()
end)

-- A ragdoll or an object that is held by another player is held on this machine too, by the same code, from the eye and aim of the
-- holder that are sent. This machine's copy of it is identified by its id, because the ragdolls do not lie in the same places on
-- the machines. The body that is held is the one of the bone that the holder holds. If this copy does not have that bone, it is
-- the body nearest to the chest, because the copies do not have the same parts and a limb can be missing on one and not on
-- another. The copies are not the same, but they are all held at the same place. The holder's own game does what it always did.
local function update_object_mirrors(dt)
	if not next(remote_beams) then
		return
	end

	local now = Application.time_since_launch()
	local physics_world = World.get_data(Managers.world:world("level_world"), "physics_world")

	for beam_owner_unit, beam in pairs(remote_beams) do
		local mirror = beam.mirror

		-- The mirror is dropped when nothing is held, when another object is held, or when the object is gone from this machine.
		if not beam.hold_distance or mirror and (mirror.object_id ~= beam.object_id or not Unit.alive(mirror.target)) then
			mirror = nil
			beam.mirror = nil
		end

		if beam.hold_distance then
			if not mirror then
				local unit = object_unit_of(beam.object_id)

				-- If this machine cannot tell the copy by its id, the copy is the ragdoll or object that is near where the holder
				-- has it. It is looked for every object_search_interval, not every frame.
				if not unit and now >= (beam.next_object_search or 0) then
					beam.next_object_search = now + CONFIG.object_search_interval

					unit = find_object_near(physics_world, beam.link_position:unbox(), CONFIG.object_search_radius)
				end

				if unit and Unit.alive(unit) then
					mirror = {
						corpse = AiUtils.unit_breed(unit) ~= nil,
						kind = "object",
						object_id = beam.object_id,
						since = now,
						target = unit,
						thawed = false,
					}
					beam.mirror = mirror

					if mirror.corpse then
						preserve_corpse(unit)
					end
				end
			end

			if mirror then
				mirror.hold_distance = beam.hold_distance
				-- The body is the one of the bone that the holder holds. If this copy does not have that bone, because a limb is
				-- missing, the body nearest to the chest is used.
				mirror.node_index = beam.node_index

				refresh_object(mirror, true)

				if not mirror.actor then
					mirror.node_index = nil

					refresh_object(mirror, true)
				end

				-- A prop that this machine's own beam or another player's beam holds as well is moved by the one that counts (see
				-- object_hold_counts).
				note_object_holder(mirror.target, beam_owner_unit, now, mirror.since)

				if mirror.corpse or object_hold_counts(mirror.target, beam_owner_unit, now) then
					hold_object(mirror, beam.aim:unbox(), beam.origin:unbox(), dt)
				end
			end
		end
	end
end

-- A networked object that the host holds, such as a barrel, is a copy on the other machines. The copy moves by its own physics and
-- is only put right by the game now and then. So the host tells them its pose while it holds the object and a little after it lets
-- the object go, and they move their copy there smoothly. The copy's own locomotion has a way of being put somewhere, and that is
-- used.
local barrel_poses = {} -- on the others: { [game object id] = { position, rotation, received } }

mod:network_register("ut_link_barrel_pose", function (_, go_id, px, py, pz, qx, qy, qz, qw)
	barrel_poses[go_id] = {
		position = Vector3Box(Vector3(px, py, pz)),
		received = Application.time_since_launch(),
		rotation = QuaternionBox(Quaternion.from_elements(qx, qy, qz, qw)),
	}
end)

local function send_barrel_pose(unit, actor)
	local pose = actor and Actor.pose(actor) or Unit.world_pose(unit, 0)
	local position = Matrix4x4.translation(pose)
	local qx, qy, qz, qw = Quaternion.to_elements(Matrix4x4.rotation(pose))

	mod:network_send("ut_link_barrel_pose", "others", Managers.state.unit_storage:go_id(unit), position.x, position.y, position.z, qx, qy, qz, qw)
end

local function update_barrel_poses(dt)
	local now = Application.time_since_launch()

	if Managers.player.is_server then
		for _, state in pairs(states) do
			if state.kind == "object" and state.target and Unit.alive(state.target) and is_networked_object(state.target) and now >= (state.next_pose_send or 0) then
				state.next_pose_send = now + CONFIG.beam_send_interval

				send_barrel_pose(state.target, held_actor(state))
			end
		end

		for i = #barrel_settling, 1, -1 do
			local entry = barrel_settling[i]

			if not Unit.alive(entry.unit) or now >= entry.stop_at then
				table.remove(barrel_settling, i)
			elseif now >= (entry.next_send or 0) then
				entry.next_send = now + CONFIG.beam_send_interval

				send_barrel_pose(entry.unit, nil)
			end
		end

		return
	end

	local blend = 1 - math.exp(-CONFIG.remote_beam_smoothing * dt)

	for go_id, entry in pairs(barrel_poses) do
		local unit = Managers.state.unit_storage:unit(go_id)
		local locomotion_extension = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "projectile_locomotion_system")

		if not locomotion_extension or not locomotion_extension.teleport or now - entry.received > CONFIG.barrel_settle_time then
			barrel_poses[go_id] = nil
		else
			local pose = Unit.world_pose(unit, 0)
			local position = Matrix4x4.translation(pose)
			local rotation = Matrix4x4.rotation(pose)

			locomotion_extension:teleport(position + (entry.position:unbox() - position) * blend, Quaternion.lerp(rotation, entry.rotation:unbox(), blend))
		end
	end
end

mod:network_register("ut_link_beam_end", function (_, owner_go_id)
	local owner_unit = Managers.state.unit_storage:unit(owner_go_id)

	if owner_unit then
		remove_remote_beam(owner_unit)
	end
end)

-- Returns where another player's beam starts: the muzzle of the mesh in their hand, or else the end node of their staff.
local function remote_staff_end(owner_unit)
	local position = mod.link_beam_callbacks.start_position(owner_unit)

	if position then
		return position
	end

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

	for owner_unit, beam in pairs(remote_beams) do
		local start_position = remote_staff_end(owner_unit)

		if not start_position or now - beam.received > CONFIG.remote_beam_timeout then
			remove_remote_beam(owner_unit)
		else
			set_drone(owner_unit, beam.linked)

			local target = beam.end_position:unbox()
			local shown = beam.shown and beam.shown:unbox() or target
			local shown_aim = beam.shown_aim and beam.shown_aim:unbox() or beam.aim:unbox()
			local shown_lag = beam.shown_lag and beam.shown_lag:unbox() or beam.lag:unbox()
			local blend = 1 - math.exp(-CONFIG.remote_beam_smoothing * (now - (beam.drawn_at or now)))

			-- What is drawn follows what was told: the end, the aim and the lag. They come every beam_send_interval.
			shown = shown + (target - shown) * blend
			shown_aim = shown_aim + (beam.aim:unbox() - shown_aim) * blend
			shown_lag = shown_lag + (beam.lag:unbox() - shown_lag) * blend
			beam.shown = Vector3Box(shown)
			beam.shown_aim = Vector3Box(shown_aim)
			beam.shown_lag = Vector3Box(shown_lag)
			beam.drawn_at = now

			-- The beam is curved the same way the holder's is.
			local count = beam_curve(remote_points, start_position, shown, Vector3.normalize(shown_aim), beam.weight, shown_lag, CONFIG.beam_segment_length)

			beam_sets_off_goop(remote_points, count)
			mod.link_beam_callbacks.draw(beam, remote_points, count)
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
				draw_beam(state, start_position, pending.rotation, end_position, pending.weight, pending.lag)
			end
		end
	end
end

-- The beam ends when the button is let go, or when the weapon is left for something else.
mod.charge_finish_callbacks.link = function (self)
	local action = self.current_action

	if action and action.ut_charge_callback == "link" then
		end_beam(self.owner_unit)
	end
end

-- When the player hangs off a ledge, the staff's stance ends in the character the others see, under the hanging animations.
mod.ledge_hang_callbacks.link = function (unit)
	if utils.wielded_template_name(unit) == TEMPLATE_NAME then
		Managers.state.network:anim_event(unit, "attack_finished")
	end
end

-- When the staff is wielded, its overcharge lockout is read from then on.
mod.wield_callbacks.link = function (self, equipment, slot_data)
	if not slot_data or not has_staff then
		return
	end

	local item_template = BackendUtils.get_item_template(slot_data.item_data)

	if item_template.name == TEMPLATE_NAME then
		wielder_overcharge_extension = ScriptUnit.has_extension(self._unit, "overcharge_system")
	end
end

-- The host runs the beams of the other players from the weapon system's update, where its own beam is run because the actions of
-- the weapons are updated there. It does not run them from the mod's update, which comes before every system of the game, because
-- the order of the systems matters to a throw. The behavior of an enemy is run by the AI system, which comes before the weapons,
-- and it goes on from what it finds when it is updated. The locomotion comes after the weapons and moves the unit by the velocity
-- it was given. A throw that is set up before the AI system is seen by the behavior while the unit has not moved yet, and that
-- lands the unit where it is.
mod:hook_safe(WeaponSystem, "update", function (self, context, t)
	update_remote_inputs(context.dt, t)
end)

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	-- There is no game time outside of a level.
	local t = Managers.time:time("game")

	if t then
		update_object_mirrors(dt)
		update_barrel_poses(dt)

		if Managers.player.is_server then
			update_ally_buffs()
		end
	end

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

	-- The gusts that are still playing are stopped now, because their world is gone after the level.
	for i = #yank_sounds, 1, -1 do
		WwiseWorld.trigger_event(yank_sounds[i].wwise_world, CONFIG.link_sound_stop, yank_sounds[i].source)

		yank_sounds[i] = nil
	end

	table.clear(remote_inputs)
	table.clear(corpse_units)
	table.clear(object_holders)
	table.clear(barrel_settling)
	table.clear(barrel_poses)

	-- There is no player manager when the game is closing, or when the mod is unloaded after that. The buffs are gone with it.
	if Managers.player and Managers.player.is_server then
		clear_ally_buffs()
	end

	restore_corpse()
	wielder_overcharge_extension = nil
	table.clear(bolts)
end

mod.enabled_callbacks[#mod.enabled_callbacks + 1] = apply_link_gun

local function give_back()
	clear_beams()
	restore_staff()
end

mod.disabled_callbacks[#mod.disabled_callbacks + 1] = give_back
mod.unload_callbacks[#mod.unload_callbacks + 1] = give_back

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	clear_beams()
end
