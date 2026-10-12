local mod = get_mod("unreal_tournament")

-- Flak Cannon: a copy of the Blunderbuss with its fire modes replaced, the same way the Shock Rifle is a copy of the Beam Staff.
-- The numbers come from UT2004 (XWeapons/FlakFire, FlakAltFire, FlakChunk, FlakShell).
--   LMB: a tight spread of flak chunks. They bounce off walls.
--   RMB: a lobbed shell that explodes when it hits something and throws flak chunks in all directions.
-- Recoil and the sounds of the shot are the Blunderbuss's own. There is no reload.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local register_damage_profile = utils.register_damage_profile
local register_explosion_template = utils.register_explosion_template
local register_network_lookup = utils.register_network_lookup
local make_flat = utils.make_flat
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for

mod.items.register("flak_cannon", {
	key = "ut_flak_cannon",
	template = "ut_flak_cannon_template",
	base_item = "es_blunderbuss",
	deus_copy = "deus_es_blunderbuss",
	name = "UT2004 Flak Cannon",
	type_name = "Flak Cannon",
	description = "The Trident Series 7 Flechette Cannon has evolved into the \"Mk3 Negotiator\". Its ionized flechettes burn and cauterize flesh, fired in a spread from the barrel or by grenades that explode on impact and radiate flechettes.",
	keywords = { "weapon_keyword_high_damage", "weapon_keyword_crowd_control", "weapon_keyword_versatile" },
	icon = "ut_flak_cannon_icon",
	icon_package = "resource_packages/unreal_tournament/icons",
	icon_materials = "ui/ut/flak_cannon_icon",
})

local TEMPLATE_NAME = mod.items.weapons.flak_cannon.template

