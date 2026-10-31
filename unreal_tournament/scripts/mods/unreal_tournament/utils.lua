local mod = get_mod("unreal_tournament")

-- Helpers that the weapons and the other shared files use (mod.utils), and the extras mod's tests too: calling the game's functions,
-- registering network names and damage profiles, emptying a weapon template down to its base's, UT's units, spread and random numbers,
-- the damage, self damage and jumps of explosions, sounds, and finding units, projectiles and enemies in the world.
local stagger_types = require("scripts/utils/stagger_types")

local utils = {}
mod.utils = utils

-- Calling the game's functions

-- Calls a game function that looks at where units are.
-- The game works out what an explosion hits, and the positions of units in a stagger or a hit, from POSITION_LOOKUP. The mod's update
-- runs before the game's own, when those positions are still last frame's and have gone stale (a "Stale Vector3", which breaks the
-- call). So for the length of the call, every stale position is replaced with the unit's real one.
function utils.with_valid_positions(func, ...)
	local fixed = {}

	for unit, position in pairs(POSITION_LOOKUP) do
		if Script.type_name(position) ~= "Vector3" then
			fixed[unit] = position
		end
	end

	for unit in pairs(fixed) do
		POSITION_LOOKUP[unit] = Unit.alive(unit) and Unit.world_position(unit, 0) or nil
	end

	local ok, error_message = pcall(func, ...)

	for unit, position in pairs(fixed) do
		POSITION_LOOKUP[unit] = Unit.alive(unit) and position or nil
	end

	if not ok then
		error(error_message, 0)
	end
end

-- Whether a unit is the character of the player on this machine. Bots use the same weapons and run the same hooks, but they have no
-- first person arms, so what is done to a player's arms must not be done for them.
function utils.is_local_player_unit(unit)
	local local_player = Managers.player and Managers.player:local_player()

	return local_player ~= nil and local_player.player_unit == unit
end

-- Where the local player's camera is and how it is turned. Returns nothing if there is no camera now.
-- The node of the first person unit that the camera follows (GenericCameraExtension.get_follow_data). The game's head bob is an
-- animation that moves it, so what is drawn in the player's view is linked to it, not to the unit's root, to move with the camera.
function utils.camera_node(first_person_unit)
	return Unit.has_node(first_person_unit, "camera_node") and Unit.node(first_person_unit, "camera_node") or 0
end

function utils.camera_pose()
	local player = Managers.player and Managers.player:local_player()
	local camera_manager = Managers.state and Managers.state.camera

	if not player or not camera_manager or not camera_manager:has_viewport(player.viewport_name) then
		return
	end

	return camera_manager:camera_position(player.viewport_name), camera_manager:camera_rotation(player.viewport_name)
end

-- Whether the character's animations are free for the weapon to play. They are not while the game plays its own: hanging off a ledge,
-- being knocked down, or dead. A weapon's stance is an animation event that the other players see too, and sent during one of those
-- it would replace the animation of that state. Being disabled is not checked, because that is wider, and the stance is wanted in some
-- of those states.
function utils.character_animation_is_free(unit)
	local status_extension = ScriptUnit.has_extension(unit, "status_system")

	return status_extension == nil or not (status_extension:get_is_ledge_hanging() or status_extension:is_knocked_down() or status_extension:is_dead())
end

-- Whether the game has a reason of its own to hide the weapon (on a ladder, say). The reasons of the skins are not the game's: a weapon
-- drawn as two models has two skins, each with its own reason.
local function game_hides_weapon(first_person_extension)
	for reason in pairs(first_person_extension.hide_weapon_reasons) do
		if string.sub(reason, 1, 8) ~= "ut_skin_" then
			return true
		end
	end

	return false
end

-- Whether the game would show its own first person weapon now, from the player's first person extension: in the first person view,
-- with the arms and weapons shown (/hud), and with no reason of the game's own to hide the weapon (on a ladder, say), and with the
-- character's animations free (utils.character_animation_is_free). The skins' models, and the effects linked to them, show only then.
function utils.first_person_weapon_shown(first_person_extension)
	return not game_hides_weapon(first_person_extension) and first_person_extension:first_person_mode_active() and
		first_person_extension:first_person_units_visible() and utils.character_animation_is_free(first_person_extension.unit)
end

-- The unit that holds a player right now, if there is one. The game's own get_disabler_unit doesn't work for this: the unit that grabbed
-- a player (a Chaos Spawn, say) stays in their status after they are let go and comes first in its order, so it would be found again
-- for a later grab by another disabler. This only looks at what the status says is going on.
function utils.get_disabler(status_extension)
	local disabler_unit

	if status_extension:is_grabbed_by_tentacle() then
		disabler_unit = status_extension.grabbed_by_tentacle_unit
	elseif status_extension:is_pounced_down() then
		disabler_unit = status_extension:get_pouncer_unit()
	elseif status_extension:is_grabbed_by_chaos_spawn() then
		disabler_unit = status_extension.grabbed_by_chaos_spawn_unit
	elseif status_extension:is_grabbed_by_pack_master() then
		disabler_unit = status_extension:get_pack_master_grabber()
	elseif status_extension:is_grabbed_by_corruptor() then
		disabler_unit = status_extension.corruptor_unit
	end

	if disabler_unit and Unit.alive(disabler_unit) then
		return disabler_unit
	end
end

-- Frees a player from the disabler that holds them. The disabler is staggered, which interrupts its hold. The host does this, since
-- the enemies are on the host.
function utils.release_from_disabler(disabler_unit, player_unit, t, stagger_duration)
	local blackboard = BLACKBOARDS[disabler_unit]
	local breed = blackboard and blackboard.breed

	if not breed then
		return
	end

	local away = Vector3.flat(Unit.world_position(disabler_unit, 0) - Unit.world_position(player_unit, 0))
	local direction = Vector3.length(away) > 0.01 and Vector3.normalize(away) or Vector3.forward()

	-- Big enemies can only be staggered by the strongest kind
	local stagger_type = breed.boss_staggers and stagger_types.explosion or stagger_types.heavy

	-- The game's statistics read unit positions during a stagger, and they are not current yet when this runs
	utils.with_valid_positions(AiUtils.stagger, disabler_unit, blackboard, player_unit, direction, 1, stagger_type, stagger_duration, nil, t, 1, true, false)
