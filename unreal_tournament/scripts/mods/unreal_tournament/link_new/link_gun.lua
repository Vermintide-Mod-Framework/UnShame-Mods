local mod = get_mod("unreal_tournament")

-- Link Gun: UT2004's (XWeapons/LinkGun, LinkAltFire, LinkProjectile and LinkFire), for every hero. Each hero has a copy on a gun of
-- their own, as the Shield Gun has: only the base's animations, models and sounds are kept, and everything else is set here.
--   Left button: plasma bolts, one every 0.2 s while it is held, for 2 ammo each. A bolt speeds up as it flies.
--   Right button: the beam, held. It hurts what it is on every 0.12 s, for 1 ammo each time. On an ally who holds a Link Gun it becomes a
--               link instead: it does no damage and takes no ammo, and it boosts the ally. A link holds for half a second after the
--               aim leaves the ally, and breaks when the ally is too far or too far off the aim.
-- Links: a player who is linked by others has as many links as the players who link them, and each of those counts their own links too
-- (LinkFire.AddLink). Every link makes their bolts do as much again (LinkProjectile: times 1 + links), fly faster, and start further
-- ahead, and their beam do one and a half times as much again (LinkFire: times 1 + 1.5 links) and reach further. The ammo a linked
-- player's gun uses is also taken from the guns of the players who link them (LinkGun.ConsumeAmmo).
-- Who does what: the machine of the player who holds the gun (the host's for a bot) fires, links, and uses the ammo. It tells the others
-- what is linked, and where the beam ends, so that every machine knows everyone's links and can draw the beams. The skin (skin.lua)
-- draws all of it.

local utils = mod.utils
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for
local register_network_lookup = utils.register_network_lookup

local UNIT = utils.UT_UNIT

local DESCRIPTION = "Riordan Dynamic Weapon Systems combines the best of weapon design in the Advanced Plasma Rifle v23, commonly known as the Link Gun. Its secondary mode is a switchable energy matrix: on a teammate it becomes a harmless carrier stream that boosts the output of any targeted player also using the Link."

-- The items, one for each hero, on the base that reaches the most of the hero's careers. hand is the hand that holds the base's weapon,
-- which the actions and the ammo are on.
local VARIANTS = {
	{
		base_item = "es_repeating_handgun",
		deus_copy = "deus_es_repeating_handgun",
		id = "link_new",
		key = "ut_link_new",
		template = "ut_link_new_template",
		hand = "right",
	},
	{
		base_item = "dr_handgun",
		deus_copy = "deus_dr_handgun",
		id = "link_new_dr",
		key = "ut_link_new_dr",
		template = "ut_link_new_dr_template",
		hand = "right",
	},
	{
		base_item = "wh_crossbow",
		deus_copy = "deus_wh_crossbow",
		id = "link_new_wh",
		key = "ut_link_new_wh",
		template = "ut_link_new_wh_template",
		hand = "left",
	},
	-- Sienna's staffs have no ammo. This copy has the Link Gun's. The local item list shows only her own staff to the Necromancer, so she
	-- is named here, as the Shock Rifle does.
	{
		base_item = "bw_skullstaff_beam",
		deus_copy = "deus_bw_skullstaff_beam",
		id = "link_new_bw",
		key = "ut_link_new_bw",
		template = "ut_link_new_bw_template",
		hand = "right",
		can_wield = { "bw_scholar", "bw_adept", "bw_unchained", "bw_necromancer" },
	},
	-- The Deepwood Staff's item lists only the Sister of the Thorn, but all four of Kerillian's careers share one third person body, which
	-- has the staff's animations, so this copy lists all four (as the Lightning Gun's does). It has the Link Gun's ammo.
	{
		base_item = "we_life_staff",
		deus_copy = "deus_we_life_staff",
		id = "link_new_we",
		key = "ut_link_new_we",
		template = "ut_link_new_we_template",
		hand = "left",
		can_wield = { "we_shade", "we_maidenguard", "we_waywatcher", "we_thornsister" },
	},
}

-- Each template's variant, and the items' keys
local VARIANT_OF = {}
local ITEM_KEYS = {}

for _, variant in ipairs(VARIANTS) do
	mod.items.register(variant.id, {
		key = variant.key,
		template = variant.template,
		base_item = variant.base_item,
		deus_copy = variant.deus_copy,
		can_wield = variant.can_wield,
		name = "UT2004 Link Gun",
		type_name = "Link Gun",
		description = DESCRIPTION,
		keywords = { "weapon_keyword_rapid_fire", "weapon_keyword_versatile", "weapon_keyword_crowd_control" },
		icon = "ut_link_gun_icon",
		icon_package = "resource_packages/unreal_tournament/icons",
		icon_materials = "ui/ut/link_gun_icon",
		-- The illusions are UT2004's model and UT2003's old model, which UT2004 still has as an option (LinkGun.OldMesh)
		skins = {
			{
				key = variant.key .. "_skin_2004",
				name = "UT2004 Link Gun",
				default = true,
			},
			{
				key = variant.key .. "_skin_2003",
				name = "UT2003 Link Gun",
				icon = "ut_link_gun_2003_icon",
				icon_materials = "ui/ut/link_gun_2003_icon",
			},
		},
	})

	VARIANT_OF[variant.template] = variant
	ITEM_KEYS[variant.key] = true
