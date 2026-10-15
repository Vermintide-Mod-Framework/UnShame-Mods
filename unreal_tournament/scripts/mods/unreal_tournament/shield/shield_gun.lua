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
-- Each hero has a melee weapon to be a copy of, so the weapon is six items of the mod that share everything but the base.
-- The skin (skin.lua) draws all of it, and this file only sets what it does to the game.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
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
	},
	{
		base_item = "dr_2h_cog_hammer",
		deus_copy = "deus_dr_2h_cog_hammer",
		id = "shield_gun_dr",
		key = "ut_shield_gun_dr",
		template = "ut_shield_gun_dr_template",
	},
	{
		base_item = "bw_ghost_scythe",
		deus_copy = "deus_bw_ghost_scythe",
		id = "shield_gun_bw",
		key = "ut_shield_gun_bw",
		template = "ut_shield_gun_bw_template",
	},
	{
		base_item = "wh_2h_billhook",
		deus_copy = "deus_wh_2h_billhook",
		id = "shield_gun_wh",
		key = "ut_shield_gun_wh",
		template = "ut_shield_gun_wh_template",
	},
	{
		base_item = "we_spear",
		deus_copy = "deus_we_spear",
		id = "shield_gun_we",
		key = "ut_shield_gun_we",
		template = "ut_shield_gun_we_template",
	},
	{
		base_item = "wh_1h_hammer",
		deus_copy = "deus_wh_1h_hammer",
		id = "shield_gun_priest",
		key = "ut_shield_gun_priest",
		template = "ut_shield_gun_priest_template",
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
		keywords = { "weapon_keyword_high_damage", "weapon_keyword_charged_attack", "weapon_keyword_damage_against_armoured" },
		icon = "ut_shield_gun_icon",
		icon_package = "resource_packages/unreal_tournament/icons",
		icon_materials = "ui/ut/shield_gun_icon",
	})
end

local TEMPLATE_NAMES = {}

for _, variant in ipairs(VARIANTS) do
	TEMPLATE_NAMES[mod.items.weapons[variant.id].template] = true
end

local CONFIG = {
	meters_per_uu = 0.02, -- Unreal unit to meters
	-- ShieldFire.ShieldRange: how far a wall can be for a punch to throw the player off it (the shield jump), in UT units
	range = 112,
	-- How far the punch reaches what it hits, and the bash out of a push, in UT units. They are longer than UT's ShieldRange on
	-- purpose: these numbers are a guess.
	hit_range = 150,
	bash_range = 200,
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
	-- body, its sounds); and the share of UT's damage it does, less for a short charge than UT's (a choice). Its stagger and the player's
	-- own damage of a shield jump are still worked out from UT's damage.
	damage_types = {
		{ 1 / 3, "light_blunt_tank", 1 / 2 },
		{ 2 / 3, "blunt_tank", 2 / 3 },
		{ 1, "heavy_blunt_tank", 1 },
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
}

local UNIT = CONFIG.meters_per_uu

-- What the gun does now, on the player's own machine, for the skin
mod.shield = {
	charge_started = nil, -- when the charge started, or nil
	last_punch = nil, -- when the last punch was
	fully_charged_time = CONFIG.fully_charged_time,
	-- How long after a push a bash can come, while both buttons are held
	bash_window_end = CONFIG.bash_window[2],
	-- Where on the charge (0 to FullyChargedTime, as a share) the punch becomes the next blow (damage_types), for the charge bar
	charge_marks = {},
}

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