end

-- Registering new named game data.
-- The data has to exist on every machine in the same order, so everyone in the game needs the mod.

-- Adds a name to a NetworkLookup table. Names are sent over the network as numbers.
function utils.register_network_lookup(lookup_name, key)
	local lookup = NetworkLookup[lookup_name]

	if rawget(lookup, key) then
		return
	end

	local index = #lookup + 1

	lookup[index] = key
	lookup[key] = index
end

-- Adds a damage profile, and its _no_damage variant. The game makes _no_damage variants of its profiles in damage_profile_templates.lua.
-- This makes the same, because explosions fall back to them when the target is immune.
local function add_profile(name, profile)
	profile.name = name

	local no_damage_name = name .. "_no_damage"
	local no_damage_profile = table.clone(profile)

	no_damage_profile.name = no_damage_name

	if no_damage_profile.targets then
		for _, target in ipairs(no_damage_profile.targets) do
			if target.power_distribution then
				target.power_distribution.attack = 0
			end
		end
	end

	if no_damage_profile.default_target.power_distribution then
		no_damage_profile.default_target.power_distribution.attack = 0
	end

	DamageProfileTemplates[name] = profile
	DamageProfileTemplates[no_damage_name] = no_damage_profile

	utils.register_network_lookup("damage_profiles", name)
	utils.register_network_lookup("damage_profiles", no_damage_name)
end

-- A copy of an existing damage profile, changed by modify(profile). What modify leaves alone is the game's profile's. The weapons that
-- are finished use utils.add_damage_profile instead, which leaves nothing to a profile of the game.
function utils.register_damage_profile(name, source_name, modify)
	local profile = table.clone(DamageProfileTemplates[source_name])

	if modify then
		modify(profile)
	end

	add_profile(name, profile)
end