end

local CONFIG = {
	-- LinkAmmo.MaxAmmo. All of the ammo is the clip, so there is no reload.
	max_ammo = 220,
	-- LinkAltFire: FireRate, AmmoPerFire, and ProjSpawnOffset (forward, right and down from the eye, in UT units)
	bolt_rate = 0.2, -- s
	bolt_ammo = 2,
	bolt_start = { 25, 8, 3 },
	-- LinkAltFire.SpawnProjectile: each link starts the bolt this much further ahead (UT units)
	bolt_start_per_link = 10,
	-- LinkProjectile: Damage, Speed, the acceleration along its way (PostNetBeginPlay), MaxSpeed and the speed each link adds to it
	-- (LinkAdjust), and LifeSpan. The speeds are UT units a second, turned into meters by the size of a UT unit.
	bolt_damage = 30,
	bolt_speed = 1000,
	bolt_acceleration = 3000,
	bolt_max_speed = 4000,
	bolt_max_speed_per_link = 350,
	bolt_life = 3, -- s
	-- LinkFire: a hit every FireRate for AmmoPerFire, Damage, TraceRange and the range each link adds to it, and how much further a link
	-- reaches. A link breaks LinkBreakDelay after the aim has left the ally, or when the ally is more than the reach away, or the way to
	-- them is further off the aim than LinkFlexibility (the cosine of the angle).
	beam_rate = 0.12, -- s
	beam_ammo = 1,
	beam_damage = 9,
	beam_range = 1100, -- UT units
	beam_range_per_link = 250,
	linked_range_scale = 1.5,
	link_break_delay = 0.5, -- s
	link_flexibility = 0.64,
	-- LinkFire.LinkScale stops at 5 links, and so do the damage profiles here
	max_links = 5,
	-- How near the beam has to pass an ally to be on them: UT's collision cylinder of a player (xPawn.CollisionRadius and twice its
	-- CollisionHeight), in UT units. A linked beam ends at an ally's middle (LockedPawn.Location, and half the eye height).
	pawn_radius = 25,
	pawn_height = 88,
	linked_end_height = 55,
	-- The multipliers of the damage and the stagger for each armor type: unarmored, armored, monsters, players, berserkers and super armor.
	-- UT has no armor. The bolts are plasma, as hard on armor as the Shock Rifle's beam, and the beam's many small hits are poor against
	-- it, as the Minigun's rounds are (a choice, to be set in the game).
	bolt_armor_attack = { 1, 0.8, 1.5, 1, 1, 0.5 },
	bolt_armor_impact = { 1, 0.8, 1, 1, 1, 0.5 },
	beam_armor_attack = { 1, 0.5, 1, 1, 1, 0.3 },
	beam_armor_impact = { 1, 1, 1, 1, 1, 0.5 },
	-- How far a bot shoots its bolts from, in meters
	bot_max_range = 30,
	-- A held button repeats the shot. The shot lasts this much longer than the time to the next one, because a held button is only read
	-- while a shot is still running.
	chain_margin = 0.05, -- s
	-- How often the player who holds the beam tells the others where it ends
	beam_send_interval = 0.05, -- s
}

-- The bolts and the beam have no hit effect of their own. Without one the game would play the sound, particles and decals of the surface
-- that is hit, and with none at all it stops on a hit on the level. The skin draws UT's (see mod.silent_hit_effects in hooks.lua).
local NO_HIT_EFFECT = "ut_link_new_impact"

mod.silent_hit_effects[NO_HIT_EFFECT] = true

-- The projectile unit of the bolts: the Drakefire Pistols' shot, which has no gravity of its own. The skin draws UT's bolt at it.
local PROJECTILE_UNIT_TEMPLATES = { "drake_pistol_shot" }
local BOLT_GRAVITY_SETTINGS = "drake_pistols"

-- The bolts are actions that are not started, only spawned: one for each number of links, whose damage profile is that many times
-- stronger
local BOLT_ACTION_NAME = "action_one"
local BOLT_ACTIONS = {}

for links = 0, CONFIG.max_links do
	BOLT_ACTIONS[links] = "ut_link_new_bolt_" .. links

	register_network_lookup("sub_actions", BOLT_ACTIONS[links])
end

-- Damage

