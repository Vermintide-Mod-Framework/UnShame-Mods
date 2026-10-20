local mod = get_mod("unreal_tournament")

-- The Shock Rifle's gameplay. It is an item of its own, made on the shell of Sienna's Beam Staff (utils.template_shell).
--   Left button: fires an instant hitscan beam.
--   Right button: fires a slow ball that flies straight and explodes on impact.
--   A beam that hits a ball detonates it in a large "shock combo" explosion.
-- The skin (skin.lua) draws all of it. This file only sets what it does to the game.

local SETTING_ID = "shock_rifle"
local ITEM_KEY = "ut_shock_rifle"
local TEMPLATE_NAME = "ut_shock_rifle_template"

mod.items.register(SETTING_ID, {
	key = ITEM_KEY,
	template = TEMPLATE_NAME,
	base_item = "bw_skullstaff_beam",
	deus_copy = "deus_bw_skullstaff_beam",
	-- The careers are the Beam Staff's, plus the Necromancer, which is a DLC career that has its own staffs.
	can_wield = { "bw_scholar", "bw_adept", "bw_unchained", "bw_necromancer" },
	name = "UT2004 Shock Rifle",
	type_name = "Shock Rifle",
	-- This is UT2004's description, shortened.
	description = "The ASMD Shock Rifle has changed little since its incorporation into the Tournaments. Fire the photon beam into the slow-moving plasma charge to release the explosive energy of the anti-photons contained within its EM field.",
	keywords = { "weapon_keyword_sniper", "weapon_keyword_crowd_control", "ut_weapon_keyword_combo" },
	texts = { ut_weapon_keyword_combo = "Combo" },
	icon = "ut_shock_rifle_icon",
	icon_package = "resource_packages/unreal_tournament/icons",
	icon_materials = "ui/ut/shock_rifle_icon",
	-- The illusions are UT2004's model and UT2003's old model. UT2004 still has the old model as an option.
	skins = {
		{
			key = "ut_shock_rifle_skin_2004",
			name = "UT2004 Shock Rifle",
			default = true,
		},
		{
			key = "ut_shock_rifle_skin_2003",
			name = "UT2003 Shock Rifle",
			icon = "ut_shock_rifle_2003_icon",
			icon_materials = "ui/ut/shock_rifle_2003_icon",
		},
		-- This is UT2004's SuperShockRifle, which is the same rifle with a red chamber, beam and flashes.
		{
			key = "ut_shock_rifle_skin_instagib",
			name = "UT2004 Instagib Shock Rifle",
			description = "This version of the Shock Rifle will instantly kill most enemies, and down allies as well.",
			icon = "ut_shock_rifle_instagib_icon",
			icon_materials = "ui/ut/shock_rifle_instagib_icon",
		},
	},
})

local INSTAGIB_SKIN = "ut_shock_rifle_skin_instagib"

local CONFIG = {
	-- The multipliers of the damage and the stagger for each armor type: unarmored, armored, monsters, players, berserkers and
	-- super armor. The game's own multiplier for beams is 0 against super armor, which chaos warriors have, so a beam would do
	-- next to nothing to them.
	armor_attack = {1, 0.8, 1.5, 1, 1, 0.5},
	armor_impact = {1, 0.8, 1, 1, 1, 0.5},
	-- Beam
	beam_fire_rate = 0.7, -- UT2004 ShockBeamFire.FireRate
	beam_fire_time = 0, -- the delay between pressing fire and the shot
	beam_range = 60, -- the length of the beam when it does not hit anything
	-- Ball
	-- throw_trajectory divides the speed by 100, so this is 15 m/s. Walking is about 4 to 5 m/s, so the ball is faster than a
	-- running dodge jump, as in UT.
	ball_speed = 1500,
	-- The impact sphere, which is how easily the ball hits things (the beam hitting the ball is unrelated). An enemy is hit as a rocket
	-- hits one (utils.UT_PROJECTILE_RADIUS), with the ball's own 10 uu (ShockProjectile.CollisionRadius) added. A wall is hit by a quarter
	-- of it (the game's fireball does that), 0.125 m, where UT's is the ball's 10 uu.
	ball_radius = 10 * mod.utils.UT_UNIT + mod.utils.UT_PROJECTILE_RADIUS, -- m
	ball_visual_scale = 3, -- the size multiplier of the projectile unit
	ball_charge_level = 0.99, -- drives the projectile scale, and is kept under 1 to avoid "full charge" procs
	ball_lifetime = 10, -- UT2004 ShockProjectile.LifeSpan
	ball_fire_rate = 0.6, -- UT2004 ShockProjFire.FireRate
	ball_spawn_forward_uu = 24, -- UT2004 ShockProjFire.ProjSpawnOffset.X, which is how far ahead of the eye the ball starts
	ball_spawn_right_uu = 8, -- ProjSpawnOffset.Y, which is how far to the right the ball starts
	ball_fire_time = 0, -- the ball leaves as the button is pressed, like the beam, because ShockProjFire has no PreFireTime
	-- Combo
	combo_pick_radius = 0.6, -- how close the beam has to pass to the ball's center
	combo_max_range = 100,
	-- The damage values are relative, from UT2004 (XWeapons/ShockBeamFire.uc and ShockProjectile.uc). The beam does 45, the ball's
	-- splash does 45 (radius 150 uu) and the combo does 200 (radius 275 uu). The beam and the ball's splash do the same damage,
	-- and the combo does 200 / 45 times that.
	beam_attack_power = 0.7, -- the multiplier on the weapon's power level, which sets the damage
	beam_impact_power = 0.3, -- the same multiplier for the stagger
	combo_damage_multiplier = 200 / 45,
	-- UT2004's ShockProjectile.DamageRadius is 150, but 3 m covers a lot of a horde in a game of this scale.
	ball_explosion_radius_uu = 90,
	combo_explosion_radius_uu = 190, -- UT2004's ShockProjectile.ComboRadius is 275, which would be 5.5 m here
	explosion_full_damage_radius = 0.5, -- the damage falls off linearly from here to the radius
	-- Friendly fire is scaled to nothing on lower difficulties, so the combo's damage to the shooter is applied separately. This
	-- much is done at the center, and it falls off like the explosion.
	combo_self_damage = 100,
	combo_standard_power_level = 500, -- the power level against a beastmen standard (banner) in the combo's radius
	-- Shock jumps: the explosions throw the shooter away from them. UT's ShockProjectile.MomentumTransfer is 70000 and the combo's
	-- is 150000. The speeds below are in m/s at the center, and they fall off like the damage. They add to the speed the shooter
	-- has.
	ball_jump_speed = 8,
	combo_jump_speed = 14,
	-- The ball's explosion hurts the shooter in the same way. In UT's numbers that is half of the ball's damage, as the combo's is
	-- half of its damage.
	ball_self_damage = 18,
	-- Combo: the blast, which the skin draws, is followed by everything that died being pulled back to the center, like in UT.
	-- The ring of the game's own effect (Kruber's shockwave) bends the light behind it, which the skin's effects cannot do. One
	-- ring is played where the combo goes off, turned to face the player, at combo_distortion_scale times the effect's own size.
	combo_ring_effect = mod.effects.game_effect("fx/chr_kruber_shockwave"),
	combo_distortion_scale = 0.7,
	-- How high above the effect's origin its ring is, in meters. The effect is made to be played at a character's feet.
	combo_ring_height = 1,
	-- Bodies are thrown away from the blast first. Whatever has died and started to ragdoll in the first implosion_delay seconds
	-- is thrown once, and then everything is pulled back in.
	implosion_delay = 0.6, -- seconds after the blast before bodies start being pulled in
	implosion_duration = 0.6,
	-- The pull is like gravity. It speeds the bodies up toward the center, and they keep their own speed. They go through the
	-- center and fly off the other side when the pull ends. The pull softens near the center so there is no sudden stop or kick.
	implosion_pull = 90, -- m/s^2
	implosion_pull_softening = 1, -- m, the pull is weaker than this close to the center
	implosion_max_speed = 30, -- m/s
	-- The Instagib skin is UT2004's SuperShockRifle. Both fire modes shoot a beam (SuperShockBeamFire) that does 1000 damage
	-- (DamageMax), where the normal beam does 45. It fires every 1.1 seconds and uses no overcharge. The stagger is scaled less
	-- than the damage.
	instagib_damage = 1000,
	instagib_fire_rate = 1.1,
	instagib_impact_multiplier = 2,
	-- Overcharge: a shot costs this much of what the staff's own shots do. A combo costs this many beam shots on top of the beam
	-- shot that set it off, because UT2004's ShockProjectile.ComboAmmoCost is 3 on top of the beam's own 1 ammo.
	overcharge_scale = 0.5,
	combo_overcharge_multiplier = 3,
	-- Overheating the weapon sets off a combo at the player. It does not hurt the shooter, because the game's overheating
	-- explosion does that. There is no shot to take a power level from, so the combo is given one.
	overheat_combo_height = 1, -- m above the player
	overheat_combo_power_level = 500,
}