-- Everything a damage profile from utils.add_damage_profile is made of. Each must be given: false where a flag is off or a boost curve
-- is none. The game's defaults, where it has one, are in brackets.
--   charge_value: what the game takes the hit for, for talents, traits and buffs ("instant_projectile", "projectile", "aoe",
--       "heavy_attack", ...).
--   shield_break: whether it breaks an enemy's shield. no_stagger_damage_reduction_ranged: whether a staggered enemy takes the game's
--       ranged damage bonus in full. is_explosion: whether its stagger is taken as an explosion's.
--   attack_template: the game's attack template, which picks the enemies' hit reactions and the sounds. damage_type: the type of the
--       damage, which picks the hit effects and how bodies die.
--   attack_power, impact_power: the power factors of the damage and the stagger (utils.attack_power_for and impact_power_for).
--   armor_attack, armor_impact: the multipliers of the damage and the stagger for each armor type (unarmored, armored, monsters, players,
--       berserkers, super armor), and critical_armor_attack and critical_armor_impact the same for a critical hit.
--   cleave_attack, cleave_impact: how many enemies it goes through (0.01 is the first one only).
--   boost_curve_type: the curve of the bonus of head shots and critical hits ("linesman_curve", "smiter_curve", ...; false: none, as the
--       game's explosions have). boost_curve_coefficient, boost_curve_coefficient_headshot: the curve's multipliers for critical hits and
--       head shots [1].
--   headshot_boost, headshot_boost_boss, headshot_boost_armor, headshot_boost_heavy_armor: the head bonus on the curve against others,
--       bosses, armour that the hit doesn't get through, and super armour that it doesn't get through [0.5, 0.25, 0.5, 0.25].
--       no_headshot_boost: no head bonus at all.
--   crit_boost: the bonus of a critical hit on the curve [0.5]. no_crit_boost: none.
--   stagger_duration_modifier, stagger_distance_modifier: how long and how far it staggers [1, 1].
-- And optionally, for a stagger that falls off with distance as the game's shotguns' does: impact_power_near, impact_power_far, and
-- impact_dropoff = { start, end } in meters.
local DAMAGE_PROFILE_FIELDS = {
	"charge_value",
	"shield_break",
	"no_stagger_damage_reduction_ranged",
	"is_explosion",
	"attack_template",
	"damage_type",
	"attack_power",
	"impact_power",
	"armor_attack",
	"armor_impact",
	"critical_armor_attack",
	"critical_armor_impact",
	"cleave_attack",
	"cleave_impact",
	"boost_curve_type",
	"boost_curve_coefficient",
	"boost_curve_coefficient_headshot",
	"headshot_boost",
	"headshot_boost_boss",
	"headshot_boost_armor",
	"headshot_boost_heavy_armor",
	"no_headshot_boost",
	"crit_boost",
	"no_crit_boost",
	"stagger_duration_modifier",
	"stagger_distance_modifier",
}

local OPTIONAL_DAMAGE_PROFILE_FIELDS = {
	impact_power_near = true,
	impact_power_far = true,
	impact_dropoff = true,
}

-- Adds a damage profile made only of what spec gives (see DAMAGE_PROFILE_FIELDS), and nothing of the game's profiles. A field that is
-- missing or unknown is an error when the mod loads.
function utils.add_damage_profile(name, spec)
	local known = {}

	for _, field in ipairs(DAMAGE_PROFILE_FIELDS) do
		fassert(spec[field] ~= nil, "[unreal_tournament] damage profile %s has no %s", name, field)

		known[field] = true
	end

	for field in pairs(spec) do
		fassert(known[field] or OPTIONAL_DAMAGE_PROFILE_FIELDS[field], "[unreal_tournament] damage profile %s has an unknown field %s", name, field)
	end

	local target = {
		attack_template = spec.attack_template,
		damage_type = spec.damage_type,
		boost_curve_type = spec.boost_curve_type or nil,
		boost_curve_coefficient = spec.boost_curve_coefficient,
		boost_curve_coefficient_headshot = spec.boost_curve_coefficient_headshot,
		headshot_boost = spec.headshot_boost,
		headshot_boost_boss = spec.headshot_boost_boss,
		headshot_boost_armor = spec.headshot_boost_armor,
		headshot_boost_heavy_armor = spec.headshot_boost_heavy_armor,
		power_distribution = {
			attack = spec.attack_power,
			impact = spec.impact_power,
		},
	}

	if spec.impact_dropoff then
		target.power_distribution_near = {
			attack = spec.attack_power,
			impact = spec.impact_power_near,
		}
		target.power_distribution_far = {
			attack = spec.attack_power,
			impact = spec.impact_power_far,
		}
		target.range_modifier_settings = {
			dropoff_start = spec.impact_dropoff[1],
			dropoff_end = spec.impact_dropoff[2],
		}
	end

	add_profile(name, {
		charge_value = spec.charge_value,
		shield_break = spec.shield_break,
		no_stagger_damage_reduction_ranged = spec.no_stagger_damage_reduction_ranged,
		is_explosion = spec.is_explosion,
		no_headshot_boost = spec.no_headshot_boost,
		crit_boost = spec.crit_boost,
		no_crit_boost = spec.no_crit_boost,
		stagger_duration_modifier = spec.stagger_duration_modifier,
		stagger_distance_modifier = spec.stagger_distance_modifier,
		armor_modifier = {
			attack = table.clone(spec.armor_attack),
			impact = table.clone(spec.armor_impact),
		},
		critical_strike = {
			attack_armor_power_modifer = table.clone(spec.critical_armor_attack),
			impact_armor_power_modifer = table.clone(spec.critical_armor_impact),
		},
		cleave_distribution = {
			attack = spec.cleave_attack,
			impact = spec.cleave_impact,
		},
		default_target = target,
		targets = {},
	})
end

-- Returns a copy of a damage profile's spec with some of its fields changed, for profiles that differ only in those
function utils.damage_profile_spec(base, changes)
	local spec = table.clone(base)

	for field, value in pairs(changes) do
		spec[field] = value
	end

	return spec
end

-- The parts of a weapon template that belong to its base weapon's animations, models and sounds, which a copy has to keep: the first
-- person state machine and the wield animations, the models in the hands and how they are linked, the model on display, the sound banks,
-- the reload's animation event, and the projectile units. And the mod's own name and tooltip keywords, which items.register sets.
local SHELL_FIELDS = {
	"state_machine",
	"wield_anim",
	"wield_anim_no_ammo",
	"wield_anim_not_loaded",
	"wield_anim_career",
	"wield_anim_no_ammo_career",
	"jump_anim_enabled_1p",
	"right_hand_unit",
	"left_hand_unit",
	"right_hand_attachment_node_linking",
	"left_hand_attachment_node_linking",
	"display_unit",
	"gui_texture",
	"wwise_dep_right_hand",
	"wwise_dep_left_hand",
	"reload_event",
	"no_ammo_reload_event",
	"required_projectile_unit_templates",
	"name",
	"tooltip_keywords",
}

-- Empties a copy of a weapon template down to what it has to keep of its base (SHELL_FIELDS, and the actions of the careers' skills and
-- of inspecting, which are animations), for a weapon that sets everything else itself. Returns what the template had, for the weapon to
-- take the base's animation events from by name.
function utils.template_shell(template)
	local base = table.clone(template)

	table.clear(template)

	for _, field in ipairs(SHELL_FIELDS) do
		template[field] = base[field]
	end

	template.actions = {}

	for action_name, action in pairs(base.actions) do
		if action_name == "action_inspect" or string.find(action_name, "^action_career") then
			template.actions[action_name] = action
		end
	end

	return base
end

function utils.register_explosion_template(name, template)
	template.name = name
	ExplosionTemplates[name] = template

	utils.register_network_lookup("explosion_templates", name)
end

-- Damage scales linearly with a profile's power distribution, armor modifiers and range falloff. So the weapons share those and only
-- differ in the power factor. Damage is flat, with no range falloff, like in UT, and there is no burning.
local BASE_ARMOR_MODIFIER = table.clone(DamageProfileTemplates.beam_shot.armor_modifier_near)

-- The damage type of a hit picks the game's hit effects, and those of the fire attacks (burn_*, drakegun) set the bodies they kill on
-- fire. The profiles that are copied from fire attacks get another damage type: an explosion gets the frag grenade's, which throws the
-- body and takes limbs off. The caller gives the damage type of the others, such as "shot_shotgun" for flechettes.
local EXPLOSION_DAMAGE_TYPES = {
	drakegun = "grenade",
	drakegun_glance = "grenade_glance",
}

function utils.make_flat(profile, attack_power, impact_power, damage_type)
	local target = profile.default_target

	target.damage_type = damage_type or EXPLOSION_DAMAGE_TYPES[target.damage_type] or target.damage_type
	target.power_distribution = {
		attack = attack_power,
		impact = impact_power,
	}
	target.power_distribution_near = nil
	target.power_distribution_far = nil
	target.range_modifier_settings = nil
	target.dot_template_name = nil
	target.dot_balefire_variant = nil

	profile.armor_modifier = table.clone(BASE_ARMOR_MODIFIER)
	profile.armor_modifier_near = nil
	profile.armor_modifier_far = nil
end

-- A hit on the head does this many times the damage of a hit on the body, up to 2, as UT's HeadShotDamageMult. The game adds the damage
-- times its boost curve at the profile's headshot_boost (0.5 if it has none), and every curve ends at 1, so a boost of 1 doubles it. The
-- action's own headshot_multiplier is not what the game uses for this. The players' talents and properties that raise head shots still
-- do.
function utils.set_headshot_multiplier(profile, multiplier)
	profile.default_target.headshot_boost = math.clamp(multiplier - 1, 0, 1)
	profile.default_target.boost_curve_coefficient_headshot = 1
end

-- Meters in one Unreal unit of the world. A UT2004 player is 88 units high, about 1.8 m.
utils.UT_UNIT = 0.02

-- How fast an xEmitter's particle of mass 1 falls, in UT units a second squared: Engine.dll's particle update pulls it by the zone's
-- gravity (950) times 0.35, times its mass (mMassRange). A negative mass makes it rise.
utils.UT_PARTICLE_GRAVITY = 950 * 0.35

-- An xEmitter's sprite or disc has its corners its size from its middle, along the two axes of the screen (or of the disc), so it is
-- a square turned 45 degrees, with its texture turned with it (Engine.dll, decompiled). Its side is this many times its size. UT's
-- green cross texture is an x, which shows as a + this way.
utils.UT_SPRITE_SIDE = math.sqrt(2)

-- How easily a projectile hits an enemy. UT's projectile is a point that hits a player's collision cylinder, 25 uu (0.5 m) in radius.
-- Here the projectile is a sphere that hits the enemy's body, which is about 0.2 m from its middle to its side, so the sphere reaches
-- the rest of the way. A projectile that is bigger than a point in UT adds its own size. Walls are hit by a ray, or by a sphere of the
-- projectile's own (ut_wall_radius, hooks.lua).
utils.UT_PROJECTILE_RADIUS = 0.3 -- m

-- The intensity of a weapon's light in a character's hand (xWeaponAttachment.WeaponLight, LightBrightness 255) for this game's lights.
-- UT's brightness has no measure here, so it was set in the game.
utils.WEAPON_LIGHT_INTENSITY = 0.5

-- Returns a random number between range[1] and range[2], as UT's Range values are picked
function utils.random_between(range)
	return range[1] + (range[2] - range[1]) * math.random()
end

-- Returns a random direction, every direction as likely as any other (UT's VRand). Points outside the unit sphere are thrown away,
-- or directions toward the corners of the cube would come up more often.
function utils.random_direction()
	local direction = Vector3(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1)
	local length = Vector3.length(direction)

	if length < 0.001 or length > 1 then
		return utils.random_direction()
	end

	return direction / length
end

-- How an xEmitter starts a particle (Engine.dll's InitParticle, decompiled, for its default ST_Sphere). The velocity is the speed times
-- the emitter's direction plus mDirDev times a random direction (VRand), axis by axis. That sum isn't made 1 long again, so a particle
-- that is turned aside flies faster than its speed. The place is the emitter's plus mPosDev times another random direction, which is on
-- the surface of that ellipsoid. mDirDev and mPosDev are along the world's axes. They are given as a number for all three, or as UT's
-- { X, Y, Z }, which are this game's y, x and z (as the meshes are turned: tools/asset_conversion).
local function ut_axes(deviation)
	if type(deviation) == "number" then
		return Vector3(deviation, deviation, deviation)
	end

	return Vector3(deviation[2], deviation[1], deviation[3])
end

function utils.ut_particle_velocity(direction, deviation, speed)
	local random, scale = utils.random_direction(), ut_axes(deviation)

	return (direction + Vector3(Vector3.x(random) * Vector3.x(scale), Vector3.y(random) * Vector3.y(scale), Vector3.z(random) * Vector3.z(scale))) * speed
end

-- The offset of a particle's place from the emitter's (see above), in the units of mPosDev
function utils.ut_particle_offset(deviation)
	local random, scale = utils.random_direction(), ut_axes(deviation)

	return Vector3(Vector3.x(random) * Vector3.x(scale), Vector3.y(random) * Vector3.y(scale), Vector3.z(random) * Vector3.z(scale))
end

-- Returns the aim moved by UT's random spread: a random direction, a random share of the spread long (InstantFire.DoFireEffect)
function utils.ut_spread(rotation, spread)
	local direction = Quaternion.forward(rotation) + utils.random_direction() * (spread * math.random())

	return Quaternion.look(Vector3.normalize(direction), Vector3.up())
end

-- Returns the way the surface faces where a projectile exploded, from the explosion's rotation (the projectile's, along its flight). The
-- projectile flew into the surface, so this is the normal that a ray along the flight finds, or against the flight if it finds none.
function utils.explosion_normal(world, position, rotation)
	local forward = Quaternion.forward(rotation)
	local physics_world = World.get_data(world, "physics_world")
	local hit, _, _, normal = PhysicsWorld.immediate_raycast(physics_world, position - forward * 0.5, forward, 1, "closest", "collision_filter", "filter_ai_line_of_sight_check")

	if hit and normal and Vector3.length(normal) > 0.5 then
		return Vector3.normalize(normal)
	end

	return -forward
end

-- Returns where a projectile starts, as UT's ProjectileFire puts it (ProjSpawnOffset): forward, right and down meters from the eye at
-- position. A projectile that would start behind a wall starts at the wall instead, because ProjectileFire.DoFireEffect traces to it.
function utils.projectile_start(position, rotation, forward, right, down)
	position = utils.as_vector(position)

	-- The game's spread rolls the rotation of a shot by a random angle about the way it points, whatever the spread numbers are. So
	-- right and up are taken from the way it points alone. Otherwise the offset would turn about the aim from shot to shot.
	local level = Quaternion.look(Quaternion.forward(rotation), Vector3.up())
	local offset = Quaternion.forward(level) * forward + Quaternion.right(level) * right - Quaternion.up(level) * down
	local distance = Vector3.length(offset)
	local direction = offset * (1 / distance)
	local physics_world = World.get_data(Managers.world:world("level_world"), "physics_world")
	local hit, _, hit_distance = PhysicsWorld.immediate_raycast(physics_world, position, direction, distance, "closest", "collision_filter", "filter_ai_line_of_sight_check")

	if hit then
		return position + direction * math.max(hit_distance - 0.05, 0)
	end

	return position + offset
end

-- Groups other players' projectiles into shots. The projectiles of one shot (a spread, a salvo) reach this machine one after another,
-- so a projectile that starts less than gap seconds after its player's last shot is part of that shot. Returns a table with
-- is_new_shot(owner_unit), which records the shot when it is new, and clear().
function utils.shot_grouping(gap)
	local last_shot = {}

	return {
		is_new_shot = function (owner_unit)
			local now = Managers.time:time("game")

			if last_shot[owner_unit] and now - last_shot[owner_unit] < gap then
				return false
			end

			last_shot[owner_unit] = now

			return true
		end,
		clear = function ()
			table.clear(last_shot)
		end,
	}
end

-- Puts UT's spread on the round of a game handgun action that is starting (self is ActionHandgun). The direction it gives the round is
-- kept for utils.handgun_round_hit.
function utils.set_handgun_spread(handgun_action, spread)
	local spread_extension = handgun_action.spread_extension

	if spread_extension then
		spread_extension.get_randomised_spread = function (extension, rotation)
			local spread_rotation = utils.ut_spread(rotation, spread)

			extension._ut_last_rotation = QuaternionBox(spread_rotation)

			return spread_rotation
		end
	end
end

-- Returns the surface material of a unit where it was hit (stone, wood_solid, dirt, ...), found as the game finds it for its impacts
-- (EffectHelper.play_surface_material_effects): the level's default where the unit has none.
function utils.surface_material(hit_unit, position, normal)
	local material_ids = EffectHelper.query_material_surface(hit_unit, position, normal)
	local material = material_ids and material_ids[1] and material_ids[1] ~= 0 and MaterialIDToName.surface_material[material_ids[1]]

	if not material then
		local level_settings = LevelHelper:current_level_settings()

		material = level_settings and level_settings.default_surface_material or DefaultSurfaceMaterial
	end

	return material
end

-- Returns where the round of a game handgun action hit, the normal of what it hit (the zero vector if nothing, and then the end is
-- 100 m along), whether what it hit is the level or a prop, not a character, and then the surface material it hit
-- (utils.surface_material). The ray goes the way set_handgun_spread sent the round, or along the aim.
function utils.handgun_round_hit(handgun_action)
	local owner_unit = handgun_action.owner_unit
	local first_person_extension = ScriptUnit.extension(owner_unit, "first_person_system")
	local origin, aim_rotation = first_person_extension:get_projectile_start_position_rotation()
	local stored = handgun_action.spread_extension and handgun_action.spread_extension._ut_last_rotation
	local rotation = stored and stored:unbox() or aim_rotation
	local direction = Quaternion.forward(rotation)
	local hits = PhysicsWorld.immediate_raycast_actors(handgun_action.physics_world, origin, direction, "static_collision_filter", "filter_player_ray_projectile_static_only", "dynamic_collision_filter", "filter_player_ray_projectile_ai_only", "dynamic_collision_filter", "filter_player_ray_projectile_hitbox_only")
	local hit = utils.first_beam_hit(hits, owner_unit)
	local hit_unit = hit and Actor.unit(hit[4])
	local hit_level = hit and not Unit.get_data(hit_unit, "breed") or false
	local surface = hit_level and utils.surface_material(hit_unit, hit[1], hit[3]) or nil

	return hit and hit[1] or origin + direction * 100, hit and hit[3] or Vector3.zero(), hit_level, surface
end

-- Returns a function that gives a screen gui in the level's world, made with the materials of material_file, for drawing over the
-- view, or nil outside a level. The game's own renderer only gets the mod's materials when a level starts, so after a mod reload it
-- wouldn't draw them until the next level. The gui belongs to the level's world, so each level gets a new one.
function utils.level_screen_gui(material_file)
	local gui, gui_world

	mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
		if gui and Managers.world:has_world("level_world") and Managers.world:world("level_world") == gui_world then
			World.destroy_gui(gui_world, gui)
		end

		gui, gui_world = nil, nil
	end

	-- The next level's world can be given the same handle, so the gui is forgotten when the level ends
	mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
		gui, gui_world = nil, nil
	end

	return function ()
		local world = Managers.world:has_world("level_world") and Managers.world:world("level_world")

		if not world then
			return
		end

		if gui_world ~= world then
			gui = World.create_screen_gui(world, "immediate", "material", material_file)
			gui_world = world
		end

		return gui
	end
end

-- Returns a callback for mod.bot_shot_callbacks that keeps a bot from firing an explosive where it would hurt the bot or a player: at
-- a target nearer than min_range, or with a player or another bot within ally_clearance of the target (meters). Otherwise the game's
-- own bot shooting goes on.
function utils.explosive_bot_shot(min_range, ally_clearance)
	return function (func, self, shoot_blackboard, action_data, input_extension, t)
		local target_unit = shoot_blackboard.target_unit
		local bot_unit = shoot_blackboard.ut_unit

		if not bot_unit or not HEALTH_ALIVE[target_unit] then
			return func(self, shoot_blackboard, action_data, input_extension, t)
		end

		local target_position = POSITION_LOOKUP[target_unit]

		if Vector3.distance(POSITION_LOOKUP[bot_unit], target_position) < min_range then
			return
		end

		for _, player in pairs(Managers.player:players()) do
			local player_unit = player.player_unit

			if player_unit and Unit.alive(player_unit) and player_unit ~= bot_unit and Vector3.distance(POSITION_LOOKUP[player_unit], target_position) < ally_clearance then
				return
			end
		end

		return func(self, shoot_blackboard, action_data, input_extension, t)
	end
end

-- Plays a sound that follows a unit. Returns a handle for utils.stop_sound, or nil if it didn't play.
function utils.play_on_unit(event, unit)
	local id, _, wwise_world = WwiseUtils.trigger_unit_event(Managers.world:world("level_world"), event, unit)

	return id and { id = id, wwise_world = wwise_world } or nil
end

-- Stops a sound that utils.play_on_unit started. The handle can be nil.
function utils.stop_sound(handle)
	if handle then
		WwiseWorld.stop_event(handle.wwise_world, handle.id)
	end
end

-- The Shock Rifle's beam is the reference for damage in UT2004's units: its 45 damage is an attack power of 0.7 and an impact power
-- of 0.3.
utils.UT_REFERENCE_DAMAGE = 45
utils.REFERENCE_ATTACK_POWER = 0.7
utils.REFERENCE_IMPACT_POWER = 0.3

-- The attack power of a hit that only staggers: 1 damage. A hit with no damage at all is shown as blocked by armor, because the game does not
-- check why there was none.
utils.STAGGER_HIT_ATTACK_POWER = 0.01

function utils.attack_power_for(ut_damage)
	return utils.REFERENCE_ATTACK_POWER * ut_damage / utils.UT_REFERENCE_DAMAGE
end

function utils.impact_power_for(ut_damage)
	return utils.REFERENCE_IMPACT_POWER * ut_damage / utils.UT_REFERENCE_DAMAGE
end

-- Sets the multipliers of a damage profile's damage (attack) and stagger (impact) for each armor type, in this order: unarmored,
-- armored, monsters, players, berserkers, super armor. With with_critical, critical hits use the same multipliers.
function utils.set_armor_modifiers(profile, attack, impact, with_critical)
	profile.armor_modifier.attack = table.clone(attack)
	profile.armor_modifier.impact = table.clone(impact)

	if with_critical then
		profile.critical_strike = {
			attack_armor_power_modifer = table.clone(attack),
			impact_armor_power_modifer = table.clone(impact),
		}
	end
end

-- Where an explosion aims at a character: the middle of its body
function utils.body_position(unit)
	return Unit.world_position(unit, 0) + Vector3.up() * 0.9
end

-- Whether the level hides a body from an explosion whose walls block players (the explosion table's ut_walls_block_players): UT's
-- HurtRadius only hurts what it can see. UT looks from the projectile's center, which is off the surface it hit by its radius
-- (ut_origin_offset, in meters), and the explosion here is on that surface. So the line goes from the body and stops that far short.
function utils.walls_block_explosion(explosion, position, body_position)
	if not explosion.ut_walls_block_players then
		return false
	end

	local offset = position - body_position
	local length = Vector3.length(offset) - (explosion.ut_origin_offset or 0)

	if length <= 0 then
		return false
	end

	local physics_world = World.get_data(Managers.world:world("level_world"), "physics_world")
	local hit = PhysicsWorld.immediate_raycast(physics_world, body_position, Vector3.normalize(offset), length, "closest", "collision_filter", "filter_ai_line_of_sight_check")

	return not not hit
end

-- How much of an explosion reaches a player: 1 inside the full damage radius, falling to 0 at the radius. Also returns the direction
-- from the explosion to the player's body. Returns nothing if the player is out of reach, hidden from it by a wall (see
-- walls_block_explosion) or dead. `explosion` is the "explosion" table of the explosion template.
local function explosion_reach(owner_unit, position, explosion)
	local body_position = utils.body_position(owner_unit)
	local offset = body_position - position
	local distance = Vector3.length(offset)
	local full_radius = explosion.max_damage_radius
	local falloff_range = explosion.radius - full_radius

	if distance >= explosion.radius or not HEALTH_ALIVE[owner_unit] then
		return nil
	end

	if utils.walls_block_explosion(explosion, position, body_position) then
		return nil
	end

	local factor = distance <= full_radius and 1 or 1 - (distance - full_radius) / falloff_range
	local direction = distance > 0.01 and offset * (1 / distance) or Vector3.up()

	return factor, direction
end

-- Damages the player who set off an explosion. The game scales friendly fire damage, which includes damage to yourself, by a number
-- that is 0 on the lower difficulties. So the damage is applied directly: max_damage at the center of the explosion, falling off the
-- same way as the explosion's damage.
function utils.apply_explosion_self_damage(owner_unit, position, item_name, explosion, max_damage)
	local factor, direction = explosion_reach(owner_unit, position, explosion)

	if not factor then
		return
	end

	utils.apply_self_damage(owner_unit, position, direction, item_name, max_damage * factor)
end

-- Damages the player who fired a weapon, applied directly as above. The damage can set off the player's own buffs, such as the
-- Ironbreaker's talent that makes an explosion at the player when Gromril Armour is lost, and they read the units' positions, so these
-- are made current (with_valid_positions).
function utils.apply_self_damage(owner_unit, position, direction, item_name, damage)
	utils.with_valid_positions(DamageUtils.add_damage_network, owner_unit, owner_unit, damage, "torso", "drakegun", position, direction, item_name, nil, owner_unit, nil, nil, false, nil, nil, nil, nil, nil, 1)
end

-- Throws the player on this machine away from an explosion, for a rocket or shock jump. Whoever set the explosion off, each machine
-- moves its own player, because that is where their movement runs. It adds `speed` m/s at the center of the explosion, falling off
-- the same way as its damage, to the player's speed.
function utils.apply_explosion_push(position, explosion, speed)
	local player = Managers.player:local_player_safe()
	local unit = player and player.player_unit

	if not unit or not Unit.alive(unit) then
		return
	end

	local factor, direction = explosion_reach(unit, position, explosion)

	if not factor then
		return
	end

	local locomotion_extension = ScriptUnit.extension(unit, "locomotion_system")
	local velocity = locomotion_extension:current_velocity() + direction * (speed * factor)

	-- The jumping state limits how fast the player can go up, and the falling state doesn't
	locomotion_extension:set_maximum_upwards_velocity(math.huge)
	locomotion_extension:set_forced_velocity(velocity)
	locomotion_extension:set_wanted_velocity(velocity)
end

-- Makes a spread template with no spread: a copy of another one with all its numbers set to zero, so the weapon shoots where the
-- crosshair is. It is made again on every load.
function utils.zero_spread_template(name, base_name)
	local function zero(tbl)
		for key, value in pairs(tbl) do
			if type(value) == "table" then
				zero(value)
			elseif type(value) == "number" then
				tbl[key] = 0
			end
		end
	end

	SpreadTemplates[name] = table.clone(SpreadTemplates[base_name])

	zero(SpreadTemplates[name])
end

-- Units in the world

-- Returns a position as a vector. Some game calls give a Vector3Box, and engine functions don't accept that.
function utils.as_vector(position)
	if pcall(Vector3.x, position) then
		return position
	end

	return position:unbox()
end

-- Returns what a hitscan shot hits first among the hits of its ray, which are sorted nearest first. It follows the rule of the game's
-- own Beam Staff (ActionBeam). The shooter's own hitbox, which the ray starts in, does not count. Neither does a hit on an enemy's
-- "afro" zone, which is a much bigger hit zone than the enemy itself, nor a hit on someone who is not to be hurt. The shot stops at
-- that hit, as UT's trace does. A hit on ignore_unit doesn't count either (a shot reflected off a shield starts at that player).
function utils.first_beam_hit(hits, owner_unit, ignore_unit)
	local allow_friendly_fire = DamageUtils.allow_friendly_fire_ranged(Managers.state.difficulty:get_difficulty_settings(), Managers.player:owner(owner_unit))

	for i = 1, #(hits or {}) do
		local hit_actor = hits[i][4]
		local hit_unit

		hit_unit, hit_actor = ActionUtils.redirect_shield_hit(Actor.unit(hit_actor), hit_actor)

		if hit_unit ~= owner_unit and hit_unit ~= ignore_unit then
			local breed = Unit.get_data(hit_unit, "breed")

			if not breed then
				return hits[i]
			end

			local is_enemy = DamageUtils.is_enemy(owner_unit, hit_unit)

			if (allow_friendly_fire and breed.is_player or is_enemy) and breed.hit_zones_lookup[Actor.node(hit_actor)].name ~= "afro" then
				return hits[i]
			end
		end
	end
end

-- How much ammo the local player's ranged weapon has, in the clip and in reserve, or nil if there is no such weapon
function utils.local_ranged_ammo()
	local player = Managers.player and Managers.player:local_player_safe()
	local unit = player and player.player_unit
	local inventory_extension = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "inventory_system")
	local slot_data = inventory_extension and inventory_extension:get_slot_data("slot_ranged")
	local ammo_extension = slot_data and GearUtils.get_ammo_extension(slot_data.right_unit_1p, slot_data.left_unit_1p)

	return ammo_extension and ammo_extension:total_remaining_ammo() or nil
end

-- Whether that weapon has no ammo at all. False if there is no such weapon.
function utils.local_ranged_out_of_ammo()
	return utils.local_ranged_ammo() == 0
end

-- The projectiles in flight, this machine's own and the copies of other players'. Returns a list of { unit, extension, own }.
function utils.flying_projectiles()
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

-- The enemies in a sphere (units with a breed that isn't a player's), as a table with the unit as the key
function utils.units_in_radius(world, position, radius)
	position = utils.as_vector(position)

	local physics_world = World.physics_world(world)
	local actors, num_actors = PhysicsWorld.immediate_overlap(physics_world, "shape", "sphere", "position", position, "size", radius, "collision_filter", "filter_explosion_overlap")
	local units = {}

	for i = 1, num_actors do
		local unit = Actor.unit(actors[i])
		local breed = unit and Unit.alive(unit) and AiUtils.unit_breed(unit)

		if breed and not breed.is_player then
			units[unit] = true
		end
	end

	return units
end

-- UT throws a ragdoll that is reached by the explosion of a weapon with bThrowRagdoll (xPawn.TakeDamage: the rocket, the flak shell
-- and the shock combo). The whole body gets RagDeathVel (200 uu/s, 4 m/s) away from the explosion and 250 uu/s (5 m/s) up, however
-- far away it is. It also spins about the axis across the throw, 18000 units of rotation a second (1.73 rad/s). These are UT's speeds
-- in meters. The flak pellets are scaled up for a reason of their own, in flak_cannon.lua.
utils.UT_RAGDOLL_SPEED = 4
utils.UT_RAGDOLL_UP = 5
utils.UT_RAGDOLL_SPIN = 18000 / 65536 * 2 * math.pi

-- The velocity and spin that UT's throw gives a body that lies in `direction` from the explosion (any length). A damage type can have
-- its own speeds instead (bKUseOwnDeathVel: speed away from the explosion and up, in m/s).
function utils.ut_ragdoll_throw(direction, speed, up)
	local length = Vector3.length(direction)
	local unit_direction = length > 0.01 and direction * (1 / length) or Vector3.up()
	local velocity = unit_direction * (speed or utils.UT_RAGDOLL_SPEED) + Vector3(0, 0, up or utils.UT_RAGDOLL_UP)
	local across = Vector3.cross(Vector3.up(), Vector3.flat(unit_direction))
	local spin = Vector3.length(across) > 0.01 and Vector3.normalize(across) * utils.UT_RAGDOLL_SPIN or Vector3.zero()

	return velocity, spin
end

-- Whether physics moves a part. A part that the animation moves (kinematic: a living enemy's, a body's before it falls, its hit
-- boxes, a part pinned to a wall) is dynamic too, but it must not be given a velocity: PhysX keeps such a part still and only
-- moves it to where the animation puts it, and a velocity also wakes it up, which breaks that (the game crashed in a horde, in
-- PhysX's update of the parts that animation moves). The game only moves parts that are physical.
function utils.moved_by_physics(actor)
	return Actor.is_dynamic(actor) and Actor.is_physical(actor)
end

-- The mass of the parts of a ragdoll that physics moves
function utils.ragdoll_mass(unit)
	local mass = 0

	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		if actor and utils.moved_by_physics(actor) then
			mass = mass + Actor.mass(actor)
		end
	end

	return mass
end

-- UT throws every body at the same speed: KSetSkelVel sets its velocity, whatever its mass. Here, not as in UT, a body heavier than
-- RAGDOLL_REFERENCE_MASS gets the push that gives that mass UT's speed, so it goes as much slower as it is heavier. A lighter body is
-- thrown at UT's speed. The mass was set in the game.
utils.RAGDOLL_REFERENCE_MASS = 160

-- The share of UT's throw speed that a body gets
function utils.throw_share(unit)
	local reference = utils.RAGDOLL_REFERENCE_MASS
	local mass = utils.ragdoll_mass(unit)

	if not reference or mass <= reference then
		return 1
	end

	return reference / mass
end

-- How many times as hard a unit's attacks push players and throw bodies: twice in the Berserk combo. UT doubles only the Shield Gun's
-- push off a wall (ShieldFire, bBerserk); here it is every push and throw of the weapons.
utils.BERSERK_PUSH = 2

function utils.push_scale(unit)
	return unit and mod.combos and mod.combos.kind_of(unit) == "berserk" and utils.BERSERK_PUSH or 1
end

-- Throws a ragdoll as above, away from a point, with the damage type's own speeds if they are given, and its velocity times scale (1 if
-- not given). Returns whether it had any bodies that move.
function utils.blast_ragdoll(unit, center, speed, up, scale)
	local body_position

	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		if actor and utils.moved_by_physics(actor) then
			body_position = body_position or Actor.position(actor)
		end
	end

	if not body_position then
		return false
	end

	local velocity, spin = utils.ut_ragdoll_throw(body_position - center, speed, up)

	utils.set_ragdoll_motion(unit, velocity * (scale or 1), spin)

	return true
end

-- Gives every moving body of a ragdoll this velocity and spin, less for a heavy body (throw_share)
function utils.set_ragdoll_motion(unit, velocity, spin)
	local share = utils.throw_share(unit)

	velocity = velocity * share
	spin = spin * share

	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		if actor and utils.moved_by_physics(actor) then
			Actor.set_velocity(actor, velocity)
			Actor.set_angular_velocity(actor, spin)
		end
	end
end

-- The template name of the weapon a unit is wielding, if any
function utils.wielded_template_name(unit)
	local inventory_extension = ScriptUnit.has_extension(unit, "inventory_system")
	local equipment = inventory_extension and inventory_extension:equipment()
	local wielded = equipment and equipment.wielded

	-- The item data is either the item master list entry, or has it as .data
	return wielded and (wielded.template or wielded.data and wielded.data.template)
end

-- The skin (illusion) of the weapon a unit is wielding, if any
function utils.wielded_skin(unit)
	local inventory_extension = ScriptUnit.has_extension(unit, "inventory_system")
	local equipment = inventory_extension and inventory_extension:equipment()
	local slot_data = equipment and equipment.wielded_slot and equipment.slots[equipment.wielded_slot]

	return slot_data and slot_data.skin
end

-- How many times as fast a unit attacks, from the game's attack_speed buffs (the Berserk combo's among them). The game speeds up its
-- actions by it, so the weapons' own timers are divided by it too.
function utils.attack_speed(unit)
	local buff_extension = unit and ScriptUnit.has_extension(unit, "buff_system")

	return buff_extension and buff_extension:apply_buffs_to_value(1, "attack_speed") or 1
