local mod = get_mod("unreal_tournament")

-- Bio Rifle: made on the shell of Bardin's Masterwork Pistol (utils.template_shell), with fire modes of its own. It follows UT2004's XWeapons/BioRifle, BioFire,
-- BioChargedFire and BioGlob.
--   LMB: lobs one glob of goop. It costs 1 ammo, and a glob can be fired every 0.33 seconds.
--   RMB (held): loads goop, 1 ammo at once and then 1 more every 0.25 seconds, up to 10. Releasing RMB fires one big glob, which has
--               as much goop as was loaded.
-- A glob that hits a player, a bot or an enemy while it flies explodes there. A glob that hits a surface sticks to it. Its goop level
-- is cut down to 2, 3 or 4, chosen at random for each glob, and what is above that is thrown off as small globs of 1 goop each. A
-- stuck glob explodes by itself after 2.25 seconds. It explodes 0.15 seconds after something steps into it, and 0.1 seconds after
-- an explosion of a rocket, a flak shell, a shock ball, a shock combo or another glob reaches it. A glob on a ceiling drips instead
-- of exploding: it falls after about 2.2 seconds and explodes where it lands. A glob that lands in a stuck glob joins it, up to a
-- level of 5, and what is above that is thrown off as small globs. An explosion does 20 + 19 damage for each level of goop, and it is
-- as wide as the level's square root times the radius of a level 1 glob.
-- The ammo is the clip, so there is no reload.

local utils = mod.utils
local with_valid_positions = utils.with_valid_positions
local register_explosion_template = utils.register_explosion_template
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for

local SETTING_ID = "bio_rifle"
local ITEM_KEY = "ut_bio_rifle"
local TEMPLATE_NAME = "ut_bio_rifle_template"

mod.items.register(SETTING_ID, {
	key = ITEM_KEY,
	template = TEMPLATE_NAME,
	base_item = "dr_steam_pistol",
	deus_copy = "deus_dr_steam_pistol",
	name = "UT2004 Bio Rifle",
	type_name = "Bio Rifle",
	-- This is UT2004's description, shortened.
	description = "The GES Bio Rifle is one of the most controversial weapons in the Tournament, loved by some and loathed by others. It peppers an area with small globs of Biosludge, or launches one large glob at the target.",
	keywords = { "weapon_keyword_rapid_fire", "weapon_keyword_crowd_control", "weapon_keyword_charged_attack" },
	icon = "ut_bio_rifle_icon",
	icon_package = "resource_packages/unreal_tournament/icons",
	icon_materials = "ui/ut/bio_rifle_icon",
})

