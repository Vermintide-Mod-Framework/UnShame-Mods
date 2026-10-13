local mod = get_mod("unreal_tournament")

-- Helpers that more than one file uses. Load with mod:dofile("scripts/mods/unreal_tournament/utils").
local stagger_types = require("scripts/utils/stagger_types")

local utils = {}

-- Calling the game's functions

-- Calls a function of the game that looks at where units are.
-- The game sorts what an explosion hits, and looks at the positions of the units in a stagger or a hit, by their
-- positions in POSITION_LOOKUP. The mods' update runs before the game's own, where those positions are the last
-- frame's, which the game has let go stale (a "Stale Vector3", it breaks the call). Those are given their real position
-- for the duration of the call.
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

-- Whether a unit is the character of the player who is playing on this machine. The bots that the host has use the same weapons and
-- run the same hooks of them, and are not played through first person arms: what is done to the arms of a player's weapon isn't to be.
function utils.is_local_player_unit(unit)
	local local_player = Managers.player and Managers.player:local_player()

	return local_player ~= nil and local_player.player_unit == unit
end

-- Where the camera of the player who is playing on this machine is and how it is turned (nothing if there is none now)
function utils.camera_pose()
	local player = Managers.player and Managers.player:local_player()
	local camera_manager = Managers.state and Managers.state.camera

	if not player or not camera_manager or not camera_manager:has_viewport(player.viewport_name) then
		return
	end

	return camera_manager:camera_position(player.viewport_name), camera_manager:camera_rotation(player.viewport_name)
end

-- Whether the animations of a player's character are the weapon's to play: not while the game plays its own (hanging off a ledge,
-- being knocked down, dead). The weapons' stance is an animation event that is sent to the character that others see too, and
-- sent in the middle of one of those it replaces the animation of the state. (Only these: the status of being disabled is
-- wider, and holds in states where the stance is wanted.)
function utils.character_animation_is_free(unit)
	local status_extension = ScriptUnit.has_extension(unit, "status_system")

	return status_extension == nil or not (status_extension:get_is_ledge_hanging() or status_extension:is_knocked_down() or status_extension:is_dead())
end

-- The unit that holds a player now, if one does. The game's own get_disabler_unit can't be used for this: the unit that
-- grabbed a player (a Chaos Spawn, say) stays in their status after they are let go, and comes first in the game's
-- order, so it would be found again for a later grab by another disabler. Only what the status says is going on counts.
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

