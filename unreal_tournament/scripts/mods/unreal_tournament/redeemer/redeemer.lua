local mod = get_mod("unreal_tournament")

-- Redeemer: a copy of the Trollhammer Torpedo with its shot replaced. The numbers come from UT2004 (XWeapons/Redeemer, RedeemerFire,
-- RedeemerProjectile and RedeemerAmmo).
--   Left button: fires a slow missile that flies straight until it hits something, and there it makes a nuclear blast: six waves that
--       reach further and further out over 1.3 seconds, each hurting everything in its reach.
--   Right button: the base weapon's block. UT's second mode steers the missile from its own view (RedeemerGuidedFire), which is not made.
-- It holds one missile, as UT's does.
-- The skin (skin.lua) draws all of it, and this file only sets what it does to the game.

local utils = mod.utils
local register_damage_profile = utils.register_damage_profile
local register_explosion_template = utils.register_explosion_template
local make_flat = utils.make_flat
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for

local DESCRIPTION = "The first time you witness this miniature nuclear device in action, you'll agree it is the most powerful weapon in the Tournament. Launch a slow-moving but utterly devastating missile, but make sure you're out of its impressive blast radius before it impacts."

local SETTING_ID = "redeemer"
local ITEM_KEY = "ut_redeemer"
local TEMPLATE_NAME = "ut_redeemer_template"

mod.items.register(SETTING_ID, {
	key = ITEM_KEY,
	template = TEMPLATE_NAME,
	base_item = "dr_deus_01",
	deus_copy = "deus_dr_deus_01",
	name = "UT2004 Redeemer",
	type_name = "Redeemer",
	description = DESCRIPTION,
	keywords = { "weapon_keyword_high_damage", "weapon_keyword_crowd_control", "weapon_keyword_armour_piercing" },
	icon = "ut_redeemer_icon",
	icon_package = "resource_packages/unreal_tournament/icons",
	icon_materials = "ui/ut/redeemer_icon",
})

local CONFIG = {
	-- RedeemerProjectile.Speed is 1000 units a second. The Rocket Launcher's 1350 is 2200 here (the action's unit is m/s * 100), so
	-- this is the same share of it.
	missile_speed = 2200 * 1000 / 1350,
	missile_lifetime = 20, -- seconds, LifeSpan
	missile_radius = 24, -- UT units, CollisionRadius
	-- The game's gravity setting with the least gravity. UT's missile flies straight (PHYS_Projectile).
	missile_gravity_settings = "spark",
	-- RedeemerAmmo.MaxAmmo. All the ammo is the clip, so there is no reload.
	max_ammo = 1,
	-- RedeemerFire.FireRate
	fire_interval = 1, -- seconds
	-- RedeemerProjectile's blast (state Dying): HurtRadius six times, each with the whole Damage (250) and a radius that grows from 0.125
	-- of DamageRadius (2000 units) to all of it, the first at once and the others 0.5, 0.7, 0.9, 1.1 and 1.3 s after. The Rocket
	-- Launcher's damage and radius are reduced from UT's (90 to 60, and 220 units to 150), and these are reduced in the same way.
	damage = 250 * 60 / 90,
	radius_uu = 2000 * 150 / 220,
	wave_radii = { 0.125, 0.3, 0.475, 0.65, 0.825, 1 }, -- shares of the radius
	wave_times = { 0, 0.5, 0.7, 0.9, 1.1, 1.3 }, -- seconds after the hit
	-- HurtRadius falls off with the distance over the whole radius, from full damage at the center
	full_damage_radius = 0, -- share of each wave's radius
	-- The blast hurts the player who fired it (HurtRadius hurts everyone). This is the damage at the center, reduced from UT's as the
	-- Rocket Launcher's self damage is (45 for its 60).
	self_damage = 250 * 60 / 90 * 45 / 60,
	-- The multipliers of the damage and the stagger for each armor type: unarmored, armored, monsters, players, berserkers and super
	-- armor. UT has no armor, and a nuclear blast is not stopped by it.
	armor_attack = { 1, 1, 1, 1, 1, 1 },
	armor_impact = { 1, 1, 1, 1, 1, 1 },
	-- How far a bot shoots from, in meters. It should be well out of the blast.
	bot_min_range = 30,
	bot_max_range = 80,
}

local UNIT = utils.UT_UNIT

-- The direct hit only staggers: the damage is the blast, as in UT, where the missile blows up on what it touches.
register_damage_profile("ut_redeemer", "staff_fireball", function (profile)
	make_flat(profile, utils.STAGGER_HIT_ATTACK_POWER, impact_power_for(CONFIG.damage), "grenade")

	profile.cleave_distribution = {
		attack = 0.01,
		impact = 0.01,
	}
end)

local function modify_blast_profile(profile)
	make_flat(profile, attack_power_for(CONFIG.damage), impact_power_for(CONFIG.damage))
	utils.set_armor_modifiers(profile, CONFIG.armor_attack, CONFIG.armor_impact)
end

register_damage_profile("ut_redeemer_blast", "fireball_charged_explosion", modify_blast_profile)
register_damage_profile("ut_redeemer_blast_glance", "fireball_charged_explosion_glance", modify_blast_profile)

-- One explosion template for each wave. The look and the sound of the blast come from the skin, which draws it once, for the first wave.
local WAVE_NAMES = {}

