local mod = get_mod("unreal_tournament")

-- Shield Gun: a copy of a melee weapon with its attacks replaced. The numbers come from UT2004 (XWeapons/ShieldGun, ShieldFire and
-- ShieldAltFire).
--   Left button: held, it charges the gun, for up to 2.5 seconds. Let go, it punches what is right in front with a wave of force, for
--       40 to 150 damage by how long it charged. While it charges, it punches by itself as soon as an enemy is in reach. Punching a wall
--       throws the player away from it (the shield jump).
--   Right button: the base weapon's block, made a shield block as the game's sword and shield has (SHIELD_FIELDS): it stops shots too.
--       UT's shield blocks what comes from the front and is drained by what it stops, which is what the game's block and stamina do. The
--       skin draws UT's shield while it is up.
--   Left button while blocking: the base weapon's push, which the skin draws as a shove of the shield. Both buttons held after it: a bash,
--       a punch as strong as a charge held since the push, with the shield down for a moment. UT has no push; this is the mod's own.
-- Each hero has a melee weapon to be a copy of, so the weapon is five items of the mod that share everything but the base. (The Warrior
-- Priest's is on the TODO list.)
-- The skin (skin.lua) draws all of it, and this file only sets what it does to the game.

local utils = mod.utils
local register_damage_profile = utils.register_damage_profile
local make_flat = utils.make_flat
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for
local first_beam_hit = utils.first_beam_hit

local DESCRIPTION = "The Kemphler DD280 Riot Control Device has the ability to resist and reflect incoming projectiles and energy beams. The plasma wave inflicts massive damage, rupturing tissue, pulverizing organs, and flooding the bloodstream with dangerous gas bubbles."

-- The items, one for each hero. The careers of each are those of its base.
local VARIANTS = {
	{
		base_item = "es_bastard_sword",
		deus_copy = "deus_es_bastard_sword",
		id = "shield_gun",
		key = "ut_shield_gun",
		template = "ut_shield_gun_template",
		-- The blunderbuss's pose. The punches are its shot there, and so is the push: its shove swings the butt of the gun forward.
		pose_3p = "to_blunderbuss",
		punch_3p = "attack_shoot",
		push_3p = "attack_shoot",
	},
	{
		base_item = "dr_2h_cog_hammer",
		deus_copy = "deus_dr_2h_cog_hammer",
		id = "shield_gun_dr",
		key = "ut_shield_gun_dr",
		template = "ut_shield_gun_dr_template",
		-- How the hero holds it in third person and on the hero screen (the hero's wield animation of another weapon): the grudge-raker's.
		-- The punches are its shot there, and the push its shove.
		pose_3p = "to_grudge_raker",
		punch_3p = "attack_shoot",
		push_3p = "attack_push",
	},
	{
		base_item = "bw_ghost_scythe",
		deus_copy = "deus_bw_ghost_scythe",
		id = "shield_gun_bw",
		key = "ut_shield_gun_bw",
		template = "ut_shield_gun_bw_template",
		-- The staffs' pose, as the Shock Rifle has (it is a copy of the beam staff). The push is the staffs' fireball shot, the Shock
		-- Rifle's second shot. The punches and the bash have no animation.
		pose_3p = "to_staff",
		push_3p = "attack_shoot_fireball",
	},
	{
		base_item = "wh_2h_billhook",
		deus_copy = "deus_wh_2h_billhook",
		id = "shield_gun_wh",
		key = "ut_shield_gun_wh",
		template = "ut_shield_gun_wh_template",
		-- The Volley Crossbow's pose. The shield is its aim, and so is a charge once it is held a while. The punch is its shot. It has
		-- no shove, so the push is its shot too.
		pose_3p = "to_repeating_crossbow",
		punch_3p = "attack_shoot",
		push_3p = "attack_shoot",
		aim_3p = "to_zoom",
		aim_end_3p = "to_unzoom",
	},
	{
		base_item = "we_spear",
		deus_copy = "deus_we_spear",
		id = "shield_gun_we",
		key = "ut_shield_gun_we",
		template = "ut_shield_gun_we_template",
		-- The Life Staff's pose (the Sister of the Thorn's: every career of hers has the same third person body, and so its animations).
		-- It has no shove, so the push is its shot. The punches and the bash have no animation. Its held second attack is not the shield:
		-- it turns the hand so far that the gun would point up.
		pose_3p = "to_life_staff",
		push_3p = "attack_shoot",
	},
}

for _, variant in ipairs(VARIANTS) do
	mod.items.register(variant.id, {
		key = variant.key,
		template = variant.template,
		base_item = variant.base_item,
		deus_copy = variant.deus_copy,
		name = "UT2004 Shield Gun",
		type_name = "Shield Gun",
		description = DESCRIPTION,
		keywords = { "weapon_keyword_high_damage", "weapon_keyword_charged_attack", "weapon_keyword_armour_piercing" },
		icon = "ut_shield_gun_icon",
		icon_package = "resource_packages/unreal_tournament/icons",
		icon_materials = "ui/ut/shield_gun_icon",
	})
end

local TEMPLATE_NAMES = {}
local POSES_3P = {}

for _, variant in ipairs(VARIANTS) do
	local template_name = mod.items.weapons[variant.id].template

	TEMPLATE_NAMES[template_name] = true
	POSES_3P[template_name] = variant.pose_3p and variant
end

local CONFIG = {
	-- ShieldFire.ShieldRange: how far a wall can be for a punch to throw the player off it (the shield jump), in UT units
	range = 112,
	-- How far the punch reaches what it hits, and the bash out of a push, in UT units, and how far the charge looks for an enemy to punch
	-- by itself. A little farther than UT's ShieldRange (a choice): at 112 units, dodging into an enemy slid the player off it before
	-- the charge found it in reach, and 131 reached too far.
	hit_range = 122,
	bash_range = 162,
	-- The punch hits every enemy within its range in a cone this wide (degrees) about the way the player looks, that it can see. UT's
	-- punch hits the one thing in front: this is the mod's own, and a guess.
	hit_angle = 60,
	-- What the punch throws (see throws below): DamTypeShieldImpact's death throw (xPawn.PlayDying), KDeathVel along the way the punch
	-- went (its momentum, Force * (X + 0.5 up), so lifted by half) and KDeathUpKick up, in UT units a second. A body is thrown once it
	-- falls, if it dies within ragdoll_window seconds of the hit, and the throw is held for kill_hold seconds. The throw of a body the punch
	-- kills is as strong as the punch's force is of MaxForce, so this at full charge (a choice: UT's death throw is the same for any).
	ragdoll_speed = 450,
	ragdoll_up = 300,
	ragdoll_window = 1.5,
	kill_hold = 0.15,
	-- The punch reaches from the middle of the player (Instigator.Location), not from the eyes: xPawn's CollisionHeight (44) above the
	-- feet, and CrouchHeight (29) when crouched, in UT units. So the floor is in reach while looking up to 67 degrees from straight down.
	reach_height = 44,
	reach_height_crouched = 29,
	-- ShieldFire.MinHoldTime and FullyChargedTime: held for MinHoldTime or less, the punch does MinDamage; held for FullyChargedTime or
	-- more, MaxDamage; in between, in a line
	min_hold_time = 0.4,
	fully_charged_time = 2.5,
	min_damage = 40,
	max_damage = 150,
	-- The damage is a profile for each of this many steps between the two
	damage_steps = 12,
	-- The punch by how far the charge went, each up to the share of the charge given: the game's damage type, a two-handed hammer's light,
	-- normal and heavy blows, which hit wide ("tank"), which chooses how the game shows a hit and a death (the hit effects: the push of the
	-- body, its sounds); the share of UT's damage it does, less than UT's (a choice); and how many enemies it gets
	-- through, as a swing with the game's cleave of that name does (light to heavy tank blows that reach about half as far as the
	-- two-handed hammer's: a choice). Its stagger and the player's own damage of a shield jump are still worked out from UT's damage.
	damage_types = {
		{ 1 / 3, "light_blunt_tank", 1 / 2, "cleave_distribution_tank_spiked_L" },
		{ 2 / 3, "blunt_tank", 1 / 2, "cleave_distribution_tank_dual_L" },
		{ 1, "heavy_blunt_tank", 2 / 3, "cleave_distribution_burning_tank_M" },
	},
	-- The bash out of a push is the blow of this third of the charge (above), its damage type and share, whatever its time held gives
	bash_damage_type = 2,
	-- ShieldFire: punching a wall hurts the player MinSelfDamage + SelfDamageScale * the damage. UT's DeathMatch.ReduceDamage halves a
	-- player's own damage in a game with bots at the lower skills, and the Rocket Launcher and the Flak Cannon of the mod take that half too.
	min_self_damage = 8,
	self_damage_scale = 0.3,
	self_damage_share = 0.5,
	-- ShieldFire.FireRate: after a punch, the next charge starts this long after
	fire_rate = 0.6,
	-- The bash out of a push (not UT's: see build_bash): the shield is down this long after it, the length of UT's Fire animation
	bash_shield_down = 0.5,
	-- A base weapon without a push-stab gets one at these times into the push, the bastard sword's
	bash_window = {0.4, 0.8},
	-- ShieldFire.AutoFireTestFreq: how often the charge looks for an enemy in reach
	auto_fire_test_freq = 0.15,
	-- ShieldFire.MinForce and MaxForce: the push of a punch, UT's momentum. A wall pushes the player back with SelfForceScale (1) of
	-- it. UT divides momentum by the player's mass (100) for the speed, and on the ground makes the upward part at least 0.4 of it
	-- (Pawn.TakeDamage).
	min_force = 65000,
	max_force = 100000,
	self_force_scale = 1,
	ut_mass = 100,
	ground_lift = 0.4,
	-- Pawn.TakeDamage takes the momentum a player gives themselves down to this share (instigatedBy == self), after the lift
	self_momentum = 0.6,
	-- UT speeds are turned into this game's, upward by the ratio of the jumps (UT's JumpZ is 340 units a second, and the mod's jump is
	-- 4.25 * 1.35 m/s, movement.lua) and along the ground by the ratio of the run speeds (UT's GroundSpeed is 440, and the game's is
	-- PlayerUnitMovementSettings.move_speed). This game runs slower for its jump than UT, so one ratio for both would push the player
	-- along the ground about twice as hard for their run as UT does. The movement's dodges are made from the run speed the same way.
	ut_speed_to_mps = 4.25 * 1.35 / 340,
	ut_ground_speed = 440,
	-- The multipliers of the damage and the stagger for each armor type: unarmored, armored, monsters, players, berserkers and super
	-- armor. UT has no armor, and the punch's force is not stopped by it.
	armor_attack = {1, 1, 1, 1, 1, 0.8},
	armor_impact = {1, 1, 1, 1, 1, 1},
	-- The punch's stagger is this many times what its damage gives. UT's punch throws a pawn back with all its momentum (650 to 1000
	-- units a second), far more than a stagger of its damage. This number is a choice.
	stagger_multiplier = 2,
	-- The spin of a body the punch kills (xPawn.PlayDying): RagInvInertia times where it was hit from its middle, across the throw, with
	-- the hit's sideways distance made RagSpinScale times longer, in UT's rotation units (65536 a turn). The middle is the pawn's
	-- (CollisionHeight above the feet).
	spin_inverse_inertia = 4,
	spin_sideways_scale = 2.5,
	-- The spin is this many times UT's, which looked too little in this game: a choice
	spin_multiplier = 3,
	-- The push of a body that is down already, as the game pushes a body for a hit (GenericHitReactionExtension._do_push: Actor.push on the
	-- push actors of the zone it hit), with the forces of a hit effect's push. These are near the strongest the game's hit effects have
	-- (explosions' 300): a choice.
	body_push_distal = 250,
	body_push_vertical = 100,
	-- Reflection (ShieldGun.CheckReflect): a shot that touches a player while their shield is up is sent on the way they look, if it
	-- comes from within this of where they look (the dot product of the look and the way from the hit to them, -0.37 for 68 degrees).
	-- What touches a player is their collision cylinder (xPawn's CollisionRadius 25 and the heights above, in UT units). The shield's
	-- charge it costs in UT is the game's stamina for blocking a shot here. Every UT shot that is reflective is: the Shock Rifle's beam
	-- (InstantFire.DoTrace, at most max_reflections times) and ball (ShockProjectile), and the Link Gun's bolt (LinkProjectile), which
	-- start again reflect_offset UT units out from the hit.
	reflect_dot = -0.37,
	reflect_up_offset = 8,
	pawn_radius = 25,
	max_reflections = 3,
	reflect_offset = 20,
	-- The shield also reflects what UT has no counterpart of (the mod's own): a sorcerer's magic missile, which then blows up as this
	-- explosion of the player's (the charged fireball's, which looks and sounds like the missile's own), and a gutter runner's pounce,
	-- which throws it back. The game snaps a pounce onto a player from 2 m and pins whoever is within 1 m of it, so a pounce reaches the
	-- shield pounce_radius meters out from the player's cylinder (2 m from their middle). These cost the stamina of blocking a shot and
	-- a jump attack.
	-- ShieldGun.AdjustPlayerDamage: the shield takes up to this much of a fall's damage (its DamageMax for Fell), if it is up and the
	-- player looks down into the fall, for the stamina of a blocked attack
	fall_absorb = 20,
	fall_fatigue_type = "blocked_attack",
	reflected_missile_explosion = "fireball_charged",
	pounce_radius = 1.5,
	pounce_fatigue_type = "blocked_jump_slam",
	-- A lifeleech's grab that gets to a player's shield fails, as when they dodge it, for the stamina of blocking a jump attack too
	grab_fatigue_type = "blocked_jump_slam",
	-- An explosion that the shield stops costs 6 fatigue points, half of the gun's 6 stamina shields of 2 points: UT's shield gives half
	-- of the damage it stops from its charge of 100, and an explosion of its weapons does about 90
	explosion_fatigue_type = "blocked_sv_sweep_2",
}

local UNIT = utils.UT_UNIT

-- What the gun does now, on the player's own machine, for the skin
mod.shield = {
	charge_started = nil, -- when the charge started, or nil
	last_punch = nil, -- when the last punch was
	fully_charged_time = CONFIG.fully_charged_time,
	-- How long after a push a bash can come, while both buttons are held
	bash_window_end = CONFIG.bash_window[2],
	-- Where on the charge (0 to FullyChargedTime, as a share) the punch becomes the next blow (damage_types), for the charge bar
	charge_marks = {},
	-- What any character's gun does, on the machine that owns their actions (the player's own, and the bots on the host), for the third
	-- person: mod.shield.event_callbacks[name] = function (owner_unit, event), where event is one of mod.shield.events
	event_callbacks = {},
	events = {
		charge = 1, -- the charge starts
		charge_end = 2, -- the charge ends without a punch
		punch = 3, -- the punch, or the bash out of a push
		hit = 4, -- the shield stops something
	},
}

local function tell(owner_unit, event)
	for _, callback in pairs(mod.shield.event_callbacks) do
		callback(owner_unit, event)
	end
end

-- A step is the charge's share between MinHoldTime and FullyChargedTime, rounded (charge_step below). A blow holds up to the last step at or
-- under its share, so the next starts where the charge rounds to the step after that.
for i = 1, #CONFIG.damage_types - 1 do
	local last_step = math.floor(CONFIG.damage_types[i][1] * (CONFIG.damage_steps - 1) + 0.0001)
	local scale = (last_step + 0.5) / (CONFIG.damage_steps - 1)
	local hold_time = CONFIG.min_hold_time + scale * (CONFIG.fully_charged_time - CONFIG.min_hold_time)

	mod.shield.charge_marks[i] = hold_time / CONFIG.fully_charged_time
end

-- Damage profiles: one for each step of the charge

local function damage_for_step(step)
	return CONFIG.min_damage + (CONFIG.max_damage - CONFIG.min_damage) * step / (CONFIG.damage_steps - 1)
end

-- Makes the damage profile of a punch of a step of the charge, of a damage type, a share of UT's damage and the game's cleave, and
-- returns the punch as a melee action, for its hits (see melee_hit)
local function make_punch_action(name, damage, damage_type, damage_share, cleave, charge_value)
	register_damage_profile(name, "shot_sniper", function (profile)
		make_flat(profile, attack_power_for(damage * damage_share), impact_power_for(damage) * CONFIG.stagger_multiplier, damage_type)

		-- It is a melee blow to the game (what talents, traits and buffs take it for), not the sniper shot the profile is made from
		profile.charge_value = charge_value

		-- How many enemies it gets through (see punch)
		profile.cleave_distribution = table.clone(PowerLevelTemplates[cleave])

		-- (a critical hit too, which would have the sniper shot's own armor multipliers)
		utils.set_armor_modifiers(profile, CONFIG.armor_attack, CONFIG.armor_impact, true)

		-- A punch has no headshots, as in UT (and a hit on the head is moved to the body, see body_hit)
		profile.no_headshot_boost = true
	end)

	-- A melee swing for its critical hits, with the sounds of a two-handed hammer's hits
	return {
		additional_critical_strike_chance = 0,
		damage_profile = name,
		impact_sound_event = "hammer_2h_hit",
		kind = "sweep",
		no_damage_impact_sound_event = "blunt_hit_armour",
		no_headshot_sound = true,
	}
end

-- The punches of each step of the charge (their damage type and share by the third of the charge, see damage_types), and the bashes,
-- which are the middle third's whatever their step (bash_damage_type)
local PUNCH_ACTIONS = {}
local BASH_ACTIONS = {}

for step = 0, CONFIG.damage_steps - 1 do
	local damage = damage_for_step(step)
	local share = step / (CONFIG.damage_steps - 1)
	local blow
	local bash_blow = CONFIG.damage_types[CONFIG.bash_damage_type]

	for _, entry in ipairs(CONFIG.damage_types) do
		if not blow and share <= entry[1] + 0.0001 then
			blow = entry
		end
	end

	-- (a charged punch is a heavy attack, and the bash a light one, as the game's push-stab is)
	PUNCH_ACTIONS[step] = make_punch_action("ut_shield_punch_" .. step, damage, blow[2], blow[3], blow[4], "heavy_attack")
	BASH_ACTIONS[step] = make_punch_action("ut_shield_bash_" .. step, damage, bash_blow[2], bash_blow[3], bash_blow[4], "light_attack")
end

-- The step of the charge after holding for some time (ShieldFire.DoFireEffect)
local function charge_step(hold_time)
	local scale = (math.clamp(hold_time, CONFIG.min_hold_time, CONFIG.fully_charged_time) - CONFIG.min_hold_time) / (CONFIG.fully_charged_time - CONFIG.min_hold_time)

	return math.floor(scale * (CONFIG.damage_steps - 1) + 0.5), scale
end

-- What is in reach in front of a player: the first thing the ray from their middle, the way they look, hits within the range (UT
-- units), and whether it is an enemy. The ray finds enemies and the level as a shot does, and the things a melee swing hits (doors,
-- barrels, loose things, bodies) as the swing does (filter_melee_sweep), whichever is nearer.
-- The engine fills the same tables with the hits of the next ray, so the hits of a ray that are kept past the next one are copies. A
-- punch kept the hit straight ahead while it cast its rays at the enemies in its cone, and one of those started in the player's own
-- head: the punch then hit the player.
local function copies(hits)
	local copied = {}

	for i = 1, #(hits or {}) do
		local hit = hits[i]

		copied[i] = { hit[1], hit[2], hit[3], hit[4] }
	end

	return copied
end

local function raycast(physics_world, origin, direction, range)
	return copies(PhysicsWorld.immediate_raycast_actors(physics_world, origin, direction, range * UNIT, "static_collision_filter", "filter_player_ray_projectile_static_only", "dynamic_collision_filter", "filter_player_ray_projectile_ai_only", "dynamic_collision_filter", "filter_player_ray_projectile_hitbox_only"))
end

-- Whether a melee swing that hits this actor hits a thing that is not a character: one with health (a door, a barrel), or one whose part
-- is not a static part of the level (a loose thing, a body, a lantern that hangs, which hangs by a kinematic part)
local function is_object(unit, actor, owner_unit)
	return unit ~= owner_unit and (ScriptUnit.has_extension(unit, "health_system") and not Unit.get_data(unit, "breed") or not Actor.is_static(actor))
end

-- Whether the unit is a dead character
local function is_body(unit)
	return Unit.get_data(unit, "breed") ~= nil and not HEALTH_ALIVE[unit]
end

-- The first such thing along the ray, past the dead bodies
local function first_object_hit(physics_world, origin, direction, range, owner_unit)
	local hits = copies(PhysicsWorld.immediate_raycast(physics_world, origin, direction, range * UNIT, "all", "collision_filter", "filter_melee_sweep"))

	for i = 1, #hits do
		local actor = hits[i][4]
		local unit = actor and Actor.unit(actor)

		if unit and not is_body(unit) and is_object(unit, actor, owner_unit) then
			return hits[i]
		end
	end
end

-- The hits of a ray without the dead bodies, which the ray goes through (the punch finds bodies with targets_in_reach)
local function without_bodies(hits)
	local kept = {}

	for i = 1, #(hits or {}) do
		local unit = ActionUtils.redirect_shield_hit(Actor.unit(hits[i][4]), hits[i][4])

		if not is_body(unit) then
			kept[#kept + 1] = hits[i]
		end
	end

	return kept
end

local function in_reach(owner_unit, physics_world, range)
	local first_person_extension = ScriptUnit.has_extension(owner_unit, "first_person_system")

	if not first_person_extension then
		return nil
	end

	local status_extension = ScriptUnit.has_extension(owner_unit, "status_system")
	local height = status_extension and status_extension:is_crouching() and CONFIG.reach_height_crouched or CONFIG.reach_height
	local origin = Unit.local_position(owner_unit, 0) + Vector3(0, 0, height * UNIT)
	local direction = Quaternion.forward(first_person_extension:current_rotation())
	local eye = first_person_extension:current_position()

	-- The enemy the crosshair is on. The crosshair is at the eye: close up, a ray from the middle along the view passes under it.
	local ahead = first_beam_hit(without_bodies(raycast(physics_world, eye, direction, range)), owner_unit)
	local ahead_unit = ahead and ActionUtils.redirect_shield_hit(Actor.unit(ahead[4]), ahead[4])

	if ahead_unit and Unit.get_data(ahead_unit, "breed") and HEALTH_ALIVE[ahead_unit] then
		return ahead, true, direction, origin, eye
	end

	local hit = first_beam_hit(without_bodies(raycast(physics_world, origin, direction, range)), owner_unit)
	local object = first_object_hit(physics_world, origin, direction, range, owner_unit)

	if object and (not hit or object[2] < hit[2]) then
		hit = object
	end

	if not hit then
		return nil, nil, direction, origin, eye
	end

	local hit_unit = ActionUtils.redirect_shield_hit(Actor.unit(hit[4]), hit[4])

	return hit, Unit.get_data(hit_unit, "breed") ~= nil and HEALTH_ALIVE[hit_unit] or false, direction, origin, eye
end

-- The enemies and bodies in the cone of the punch (hit_angle) within the range, that a ray from the player reaches without a wall in
-- the way. Each is { unit, hit }: the hit is where that ray meets it, as a shot's hit is. The cone is about the crosshair, so the origin
-- is the eye.
local function targets_in_reach(owner_unit, physics_world, origin, direction, range)
	local world = Managers.world:world("level_world")
	local min_dot = math.cos(math.rad(CONFIG.hit_angle / 2))
	local targets = {}

	for unit in pairs(utils.units_in_radius(world, origin, range * UNIT)) do
		local node = Unit.has_node(unit, "j_spine") and Unit.node(unit, "j_spine") or 0
		local to = Unit.world_position(unit, node) - origin
		local distance = Vector3.length(to)

		if unit ~= owner_unit and distance > 0.01 and Vector3.dot(to / distance, direction) >= min_dot and not HEALTH_ALIVE[unit] then
			-- (a body: its hit zones are off, so it is thrown without looking for them)
			targets[#targets + 1] = {
				unit = unit,
			}
		elseif unit ~= owner_unit and distance > 0.01 and Vector3.dot(to / distance, direction) >= min_dot then
			local hits = raycast(physics_world, origin, to / distance, range)

			for i = 1, #(hits or {}) do
				local hit_actor = hits[i][4]
				local hit_unit = ActionUtils.redirect_shield_hit(Actor.unit(hit_actor), hit_actor)
				local breed = Unit.get_data(hit_unit, "breed")
				local zone = breed and breed.hit_zones_lookup and breed.hit_zones_lookup[Actor.node(hit_actor)]

				-- (the "afro" zone is far bigger than the enemy, for near misses, and a hit on it does nothing: the ray goes on)
				if hit_unit == unit and not (zone and zone.name == "afro") then
					targets[#targets + 1] = {
						hit = hits[i],
						unit = unit,
					}

					break
				elseif not breed then
					-- (a wall in the way)
					break
				end
			end
		end
	end

	return targets
end

-- The things that are not characters (is_object, but not bodies, which are targets) in the same cone within the range, as a melee swing
-- hits whatever it passes through. Each is { unit, hit }, with the hit of a ray from the player to it that nothing else stops (characters
-- don't). Two kinds of bodies are looked for: what a melee swing hits (filter_melee_sweep: doors, barrels, standards), and the bodies of
-- props that move, which only explosions find (filter_explosion_overlap: a lantern that hangs, as the Link Gun finds it). A body of the
-- second kind is reached if no wall is in the way.
local OBJECT_FILTERS = { "filter_melee_sweep", "filter_explosion_overlap" }

local function objects_in_reach(owner_unit, physics_world, origin, direction, range)
	local min_dot = math.cos(math.rad(CONFIG.hit_angle / 2))
	local objects = {}
	local found = {}

	for _, filter in ipairs(OBJECT_FILTERS) do
		local actors, num_actors = PhysicsWorld.immediate_overlap(physics_world, "shape", "sphere", "position", origin, "size", range * UNIT, "types", "both", "collision_filter", filter)

		for i = 1, num_actors or 0 do
			local actor = actors[i]
			local unit = actor and Actor.unit(actor)
			local to = unit and Actor.position(actor) - origin
			local distance = to and Vector3.length(to)

			if unit and not found[unit] and not Unit.get_data(unit, "breed") and is_object(unit, actor, owner_unit) and distance > 0.01 and Vector3.dot(to / distance, direction) >= min_dot then
				local hit

				if filter == "filter_melee_sweep" then
					local hits = copies(PhysicsWorld.immediate_raycast(physics_world, origin, to / distance, range * UNIT, "all", "collision_filter", filter))

					for j = 1, #hits do
						local hit_unit = hits[j][4] and Actor.unit(hits[j][4])

						if hit_unit == unit then
							hit = hits[j]

							break
						elseif hit_unit ~= owner_unit and not (hit_unit and Unit.get_data(hit_unit, "breed")) then
							-- (a wall or another thing in the way)
							break
						end
					end
				elseif not Actor.is_static(actor) then
					local wall, _, wall_distance = PhysicsWorld.immediate_raycast(physics_world, origin, to / distance, distance, "closest", "collision_filter", "filter_player_ray_projectile_static_only")

					if not wall or wall_distance >= distance - 0.05 then
						-- (where the ray meets the thing's surface, or its middle if the ray misses it)
						local hits = copies(PhysicsWorld.immediate_raycast(physics_world, origin, to / distance, distance + 1, "all", "collision_filter", filter))

						for j = 1, #hits do
							if hits[j][4] and Actor.unit(hits[j][4]) == unit then
								hit = hits[j]

								break
							end
						end

						hit = hit or {
							Actor.position(actor),
							distance,
							-to / distance,
							actor,
						}
					end
				end

				if hit then
					found[unit] = true
					objects[#objects + 1] = {
						hit = hit,
						unit = unit,
					}
				end
			end
		end
	end

	return objects
end

-- The charge ends by itself when an enemy comes into reach (ShieldFire.Timer). The game asks this every frame while the charge goes
-- on, and it looks every auto_fire_test_freq seconds.
local next_auto_test = {}

local function enemy_in_reach(unit)
	local t = Managers.time:time("game")

	if next_auto_test[unit] and t < next_auto_test[unit] then
		return false
	end

	next_auto_test[unit] = t + CONFIG.auto_fire_test_freq

	local physics_world = World.get_data(Managers.world:world("level_world"), "physics_world")
	-- (as far as the punch reaches)
	local _, is_enemy, direction, origin, eye = in_reach(unit, physics_world, CONFIG.hit_range)

	if is_enemy then
		return true
	elseif not origin then
		return false
	end

	for _, target in ipairs(targets_in_reach(unit, physics_world, eye, direction, CONFIG.hit_range)) do
		if HEALTH_ALIVE[target.unit] then
			return true
		end
	end

	return false
end

-- The shield jump: punching a wall pushes the player away from it (ShieldFire.DoFireEffect, Pawn.TakeDamage)
local function push_player(owner_unit, direction, force)
	local locomotion_extension = ScriptUnit.has_extension(owner_unit, "locomotion_system")

	if not locomotion_extension then
		return
	end

	local momentum = -direction * (CONFIG.self_force_scale * force / CONFIG.ut_mass)

	if locomotion_extension:is_on_ground() then
		local size = Vector3.length(momentum)

		momentum = Vector3(momentum.x, momentum.y, math.max(momentum.z, CONFIG.ground_lift * size))
	end

	local ground_scale = PlayerUnitMovementSettings.move_speed / CONFIG.ut_ground_speed
	local push = Vector3(momentum.x * ground_scale, momentum.y * ground_scale, momentum.z * CONFIG.ut_speed_to_mps) * CONFIG.self_momentum
	local velocity = locomotion_extension:current_velocity() + push

	locomotion_extension:set_maximum_upwards_velocity(math.huge)
	locomotion_extension:force_on_ground(false)
	locomotion_extension:set_forced_velocity(velocity)
	locomotion_extension:set_wanted_velocity(velocity)
end

-- What a punch throws, besides the push that the game gives a body for any hit. This runs on every machine, because the physics of bodies
-- is each machine's own, so the machine of the punch tells the others. There are two kinds:
--   KILL: an enemy the punch hits. If it dies, its body is thrown with the punch's momentum once it falls (its parts move by physics only
--       then), every part alike, as UT starts a ragdoll with a velocity (xPawn.PlayDying). The velocity is held for kill_hold seconds,
--       because for its first moments the body is still moved by its animation, and the game pushes it too.
--   LOOSE: a loose thing, which is pushed where the punch hit it, as UT pushes a physics object it hits (KAddImpulse at the hit). A hit
--       off its middle turns it, and the parts joined to it (a lantern's chain) move with it. A part that is held still (kinematic) is
--       pushed once the game lets it move, which a lantern's hit does.
local KILL, LOOSE = 1, 2
local throws = {}

local function add_throw(unit, kind, velocity, spin, at)
	throws[unit] = {
		at = Vector3Box(at),
		kind = kind,
		spin = Vector3Box(spin),
		t = Managers.time:time("game"),
		velocity = Vector3Box(velocity),
	}
end

-- Gives the part of a unit that physics moves, nearest to a point, a velocity at that point. Returns whether there was such a part.
local function push_part(unit, velocity, at)
	local nearest, nearest_distance

	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		if actor and utils.moved_by_physics(actor) then
			local distance = Vector3.distance(Actor.center_of_mass(actor), at)

			if not nearest or distance < nearest_distance then
				nearest, nearest_distance = actor, distance
			end
		end
	end

	if nearest then
		Actor.add_velocity_at(nearest, velocity, at)
	end

	return nearest ~= nil
end

-- Sets the velocity and the spin (radians a second, about each axis) of the moving parts of a unit, as one body: each part also moves
-- with the spin about the middle of the parts, so that the whole body turns, not each part in its place. Returns whether anything moved.
local function move_parts(unit, velocity, spin)
	local actors = {}
	local middle = Vector3.zero()

	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		if actor and utils.moved_by_physics(actor) then
			actors[#actors + 1] = actor
			middle = middle + Actor.position(actor)
		end
	end

	if #actors == 0 then
		return false
	end

	middle = middle / #actors

	for _, actor in ipairs(actors) do
		Actor.set_velocity(actor, velocity + Vector3.cross(spin, Actor.position(actor) - middle))
		Actor.set_angular_velocity(actor, spin)
	end

	return true
end

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	local t = Managers.time:time("game")

	for unit, throw in pairs(throws) do
		local velocity, spin = throw.velocity:unbox(), throw.spin:unbox()

		if not Unit.alive(unit) or t - throw.t > CONFIG.ragdoll_window or throw.thrown_t and t - throw.thrown_t > CONFIG.kill_hold then
			throws[unit] = nil
		elseif throw.kind == KILL then
			if not HEALTH_ALIVE[unit] and move_parts(unit, velocity, spin) then
				throw.thrown_t = throw.thrown_t or t
			end
		elseif push_part(unit, velocity, throw.at:unbox()) then
			throws[unit] = nil
		end
	end
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(throws)
end

mod:network_register("ut_shield_throw", function (_, id, is_level_unit, kind, x, y, z, spin_x, spin_y, spin_z, at_x, at_y, at_z)
	local unit = Managers.state.network:game_object_or_level_unit(id, is_level_unit == 1)

	if unit and Unit.alive(unit) then
		add_throw(unit, kind, Vector3(x, y, z), Vector3(spin_x or 0, spin_y or 0, spin_z or 0), at_x and Vector3(at_x, at_y, at_z) or Unit.world_position(unit, 0))
	end
end)

-- The spin of a body the punch kills (xPawn.PlayDying), from where it was hit, in radians a second
local function death_spin(unit, at, shot)
	local middle = Unit.world_position(unit, 0) + Vector3(0, 0, CONFIG.reach_height * UNIT)
	local from_middle = (at - middle) / UNIT

	from_middle = Vector3(Vector3.x(from_middle) * CONFIG.spin_sideways_scale, Vector3.y(from_middle) * CONFIG.spin_sideways_scale, Vector3.z(from_middle))

	return Vector3.cross(from_middle, shot) * (CONFIG.spin_inverse_inertia * CONFIG.spin_multiplier * 2 * math.pi / 65536)
end

-- Throws what the punch hit, here and on the other machines. alive says that it is an enemy that was alive before the punch (which may
-- have killed it), not a loose thing. at is where the punch hit it, and force the punch's.
local function throw_hit(unit, direction, alive, at, force)
	local kind = alive and KILL or LOOSE
	local shot = Vector3.normalize(direction + Vector3(0, 0, 0.5)) * CONFIG.ragdoll_speed
	local velocity = (shot + Vector3(0, 0, CONFIG.ragdoll_up)) * (UNIT * (alive and force / CONFIG.max_force or 1))
	local spin = alive and at and death_spin(unit, at, shot) or Vector3.zero()
	local id, is_level_unit = Managers.state.network:game_object_or_level_id(unit)

	at = at or Unit.world_position(unit, 0)

	add_throw(unit, kind, velocity, spin, at)

	if id then
		mod:network_send("ut_shield_throw", "others", id, is_level_unit and 1 or 0, kind, Vector3.x(velocity), Vector3.y(velocity), Vector3.z(velocity), Vector3.x(spin), Vector3.y(spin), Vector3.z(spin), Vector3.x(at), Vector3.y(at), Vector3.z(at))
	end
end

-- Pushes a body that is down already, at the zone it was hit, the way the game pushes a body for a hit (GenericHitReactionExtension._do_push)
local function push_body(unit, zone_name, direction)
	local breed = Unit.get_data(unit, "breed")
	local zone = breed and breed.hit_zones and breed.hit_zones[zone_name]
	local push_actors = zone and zone.push_actors

	if not push_actors then
		return
	end

	local force = (Vector3.normalize(Vector3.flat(direction)) * CONFIG.body_push_distal + Vector3(0, 0, CONFIG.body_push_vertical)) * ((breed.scale_death_push or 1) * 0.25)
	local velocity = Vector3.normalize(force) * 60
	local mass = Vector3.length(force) / #push_actors

	for _, name in ipairs(push_actors) do
		local actor = Unit.actor(unit, name)

		-- (a part pinned to a wall is kinematic)
		if actor and utils.moved_by_physics(actor) then
			Actor.push(actor, velocity, mass)
		end
	end
end

mod:network_register("ut_shield_body_push", function (_, id, zone_name, x, y, z)
	local unit = Managers.state.unit_storage:unit(id)

	if unit and Unit.alive(unit) then
		push_body(unit, zone_name, Vector3(x, y, z))
	end
end)

-- The zones a punch doesn't hit: "afro" is the bigger zone for near misses, and a punch has no headshots
local NOT_PUNCHED = {
	afro = true,
	head = true,
	neck = true,
}

-- The zone of an enemy that a hit is on
local function hit_zone_name(hit)
	local actor = hit and hit[4]
	local unit = actor and Actor.unit(actor)
	local breed = unit and Unit.get_data(unit, "breed")
	local zone = breed and breed.hit_zones_lookup and breed.hit_zones_lookup[Actor.node(actor)]

	return zone and zone.name
end

-- A thing with no health is hit as a melee swing hits the level (ActionSweep): the game sets where the hit was and where it came from on
-- the unit and gives it the flow event of a hit, and the level does the rest, such as a lantern that hangs swinging or coming down. The
-- flow event is each machine's own, so the others are told what was hit, and give it too.
local function give_simple_damage(unit, actor, position, direction)
	Unit.set_flow_variable(unit, "hit_actor", actor)
	Unit.set_flow_variable(unit, "hit_direction", direction)
	Unit.set_flow_variable(unit, "hit_position", position)
	Unit.flow_event(unit, "lua_simple_damage")
end

mod:network_register("ut_shield_simple_damage", function (_, id, is_level_unit, actor_index, x, y, z, direction_x, direction_y, direction_z)
	local unit = Managers.state.network:game_object_or_level_unit(id, is_level_unit == 1)
	local actor = unit and Unit.alive(unit) and actor_index < Unit.num_actors(unit) and Unit.actor(unit, actor_index)

	if actor then
		give_simple_damage(unit, actor, Vector3(x, y, z), Vector3(direction_x, direction_y, direction_z))
	end
end)

local function simple_damage(unit, actor, position, direction)
	give_simple_damage(unit, actor, position, direction)

	local id, is_level_unit = Managers.state.network:game_object_or_level_id(unit)

	for i = 0, id and Unit.num_actors(unit) - 1 or -1 do
		if Unit.actor(unit, i) == actor then
			mod:network_send("ut_shield_simple_damage", "others", id, is_level_unit and 1 or 0, i, Vector3.x(position), Vector3.y(position), Vector3.z(position), Vector3.x(direction), Vector3.y(direction), Vector3.z(direction))

			break
		end
	end
end

-- What the punch does to a thing that is not a character, as a melee swing does (ActionSweep.hit_level_object and the attack of a unit
-- with health): doors, barrels and the like take its damage, and a thing with no health gets the hit above
local function hit_object(action, hit_unit, hit, direction, damage_profile_name, power_level, blow)
	if not ScriptUnit.has_extension(hit_unit, "health_system") then
		simple_damage(hit_unit, hit[4], hit[1], direction)

		return
	elseif Unit.get_data(hit_unit, "allow_melee_damage") == false then
		return
	end

	local network_manager = Managers.state.network
	local _, is_level_unit = network_manager:game_object_or_level_id(hit_unit)
	local damage_profile = DamageProfileTemplates[damage_profile_name]

	if is_level_unit then
		DamageUtils.damage_level_unit(hit_unit, action.owner_unit, "full", power_level, blow.boost_curve_multiplier, blow.is_critical_strike, damage_profile, 1, direction, action.item_name)
	else
		local weapon_system = Managers.state.entity:system("weapon_system")

		weapon_system:send_rpc_attack_hit(NetworkLookup.damage_sources[action.item_name], network_manager:unit_game_object_id(action.owner_unit), network_manager:unit_game_object_id(hit_unit), NetworkLookup.hit_zones.full, hit[1], direction, NetworkLookup.damage_profiles[damage_profile_name], "power_level", power_level, "hit_target_index", 1, "blocking", false, "boost_curve_multiplier", blow.boost_curve_multiplier, "is_critical_strike", blow.is_critical_strike)
	end
end

-- Hits an enemy or a body with the punch as a melee blow hits it (ActionSweep, ActionShieldSlam): the sound, the blood and the hit reaction
-- here, the talents, traits and buffs of a melee hit, and the damage on the server. A shield doesn't stop the punch. blow is the punch's
-- critical hit and melee boost, and index the number of this target among those it hits. can_damage and can_stagger say whether it is
-- still within the punch's cleave (see punch).
local function melee_hit(action, punch_action, hit_unit, hit, direction, power_level, blow, index, can_damage, can_stagger)
	local network_manager = Managers.state.network
	local owner_unit = action.owner_unit
	local attacker_unit_id = network_manager:unit_game_object_id(owner_unit)
	local hit_unit_id = network_manager:unit_game_object_id(hit_unit)
	local breed = Unit.get_data(hit_unit, "breed")

	if not attacker_unit_id or not hit_unit_id or not breed then
		return
	end

	local zone_name = hit_zone_name(hit) or "torso"
	local position = hit[1]
	local damage_profile = DamageProfileTemplates[punch_action.damage_profile]
	local alive = HEALTH_ALIVE[hit_unit]
	local sound_effect_extension = ScriptUnit.has_extension(owner_unit, "sound_effect_system")

	if sound_effect_extension and alive then
		sound_effect_extension:add_hit()
	end

	local weapon_system = Managers.state.entity:system("weapon_system")

	-- (what ActionSweep reads of the action that hits; the hit is sent at once, with no wait for the swing's moment)
	local sweep = {
		_current_action = punch_action,
		_overridable_settings = punch_action,
		_time_to_hit = 0,
		item_name = action.item_name,
		owner_unit = owner_unit,
		weapon_system = weapon_system,
		weapon_unit = action.weapon_unit,
		world = action.world,
	}

	ActionSweep._play_character_impact(sweep, action.is_server, owner_unit, hit_unit, breed, position, zone_name, punch_action, damage_profile, 1, power_level, direction, false, blow.boost_curve_multiplier, blow.is_critical_strike)

	-- (the buffs only for a living enemy, so that hitting bodies doesn't set them off)
	local buff_result

	if alive then
		buff_result = DamageUtils.buff_on_attack(owner_unit, hit_unit, damage_profile.charge_value, blow.is_critical_strike, zone_name, index, true, DamageUtils.get_item_buff_type(action.item_name), nil, action.item_name)
	end

	local attack_template_id = NetworkLookup.attack_templates[damage_profile.default_target.attack_template]

	weapon_system:rpc_weapon_blood(nil, attacker_unit_id, attack_template_id)
	Managers.state.blood:add_enemy_blood(position, hit_unit)

	-- (a buff can kill the enemy itself)
	if buff_result == "killing_blow" then
		return
	end

	-- (sent as a swing sends its hit, which is where the movement's momentum damage scales a hit's power)
	ActionSweep._send_attack_hit(sweep, Managers.time:time("game"), NetworkLookup.damage_sources[action.item_name], attacker_unit_id, hit_unit_id, NetworkLookup.hit_zones[zone_name], position, direction, NetworkLookup.damage_profiles[punch_action.damage_profile], "power_level", power_level, "hit_target_index", 1, "blocking", false, "shield_break_procced", false, "boost_curve_multiplier", blow.boost_curve_multiplier, "is_critical_strike", blow.is_critical_strike, "can_damage", can_damage, "can_stagger", can_stagger, "first_hit", index == 1)

	if not action.is_server then
		network_manager.network_transmit:send_rpc_server("rpc_weapon_blood", attacker_unit_id, attack_template_id)
	end
end

-- A hit on a body at its part nearest a point, as a ray's hit is ({ position, distance, normal, actor }). Only a part that is a hit zone
-- of the body's breed will do, because the game looks the zone up, and not one of NOT_PUNCHED.
local function body_hit(unit, from, direction)
	local breed = Unit.get_data(unit, "breed")
	local lookup = breed and breed.hit_zones_lookup
	local best, best_distance

	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)
		local zone = actor and lookup and lookup[Actor.node(actor)]

		if zone and not NOT_PUNCHED[zone.name] then
			local distance = Vector3.distance(Actor.position(actor), from)

			if not best or distance < best_distance then
				best, best_distance = actor, distance
			end
		end
	end

	return best and {
		Actor.position(best),
		best_distance,
		-direction,
		best,
	}
end

-- How many enemies a punch gets through, as a melee swing works it out when it starts (ActionSweep.client_owner_start_action): the most
-- hit mass its damage and its stagger get through, from the profile's cleave and the player's power, and whether a critical hit gets
-- through all of them (a talent's)
local function cleave_of(owner_unit, damage_profile, power_level, is_critical_strike)
	local buff_extension = ScriptUnit.extension(owner_unit, "buff_system")
	local cleave_power_level = ActionUtils.scale_power_levels(power_level, "cleave", owner_unit, Managers.state.difficulty:get_difficulty())

	cleave_power_level = buff_extension:apply_buffs_to_value(cleave_power_level, "power_level_melee")
	cleave_power_level = buff_extension:apply_buffs_to_value(cleave_power_level, "power_level_melee_cleave")

	local max_attack, max_impact = ActionUtils.get_max_targets(damage_profile, cleave_power_level)

	max_attack = buff_extension:apply_buffs_to_value(max_attack or 1, "increased_max_targets")
	max_impact = buff_extension:apply_buffs_to_value(max_impact or 1, "increased_max_targets")

	if buff_extension:has_buff_perk("potion_armor_penetration") then
		max_impact = max_impact * 2
	end

	return max_attack, max_impact, is_critical_strike and buff_extension:has_buff_perk("crit_unlimited_cleave")
end

-- The hit mass of an enemy, as a melee swing counts it (ActionSweep._get_target_hit_mass): its breed's on this difficulty, less while it
-- is staggered, and as buffs change it. A shield doesn't stop the punch, so it is never the mass of a block.
local function hit_mass(owner_unit, unit)
	local breed = Unit.get_data(unit, "breed")
	local difficulty_rank = Managers.state.difficulty:get_difficulty_rank()
	local mass = breed.hit_mass_counts and (breed.hit_mass_counts[difficulty_rank] or breed.hit_mass_counts[2]) or breed.hit_mass_count or 1
	local game = Managers.state.network:game()
	local go_id = Managers.state.unit_storage:go_id(unit)

	if not breed.is_player and game and go_id and NetworkLookup.bt_action_names[GameSession.game_object_field(game, go_id, "bt_action_name")] == "stagger" then
		mass = mass * 0.75
	end

	local target_buff_extension = ScriptUnit.has_extension(unit, "buff_system")

	if target_buff_extension then
		mass = target_buff_extension:apply_buffs_to_value(mass, "hit_mass_amount")
	end

	return ScriptUnit.extension(owner_unit, "buff_system"):apply_buffs_to_value(mass, "hit_mass_reduction")
end

-- When each player's charge started, on the machine that owns their actions
local charge_started = {}

local function punch(action, t, power_level, bash)
	local owner_unit = action.owner_unit
	local hold_time = charge_started[owner_unit] and t - charge_started[owner_unit] or 0
	local step, scale = charge_step(hold_time)
	local range = bash and CONFIG.bash_range or CONFIG.hit_range
	local hit, is_enemy, direction, origin, eye = in_reach(owner_unit, action.physics_world, range)

	charge_started[owner_unit] = nil

	if utils.is_local_player_unit(owner_unit) then
		mod.shield.charge_started = nil
		mod.shield.last_punch = t
	end

	tell(owner_unit, mod.shield.events.punch)

	if not origin then
		return
	end

	local punch_action = bash and BASH_ACTIONS[step] or PUNCH_ACTIONS[step]
	local targets = targets_in_reach(owner_unit, action.physics_world, eye, direction, range)

	-- (the enemy straight ahead is always one: close up, its middle can be outside the cone)
	if is_enemy then
		local ahead = ActionUtils.redirect_shield_hit(Actor.unit(hit[4]), hit[4])
		local listed = false

		for _, target in ipairs(targets) do
			listed = listed or target.unit == ahead
		end

		if not listed then
			targets[#targets + 1] = {
				hit = hit,
				unit = ahead,
			}
		end
	end

	local force = CONFIG.min_force + scale * (CONFIG.max_force - CONFIG.min_force)

	-- The punch is a melee swing: it can be a critical hit, and the career's melee boost adds to it, as a swing's start has them (ActionSweep)
	local buff_extension = ScriptUnit.has_extension(owner_unit, "buff_system")
	local has_melee_boost, boost_curve_multiplier = ActionUtils.get_melee_boost(owner_unit)
	local blow = {
		boost_curve_multiplier = boost_curve_multiplier,
		is_critical_strike = ActionUtils.is_critical_strike(owner_unit, punch_action, t) or has_melee_boost,
	}

	if buff_extension then
		buff_extension:trigger_procs("on_sweep")
	end

	-- (with no HUD extension, so the critical hit's mark on the crosshair isn't left on: a swing takes it off when it ends)
	action:_handle_critical_strike(blow.is_critical_strike, buff_extension, nil, ScriptUnit.has_extension(owner_unit, "first_person_system"), "on_critical_sweep", "Play_player_combat_crit_swing_2D")

	-- The enemies and bodies in reach take the punch as a hit (a body at its part nearest the player), the nearest first. A body that is down
	-- already is pushed at that zone as the game pushes a body for a hit, here and on the other machines; the game doesn't for a hit on one
	-- that is dead. What the punch kills is thrown. How many enemies it gets through is a melee swing's cleave (ActionSweep): each living
	-- one adds its hit mass, and once that is the punch's most, the rest are not hit. One that is hit past what its damage or its stagger
	-- gets through is hit without that. Bodies cost nothing.
	local max_attack, max_impact, unlimited = cleave_of(owner_unit, DamageProfileTemplates[punch_action.damage_profile], power_level, blow.is_critical_strike)
	local mass = 0
	local index = 0
	local hit_enemy = false

	for _, target in ipairs(targets) do
		target.distance = target.hit and target.hit[2] or Vector3.distance(eye, POSITION_LOOKUP[target.unit] or Unit.world_position(target.unit, 0))
	end

	table.sort(targets, function (a, b)
		return a.distance < b.distance
	end)

	for _, target in ipairs(targets) do
		local alive = HEALTH_ALIVE[target.unit]
		local can_damage, can_stagger = true, true
		local missed = false

		if alive and not unlimited then
			if mass >= math.max(max_attack, max_impact) then
				missed = true
			else
				can_damage, can_stagger = mass <= max_attack, mass <= max_impact
				mass = mass + hit_mass(owner_unit, target.unit)
			end
		end

		if not missed then
			local hit_on_target = target.hit
			local zone = hit_zone_name(hit_on_target)

			-- (a hit on the head goes to the body)
			if not hit_on_target or zone and NOT_PUNCHED[zone] then
				hit_on_target = body_hit(target.unit, origin, direction)
			end

			if hit_on_target then
				index = index + 1

				melee_hit(action, punch_action, target.unit, hit_on_target, direction, power_level, blow, index, can_damage, can_stagger)

				hit_enemy = hit_enemy or alive
			end

			if alive then
				throw_hit(target.unit, direction, true, hit_on_target and hit_on_target[1], force)
			elseif hit_on_target then
				local body_zone = hit_zone_name(hit_on_target)
				local id = Managers.state.unit_storage:go_id(target.unit)

				push_body(target.unit, body_zone, direction)

				if id and body_zone then
					mod:network_send("ut_shield_body_push", "others", id, body_zone, Vector3.x(direction), Vector3.y(direction), Vector3.z(direction))
				end
			end
		end
	end

	-- Every thing in reach that is not a character: a door or a barrel takes the punch as from a melee swing, and a loose thing is thrown.
	-- The one straight ahead is always one.
	local objects = objects_in_reach(owner_unit, action.physics_world, eye, direction, range)
	local hit_unit = hit and not is_enemy and ActionUtils.redirect_shield_hit(Actor.unit(hit[4]), hit[4])

	if hit_unit and not Unit.get_data(hit_unit, "breed") and is_object(hit_unit, hit[4], owner_unit) then
		local listed = false

		for _, object in ipairs(objects) do
			listed = listed or object.unit == hit_unit
		end

		if not listed then
			objects[#objects + 1] = {
				hit = hit,
				unit = hit_unit,
			}
		end
	end

	for _, object in ipairs(objects) do
		-- (looked at before the hit, which can break the thing, and the part it hit is then gone)
		local loose = not Actor.is_static(object.hit[4])

		hit_object(action, object.unit, object.hit, direction, punch_action.damage_profile, power_level, blow)

		if loose then
			throw_hit(object.unit, direction, false, object.hit[1])
		end
	end

	-- A punch that hit an enemy or a thing in its cone doesn't throw the player. A body doesn't stop it.
	if not hit_unit or Unit.get_data(hit_unit, "breed") or hit_enemy or #objects > 0 then
		return
	end

	-- Anything else near enough straight ahead throws the player off it and hurts them, as UT's punch of anything that is not a pawn does
	if hit[2] <= CONFIG.range * UNIT then
		local self_damage = (CONFIG.min_self_damage + CONFIG.self_damage_scale * damage_for_step(step)) * CONFIG.self_damage_share

		utils.apply_self_damage(owner_unit, hit[1], -direction, action.item_name, self_damage)

		if utils.is_local_player_unit(owner_unit) then
			push_player(owner_unit, direction, force)
		end
	end
end

-- A charge of a copy whose third person pose has an aim (VARIANTS' aim_3p) goes into the aim once it has been held for min_hold_time, so
-- that a quick punch is only the shot. The machine that owns the character's actions plays the event, which the game sends to the
-- others. As [character unit] = { at = game time, event }.
local aim_after_hold = {}

mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	if not next(aim_after_hold) then
		return
	end

	local t = Managers.time:time("game")

	for unit, pending in pairs(aim_after_hold) do
		if not Unit.alive(unit) then
			aim_after_hold[unit] = nil
		elseif t >= pending.at then
			aim_after_hold[unit] = nil

			Managers.state.network:anim_event(unit, pending.event)
		end
	end
end

mod.dummy_start_callbacks.shield_gun = function (action, new_action, t, power_level)
	aim_after_hold[action.owner_unit] = nil

	if new_action.ut_shield_charge then
		local variant = POSES_3P[utils.wielded_template_name(action.owner_unit)]

		if variant and variant.aim_3p then
			aim_after_hold[action.owner_unit] = {
				at = t + CONFIG.min_hold_time,
				event = variant.aim_3p,
			}
		end

		charge_started[action.owner_unit] = t

		if utils.is_local_player_unit(action.owner_unit) then
			mod.shield.charge_started = t
		end

		tell(action.owner_unit, mod.shield.events.charge)
	elseif new_action.ut_shield_punch then
		if new_action.ut_shield_bash and utils.is_local_player_unit(action.owner_unit) then
			mod.shield.last_bash = t
		end

		punch(action, t, power_level, new_action.ut_shield_bash)
	end
end

-- A push counts as the start of a charge, so that the bash out of it is as strong as a charge held that long
mod.push_start_callbacks.shield_gun = function (action, new_action, t)
	if not new_action.ut_shield_push then
		return
	end

	charge_started[action.owner_unit] = t

	if utils.is_local_player_unit(action.owner_unit) then
		mod.shield.last_push = t
	end
end

-- What the gun did belongs to the character that did it. When the player's character changes (they died, or the level changed), it is
-- all forgotten: the game doesn't finish the actions of a player who dies, so a charge would go on, and the game's clock can start over
-- with a level, so an old push would look like one that is still going.
mod.update_callbacks[#mod.update_callbacks + 1] = function ()
	local player = Managers.player:local_player_safe()
	local unit = player and player.player_unit

	if unit == mod.shield.player_unit then
		return
	end

	if mod.shield.player_unit then
		charge_started[mod.shield.player_unit] = nil
	end

	mod.shield.player_unit = unit
	mod.shield.charge_started = nil
	mod.shield.last_push = nil
	mod.shield.last_bash = nil
	mod.shield.last_punch = nil
end

-- The charge can end without a punch: on a ladder, when stunned, when the weapon is put away, and so on. The game then finishes the
-- action, and the skin stops showing the charge. When the button is let go the charge finishes the same way just before the punch starts
-- ("new_interupting_action"), and the punch still needs when it started, so that is kept then.
mod.dummy_finish_callbacks.shield_gun = function (action, reason)
	local current = action.current_action

	if not current or not current.ut_shield_charge then
		return
	end

	local owner_unit = action.owner_unit

	aim_after_hold[owner_unit] = nil

	if reason ~= "new_interupting_action" then
		charge_started[owner_unit] = nil
	end

	-- (a punch that follows is told after this)
	tell(owner_unit, mod.shield.events.charge_end)

	if utils.is_local_player_unit(owner_unit) then
		mod.shield.charge_started = nil
	end
end

-- Reflection (see reflect_dot in CONFIG)

-- Where a segment from `from` to `to` first gets to an upright cylinder, as the share of the way along it (0 if it starts inside), or
-- nil if it doesn't
local function segment_cylinder(from, to, center, radius, half_height)
	local dx, dy, dz = Vector3.x(to) - Vector3.x(from), Vector3.y(to) - Vector3.y(from), Vector3.z(to) - Vector3.z(from)
	local fx, fy = Vector3.x(from) - Vector3.x(center), Vector3.y(from) - Vector3.y(center)
	local fz = Vector3.z(from) - Vector3.z(center)
	local best

	-- (a segment that starts inside it gets to it where it starts: a gutter runner that jumps from up close)
	if fx * fx + fy * fy <= radius * radius and math.abs(fz) <= half_height then
		return 0
	end

	-- (its side)
	local a = dx * dx + dy * dy
	local b = 2 * (fx * dx + fy * dy)
	local c = fx * fx + fy * fy - radius * radius
	local discriminant = b * b - 4 * a * c

	if a > 1e-8 and discriminant >= 0 then
		local t = (-b - math.sqrt(discriminant)) / (2 * a)

		if t >= 0 and t <= 1 and math.abs(fz + dz * t) <= half_height then
			best = t
		end
	end

	-- (its top and bottom)
	if math.abs(dz) > 1e-8 then
		for _, side in ipairs({ 1, -1 }) do
			local t = (side * half_height - fz) / dz
			local x, y = fx + dx * t, fy + dy * t

			if t >= 0 and t <= 1 and (not best or t < best) and x * x + y * y <= radius * radius then
				best = t
			end
		end
	end

	return best
end

-- Whether a player holds the Shield Gun's shield up
local function shield_is_up(unit)
	local status_extension = ScriptUnit.has_extension(unit, "status_system")

	return HEALTH_ALIVE[unit] and TEMPLATE_NAMES[utils.wielded_template_name(unit)] and status_extension and status_extension:is_blocking()
end

-- The shield pays for a reflection as for a blocked attack of the fatigue type, the way the game blocks a shot
-- (DamageUtils.check_ranged_block): the block is made here, and the player's own machine is told, which takes their stamina and shows
-- the hit.
local function pay_for_reflection(unit, attacker_unit, fatigue_type)
	local network_manager = Managers.state.network
	local status_extension = ScriptUnit.extension(unit, "status_system")
	local template = WeaponUtils.get_weapon_template(utils.wielded_template_name(unit))
	local multiplier = template and template.block_fatigue_point_multiplier or 1

	status_extension:blocked_attack(fatigue_type, attacker_unit, multiplier, true)

	local go_id = Managers.state.unit_storage:go_id(unit)
	local attacker_id, attacker_is_level_unit = network_manager:game_object_or_level_id(attacker_unit)

	if not go_id or not attacker_id then
		return
	end

	if Managers.player.is_server then
		network_manager.network_transmit:send_rpc_clients("rpc_player_blocked_attack", go_id, NetworkLookup.fatigue_types[fatigue_type], attacker_id, multiplier, true, "back", attacker_is_level_unit)
	else
		network_manager.network_transmit:send_rpc_server("rpc_player_blocked_attack", go_id, NetworkLookup.fatigue_types[fatigue_type], attacker_id, multiplier, true, "back", attacker_is_level_unit)
	end
end

-- Whether a shot from `from` to `to`, as wide as `radius` (meters), is reflected by a player's shield on its way. The shot is the
-- attacker's, and ignore_unit is a player it has just left. Only the first player it gets to counts: a shot that gets to a player who
-- doesn't reflect it hits them. The attacker's own shot doesn't get to them (a projectile's ProcessTouch skips its Instigator, which a
-- reflected one keeps), except a beam that was reflected already, with reaches_attacker (InstantFire.DoTrace: ReflectNum > 0). The
-- shield's stamina pays as for a blocked attack of fatigue_type (a shot's, "blocked_ranged", if not given). Returns where it was
-- reflected, how far along the way that is (meters), the way it goes on (the way the player looks), and the player.
function mod.shield.reflect(from, to, radius, attacker_unit, ignore_unit, reaches_attacker, fatigue_type)
	local heroes = Managers.state.side and Managers.state.side:get_side_from_name("heroes")
	local game = Managers.state.network:game()

	if not heroes or not game then
		return
	end

	-- (the players it gets to at the same point, as when it starts inside the reach of more than one, count by how near they are)
	local best_t, best_unit, best_center, best_distance

	for _, unit in ipairs(heroes.PLAYER_AND_BOT_UNITS) do
		if (unit ~= attacker_unit or reaches_attacker) and unit ~= ignore_unit and Unit.alive(unit) then
			local status_extension = ScriptUnit.has_extension(unit, "status_system")
			local height = status_extension and status_extension:is_crouching() and CONFIG.reach_height_crouched or CONFIG.reach_height
			local center = POSITION_LOOKUP[unit] + Vector3(0, 0, height * UNIT)
			-- (a shot as wide as radius gets to the cylinder grown by radius, up and down as well as across)
			local t = segment_cylinder(from, to, center, CONFIG.pawn_radius * UNIT + radius, height * UNIT + radius)
			local distance = t and Vector3.distance(Vector3.lerp(from, to, t), center)

			if t and (not best_t or t < best_t or t == best_t and distance < best_distance) then
				best_t, best_unit, best_center, best_distance = t, unit, center, distance
			end
		end
	end

	if not best_unit or not shield_is_up(best_unit) then
		return
	end

	local go_id = Managers.state.unit_storage:go_id(best_unit)
	local face = go_id and Vector3.normalize(GameSession.game_object_field(game, go_id, "aim_direction"))
	local position = Vector3.lerp(from, to, best_t)
	local to_player = Vector3.normalize(best_center - position + Vector3(0, 0, CONFIG.reflect_up_offset * UNIT))

	-- (UT's arc is measured from the hit to the player, so a hit in front points back at the look)
	if not face or Vector3.dot(face, to_player) >= CONFIG.reflect_dot then
		return
	end

	pay_for_reflection(best_unit, attacker_unit, fatigue_type or "blocked_ranged")

	return position, Vector3.distance(from, position), face, best_unit
end

-- Sends a projectile of a UT weapon on from a shield, as UT does (ShockProjectile and LinkProjectile.ProcessTouch): a new one of the same
-- shot starts reflect_offset out from the hit, the way the player with the shield looks, at the shot's starting speed, and the old one
-- ends. The new one is the same player's shot, and it doesn't touch the shield it came from.
local function reflect_projectile(projectile, position, direction, shield_unit)
	local lookup = projectile.action_lookup_data
	local action = projectile._current_action
	local owner_unit = projectile._owner_unit
	local projectile_system = Managers.state.entity:system("projectile_system")
	local before = {}

	for unit in pairs(projectile_system.player_projectile_units[owner_unit] or {}) do
		before[unit] = true
	end

	local start = position + direction * (CONFIG.reflect_offset * UNIT)
	local flat = Vector3.flat(direction)
	local target_vector = Vector3.length(flat) > 0.001 and Vector3.normalize(flat) or Vector3(1, 0, 0)
	local angle = math.asin(math.clamp(Vector3.z(direction), -1, 1))

	ActionUtils.spawn_player_projectile(owner_unit, start, Quaternion.look(direction, Vector3.up()), (projectile.scale or 1) * 100, angle, target_vector, action.speed, projectile.item_name, lookup.item_template_name, lookup.action_name, lookup.sub_action_name, projectile._is_critical_strike, projectile.power_level, nil, (projectile.charge_level or 0) * 100)

	for unit in pairs(projectile_system.player_projectile_units[owner_unit] or {}) do
		local extension = not before[unit] and ScriptUnit.has_extension(unit, "projectile_system")

		if extension then
			-- (the game blends a staff's bolt in from the hand that fired it, which a reflected one doesn't come from)
			extension._anim_blend_enabled = false
			extension._ut_reflected_by = shield_unit
		end
	end

	projectile:stop()
end

-- A projectile of a UT weapon that reflects (its action has ut_reflective) is looked at before the game looks at what it hit this frame,
-- on the machine of the player who shot it, where it flies
mod:hook(PlayerProjectileImpactUnitExtension, "update", function (func, self, unit, ...)
	local projectile = ScriptUnit.has_extension(unit, "projectile_system")
	local action = projectile and projectile._current_action
	local locomotion_extension = self.locomotion_extension

	if action and action.ut_reflective and not projectile._stop_impacts and locomotion_extension:moved_this_frame() then
		local position, _, direction, shield_unit = mod.shield.reflect(locomotion_extension:last_position(), locomotion_extension:current_position(), self.radius or 0, self.owner_unit, projectile._ut_reflected_by)

		if position then
			reflect_projectile(projectile, position, direction, shield_unit)

			return
		end
	end

	return func(self, unit, ...)
end)

mod.shield.max_reflections = CONFIG.max_reflections

-- What is left of a fall's damage (movement.lua) after the shield takes its part. UT's arc is from where the fall hits, the player's
-- middle, so it is under them, and the player has to look down into it (CheckReflect's HitDir is straight up).
function mod.shield.absorb_fall(unit, damage)
	local game = Managers.state.network:game()
	local go_id = Managers.state.unit_storage:go_id(unit)

	if not game or not go_id or not shield_is_up(unit) then
		return damage
	end

	local face = Vector3.normalize(GameSession.game_object_field(game, go_id, "aim_direction"))

	if Vector3.dot(face, Vector3.up()) >= CONFIG.reflect_dot then
		return damage
	end

	pay_for_reflection(unit, unit, CONFIG.fall_fatigue_type)

	return damage - math.min(damage, CONFIG.fall_absorb)
end

-- A sorcerer's magic missile (BTCastMissileAction.launch_magic_missile: Burblespue's and the Drachenfels sorcerer's) flies at a
-- player and blows up where it hits (the "direct_impact" impact, an explosion of the sorcerer's that hurts players). The host moves it
-- and looks for what it hits, so the host reflects it. A reflected missile stops following its target and flies on the way the player
-- with the shield looks, hits the enemies and the level instead of the players, and blows up as that player's explosion.
local REFLECTED_MISSILE_IMPACT = "ut_reflected_missile"
local MISSILE_IMPACTS = {
	direct_impact = true,
	[REFLECTED_MISSILE_IMPACT] = true,
}

ProjectileTemplates.impact_templates[REFLECTED_MISSILE_IMPACT] = {
	server = {
		execute = function (world, damage_source, projectile_unit, recent_impacts, num_impacts, owner_unit, explosion_template)
			local projectile = ScriptUnit.has_extension(projectile_unit, "projectile_system")
			local shield_unit = projectile and projectile._ut_reflected_by
			local inventory_extension = shield_unit and HEALTH_ALIVE[shield_unit] and ScriptUnit.has_extension(shield_unit, "inventory_system")
			local wielded = inventory_extension and inventory_extension:equipment().wielded
			local career_extension = shield_unit and ScriptUnit.has_extension(shield_unit, "career_system")

			if wielded and career_extension then
				local position = Vector3Box.unbox(recent_impacts[ProjectileImpactDataIndex.POSITION])
				local area_damage_system = Managers.state.entity:system("area_damage_system")

				area_damage_system:create_explosion(shield_unit, position, Quaternion.identity(), CONFIG.reflected_missile_explosion, 1, wielded.name, career_extension:get_career_power_level(), false, shield_unit)
			end

			Managers.state.unit_spawner:mark_for_deletion(projectile_unit)

			return true
		end,
	},
	client = ProjectileTemplates.impact_templates.direct_impact.client,
}

-- Sends a missile on from a shield, reflect_offset out from the hit, as ProjectileTrueFlightLocomotionExtension.bounce sends one on
local function reflect_missile(unit, impact_extension, projectile, position, direction, shield_unit)
	local locomotion = impact_extension.locomotion_extension
	local start = position + direction * (CONFIG.reflect_offset * UNIT)
	local rotation = Quaternion.look(direction, Vector3.up())
	local flat = Vector3.flat(direction)

	-- (it looks for no target any more, so it flies straight)
	locomotion.target_unit = nil
	locomotion.position_target = nil
	locomotion._find_target_func = function () end
	locomotion.t = Managers.time:time("game")

	locomotion.target_vector_boxed:store(Vector3.length(flat) > 0.001 and Vector3.normalize(flat) or Vector3(1, 0, 0))
	locomotion.initial_position_boxed:store(start)
	locomotion._current_position:store(start)

	locomotion.radians = math.asin(math.clamp(Vector3.z(direction), -1, 1))

	locomotion:_unit_set_position_rotation(unit, start, rotation)

	local game = Managers.state.network:game()
	local id = Managers.state.unit_storage:go_id(unit)

	if game and id then
		GameSession.set_game_object_field(game, id, "position", start)
		GameSession.set_game_object_field(game, id, "rotation", rotation)
	end

	impact_extension.collision_filter = "filter_player_ray_projectile_no_player"
	impact_extension.last_position = nil
	projectile.impact_template_name = REFLECTED_MISSILE_IMPACT
	projectile._ut_reflected_by = shield_unit
end

-- The host looks at a missile's way this frame before it looks for what the missile hit
mod:hook(ProjectileRaycastImpactUnitExtension, "update", function (func, self, unit, input, dt, context, t)
	local projectile = self.is_server and self.server_side_raycast and ScriptUnit.has_extension(unit, "projectile_system")
	local locomotion = self.locomotion_extension

	if projectile and MISSILE_IMPACTS[projectile.impact_template_name] and locomotion.true_flight_template_name and BLACKBOARDS[projectile.owner_unit] and locomotion:moved_this_frame() then
		local position, _, direction, shield_unit = mod.shield.reflect(POSITION_LOOKUP[unit], Unit.local_position(unit, 0), 0, projectile.owner_unit, projectile._ut_reflected_by)

		if position then
			reflect_missile(unit, self, projectile, position, direction, shield_unit)

			return
		end
	end

	return func(self, unit, input, dt, context, t)
end)

-- A gutter runner's pounce (BTCrazyJumpAction, on the host) that gets to a player's shield throws the gutter runner back, the way the
-- player looks, as fast as it came. It doesn't pin anyone for the rest of that jump, and it lands and goes on.
mod:hook(BTCrazyJumpAction, "run", function (func, self, unit, blackboard, t, dt)
	local data = blackboard.jump_data
	local state = data and data.state
	local in_air = state == "in_air" or state == "in_air_no_target" or state == "snapping"

	if in_air and data.ut_reflected_jump ~= blackboard.last_jump and data.overlap_context and data.overlap_context.spine_node then
		local locomotion = blackboard.locomotion_extension
		local velocity = locomotion:current_velocity()
		local from = Unit.world_position(unit, data.overlap_context.spine_node)
		local position, _, direction = mod.shield.reflect(from, from + velocity * dt, CONFIG.pounce_radius, unit, nil, false, CONFIG.pounce_fatigue_type)

		if position then
			data.ut_reflected_jump = blackboard.last_jump
			data.target_unit = nil
			blackboard.target_unit = nil

			locomotion:set_wanted_velocity(direction * Vector3.length(velocity))
		end
	end

	return func(self, unit, blackboard, t, dt)
end)

-- Whether a player's shield stops what comes at them from a place, by UT's arc (see mod.shield.reflect): it gets to their cylinder on
-- the side that faces that place. If it does, the shield pays for it.
local function shield_stops(unit, from, attacker_unit, fatigue_type)
	local game = Managers.state.network:game()
	local go_id = Managers.state.unit_storage:go_id(unit)

	if not game or not go_id or not shield_is_up(unit) then
		return false
	end

	local status_extension = ScriptUnit.extension(unit, "status_system")
	local height = status_extension:is_crouching() and CONFIG.reach_height_crouched or CONFIG.reach_height
	local center = POSITION_LOOKUP[unit] + Vector3(0, 0, height * UNIT)
	local hit = center + Vector3.normalize(from - center) * (CONFIG.pawn_radius * UNIT)
	local to_player = Vector3.normalize(center - hit + Vector3(0, 0, CONFIG.reflect_up_offset * UNIT))
	local face = Vector3.normalize(GameSession.game_object_field(game, go_id, "aim_direction"))

	if Vector3.dot(face, to_player) >= CONFIG.reflect_dot then
		return false
	end

	pay_for_reflection(unit, attacker_unit, fatigue_type)

	return true
end

-- An explosion (an exploding barrel, a bomb rat's bomb, a sorcerer's blast) that gets to a player from the front of their shield, by UT's
-- arc from where it goes off, is stopped, as UT's shield stops the explosions of its weapons (ShieldGun.AdjustPlayerDamage: rockets,
-- flak shells, grenades). The game's own block stops none. The shield pays as for a blocked attack of explosion_fatigue_type. UT's stops up
-- to 100 damage of it, which is all of an explosion of its weapons; here it stops all of it. This is on the host, where explosions hurt.
mod:hook(AreaDamageSystem, "_damage_unit", function (func, self, aoe_damage_data)
	local hit_unit = aoe_damage_data.hit_unit
	local attacker_unit = aoe_damage_data.attacker_unit

	if Unit.alive(hit_unit) and Unit.alive(attacker_unit) and DamageUtils.is_player_unit(hit_unit) and shield_stops(hit_unit, aoe_damage_data.impact_position:unbox(), attacker_unit, CONFIG.explosion_fatigue_type) then
		return
	end

	return func(self, aoe_damage_data)
end)

-- A lifeleech's grab (BTCorruptorGrabAction, on the host) is a beam that flies to the player and takes them when it is near enough. It
-- fails at the shield, from where the beam is, when it would take them (after the action's grab_delay, if it has one).
mod:hook(BTCorruptorGrabAction, "grab_player", function (func, self, t, unit, blackboard)
	local action = blackboard.action
	local target_unit = blackboard.corruptor_target
	local due = not action.grab_delay or blackboard.grab_at and t >= blackboard.grab_at

	if due and target_unit and blackboard.projectile_position and shield_stops(target_unit, blackboard.projectile_position:unbox(), unit, CONFIG.grab_fatigue_type) then
		blackboard.grab_at = nil
		blackboard.attack_success = false
		blackboard.attack_aborted = true

		return
	end

	return func(self, t, unit, blackboard)
end)

mod:hook(BTCrazyJumpAction, "check_colliding_players", function (func, self, unit, blackboard, pos)
	local data = blackboard.jump_data

	if data and data.ut_reflected_jump and data.ut_reflected_jump == blackboard.last_jump then
		return nil
	end

	return func(self, unit, blackboard, pos)
end)

-- The actions

local function chain(action, sub_action, input, start_time)
	return {
		action = action,
		input = input,
		start_time = start_time or 0,
		sub_action = sub_action,
	}
end

-- The charge: held for as long as the button is, until it is let go or an enemy comes into reach
local function build_charge(original)
	local action = table.clone(original)

	action.kind = "dummy"
	action.total_time = math.huge
	action.buff_data = nil
	action.blocking_charge = nil
	action.ut_shield_charge = true
	action.allowed_chain_actions = {
		chain("action_one", "punch", "action_one_release"),
		{
			action = "action_one",
			auto_chain = true,
			start_time = 0,
			sub_action = "punch_auto",
		},
		chain("action_two", "default", "action_two_hold"),
		chain("action_wield", "default", "action_wield"),
	}

	return action
end

-- The punch: the hit is made when it starts (see punch above), and the next charge can start after the fire rate
local function build_punch(original, auto)
	local action = table.clone(original)

	action.kind = "dummy"
	action.total_time = CONFIG.fire_rate
	action.damage_window_start = nil
	action.damage_window_end = nil
	action.ut_shield_punch = true
	action.allowed_chain_actions = {
		chain("action_one", "default", "action_one", CONFIG.fire_rate),
		chain("action_one", "default", "action_one_hold", CONFIG.fire_rate),
		chain("action_two", "default", "action_two_hold", 0),
		chain("action_wield", "default", "action_wield", 0),
	}

	if auto then
		action.chain_condition_func = function (unit)
			return enemy_in_reach(unit)
		end
	end

	return action
end

-- The push out of the block is the base weapon's own (its stagger and stamina), which the skin draws as a shove of the shield. Its
-- push-stab, both buttons held after the push, is the bash instead.
local function build_push(original)
	local action = table.clone(original)
	local has_bash = false

	action.ut_shield_push = true

	-- (its other chains to the left button's attacks go to the charge: the base's attacks are not in the weapon)
	for _, entry in ipairs(action.allowed_chain_actions or {}) do
		if entry.action == "action_one" and entry.hold_required then
			entry.sub_action = "bash"
			has_bash = true
		elseif entry.action == "action_one" then
			entry.sub_action = "default"
		end
	end

	if not has_bash then
		action.allowed_chain_actions = action.allowed_chain_actions or {}
		action.allowed_chain_actions[#action.allowed_chain_actions + 1] = {
			action = "action_one",
			doubleclick_window = 0,
			end_time = CONFIG.bash_window[2],
			input = "action_one_hold",
			start_time = CONFIG.bash_window[1],
			sub_action = "bash",
			hold_required = {
				"action_two_hold",
				"action_one_hold",
			},
		}
	end

	return action
end

-- The bash: the shield goes down, the gun punches as hard as a charge held since the push started (the push starts it, see
-- push_start_callbacks), and the shield can go up again after bash_shield_down. This is not in UT, which has no push.
local function build_bash(original)
	local action = build_punch(original, false)

	action.ut_shield_bash = true
	action.allowed_chain_actions = {
		chain("action_one", "default", "action_one", CONFIG.fire_rate),
		chain("action_one", "default", "action_one_hold", CONFIG.fire_rate),
		chain("action_two", "default", "action_two_hold", CONFIG.bash_shield_down),
		chain("action_wield", "default", "action_wield", 0),
	}

	return action
end

-- What makes the game's shields different from a weapon's block, which the block of the gun takes from the game's sword and shield:
-- it blocks shots too (a ratling gun's, a warpfire thrower's), it blocks a wider arc for less stamina and the rest of the way round for
-- more, and it sounds like a shield.
local SHIELD_FIELDS = {
	"shield_block",
	"can_block_ranged_attacks",
	"block_angle",
	"outer_block_angle",
	"block_fatigue_point_multiplier",
	"outer_block_fatigue_point_multiplier",
	"sound_event_block_within_arc",
}

local function apply_template(template)
	local template_name = template.name
	local actions = template.actions
	local original = actions.action_one
	local heavy = original.heavy_attack or original.heavy_attack_left or original.default
	local game_shield = rawget(Weapons, "one_handed_sword_shield_template_1")

	for _, field in ipairs(game_shield and SHIELD_FIELDS or {}) do
		template[field] = game_shield[field]
	end

	-- The chart of the item's stats, from 0 to 7: the bash out of a push (light) and the charged punch (heavy). Both get through enemies
	-- as the game's tank blows do (damage_types).
	template.weapon_diagram = {
		light_attack = {
			[DamageTypes.ARMOR_PIERCING] = 5,
			[DamageTypes.CLEAVE] = 3,
			[DamageTypes.SPEED] = 3,
			[DamageTypes.STAGGER] = 6,
			[DamageTypes.DAMAGE] = 3,
		},
		heavy_attack = {
			[DamageTypes.ARMOR_PIERCING] = 6,
			[DamageTypes.CLEAVE] = 4,
			[DamageTypes.SPEED] = 1,
			[DamageTypes.STAGGER] = 7,
			[DamageTypes.DAMAGE] = 6,
		},
	}

	actions.action_one = {
		default = build_charge(original.default),
		punch = build_punch(heavy, false),
		punch_auto = build_punch(heavy, true),
		push = original.push and build_push(original.push),
		bash = original.push and build_bash(heavy),
	}

	-- The block keeps its push. Its other attacks out of the block (some weapons have a block attack) start a charge instead.
	local block = actions.action_two and actions.action_two.default

	if block and block.allowed_chain_actions then
		local kept = {}

		for _, entry in ipairs(block.allowed_chain_actions) do
			if not (entry.action == "action_one" and entry.sub_action ~= "default" and not (entry.sub_action == "push" and original.push)) then
				kept[#kept + 1] = entry
			end
		end

		block.allowed_chain_actions = kept
	end

	utils.set_actions_lookup_data({
		action_one = actions.action_one,
	}, template_name)

	-- Bots (BTBotMeleeAction): a light attack lets go of the charge at once, which is a quick punch. A heavy attack holds the charge until
	-- it punches by itself, when an enemy is in reach, as UT's bots hold the Shield Gun's fire and let it go off by itself (ShieldFire's
	-- auto release). That is told the game's way (attack_chain, WeaponUtils.add_bot_meta_data_chain_actions). Without it the heavy attack
	-- looked for a second release in the charge, which has only one, and did nothing. The base weapon's own chains name its attacks, which
	-- this weapon doesn't have. The bot attacks from as far as the charge looks for an enemy.
	local reach = CONFIG.hit_range * UNIT

	template.attack_meta_data = {
		tap_attack = {
			arc = 1,
			max_range = reach,
		},
		hold_attack = {
			arc = 2,
			max_range = reach,
			attack_chain = {
				start_action_name = "action_one",
				start_sub_action_name = "default",
				transitions = {
					action_one = {
						default = {
							bot_wait_input = "hold_attack",
							bot_wanted_input = "hold_attack",
							wanted_action_name = "action_one",
							wanted_sub_action_name = "punch_auto",
						},
					},
				},
			},
		},
	}

	WeaponUtils.add_bot_meta_data_chain_actions(actions, template.attack_meta_data.hold_attack.attack_chain.transitions)

	template.tooltip_compare = {
		light = {
			action_name = "action_one",
			sub_action_name = "punch",
		},
		heavy = {
			action_name = "action_one",
			sub_action_name = "punch",
		},
	}
	template.tooltip_detail = template.tooltip_compare

	-- The pose in third person: the game plays wield_anim_3p there, and the hero screen only the one for the career (any career: the
	-- item is only the hero's). The actions' anim_event_3p is what the body plays for them there. First person keeps the base weapon's,
	-- which the skin hides.
	local variant = POSES_3P[template_name]

	if variant then
		template.wield_anim_3p = variant.pose_3p
		template.wield_anim_career_3p = {}

		for career_name in pairs(CareerSettings) do
			template.wield_anim_career_3p[career_name] = variant.pose_3p
		end

		for name, action in pairs(actions.action_one) do
			if (name == "punch" or name == "punch_auto" or name == "bash") and variant.punch_3p then
				action.anim_event_3p = variant.punch_3p
			elseif name == "punch" or name == "punch_auto" or name == "bash" then
				-- (with no punch_3p the body plays nothing for them: without an event of its own, the game would play the base weapon's
				-- attack. First person doesn't play the base's attacks either, see the skin's first_person_animation_filters.)
				action.anim_event = nil
				action.anim_end_event = nil
			elseif name == "push" then
				action.anim_event_3p = variant.push_3p
			end
		end

		-- The shield goes into the aim, and so does a charge held for min_hold_time (see aim_after_hold). The punch comes out of it. The
		-- aim ends when one of them ends with nothing after it: a punch that the next charge follows stays in the aim. (The game plays the
		-- base's end event on the body too, before this.)
		if variant.aim_3p then
			local function not_chained(_, end_reason)
				return end_reason ~= "new_interupting_action"
			end

			-- The push and the bash out of it end the aim too: the shield before the push started it. (A weapon may have no push, bash or
			-- block, so those are added last, and a missing one adds nothing.)
			local ending = { actions.action_one.default, actions.action_one.punch, actions.action_one.punch_auto }

			ending[#ending + 1] = actions.action_one.push
			ending[#ending + 1] = actions.action_one.bash
			ending[#ending + 1] = block

			for _, action in ipairs(ending) do
				if action == block then
					action.anim_event_3p = variant.aim_3p
				end

				action.anim_end_event_3p = variant.aim_end_3p
				action.anim_end_event_condition_func = not_chained
			end
		end
	end
end

for template_name in pairs(TEMPLATE_NAMES) do
	mod.items.set_template_changes(template_name, apply_template)
end

mod.shield.template_names = TEMPLATE_NAMES