-- A bolt or a hit of the beam stops at the first enemy, as UT's do. A hit on the head has the game's usual bonus, as the game's guns and
-- staffs do, where UT gives one only to its sniper weapons.
local BOLT = {
	charge_value = "projectile",
	shield_break = false,
	no_stagger_damage_reduction_ranged = true,
	is_explosion = false,
	-- (the Shock Rifle's ball's hit reactions and effects)
	attack_template = "fireball",
	damage_type = "grenade",
	attack_power = attack_power_for(CONFIG.bolt_damage),
	impact_power = impact_power_for(CONFIG.bolt_damage),
	armor_attack = CONFIG.bolt_armor_attack,
	armor_impact = CONFIG.bolt_armor_impact,
	critical_armor_attack = CONFIG.bolt_armor_attack,
	critical_armor_impact = CONFIG.bolt_armor_impact,
	cleave_attack = 0.01,
	cleave_impact = 0.01,
	boost_curve_type = "linesman_curve",
	boost_curve_coefficient = 0.75,
	boost_curve_coefficient_headshot = 1,
	headshot_boost = 0.5,
	headshot_boost_boss = 0.25,
	headshot_boost_armor = 0.5,
	headshot_boost_heavy_armor = 0.25,
	no_headshot_boost = false,
	crit_boost = 0.5,
	no_crit_boost = false,
	stagger_duration_modifier = 1,
	stagger_distance_modifier = 1,
}