-- The overcharge costs are derived from the staff's own values.
local overcharge_values = PlayerUnitStatusSettings.overcharge_values

overcharge_values.ut_shock_beam = overcharge_values.beam_staff_sniper * CONFIG.overcharge_scale
overcharge_values.ut_shock_ball = overcharge_values.ut_shock_beam
overcharge_values.ut_shock_instagib = 0

-- The game already defines a gravity of 0, which the drake pistols use. Reusing it means NetworkLookup.projectile_gravity_settings
-- does not have to be extended.
local BALL_GRAVITY_SETTINGS = "drake_pistols"

-- New named data is registered below. It must exist on every peer in the same order, so everyone in the game needs the mod.

local utils = mod.utils
local effects = mod.effects
local register_explosion_template = utils.register_explosion_template

-- Spread: the beam is hitscan and should hit exactly where the crosshair is.

local function zero_numbers(tbl)
	for key, value in pairs(tbl) do
		if type(value) == "table" then
			zero_numbers(value)
		elseif type(value) == "number" then
			tbl[key] = 0
		end
	end
end

SpreadTemplates.ut_shock_beam = table.clone(SpreadTemplates.handgun)

zero_numbers(SpreadTemplates.ut_shock_beam)

-- Damage profiles (see utils.add_damage_profile)
-- The beam, the ball and the explosions share the armor modifiers, for critical hits too. They differ in their power factor (see
-- utils.lua).