local CONFIG = {
	meters_per_uu = 0.02, -- Unreal unit to meters
	-- Temporary, for testing: multiplies the launch speed of the chunks and the shell. 1 is normal.
	debug_speed_scale = 1,
	-- The Blunderbuss's ammo (16) is multiplied by this.
	ammo_multiplier = 1.33,
	-- Flak chunk
	chunk_count = 9, -- FlakFire.ProjPerFire
	chunk_spread_degrees = 4, -- "tight", FlakFire.Spread is about 7.7 degrees
	-- FlakChunk.Speed is 2500 uu/s, which is 50 m/s with the unit conversion for sizes and 23 m/s in
	-- proportion to the run speed. Both felt wrong, this is in between. (The action's unit is m/s * 100.)
	chunk_speed = 3500,
	chunk_lifetime = 2.7, -- seconds
	chunk_radius = 0.08, -- m, how easily a chunk hits things
	-- Where the chunks start, from the camera: forward, to the right and down (FlakFire.ProjSpawnOffset, 25, 5 and -6 units).
	-- The shift sideways is what lets you see a trail from the front instead of straight on.
	chunk_spawn_forward = 0.5, -- m
	chunk_spawn_right = 0.1, -- m
	chunk_spawn_down = 0.12, -- m
	-- Where the shell starts, from the camera (FlakAltFire.ProjSpawnOffset, 25, 9 and -12 units): lower and further right than the chunks
	shell_spawn_forward = 0.5, -- m
	shell_spawn_right = 0.18, -- m
	shell_spawn_down = 0.24, -- m
	-- A UT chunk flies straight and only starts to fall after it hits a wall. So there is no gravity in flight, and after the first bounce
	-- the chunk gets the game's weakest gravity setting (-0.5).
	chunk_gravity_settings = "drake_pistols", -- the game's gravity of 0
	chunk_bounce_gravity_settings = "spark",
	chunk_bounce_speed_scale = 0.65, -- the speed a chunk keeps after bouncing
	-- UT2004: 25% of the chunks bounce twice off the level, 50% once and 25% not at all. A chunk that has used up its bounces goes cold:
	-- it stops flying straight, slides along the surface it hit and falls, and it stops where it lands.
	-- A chunk also goes through enemies. Each enemy it goes through and each bounce uses up one of the
	-- chunk's passes, and a chunk has its bounces plus this many in all.
	-- The multipliers of a chunk per armor type (unarmored, armored, monsters, players, berserkers, super armor). UT has no
	-- armor: these make the chunks armor piercing, which is the mod's.
	chunk_armor_attack = {1, 1.25, 1.5, 1, 1, 0.5},
	chunk_armor_impact = {1, 1, 1, 1, 1, 0.25},
	chunk_bounces = 2, -- the most bounces a chunk has in UT2004
	chunk_extra_bounces = 2,
	chunk_damage = 11, -- in UT2004's units, 45 is the shock rifle's beam. UT has 13 with a 90 explosion, 8.7 was it scaled with the explosion's 60
	-- UT2004: after its first second a chunk loses 5 damage per second of its 13, but not below 5
	-- (FlakChunk.DamageAtten). These numbers are UT's and are scaled to chunk_damage.
	chunk_ut_damage = 13,
	chunk_damage_decay = 5, -- per second
	chunk_damage_decay_delay = 1, -- seconds
	chunk_damage_min = 5,
	-- A chunk slower than 200 of UT's 2500 units per second does no damage (FlakChunk.ProcessTouch).
	chunk_min_speed_fraction = 200 / 2500,
	-- A chunk that has bounced can hit the player who fired it (in UT a falling chunk no longer ignores its shooter). It does this much
	-- damage if it passes within this distance of a line along the player's body.
	chunk_self_damage = 8,
	chunk_self_hit_radius = 0.45, -- m
	chunk_self_hit_height = 1.6, -- m, the height of that line
	-- Fire rates (FlakFire.FireRate and FlakAltFire.FireRate). After a shot, either fire mode can be used again once this much time has
	-- passed. There is no reload: all the ammo is the clip, and picked up ammo goes straight into it (ammo_immediately_available).
	primary_fire_rate = 0.8947,
	alt_fire_rate = 1.11,
	chain_margin = 0.15, -- seconds
	-- Knockback of a chunk: how hard it staggers what it hits, (the beam's impact power is 0.3, a
	-- shotgun pellet's is 0.3 up close and 0.15 far away). It falls off with the distance between the
	-- player and the target, from the near value up to the start, to the far value from the end.
	chunk_knockback_near = 1.2,
	chunk_knockback_far = 0.05,
	-- Multiplies how far a staggered enemy is pushed back (1 is what the game's shotguns do). Strong
	-- hits (up close) get the whole of it, weak ones (far away) get less because their stagger is weaker.
	chunk_stagger_distance_modifier = 6,
	chunk_knockback_falloff_start = 2, -- m
	chunk_knockback_falloff_end = 12, -- m
	-- The ragdoll of what a chunk killed is thrown (the game's own push of a dying body is small).
	-- Every chunk that hit adds its speed, so point blank all of them together send the body flying.
	-- Falls off with the distance between the player and the target like the knockback.
	chunk_ragdoll_speed_near = 25, -- m/s per chunk
	chunk_ragdoll_speed_far = 3, -- m/s per chunk
	chunk_ragdoll_max_speed = 180, -- m/s
	chunk_ragdoll_up = 0.35, -- upwards speed, as a share of the horizontal speed
	chunk_ragdoll_window = 1.5, -- seconds a body has to start ragdolling after it was hit
	-- Shell
	shell_speed = 2400, -- FlakShell.Speed 1200 uu/s = 24 m/s
	shell_lob_degrees = 10.6, -- how far up the shell is tossed from the aim (FlakShell.TossZ: 225 units/s up for 1200 forward)
	shell_lifetime = 6,
	-- UT's gravity is 950 units/s^2, which is 19 m/s^2 at 0.02 m per unit. This is a little less. The game's own is -9.82, which keeps a shell
	-- fired straight up in the air twice as long as UT's.
	shell_gravity = -17,
	shell_radius = 0.2, -- m
	shell_damage = 60, -- the damage of the explosion
	-- The multipliers of the explosion's damage and stagger per armor type: unarmored, armored, monsters, players,
	-- berserkers, super armor
	shell_armor_attack = {
		1,
		1,
		1.5,
		1,
		1,
		0.5,
	},
	shell_armor_impact = {
		1,
		1,
		1,
		1,
		1,
		0.5,
	},
	shell_explosion_radius_uu = 150, -- FlakShell: 220, it was reduced
	-- The explosion hurts the player who fired the shell: this much at the center, falling off like
	-- the explosion's damage does (the combo of the shock rifle, which is twice the damage, is 100)
	shell_self_damage = 45,
	-- The shell's explosion throws the player who fired it away from the center at this speed (m/s), less further out, like the damage.
	-- (FlakShell.MomentumTransfer is 75000. The Shock Rifle's ball has 70000 and uses 8.)
	shell_jump_speed = 8.5,
	-- The shell explodes when another projectile of this mod (a ball, a rocket, another shell) gets this close to it (FlakShell.bProjTarget).
	shell_trigger_radius = 0.5, -- m
	-- While flying, the shell pushes dead bodies near it away (FlakShell.ForceType, ForceRadius 60 units, ForceScale 5).
	shell_force_radius = 1.2, -- m
	shell_force_acceleration = 12, -- m/s^2
	-- Bodies killed by the shell are thrown away from the explosion at this speed (m/s) at the center (DamTypeFlakShell.bThrowRagdoll).
	shell_ragdoll_speed = 30,
	shell_explosion_full_damage_radius = 0.5, -- damage falls off linearly from here to the radius
	shell_standard_power_level = 500, -- against a beastmen standard (banner) in the explosion's radius
	-- Chunks of one shot that spawn this close in time (seconds) are one shot, see shots
	shot_window = 0.1,
	shell_chunk_count = 6,
	shell_chunk_cone_degrees = 88, -- the chunks go up to this far from the direction of the shell, in yaw and pitch
	shell_chunk_start_offset = 0.2, -- m back from the explosion, so the chunks start in front of the wall
}

-- The projectiles of the weapon are sub actions of its two actions, the names go over the network.
-- The chunks belong to the primary action, the shell to the secondary one.
local CHUNK_ACTION_NAME = "action_one"
local SHELL_ACTION_NAME = "action_two"
local CHUNK_ACTIONS = {} -- the chunk that bounces n times is CHUNK_ACTIONS[n + 1]
local BURST_ACTIONS = {} -- the same, for the chunks of a shell's explosion, so that they are not taken for a shot of the primary fire

for bounces = 0, CONFIG.chunk_bounces + CONFIG.chunk_extra_bounces do
	CHUNK_ACTIONS[bounces + 1] = "ut_flak_chunk_" .. bounces
	BURST_ACTIONS[bounces + 1] = "ut_flak_burst_" .. bounces
end
local SHELL_ACTION = "ut_flak_shell"
local SHELL_GRAVITY_SETTINGS = "ut_flak_shell"

ProjectileGravitySettings[SHELL_GRAVITY_SETTINGS] = CONFIG.shell_gravity
register_network_lookup("projectile_gravity_settings", SHELL_GRAVITY_SETTINGS)

for _, name in ipairs(CHUNK_ACTIONS) do
	register_network_lookup("sub_actions", name)
end

for _, name in ipairs(BURST_ACTIONS) do
	register_network_lookup("sub_actions", name)
end

register_network_lookup("sub_actions", SHELL_ACTION)

-- Damage profiles
-- A chunk stops at the first enemy it hits, the direct hit of the shell only staggers: its damage is the
-- explosion, which is at full strength for whatever the shell hits (like in UT).

register_damage_profile("ut_flak_chunk", "staff_fireball", function (profile)
	make_flat(profile, attack_power_for(CONFIG.chunk_damage), impact_power_for(CONFIG.chunk_damage))

	-- armor piercing: armored enemies take more damage than unarmored ones (critical hits too)
	utils.set_armor_modifiers(profile, CONFIG.chunk_armor_attack, CONFIG.chunk_armor_impact, true)

	-- knockback that falls off: the damage is the same at any distance, the impact is not. This is
	-- how the game does the falloff of shotguns, with the shotgun's way of staggering.
	local target = profile.default_target
	local attack_power = attack_power_for(CONFIG.chunk_damage)

	target.attack_template = "shot_shotgun"
	target.stagger_distance_modifier = CONFIG.chunk_stagger_distance_modifier
	target.power_distribution_near = {
		attack = attack_power,
		impact = CONFIG.chunk_knockback_near,
	}
	target.power_distribution_far = {
		attack = attack_power,
		impact = CONFIG.chunk_knockback_far,
	}
	target.range_modifier_settings = {
		dropoff_end = CONFIG.chunk_knockback_falloff_end,
		dropoff_start = CONFIG.chunk_knockback_falloff_start,
	}

	profile.cleave_distribution = {
		attack = 0.01,
		impact = 0.01,
	}
end)
register_damage_profile("ut_flak_shell", "staff_fireball", function (profile)
	make_flat(profile, 0, impact_power_for(CONFIG.chunk_damage))

	profile.cleave_distribution = {
		attack = 0.01,
		impact = 0.01,
	}
end)

local function modify_explosion_profile(profile)
	make_flat(profile, attack_power_for(CONFIG.shell_damage), impact_power_for(CONFIG.shell_damage))

	-- the game's own multipliers for this are 0 against super armor (chaos warriors), the explosion would do
	-- nothing to them
	profile.armor_modifier.attack = table.clone(CONFIG.shell_armor_attack)
	profile.armor_modifier.impact = table.clone(CONFIG.shell_armor_impact)
end

register_damage_profile("ut_flak_shell_explosion", "fireball_charged_explosion", modify_explosion_profile)
register_damage_profile("ut_flak_shell_explosion_glance", "fireball_charged_explosion_glance", modify_explosion_profile)

-- The effect of the explosion is played by the code below, only if the game has it loaded
register_explosion_template("ut_flak_shell_explosion", {
	explosion = {
		alert_enemies = true,
		alert_enemies_radius = 15,
		attacker_power_level_offset = 1,
		damage_profile = "ut_flak_shell_explosion",
		damage_profile_glance = "ut_flak_shell_explosion_glance",
		-- the shooter is hurt separately, see shell_self_damage
		ignore_attacker_unit = true,
		max_damage_radius = CONFIG.shell_explosion_full_damage_radius,
		radius = CONFIG.shell_explosion_radius_uu * CONFIG.meters_per_uu,
		sound_event_name = "fireball_big_hit",
		use_attacker_power_level = true,
		camera_effect = {
			far_distance = 20,
			far_scale = 0.1,
			near_distance = 5,
			near_scale = 0.5,
			shake_name = "frag_grenade_explosion",
		},
	},
})

-- Weapon template

local function build_chunk_action(max_bounces, burst)
	local projectile_info = table.clone(Projectiles.brace_of_drake_pistols_shot)

	projectile_info.gravity_settings = CONFIG.chunk_gravity_settings
	projectile_info.radius = CONFIG.chunk_radius
	projectile_info.unit_life_time = CONFIG.chunk_lifetime

	return {
		hit_effect = "shotgun_bullet_impact",
		kind = "charged_projectile",
		ut_flak_burst = burst,
		ut_flak_chunk = true,
		ut_hit_enemy_callback = "ut_flak_chunk",
		ut_init_callback = "ut_flak_chunk",
		ut_init_flow_event_filter = "flak",
		ut_skin_init_callback = "ut_flak_chunk",
		projectile_info = projectile_info,
		impact_data = {
			bounce_on_level_units = true,
			damage_profile = "ut_flak_chunk",
			max_bounces = max_bounces,
		},
	}
end

local function build_shell_action()
	-- The game's frag bomb, it spins as it flies. (The other grenade unit is the fire bomb,
	-- "grenade_fire".)
	local projectile_info = table.clone(Projectiles.grenade)

	projectile_info.gravity_settings = SHELL_GRAVITY_SETTINGS
	projectile_info.life_time = CONFIG.shell_lifetime
	projectile_info.radius = CONFIG.shell_radius
	projectile_info.show_warning_icon = nil
	projectile_info.unit_life_time = CONFIG.shell_lifetime

	-- The effect where the shell lands is a bullet impact of the game's, the blunderbuss's own ones
	-- are loaded ("shotgun_bullet_impact" is the small one, "bullet_critical_impact" the big one). (The fireball's
	-- belongs to Sienna's packages, which aren't loaded for the blunderbuss, and playing an
	-- effect that isn't loaded crashes the game. The explosion effects that are loaded for
	-- Kruber are all too big, and they can't be scaled.)
	return {
		hit_effect = "bullet_critical_impact",
		kind = "charged_projectile",
		ut_aoe_callback = "ut_flak_shell",
		ut_flak_shell = true,
		ut_init_flow_event_filter = "flak",
		ut_skin_init_callback = "ut_flak_shell",
		projectile_info = projectile_info,
		impact_data = {
			aoe = ExplosionTemplates.ut_flak_shell_explosion,
			damage_profile = "ut_flak_shell",
		},
	}
end

-- The actions that can follow a shot: either fire mode, once the shot's time is over. Holding the button repeats the shot, as in UT.
local function fire_chain_actions(rate)
	local entries = {
		{
			action = "action_wield",
			input = "action_wield",
			start_time = 0.4,
			sub_action = "default",
		},
	}

	for _, action_name in ipairs({ "action_one", "action_two" }) do
		for _, input in ipairs({ action_name, action_name .. "_hold" }) do
			entries[#entries + 1] = {
				action = action_name,
				input = input,
				start_time = rate,
				sub_action = "default",
			}
		end
	end

	return entries
end

-- The Blunderbuss's shot (ammo, recoil, animation), repeatable after UT's fire time, with no reload.
local function build_shot(original, rate)
	local action = table.clone(original)

	-- The shot lasts slightly longer than the time to the next shot. A held button is only read while a shot is still running, so a shot
	-- that ends exactly when the next one may start would miss it.
	action.total_time = rate + CONFIG.chain_margin
	action.total_time_secondary = rate + CONFIG.chain_margin
	action.play_reload_animation = false
	action.allowed_chain_actions = fire_chain_actions(rate)

	return action
end

-- The secondary fire is the same shot, but it fires the shell instead of pellets.
local function build_shell_launcher(original)
	local action = build_shot(original, CONFIG.alt_fire_rate)

	action.damage_profile = "ut_flak_shell"
	action.shot_count = 1
	action.ut_flak_chunks = nil
	action.ut_flak_shell = true

	return action
end

-- The template is shared game state: it is patched in place, what is touched is saved to be put
-- back on disable, and when the mod is unloaded (a reload would take the patched template for the original).
local saved = {}

local PROJECTILE_UNIT_TEMPLATES = {
	"drake_pistol_shot",
	"grenade",
}

local function restore_blunderbuss()
	local original = saved.original
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not original or not template then
		return
	end

	local actions = template.actions

	actions.action_one.default = original.action_one_default
	actions.action_two.default = original.action_two_default

	for _, name in ipairs(CHUNK_ACTIONS) do
		actions[CHUNK_ACTION_NAME][name] = nil
	end

	for _, name in ipairs(BURST_ACTIONS) do
		actions[CHUNK_ACTION_NAME][name] = nil
	end

	actions[SHELL_ACTION_NAME][SHELL_ACTION] = nil
	template.attack_meta_data.ut_flak = nil

	for _, name in ipairs(PROJECTILE_UNIT_TEMPLATES) do
		template.required_projectile_unit_templates[name] = original.required_projectile_unit_templates[name]
	end

	for key, value in pairs(original.ammo_data or {}) do
		template.ammo_data[key] = value
	end

	saved.original = nil
end

local function apply_flak_cannon()
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not template then
		return
	end

	-- Already applied by a previous load of this mod, start over from the original
	restore_blunderbuss()

	-- The chart of the item's stats (0 to 7): the primary fire is the normal attack, the shell the heavy one
	template.weapon_diagram = {
		light_attack = {
			[DamageTypes.ARMOR_PIERCING] = 2,
			[DamageTypes.CLEAVE] = 5,
			[DamageTypes.SPEED] = 5,
			[DamageTypes.STAGGER] = 4,
			[DamageTypes.DAMAGE] = 5,
		},
		heavy_attack = {
			[DamageTypes.ARMOR_PIERCING] = 4,
			[DamageTypes.CLEAVE] = 7,
			[DamageTypes.SPEED] = 3,
			[DamageTypes.STAGGER] = 6,
			[DamageTypes.DAMAGE] = 6,
		},
	}

	local actions = template.actions
	local original = {
		action_one_default = actions.action_one.default,
		action_two_default = actions.action_two.default,
		required_projectile_unit_templates = {},
		ammo_data = {
			reload_time = template.ammo_data.reload_time,
			ammo_immediately_available = template.ammo_data.ammo_immediately_available,
			ammo_per_clip = template.ammo_data.ammo_per_clip,
			ammo_per_reload = template.ammo_data.ammo_per_reload,
			max_ammo = template.ammo_data.max_ammo,
		},
	}

	for _, name in ipairs(PROJECTILE_UNIT_TEMPLATES) do
		original.required_projectile_unit_templates[name] = template.required_projectile_unit_templates[name]
	end

	saved.original = original

	-- (what tells the bot shooting, see bots.lua, that this is the Flak Cannon)
	template.attack_meta_data.ut_flak = true

	-- All the ammo is the clip, and picked up ammo is added to it, so there is no reload between shots.
	template.ammo_data.max_ammo = math.floor(original.ammo_data.max_ammo * CONFIG.ammo_multiplier + 0.5)
	template.ammo_data.ammo_per_clip = template.ammo_data.max_ammo
	template.ammo_data.ammo_per_reload = template.ammo_data.max_ammo
	template.ammo_data.ammo_immediately_available = true
	-- Nothing should need a reload, but the game may still start one (when the weapon is wielded), so make it short.
	template.ammo_data.reload_time = 0.2

	local primary = build_shot(original.action_one_default, CONFIG.primary_fire_rate)

	primary.shot_count = CONFIG.chunk_count
	primary.ut_flak_chunks = true

	actions.action_one.default = primary
	actions.action_two.default = build_shell_launcher(original.action_one_default)

	for bounces = 0, #CHUNK_ACTIONS - 1 do
		actions[CHUNK_ACTION_NAME][CHUNK_ACTIONS[bounces + 1]] = build_chunk_action(bounces)
		actions[CHUNK_ACTION_NAME][BURST_ACTIONS[bounces + 1]] = build_chunk_action(bounces, true)
	end

	actions[SHELL_ACTION_NAME][SHELL_ACTION] = build_shell_action()

	utils.set_actions_lookup_data({
		action_one = actions.action_one,
		action_two = actions.action_two,
	}, TEMPLATE_NAME)

	-- the projectile units have to be loaded when the weapon is wielded
	for _, name in ipairs(PROJECTILE_UNIT_TEMPLATES) do
		template.required_projectile_unit_templates[name] = false
	end
end

-- Spawning a projectile
-- The data of the shot a projectile comes from (the weapon's action or the shell's extension)

local function spawn_projectile(shot, position, rotation, action_name, sub_action_name, speed, scale)
	local direction = Quaternion.forward(rotation)

	ActionUtils.spawn_player_projectile(shot.owner_unit, position, rotation, scale, ActionUtils.pitch_from_rotation(rotation), Vector3.normalize(Vector3.flat(direction)), speed, shot.item_name, shot.item_template_name, action_name, sub_action_name, shot.is_critical_strike, shot.power_level)
end

-- UT2004: a quarter of the chunks bounce twice, half of them once (plus the extra bounces)
local function random_chunk_action(burst)
	local roll = math.random()
	local bounces = roll > 0.75 and 2 or roll > 0.25 and 1 or 0

	return (burst and BURST_ACTIONS or CHUNK_ACTIONS)[bounces + CONFIG.chunk_extra_bounces + 1]
end

-- A random direction inside a cone of the angle (radians) around the rotation
local function spread_rotation(rotation, max_angle)
	local angle = math.random() * 2 * math.pi
	local radius = math.sqrt(math.random()) * max_angle
	local yaw = Quaternion.axis_angle(Vector3.up(), radius * math.cos(angle))
	local pitch = Quaternion.axis_angle(Vector3.right(), radius * math.sin(angle))

	return Quaternion.multiply(rotation, Quaternion.multiply(yaw, pitch))
end

-- UT2004's FlakShell: yaw and pitch are each randomly off by up to the cone
local function burst_rotation(rotation, cone)
	local yaw = Quaternion.axis_angle(Vector3.up(), (math.random() * 2 - 1) * cone)
	local pitch = Quaternion.axis_angle(Vector3.right(), (math.random() * 2 - 1) * cone)

	return Quaternion.multiply(rotation, Quaternion.multiply(yaw, pitch))
end

-- The shots
-- ActionShotgun fires pellets as hitscan, these actions fire projectiles instead and keep the rest of
-- the shot (ammo, reload, recoil, sound).
mod:hook(ActionShotgun, "_shoot", function (func, self, num_shots_total, num_shots_this_frame)
	local action = self.current_action

	if not action.ut_flak_chunks and not action.ut_flak_shell then
		return func(self, num_shots_total, num_shots_this_frame)
	end

	local lookup_data = action.lookup_data
	local shot = {
		is_critical_strike = self._is_critical_strike,
		item_name = self.item_name,
		item_template_name = lookup_data.item_template_name,
		owner_unit = self.owner_unit,
		power_level = self.power_level,
	}
	local position = self._fire_position:unbox()
	local rotation = self._fire_rotation:unbox()

	for _ = 1, num_shots_this_frame do
		self._shots_fired = self._shots_fired + 1

		if action.ut_flak_chunks then
			local chunk_position = position + Quaternion.forward(rotation) * CONFIG.chunk_spawn_forward + Quaternion.right(rotation) * CONFIG.chunk_spawn_right - Quaternion.up(rotation) * CONFIG.chunk_spawn_down

			spawn_projectile(shot, chunk_position, spread_rotation(rotation, math.degrees_to_radians(CONFIG.chunk_spread_degrees)), CHUNK_ACTION_NAME, random_chunk_action(), CONFIG.chunk_speed * CONFIG.debug_speed_scale)
		else
			local lobbed_rotation = Quaternion.multiply(rotation, Quaternion.axis_angle(Vector3.right(), math.degrees_to_radians(CONFIG.shell_lob_degrees)))

			local shell_position = position + Quaternion.forward(rotation) * CONFIG.shell_spawn_forward + Quaternion.right(rotation) * CONFIG.shell_spawn_right - Quaternion.up(rotation) * CONFIG.shell_spawn_down

			spawn_projectile(shot, shell_position, lobbed_rotation, SHELL_ACTION_NAME, SHELL_ACTION, CONFIG.shell_speed * CONFIG.debug_speed_scale)
		end
	end
end)

-- The explosion of the shell: the chunks. This runs where the shell's impact is handled, which is
-- on the machine of the player who fired it.
mod.aoe_callbacks.ut_flak_shell = function (self, aoe_data, position)
	if self._ut_flak_exploded then
		return
	end

	self._ut_flak_exploded = true

	local velocity = self.locomotion_extension:current_velocity()
	local direction = Vector3.length(velocity) > 0.001 and Vector3.normalize(velocity) or Vector3.up()
	local rotation = Quaternion.look(direction)
	local start = position - direction * CONFIG.shell_chunk_start_offset
	local lookup_data = self.action_lookup_data
	local shot = {
		is_critical_strike = self._is_critical_strike,
		item_name = self.item_name,
		item_template_name = lookup_data.item_template_name,
		owner_unit = self._owner_unit,
		power_level = self.power_level,
	}

	local explosion = ExplosionTemplates.ut_flak_shell_explosion.explosion

	utils.apply_explosion_self_damage(self._owner_unit, position, self.item_name, explosion, CONFIG.shell_self_damage)
	utils.apply_explosion_self_push(self._owner_unit, position, explosion, CONFIG.shell_jump_speed)

	for _ = 1, CONFIG.shell_chunk_count do
		spawn_projectile(shot, start, burst_rotation(rotation, math.degrees_to_radians(CONFIG.shell_chunk_cone_degrees)), CHUNK_ACTION_NAME, random_chunk_action(true), CONFIG.chunk_speed * CONFIG.debug_speed_scale)
	end
end

-- Runs after the game has bounced a chunk off the level. A chunk keeps part of its speed and starts to fall. A chunk that has no
-- bounces left goes cold instead: it slides along the surface and falls, and stops at the next surface it hits.
mod:hook_safe(ProjectileScriptUnitLocomotionExtension, "bounce", function (self, hit_position, hit_direction, hit_normal)
	local extension = ScriptUnit.has_extension(self.unit, "projectile_system")
	local action = extension and extension._current_action

	if action and action.ut_flak_chunk then
		self.gravity = ProjectileGravitySettings[CONFIG.chunk_bounce_gravity_settings]
		extension._ut_flak_bounced = true

		if (extension._ut_flak_bounces_left or 0) > 0 then
			extension._ut_flak_bounces_left = extension._ut_flak_bounces_left - 1
			self.speed = self.speed * CONFIG.chunk_bounce_speed_scale
		else
			local slide = hit_direction - hit_normal * Vector3.dot(hit_direction, hit_normal)

			if Vector3.length(slide) < 0.01 then
				slide = Vector3.down()
			end

			slide = Vector3.normalize(slide)

			self.target_vector_boxed:store(slide)
			self.radians = math.degrees_to_radians(ActionUtils.pitch_from_rotation(Quaternion.look(slide)))
			extension._ut_flak_cold = true

			-- The game stops a projectile that has no bounces left, on the next surface it hits.
			extension._num_bounces = math.huge
		end

		extension._num_additional_penetrations = math.max(extension._num_additional_penetrations - 1, 0)
	end
end)

-- What stops a chunk: the targets the game itself stops projectiles on, armor (armored and monster
-- armor, like the game does it) and an enemy that blocks with a shield
local function stops_chunk(self, hit_unit, hit_direction)
	local breed = AiUtils.unit_breed(hit_unit)

	if not breed then
		return false
	end

	if breed.armor_category == 2 or breed.armor_category == 3 then
		return true
	end

	return not not AiUtils.attack_is_shield_blocked(hit_unit, self._owner_unit, nil, hit_direction)
end

-- Ragdolls thrown by chunks: the hits are collected per target, and once the target has died and
-- its ragdoll has started (before that the actors are driven by animation) the body is thrown once,
-- with the speed of all the chunks that hit it. Runs on every peer, the physics of ragdolls is local.
local ragdoll_throws = {}

local function ragdoll_speed_at(distance)
	local fraction = math.clamp((distance - CONFIG.chunk_knockback_falloff_start) / (CONFIG.chunk_knockback_falloff_end - CONFIG.chunk_knockback_falloff_start), 0, 1)

	return math.lerp(CONFIG.chunk_ragdoll_speed_near, CONFIG.chunk_ragdoll_speed_far, fraction)
end

local function add_ragdoll_throw(hit_unit, owner_unit, hit_position, hit_direction)
	local owner_position = POSITION_LOOKUP[owner_unit]

	if not owner_position then
		return
	end

	local throw = ragdoll_throws[hit_unit]

	if not throw then
		throw = {
			t = Managers.time:time("game"),
			velocity = Vector3Box(0, 0, 0),
		}
		ragdoll_throws[hit_unit] = throw
	end

	local flat_direction = Vector3.normalize(Vector3.flat(hit_direction))

	throw.velocity:store(throw.velocity:unbox() + flat_direction * ragdoll_speed_at(Vector3.length(hit_position - owner_position)))
end

-- Returns true once the body has been thrown
local function throw_ragdoll(unit, velocity)
	local thrown = false

	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		if actor and Actor.is_dynamic(actor) then
			Actor.set_velocity(actor, velocity)

			thrown = true
		end
	end

	return thrown
end

local function update_ragdoll_throws()
	local t = Managers.time:time("game")

	for unit, throw in pairs(ragdoll_throws) do
		if not Unit.alive(unit) or t - throw.t > CONFIG.chunk_ragdoll_window then
			ragdoll_throws[unit] = nil
		elseif not HEALTH_ALIVE[unit] then
			local velocity = throw.velocity:unbox()
			local speed = Vector3.length(velocity)

			if speed > 0 then
				velocity = velocity * (math.min(speed, CONFIG.chunk_ragdoll_max_speed) / speed)
				velocity = velocity + Vector3(0, 0, Vector3.length(velocity) * CONFIG.chunk_ragdoll_up)
			end

			if throw_ragdoll(unit, velocity) then
				ragdoll_throws[unit] = nil
			end
		end
	end
end

-- Sets how many times the chunk bounces and how many enemies it goes through. The action's max_bounces is the bounces UT
-- gave the chunk plus chunk_extra_bounces, and the chunk can go through that many enemies. Going through an enemy is counted
-- as one of the game's bounces, so the action allows enough of them. Runs on every machine.
mod.init_callbacks.ut_flak_chunk = function (self)
	local max_bounces = self._current_action.impact_data.max_bounces

	self._num_additional_penetrations = max_bounces
	self._ut_flak_bounces_left = max_bounces - CONFIG.chunk_extra_bounces
	self._ut_flak_spawn_t = Managers.time:time("game")
end

-- Bounces the chunk off the shield of an enemy that blocks it, like off a wall. Returns false if the chunk can't bounce any more.
local function bounce_off_shield(self, impact_data, hit_unit, hit_position, hit_direction, hit_normal)
	local locomotion = self.locomotion_extension

	if not locomotion.bounce or self._num_bounces >= (impact_data.max_bounces or 0) then
		return false
	end

	-- The shield faces the way the enemy does.
	local normal = Vector3.flat(Quaternion.forward(Unit.world_rotation(hit_unit, 0)))

	if Vector3.length(normal) < 0.01 or Vector3.dot(normal, hit_direction) > 0 then
		normal = -hit_direction
	end

	normal = Vector3.normalize(normal)

	local breed = AiUtils.unit_breed(hit_unit)

	if breed and breed.blocking_hit_effect then
		EffectHelper.player_ranged_block_hit_particles(self._world, breed.blocking_hit_effect, hit_position, hit_direction, hit_unit)
	end

	locomotion:bounce(hit_position, hit_direction, normal)

	self._num_bounces = self._num_bounces + 1

	return true
end

-- The game's hitscan shotguns run the buffs that trigger on a hit (the headshot ammo trait, ...) only for the first pellet that hits, once per
-- shot (ActionShotgun's check_buffs). The chunks are projectiles that each run them. Here a shot runs them once, and once more if a chunk gets a
-- headshot after a hit that was not one, so a headshot by any chunk counts: shots[owner unit] = { t = the spawn time of the shot,
-- hit = if they have run, head = if they have run for a headshot }.
local shots = {}
local chunk_in_hit

mod:hook(DamageUtils, "buff_on_attack", function (func, unit, hit_unit, attack_type, is_critical_strike, hit_zone_name, ...)
	local chunk = chunk_in_hit

	if chunk and chunk._ut_flak_spawn_t then
		local spawn_t = chunk._ut_flak_spawn_t
		local shot = shots[unit]

		if not shot or math.abs(shot.t - spawn_t) >= CONFIG.shot_window then
			shot = { t = spawn_t }
			shots[unit] = shot
		end

		local head = hit_zone_name == "head"

		if shot.hit and (not head or shot.head) then
			return false
		end

		shot.hit = true
		shot.head = shot.head or head
	end

	return func(unit, hit_unit, attack_type, is_critical_strike, hit_zone_name, ...)
end)

mod.hit_enemy_callbacks.ut_flak_chunk = function (func, self, is_owner, impact_data, hit_unit, hit_position, hit_direction, hit_normal, ...)
	if AiUtils.attack_is_shield_blocked(hit_unit, self._owner_unit, nil, hit_direction) and bounce_off_shield(self, impact_data, hit_unit, hit_position, hit_direction, hit_normal) then
		return
	end

	-- armor stops a chunk (after it did its damage): the game stops a projectile that has
	-- nothing left to go through
	if stops_chunk(self, hit_unit, hit_direction) then
		self._num_additional_penetrations = 0
	end

	local penetrations_before = self._num_additional_penetrations

	-- the damage (and the knockback) of a chunk decays with its age. The power level is what
	-- the game reads for a hit, so it is scaled for the duration of it.
	local power_level = self.power_level
	local spawn_t = self._ut_flak_spawn_t

	if power_level and spawn_t then
		local age = Managers.time:time("game") - spawn_t
		local damage = math.max(CONFIG.chunk_damage_min, CONFIG.chunk_ut_damage - CONFIG.chunk_damage_decay * math.max(0, age - CONFIG.chunk_damage_decay_delay))

		self.power_level = power_level * damage / CONFIG.chunk_ut_damage

		-- A chunk that is too slow does no damage. The locomotion's velocity is the distance moved in the last frame.
		local locomotion = self.locomotion_extension
		local frame_time = locomotion.dt or 0

		if frame_time > 0.0001 and Vector3.length(locomotion:current_velocity()) / frame_time < CONFIG.chunk_speed * CONFIG.debug_speed_scale / 100 * CONFIG.chunk_min_speed_fraction then
			self.power_level = 0
		end
	end

	-- (an error mustn't leave the chunk set)
	chunk_in_hit = self

	local ok, error_message = pcall(func, self, impact_data, hit_unit, hit_position, hit_direction, hit_normal, ...)

	chunk_in_hit = nil
	self.power_level = power_level

	if not ok then
		error(error_message, 0)
	end

	if not AiUtils.attack_is_shield_blocked(hit_unit, self._owner_unit, nil, hit_direction) then
		add_ragdoll_throw(hit_unit, self._owner_unit, hit_position, hit_direction)
	end

	if self._num_additional_penetrations < penetrations_before then
		self._num_bounces = self._num_bounces + penetrations_before - self._num_additional_penetrations
	end
end

-- Returns the projectiles in flight: this machine's own and the copies of other players' (like find_ball_hit_by_beam in shock_rifle.lua).
-- Each entry is { unit, extension, own }.
local function flying_projectiles()
	local entity = Managers.state and Managers.state.entity
	local projectile_system = entity and entity:system("projectile_system")

	if not projectile_system then
		return nil
	end

	local projectiles = {}

	for _, units in pairs(projectile_system.player_projectile_units) do
		for unit in pairs(units) do
			local extension = Unit.alive(unit) and ScriptUnit.has_extension(unit, "projectile_system")

			if extension and extension._current_action then
				projectiles[#projectiles + 1] = { unit = unit, extension = extension, own = true }
			end
		end
	end

	for unit, extension in pairs(entity:get_entities("PlayerProjectileHuskExtension")) do
		if Unit.alive(unit) and extension._current_action then
			projectiles[#projectiles + 1] = { unit = unit, extension = extension, own = false }
		end
	end

	return projectiles
end

-- Hurts the player if a bounced chunk of theirs hits them.
local function hit_owner(chunk)
	local extension = chunk.extension
	local owner_unit = extension._owner_unit

	if not extension._ut_flak_bounced or extension._ut_flak_hit_owner or extension._stop_impacts then
		return
	end

	if not owner_unit or not Unit.alive(owner_unit) or not HEALTH_ALIVE[owner_unit] or not utils.is_local_player_unit(owner_unit) then
		return
	end

	-- (A player's entry in POSITION_LOOKUP is not a vector, so the position is read from the unit.)
	local feet = Unit.world_position(owner_unit, 0)
	local position = Unit.world_position(chunk.unit, 0)

	local feet_z = Vector3.z(feet)
	local closest = Vector3(Vector3.x(feet), Vector3.y(feet), feet_z + math.clamp(Vector3.z(position) - feet_z, 0, CONFIG.chunk_self_hit_height))

	if Vector3.distance(position, closest) > CONFIG.chunk_self_hit_radius then
		return
	end

	extension._ut_flak_hit_owner = true

	utils.apply_self_damage(owner_unit, position, Vector3.normalize(position - closest), extension.item_name, CONFIG.chunk_self_damage)
	extension:stop()
end

-- Makes a shell explode when another projectile of the mod touches it.
local function detonate_by_projectiles(shell, projectiles)
	local position = Unit.world_position(shell.unit, 0)

	if not position or shell.extension._ut_flak_exploded then
		return
	end

	for _, other in ipairs(projectiles) do
		local action = other.extension._current_action
		local other_position = Unit.world_position(other.unit, 0)

		if other ~= shell and (action.ut_shock_ball or action.ut_flak_shell or action.ut_rocket) and not other.extension._stop_impacts and other_position and Vector3.distance(position, other_position) < CONFIG.shell_trigger_radius then
			shell.extension:do_aoe(ExplosionTemplates.ut_flak_shell_explosion, position, true)
			shell.extension:stop()

			return
		end
	end
end

-- Pushes dead bodies near a shell away from it while it flies.
local function push_bodies(world, shell, dt)
	local position = Unit.world_position(shell.unit, 0)

	if not position then
		return
	end

	for unit in pairs(utils.units_in_radius(world, position, CONFIG.shell_force_radius)) do
		if not HEALTH_ALIVE[unit] then
			for i = 0, Unit.num_actors(unit) - 1 do
				local actor = Unit.actor(unit, i)

				if actor and Actor.is_dynamic(actor) then
					local offset = Actor.position(actor) - position
					local distance = Vector3.length(offset)

					if distance > 0.01 then
						Actor.set_velocity(actor, Actor.velocity(actor) + offset * (CONFIG.shell_force_acceleration * dt / distance))
					end
				end
			end
		end
	end
end

local function update_flying_projectiles(dt)
	local projectiles = flying_projectiles()

	if not projectiles or #projectiles == 0 then
		return
	end

	local world = Managers.world:world("level_world")

	for _, projectile in ipairs(projectiles) do
		local action = projectile.extension._current_action

		if action.ut_flak_shell and not projectile.extension._stop_impacts then
			push_bodies(world, projectile, dt)

			if projectile.own then
				detonate_by_projectiles(projectile, projectiles)
			end
		elseif action.ut_flak_chunk and projectile.own then
			hit_owner(projectile)
		end
	end
end

-- Bodies killed by a shell are thrown away from it. The throw is queued here and applied once the ragdoll has started, the same way as
-- for chunks. It runs on every machine, because ragdolls are simulated locally.
mod.explosion_before_callbacks.ut_flak_shell_explosion = function (world, position, attacker_unit)
	return {
		alive = utils.units_in_radius(world, position, ExplosionTemplates.ut_flak_shell_explosion.explosion.radius),
		attacker_unit = attacker_unit,
	}
end

-- The shell's explosion damages the beastmen standards (banners) in its radius. The chunks don't: a standard drops their damage.
mod.explosion_callbacks.ut_flak_shell_explosion = function (world, position, _, before)
	local t = Managers.time:time("game")

	mod.standards.blow_up(position, before and before.attacker_unit, ExplosionTemplates.ut_flak_shell_explosion.explosion.radius, DamageProfileTemplates.ut_flak_shell_explosion, CONFIG.shell_standard_power_level, mod.items.weapons.flak_cannon.key)

	for unit in pairs(before and before.alive or {}) do
		if Unit.alive(unit) and not HEALTH_ALIVE[unit] and not ragdoll_throws[unit] then
			local unit_position = Unit.world_position(unit, 0)
			local offset = Vector3.flat(unit_position - position)
			local distance = Vector3.length(offset)
			local direction = distance > 0.01 and offset * (1 / distance) or Vector3.up()
			local speed = CONFIG.shell_ragdoll_speed * math.lerp(1, 0.5, math.clamp(distance / ExplosionTemplates.ut_flak_shell_explosion.explosion.radius, 0, 1))

			-- (The upward speed is added when the body is thrown, as for chunks.)
			ragdoll_throws[unit] = {
				t = t,
				velocity = Vector3Box(direction * speed),
			}
		end
	end
end

-- The mod holds its own references to the units of the projectiles while the weapon is enabled
local packages = utils.package_holder("unreal_tournament_flak")

local function enable_flak_cannon()
	packages.load_projectile_units(PROJECTILE_UNIT_TEMPLATES)
	apply_flak_cannon()
end

-- Called when the mod is disabled or unloaded.
local function disable_flak_cannon()
	restore_blunderbuss()
end

mod.enabled_callbacks[#mod.enabled_callbacks + 1] = enable_flak_cannon
mod.disabled_callbacks[#mod.disabled_callbacks + 1] = disable_flak_cannon
mod.unload_callbacks[#mod.unload_callbacks + 1] = disable_flak_cannon

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	update_ragdoll_throws()
	update_flying_projectiles(dt)
end

mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
	table.clear(ragdoll_throws)
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(ragdoll_throws)
end