local CONFIG = {
	-- Sizes and distances use UT's meters for each Unreal unit (uu, utils.UT_UNIT). Speeds are 0.75 of that, so the globs are slower,
	-- and the gravity is lowered to match, which keeps the drop of a glob over a distance the same as in UT.
	speed_scale = 0.75,
	gravity = -10.7, -- m/s^2, UT's 950 uu/s^2 (19 m/s^2) times speed_scale squared
	-- BioAmmo.MaxAmmo. All of it is the clip, so there is no reload.
	max_ammo = 50,
	-- BioFire: FireRate and the speed of BioGlob (Speed 2000 uu/s)
	fire_interval = 0.33,
	glob_speed_uu = 2000,
	-- Bots shoot globs at targets up to this far, in meters (BioFire.MaxRange is 1500 uu). It goes in the weapon's attack_meta_data, which
	-- the game's bot shooting reads.
	bot_max_range = 30,
	-- Where a glob starts, measured from the camera: forward, to the right and down. UT's ProjSpawnOffset is 20, 9 and -6 uu. The
	-- pistol is drawn further out here, so the offsets are larger, to start the glob at the muzzle.
	start_forward = 0.8, -- m
	start_right = 0.25, -- m
	start_down = 0.15, -- m
	-- The view kicks when a glob is fired, with the game's weapon recoil, which is the Masterwork Pistol's own for the small glob. UT's
	-- BioChargedFire shakes the view 100 against BioFire's 70 (ShakeRotMag), so the big glob kicks that much more.
	recoil_climb = 2, -- degrees
	recoil_climb_time = 0.1, -- seconds
	recoil_restore_time = 0.25, -- seconds
	recoil_charged_share = 100 / 70,
	-- BioChargedFire: GoopUpRate, MaxGoopLoad and FireRate
	goop_up_rate = 0.25, -- seconds between two units of goop
	max_goop_load = 10,
	charged_fire_interval = 0.33,
	-- The release of the button fires the glob once this long has passed since the charge started.
	release_delay = 0.05, -- seconds
	-- BioGlob
	max_goop_level = 5, -- the level a glob that has landed can grow to
	base_damage = 20, -- BaseDamage
	level_damage = 19, -- Damage, which is added for each level of goop
	-- UT's damage is scaled down as the Rocket Launcher's and the Flak Cannon's explosions are (UT's 90 is 60 here), because the game's enemies
	-- are not UT's players.
	damage_scale = 60 / 90,
	-- DamageRadius is 120 uu. It is reduced to 80 uu here, the way the other weapons' explosions are, because a glob explodes a lot.
	blast_radius_uu = 80,
	-- The damage is the same up to this share of the radius and then falls off linearly to 0 at the radius. UT's falls off from the
	-- edge of the victim's body.
	blast_full_damage_share = 0.15,
	-- MomentumTransfer is 40000. (BioGlob.BlowUp halves it for a glob in the air, but it checks for PHYS_Flying and a glob in the air is
	-- PHYS_Falling, so it never does.) Scaled by the volume of the glob, which is the square root of
	-- its level. This is the speed in m/s that the player who fired the glob is thrown at when it explodes at their feet.
	jump_speed = 4.6,
	-- The explosion hurts the player who fired the glob, as in UT. This is the share of the glob's damage that they take at the center.
	self_damage_share = 0.75,
	-- BioGlob.GloblingSpeed is 200 uu/s, plus up to 150 uu/s more. SplashGlobs multiplies it by (the surface's normal plus a random
	-- direction times 0.8).
	globling_speed_uu = { 200, 350 },
	globling_random_share = 0.8,
	-- How much of the speed of the glob that landed, reflected off the surface, a small glob takes with it
	globling_inherit_share = 0.1,
	-- BioGlob.RestTime, TouchDetonationDelay and DripTime. The delay of an explosion that is set off by an explosion is 0.1 seconds in
	-- BioGlob.TakeDamage.
	rest_time = 2.25,
	touch_detonation_delay = 0.15,
	drip_time = 1.8,
	detonation_delay = 0.1,
	-- A glob that drips starts with the gravity times 0.2 as its speed (190 uu/s).
	drip_speed_uu = 190,
	-- The glob's Hit animation plays when it lands. A glob on a ceiling starts to drip when the animation ends. The animation is 18 frames
	-- (BioRifle_rc.uc) at the frame rate of 30 a second, which the skin assumes (see goop_frame_rate in bio/skin.lua).
	hit_animation_time = 0.6,
	-- The collision of a glob that has landed is a cylinder, GoopVolume * 10 uu across. The collision of a glob in the air is 2 uu.
	collision_uu = 10,
	flying_collision_uu = 2,
	-- The height of the surface normal's down component above which a glob is on a ceiling (SurfaceNormal dot (0, 0, -1) > 0.7)
	ceiling_dot = 0.7,
	-- Bots keep away from a glob that has landed (UT's AvoidMarker) the way they keep away from a fire grenade's fire: a nav tag volume
	-- of the same layer, as wide as the blast plus this margin (the margin is what AreaDamageExtension adds for a player's size).
	avoid_layer = "fire_grenade",
	avoid_margin = 0.5, -- m
	-- A glob that lands also leaves a splat on the surface (BioDecal), which stays for 6 seconds.
	-- The size of a character, for the globs that wait for someone to step in. UT's collision is 17 uu in radius and 88 uu high.
	pawn_radius_uu = 17,
	pawn_height_uu = 88,
	-- A glob that is still flying after this many seconds disappears. UT's LifeSpan is 20.
	max_flight = 8,
	-- The most globs that can wait on the surfaces at once. The oldest explodes when there are more.
	max_stuck = 40,
	-- A critical hit and the armor of an enemy do not exist in UT. These are how much of the damage and the stagger each armor type
	-- takes: unarmored, armored, monsters, players, berserkers and super armor. The game's own multipliers for explosions are 0 against
	-- super armor (chaos warriors), which would make them take nothing. The Bio Rifle is for denying an area and for swarms. Its many
	-- small hits do less against armor, so that it does not stand in for the weapons that pierce it.
	armor_attack = {1, 0.8, 1.5, 1, 1, 0.5},
	armor_impact = {1, 0.8, 1, 1, 1, 0.5},
	-- The game's sound event of the Sienna's fireball. The skin plays UT's sound instead.
	fire_sound = "player_combat_weapon_staff_fireball_fire",
}

local UNIT = utils.UT_UNIT

-- The goop level of a glob is carried by the scale of its projectile. The scale goes from 0 to 1, and 0 is a level 1 glob. The blast
-- radius of a level is the radius of level 1 times the level's square root, so the scale is made to follow the square root.
local ROOT_MAX = math.sqrt(CONFIG.max_goop_load)

local function scale_of_level(level)
	return (math.sqrt(level) - 1) / (ROOT_MAX - 1)
end

local function level_of_scale(scale)
	local root = 1 + math.clamp(scale or 0, 0, 1) * (ROOT_MAX - 1)

	return math.clamp(math.floor(root * root + 0.5), 1, CONFIG.max_goop_load)
end

-- The scale is sent as a whole number from 0 to 100.
local function scale_to_send(level)
	return math.floor(scale_of_level(level) * 100 + 0.5)
end

-- What the skin needs to know about a glob
mod.bio_goop = {
	level_of_scale = level_of_scale,
	volume_of_level = function (level)
		return math.sqrt(level)
	end,
}

-- The damage of a glob of the level, in the units that the damage profiles use (UT's scaled by damage_scale).
local function blast_damage(level)
	return (CONFIG.base_damage + CONFIG.level_damage * level) * CONFIG.damage_scale
end

local REFERENCE_DAMAGE = blast_damage(CONFIG.max_goop_load)

-- The power level of a glob is the weapon's power level times this. The damage profiles are made for the biggest glob.
local function power_ratio(level)
	return blast_damage(level) / REFERENCE_DAMAGE
end

local function blast_radius(level)
	return CONFIG.blast_radius_uu * UNIT * math.sqrt(level)
end

local function glob_radius(level)
	return CONFIG.collision_uu * UNIT * math.sqrt(level)
end

-- The speed for the action or the projectile, in the unit that the game uses: m/s * 100
local function action_speed(speed_uu)
	return speed_uu * UNIT * CONFIG.speed_scale * 100
end

-- A charged glob is slower the more goop it has (BioGlob.AdjustSpeed).
local function charged_speed_uu(level)
	return CONFIG.glob_speed_uu * (0.4 + level) / (1.4 * level)
end

local GRAVITY_SETTINGS = "ut_bio_glob"

ProjectileGravitySettings[GRAVITY_SETTINGS] = CONFIG.gravity

utils.register_network_lookup("projectile_gravity_settings", GRAVITY_SETTINGS)

-- The globs that come off a landing glob, and the glob that drips, are an action of the weapon of their own. A projectile takes its
-- settings from its action by name, and the name is sent over the network, so it is registered.
local CHILD_ACTION_NAME = "action_one"
local CHILD_SUB_ACTION = "ut_bio_child"

utils.register_network_lookup("sub_actions", CHILD_SUB_ACTION)

-- A glob goes where the crosshair is. It has no spread.
local SPREAD_TEMPLATE = "ut_bio"

utils.zero_spread_template(SPREAD_TEMPLATE, "brace_of_pistols")

-- Damage profiles (see utils.add_damage_profile). The direct hit of a glob only staggers (UT has no damage from the hit itself, all of
-- the damage is the explosion), and does 1 damage so that it is not shown as blocked by armor. It stops at the first enemy. The glob
-- and the blast share the armor modifiers, for critical hits too.
local GLOB = {
	charge_value = "projectile",
	shield_break = false,
	no_stagger_damage_reduction_ranged = true,
	is_explosion = false,
	-- (the fireball's hit reactions, and the frag grenade's hit effects)
	attack_template = "fireball",
	damage_type = "grenade",
	attack_power = utils.STAGGER_HIT_ATTACK_POWER,
	impact_power = impact_power_for(CONFIG.level_damage * CONFIG.damage_scale),
	armor_attack = CONFIG.armor_attack,
	armor_impact = CONFIG.armor_impact,
	critical_armor_attack = CONFIG.armor_attack,
	critical_armor_impact = CONFIG.armor_impact,
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

utils.add_damage_profile("ut_bio_glob", GLOB)

-- The blast has no head shots or critical boost: the game's explosions have no boost curve. The cleave doesn't apply to it. A glance is
-- the blast's edge, with the game's glancing hit reactions and effects.
local BLAST = utils.damage_profile_spec(GLOB, {
	charge_value = "aoe",
	attack_template = "drakegun",
	damage_type = "grenade",
	attack_power = attack_power_for(REFERENCE_DAMAGE),
	impact_power = impact_power_for(REFERENCE_DAMAGE),
	cleave_attack = 1,
	cleave_impact = 1,
	boost_curve_type = false,
})

utils.add_damage_profile("ut_bio_blast", BLAST)
utils.add_damage_profile("ut_bio_blast_glance", utils.damage_profile_spec(BLAST, {
	attack_template = "drakegun_glance",
	damage_type = "grenade_glance",
}))

-- Explosion templates. The scale of the explosion goes from 0 for a level 1 glob to 1 for a level 10 glob. The damage comes from the
-- power level that the explosion is made with (see power_ratio). The one in the air is a template of its own for the skin, which draws
-- it differently. The shooter is hurt separately.
local function blast_template(name)
	register_explosion_template(name, {
		explosion = {
			alert_enemies = true,
			alert_enemies_radius = 10,
			attacker_power_level_offset = 1,
			damage_profile = "ut_bio_blast",
			damage_profile_glance = "ut_bio_blast_glance",
			ignore_attacker_unit = true,
			max_damage_radius_max = blast_radius(CONFIG.max_goop_load) * CONFIG.blast_full_damage_share,
			max_damage_radius_min = blast_radius(1) * CONFIG.blast_full_damage_share,
			radius_max = blast_radius(CONFIG.max_goop_load),
			radius_min = blast_radius(1),
			use_attacker_power_level = true,
		},
	})
end

blast_template("ut_bio_blast")
blast_template("ut_bio_blast_air")

-- A glob that lands or runs out of time does nothing by itself. The mod handles the landing.
register_explosion_template("ut_bio_landing", {})

-- The Weapon template
-- The glob is one of the game's projectiles, the bolt of the drakefire pistols.
local PROJECTILE_UNIT_TEMPLATES = {
	"drake_pistol_shot",
}

local function enter_function(attacker_unit, input_extension)
	input_extension:clear_input_buffer()

	return input_extension:reset_release_input()
end

local function build_projectile_info()
	local projectile_info = table.clone(Projectiles.brace_of_drake_pistols_shot)

	projectile_info.gravity_settings = GRAVITY_SETTINGS
	projectile_info.life_time = CONFIG.max_flight + 1
	projectile_info.unit_life_time = CONFIG.max_flight + 1
	-- A glob in the air hits an enemy as a rocket does (utils.UT_PROJECTILE_RADIUS), with its own 2 uu added. A wall is hit by the
	-- base's sphere, as before.
	projectile_info.radius = CONFIG.flying_collision_uu * UNIT + utils.UT_PROJECTILE_RADIUS
	projectile_info.static_impact_type = "sphere_sweep"
	projectile_info.ut_wall_radius = Projectiles.brace_of_drake_pistols_shot.radius

	return projectile_info
end

-- The actions that can follow a shot. Either fire mode can be used once the fire rate has passed, and the button can be held.
local function fire_chain_actions(interval)
	return {
		{
			action = "action_wield",
			input = "action_wield",
			start_time = 0.2,
			sub_action = "default",
		},
		{
			action = "action_one",
			input = "action_one",
			start_time = interval,
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
		{
			action = "weapon_reload",
			input = "weapon_reload",
			start_time = 0.3,
			sub_action = "default",
		},
	}
end

-- The fields that every glob's action has, whether the player fires it or it comes off a landed glob
local function glob_fields()
	return {
		kind = "crossbow",
		projectile_info = build_projectile_info(),
		speed = action_speed(CONFIG.glob_speed_uu),
		spread_template_override = SPREAD_TEMPLATE,
		ut_aoe_callback = "ut_bio_glob",
		ut_bio_glob = true,
		ut_hit_enemy_callback = "ut_bio_glob",
		ut_init_flow_event_filter = "bio",
		impact_data = {
			aoe = ExplosionTemplates.ut_bio_landing,
			damage_profile = "ut_bio_glob",
		},
		timed_data = {
			aoe = ExplosionTemplates.ut_bio_landing,
			life_time = CONFIG.max_flight,
		},
	}
end

-- The shot of a player: LMB fires a small glob, and releasing RMB fires the big one.
local function build_shot_action(charged)
	local interval = charged and CONFIG.charged_fire_interval or CONFIG.fire_interval
	local action = glob_fields()

	action.alert_sound_range_fire = 12
	action.alert_sound_range_hit = 2
	action.allowed_chain_actions = fire_chain_actions(interval)
	-- The ammo of the big glob was used while it was loaded.
	action.ammo_usage = charged and 0 or 1
	action.anim_event = "attack_shoot"
	action.anim_event_last_ammo = "attack_shoot"
	action.apply_recoil = true
	action.enter_function = enter_function
	action.fire_sound_event = CONFIG.fire_sound
	action.fire_time = 0
	action.recoil_settings = {
		climb_duration = CONFIG.recoil_climb_time,
		horizontal_climb = 0,
		restore_duration = CONFIG.recoil_restore_time,
		vertical_climb = CONFIG.recoil_climb * (charged and CONFIG.recoil_charged_share or 1),
		climb_function = math.easeInCubic,
		restore_function = math.ease_out_quad,
	}
	action.total_time = interval
	action.ut_bio_charged = charged or nil
	action.ut_bio_shot = true
	action.ut_skin_init_callback = "bio"

	return action
end

-- The globs that come off a landed glob. They are not fired by the player.
local function build_child_action()
	local action = glob_fields()

	action.allowed_chain_actions = {}
	action.ammo_usage = 0
	action.total_time = 1
	action.ut_skin_init_callback = "bio"

	return action
end

-- The charge. The goop is loaded by the callbacks below. Releasing the button fires the big glob.
local function build_charge_action()
	return {
		allowed_chain_actions = {
			{
				action = "action_wield",
				input = "action_wield",
				start_time = 0,
				sub_action = "default",
			},
			{
				action = "action_one",
				auto_chain = true,
				release_required = "action_two_hold",
				start_time = CONFIG.release_delay,
				sub_action = "shoot_charged",
			},
		},
		charge_time = CONFIG.goop_up_rate * CONFIG.max_goop_load,
		-- The charge needs ammo to start, like UT's ModeHoldFire.
		condition_func = function (unit, input_extension, ammo_extension)
			return not ammo_extension or ammo_extension:total_remaining_ammo() > 0
		end,
		enter_function = enter_function,
		hold_input = "action_two_hold",
		kind = "charge",
		minimum_hold_time = 0.05,
		total_time = math.huge,
		ut_charge_callback = "bio",
		zoom_condition_function = function ()
			return false
		end,
	}
end

-- Makes the rifle on the shell of the Masterwork Pistol (utils.template_shell): everything that is not the pistol's animations, models
-- and sounds is set here
local function apply_bio_rifle(template)
	utils.template_shell(template)

	-- The stat chart, from 0 to 7, set by hand against the Rocket Launcher's (its rocket is 60 damage and 6 on the chart) and the Flak Cannon's
	-- (its chunk and its shell). The small glob is the light attack (26 damage), and the big glob is the heavy one (140). The goop does a
	-- fifth less against armor, which puts its armor piercing between the chunk's and the shell's.
	template.weapon_diagram = {
		light_attack = {
			[DamageTypes.ARMOR_PIERCING] = 2,
			[DamageTypes.CLEAVE] = 4,
			[DamageTypes.SPEED] = 5,
			[DamageTypes.STAGGER] = 3,
			[DamageTypes.DAMAGE] = 3,
		},
		heavy_attack = {
			[DamageTypes.ARMOR_PIERCING] = 4,
			[DamageTypes.CLEAVE] = 6,
			[DamageTypes.SPEED] = 2,
			[DamageTypes.STAGGER] = 6,
			[DamageTypes.DAMAGE] = 6,
		},
	}

	local actions = template.actions

	template.required_projectile_unit_templates = template.required_projectile_unit_templates or {}

	for _, name in ipairs(PROJECTILE_UNIT_TEMPLATES) do
		template.required_projectile_unit_templates[name] = true
	end

	-- How bots use it: the pistol's. A bot aims at the body and holds the button while it fires the small glob, shooting past enemies in
	-- the way, against berserkers, specials and armored enemies.
	local effective_against = bit.bor(BreedCategory.Berserker, BreedCategory.Special, BreedCategory.Armored)

	template.attack_meta_data = {
		aim_at_node = "j_spine1",
		fire_input = "fire_hold",
		ignore_enemies_for_obstruction = true,
		max_range = CONFIG.bot_max_range,
		aim_data = {
			max_radius_pseudo_random_c = 0.0557,
			min_radius_pseudo_random_c = 0.3021,
			min_radius = math.pi / 72,
			max_radius = math.pi / 16,
		},
		aim_data_charged = {
			max_radius_pseudo_random_c = 0.01475,
			min_radius_pseudo_random_c = 0.0557,
			min_radius = math.pi / 72,
			max_radius = math.pi / 16,
		},
		-- (while its action is the small glob's)
		hold_fire_condition = function (t, blackboard)
			if blackboard then
				local inventory_extension = blackboard.inventory_extension
				local _, right_hand_weapon_extension, left_hand_weapon_extension = CharacterStateHelper.get_item_data_and_weapon_extensions(inventory_extension)
				local current_action_settings = CharacterStateHelper.get_current_action_data(left_hand_weapon_extension, right_hand_weapon_extension)

				if current_action_settings then
					local action_lookup = current_action_settings.lookup_data

					return action_lookup and action_lookup.action_name == "action_one" and action_lookup.sub_action_name == "default"
				end
			end

			return false
		end,
		effective_against = effective_against,
		effective_against_charged = 0,
		effective_against_combined = effective_against,
		-- This tells the bot shooting that this is the Bio Rifle (see bots.lua).
		ut_bio = true,
	}

	-- All the ammo is the clip, and picked up ammo is added to it, so there is no reload between shots. The pistol's ammo counter is
	-- for six rounds, so it is not updated. Nothing should need a reload, but the game may still start one when the weapon is wielded,
	-- so the reload is made short.
	template.ammo_data = {
		ammo_hand = "right",
		max_ammo = CONFIG.max_ammo,
		ammo_per_clip = CONFIG.max_ammo,
		ammo_per_reload = CONFIG.max_ammo,
		ammo_immediately_available = true,
		reload_time = 0.2,
		reload_on_ammo_pickup = false,
		play_reload_anim_on_wield_reload = false,
		should_update_anim_ammo = false,
	}

	-- What the game's talents, traits and properties take it for: the pistol's kind, a brace of pistols
	template.buff_type = "RANGED"
	template.weapon_type = "BRACE_OF_PISTOLS"

	-- Dodging, the crosshair and its spread: the pistol's (each glob has UT's own spread, see SPREAD_TEMPLATE). A pistol's dodges go a
	-- quarter further and faster, and any number of them in a row go the full distance (dodge_count).
	template.dodge_count = 100
	template.buffs = {
		change_dodge_distance = {
			external_optional_multiplier = 1.25,
		},
		change_dodge_speed = {
			external_optional_multiplier = 1.25,
		},
	}
	template.crosshair_style = "default"
	template.default_spread_template = SPREAD_TEMPLATE
	template.spread_lerp_speed = 5

	-- The aim assist for a controller: the pistol's
	template.aim_assist_settings = {
		aim_at_node = "j_spine",
		always_auto_aim = true,
		base_multiplier = 0.15,
		effective_max_range = 10,
		max_range = 22,
		no_aim_input_multiplier = 0,
		breed_scalars = {
			skaven_clan_rat = 1,
			skaven_slave = 1,
			skaven_storm_vermin = 0.25,
		},
	}

	-- The tooltip's light attack is the small glob, and its heavy attack the big one
	template.tooltip_compare = {
		light = {
			action_name = "action_one",
			sub_action_name = "default",
		},
		heavy = {
			action_name = "action_one",
			sub_action_name = "shoot_charged",
		},
	}
	template.tooltip_detail = template.tooltip_compare

	-- The small glob, the big one, the globs that come off a landed glob, and the charge. Inspecting is the pistol's, kept by the shell.
	actions.action_one = {
		default = build_shot_action(false),
		shoot_charged = build_shot_action(true),
	}
	actions[CHILD_ACTION_NAME][CHILD_SUB_ACTION] = build_child_action()
	actions.action_two = {
		default = build_charge_action(),
	}
	-- The game's own wielding and reload, which every gun of the game has (the reload only comes with picked up ammo, see ammo_data)
	actions.action_wield = table.clone(ActionTemplates.wield)
	actions.weapon_reload = table.clone(ActionTemplates.reload)

	utils.set_actions_lookup_data(actions, TEMPLATE_NAME)
end

-- The mod holds its own references to the units of the globs while the weapon is enabled.
local packages = utils.package_holder("unreal_tournament_bio")

-- Loading goop
-- The goop that each player has loaded: { load, timer, done }. It is read when the big glob is fired.
local goop_loads = setmetatable({}, {
	__mode = "k",
})

-- Used by the skin: how long a full load takes, and whether a player's load is done (full, or the ammo ran out).
mod.bio_goop.load_time = CONFIG.goop_up_rate * CONFIG.max_goop_load
mod.bio_goop.max_load = CONFIG.max_goop_load
mod.bio_goop.load_amount = function (owner_unit)
	local state = goop_loads[owner_unit]

	return state and state.load or 0
end
mod.bio_goop.is_load_done = function (owner_unit)
	local state = goop_loads[owner_unit]

	return state ~= nil and state.done
end

-- Loads one more unit of goop. It takes 1 ammo, and nothing is loaded if there is none. The loading is done when the load is full or
-- the ammo is gone.
local function add_goop(action, state)
	local ammo_extension = action.ammo_extension

	if ammo_extension and ammo_extension:ammo_count() > 0 then
		state.load = state.load + 1

		ammo_extension:use_ammo(1)
	end

	if state.load >= CONFIG.max_goop_load or not ammo_extension or ammo_extension:ammo_count() <= 0 then
		state.done = true
	end
end

-- BioChargedFire.Hold: one unit of goop at once, and then one every GoopUpRate seconds.
mod.charge_start_callbacks.bio = function (action, new_action)
	if new_action.ut_charge_callback ~= "bio" then
		return
	end

	local state = {
		done = false,
		load = 0,
		timer = 0,
	}

	goop_loads[action.owner_unit] = state

	add_goop(action, state)
end

mod.charge_update_callbacks.bio = function (action, dt)
	local state = goop_loads[action.owner_unit]

	if not state or state.done then
		return
	end

	state.timer = state.timer + dt

	while state.timer >= CONFIG.goop_up_rate and not state.done do
		state.timer = state.timer - CONFIG.goop_up_rate

		add_goop(action, state)
	end
end

-- Returns how much goop the player has loaded, at least 1, and empties the load.
local function take_goop_load(owner_unit)
	local state = goop_loads[owner_unit]
	local load = state and state.load or 0

	if state then
		state.load = 0
	end

	return math.clamp(load, 1, CONFIG.max_goop_load)
end

-- Gives back ammo that use_ammo took. The game counts what was used in the last frame in _shots_fired, and takes it from the clip in
-- its next update. add_ammo cannot give that part back, as it adds to a clip that has not lost it yet and stops at the maximum.
local function give_back_ammo(ammo_extension, amount)
	local pending = math.min(ammo_extension._shots_fired, amount)

	ammo_extension._shots_fired = ammo_extension._shots_fired - pending

	if amount > pending then
		ammo_extension:add_ammo(amount - pending)
	end
end

-- The ammo for the goop was used as it was loaded. When the charge ends and the glob is not fired, the ammo is given back: when the
-- player switches weapons, mounts a ladder, is grabbed, starts an interaction, and so on, and when the button is let go before the
-- shot can start. The shot is the only thing that keeps it. Its action interrupts the charge, so the reason is a new action, and the
-- action that comes next tells the shot from a switch of weapons or a skill.
mod.charge_finish_callbacks.bio = function (action, reason, data)
	local fires = reason == "new_interupting_action" and data and data.new_action == "action_one"

	if fires or not action.current_action or action.current_action.ut_charge_callback ~= "bio" then
		return
	end

	local state = goop_loads[action.owner_unit]

	if state and state.load > 0 and action.ammo_extension then
		give_back_ammo(action.ammo_extension, state.load)

		state.load = 0
	end
end

-- Starting a glob
-- Returns where a glob starts: in front of the camera, to its right and below it (utils.projectile_start)
local function start_position(position, rotation)
	return utils.projectile_start(position, rotation, CONFIG.start_forward, CONFIG.start_right, CONFIG.start_down)
end

-- A shot of the player starts at UT's offset, and the big glob has the goop that was loaded. Its scale carries the level, its speed
-- depends on the level, and its power level is the share of the biggest glob's.
mod.spawn_projectile_callbacks[TEMPLATE_NAME] = function (func, owner_unit, position, rotation, scale, angle, target_vector, speed, item_name, item_template_name, action_name, sub_action_name, is_critical_strike, power_level, ...)
	local template = rawget(Weapons, item_template_name)
	local sub_actions = template and template.actions[action_name]
	local action = sub_actions and sub_actions[sub_action_name]

	if action and action.ut_bio_shot then
		local level = action.ut_bio_charged and take_goop_load(owner_unit) or 1

		position = start_position(position, rotation)
		scale = scale_to_send(level)
		speed = action_speed(action.ut_bio_charged and charged_speed_uu(level) or CONFIG.glob_speed_uu)
		power_level = power_level * power_ratio(level)
	end

	return func(owner_unit, position, rotation, scale, angle, target_vector, speed, item_name, item_template_name, action_name, sub_action_name, is_critical_strike, power_level, ...)
end

-- Spawns a glob of the given level, moving at the given velocity (in m/s). It is used for the small globs and for the glob that drips.
local function spawn_glob(context, position, velocity, level)
	local speed = Vector3.length(velocity)
	local direction = speed > 0.001 and velocity * (1 / speed) or Vector3.down()
	local flat = Vector3.flat(direction)
	local target_vector = Vector3.length(flat) > 0.01 and Vector3.normalize(flat) or Vector3(0, 1, 0)
	local angle = math.radians_to_degrees(math.asin(math.clamp(Vector3.z(direction), -1, 1)))
	-- A rotation that looks straight up or down needs another vector to say which way is up.
	local up = math.abs(Vector3.z(direction)) > 0.99 and Vector3(0, 1, 0) or Vector3.up()

	ActionUtils.spawn_player_projectile(context.owner_unit, position, Quaternion.look(direction, up), scale_to_send(level), angle, target_vector, speed * 100, context.item_name, TEMPLATE_NAME, CHILD_ACTION_NAME, CHILD_SUB_ACTION, context.is_critical_strike, context.base_power * power_ratio(level))
end

local random_direction = utils.random_direction

-- Globs that have landed
-- Only the host keeps these. It has the enemies, and it makes the explosions. Each is { id, context, position, normal (boxes), level,
-- rand3, expire, drips, inside }. The context is who fired it: { owner_unit, item_name, is_critical_strike, base_power }, where the
-- base power is the power of a level 10 glob.
local stuck = {}

local function visuals()
	return mod.goop_visual_callbacks
end

-- Where the globs that have landed are, on every machine, by the glob's id: { level, normal, position, carrier } (the vectors boxed). A
-- player's own glob looks here to see if it flies into one (see join_flying_globs).
local landed_globs = {}

-- What a glob landed on, so that it goes where that goes (a lift, a cart): the unit, the node of the part it hit, and the glob's place and
-- the way it faces in that node's frame. Every machine follows it (follow_carriers below).
local function make_carrier(unit, node, position, normal)
	if not unit or not Unit.alive(unit) or not node or node < 0 then
		return nil
	end

	local inverse = Matrix4x4.inverse(Unit.world_pose(unit, node))

	return {
		node = node,
		normal = Vector3Box(Matrix4x4.transform_without_translation(inverse, normal)),
		position = Vector3Box(Matrix4x4.transform(inverse, position)),
		unit = unit,
	}
end

-- The network's name for a carrier: the unit's id, whether it is a unit of the level, and the node (-1 for none)
local function carrier_ids(unit, node)
	local id, is_level_unit = unit and Unit.alive(unit) and Managers.state.network:game_object_or_level_id(unit)

	if not id then
		return -1, 0, -1
	end

	return id, is_level_unit and 1 or 0, node or 0
end

local function carrier_unit(id, is_level_unit)
	return id >= 0 and Managers.state.network:game_object_or_level_unit(id, is_level_unit == 1) or nil
end

local function glob_landed(id, position, normal, level, on_unit, on_node)
	landed_globs[id] = {
		carrier = make_carrier(on_unit, on_node, position, normal),
		level = level,
		normal = Vector3Box(normal),
		position = Vector3Box(position),
	}

	visuals().land(id, position, normal, level, on_unit, on_node)
end

local function glob_merged(id, level)
	if landed_globs[id] then
		landed_globs[id].level = level
	end

	visuals().merge(id, level)
end

local function glob_ended(id)
	landed_globs[id] = nil

	visuals().stop(id)
end

mod:network_register("ut_bio_land", function (_, id, x, y, z, normal_x, normal_y, normal_z, level, on_id, on_level_unit, on_node)
	glob_landed(id, Vector3(x, y, z), Vector3(normal_x, normal_y, normal_z), level, carrier_unit(on_id or -1, on_level_unit), on_node)
end)

mod:network_register("ut_bio_merge", function (_, id, level)
	glob_merged(id, level)
end)

mod:network_register("ut_bio_end", function (_, id)
	glob_ended(id)
end)

local function end_visual(glob)
	glob_ended(glob.id)
	mod:network_send("ut_bio_end", "others", glob.id)
end

-- Returns when a glob that has been hit or has landed explodes or drips: a glob on a ceiling drips when its animation ends and
-- DripTime has passed, and any other glob explodes after RestTime.
local function rest_end_time(glob, t)
	if glob.ceiling then
		return t + CONFIG.hit_animation_time + CONFIG.drip_time
	end

	return t + CONFIG.rest_time
end

-- Makes the volume that bots avoid at a glob, or makes it again at the glob's size now.
local function stop_avoiding(glob)
	local entity_manager = Managers.state and Managers.state.entity
	local volume_system = entity_manager and entity_manager:system("volume_system")
	local handler = volume_system and volume_system.nav_tag_volume_handler

	-- The volume is gone with the level it was made in, and the game breaks on destroying one that is not there.
	if glob.avoid_volume and handler == glob.avoid_handler and handler.created_tag_volumes[glob.avoid_volume] then
		volume_system:destroy_nav_tag_volume(glob.avoid_volume)
	end

	glob.avoid_volume = nil
	glob.avoid_handler = nil
end

local function avoid_glob(glob)
	local volume_system = Managers.state.entity:system("volume_system")

	if not volume_system.nav_tag_volume_handler then
		return
	end

	stop_avoiding(glob)

	glob.avoid_volume = volume_system:create_nav_tag_volume_from_data(glob.position:unbox(), blast_radius(glob.level) + CONFIG.avoid_margin, CONFIG.avoid_layer)
	glob.avoid_handler = volume_system.nav_tag_volume_handler
end

local function blow_up(glob)
	stop_avoiding(glob)

	local context = glob.context
	local normal = glob.normal:unbox()
	local position = glob.position:unbox() + normal * 0.1
	-- The explosion looks the way the surface faces, as UT's glob does when it has landed (its effects are made along its rotation).
	local up = math.abs(Vector3.z(normal)) > 0.99 and Vector3(0, 1, 0) or Vector3.up()

	local area_damage_system = Managers.state.entity:system("area_damage_system")

	-- The game looks at where units are, and the mod's update runs before the positions are current (see utils.with_valid_positions).
	with_valid_positions(area_damage_system.create_explosion, area_damage_system, context.owner_unit, position, Quaternion.look(normal, up), "ut_bio_blast", scale_of_level(glob.level), context.item_name, context.base_power * power_ratio(glob.level), context.is_critical_strike, context.owner_unit)
	end_visual(glob)
end

-- A glob on a ceiling falls, as a glob of the same level.
local function drip(glob)
	stop_avoiding(glob)

	local context = glob.context
	local position = glob.position:unbox() + glob.normal:unbox() * 0.1
	local speed = CONFIG.drip_speed_uu * UNIT * CONFIG.speed_scale

	spawn_glob(context, position, Vector3(0, 0, -speed), glob.level)
	end_visual(glob)
end

-- BioGlob.SplashGlobs: small globs fly off the surface. They start a little off it, and fly away from it in random directions. The
-- glob that landed gives them a tenth of its velocity, reflected.
local function splash_globs(context, position, normal, landing_velocity, count, volume)
	local start = position + normal * (volume * (CONFIG.flying_collision_uu + 4) * UNIT)
	local reflected = landing_velocity and (landing_velocity - normal * (Vector3.dot(landing_velocity, normal) * 2)) * CONFIG.globling_inherit_share or Vector3.zero()

	for _ = 1, count do
		local speed_uu = CONFIG.globling_speed_uu[1] + math.random() * (CONFIG.globling_speed_uu[2] - CONFIG.globling_speed_uu[1])
		local velocity = speed_uu * UNIT * CONFIG.speed_scale * (normal + random_direction() * CONFIG.globling_random_share) + reflected

		spawn_glob(context, start, velocity, 1)
	end
end

local function is_ceiling(normal)
	return Vector3.dot(normal, Vector3.down()) > CONFIG.ceiling_dot
end

-- BioGlob.MergeWithGlob (in the state OnGround): a glob that lands in another adds its goop. What is above the biggest level is
-- thrown off as small globs.
local function merge(glob, level, t)
	local new_level = glob.level + level

	if new_level > CONFIG.max_goop_level then
		glob.rand3 = (glob.rand3 + 1) % 3

		local extra = glob.rand3

		splash_globs(glob.context, glob.position:unbox(), glob.normal:unbox(), nil, new_level - CONFIG.max_goop_level + extra, math.sqrt(glob.level))

		new_level = CONFIG.max_goop_level - extra
	end

	glob.level = new_level
	glob.drips = glob.ceiling
	glob.expire = rest_end_time(glob, t)

	avoid_glob(glob)
	glob_merged(glob.id, glob.level)
	mod:network_send("ut_bio_merge", "others", glob.id, glob.level)
end

-- Returns the glob that has landed that a glob landing at this position joins, if there is one: the nearest whose collision it
-- touches.
local function glob_to_join(position)
	local nearest, nearest_distance

	for _, glob in ipairs(stuck) do
		local distance = Vector3.distance(glob.position:unbox(), position)

		if distance <= glob_radius(glob.level) + CONFIG.flying_collision_uu * UNIT and (not nearest_distance or distance < nearest_distance) then
			nearest = glob
			nearest_distance = distance
		end
	end

	return nearest
end

-- BioGlob.Landed: a glob lands on a surface. It joins a glob that is there, or it sticks. A glob that is bigger than its core size
-- throws off the rest as small globs. landing_velocity is the glob's velocity as it hit, in m/s.
local function land(context, position, normal, landing_velocity, level, t, on_unit, on_node)
	local joined = glob_to_join(position)

	if joined then
		merge(joined, level, t)

		return
	end

	local rand3 = math.random(0, 2)
	local core = rand3 + CONFIG.max_goop_level - 3

	if level > core then
		splash_globs(context, position, normal, landing_velocity, level - core, math.sqrt(level))

		level = core
	end

	if #stuck >= CONFIG.max_stuck then
		stuck[1].expire = 0
		stuck[1].drips = false
	end

	local glob = {
		ceiling = is_ceiling(normal),
		context = context,
		-- Sent to the other machines, so it must not clash with another player's glob
		id = Application.guid(),
		inside = {},
		level = level,
		normal = Vector3Box(normal),
		position = Vector3Box(position),
		rand3 = rand3,
	}

	glob.drips = glob.ceiling
	glob.expire = rest_end_time(glob, t)
	stuck[#stuck + 1] = glob

	avoid_glob(glob)
	glob_landed(glob.id, position, normal, level, on_unit, on_node)
	mod:network_send("ut_bio_land", "others", glob.id, position.x, position.y, position.z, normal.x, normal.y, normal.z, level, carrier_ids(on_unit, on_node))
end

-- Globs that landed on something that moves go with it, on every machine. The host's own record of the glob, which the explosion and the
-- touches use, goes with it too.
mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	for id, landed in pairs(landed_globs) do
		local carrier = landed.carrier

		if carrier and Unit.alive(carrier.unit) then
			local pose = Unit.world_pose(carrier.unit, carrier.node)
			local position = Matrix4x4.transform(pose, carrier.position:unbox())
			local normal = Vector3.normalize(Matrix4x4.transform_without_translation(pose, carrier.normal:unbox()))

			if Vector3.distance(position, landed.position:unbox()) > 0.001 then
				landed.position:store(position)
				landed.normal:store(normal)
				visuals().move(id, position, normal)

				for _, glob in ipairs(stuck) do
					if glob.id == id then
						glob.position:store(position)
						glob.normal:store(normal)
					end
				end
			end
		end
	end
end

-- A player, a bot or an enemy that touches a glob that has landed makes it explode soon. This returns the units that are inside the
-- glob's collision, as a set.
local query_units = {}

local function units_touching(glob)
	local touching = {}
	local position = glob.position:unbox()
	local side = Managers.state.side:get_side_from_name("heroes")

	if not side then
		return touching
	end

	local pawn_radius = CONFIG.pawn_radius_uu * UNIT
	local pawn_height = CONFIG.pawn_height_uu * UNIT
	local radius = glob_radius(glob.level)

	local function consider(unit)
		local offset = position - Unit.world_position(unit, 0)

		if Vector3.length(Vector3.flat(offset)) <= radius + pawn_radius and Vector3.z(offset) >= -radius and Vector3.z(offset) <= pawn_height + radius then
			touching[unit] = true
		end
	end

	for _, unit in ipairs(side.PLAYER_AND_BOT_UNITS) do
		if Unit.alive(unit) and HEALTH_ALIVE[unit] then
			consider(unit)
		end
	end

	local count = AiUtils.broadphase_query(position, radius + pawn_radius + 1, query_units, side.enemy_broadphase_categories)

	for i = 1, count do
		local unit = query_units[i]

		if HEALTH_ALIVE[unit] then
			consider(unit)
		end
	end

	return touching
end

-- BioGlob.TakeDamage: a glob that something detonates explodes in 0.1 seconds. It does not drip any more.
local function detonate(glob, t)
	glob.drips = false
	glob.expire = t + CONFIG.detonation_delay
end

local function update_globs(t)
	for i = #stuck, 1, -1 do
		local glob = stuck[i]

		if not Unit.alive(glob.context.owner_unit) then
			-- The player's unit is gone, because a hero was changed or the level was left. Nothing can be made for it, because the game
			-- breaks on an explosion that has no attacker.
			table.remove(stuck, i)
			stop_avoiding(glob)
			end_visual(glob)
		else
			-- BioGlob.OnGround.ProcessTouch: a pawn that steps in sets the explosion for 0.15 seconds from now.
			local touching = units_touching(glob)

			for unit in pairs(touching) do
				if not glob.inside[unit] then
					glob.drips = false
					glob.expire = t + CONFIG.touch_detonation_delay
				end
			end

			glob.inside = touching

			if t >= glob.expire then
				table.remove(stuck, i)

				if glob.drips then
					drip(glob)
				else
					blow_up(glob)
				end
			end
		end
	end
end

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	if not Managers.player or not Managers.player.is_server or #stuck == 0 then
		return
	end

	local t = Managers.time:time("game")

	if t then
		update_globs(t)
	end
end

-- What detonates a glob: the explosions of the rocket, the flak shell, the shock ball, the shock combo and a glob (they all have
-- bDetonatesGoop in UT). A glob that the explosion reaches explodes in 0.1 seconds.
local DETONATORS = {
	ut_bio_blast = true,
	ut_bio_blast_air = true,
	ut_flak_shell_explosion = true,
	ut_rocket_explosion = true,
	ut_shock_ball_explosion = true,
	ut_shock_combo_explosion = true,
}

mod.any_explosion_callbacks.bio = function (explosion_template, position, scale)
	if not DETONATORS[explosion_template.name] or #stuck == 0 or not Managers.player.is_server then
		return
	end

	local explosion = explosion_template.explosion
	local radius = explosion and (explosion.radius or math.lerp(explosion.radius_min, explosion.radius_max, scale or 0))
	local t = Managers.time:time("game")

	if not radius or not t then
		return
	end

	for _, glob in ipairs(stuck) do
		if Vector3.distance(glob.position:unbox(), position) <= radius + glob_radius(glob.level) then
			detonate(glob, t)
		end
	end
end

-- A beam or a bolt that passes through a glob that has landed sets it off too (the shock beam, and the link gun's bolts and beam: their damage
-- types have bDetonatesGoop in UT). This is called with the two ends of what moved: the beam, or the part of the path of a bolt in the
-- last frame. Only the host does it, as it has the globs.
local function distance_to_segment(point, from, to)
	local along = to - from
	local length_squared = Vector3.dot(along, along)
	local share = length_squared > 0.0001 and math.clamp(Vector3.dot(point - from, along) / length_squared, 0, 1) or 0

	return Vector3.distance(point, from + along * share)
end

mod.bio_goop.detonate_segment = function (from, to)
	if #stuck == 0 or not Managers.player.is_server then
		return
	end

	local t = Managers.time:time("game")

	if not t then
		return
	end

	for _, glob in ipairs(stuck) do
		if distance_to_segment(glob.position:unbox(), from, to) <= glob_radius(glob.level) then
			detonate(glob, t)
		end
	end
end

mod.shock_beam_callbacks.bio = function (owner_unit, start_position, end_position)
	mod.bio_goop.detonate_segment(start_position, end_position)
end

-- Globs that hit something
-- A glob lands on the machine of the player who fired it. The host handles it. For another player, this tells the host.
mod:network_register("ut_bio_goo", function (_, owner_go_id, item_name, is_critical_strike, base_power, x, y, z, normal_x, normal_y, normal_z, velocity_x, velocity_y, velocity_z, level, on_id, on_level_unit, on_node)
	if not Managers.player.is_server then
		return
	end

	local owner_unit = Managers.state.unit_storage:unit(owner_go_id)
	local t = Managers.time:time("game")

	if not owner_unit or not Unit.alive(owner_unit) or not t then
		return
	end

	land({
		base_power = base_power,
		is_critical_strike = is_critical_strike,
		item_name = item_name,
		owner_unit = owner_unit,
	}, Vector3(x, y, z), Vector3(normal_x, normal_y, normal_z), Vector3(velocity_x, velocity_y, velocity_z), level, t, carrier_unit(on_id or -1, on_level_unit), on_node)
end)

-- The way out of the wall, floor or ceiling that a glob hits, and what it hit (the unit and the node of the part), are stored on the glob
-- before it lands, because the game gives the landing only the place.
for _, function_name in ipairs({
	"hit_level_unit",
	"hit_non_level_unit",
}) do
	mod:hook(PlayerProjectileUnitExtension, function_name, function (func, self, impact_data, hit_unit, hit_position, hit_direction, hit_normal, hit_actor, ...)
		local action = self._current_action

		if action and action.ut_bio_glob and hit_normal then
			self._ut_bio_hit_normal = Vector3Box(hit_normal)
			self._ut_bio_hit_direction = Vector3Box(hit_direction)
			self._ut_bio_hit_unit = hit_unit
			self._ut_bio_hit_node = hit_actor and Actor.node(hit_actor) or 0
		end

		return func(self, impact_data, hit_unit, hit_position, hit_direction, hit_normal, hit_actor, ...)
	end)
end

-- A glob that hit a surface lands, once.
mod.aoe_callbacks.ut_bio_glob = function (self, aoe_data, position)
	local normal_box = self._ut_bio_hit_normal

	if not normal_box or self._ut_bio_done then
		return
	end

	self._ut_bio_done = true

	local level = level_of_scale(self.scale)
	local normal = normal_box:unbox()
	local direction = self._ut_bio_hit_direction:unbox()
	local speed = (self.locomotion_extension.speed or 0) / 100
	local base_power = self.power_level / power_ratio(level)
	local velocity = direction * speed

	local on_unit, on_node = self._ut_bio_hit_unit, self._ut_bio_hit_node

	if self._is_server then
		local t = Managers.time:time("game")

		if t then
			land({
				base_power = base_power,
				is_critical_strike = self._is_critical_strike,
				item_name = self.item_name,
				owner_unit = self._owner_unit,
			}, position, normal, velocity, level, t, on_unit, on_node)
		end
	else
		mod:network_send("ut_bio_goo", "others", Managers.state.unit_storage:go_id(self._owner_unit), self.item_name, self._is_critical_strike or false, base_power, position.x, position.y, position.z, normal.x, normal.y, normal.z, velocity.x, velocity.y, velocity.z, level, carrier_ids(on_unit, on_node))
	end
end

-- BioGlob.Flying.ProcessTouch: a glob that flies into a glob that has landed joins it, wherever it touches it, and does not have to
-- reach a surface. It is landed at the glob it touched, which joins them, and it is stopped. The globs that come off a landing glob are not
-- joined, because they start inside it. Each machine checks the globs of its own player.
mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	local projectiles = next(landed_globs) and utils.flying_projectiles()

	if not projectiles then
		return
	end

	local touch_extra = CONFIG.flying_collision_uu * UNIT

	for _, projectile in ipairs(projectiles) do
		local extension = projectile.extension

		if projectile.own and extension._current_action.ut_bio_shot and not extension._ut_bio_done and not extension._stop_impacts then
			local position = Unit.world_position(projectile.unit, 0)

			for _, landed in pairs(landed_globs) do
				local landed_position = landed.position:unbox()

				if Vector3.distance(landed_position, position) <= glob_radius(landed.level) + touch_extra then
					extension._ut_bio_hit_normal = landed.normal
					extension._ut_bio_hit_direction = Vector3Box(Vector3.normalize(landed_position - position))

					mod.aoe_callbacks.ut_bio_glob(extension, nil, landed_position)
					extension:stop()

					break
				end
			end
		end
	end
end

-- A glob that hits a player, a bot or an enemy explodes there, in the air (BioGlob.Flying.ProcessTouch). The explosion goes through
-- the area damage system, which applies the damage on the host and makes the explosion on every machine.
mod.hit_enemy_callbacks.ut_bio_glob = function (func, self, is_owner, impact_data, hit_unit, hit_position, ...)
	func(self, impact_data, hit_unit, hit_position, ...)

	if is_owner and not self._ut_bio_done then
		self._ut_bio_done = true

		self:do_aoe(ExplosionTemplates.ut_bio_blast_air, hit_position, true)
	end
end

-- Explosions
-- The explosion of a glob hurts the player who fired it, as in UT, and throws every player near it. It runs on every machine. The
-- hurt is done on the machine of the player who fired, and each machine throws its own player. before.attacker_unit is the player
-- who fired.
for _, template_name in ipairs({ "ut_bio_blast", "ut_bio_blast_air" }) do
	mod.explosion_before_callbacks[template_name] = function (world, position, attacker_unit)
		return {
			attacker_unit = attacker_unit,
		}
	end

	mod.explosion_callbacks[template_name] = function (world, position, rotation, before, scale)
		local owner_unit = before and before.attacker_unit
		local level = level_of_scale(scale)
		local radius = blast_radius(level)
		local explosion = {
			max_damage_radius = radius * CONFIG.blast_full_damage_share,
			radius = radius,
		}

		if owner_unit and utils.is_local_player_unit(owner_unit) then
			utils.apply_explosion_self_damage(owner_unit, position, ITEM_KEY, explosion, blast_damage(level) * CONFIG.self_damage_share)
		end

		utils.apply_explosion_push(position, explosion, CONFIG.jump_speed * math.sqrt(level) * utils.push_scale(owner_unit))
	end
end

mod.items.set_template_changes(TEMPLATE_NAME, apply_bio_rifle)

mod.enabled_callbacks[#mod.enabled_callbacks + 1] = function ()
	packages.load_projectile_units(PROJECTILE_UNIT_TEMPLATES)
end

-- The globs are cleared when the mod is unloaded and when a level is left.
local function clear_all()
	for _, glob in ipairs(stuck) do
		stop_avoiding(glob)

		if visuals().stop then
			visuals().stop(glob.id)
		end
	end

	table.clear(landed_globs)
	table.clear(stuck)
	table.clear(goop_loads)
end

mod.unload_callbacks[#mod.unload_callbacks + 1] = clear_all
mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = clear_all