-- The beam stops at the first enemy it hits, as UT's trace does. The cleave is how many enemies a shot can hurt.
local BEAM = {
	charge_value = "projectile",
	shield_break = false,
	no_stagger_damage_reduction_ranged = true,
	is_explosion = false,
	-- (the beam staff's hit reactions, and the sniper shot's hit effects)
	attack_template = "wizard_staff_beam_sniper",
	damage_type = "shot_sniper",
	attack_power = CONFIG.beam_attack_power,
	impact_power = CONFIG.beam_impact_power,
	armor_attack = CONFIG.armor_attack,
	armor_impact = CONFIG.armor_impact,
	critical_armor_attack = CONFIG.armor_attack,
	critical_armor_impact = CONFIG.armor_impact,
	cleave_attack = 0.01,
	cleave_impact = 0.01,
	boost_curve_type = "ninja_curve",
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

utils.add_damage_profile("ut_shock_beam", BEAM)
utils.add_damage_profile("ut_shock_beam_instagib", utils.damage_profile_spec(BEAM, {
	attack_power = CONFIG.beam_attack_power * CONFIG.instagib_damage / utils.UT_REFERENCE_DAMAGE,
	impact_power = CONFIG.beam_impact_power * CONFIG.instagib_impact_multiplier,
}))

-- The ball's direct hit does no damage of its own. As in UT, the damage is the explosion, which is at full strength for whatever
-- the ball hits. The direct hit only staggers, and does 1 damage so that it is not shown as blocked by armor. The cleave is kept tiny
-- so the ball detonates on the first enemy it hits.
utils.add_damage_profile("ut_shock_ball", utils.damage_profile_spec(BEAM, {
	-- (the fireball's hit reactions, and the frag grenade's hit effects)
	attack_template = "fireball",
	damage_type = "grenade",
	attack_power = utils.STAGGER_HIT_ATTACK_POWER,
	boost_curve_type = "linesman_curve",
}))

-- The explosions have no head shots or critical boost: the game's explosions have no boost curve. The cleave doesn't apply to them.
-- A glance is the explosion's edge, with the game's glancing hit reactions and effects.
local function add_explosion_profiles(name, damage_multiplier)
	local explosion = utils.damage_profile_spec(BEAM, {
		charge_value = "aoe",
		attack_template = "drakegun",
		damage_type = "grenade",
		attack_power = CONFIG.beam_attack_power * damage_multiplier,
		impact_power = CONFIG.beam_impact_power * damage_multiplier,
		cleave_attack = 1,
		cleave_impact = 1,
		boost_curve_type = false,
	})

	utils.add_damage_profile(name, explosion)
	utils.add_damage_profile(name .. "_glance", utils.damage_profile_spec(explosion, {
		attack_template = "drakegun_glance",
		damage_type = "grenade_glance",
	}))
end

add_explosion_profiles("ut_shock_ball_explosion", 1)
add_explosion_profiles("ut_shock_combo_explosion", CONFIG.combo_damage_multiplier)

-- Explosion templates
-- A plain `radius` is used instead of radius_min and radius_max, because those would make the explosion depend on the
-- projectile's scale. Setting attacker_power_level_offset to 1 makes the power level independent of the scale too.

register_explosion_template("ut_shock_ball_explosion", {
	-- Shields do not block the explosion (see the hook of create_explosion).
	ut_penetrates_shields = true,
	explosion = {
		alert_enemies = true,
		alert_enemies_radius = 10,
		attacker_power_level_offset = 1,
		damage_profile = "ut_shock_ball_explosion",
		damage_profile_glance = "ut_shock_ball_explosion_glance",
		-- The explosion has no effect or sound of its own. The skin draws and plays them (see skin_explosion_callbacks).
		-- The shooter is hurt separately. See ball_self_damage.
		ignore_attacker_unit = true,
		max_damage_radius = CONFIG.explosion_full_damage_radius,
		radius = CONFIG.ball_explosion_radius_uu * utils.UT_UNIT,
		use_attacker_power_level = true,
	},
})
register_explosion_template("ut_shock_combo_explosion", {
	ut_penetrates_shields = true,
	explosion = {
		alert_enemies = true,
		alert_enemies_radius = 30,
		attacker_power_level_offset = 1,
		damage_profile = "ut_shock_combo_explosion",
		damage_profile_glance = "ut_shock_combo_explosion_glance",
		-- The shooter is handled separately. See apply_combo_self_damage.
		ignore_attacker_unit = true,
		max_damage_radius = CONFIG.explosion_full_damage_radius,
		radius = CONFIG.combo_explosion_radius_uu * utils.UT_UNIT,
		use_attacker_power_level = true,
		camera_effect = {
			far_distance = 25,
			far_scale = 0.15,
			near_distance = 6,
			near_scale = 0.75,
			shake_name = "frag_grenade_explosion",
		},
	},
})

-- The beam's hit effect does nothing. Without this, the game would play the sound, particles and decals of the surface the beam
-- hits. The skin draws the impact instead (see mod.silent_hit_effects in hooks.lua).
local NO_HIT_EFFECT = "ut_shock_impact"

mod.silent_hit_effects[NO_HIT_EFFECT] = true

-- Weapon template

-- UT2004's refire logic (WeaponFire, Weapon.StartFire and Weapon.ReadyToFire) works like this:
--   * Each mode fires again FireRate seconds after its previous shot.
--   * A mode that starts after the other one fired also waits for the other's cooldown (NextFireTime = max(own, other's)). This
--     prevents rapidly alternating fire modes.
--   * While one fire button is held, the other mode cannot fire, because both are bModeExclusive.
--   * Holding fire repeats the shot.
-- The shot happens fire_time seconds into an action, so the delays below are measured from the start of the action to make the
-- time between the shots exact.
local BEAM_TO_BEAM = CONFIG.beam_fire_rate
local BEAM_TO_BALL = math.max(CONFIG.beam_fire_time + CONFIG.beam_fire_rate - CONFIG.ball_fire_time, 0)
local BALL_TO_BALL = CONFIG.ball_fire_rate
local BALL_TO_BEAM = math.max(CONFIG.ball_fire_time + CONFIG.ball_fire_rate - CONFIG.beam_fire_time, 0)
local BEAM_TOTAL_TIME = math.max(BEAM_TO_BEAM, BEAM_TO_BALL)
local BALL_TOTAL_TIME = math.max(BALL_TO_BALL, BALL_TO_BEAM)

local function fire_chain_entries(own_action, other_action, own_delay, other_delay)
	local own_hold = own_action .. "_hold"
	local other_hold = other_action .. "_hold"

	return {
		{
			action = own_action,
			input = own_action,
			start_time = own_delay,
			sub_action = "default",
		},
		{
			action = own_action,
			input = own_hold,
			start_time = own_delay,
			sub_action = "default",
		},
		{
			action = other_action,
			blocking_input = own_hold,
			input = other_action,
			start_time = other_delay,
			sub_action = "default",
		},
		{
			action = other_action,
			blocking_input = own_hold,
			input = other_hold,
			start_time = other_delay,
			sub_action = "default",
		},
	}
end