-- Makes the damage profile of a punch of a step of the charge, of a damage type and a share of UT's damage, and returns what the punch is to
-- the game's hit processing
local function make_punch_action(name, damage, damage_type, damage_share, charge_value)
	register_damage_profile(name, "shot_sniper", function (profile)
		make_flat(profile, attack_power_for(damage * damage_share), impact_power_for(damage) * CONFIG.stagger_multiplier, damage_type)

		-- It is a melee blow to the game (what talents, traits and buffs take it for), not the sniper shot the profile is made from
		profile.charge_value = charge_value

		-- The punch hurts the one thing it hits, as UT's trace does
		profile.cleave_distribution = {
			attack = 0.01,
			impact = 0.01,
		}

		-- (a critical hit too, which would have the sniper shot's own armor multipliers)
		utils.set_armor_modifiers(profile, CONFIG.armor_attack, CONFIG.armor_impact, true)

		-- A punch has no headshots, as in UT (and a hit on the head is moved to the body, see body_hit)
		profile.no_headshot_boost = true
	end)

	return {
		damage_profile = name,
		hit_effect = "melee_hit_hammers_2h",
		ignore_shield_hit = true,
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
	local damage_type, damage_share

	for _, entry in ipairs(CONFIG.damage_types) do
		if not damage_type and share <= entry[1] + 0.0001 then
			damage_type, damage_share = entry[2], entry[3]
		end
	end

	-- (a charged punch is a heavy attack, and the bash a light one, as the game's push-stab is)
	PUNCH_ACTIONS[step] = make_punch_action("ut_shield_punch_" .. step, damage, damage_type, damage_share, "heavy_attack")
	BASH_ACTIONS[step] = make_punch_action("ut_shield_bash_" .. step, damage, CONFIG.damage_types[CONFIG.bash_damage_type][2], CONFIG.damage_types[CONFIG.bash_damage_type][3], "light_attack")
end

-- The step of the charge after holding for some time (ShieldFire.DoFireEffect)
local function charge_step(hold_time)
	local scale = (math.clamp(hold_time, CONFIG.min_hold_time, CONFIG.fully_charged_time) - CONFIG.min_hold_time) / (CONFIG.fully_charged_time - CONFIG.min_hold_time)

	return math.floor(scale * (CONFIG.damage_steps - 1) + 0.5), scale
end

-- What is in reach in front of a player: the first thing the ray from their middle, the way they look, hits within the range (UT
-- units), and whether it is an enemy. The ray finds enemies and the level as a shot does, and the things a melee swing hits (doors,
-- barrels, loose things, bodies) as the swing does (filter_melee_sweep), whichever is nearer.
local function raycast(physics_world, origin, direction, range)
	return PhysicsWorld.immediate_raycast_actors(physics_world, origin, direction, range * UNIT, "static_collision_filter", "filter_player_ray_projectile_static_only", "dynamic_collision_filter", "filter_player_ray_projectile_ai_only", "dynamic_collision_filter", "filter_player_ray_projectile_hitbox_only")
end

-- The first thing a melee swing would hit along the ray that is not a character: one with health (a door, a barrel), or one that
-- moves (a loose thing, a body)
local function first_object_hit(physics_world, origin, direction, range, owner_unit)
	local hits = PhysicsWorld.immediate_raycast(physics_world, origin, direction, range * UNIT, "all", "collision_filter", "filter_melee_sweep")

	for i = 1, #(hits or {}) do
		local actor = hits[i][4]
		local unit = actor and Actor.unit(actor)

		if unit and unit ~= owner_unit and (ScriptUnit.has_extension(unit, "health_system") and not Unit.get_data(unit, "breed") or Actor.is_dynamic(actor)) then
			return hits[i]
		end
	end
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
	local hit = first_beam_hit(raycast(physics_world, origin, direction, range), owner_unit)
	local object = first_object_hit(physics_world, origin, direction, range, owner_unit)

	if object and (not hit or object[2] < hit[2]) then
		hit = object
	end

	if not hit then
		return nil, nil, direction, origin
	end

	local hit_unit = ActionUtils.redirect_shield_hit(Actor.unit(hit[4]), hit[4])

	return hit, Unit.get_data(hit_unit, "breed") ~= nil and HEALTH_ALIVE[hit_unit] or false, direction, origin
end

-- The enemies and bodies in the cone of the punch (hit_angle) within the range, that a ray from the player reaches without a wall in
-- the way. Each is { unit, hit }: the hit is where that ray meets it, as a shot's hit is.
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
	-- (it looks as far as UT's punch reached, which is less than the punch reaches here)
	local _, is_enemy, direction, origin = in_reach(unit, physics_world, CONFIG.range)

	if is_enemy then
		return true
	elseif not origin then
		return false
	end

	for _, target in ipairs(targets_in_reach(unit, physics_world, origin, direction, CONFIG.range)) do
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
--   LOOSE: a loose thing, which moves as a whole.
local KILL, LOOSE = 1, 2
local throws = {}

local function add_throw(unit, kind, velocity, spin)
	throws[unit] = {
		kind = kind,
		spin = Vector3Box(spin),
		t = Managers.time:time("game"),
		velocity = Vector3Box(velocity),
	}
end

-- Sets the velocity and the spin (radians a second, about each axis) of the moving parts of a unit, as one body: each part also moves
-- with the spin about the middle of the parts, so that the whole body turns, not each part in its place. Returns whether anything moved.
local function move_parts(unit, velocity, spin)
	local actors = {}
	local middle = Vector3.zero()

	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		if actor and Actor.is_dynamic(actor) then
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
		elseif move_parts(unit, velocity, spin) then
			throws[unit] = nil
		end
	end
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(throws)
end

mod:network_register("ut_shield_throw", function (_, id, is_level_unit, kind, x, y, z, spin_x, spin_y, spin_z)
	local unit = Managers.state.network:game_object_or_level_unit(id, is_level_unit == 1)

	if unit and Unit.alive(unit) then
		add_throw(unit, kind, Vector3(x, y, z), Vector3(spin_x or 0, spin_y or 0, spin_z or 0))
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

	add_throw(unit, kind, velocity, spin)

	if id then
		mod:network_send("ut_shield_throw", "others", id, is_level_unit and 1 or 0, kind, Vector3.x(velocity), Vector3.y(velocity), Vector3.z(velocity), Vector3.x(spin), Vector3.y(spin), Vector3.z(spin))
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

		if actor then
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

-- What the punch does to a thing that is not a character, as a melee swing does (ActionSweep.hit_level_object and the attack of a unit
-- with health): doors, barrels and the like take its damage
local function hit_object(action, hit_unit, hit, direction, damage_profile_name, power_level)
	if not ScriptUnit.has_extension(hit_unit, "health_system") or Unit.get_data(hit_unit, "allow_melee_damage") == false then
		return
	end

	local network_manager = Managers.state.network
	local _, is_level_unit = network_manager:game_object_or_level_id(hit_unit)
	local damage_profile = DamageProfileTemplates[damage_profile_name]

	if is_level_unit then
		DamageUtils.damage_level_unit(hit_unit, action.owner_unit, "full", power_level, nil, false, damage_profile, 1, direction, action.item_name)
	else
		local weapon_system = Managers.state.entity:system("weapon_system")

		weapon_system:send_rpc_attack_hit(NetworkLookup.damage_sources[action.item_name], network_manager:unit_game_object_id(action.owner_unit), network_manager:unit_game_object_id(hit_unit), NetworkLookup.hit_zones.full, hit[1], direction, NetworkLookup.damage_profiles[damage_profile_name], "power_level", power_level, "hit_target_index", 1, "blocking", false, "boost_curve_multiplier", 0, "is_critical_strike", false)
	end
end

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

-- When each player's charge started, on the machine that owns their actions
local charge_started = {}

local function punch(action, t, power_level, bash)
	local owner_unit = action.owner_unit
	local hold_time = charge_started[owner_unit] and t - charge_started[owner_unit] or 0
	local step, scale = charge_step(hold_time)
	local range = bash and CONFIG.bash_range or CONFIG.hit_range
	local hit, is_enemy, direction, origin = in_reach(owner_unit, action.physics_world, range)

	charge_started[owner_unit] = nil

	if utils.is_local_player_unit(owner_unit) then
		mod.shield.charge_started = nil
		mod.shield.last_punch = t
	end

	if not origin then
		return
	end

	local punch_action = bash and BASH_ACTIONS[step] or PUNCH_ACTIONS[step]
	local targets = targets_in_reach(owner_unit, action.physics_world, origin, direction, range)

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

	-- Every enemy and every body in reach takes the punch as a hit (a body at its part nearest the player). A body that is down already is
	-- pushed at that zone as the game pushes a body for a hit, here and on the other machines; the game doesn't for a hit on one that is
	-- dead. What the punch kills is thrown.
	for _, target in ipairs(targets) do
		local alive = HEALTH_ALIVE[target.unit]
		local hit_on_target = target.hit
		local zone = hit_zone_name(hit_on_target)

		-- (a hit on the head goes to the body)
		if not hit_on_target or zone and NOT_PUNCHED[zone] then
			hit_on_target = body_hit(target.unit, origin, direction)
		end

		if hit_on_target then
			DamageUtils.process_projectile_hit(action.world, action.item_name, owner_unit, action.is_server, { hit_on_target }, punch_action, direction, true, nil, nil, false, power_level)
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

	-- The thing straight ahead, if it is not an enemy: a door or a barrel takes the punch as from a melee swing, a loose thing is thrown,
	-- and a wall near enough throws the player off it
	if not hit or is_enemy then
		return
	end

	local hit_unit = ActionUtils.redirect_shield_hit(Actor.unit(hit[4]), hit[4])

	if Unit.get_data(hit_unit, "breed") then
		return
	end

	hit_object(action, hit_unit, hit, direction, punch_action.damage_profile, power_level)

	if Actor.is_dynamic(hit[4]) then
		throw_hit(hit_unit, direction, false)
	end

	-- Anything else near enough throws the player off it and hurts them, as UT's punch of anything that is not a pawn does
	if hit[2] <= CONFIG.range * UNIT and not Actor.is_dynamic(hit[4]) then
		local self_damage = (CONFIG.min_self_damage + CONFIG.self_damage_scale * damage_for_step(step)) * CONFIG.self_damage_share

		utils.apply_self_damage(owner_unit, hit[1], -direction, action.item_name, self_damage)

		if utils.is_local_player_unit(owner_unit) then
			push_player(owner_unit, direction, force)
		end
	end
end

mod.dummy_start_callbacks.shield_gun = function (action, new_action, t, power_level)
	if new_action.ut_shield_charge then
		charge_started[action.owner_unit] = t

		if utils.is_local_player_unit(action.owner_unit) then
			mod.shield.charge_started = t
		end
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

	if reason ~= "new_interupting_action" then
		charge_started[owner_unit] = nil
	end

	if utils.is_local_player_unit(owner_unit) then
		mod.shield.charge_started = nil
	end
end

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

local function apply_template(template_name)
	local template = rawget(Weapons, template_name)
	local actions = template.actions
	local original = actions.action_one
	local heavy = original.heavy_attack or original.heavy_attack_left or original.default
	local game_shield = rawget(Weapons, "one_handed_sword_shield_template_1")

	for _, field in ipairs(game_shield and SHIELD_FIELDS or {}) do
		template[field] = game_shield[field]
	end

	-- The chart of the item's stats, from 0 to 7
	template.weapon_diagram = {
		light_attack = {
			[DamageTypes.ARMOR_PIERCING] = 5,
			[DamageTypes.CLEAVE] = 0,
			[DamageTypes.SPEED] = 3,
			[DamageTypes.STAGGER] = 6,
			[DamageTypes.DAMAGE] = 3,
		},
		heavy_attack = {
			[DamageTypes.ARMOR_PIERCING] = 6,
			[DamageTypes.CLEAVE] = 0,
			[DamageTypes.SPEED] = 1,
			[DamageTypes.STAGGER] = 7,
			[DamageTypes.DAMAGE] = 7,
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
end

-- The templates are the mod's own copies (items.register), so they are changed once
for template_name in pairs(TEMPLATE_NAMES) do
	apply_template(template_name)
end

mod.shield.template_names = TEMPLATE_NAMES