for index, share in ipairs(CONFIG.wave_radii) do
	local name = "ut_redeemer_wave_" .. index

	WAVE_NAMES[index] = name

	register_explosion_template(name, {
		explosion = {
			alert_enemies = true,
			alert_enemies_radius = CONFIG.radius_uu * UNIT,
			attacker_power_level_offset = 1,
			damage_profile = "ut_redeemer_blast",
			damage_profile_glance = "ut_redeemer_blast_glance",
			-- The shooter is hurt separately (see self_damage)
			ignore_attacker_unit = true,
			max_damage_radius = CONFIG.full_damage_radius * CONFIG.radius_uu * share * UNIT,
			radius = CONFIG.radius_uu * share * UNIT,
			use_attacker_power_level = true,
			camera_effect = index == 1 and {
				far_distance = 60,
				far_scale = 0.3,
				near_distance = 10,
				near_scale = 1,
				shake_name = "frag_grenade_explosion",
			} or nil,
		},
	})
end

mod.redeemer = {
	wave_names = WAVE_NAMES,
	radius = CONFIG.radius_uu * UNIT,
}

-- The waves after the first, made by the machine of the player who fired: each is an explosion that the game sends to the others
local waves = {}

mod.aoe_callbacks.redeemer = function (self, aoe_data, position)
	if self._ut_redeemer_exploded then
		return
	end

	self._ut_redeemer_exploded = true

	local t = Managers.time:time("game")

	for index = 2, #WAVE_NAMES do
		waves[#waves + 1] = {
			at = t + CONFIG.wave_times[index],
			critical = self._is_critical_strike,
			item_name = self.item_name,
			name = WAVE_NAMES[index],
			owner_unit = self._owner_unit,
			position = Vector3Box(position),
			power_level = self.power_level,
		}
	end

	utils.apply_explosion_self_damage(self._owner_unit, position, self.item_name, ExplosionTemplates[WAVE_NAMES[#WAVE_NAMES]].explosion, CONFIG.self_damage)
end

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	if #waves == 0 or not Managers.state.entity then
		return
	end

	local t = Managers.time:time("game")

	for index = #waves, 1, -1 do
		local wave = waves[index]

		if t >= wave.at then
			table.remove(waves, index)

			if Unit.alive(wave.owner_unit) then
				Managers.state.entity:system("area_damage_system"):create_explosion(wave.owner_unit, wave.position:unbox(), Quaternion.identity(), wave.name, 1, wave.item_name, wave.power_level, wave.critical, wave.owner_unit)
			end
		end
	end
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(waves)
end

-- Weapon template

local function build_shot(source)
	local action = table.clone(source)
	-- (the Trollhammer's own projectile, whose unit is loaded with the weapon: another weapon's unit is not, and spawning it crashes)
	local projectile_info = table.clone(source.projectile_info)

	projectile_info.gravity_settings = CONFIG.missile_gravity_settings
	projectile_info.radius = CONFIG.missile_radius * UNIT
	projectile_info.unit_life_time = CONFIG.missile_lifetime
	projectile_info.life_time = CONFIG.missile_lifetime

	action.projectile_info = projectile_info
	-- The skin plays UT's sound
	action.fire_sound_event = nil
	action.speed = CONFIG.missile_speed
	action.angular_velocity = nil
	action.timed_data = nil
	action.ut_aoe_callback = "redeemer"
	action.ut_init_flow_event_filter = "redeemer"
	action.ut_skin_init_callback = "redeemer"
	action.ut_redeemer = true
	action.reload_when_out_of_ammo = false

	-- The missile is a grenade, so the first thing it hits sets off the blast
	action.impact_data = {
		aoe = ExplosionTemplates[WAVE_NAMES[1]],
		damage_profile = "ut_redeemer",
		grenade = true,
	}
	action.total_time = CONFIG.fire_interval

	for _, chain in ipairs(action.allowed_chain_actions or {}) do
		if chain.action == "action_one" then
			chain.start_time = CONFIG.fire_interval
		end
	end

	return action
end

local function apply_template()
	local template = rawget(Weapons, TEMPLATE_NAME)
	local actions = template.actions

	template.weapon_diagram = {
		light_attack = {
			[DamageTypes.ARMOR_PIERCING] = 7,
			[DamageTypes.CLEAVE] = 7,
			[DamageTypes.SPEED] = 1,
			[DamageTypes.STAGGER] = 7,
			[DamageTypes.DAMAGE] = 7,
		},
		heavy_attack = {
			[DamageTypes.ARMOR_PIERCING] = 0,
			[DamageTypes.CLEAVE] = 0,
			[DamageTypes.SPEED] = 0,
			[DamageTypes.STAGGER] = 0,
			[DamageTypes.DAMAGE] = 0,
		},
	}

	actions.action_one.default = build_shot(actions.action_one.default)

	utils.set_actions_lookup_data({
		action_one = actions.action_one,
	}, TEMPLATE_NAME)

	template.ammo_data.max_ammo = CONFIG.max_ammo
	template.ammo_data.ammo_per_clip = CONFIG.max_ammo
	template.ammo_data.ammo_per_reload = CONFIG.max_ammo
	template.ammo_data.ammo_immediately_available = true
	template.ammo_data.reload_time = 0.2

	template.attack_meta_data.minimum_charge_time = nil
	template.attack_meta_data.max_range = CONFIG.bot_max_range
	template.attack_meta_data.minimum_range = CONFIG.bot_min_range
end

-- The template is the mod's own copy (items.register), so it is changed once
apply_template()