local function allowed_chain_actions(fire_entries, wield_start_time, reload_start_time)
	local entries = {
		{
			action = "action_wield",
			input = "action_wield",
			start_time = wield_start_time,
			sub_action = "default",
		},
		{
			action = "weapon_reload",
			input = "weapon_reload",
			start_time = reload_start_time,
			sub_action = "default",
		},
	}

	for i = 1, #fire_entries do
		entries[#entries + 1] = fire_entries[i]
	end

	return entries
end

local function build_beam_action(instagib_own_action, instagib_other_action)
	local action
	local total_time = instagib_own_action and CONFIG.instagib_fire_rate or BEAM_TOTAL_TIME

	action = {
		alert_sound_range_fire = 12,
		anim_event = "attack_shoot_beam_spark",
		charge_value = "light_attack",
		damage_profile = instagib_own_action and "ut_shock_beam_instagib" or "ut_shock_beam",
		damage_window_end = 0,
		damage_window_start = 0.1,
		fire_sound_event = "weapon_staff_fire_beam_end_shot",
		fire_time = CONFIG.beam_fire_time,
		headshot_multiplier = 2,
		-- The beam must have a hit effect (see NO_HIT_EFFECT).
		hit_effect = NO_HIT_EFFECT,
		is_spell = true,
		kind = "handgun",
		-- The Instagib beam goes through shields. The game's own handguns set this field to ignore shields too.
		ignore_shield_hit = instagib_own_action and true or nil,
		overcharge_type = instagib_own_action and "ut_shock_instagib" or "ut_shock_beam",
		reset_aim_on_attack = true,
		spread_template_override = "ut_shock_beam",
		total_time = total_time,
		ut_shock_beam = true,
		allowed_chain_actions = instagib_own_action
			and allowed_chain_actions(fire_chain_entries(instagib_own_action, instagib_other_action, total_time, total_time), 0.2, 0.2)
			or allowed_chain_actions(fire_chain_entries("action_one", "action_two", BEAM_TO_BEAM, BEAM_TO_BALL), 0.2, 0.2),
		enter_function = function (attacker_unit, input_extension, remaining_time, weapon_extension)
			input_extension:clear_input_buffer()

			return input_extension:reset_release_input()
		end,
	}

	return action
end

local function build_ball_action()
	-- The charged fireball unit is built to be scaled up. Its times_bigger setting is driven by the charge level.
	local projectile_info = table.clone(Projectiles.fireball_charged)

	projectile_info.gravity_settings = BALL_GRAVITY_SETTINGS
	projectile_info.radius = CONFIG.ball_radius
	projectile_info.times_bigger = CONFIG.ball_visual_scale
	projectile_info.unit_life_time = CONFIG.ball_lifetime

	local action

	action = {
		alert_sound_range_fire = 12,
		alert_sound_range_hit = 2,
		anim_event = "attack_shoot_fireball",
		apply_recoil = true,
		charge_value = "light_attack",
		fire_sound_event = "player_combat_weapon_staff_fireball_fire",
		fire_sound_event_parameter = "drakegun_charge_fire",
		fire_sound_on_husk = true,
		fire_time = CONFIG.ball_fire_time,
		forced_charge_level = CONFIG.ball_charge_level,
		-- The game starts a charged projectile at the player's eye. UT's ProjSpawnOffset puts the ball ahead of the eye and a
		-- little to the right.
		fire_pos_rot = function (_, first_person_unit)
			local position = Unit.world_position(first_person_unit, 0)
			local rotation = Unit.local_rotation(first_person_unit, 0)

			position = position + Quaternion.forward(rotation) * (CONFIG.ball_spawn_forward_uu * utils.UT_UNIT)
				+ Quaternion.right(rotation) * (CONFIG.ball_spawn_right_uu * utils.UT_UNIT)

			return position, rotation
		end,
		-- There is no hit_effect, because it would play the game's fire of a fireball that hits something. The skin draws the
		-- ball's impact (see skin_explosion_callbacks).
		is_spell = true,
		kind = "charged_projectile",
		overcharge_type = "ut_shock_ball",
		speed = CONFIG.ball_speed,
		total_time = BALL_TOTAL_TIME,
		ut_shock_ball = true,
		-- A shield reflects it (see mod.shield.reflect)
		ut_reflective = true,
		ut_aoe_callback = "shock_ball",
		ut_init_callback = "shock_ball",
		ut_init_flow_event_filter = "shock_ball",
		allowed_chain_actions = allowed_chain_actions(fire_chain_entries("action_two", "action_one", BALL_TO_BALL, BALL_TO_BEAM), 0.3, 0.3),
		enter_function = function (attacker_unit, input_extension, remaining_time, weapon_extension)
			input_extension:clear_input_buffer()

			return input_extension:reset_release_input()
		end,
		projectile_info = projectile_info,
		impact_data = {
			damage_profile = "ut_shock_ball",
			aoe = ExplosionTemplates.ut_shock_ball_explosion,
		},
		recoil_settings = {
			climb_duration = 0.2,
			horizontal_climb = 0,
			restore_duration = 0.2,
			vertical_climb = -1,
			climb_function = math.easeInCubic,
			restore_function = math.ease_out_quad,
		},
	}

	return action
end

-- The two sets of fire modes, normal and Instagib, and which one the template has now (see sync_instagib_actions)
local fire_modes = {}

-- Venting the heat: the Beam Staff's. Holding the reload button vents it over 3 seconds while the player is slowed, when there is heat.
local function has_heat(action_user)
	local overcharge_extension = ScriptUnit.extension(action_user, "overcharge_system")

	return overcharge_extension:get_overcharge_value() ~= 0
end

local function build_vent()
	return {
		kind = "charge",
		anim_event = "cooldown_start",
		anim_end_event = "attack_finished",
		anim_end_event_condition_func = function (unit, end_reason)
			return end_reason ~= "new_interupting_action"
		end,
		charge_effect_material_name = "Fire",
		charge_effect_material_variable_name = "intensity",
		charge_sound_name = "player_combat_weapon_staff_cooldown",
		charge_sound_parameter_name = "drakegun_charge_fire",
		charge_sound_stop_event = "stop_player_combat_weapon_staff_cooldown",
		charge_sound_switch = "projectile_charge_sound",
		charge_time = 3,
		do_not_validate_with_hold = true,
		hold_input = "weapon_reload_hold",
		minimum_hold_time = 0.5,
		uninterruptible = true,
		vent_overcharge = true,
		total_time = math.huge,
		buff_data = {
			{
				buff_name = "planted_fast_decrease_movement",
				external_multiplier = 0.2,
				start_time = 0,
				end_time = math.huge,
			},
		},
		enter_function = function (attacker_unit, input_extension)
			input_extension:reset_release_input()
			input_extension:clear_input_buffer()
		end,
		allowed_chain_actions = {
			{
				action = "action_wield",
				input = "action_wield",
				start_time = 0.2,
				sub_action = "default",
			},
		},
		condition_func = has_heat,
		chain_condition_func = has_heat,
	}
end

-- Makes the rifle on the shell of the Beam Staff (utils.template_shell): everything that is not the staff's animations, models and
-- sounds is set here
local function apply_shock_rifle(template)
	utils.template_shell(template)

	-- The chart of the item's stats, from 0 to 7. The beam is the normal attack, and the ball is the heavy one.
	template.weapon_diagram = {
		light_attack = {
			[DamageTypes.ARMOR_PIERCING] = 5,
			[DamageTypes.CLEAVE] = 1,
			[DamageTypes.SPEED] = 5,
			[DamageTypes.STAGGER] = 2,
			[DamageTypes.DAMAGE] = 5,
		},
		heavy_attack = {
			[DamageTypes.ARMOR_PIERCING] = 3,
			[DamageTypes.CLEAVE] = 4,
			[DamageTypes.SPEED] = 6,
			[DamageTypes.STAGGER] = 4,
			[DamageTypes.DAMAGE] = 4,
		},
	}

	local actions = template.actions

	-- The beam and the ball. Inspecting is the staff's, kept by the shell.
	actions.action_one = {
		default = build_beam_action(),
	}
	actions.action_two = {
		default = build_ball_action(),
	}
	actions.weapon_reload = {
		default = build_vent(),
	}
	-- The game's own wielding
	actions.action_wield = table.clone(ActionTemplates.wield)

	utils.set_actions_lookup_data(actions, TEMPLATE_NAME)

	-- The Instagib skin's actions put the beam on both buttons (see sync_instagib_actions).
	fire_modes.normal = {
		action_one = actions.action_one,
		action_two = actions.action_two,
	}
	fire_modes.instagib = {
		action_one = {
			default = build_beam_action("action_one", "action_two"),
		},
		action_two = {
			default = build_beam_action("action_two", "action_one"),
		},
	}
	fire_modes.instagib_active = false

	utils.set_actions_lookup_data(fire_modes.instagib, TEMPLATE_NAME)

	-- The staff's heat: its warning sound and how soon it cools and how fast. Overheating sets off a combo (overheat_callbacks).
	template.overcharge_data = {
		explosion_template = "overcharge_explosion_brw",
		hit_overcharge_threshold_sound = "ui_special_attack_ready",
		overcharge_threshold = 10,
		overcharge_value_decrease_rate = 1,
		time_until_overcharge_decreases = 0.5,
	}

	-- How bots use it: the staff's aim, at the head. A bot presses the button (it has no charged shot) and doesn't shoot through an
	-- enemy in the way. A bot shoots only the enemies its ranged weapon is good against (BTConditions.has_target_and_ammo_greater_than):
	-- the Beam Staff's infantry, berserkers, specials and armour, and bosses and super armour, which bots.lua sets off combos at. The
	-- charged shot's values are the staff's, which nothing uses.
	local effective_against = bit.bor(BreedCategory.Infantry, BreedCategory.Berserker, BreedCategory.Special, BreedCategory.Armored, BreedCategory.Boss, BreedCategory.SuperArmor)

	template.attack_meta_data = {
		aim_at_node = "j_head",
		aim_at_node_charged = "j_spine1",
		can_charge_shot = false,
		charge_when_obstructed = true,
		charge_when_outside_max_range_charged = false,
		fire_input = "fire",
		ignore_enemies_for_obstruction = false,
		ignore_enemies_for_obstruction_charged = false,
		max_range = 50,
		max_range_charged = 6,
		minimum_charge_time = 0.21,
		obstruction_fuzzyness_range = 1,
		obstruction_fuzzyness_range_charged = 6,
		aim_data = {
			max_radius_pseudo_random_c = 0.0557,
			min_radius_pseudo_random_c = 0.94737,
			min_radius = math.pi / 72,
			max_radius = math.pi / 16,
		},
		aim_data_charged = {
			max_radius_pseudo_random_c = 0.01475,
			min_radius_pseudo_random_c = 0.0557,
			min_radius = math.pi / 72,
			max_radius = math.pi / 16,
		},
		effective_against = effective_against,
		effective_against_charged = 0,
		effective_against_combined = effective_against,
		-- This tells the bot shooting that this is the Shock Rifle (see bots.lua).
		ut_shock = true,
	}

	-- What the game's talents, traits and properties take it for: the staff it is a copy of
	template.buff_type = "RANGED"
	template.weapon_type = "FIRE_STAFF"

	-- Dodging, the crosshair (its arrows) and the spread: the staff's (the beam has none of its own, see ut_shock_beam)
	template.buffs = {
		change_dodge_distance = {
			external_optional_multiplier = 1,
		},
		change_dodge_speed = {
			external_optional_multiplier = 1,
		},
	}
	template.crosshair_style = "arrows"
	template.default_spread_template = "spear"

	-- The aim assist for a controller: the staff's
	template.aim_assist_settings = {
		always_auto_aim = true,
		base_multiplier = 0,
		effective_max_range = 30,
		max_range = 50,
		no_aim_input_multiplier = 0,
		target_node = "j_spine1",
		breed_scalars = {
			skaven_clan_rat = 1,
			skaven_slave = 1,
			skaven_storm_vermin = 1,
		},
	}

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

	-- The ball's projectile unit has to be loaded when the staff is wielded.
	template.required_projectile_unit_templates.fireball_charged = false
end

-- Shock combo: a beam passing through a live shock ball detonates it.

-- What the beam hits first among the hits of its ray. The beam stops at that hit, as UT's trace does.
local first_beam_hit = utils.first_beam_hit

-- Returns the ball the beam gets to before it hits anything, and how far along the beam the ball is. The blocker_distance is how
-- far the beam goes, which is up to the first thing it hits. The balls of every player count, the shooter's and the others'. The
-- projectile system keeps a list of the projectiles this machine made, which are the shooter's. The others' balls are copies of
-- units that are on their machines, and they are found among the extensions of the copies.
local function find_ball_hit_by_beam(origin, direction, blocker_distance)
	local projectile_system = Managers.state.entity:system("projectile_system")
	local wall_distance = blocker_distance or CONFIG.combo_max_range
	local best_unit, best_distance

	local function consider(projectile_unit, extension)
		local action = Unit.alive(projectile_unit) and extension._current_action

		-- A ball that has hit something has its impacts stopped. The field is the same on the unit and on its copy.
		if action and action.ut_shock_ball and not extension._stop_impacts then
			local ball_position = POSITION_LOOKUP[projectile_unit]
			local to_ball = ball_position - origin
			local along = Vector3.dot(to_ball, direction)

			if along > 0 and along < wall_distance then
				local closest_point = origin + direction * along
				local miss_distance = Vector3.length(ball_position - closest_point)

				if miss_distance <= CONFIG.combo_pick_radius and (not best_distance or along < best_distance) then
					best_unit = projectile_unit
					best_distance = along
				end
			end
		end
	end

	for _, projectiles in pairs(projectile_system.player_projectile_units) do
		for projectile_unit, _ in pairs(projectiles) do
			local extension = Unit.alive(projectile_unit) and ScriptUnit.has_extension(projectile_unit, "projectile_system")

			if extension then
				consider(projectile_unit, extension)
			end
		end
	end

	for projectile_unit, extension in pairs(Managers.state.entity:get_entities("PlayerProjectileHuskExtension")) do
		consider(projectile_unit, extension)
	end

	return best_unit, best_distance
end

local function apply_combo_self_damage(owner_unit, position, item_name)
	local explosion = ExplosionTemplates.ut_shock_combo_explosion.explosion

	utils.apply_explosion_self_damage(owner_unit, position, item_name, explosion, CONFIG.combo_self_damage)
end

-- The ball's explosion hurts the shooter. The ball's do_aoe is also what makes the combo go off, and the two are told apart by
-- the explosion template they are given.
mod.aoe_callbacks.shock_ball = function (self, aoe_data, position)
	if aoe_data ~= ExplosionTemplates.ut_shock_ball_explosion or self._ut_shock_ball_exploded then
		return
	end

	self._ut_shock_ball_exploded = true

	local explosion = ExplosionTemplates.ut_shock_ball_explosion.explosion

	utils.apply_explosion_self_damage(self._owner_unit, position, self.item_name, explosion, CONFIG.ball_self_damage)
end

-- The ball and the combo throw every player near them.
mod.explosion_push_speeds.ut_shock_ball_explosion = function ()
	return CONFIG.ball_jump_speed
end

mod.explosion_push_speeds.ut_shock_combo_explosion = function ()
	return CONFIG.combo_jump_speed
end

-- Another player's ball is a copy on this machine. The combo is the shooter's. It goes through the area damage system, which
-- applies the damage on the server with the shooter as the attacker. The player whose ball it is gets told to end it on their
-- machine, where it flies.
mod:network_register("ut_shock_ball_stop", function (_, ball_go_id)
	local ball_unit = Managers.state.unit_storage:unit(ball_go_id)
	local extension = ball_unit and Unit.alive(ball_unit) and ScriptUnit.has_extension(ball_unit, "projectile_system")

	-- Only the real unit can be told to stop, not its copies.
	if extension and extension.are_impacts_stopped then
		extension:stop()
	end
end)

local function detonate_ball(projectile_unit, shooter_unit)
	local extension = ScriptUnit.extension(projectile_unit, "projectile_system")
	local position = POSITION_LOOKUP[projectile_unit]
	local ball_owner_unit = extension._owner_unit

	if ball_owner_unit == shooter_unit then
		-- The network_sync argument makes the explosion go through the area damage system, which also applies damage on the
		-- server.
		extension:do_aoe(ExplosionTemplates.ut_shock_combo_explosion, position, true)
	else
		local rotation = Unit.local_rotation(projectile_unit, 0)

		Managers.state.entity:system("area_damage_system"):create_explosion(shooter_unit, position, rotation, ExplosionTemplates.ut_shock_combo_explosion.name, extension.scale, extension.item_name, extension.power_level, extension._is_critical_strike, shooter_unit)

		local ball_owner = Managers.player:owner(ball_owner_unit)

		if ball_owner then
			mod:network_send("ut_shock_ball_stop", ball_owner.peer_id, Managers.state.unit_storage:go_id(projectile_unit))
		end
	end

	apply_combo_self_damage(shooter_unit, position, extension.item_name)

	local overcharge_extension = ScriptUnit.extension(shooter_unit, "overcharge_system")

	overcharge_extension:add_charge(overcharge_values.ut_shock_beam * CONFIG.combo_overcharge_multiplier)
	extension:stop()
end

-- Combo implosion: after the blast, the ragdolls of whatever died are pulled toward the center and go past it. This runs on every
-- peer, because create_explosion is called on all of them for networked explosions and ragdoll physics is simulated locally on
-- each.

local implosions = {}

local function start_implosion(world, position, attacker_unit)
	local radius = ExplosionTemplates.ut_shock_combo_explosion.explosion.radius

	-- This ring bends the light as the combo goes off. It is turned to face the player as it starts, so it is seen from the front.
	effects.play_facing(world, CONFIG.combo_ring_effect, position, CONFIG.combo_distortion_scale, CONFIG.combo_ring_height)

	-- The skin draws the explosion itself (see skin_explosion_callbacks).
	implosions[#implosions + 1] = {
		position = Vector3Box(position),
		push_scale = utils.push_scale(attacker_unit),
		blasted = {},
		-- This holds the direction each body was from the center when it was first pulled, and whether it has gone past the
		-- center.
		pulled = {},
		radius = radius,
		start_t = Managers.time:time("game"),
		units = utils.units_in_radius(world, position, radius),
		world = world,
	}
end

-- Returns where a ragdoll is, which is the position of its first part that physics moves. Returns nil if it is not a ragdoll yet.
local function ragdoll_position(unit)
	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		if actor and utils.moved_by_physics(actor) then
			return Actor.position(actor)
		end
	end
end

local function pull_ragdoll(unit, center, dt)
	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		-- (the parts that the animation moves are left alone: utils.moved_by_physics)
		if actor and utils.moved_by_physics(actor) then
			local offset = center - Actor.position(actor)
			local distance = Vector3.length(offset)
			local pull = offset * (CONFIG.implosion_pull / math.max(distance, CONFIG.implosion_pull_softening))
			local velocity = Actor.velocity(actor) + pull * dt
			local speed = Vector3.length(velocity)

			if speed > CONFIG.implosion_max_speed then
				velocity = velocity * (CONFIG.implosion_max_speed / speed)
			end

			Actor.set_velocity(actor, velocity)
		end
	end
end

local function clear_implosions()
	for i = #implosions, 1, -1 do
		implosions[i] = nil
	end
end

local function update_implosions(dt)
	local t = Managers.time:time("game")

	for i = #implosions, 1, -1 do
		local implosion = implosions[i]
		local age = t - implosion.start_t
		local center = implosion.position:unbox()

		if age >= CONFIG.implosion_delay + CONFIG.implosion_duration then
			table.remove(implosions, i)
		elseif age < CONFIG.implosion_delay then
			-- Blast phase: the damage has been applied, so throw out what died.
			for unit in pairs(implosion.units) do
				if not Unit.alive(unit) then
					implosion.units[unit] = nil
				elseif not HEALTH_ALIVE[unit] and not implosion.blasted[unit] and utils.blast_ragdoll(unit, center, nil, nil, implosion.push_scale) then
					implosion.blasted[unit] = true
				end
			end
		else
			-- Pull phase: what died is pulled back to the center.
			for unit in pairs(implosion.units) do
				if not Unit.alive(unit) then
					implosion.units[unit] = nil
				elseif not HEALTH_ALIVE[unit] then
					-- A body that has gone past the center is let go and is not pulled back.
					local body_position = ragdoll_position(unit)

					if body_position then
						local offset = body_position - center
						local state = implosion.pulled[unit]

						if not state then
							local distance = Vector3.length(offset)

							state = {
								direction = Vector3Box(distance > 0.01 and offset * (1 / distance) or Vector3.up()),
							}
							implosion.pulled[unit] = state
						end

						if not state.passed and Vector3.dot(offset, state.direction:unbox()) < 0 then
							state.passed = true
						end

						if not state.passed then
							pull_ragdoll(unit, center, dt)
						end
					end
				end
			end
		end
	end
end

-- One hook runs the weapons' explosions by their names on every peer.
-- This collects the enemies that are alive in the combo's radius as it goes off. The combo's damage is instant, and the host
-- applies it, so the ones that are not alive afterwards were killed by it.
mod.explosion_before_callbacks.ut_shock_combo_explosion = function (world, impact_position, attacker_unit)
	local alive = {}

	for unit in pairs(utils.units_in_radius(world, impact_position, ExplosionTemplates.ut_shock_combo_explosion.explosion.radius)) do
		if HEALTH_ALIVE[unit] then
			alive[#alive + 1] = unit
		end
	end

	return {
		alive = alive,
		attacker_unit = attacker_unit,
	}
end

-- The combo damages the beastmen standards (banners) in its radius. The beam does not, because a standard drops its damage.
local function blow_up_standards(impact_position, attacker_unit)
	mod.standards.blow_up(impact_position, attacker_unit, ExplosionTemplates.ut_shock_combo_explosion.explosion.radius, DamageProfileTemplates.ut_shock_combo_explosion, CONFIG.combo_standard_power_level, ITEM_KEY)
end

mod.explosion_callbacks.ut_shock_combo_explosion = function (world, impact_position, _, before)
	start_implosion(world, impact_position, before.attacker_unit)

	local killed = {}

	for _, unit in ipairs(before.alive) do
		if not HEALTH_ALIVE[unit] then
			killed[#killed + 1] = unit
		end
	end

	for _, callback in pairs(mod.shock_combo_callbacks) do
		callback(before.attacker_unit, killed)
	end

	blow_up_standards(impact_position, before.attacker_unit)
end

-- The skin draws the beam of the player who fires (see shock_beam_callbacks). Where the beam ends is sent to the other players,
-- who see it come from the staff of the player's character. A piece of the beam that a shield reflected (start_position is given)
-- starts where it was reflected.
local function spawn_trail(action, end_position, hit_normal, start_position)
	local weapon_unit = action.weapon_unit
	local reflected = start_position ~= nil

	start_position = start_position or Unit.world_position(weapon_unit, Unit.node(weapon_unit, "fx_muzzle"))

	for _, callback in pairs(mod.shock_beam_callbacks) do
		callback(action.owner_unit, start_position, end_position, hit_normal, reflected)
	end

	local go_id = Managers.state.unit_storage:go_id(action.owner_unit)

	if reflected then
		mod:network_send("ut_shock_trail", "others", go_id, Vector3.x(end_position), Vector3.y(end_position), Vector3.z(end_position), Vector3.x(hit_normal), Vector3.y(hit_normal), Vector3.z(hit_normal), Vector3.x(start_position), Vector3.y(start_position), Vector3.z(start_position))
	else
		mod:network_send("ut_shock_trail", "others", go_id, Vector3.x(end_position), Vector3.y(end_position), Vector3.z(end_position), Vector3.x(hit_normal), Vector3.y(hit_normal), Vector3.z(hit_normal))
	end
end

mod:network_register("ut_shock_trail", function (_, owner_go_id, x, y, z, normal_x, normal_y, normal_z, start_x, start_y, start_z)
	local unit = Managers.state.unit_storage:unit(owner_go_id)

	if start_x and unit then
		for _, callback in pairs(mod.shock_beam_callbacks) do
			callback(unit, Vector3(start_x, start_y, start_z), Vector3(x, y, z), Vector3(normal_x, normal_y, normal_z), true)
		end

		return
	end

	local inventory_extension = unit and ScriptUnit.has_extension(unit, "inventory_system")
	local equipment = inventory_extension and inventory_extension:equipment()
	-- The staff is the right hand's unit, and the left hand's unit is the fireball's effect. The game's own beam looks for the
	-- staff the same way.
	local weapon_unit = equipment and (equipment.right_hand_wielded_unit_3p or equipment.left_hand_wielded_unit_3p)

	if not weapon_unit or not Unit.alive(weapon_unit) then
		return
	end

	local muzzle_position = Unit.world_position(weapon_unit, Unit.node(weapon_unit, "fx_muzzle"))

	for _, callback in pairs(mod.shock_beam_callbacks) do
		callback(unit, muzzle_position, Vector3(x, y, z), Vector3(normal_x, normal_y, normal_z))
	end
end)

-- The Instagib skin changes how the weapon fires, but every Shock Rifle shares one template. So the Instagib fire modes are only
-- used while this player's wielded weapon has the skin. Other players' actions are not run on this machine.
local function sync_instagib_actions()
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not template or not fire_modes.instagib then
		return
	end

	-- Skip this until there is a network game, because asking the engine for this peer's id is an error in the menus.
	local player = Managers.player and Managers.player:local_player_safe()
	local unit = player and player.player_unit
	local wanted = unit ~= nil and Unit.alive(unit) and utils.wielded_template_name(unit) == TEMPLATE_NAME and utils.wielded_skin(unit) == INSTAGIB_SKIN

	if wanted == fire_modes.instagib_active then
		return
	end

	fire_modes.instagib_active = wanted

	local actions = wanted and fire_modes.instagib or fire_modes.normal

	template.actions.action_one = actions.action_one
	template.actions.action_two = actions.action_two
end

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	update_implosions(dt)
	sync_instagib_actions()
end

-- Kills by the Instagib skin dismember the enemy. The game checks the attacker's buffs for the "bloody mess" perk when deciding
-- that (GenericHitReactionExtension), so the perk is reported while the skin's weapon is wielded.
mod:hook(BuffExtension, "has_buff_perk", function (func, self, perk_name)
	if perk_name == "bloody_mess" and utils.wielded_template_name(self._unit) == TEMPLATE_NAME and utils.wielded_skin(self._unit) == INSTAGIB_SKIN then
		return true
	end

	return func(self, perk_name)
end)

local packages = utils.package_holder("unreal_tournament")

-- The overheating explosion is the whole combo, with the blast and the pulling in of what died. The game's own overheating
-- explosion hurts the player, and it is kept.
mod.overheat_callbacks[TEMPLATE_NAME] = function (state, item_data)
	local unit = state.unit
	local position = Unit.world_position(unit, 0) + Vector3(0, 0, CONFIG.overheat_combo_height)

	-- The explosion goes through the area damage system, which also tells the other peers and applies the damage on the server.
	Managers.state.entity:system("area_damage_system"):create_explosion(unit, position, Quaternion.identity(), "ut_shock_combo_explosion", 1, item_data.name, CONFIG.overheat_combo_power_level, false, unit)
end

-- The weapon's package list is built when the staff's packages are loaded, which may be before this mod patched the template.
-- Spawning a projectile unit that is not loaded crashes the game. So the mod holds its own reference to the ball's unit while it
-- is enabled.
mod.items.set_template_changes(TEMPLATE_NAME, apply_shock_rifle)

mod.enabled_callbacks[#mod.enabled_callbacks + 1] = function ()
	packages.load_projectile_units({"fireball_charged"})
end

-- This runs when the mod is switched off or unloaded. The template goes back to the Beam Staff's (items.lua), so the fire modes are
-- forgotten.
local function disable_shock_rifle()
	table.clear(fire_modes)
	clear_implosions()
end

mod.disabled_callbacks[#mod.disabled_callbacks + 1] = disable_shock_rifle
mod.unload_callbacks[#mod.unload_callbacks + 1] = disable_shock_rifle

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	clear_implosions()
end

mod.handgun_start_callbacks.shock = function (self, new_action)
	self._ut_combo_checked = not new_action.ut_shock_beam
end

local function beam_ray(physics_world, origin, direction)
	return PhysicsWorld.immediate_raycast_actors(physics_world, origin, direction, "static_collision_filter", "filter_player_ray_projectile_static_only", "dynamic_collision_filter", "filter_player_ray_projectile_ai_only", "dynamic_collision_filter", "filter_player_ray_projectile_hitbox_only")
end

-- The way the beam goes, as UT's InstantFire.DoTrace: from the eye to the first thing it hits, or to a ball it gets to before that,
-- which goes off. If it hits nothing, it goes on to its range. A player's shield that it gets to first reflects it, and it goes on
-- from there the way that player looks (mod.shield.reflect), up to max_reflections times. Each piece of the way is { origin,
-- direction, hits: the hits of its ray before where it ends, which are what it damages, end_position, hit_normal: the zero vector
-- if it ends on no surface, ball_unit: the ball it sets off }. The first piece's hits can be given, as the game's shot made them.
-- A reflection costs the shield's stamina, so this is done once a shot.
local function trace_beam(owner_unit, physics_world, origin, direction, hits)
	local pieces = {}
	local ignore_unit

	for reflection = 0, mod.shield.max_reflections do
		hits = hits or beam_ray(physics_world, origin, direction)

		local hit = first_beam_hit(hits, owner_unit, ignore_unit)
		local ball_unit, ball_distance = find_ball_hit_by_beam(origin, direction, hit and hit[2])
		local length = ball_distance or hit and hit[2] or CONFIG.beam_range
		local shield_position, shield_distance, shield_direction, shield_unit

		if reflection < mod.shield.max_reflections then
			shield_position, shield_distance, shield_direction, shield_unit = mod.shield.reflect(origin, origin + direction * length, 0, owner_unit, ignore_unit, reflection > 0)
		end

		-- (the hits before a ball or a shield: the game's shot itself stops at the first thing it hits)
		local reached = shield_distance or ball_distance or math.huge
		local piece_hits = {}

		for i = 1, #(hits or {}) do
			if hits[i][2] < reached and Actor.unit(hits[i][4]) ~= ignore_unit then
				piece_hits[#piece_hits + 1] = hits[i]
			end
		end

		-- (the beam ends a little short of what it hits, as the game's own beam does)
		local end_position = shield_position or ball_unit and origin + direction * ball_distance or hit and hit[1] - direction * 0.15 or origin + direction * CONFIG.beam_range
		local hit_normal = not shield_position and not ball_unit and hit and hit[3] or Vector3.zero()

		pieces[#pieces + 1] = {
			ball_unit = not shield_position and ball_unit or nil,
			direction = Vector3Box(direction),
			end_position = Vector3Box(end_position),
			hit_normal = Vector3Box(hit_normal),
			hits = piece_hits,
			origin = Vector3Box(origin),
		}

		if not shield_position then
			break
		end

		origin, direction, ignore_unit, hits = shield_position, shield_direction, shield_unit, nil
	end

	return pieces
end

-- The way of each player's last shot, from the game's shot (below) to the end of the action's update, which draws it
local beam_pieces = {}

mod.handgun_update_callbacks.shock = function (self)
	if self._ut_combo_checked or self.state == "waiting_to_shoot" then
		return
	end

	self._ut_combo_checked = true

	local owner_unit = self.owner_unit
	local pieces = beam_pieces[owner_unit]

	beam_pieces[owner_unit] = nil

	-- (the game gives the shot to process_projectile_hit only if its ray hit something)
	if not pieces then
		local first_person_extension = ScriptUnit.extension(owner_unit, "first_person_system")
		local origin, rotation = first_person_extension:get_projectile_start_position_rotation()

		pieces = trace_beam(owner_unit, self.physics_world, origin, Quaternion.forward(rotation))
	end

	-- (a reflected piece is damaged here, as the same shot: see the hook below)
	local reflected_action = setmetatable({
		ut_reflected_beam = true,
	}, {
		__index = self.current_action,
	})

	for i, piece in ipairs(pieces) do
		if i > 1 then
			DamageUtils.process_projectile_hit(self.world, self.item_name, owner_unit, self.is_server, piece.hits, reflected_action, piece.direction:unbox(), true, nil, nil, self._is_critical_strike, self.power_level)
		end

		spawn_trail(self, piece.end_position:unbox(), piece.hit_normal:unbox(), i > 1 and piece.origin:unbox() or nil)

		if piece.ball_unit and Unit.alive(piece.ball_unit) then
			detonate_ball(piece.ball_unit, owner_unit)
		end
	end
end

-- The game's shot damages what the first piece of the beam's way gets to: no further than a ball, which goes off and spends the
-- beam, or a shield, which sends it on. The rest of the way is kept for the action's update, which draws it and damages the rest.
mod:hook(DamageUtils, "process_projectile_hit", function (func, world, damage_source, owner_unit, is_server, raycast_result, current_action, direction, ...)
	if current_action.ut_shock_beam and not rawget(current_action, "ut_reflected_beam") and raycast_result then
		local first_person_extension = ScriptUnit.has_extension(owner_unit, "first_person_system")
		local origin = first_person_extension and first_person_extension:get_projectile_start_position_rotation()

		if origin then
			local pieces = trace_beam(owner_unit, World.get_data(world, "physics_world"), origin, direction, raycast_result)

			beam_pieces[owner_unit] = pieces
			raycast_result = pieces[1].hits
		end
	end

	return func(world, damage_source, owner_unit, is_server, raycast_result, current_action, direction, ...)
end)
