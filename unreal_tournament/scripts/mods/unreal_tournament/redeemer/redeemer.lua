local mod = get_mod("unreal_tournament")

-- Redeemer: the Bounty Hunter's career ability (Locked and Loaded) while he holds the Rocket Launcher. Instead of the ability's two
-- barrels he fires one slow missile that flies straight until it hits something, and there it makes a nuclear blast: six waves that
-- reach further and further out over 1.3 seconds, each hurting everything in its reach. The numbers come from UT2004 (XWeapons/Redeemer,
-- RedeemerFire, RedeemerProjectile). UT's second mode, which steers the missile from its own view (RedeemerGuidedFire), is not made.
-- Without the Rocket Launcher the ability is the game's.
-- The skin (skin.lua) draws all of it, and this file only sets what it does to the game.

local utils = mod.utils
local register_damage_profile = utils.register_damage_profile
local register_explosion_template = utils.register_explosion_template
local make_flat = utils.make_flat
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for

-- The Bounty Hunter's career weapon, the pistol he draws for his ability
local TEMPLATE_NAME = "victor_bountyhunter_career_skill_weapon"
local CAREER_NAME = "wh_bountyhunter"
-- The sub-action of the ability's shot that is the Redeemer's, and the one that chooses between it and the game's own
local SHOT_ACTION = "ut_redeemer"
local SELECT_ACTION = "ut_redeemer_select"
local SPREAD_TEMPLATE = "ut_redeemer"

utils.register_network_lookup("sub_actions", SHOT_ACTION)