end

-- Actions of a weapon

-- Gives a bot attack chain (attack_meta_data's attack_chain) an entry for every action of the weapon, empty for those it has no
-- attack from. The game looks up the transitions of the action the bot is in, whatever it is (WeaponUnitExtension._get_attack_chain_data),
-- and stops on an action that has none, such as the wield a bot is in after a reload of the mods.
function utils.cover_attack_chain_actions(actions, transitions)
	for action_name in pairs(actions) do
		transitions[action_name] = transitions[action_name] or {}
	end
end

-- Sets an action's lookup data. The game uses it to tell the other machines which action a projectile came from.
function utils.set_lookup_data(action, template_name, action_name, sub_action_name)
	action.lookup_data = {
		item_template_name = template_name,
		action_name = action_name,
		sub_action_name = sub_action_name,
	}
end

-- The same for every action in a table of { action_name = { sub_action_name = action } }
function utils.set_actions_lookup_data(actions, template_name)
	for action_name, sub_actions in pairs(actions) do
		for sub_action_name, sub_action in pairs(sub_actions) do
			utils.set_lookup_data(sub_action, template_name, action_name, sub_action_name)
		end
	end
end

-- Delayed events. The callback runs `delay` seconds after it is scheduled, but only if is_valid() is still true by then. That way
-- nothing happens if the weapon was swapped or another action started in the meantime.
-- Returns a scheduler: scheduler.schedule(delay, is_valid, callback), scheduler.update(dt) (call it every frame), and
-- scheduler.clear() (forget what is waiting).
function utils.delayed_events()
	local pending = {}
	local scheduler = {}

	function scheduler.schedule(delay, is_valid, callback)
		pending[#pending + 1] = {
			callback = callback,
			is_valid = is_valid,
			time_left = delay,
		}
	end

	function scheduler.update(dt)
		for i = #pending, 1, -1 do
			local event = pending[i]

			event.time_left = event.time_left - dt

			if event.time_left <= 0 then
				table.remove(pending, i)

				if event.is_valid() then
					event.callback()
				end
			end
		end
	end

	function scheduler.clear()
		table.clear(pending)
	end

	return scheduler
end

-- The game's outlines on a unit. What is needed to take an outline off again is kept in `state`.

-- Puts the outline (a template of OutlineSettings.templates, or one like it) on the unit, if the unit has the outline system
function utils.add_outline(state, unit, template)
	if state.outline_extension or not Unit.alive(unit) then
		return
	end

	local extension = ScriptUnit.has_extension(unit, "outline_system")

	if extension then
		state.outline_extension = extension
		state.outline_id = extension:add_outline(template)
	end
end

function utils.clear_outline(state)
	local extension = state.outline_extension

	if extension then
		-- The unit may be gone
		pcall(extension.remove_outline, extension, state.outline_id)

		state.outline_extension = nil
		state.outline_id = nil
	end
end

-- Packages: what a weapon's projectiles are made of

-- The game only loads projectile units with the characters that use them, and spawning a projectile whose unit is not loaded crashes
-- the game. So a weapon holds references of its own to them. They are never released: units made from them may still be alive when the
-- mod is unloaded, and unloading a package with a locked resource is an error.
-- Returns a holder for one weapon, with holder.load(package_names), under the reference name.
function utils.package_holder(reference_name)
	local holder = {}

	function holder.load(package_names)
		if not Managers.package then
			return
		end

		for _, package_name in ipairs(package_names) do
			if not Managers.package:has_loaded(package_name, reference_name) then
				Managers.package:load(package_name, reference_name)
			end
		end
	end

	-- Loads the packages of these game projectile units, by their names in ProjectileUnits
	function holder.load_projectile_units(unit_template_names)
		local package_names = {}

		for _, name in ipairs(unit_template_names) do
			package_names[#package_names + 1] = ProjectileUnits[name].projectile_unit_name
		end

		holder.load(package_names)
	end

	return holder
end