local BEAM = utils.damage_profile_spec(BOLT, {
	charge_value = "instant_projectile",
	-- (the Beam Staff's beam's hit reactions, and the repeater's hit effects)
	attack_template = "wizard_staff_beam",
	damage_type = "shot_repeating_handgun",
	attack_power = attack_power_for(CONFIG.beam_damage),
	impact_power = impact_power_for(CONFIG.beam_damage),
	armor_attack = CONFIG.beam_armor_attack,
	armor_impact = CONFIG.beam_armor_impact,
	critical_armor_attack = CONFIG.beam_armor_attack,
	critical_armor_impact = CONFIG.beam_armor_impact,
})

local function bolt_profile(links)
	return "ut_link_new_bolt_" .. links
end

local function beam_profile(links)
	return "ut_link_new_beam_" .. links
end

for links = 0, CONFIG.max_links do
	local bolt_scale = 1 + links
	local beam_scale = 1 + 1.5 * links

	utils.add_damage_profile(bolt_profile(links), utils.damage_profile_spec(BOLT, {
		attack_power = BOLT.attack_power * bolt_scale,
		impact_power = BOLT.impact_power * bolt_scale,
	}))
	utils.add_damage_profile(beam_profile(links), utils.damage_profile_spec(BEAM, {
		attack_power = BEAM.attack_power * beam_scale,
		impact_power = BEAM.impact_power * beam_scale,
	}))
end

-- The state of the links and the beams, which the skin reads. Every machine keeps it for every character, from what the machine that owns
-- each beam says.
--   locked[unit] = the ally that unit's beam links
--   beams[unit] = { end_position, aim (boxes: where it ends, and the way the character aims), hit (0: nothing, 1: the level or a thing,
--   2: an enemy it hurts), received } while that unit's beam is held
local link = {
	locked = {},
	beams = {},
	templates = {},
}

mod.link_new = link

for template_name in pairs(VARIANT_OF) do
	link.templates[template_name] = true
end

local locked = link.locked
local beams = link.beams

-- Whether a character holds one of the Link Guns
function link.holds_link(unit)
	return link.templates[utils.wielded_template_name(unit)] == true
end

-- How many links a character has: one for each ally whose beam links them, and as many more as that ally has (LinkGun.Links)
function link.links_of(unit, depth)
	depth = depth or 0

	if depth > 8 then
		return 0
	end

	local total = 0

	for linker, target in pairs(locked) do
		if target == unit and linker ~= unit then
			total = total + 1 + link.links_of(linker, depth + 1)
		end
	end

	return math.min(total, CONFIG.max_links)
end

-- Whether this machine runs a character's weapon: the player's own character, and the bots on the host
local function owns(unit)
	if utils.is_local_player_unit(unit) then
		return true
	end

	local owner = Managers.player:owner(unit)

	return owner ~= nil and owner.bot_player and Managers.player.is_server or false
end

local function go_id(unit)
	return unit and Unit.alive(unit) and Managers.state.unit_storage:go_id(unit) or 0
end

local function unit_of(id)
	return id ~= 0 and Managers.state.unit_storage:unit(id) or nil
end

-- The ammo extension of a character's Link Gun, if it holds one
local function ammo_extension_of(unit)
	if not Unit.alive(unit) or not link.holds_link(unit) then
		return nil
	end

	local slot_data = ScriptUnit.extension(unit, "inventory_system"):get_slot_data("slot_ranged")

	return slot_data and GearUtils.get_ammo_extension(slot_data.right_unit_1p, slot_data.left_unit_1p)
end

-- Links

-- Sets what a character's beam links, on this machine, and tells the others if this machine runs that character's weapon
local function set_lock(unit, target)
	if locked[unit] == target then
		return
	end

	locked[unit] = target

	for _, callback in pairs(link.lock_callbacks) do
		callback(unit, target)
	end

	if owns(unit) then
		mod:network_send("ut_link_new_lock", "others", go_id(unit), go_id(target))
	end
end

-- What the skin is told when a link is made or broken: link.lock_callbacks[name] = function (unit, target)
link.lock_callbacks = {}

mod:network_register("ut_link_new_lock", function (_, unit_id, target_id)
	local unit = unit_of(unit_id)

	if unit then
		set_lock(unit, unit_of(target_id))
	end
end)

-- Whether a character's beam can link an ally: a player or a bot who is alive and holds a Link Gun, and who doesn't link back to the
-- character through others (LinkFire.IsLinkable)
local function linkable(unit, target)
	if target == unit or not HEALTH_ALIVE[target] or not link.holds_link(target) then
		return false
	end

	local player = Managers.player:owner(target)

	if not player or Managers.state.side.side_by_unit[target] ~= Managers.state.side.side_by_unit[unit] then
		return false
	end

	local next_unit = locked[target]
	local steps = 0

	while next_unit and steps < 32 do
		if next_unit == unit then
			return false
		end

		next_unit = locked[next_unit]
		steps = steps + 1
	end

	return true
end

-- Ammo

-- Uses a character's ammo, and the same from the guns of the allies who link the character, whose machines are told
-- (LinkGun.ConsumeAmmo and LinkedConsumeAmmo)
local function use_ammo(unit, ammo_extension, amount)
	ammo_extension:use_ammo(amount)

	if link.links_of(unit) > 0 then
		mod:network_send("ut_link_new_drain", "all", go_id(unit), amount)
	end
end

-- Whether a character is in the chain of links that ends at head
local function links_into(unit, head)
	local next_unit = locked[unit]
	local steps = 0

	while next_unit and steps < 32 do
		if next_unit == head then
			return true
		end

		next_unit = locked[next_unit]
		steps = steps + 1
	end

	return false
end

mod:network_register("ut_link_new_drain", function (_, head_id, amount)
	local head = unit_of(head_id)

	if not head then
		return
	end

	for linker in pairs(locked) do
		if owns(linker) and links_into(linker, head) then
			local ammo_extension = ammo_extension_of(linker)

			if ammo_extension and ammo_extension:total_remaining_ammo() > 0 then
				ammo_extension:use_ammo(math.min(amount, ammo_extension:total_remaining_ammo()))
			end
		end
	end
end)

-- Weapon template

-- What a bolt or the beam can chain into. Both buttons can be held, and the other mode starts once this one's time is over, as UT's fire
-- modes take turns.
local function chain_actions(interval)
	return {
		{
			action = "action_wield",
			input = "action_wield",
			start_time = 0,
			sub_action = "default",
		},
		{
			action = "action_one",
			input = "action_one_hold",
			start_time = interval,
			sub_action = "default",
		},
		{
			action = "action_two",
			input = "action_two_hold",
			start_time = interval,
			sub_action = "default",
		},
	}
end

-- A bolt, the game's handgun shot (kind "handgun") that fires a projectile, with every field given. It repeats while its button is held.
-- shot_anims is the base weapon's action whose animations a bolt plays.
local function build_bolt_shot(hand, shot_anims)
	local projectile_info = table.clone(Projectiles.brace_of_drake_pistols_shot)

	projectile_info.gravity_settings = BOLT_GRAVITY_SETTINGS

	return {
		kind = "handgun",
		weapon_action_hand = hand,
		anim_event = shot_anims.anim_event,
		anim_event_last_ammo = shot_anims.anim_event_last_ammo or shot_anims.anim_event,
		fire_time = 0,
		total_time = CONFIG.bolt_rate + CONFIG.chain_margin,
		allowed_chain_actions = chain_actions(CONFIG.bolt_rate),
		hold_input = "action_one_hold",
		-- Letting go of the button ends the shot, and a press starts the next from idle: the cooldown keeps that to the fire rate too
		cooldown = CONFIG.bolt_rate,
		cooldown_from_start = true,
		uninterruptible = true,
		enter_function = function (attacker_unit, input_extension)
			input_extension:clear_input_buffer()
		end,
		ammo_usage = CONFIG.bolt_ammo,
		reload_when_out_of_ammo = false,
		reload_time = 0.5,
		apply_recoil = false,
		charge_value = "projectile",
		additional_critical_strike_chance = 0,
		critical_strike = {},
		-- The projectile it spawns. The spawn is changed for the links (see spawn_projectile_callbacks below).
		projectile_info = projectile_info,
		speed = CONFIG.bolt_speed * UNIT * 100,
		damage_window_start = 0.1,
		damage_window_end = 0,
		alert_sound_range_fire = 10,
		alert_sound_range_hit = 2,
		aim_assist_auto_hit_chance = 0,
		aim_assist_max_ramp_multiplier = 0.3,
		aim_assist_ramp_decay_delay = 0.2,
		aim_assist_ramp_multiplier = 0.1,
		ut_link_new_shot = true,
		-- The base's own tracer is not drawn (hooks.lua): the skin draws UT's bolt
		ut_dropped_flow_events = {
			lua_bullet_trail = true,
			lua_bullet_trail_set = true,
		},
	}
end

-- The bolt itself, for a number of links (LinkProjectile). It hits an enemy as a rocket does (utils.UT_PROJECTILE_RADIUS) and a wall by
-- a ray, as UT's bolt is a point. It has no hit effect of the game's: the skin draws UT's.
local function build_bolt_projectile(links)
	local projectile_info = table.clone(Projectiles.brace_of_drake_pistols_shot)

	projectile_info.gravity_settings = BOLT_GRAVITY_SETTINGS
	projectile_info.radius = utils.UT_PROJECTILE_RADIUS
	projectile_info.static_impact_type = "raycast"
	projectile_info.life_time = CONFIG.bolt_life
	projectile_info.unit_life_time = CONFIG.bolt_life

	return {
		kind = "charged_projectile",
		hit_effect = NO_HIT_EFFECT,
		projectile_info = projectile_info,
		impact_data = {
			damage_profile = bolt_profile(links),
		},
		ut_init_callback = "link_new_bolt",
		ut_skin_init_callback = "link_new_bolt",
		ut_init_flow_event_filter = "link_new",
		-- A shield reflects it, as UT's does (see mod.shield.reflect)
		ut_reflective = true,
		ut_link_new_bolt = true,
		ut_link_new_links = links,
	}
end

-- The beam, a charge that is held. What it does is in the charge callbacks below. It needs ammo to start.
local function build_beam(hand)
	return {
		kind = "charge",
		weapon_action_hand = hand,
		charge_time = 1000, -- the charge is never "full"
		hold_input = "action_two_hold",
		minimum_hold_time = 0,
		total_time = math.huge,
		-- Only a weapon switch follows it. Letting go of the button ends it. (A chain into itself would start it again every frame while
		-- the button is held, each time with a hit and an ammo.)
		allowed_chain_actions = {
			{
				action = "action_wield",
				input = "action_wield",
				start_time = 0,
				sub_action = "default",
			},
		},
		condition_func = function (unit, input_extension, ammo_extension)
			return not ammo_extension or ammo_extension:total_remaining_ammo() >= CONFIG.beam_ammo
		end,
		enter_function = function (attacker_unit, input_extension)
			input_extension:clear_input_buffer()

			return input_extension:reset_release_input()
		end,
		zoom_condition_function = function ()
			return false
		end,
		-- (what DamageUtils.process_projectile_hit reads of the action: the damage profile is given with each hit, for the links)
		damage_profile = beam_profile(0),
		hit_effect = NO_HIT_EFFECT,
		additional_critical_strike_chance = 0,
		critical_strike = {},
		ut_charge_callback = "link_new_beam",
		ut_link_new_beam = true,
	}
end

-- Makes the gun on the shell of its base (utils.template_shell): everything that is not the base's animations, models and sounds is set
-- here
local function apply_link_gun(template)
	local base = utils.template_shell(template)
	local variant = VARIANT_OF[template.name]
	local hand = variant.hand

	-- The chart of the item's stats, from 0 to 7. The bolts are the light attack, and the beam is the heavy one.
	template.weapon_diagram = {
		light_attack = {
			[DamageTypes.ARMOR_PIERCING] = 4,
			[DamageTypes.CLEAVE] = 1,
			[DamageTypes.SPEED] = 5,
			[DamageTypes.STAGGER] = 2,
			[DamageTypes.DAMAGE] = 4,
		},
		heavy_attack = {
			[DamageTypes.ARMOR_PIERCING] = 2,
			[DamageTypes.CLEAVE] = 1,
			[DamageTypes.SPEED] = 7,
			[DamageTypes.STAGGER] = 1,
			[DamageTypes.DAMAGE] = 3,
		},
	}

	local actions = template.actions

	actions.action_one = {
		default = build_bolt_shot(hand, base.actions.action_one.default),
	}

	for links = 0, CONFIG.max_links do
		actions[BOLT_ACTION_NAME][BOLT_ACTIONS[links]] = build_bolt_projectile(links)
	end

	actions.action_two = {
		default = build_beam(hand),
	}
	-- The game's own wielding and reload, which every gun of the game has (the reload only comes with picked up ammo, see ammo_data).
	-- Inspecting is the base's, kept by the shell.
	actions.action_wield = table.clone(ActionTemplates.wield)
	actions.weapon_reload = table.clone(ActionTemplates.reload)

	utils.set_actions_lookup_data(actions, template.name)

	-- All the ammo is the clip, and picked up ammo is added to it, so there is no reload between shots
	template.ammo_data = {
		ammo_hand = hand,
		max_ammo = CONFIG.max_ammo,
		ammo_per_clip = CONFIG.max_ammo,
		ammo_per_reload = CONFIG.max_ammo,
		ammo_immediately_available = true,
		reload_time = 0.2,
		reload_on_ammo_pickup = true,
		play_reload_anim_on_wield_reload = false,
	}

	-- How bots use it: they hold the left button and fire the bolts, at the body, against specials, berserkers and armored enemies
	local effective_against = bit.bor(BreedCategory.Infantry, BreedCategory.Berserker, BreedCategory.Special, BreedCategory.Armored)

	template.attack_meta_data = {
		aim_at_node = "j_spine1",
		can_charge_shot = false,
		effective_against = effective_against,
		effective_against_charged = 0,
		effective_against_combined = effective_against,
		fire_input = "fire_hold",
		hold_fire_condition = function (t, blackboard)
			local shoot_blackboard = blackboard and blackboard.shoot

			return shoot_blackboard ~= nil and not shoot_blackboard.obstructed
		end,
		ignore_enemies_for_obstruction = false,
		max_range = CONFIG.bot_max_range,
	}

	-- What the game's talents, traits and properties take it for, and dodging, the crosshair and the aim assist: the base's
	template.buff_type = "RANGED"
	template.weapon_type = base.weapon_type
	template.dodge_count = base.dodge_count
	template.buffs = base.buffs and table.clone(base.buffs)
	template.crosshair_style = "default"
	template.default_spread_template = base.default_spread_template
	template.aim_assist_settings = base.aim_assist_settings and table.clone(base.aim_assist_settings)

	-- The tooltip's light attack is the bolts, and its heavy attack the beam
	template.tooltip_compare = {
		light = {
			action_name = "action_one",
			sub_action_name = "default",
		},
		heavy = {
			action_name = "action_two",
			sub_action_name = "default",
		},
	}
	template.tooltip_detail = template.tooltip_compare

	template.required_projectile_unit_templates = template.required_projectile_unit_templates or {}

	for _, name in ipairs(PROJECTILE_UNIT_TEMPLATES) do
		template.required_projectile_unit_templates[name] = false
	end
end

for template_name in pairs(VARIANT_OF) do
	mod.items.set_template_changes(template_name, apply_link_gun)
end

-- The mod holds its own references to the projectile units while the weapon is enabled
local packages = utils.package_holder("unreal_tournament_link_new")

mod.enabled_callbacks[#mod.enabled_callbacks + 1] = function ()
	packages.load_projectile_units(PROJECTILE_UNIT_TEMPLATES)
end

-- The bolts

-- A bolt has no spread (LinkAltFire's Spread is 0). Its links are taken as it is fired, and the ammo of the allies who link the player is
-- used with it.
mod.handgun_start_callbacks.link_new = function (self, new_action)
	if not new_action.ut_link_new_shot then
		return
	end

	utils.set_handgun_spread(self, 0)

	local owner_unit = self.owner_unit

	if link.links_of(owner_unit) > 0 and owns(owner_unit) then
		mod:network_send("ut_link_new_drain", "all", go_id(owner_unit), CONFIG.bolt_ammo)
	end
end

-- The game spawns the bolt at the eye, as the action's projectile. It is moved to UT's ProjSpawnOffset, and further ahead for each link,
-- and spawned as the bolt for the player's links. A bolt that a shield reflects is spawned again from its own action, and kept as it is.
for template_name in pairs(VARIANT_OF) do
	mod.spawn_projectile_callbacks[template_name] = function (func, owner_unit, position, rotation, scale, angle, target_vector, speed, item_name, item_template_name, action_name, sub_action_name, ...)
		if action_name ~= "action_one" or sub_action_name ~= "default" then
			return func(owner_unit, position, rotation, scale, angle, target_vector, speed, item_name, item_template_name, action_name, sub_action_name, ...)
		end

		local links = link.links_of(owner_unit)
		local start = CONFIG.bolt_start
		local start_position = utils.projectile_start(position, rotation, (start[1] + CONFIG.bolt_start_per_link * links) * UNIT, start[2] * UNIT, start[3] * UNIT)

		return func(owner_unit, start_position, rotation, scale, angle, target_vector, speed, item_name, item_template_name, BOLT_ACTION_NAME, BOLT_ACTIONS[links], ...)
	end
end

-- The bolts speed up as they fly, like UT's LinkProjectile. The path of a projectile is its starting point plus its direction times its
-- speed times the time it has flown. So when the speed changes, the starting point is changed together with it by the amount that keeps
-- the bolt where it is. Every machine does this for the bolts it has. A bolt also sets off the Bio Rifle's goop it flies through.
local bolts = {}
local last_bolt_positions = setmetatable({}, {
	__mode = "k",
})

mod.init_callbacks.link_new_bolt = function (extension)
	local links = extension._current_action and extension._current_action.ut_link_new_links or 0

	bolts[#bolts + 1] = {
		unit = extension._projectile_unit,
		max_speed = (CONFIG.bolt_max_speed + CONFIG.bolt_max_speed_per_link * links) * UNIT,
	}
end

local function update_bolts()
	for i = #bolts, 1, -1 do
		local bolt = bolts[i]
		local unit = bolt.unit
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
			local speed = math.min(CONFIG.bolt_speed * UNIT + CONFIG.bolt_acceleration * UNIT * time_lived, bolt.max_speed) * 100
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

-- The beam

-- The state of each beam that this machine runs: { action, next_hit (s), break_time (s), sent (when the end was last sent) }
local runs = {}

-- How far a character's beam reaches, in meters
local function beam_range(unit)
	return (CONFIG.beam_range + CONFIG.beam_range_per_link * link.links_of(unit)) * UNIT * (locked[unit] and CONFIG.linked_range_scale or 1)
end

-- Where a linked beam ends on an ally
local function linked_end(target)
	return Unit.world_position(target, 0) + Vector3(0, 0, CONFIG.linked_end_height * UNIT)
end

-- Returns the ally that the beam from origin along direction is on, and how far along, if it is nearer than before (UT's trace hits a
-- player's collision cylinder). Only a linkable ally that is seen counts.
local function ally_on_beam(unit, origin, direction, before, physics_world)
	local best, best_distance

	for _, player in pairs(Managers.player:human_and_bot_players()) do
		local ally = player.player_unit

		if ally and Unit.alive(ally) and linkable(unit, ally) then
			local feet = Unit.world_position(ally, 0)
			local flat_direction = Vector3.flat(direction)
			local flat_length = Vector3.length(flat_direction)

			if flat_length > 0.001 then
				local along = Vector3.dot(Vector3.flat(feet - origin), flat_direction) / (flat_length * flat_length)

				if along > 0 and along < before and (not best_distance or along < best_distance) then
					local point = origin + direction * along
					local height = Vector3.z(point) - Vector3.z(feet)

					if Vector3.length(Vector3.flat(point - feet)) <= CONFIG.pawn_radius * UNIT and height >= 0 and height <= CONFIG.pawn_height * UNIT then
						local hit = PhysicsWorld.immediate_raycast(physics_world, origin, direction, along, "closest", "collision_filter", "filter_player_ray_projectile_static_only")

						if not hit then
							best, best_distance = ally, along
						end
					end
				end
			end
		end
	end

	return best, best_distance
end

-- The hits of a ray from origin along direction, nearer than range: the game's hitscan shot's (ActionHandgun)
local function beam_hits(physics_world, origin, direction, range)
	local hits = PhysicsWorld.immediate_raycast_actors(physics_world, origin, direction, "static_collision_filter", "filter_player_ray_projectile_static_only", "dynamic_collision_filter", "filter_player_ray_projectile_ai_only", "dynamic_collision_filter", "filter_player_ray_projectile_hitbox_only")
	local near = {}

	for _, hit in ipairs(hits or {}) do
		if hit[2] <= range then
			near[#near + 1] = hit
		end
	end

	return near
end

-- Tells the other machines where the beam ends, the aim and what it hits, or that it has stopped (beam nil)
local function send_beam(unit, beam)
	local id = go_id(unit)

	if beam then
		local finish, aim = beam.end_position:unbox(), beam.aim:unbox()

		mod:network_send("ut_link_new_beam", "others", id, 1, Vector3.x(finish), Vector3.y(finish), Vector3.z(finish), Vector3.x(aim), Vector3.y(aim), Vector3.z(aim), beam.hit)
	else
		mod:network_send("ut_link_new_beam", "others", id, 0, 0, 0, 0, 0, 0, 0, 0)
	end
end

local function new_beam(received)
	return {
		end_position = Vector3Box(),
		aim = Vector3Box(Vector3.forward()),
		hit = 0,
		received = received,
	}
end

mod:network_register("ut_link_new_beam", function (_, unit_id, on, x, y, z, aim_x, aim_y, aim_z, hit)
	local unit = unit_of(unit_id)

	if not unit then
		return
	end

	if on == 1 then
		local beam = beams[unit] or new_beam(true)

		beam.end_position:store(Vector3(x, y, z))
		beam.aim:store(Vector3(aim_x, aim_y, aim_z))
		beam.hit = hit
		beams[unit] = beam
	else
		beams[unit] = nil
	end
end)

local function stop_beam(unit)
	runs[unit] = nil

	if beams[unit] then
		beams[unit] = nil

		send_beam(unit, nil)
	end

	set_lock(unit, nil)
end

mod.charge_start_callbacks.link_new = function (action, new_action)
	if not new_action.ut_link_new_beam then
		return
	end

	runs[action.owner_unit] = {
		action = action,
		next_hit = 0,
		break_time = 0,
		sent = -math.huge,
	}
end

mod.charge_finish_callbacks.link_new = function (action)
	local run = runs[action.owner_unit]

	if run and run.action == action then
		stop_beam(action.owner_unit)
	end
end

-- Every frame of the beam (LinkFire.ModeTick): it links an ally the aim is on, keeps or breaks the link, and every beam_rate it hurts what
-- it is on, unless it links someone
mod.charge_update_callbacks.link_new_beam = function (action, dt, t, world)
	local unit = action.owner_unit
	local run = runs[unit]

	if not run or run.action ~= action then
		return
	end

	local ammo_extension = ammo_extension_of(unit)

	-- With no ammo the beam stops (LinkFire.myHasAmmo), until the button is pressed again
	if run.stopped then
		return
	end

	if not ammo_extension or ammo_extension:total_remaining_ammo() < CONFIG.beam_ammo then
		run.stopped = true

		if beams[unit] then
			beams[unit] = nil

			send_beam(unit, nil)
		end

		set_lock(unit, nil)

		return
	end

	local physics_world = World.get_data(world, "physics_world")
	local first_person_extension = ScriptUnit.extension(unit, "first_person_system")
	local origin, rotation = first_person_extension:get_projectile_start_position_rotation()
	local direction = Quaternion.forward(rotation)
	local target = locked[unit]

	-- A link breaks when the ally is no longer linkable, too far off the aim, or too far away
	if target then
		local to_target = linked_end(target) - origin

		if not linkable(unit, target) or Vector3.dot(Vector3.normalize(to_target), direction) < CONFIG.link_flexibility or Vector3.length(to_target) > beam_range(unit) then
			set_lock(unit, nil)

			target = nil
		end
	end

	local range = beam_range(unit)
	local hits = beam_hits(physics_world, origin, direction, range)
	local first = utils.first_beam_hit(hits, unit)
	local first_distance = first and first[2] or range
	local ally = ally_on_beam(unit, origin, direction, first_distance, physics_world)

	if ally then
		set_lock(unit, ally)

		target = ally
		run.break_time = CONFIG.link_break_delay
	elseif target then
		run.break_time = run.break_time - dt

		if run.break_time <= 0 then
			set_lock(unit, nil)

			target = nil
		end
	end

	local end_position = target and linked_end(target) or first and first[1] or origin + direction * range

	-- What the beam hits, for how it is drawn: an enemy it hurts (LinkBeamEffect.bLockedOn), the level or a thing (bHitSomething), or
	-- nothing. (This is before the damage: an enemy the damage kills loses its actor.)
	local hit = 0

	if first and not target then
		local hit_unit = Actor.unit(first[4])

		hit = Unit.get_data(hit_unit, "breed") and HEALTH_ALIVE[hit_unit] and 2 or 1
	end

	-- Damage is done at the fire rate (LinkFire.DoFireEffect). A link does none, and takes no ammo (LinkGun.ConsumeAmmo).
	run.next_hit = run.next_hit - dt

	if run.next_hit <= 0 then
		run.next_hit = run.next_hit + CONFIG.beam_rate

		if not target then
			use_ammo(unit, ammo_extension, CONFIG.beam_ammo)

			if #hits > 0 then
				local is_critical_strike = ActionUtils.is_critical_strike(unit, action.current_action, t)
				local power_level = ScriptUnit.extension(unit, "career_system"):get_career_power_level()

				DamageUtils.process_projectile_hit(world, action.item_name, unit, action.is_server, hits, action.current_action, direction, true, nil, nil, is_critical_strike, power_level, beam_profile(link.links_of(unit)))
			end
		end
	end

	local beam = beams[unit] or new_beam(false)

	beam.end_position:store(end_position)
	beam.aim:store(direction)
	beam.hit = hit
	beams[unit] = beam

	if t - run.sent >= CONFIG.beam_send_interval then
		run.sent = t

		send_beam(unit, beam)
	end
end

-- Every frame: the bolts, and the links and beams of characters that are gone or no longer hold a Link Gun
mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	update_bolts()

	for unit in pairs(locked) do
		if not Unit.alive(unit) or not link.holds_link(unit) then
			locked[unit] = nil
		end
	end

	for unit in pairs(beams) do
		if not Unit.alive(unit) or not link.holds_link(unit) then
			beams[unit] = nil
			runs[unit] = nil
		end
	end
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(bolts)
	table.clear(runs)
	table.clear(locked)
	table.clear(beams)
end

link.config = CONFIG
link.item_keys = ITEM_KEYS