-- Lets a player go from the disabler that holds them: the disabler is staggered, which takes its behavior away from the
-- hold, and that frees the player. The host's game does this, it is where the enemies are.
function utils.release_from_disabler(disabler_unit, player_unit, t, stagger_duration)
	local blackboard = BLACKBOARDS[disabler_unit]
	local breed = blackboard and blackboard.breed

	if not breed then
		return
	end

	local away = Vector3.flat(Unit.world_position(disabler_unit, 0) - Unit.world_position(player_unit, 0))
	local direction = Vector3.length(away) > 0.01 and Vector3.normalize(away) or Vector3.forward()

	-- (the big ones can only be staggered by the strongest kind)
	local stagger_type = breed.boss_staggers and stagger_types.explosion or stagger_types.heavy

	-- (the game's statistics look at the positions of the units in a stagger, this runs before the game has made them current)
	utils.with_valid_positions(AiUtils.stagger, disabler_unit, blackboard, player_unit, direction, 1, stagger_type, stagger_duration, nil, t, 1, true, false)
end

-- Registration of new named game data.
-- The data has to exist on every peer in the same order, everyone in the game needs the mod.

-- Adds a name to a NetworkLookup table (the names are sent over the network as numbers)
function utils.register_network_lookup(lookup_name, key)
	local lookup = NetworkLookup[lookup_name]

	if rawget(lookup, key) then
		return
	end

	local index = #lookup + 1

	lookup[index] = key
	lookup[key] = index
end

-- A copy of an existing damage profile, changed by modify(profile)
function utils.register_damage_profile(name, source_name, modify)
	local profile = table.clone(DamageProfileTemplates[source_name])

	profile.name = name

	if modify then
		modify(profile)
	end

	-- Mirrors the _no_damage variants generated in damage_profile_templates.lua,
	-- explosions fall back to them when the target is immune
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

function utils.register_explosion_template(name, template)
	template.name = name
	ExplosionTemplates[name] = template

	utils.register_network_lookup("explosion_templates", name)
end

-- Damage scales linearly with the power distribution, armor modifiers and range falloff of a
-- damage profile, so the weapons share those and only differ in the power factor. Everything is
-- flat (no range falloff), like in UT, and there is no burning.
local BASE_ARMOR_MODIFIER = table.clone(DamageProfileTemplates.beam_shot.armor_modifier_near)

function utils.make_flat(profile, attack_power, impact_power)
	local target = profile.default_target

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

-- The power factors of the shock rifle's beam are the reference for the damage in UT2004's units:
-- its 45 damage is an attack power of 0.7 and an impact power of 0.3
utils.UT_REFERENCE_DAMAGE = 45
utils.REFERENCE_ATTACK_POWER = 0.7
utils.REFERENCE_IMPACT_POWER = 0.3

function utils.attack_power_for(ut_damage)
	return utils.REFERENCE_ATTACK_POWER * ut_damage / utils.UT_REFERENCE_DAMAGE
end

function utils.impact_power_for(ut_damage)
	return utils.REFERENCE_IMPACT_POWER * ut_damage / utils.UT_REFERENCE_DAMAGE
end

-- The multipliers of the damage (attack) and the stagger (impact) of a damage profile per armor type: unarmored, armored,
-- monsters, players, berserkers, super armor. With critical, critical hits go by the same.
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

-- How much of an explosion reaches the player who set it off (1 within the explosion's full damage radius, falling off to 0 at its radius),
-- and the direction from the explosion to the player's body. Nothing if the player is out of reach or dead. `explosion` is the "explosion"
-- table of the explosion template.
local function explosion_reach(owner_unit, position, explosion)
	local body_position = Unit.world_position(owner_unit, 0) + Vector3.up() * 0.9
	local offset = body_position - position
	local distance = Vector3.length(offset)
	local full_radius = explosion.max_damage_radius
	local falloff_range = explosion.radius - full_radius

	if distance >= explosion.radius or not HEALTH_ALIVE[owner_unit] then
		return nil
	end

	local factor = distance <= full_radius and 1 or 1 - (distance - full_radius) / falloff_range
	local direction = distance > 0.01 and offset * (1 / distance) or Vector3.up()

	return factor, direction
end

-- Damage to the player who set off an explosion. The game scales friendly fire damage, which
-- includes the damage to yourself, by a number that is 0 on the lower difficulties, so the damage
-- is applied directly: max_damage at the center of the explosion, falling off in the same way as
-- the explosion's damage does.
function utils.apply_explosion_self_damage(owner_unit, position, item_name, explosion, max_damage)
	local factor, direction = explosion_reach(owner_unit, position, explosion)

	if not factor then
		return
	end

	utils.apply_self_damage(owner_unit, position, direction, item_name, max_damage * factor)
end

-- Damages the player who fired a weapon. It is applied directly, as above.
function utils.apply_self_damage(owner_unit, position, direction, item_name, damage)
	DamageUtils.add_damage_network(owner_unit, owner_unit, damage, "torso", "drakegun", position, direction, item_name, nil, owner_unit, nil, nil, false, nil, nil, nil, nil, nil, 1)
end

-- Throws the player who set off an explosion away from it (a shock jump): `speed` m/s at the center of the explosion, falling off in the same
-- way as its damage does, added to the speed the player has. Only the player on this machine is moved: it is where their movement is run.
function utils.apply_explosion_self_push(owner_unit, position, explosion, speed)
	if not utils.is_local_player_unit(owner_unit) then
		return
	end

	local factor, direction = explosion_reach(owner_unit, position, explosion)

	if not factor then
		return
	end

	local locomotion_extension = ScriptUnit.extension(owner_unit, "locomotion_system")
	local velocity = locomotion_extension:current_velocity() + direction * (speed * factor)

	-- (the jumping state limits how fast the player can go up, the falling state doesn't)
	locomotion_extension:set_maximum_upwards_velocity(math.huge)
	locomotion_extension:set_forced_velocity(velocity)
	locomotion_extension:set_wanted_velocity(velocity)
end

-- A spread template with no spread (a copy of another one, with all its numbers zero): the weapon shoots where the crosshair is.
-- Made again on every load.
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

-- Returns a position as a vector. Some game calls give a Vector3Box, which engine functions don't accept.
function utils.as_vector(position)
	if pcall(Vector3.x, position) then
		return position
	end

	return position:unbox()
end

-- How much ammo the local player's ranged weapon has, in the clip and in reserve. Nil when there is no such weapon to ask.
function utils.local_ranged_ammo()
	local player = Managers.player and Managers.player:local_player_safe()
	local unit = player and player.player_unit
	local inventory_extension = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "inventory_system")
	local slot_data = inventory_extension and inventory_extension:get_slot_data("slot_ranged")
	local ammo_extension = slot_data and GearUtils.get_ammo_extension(slot_data.right_unit_1p, slot_data.left_unit_1p)

	return ammo_extension and ammo_extension:total_remaining_ammo() or nil
end

-- If it has none at all. False when there is no such weapon to ask.
function utils.local_ranged_out_of_ammo()
	return utils.local_ranged_ammo() == 0
end

-- The projectiles in flight, this machine's own and the copies of other players': a list of { unit, extension, own }.
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

-- The enemies (units with a breed that isn't a player's) that are in a sphere, the unit as the key
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

-- UT throws a ragdoll that an explosion of a weapon with bThrowRagdoll reaches (xPawn.TakeDamage: the rocket, the flak shell and the
-- shock combo): the whole body gets RagDeathVel (200 uu/s, 4 m/s) away from the explosion and 250 uu/s (5 m/s) up, however far from it the
-- body is, and a turn about the axis across the throw (18000 units of rotation a second, 1.73 rad/s). The speeds are UT's, as they are in
-- meters (the pellets of the flak, which are many, are scaled up for their own reason, in flak_cannon.lua).
utils.UT_RAGDOLL_SPEED = 4
utils.UT_RAGDOLL_UP = 5
utils.UT_RAGDOLL_SPIN = 18000 / 65536 * 2 * math.pi

-- The velocity and the spin that UT's throw gives a body that is away from a point in `direction` (a vector, not of length 1)
function utils.ut_ragdoll_throw(direction)
	local length = Vector3.length(direction)
	local unit_direction = length > 0.01 and direction * (1 / length) or Vector3.up()
	local velocity = unit_direction * utils.UT_RAGDOLL_SPEED + Vector3(0, 0, utils.UT_RAGDOLL_UP)
	local across = Vector3.cross(Vector3.up(), Vector3.flat(unit_direction))
	local spin = Vector3.length(across) > 0.01 and Vector3.normalize(across) * utils.UT_RAGDOLL_SPIN or Vector3.zero()

	return velocity, spin
end

-- Throws a ragdoll as above, away from a point. Returns if it had bodies that move.
function utils.blast_ragdoll(unit, center)
	local body_position

	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		if actor and Actor.is_dynamic(actor) then
			body_position = body_position or Actor.position(actor)
		end
	end

	if not body_position then
		return false
	end

	local velocity, spin = utils.ut_ragdoll_throw(body_position - center)

	utils.set_ragdoll_motion(unit, velocity, spin)

	return true
end

-- Gives every body of a ragdoll that moves the velocity and the spin
function utils.set_ragdoll_motion(unit, velocity, spin)
	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		if actor and Actor.is_dynamic(actor) then
			Actor.set_velocity(actor, velocity)
			Actor.set_angular_velocity(actor, spin)
		end
	end
end

-- The name of the template of the weapon a unit has wielded, if it has one
function utils.wielded_template_name(unit)
	local inventory_extension = ScriptUnit.has_extension(unit, "inventory_system")
	local equipment = inventory_extension and inventory_extension:equipment()
	local wielded = equipment and equipment.wielded

	-- (the item data is the entry of the item master list, or has it as data)
	return wielded and (wielded.template or wielded.data and wielded.data.template)
end

-- Returns the weapon skin (illusion) of the weapon a unit has wielded, if any.
function utils.wielded_skin(unit)
	local inventory_extension = ScriptUnit.has_extension(unit, "inventory_system")
	local equipment = inventory_extension and inventory_extension:equipment()
	local slot_data = equipment and equipment.wielded_slot and equipment.slots[equipment.wielded_slot]

	return slot_data and slot_data.skin
end

-- Actions of a weapon

-- The lookup data of an action: the game tells the other peers which action a projectile came from by it
function utils.set_lookup_data(action, template_name, action_name, sub_action_name)
	action.lookup_data = {
		item_template_name = template_name,
		action_name = action_name,
		sub_action_name = sub_action_name,
	}
end

-- (for all of the actions of a table of them: { action_name = { sub_action_name = action } })
function utils.set_actions_lookup_data(actions, template_name)
	for action_name, sub_actions in pairs(actions) do
		for sub_action_name, sub_action in pairs(sub_actions) do
			utils.set_lookup_data(sub_action, template_name, action_name, sub_action_name)
		end
	end
end

-- Delayed events: the callback is called delay seconds after it is scheduled, if is_valid() still holds by then (nothing
-- is done if the weapon was swapped or another action started in the meantime, for the animation events of a pose).
-- Returns a scheduler: scheduler.schedule(delay, is_valid, callback), scheduler.update(dt) (every frame),
-- scheduler.clear() (forgets what is waiting).
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

-- The outlines of the game on a unit (what is needed to take it off again is kept in the state)

-- Puts the outline (a template of OutlineSettings.templates, or one like it) on the unit, if it has the outline system
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
		-- (the unit may be gone)
		pcall(extension.remove_outline, extension, state.outline_id)

		state.outline_extension = nil
		state.outline_id = nil
	end
end

-- Packages (what a weapon's projectiles are made of)

-- The projectile units are only loaded with the characters that use them (a projectile that is spawned unloaded crashes the
-- game), so a weapon holds its own references to them. They are never released: units made from them may still be alive when the mod is
-- unloaded, and unloading a package with a locked resource is an error. Returns the holder of one weapon, holder.load(package_names),
-- under the reference name.
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

	-- (the names of the projectile units of the game's, in ProjectileUnits)
	function holder.load_projectile_units(unit_template_names)
		local package_names = {}

		for _, name in ipairs(unit_template_names) do
			package_names[#package_names + 1] = ProjectileUnits[name].projectile_unit_name
		end

		holder.load(package_names)
	end

	return holder
end

-- Weapons

-- If a weapon is switched on in the settings: its own checkbox, and the Weapons checkbox above all of them
function utils.is_weapon_enabled(setting_id)
	return mod:get("ut_weapons") ~= false and mod:get(setting_id) ~= false
end

-- If a weapon is switched on in the settings and the look of UT2004's is wanted for it (the Weapon Skins checkbox)
function utils.is_weapon_skin_enabled(setting_id)
	return utils.is_weapon_enabled(setting_id) and mod:get("weapon_skins") == true
end

-- A weapon that the settings can switch off: enable() makes it what the mod makes it, disable() gives the game its own
-- weapon back (and takes back what enable has loaded). It is enabled when the mod is, disabled when the mod is, enabled
-- or disabled when the settings change, and given back when the mod is unloaded.
function utils.register_weapon(setting_id, enable, disable)
	-- Whether enable has been called without disable since: enable takes the template for what the game made it, so it is not called twice
	local active = false

	local function sync()
		local wanted = utils.is_weapon_enabled(setting_id)

		if wanted and not active then
			active = true
			enable()
		elseif not wanted and active then
			active = false
			disable()
		end
	end

	local function give_back()
		if active then
			active = false
			disable()
		end
	end

	mod.enabled_callbacks[#mod.enabled_callbacks + 1] = sync

	mod.disabled_callbacks[#mod.disabled_callbacks + 1] = give_back

	mod.setting_changed_callbacks[#mod.setting_changed_callbacks + 1] = function (changed_setting_id)
		if changed_setting_id == setting_id or changed_setting_id == "ut_weapons" then
			sync()
		end
	end

	mod.unload_callbacks[#mod.unload_callbacks + 1] = give_back
end

return utils