local CONFIG = {
	-- RedeemerProjectile.Speed is 1000 units a second. The Rocket Launcher's 1350 is 2200 here (the action's unit is m/s * 100), so
	-- this is the same share of it.
	missile_speed = 2200 * 1000 / 1350,
	missile_lifetime = 20, -- seconds, LifeSpan
	missile_radius = 24, -- UT units, CollisionRadius
	-- The game's gravity setting with the least gravity. UT's missile flies straight (PHYS_Projectile).
	missile_gravity_settings = "spark",
	-- The ability's cooldown with the Redeemer, in seconds. The game's Locked and Loaded is 70 s, and its longest abilities 120 to 140 s;
	-- the Redeemer's blast is stronger than any of them.
	cooldown = 160,
	-- The shot lasts as long as the Fire animation (16 frames at 30 a second) and then the put-down (Redeemer.PutDownTime): the Redeemer
	-- holds one missile, so it is put down at once, as UT puts a weapon down when its ammo runs out. The game puts the pistol away when
	-- the shot ends. The ability's cancel puts it down the same way.
	fire_animation_time = 16 / 30,
	put_down_time = 0.45,
	-- RedeemerProjectile's blast (state Dying): HurtRadius six times, each with the whole Damage (250) and a radius that grows from 0.125
	-- of DamageRadius (2000 units) to all of it, the first at once and the others 0.5, 0.7, 0.9, 1.1 and 1.3 s after. The Rocket
	-- Launcher's damage and radius are reduced from UT's (90 to 60, and 220 units to 150), and these are reduced in the same way. The
	-- damage gives the blast's stagger; its damage is blast_damage, below.
	damage = 250 * 60 / 90,
	radius_uu = 2000 * 150 / 220,
	wave_radii = { 0.125, 0.3, 0.475, 0.65, 0.825, 1 }, -- shares of the radius
	wave_times = { 0, 0.5, 0.7, 0.9, 1.1, 1.3 }, -- seconds after the hit
	-- HurtRadius falls off with the distance over the whole radius, from full damage at the center
	full_damage_radius = 0, -- share of each wave's radius
	-- Where the missile starts, from the eye: RedeemerFire.ProjSpawnOffset, 100 units straight ahead
	start_forward = 2, -- m
	-- RedeemerFire's view shake, for the player who fires: the view jumps back 20 units (ShakeOffsetMag, rate and time as forward,
	-- right, up). It has no turn (ShakeRotMag is 0).
	shake_magnitude = { -20, 0, 0 },
	shake_rate = { -1000, 0, 0 },
	shake_time = 2,
	-- Each wave throws the player away from the center at this speed in m/s, less further out, as the damage. UT's MomentumTransfer is
	-- 200000, four times the Rocket Launcher's 50000, which throws at 5.7 m/s (rocket_launcher.lua's rocket_jump_speed).
	push_speed = 5.7 * 200000 / 50000,
	-- A body killed by a wave is thrown away from the center and up at these speeds, in m/s: DamTypeRedeemer has its own (KDeathVel and
	-- KDeathUpKick, 600 units a second each), where the rocket's is UT's usual throw (utils.ut_ragdoll_throw).
	ragdoll_speed = 600 * 0.02,
	ragdoll_up = 600 * 0.02,
	ragdoll_window = 1.5, -- seconds a body has to start ragdolling after the wave
	-- The blast hurts the player who fired it (HurtRadius hurts everyone): each wave that reaches them, when it goes off. This is a
	-- wave's damage at the center, reduced from UT's as the Rocket Launcher's self damage is (45 for its 60).
	self_damage = 250 * 60 / 90 * 45 / 60,
	-- The multipliers of the damage and the stagger for each armor type: unarmored, armored, monsters, players, berserkers and super
	-- armor. UT has no armor, and a nuclear blast is not stopped by it.
	armor_attack = { 1, 1, 1, 1, 1, 1 },
	armor_impact = { 1, 1, 1, 1, 1, 1 },
	-- The blast's damage, not UT's: a monster at the center of every wave loses this much in all on Legend, from a hero of
	-- blast_power_level with no power buffs. It is a little over a Rat Ogre's health on Legend (2400). Other enemies take more, as the
	-- game cuts the monsters' damage. UT's damage (damage above, which is still the stagger's) would take far less.
	blast_damage = 2500,
	blast_power_level = 650,
	-- How far a bot shoots from, in meters. A bot moves towards its target, so it is rarely out of the blast (radius_uu, 27 m). From 15 m,
	-- where the game's own rule for the ability stops, the blast takes about half of the self damage from it.
	bot_min_range = 15,
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

-- The attack power of a wave that gives blast_damage over the waves. The game's damage of a hit is DamageOutput's most times the power
-- over MAX_POWER_LEVEL. The power is the attack power times the power level as ActionUtils.scale_power_levels scales it, which from 300
-- up is MIN_POWER_LEVEL_CAP and then a share of the rest. DamageUtils.calculate_damage then adds Legend's stagger bonus, as the profile's
-- no_stagger_damage_reduction_ranged counts every target as staggered at least once, and a monster takes 0.45 of it
-- (boss_damage_reduction).
local MONSTER_DAMAGE_SHARE = 0.45

local function blast_attack_power()
	local power_level = CONFIG.blast_power_level
	local scaled_power_level = MIN_POWER_LEVEL_CAP + (power_level - MIN_POWER_LEVEL_CAP) * (POWER_LEVEL_DIFF_RATIO.attack - 1) / (10 - 1)
	local legend = DifficultySettings.hardest
	local stagger_bonus = legend.min_stagger_damage_coefficient + legend.stagger_damage_multiplier
	local wave_damage = CONFIG.blast_damage / #CONFIG.wave_radii / (stagger_bonus * MONSTER_DAMAGE_SHARE)

	return wave_damage * MAX_POWER_LEVEL / (DamageOutput[1].max * scaled_power_level)
end

local function modify_blast_profile(profile)
	make_flat(profile, blast_attack_power(), impact_power_for(CONFIG.damage))
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
			-- Walls shield the players, including the shooter, from the waves, as UT's HurtRadius only hurts what it can see from the
			-- missile's center (hooks.lua). Enemies are hurt through them.
			ut_walls_block_players = true,
			ut_origin_offset = CONFIG.missile_radius * UNIT,
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

-- Whether a character's career ability is the Redeemer now: a Bounty Hunter who holds the Rocket Launcher
local function has_redeemer(unit)
	local career_extension = unit and ScriptUnit.has_extension(unit, "career_system")

	if not career_extension or career_extension:career_name() ~= CAREER_NAME then
		return false
	end

	local inventory_extension = ScriptUnit.has_extension(unit, "inventory_system")
	local slot_data = inventory_extension and inventory_extension:get_slot_data("slot_ranged")
	local item_data = slot_data and slot_data.item_data

	return item_data ~= nil and item_data.template == mod.items.weapons.rocket_launcher.template
end

mod.redeemer = {
	wave_names = WAVE_NAMES,
	template = TEMPLATE_NAME,
	has_redeemer = has_redeemer,
	fire_animation_time = CONFIG.fire_animation_time,
	put_down_time = CONFIG.put_down_time,
	-- (for the tests)
	blast_damage = CONFIG.blast_damage,
	blast_power_level = CONFIG.blast_power_level,
}

-- The waves after the first, made by the machine of the player who fired: each is an explosion that the game sends to the others, and
-- each hurts the shooter if it reaches them
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

	utils.apply_explosion_self_damage(self._owner_unit, position, self.item_name, ExplosionTemplates[WAVE_NAMES[1]].explosion, CONFIG.self_damage)
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
				local area_damage_system = Managers.state.entity:system("area_damage_system")

				-- (the mod's update runs before the game's, so the units' positions are made current for the explosion)
				utils.with_valid_positions(area_damage_system.create_explosion, area_damage_system, wave.owner_unit, wave.position:unbox(), Quaternion.identity(), wave.name, 1, wave.item_name, wave.power_level, wave.critical, wave.owner_unit)
				utils.apply_explosion_self_damage(wave.owner_unit, wave.position:unbox(), wave.item_name, ExplosionTemplates[wave.name].explosion, CONFIG.self_damage)
			end
		end
	end
end

-- Each wave throws the players near it (the player on each machine is thrown by that machine), and the bodies of what it kills. This
-- runs on every machine, as the physics of ragdolls is local. The living units in a wave's reach are collected when it goes off, and the
-- ones that die are thrown once their ragdoll has started, because before that their bodies are moved by animation.
local bodies = {}

for _, name in ipairs(WAVE_NAMES) do
	mod.explosion_push_speeds[name] = function ()
		return CONFIG.push_speed
	end

	mod.explosion_callbacks[name] = function (world, position)
		local living = {}

		for unit in pairs(utils.units_in_radius(world, position, ExplosionTemplates[name].explosion.radius)) do
			if HEALTH_ALIVE[unit] then
				living[unit] = true
			end
		end

		bodies[#bodies + 1] = {
			position = Vector3Box(position),
			t = Managers.time:time("game"),
			units = living,
		}
	end
end

local function update_bodies()
	local t = Managers.time:time("game")

	for index = #bodies, 1, -1 do
		local wave = bodies[index]
		local center = wave.position:unbox()

		for unit in pairs(wave.units) do
			if not Unit.alive(unit) then
				wave.units[unit] = nil
			elseif not HEALTH_ALIVE[unit] and utils.blast_ragdoll(unit, center, CONFIG.ragdoll_speed, CONFIG.ragdoll_up) then
				wave.units[unit] = nil
			end
		end

		if t - wave.t > CONFIG.ragdoll_window or next(wave.units) == nil then
			table.remove(bodies, index)
		end
	end
end

mod.update_callbacks[#mod.update_callbacks + 1] = update_bodies

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(waves)
	table.clear(bodies)
end

-- The ability's shot. The game's has two barrels: the upper one fires a projectile, the lower one a shotgun blast, and a push goes out
-- around the shooter. The Redeemer's is the upper barrel's projectile alone, with the missile's speed and its blast, and no spread.
-- The projectile's unit is the game's (bullet_temp), which is loaded for every Bounty Hunter. The skin draws the missile over it.
utils.zero_spread_template(SPREAD_TEMPLATE, "bounty_hunter_handgun")

local function build_shot(source)
	local action = table.clone(source)
	local projectile_info = table.clone(source.projectile_info)

	projectile_info.gravity_settings = CONFIG.missile_gravity_settings
	projectile_info.radius = CONFIG.missile_radius * UNIT
	projectile_info.unit_life_time = CONFIG.missile_lifetime
	projectile_info.life_time = CONFIG.missile_lifetime

	action.projectile_info = projectile_info
	action.speed = CONFIG.missile_speed
	action.railgun_spread_template = SPREAD_TEMPLATE
	action.fire_time_upper = 0
	action.total_time = CONFIG.fire_animation_time + CONFIG.put_down_time
	action.ut_aoe_callback = "redeemer"
	action.ut_init_flow_event_filter = "redeemer"
	action.ut_skin_init_callback = "redeemer"
	action.ut_redeemer = true

	-- The missile is a grenade, so the first thing it hits sets off the blast
	action.impact_data = {
		aoe = ExplosionTemplates[WAVE_NAMES[1]],
		damage_profile = "ut_redeemer",
		grenade = true,
	}

	return action
end

-- The missile starts where UT's does (RedeemerFire.ProjSpawnOffset, see utils.projectile_start)
mod.spawn_projectile_callbacks[TEMPLATE_NAME] = function (func, owner_unit, position, rotation, scale, angle, target_vector, speed, item_name, item_template_name, action_name, sub_action_name, ...)
	local template = rawget(Weapons, item_template_name)
	local sub_actions = template and template.actions[action_name]
	local action = sub_actions and sub_actions[sub_action_name]

	if action and action.ut_redeemer then
		position = utils.projectile_start(position, rotation, CONFIG.start_forward, 0, 0)
	end

	return func(owner_unit, position, rotation, scale, angle, target_vector, speed, item_name, item_template_name, action_name, sub_action_name, ...)
end

-- The ability's hold chains to the shot. It chains to a selector instead (the game's action_selector, as the Engineer's weapon has),
-- which picks the Redeemer's shot for a Bounty Hunter who holds the Rocket Launcher and the game's own otherwise.
local function apply_template()
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not template then
		return
	end

	local release = template.actions.action_career_release

	release[SHOT_ACTION] = build_shot(release.default)
	release[SELECT_ACTION] = {
		kind = "action_selector",
		-- (the hand is looked at before the selector chooses: the pistol is in the left hand, and the right one is empty)
		weapon_action_hand = "left",
		default_action = {
			sub_action = "default",
		},
		conditional_actions = {
			{
				sub_action = SHOT_ACTION,
				condition = function (talent_extension, buff_extension, weapon_extension, owner_unit)
					return has_redeemer(owner_unit)
				end,
			},
		},
	}

	utils.set_actions_lookup_data({
		action_career_release = {
			[SHOT_ACTION] = release[SHOT_ACTION],
			[SELECT_ACTION] = release[SELECT_ACTION],
		},
	}, TEMPLATE_NAME)

	for _, hold in pairs(template.actions.action_career_hold) do
		for _, chain in ipairs(hold.allowed_chain_actions or {}) do
			if chain.action == "action_career_release" and (chain.sub_action == "default" or chain.sub_action == SELECT_ACTION) then
				chain.sub_action = SELECT_ACTION
			end
		end
	end
end

-- Puts the game's template back as it was
local function restore_template()
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not template then
		return
	end

	for _, hold in pairs(template.actions.action_career_hold) do
		for _, chain in ipairs(hold.allowed_chain_actions or {}) do
			if chain.action == "action_career_release" and chain.sub_action == SELECT_ACTION then
				chain.sub_action = "default"
			end
		end
	end

	template.actions.action_career_release[SHOT_ACTION] = nil
	template.actions.action_career_release[SELECT_ACTION] = nil
end

apply_template()
mod.unload_callbacks[#mod.unload_callbacks + 1] = restore_template

-- With the Redeemer only the upper barrel fires: the lower one and the push around the shooter are marked done before they come.
-- The upper barrel fires the projectile whatever the ability's talents make it (they choose a railgun or a shotgun for each barrel).
-- The skin plays the shot (mod.redeemer.skin_shot, from skin.lua), and the view of the player who fires shakes.
mod:hook(ActionCareerWHBountyhunter, "client_owner_start_action", function (func, self, new_action, ...)
	func(self, new_action, ...)

	if new_action.ut_redeemer then
		self.upper_shoot_function = self._railgun_shoot
		self.lower_shot_done = true
		self.aoe_done = true

		if utils.is_local_player_unit(self.owner_unit) then
			mod.view_shake.start(CONFIG.shake_magnitude, CONFIG.shake_rate, CONFIG.shake_time)
		end

		if mod.redeemer.skin_shot then
			mod.redeemer.skin_shot(self)
		end
	end
end)

-- The ability's cancel (the career pistol's action_two) puts the Redeemer down (mod.redeemer.skin_put_down, from skin.lua)
mod:hook_safe(ActionCareerDummy, "client_owner_start_action", function (self, new_action)
	local lookup_data = new_action.lookup_data

	if lookup_data and lookup_data.item_template_name == TEMPLATE_NAME and lookup_data.action_name == "action_two" and has_redeemer(self.owner_unit) and mod.redeemer.skin_put_down then
		mod.redeemer.skin_put_down(self)
	end
end)

-- Bots. A Bounty Hunter bot uses the ability on its target within 15 m (BTConditions.can_activate.wh_bountyhunter), which is well inside
-- the Redeemer's blast. With the Redeemer a bot uses it only on a target from bot_min_range to bot_max_range away, with no player or
-- other bot within the blast's radius of it. The game's check that nothing is in the way is kept. A bot takes a special for its target
-- only within 40 m of it (AIBotGroupSystem's FALLBACK_OPPORTUNITY_DISTANCE), so it fires at a special from 15 to 40 m.
mod:hook(BTConditions.can_activate, "wh_bountyhunter", function (func, blackboard)
	local bot_unit = blackboard.unit

	if not has_redeemer(bot_unit) then
		return func(blackboard)
	end

	local target = blackboard.target_unit

	if not ALIVE[target] or not BLACKBOARDS[target] then
		return false
	end

	local target_position = POSITION_LOOKUP[target]
	local distance = Vector3.distance(POSITION_LOOKUP[bot_unit], target_position)

	if distance < CONFIG.bot_min_range or distance > CONFIG.bot_max_range then
		return false
	end

	local radius = CONFIG.radius_uu * UNIT

	for _, player in pairs(Managers.player:players()) do
		local player_unit = player.player_unit

		if player_unit ~= bot_unit and ALIVE[player_unit] and Vector3.distance(POSITION_LOOKUP[player_unit], target_position) < radius then
			return false
		end
	end

	local obstruction = blackboard.ranged_obstruction_by_static
	local t = Managers.time:time("game")

	return not (obstruction and obstruction.unit == target and t <= obstruction.timer + 3)
end)

-- The ability's cooldown is the Redeemer's while a Bounty Hunter holds the Rocket Launcher. The game starts the cooldown by adding its
-- whole length (reduce_activated_ability_cooldown_percent(-1)), and a cooldown is never longer than its maximum, so the maximum is made
-- longer by the difference (CareerExtension.modify_max_cooldown, which keeps how far along the cooldown is). It is checked every frame,
-- for every character, as the Rocket Launcher can be put in or taken out at any time.
local cooldown_bonus = setmetatable({}, {
	__mode = "k",
})

local function set_cooldown_bonus(career_extension, bonus)
	local applied = cooldown_bonus[career_extension] or 0

	if bonus ~= applied then
		career_extension:modify_max_cooldown(1, bonus - applied, 0)
		cooldown_bonus[career_extension] = bonus
	end
end

local function cooldown_bonus_of(unit)
	if not has_redeemer(unit) then
		return 0
	end

	local career_extension = ScriptUnit.extension(unit, "career_system")
	local ability_data = career_extension:get_activated_ability_data()

	return CONFIG.cooldown - (ability_data and ability_data.cooldown or CONFIG.cooldown)
end

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	local player_manager = Managers.player

	if not player_manager or not Managers.state.network then
		return
	end

	for _, player in pairs(player_manager:players()) do
		local unit = player.player_unit
		local career_extension = unit and ALIVE[unit] and ScriptUnit.has_extension(unit, "career_system")

		if career_extension and career_extension:career_name() == CAREER_NAME then
			set_cooldown_bonus(career_extension, cooldown_bonus_of(unit))
		end
	end
end

mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
	for career_extension in pairs(cooldown_bonus) do
		set_cooldown_bonus(career_extension, 0)
	end
end
