local mod = get_mod("unreal_tournament")

-- Sniper Rifle: UT2004's classic one (UTClassic.ClassicSniperRifle, ClassicSniperFire and XWeapons.SniperZoom), made on the shell of a
-- handgun: only the handgun's animations, models and sounds are kept, and everything else is set here.
--   Left button: a bullet that hits at once (the game's own handgun shot). A hit on the head does double damage.
--   Right button: zooms, as the Lightning Gun does (zoom.lua).
-- All of the ammo is in the gun, so there is no reload. Kruber's handgun and Bardin's are separate templates, so the weapon is two items
-- of the mod that share everything but the base. The skin (skin.lua) draws all of it, and this file only sets what it does to the game.

local utils = mod.utils
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for
local first_beam_hit = utils.first_beam_hit

local DESCRIPTION = "This high muzzle velocity sniper rifle with a 10X scope is a lethal weapon at any range, especially if you can land a head shot."

-- The two items. The careers of each are those of its base: Bardin's handgun's are its own and the Engineer, whom his DLC adds to it.
local VARIANTS = {
	{
		base_item = "es_handgun",
		can_wield = { "es_huntsman", "es_knight", "es_mercenary" },
		id = "sniper_rifle",
		key = "ut_sniper_rifle",
		template = "ut_sniper_rifle_template",
	},
	{
		base_item = "dr_handgun",
		can_wield = { "dr_ironbreaker", "dr_ranger", "dr_engineer" },
		id = "sniper_rifle_dr",
		key = "ut_sniper_rifle_dr",
		template = "ut_sniper_rifle_dr_template",
	},
}

for _, variant in ipairs(VARIANTS) do
	mod.items.register(variant.id, {
		key = variant.key,
		template = variant.template,
		base_item = variant.base_item,
		can_wield = variant.can_wield,
		-- A gun's: the ammo traits
		slot_type = "ranged",
		property_table_name = "ranged",
		trait_table_name = "ranged_ammo",
		deus_property_table_name = "deus_ranged_ammo",
		deus_trait_table_name = "deus_ranged_ammo",
		name = "UT2004 Sniper Rifle",
		type_name = "Sniper Rifle",
		description = DESCRIPTION,
		keywords = { "weapon_keyword_high_damage", "weapon_keyword_sniper", "weapon_keyword_headshotting" },
		icon = "ut_sniper_rifle_icon",
		icon_package = "resource_packages/unreal_tournament/icons",
		icon_materials = "ui/ut/sniper_rifle_icon",
	})
end

local TEMPLATE_NAMES = {}

for _, variant in ipairs(VARIANTS) do
	TEMPLATE_NAMES[mod.items.weapons[variant.id].template] = true
end

local CONFIG = {
	-- All of the ammo, a little under ClassicSniperAmmo.MaxAmmo's 35 (set in the game). It is all the clip, so there is no reload.
	max_ammo = 30,
	-- ClassicSniperFire.FireRate. After a shot, the next one can be made once this much time has passed.
	fire_rate = 1.33,
	chain_margin = 0.15, -- seconds
	-- ClassicSniperFire.DamageMin and DamageMax, in UT2004's units, where 45 is the shock rifle's beam, and HeadShotDamageMult
	damage = 60,
	headshot_multiplier = 2,
	-- How far the bullet reaches, in meters (TraceRange is 17000 units), for where it hits
	range = 340,
	-- How far a bot shoots from, in meters
	bot_max_range = 60,
	-- ClassicSniperFire.ShakeOffsetMag, ShakeOffsetRate and ShakeOffsetTime: the view jumps back 15 units and up 10 (forward, right, up).
	-- It has no turn (ShakeRotMag is 0), so the game's recoil of the handgun is taken away.
	shake_magnitude = { -15, 0, 10 },
	shake_rate = { -4000, 0, 4000 },
	shake_time = 1.6,
	-- How long after a shot while zoomed the character aims again in third person, before the shot's animation lowers the gun (the
	-- base's zoomed shot goes back to its aim at 0.7 s, which looked late; set in the game)
	rezoom_time = 0.5, -- s
}

local TOTAL_TIME = CONFIG.fire_rate + CONFIG.chain_margin

-- Spread: the bullet hits exactly where the crosshair is.
utils.zero_spread_template("ut_sniper_bullet", "handgun")

-- The bullet. It stops at the first enemy it hits, as UT's trace does: a cleave that is tiny hurts one enemy. These are the values it had
-- as a copy of the handgun's bullet (shot_sniper) made flat: the armor multipliers of the mod's flat damage (utils.make_flat), and the
-- handgun's own multipliers for a critical hit, its hit reactions and its curve of head shot and critical bonus (smiter_curve). Super
-- armor takes 0.6, as from the Lightning Gun.
utils.add_damage_profile("ut_sniper_bullet", {
	charge_value = "instant_projectile",
	shield_break = true,
	no_stagger_damage_reduction_ranged = true,
	is_explosion = false,
	attack_template = "shot_sniper",
	damage_type = "shot_sniper",
	attack_power = attack_power_for(CONFIG.damage),
	impact_power = impact_power_for(CONFIG.damage),
	armor_attack = { 1, 0.8, 1.5, 1, 1, 0.6 },
	armor_impact = { 1, 0.8, 1, 1, 1, 0.6 },
	critical_armor_attack = { 1, 1.4, 1.5, 1, 0.75, 0.6 },
	critical_armor_impact = { 1, 1, 1, 1, 1, 1 },
	cleave_attack = 0.01,
	cleave_impact = 0.01,
	boost_curve_type = "smiter_curve",
	boost_curve_coefficient = 1,
	boost_curve_coefficient_headshot = 1,
	-- (a hit on the head does HeadShotDamageMult times the damage: see utils.set_headshot_multiplier)
	headshot_boost = math.clamp(CONFIG.headshot_multiplier - 1, 0, 1),
	headshot_boost_boss = 0.5,
	headshot_boost_armor = 0.5,
	headshot_boost_heavy_armor = 0.25,
	no_headshot_boost = false,
	crit_boost = 0.5,
	no_crit_boost = false,
	stagger_duration_modifier = 1,
	stagger_distance_modifier = 1,
})

-- The flow events of the game's handgun shot that start its tracer (ActionHandgun.client_owner_post_update). UT draws no tracer for the
-- player who fires.
local DROPPED_FLOW_EVENTS = {
	lua_bullet_trail = true,
	lua_bullet_trail_set = true,
}

-- Weapon template

-- When each character last fired, on the machine that runs their actions. A shot waits for UT's fire time after the last one whatever
-- action it starts from (the zoom's, which a shot can turn into at once, say).
local last_shots = setmetatable({}, {
	__mode = "k",
})

local function ready_to_fire(unit)
	local last = last_shots[unit]

	return not last or Managers.time:time("game") - last >= CONFIG.fire_rate / mod.utils.attack_speed(unit) - 0.01
end

-- The actions that can follow a shot. Holding the button repeats the shot, as in UT, and the zoom can start at any time.
local function fire_chain_actions()
	local entries = {
		{
			action = "action_wield",
			input = "action_wield",
			start_time = 0.4,
			sub_action = "default",
		},
		{
			action = "action_two",
			input = "action_two",
			start_time = 0,
			sub_action = "default",
		},
	}

	for _, input in ipairs({ "action_one", "action_one_hold" }) do
		entries[#entries + 1] = {
			action = "action_one",
			input = input,
			start_time = CONFIG.fire_rate,
			sub_action = "default",
		}
	end

	return entries
end

-- The shot: the game's handgun shot (kind "handgun"), with its ammo and animation. It can be repeated after UT's fire time, and it has no
-- reload. Its hits on the world and on enemies are the game's handgun's (the holes, the dust and the blood). The values that are not
-- UT's are the ones it had as a copy of the handgun's shot: how loud it is to enemies, the aim assist, the talents' kind of hit
-- (charge_value) and when its damage is dealt.
local function build_shot(hand, anims)
	return {
		kind = "handgun",
		weapon_action_hand = hand,
		anim_event = anims.anim_event,
		anim_event_last_ammo = anims.anim_event_last_ammo,
		anim_event_no_ammo_left = anims.anim_event_no_ammo_left,
		ammo_usage = 1,
		fire_time = 0,
		-- The shot lasts slightly longer than the time to the next shot. A held button is only read while a shot is still running, so a
		-- shot that ends exactly when the next one may start would miss it.
		total_time = TOTAL_TIME,
		damage_window_start = 0.1,
		damage_window_end = 0,
		damage_profile = "ut_sniper_bullet",
		headshot_multiplier = CONFIG.headshot_multiplier,
		hit_effect = "bullet_impact",
		ignore_shield_hit = true,
		ranged_attack = true,
		charge_value = "light_attack",
		alert_sound_range_fire = 10,
		alert_sound_range_hit = 2,
		aim_assist_max_ramp_multiplier = 1,
		aim_assist_ramp_decay_delay = 0.1,
		aim_assist_ramp_multiplier = 0.3,
		-- (UT's kick of the view is the skin's shake, so the game's recoil is off)
		apply_recoil = false,
		reload_when_out_of_ammo = false,
		spread_template_override = "ut_sniper_bullet",
		allowed_chain_actions = fire_chain_actions(),
		condition_func = ready_to_fire,
		chain_condition_func = ready_to_fire,
		enter_function = function (attacker_unit, input_extension)
			input_extension:clear_input_buffer()
		end,
		ut_sniper_bullet = true,
		ut_dropped_flow_events = DROPPED_FLOW_EVENTS,
	}
end

-- The aim animation of each template's base: { zoom_in = event, zoom_out = event, rezoom_time = seconds after a shot }
mod.sniper_zoom_animations = {}

-- Makes the rifle on the shell of its base handgun (utils.template_shell): everything that is not the handgun's animations, models and
-- sounds is set here. Kruber's and Bardin's handguns differ only in those.
local function apply_handgun(template)
	local base = utils.template_shell(template)
	local base_actions = base.actions

	-- The chart of the item's stats, from 0 to 7. The bullet is the normal attack. It is set against the Lightning Gun's: a little less
	-- damage, stagger and armour piercing (0.8 against armour, where the bolt does 1), and a faster shot. It hurts one enemy, as the
	-- Minigun's rounds do.
	template.weapon_diagram = {
		light_attack = {
			[DamageTypes.ARMOR_PIERCING] = 6,
			[DamageTypes.CLEAVE] = 1,
			[DamageTypes.SPEED] = 3,
			[DamageTypes.STAGGER] = 4,
			[DamageTypes.DAMAGE] = 6,
		},
		heavy_attack = {
			[DamageTypes.ARMOR_PIERCING] = 0,
			[DamageTypes.CLEAVE] = 0,
			[DamageTypes.SPEED] = 0,
			[DamageTypes.STAGGER] = 0,
			[DamageTypes.DAMAGE] = 0,
		},
	}

	local actions = template.actions

	-- The shot, with the handgun's shot animation, and UT's zoom (zoom.lua) in place of the handgun's aim. Inspecting is the handgun's,
	-- kept by the shell.
	local hand = base_actions.action_one.default.weapon_action_hand
	local aim = base_actions.action_two.default

	-- The base's aim animation, which skin.lua plays on the character while the zoom is in (the zoom is a toggle, not a held action).
	-- A shot's animation takes the character out of the aim, so skin.lua aims again rezoom_time after a shot.
	if aim.anim_event then
		mod.sniper_zoom_animations[template.name] = { zoom_in = aim.anim_event, zoom_out = aim.anim_end_event, rezoom_time = CONFIG.rezoom_time }
	end

	actions.action_one = {
		default = build_shot(hand, base_actions.action_one.default),
	}

	-- While the zoom is held, a shot can follow at once (it waits for its fire time), and so can wielding
	actions.action_two = {
		default = mod.zoom.action(hand, {
			{
				action = "action_wield",
				input = "action_wield",
				start_time = 0,
				sub_action = "default",
			},
			{
				action = "action_one",
				input = "action_one",
				start_time = 0,
				sub_action = "default",
			},
			{
				action = "action_one",
				input = "action_one_hold",
				start_time = 0,
				sub_action = "default",
			},
		}),
	}

	-- The game's own wielding and reload, which every gun of the game has (the reload only comes with picked up ammo, see ammo_data)
	actions.action_wield = table.clone(ActionTemplates.wield)
	actions.weapon_reload = table.clone(ActionTemplates.reload)

	utils.set_actions_lookup_data(actions, template.name)

	-- All the ammo is the clip, and picked up ammo is added to it, so there is no reload between shots. Nothing should need a reload, but
	-- the game may still start one when the weapon is wielded, so the reload is short.
	template.ammo_data = {
		ammo_hand = "right",
		max_ammo = CONFIG.max_ammo,
		ammo_per_clip = CONFIG.max_ammo,
		ammo_per_reload = CONFIG.max_ammo,
		ammo_immediately_available = true,
		reload_time = 0.2,
		reload_on_ammo_pickup = true,
		play_reload_anim_on_wield_reload = true,
		should_update_anim_ammo = true,
	}

	-- How bots use it: the handgun's, at the body (the head for a charged shot, which this has none of), against berserkers, specials,
	-- armored and shielded enemies, shooting past enemies in the way. effective_against_combined is what the game works out for every
	-- weapon as it loads (weapons.lua), before this table is made: its bots' check of a target (BTConditions) fails without it.
	local effective_against = bit.bor(BreedCategory.Berserker, BreedCategory.Special, BreedCategory.Armored, BreedCategory.Shielded)

	template.attack_meta_data = {
		aim_at_node = "j_spine1",
		aim_at_node_charged = "j_head",
		can_charge_shot = false,
		charge_above_range = 30,
		charge_when_obstructed = false,
		ignore_enemies_for_obstruction = true,
		minimum_charge_time = 0.45,
		effective_against = effective_against,
		effective_against_charged = 0,
		effective_against_combined = effective_against,
		max_range = CONFIG.bot_max_range,
	}

	-- What the game's talents, traits and properties take it for: a handgun
	template.buff_type = "RANGED"
	template.weapon_type = "HANDGUN"

	-- Dodging: the handgun's (no_dodge: the player's dodges are not the weapon's), and the game's crosshair and spread, the handgun's
	-- (the bullet has no spread of its own, see ut_sniper_bullet)
	template.no_dodge = true
	template.buffs = {
		change_dodge_distance = {
			external_optional_multiplier = 1,
		},
		change_dodge_speed = {
			external_optional_multiplier = 1,
		},
	}
	template.crosshair_style = "default"
	template.default_spread_template = "handgun"
	template.spread_lerp_speed = 5
	template.spread_lerp_speed_zoom = 3.75

	-- The aim assist for a controller: the handgun's
	template.aim_assist_settings = {
		always_auto_aim = true,
		base_multiplier = 0.15,
		effective_max_range = 10,
		max_range = 22,
		no_aim_input_multiplier = 0,
		target_node = "j_spine1",
		breed_scalars = {
			skaven_clan_rat = 1,
			skaven_slave = 1,
			skaven_storm_vermin = 0.25,
		},
	}

	template.tooltip_compare = {
		light = {
			action_name = "action_one",
			sub_action_name = "default",
		},
		heavy = {
			action_name = "action_one",
			sub_action_name = "default",
		},
	}
	template.tooltip_detail = template.tooltip_compare
end

for template_name in pairs(TEMPLATE_NAMES) do
	mod.items.set_template_changes(template_name, apply_handgun)
	mod.zoom.register(template_name)
end

-- The shot. The game's own shot damages what the bullet hits. This works out where it hit, for the skin's sparks and sound
-- (SniperWallHitEffect), and tells the skin and the other players. It runs on the machine that owns the shot, which is the player's,
-- or the host's for its bots.

-- What the skin is told: mod.sniper.shot_callbacks[name] = function (owner_unit, hit_position, hit_normal, start, direction), with no
-- position or normal if the bullet hit nothing. The bullet starts at start (the eye) and goes along direction.
mod.sniper = {
	shot_callbacks = {},
	-- The seconds between shots, and when the player last fired
	fire_rate = CONFIG.fire_rate,
	last_fire_time = nil,
}

-- The game's time starts again in each level, so a shot of the last level would keep the gun from being ready until the new level's time
-- got as far
mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	mod.sniper.last_fire_time = nil

	table.clear(last_shots)
end

local function raycast(physics_world, origin, direction)
	return PhysicsWorld.immediate_raycast_actors(physics_world, origin, direction, CONFIG.range, "static_collision_filter", "filter_player_ray_projectile_static_only", "dynamic_collision_filter", "filter_player_ray_projectile_ai_only", "dynamic_collision_filter", "filter_player_ray_projectile_hitbox_only")
end

local function tell(owner_unit, hit_position, hit_normal, start, direction)
	for _, callback in pairs(mod.sniper.shot_callbacks) do
		callback(owner_unit, hit_position, hit_normal, start, direction)
	end
end

mod.handgun_start_callbacks.sniper = function (self, new_action)
	self._ut_sniper_checked = not new_action.ut_sniper_bullet

	if new_action.ut_sniper_bullet then
		last_shots[self.owner_unit] = Managers.time:time("game")
	end

	-- ClassicSniperFire's view shake, for the player who fires
	if new_action.ut_sniper_bullet and utils.is_local_player_unit(self.owner_unit) then
		mod.view_shake.start(CONFIG.shake_magnitude, CONFIG.shake_rate, CONFIG.shake_time)
		mod.sniper.last_fire_time = Managers.time:time("game")
	end
end

mod.handgun_update_callbacks.sniper = function (self)
	if self._ut_sniper_checked or self.state == "waiting_to_shoot" then
		return
	end

	self._ut_sniper_checked = true

	local owner_unit = self.owner_unit
	local first_person_extension = ScriptUnit.extension(owner_unit, "first_person_system")
	local origin, rotation = first_person_extension:get_projectile_start_position_rotation()
	local direction = Quaternion.forward(rotation)
	local hit = first_beam_hit(raycast(self.physics_world, origin, direction), owner_unit)
	local hit_position = hit and hit[1]
	local hit_normal = hit and hit[3]

	tell(owner_unit, hit_position, hit_normal, origin, direction)

	-- (a shot that hit nothing is sent with the zero vector as its normal)
	local x, y, z = 0, 0, 0
	local normal_x, normal_y, normal_z = 0, 0, 0

	if hit then
		x, y, z = Vector3.x(hit_position), Vector3.y(hit_position), Vector3.z(hit_position)
		normal_x, normal_y, normal_z = Vector3.x(hit_normal), Vector3.y(hit_normal), Vector3.z(hit_normal)
	end

	mod:network_send("ut_sniper_shot", "others", Managers.state.unit_storage:go_id(owner_unit), x, y, z, normal_x, normal_y, normal_z,
		Vector3.x(origin), Vector3.y(origin), Vector3.z(origin), Vector3.x(direction), Vector3.y(direction), Vector3.z(direction))
end

mod:network_register("ut_sniper_shot", function (_, owner_go_id, x, y, z, normal_x, normal_y, normal_z, start_x, start_y, start_z, direction_x, direction_y, direction_z)
	local unit = Managers.state.unit_storage:unit(owner_go_id)

	if not unit or not Unit.alive(unit) then
		return
	end

	local normal = Vector3(normal_x, normal_y, normal_z)
	local start = Vector3(start_x, start_y, start_z)
	local direction = Vector3(direction_x, direction_y, direction_z)

	if Vector3.length(normal) > 0.01 then
		tell(unit, Vector3(x, y, z), normal, start, direction)
	else
		tell(unit, nil, nil, start, direction)
	end
end)
