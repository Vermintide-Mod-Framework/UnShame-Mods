local mod = get_mod("unreal_tournament")

-- The hooks of the game's functions that more than one weapon needs. A function can be hooked once, so the weapons
-- don't hook them: each hook here has a table of callbacks, and a weapon adds its function under a name. Most of them
-- find it from what the shot or the weapon says (the name in the action, the template of the weapon).

-- The projectiles' explosions, creation and hits, by the name the action gives:
--   mod.aoe_callbacks[action.ut_aoe_callback] = function (projectile, aoe_data, position)
--       when a projectile makes its explosion (where the shot is handled, on the machine of the player who fired it)
--   mod.init_callbacks[action.ut_init_callback] = function (projectile)
--       when a projectile is made, on every peer
--   mod.hit_enemy_callbacks[action.ut_hit_enemy_callback] = function (func, projectile, is_owner, ...)
--       wraps the hit of an enemy: it calls func(projectile, ...) itself, is_owner is if it is the projectile of the player
--       who fired (the other peers get the hit from the network)
mod.aoe_callbacks = {}
mod.init_callbacks = {}
mod.hit_enemy_callbacks = {}

mod:hook_safe(PlayerProjectileUnitExtension, "do_aoe", function (self, aoe_data, position)
	local action = self._current_action
	local callback = action and action.ut_aoe_callback and mod.aoe_callbacks[action.ut_aoe_callback]

	if callback then
		callback(self, aoe_data, position)
	end
end)

for _, extension_class in ipairs({
	PlayerProjectileUnitExtension,
	PlayerProjectileHuskExtension,
}) do
	mod:hook_safe(extension_class, "init", function (self)
		local action = self._current_action
		local callback = action and action.ut_init_callback and mod.init_callbacks[action.ut_init_callback]

		if callback then
			callback(self)
		end
	end)

	mod:hook(extension_class, "hit_enemy", function (func, self, ...)
		local action = self._current_action
		local callback = action and action.ut_hit_enemy_callback and mod.hit_enemy_callbacks[action.ut_hit_enemy_callback]

		if callback then
			return callback(func, self, extension_class == PlayerProjectileUnitExtension, ...)
		end

		return func(self, ...)
	end)
end

-- Explosions, by the name of the explosion template:
--   mod.explosion_callbacks[template name] = function (world, position, rotation)
--       after an explosion is made, on every peer
-- A template that says ut_penetrates_shields goes through shields: the game asks AiUtils.attack_is_shield_blocked for
-- every enemy in an explosion, which is answered "not blocked" while the explosion of such a template is being made.
mod.explosion_callbacks = {}

local penetrating_explosion = false

mod:hook(AiUtils, "attack_is_shield_blocked", function (func, ...)
	if penetrating_explosion then
		return false
	end

	return func(...)
end)

mod:hook(DamageUtils, "create_explosion", function (func, world, attacker_unit, impact_position, rotation, explosion_template, ...)
	penetrating_explosion = not not explosion_template.ut_penetrates_shields

	-- (an error mustn't leave the flag set)
	local ok, error_message = pcall(func, world, attacker_unit, impact_position, rotation, explosion_template, ...)

	penetrating_explosion = false

	if not ok then
		error(error_message, 0)
	end

	local callback = mod.explosion_callbacks[explosion_template.name]

	if callback then
		callback(world, impact_position, rotation)
	end
end)

-- The overheating of a weapon, by the template of the weapon (the game's own explosion hurts the player, and is kept):
--   mod.overheat_callbacks[template] = function (state, item_data)
mod.overheat_callbacks = {}

mod:hook_safe(PlayerCharacterStateOverchargeExploding, "explode", function (self)
	if self.inside_inn then
		return
	end

	local inventory_extension = self.inventory_extension
	local slot_name = inventory_extension:get_wielded_slot_name()
	local slot_data = slot_name and inventory_extension:get_slot_data(slot_name)
	local item_data = slot_data and slot_data.item_data
	local callback = item_data and mod.overheat_callbacks[item_data.template]

	if callback then
		callback(self, item_data)
	end
end)

-- The charge actions of the weapons that are patched (the Bio Rifle's charge, the Link Gun's beam) are told about
-- every frame they are held, by name: the action says which callback in ut_charge_callback.
--   mod.charge_update_callbacks[action.ut_charge_callback] = function (action_charge, dt, t, world)
mod.charge_update_callbacks = {}

mod:hook_safe(ActionCharge, "client_owner_post_update", function (self, dt, t, world)
	local action = self.current_action
	local callback = action and action.ut_charge_callback and mod.charge_update_callbacks[action.ut_charge_callback]

	if callback then
		callback(self, dt, t, world)
	end
end)

-- What the weapons do when they are wielded (their default stance). Each is called with what the game gives _wield_slot
-- and looks at the weapon itself. Only for the player's own character: the bots and the other players wield weapons
-- through the same function, and what the weapons do here is with the player's own first person view.
--   mod.wield_callbacks[name] = function (inventory_extension, equipment, slot_data, unit_1p)
mod.wield_callbacks = {}

mod:hook_safe(SimpleInventoryExtension, "_wield_slot", function (self, equipment, slot_data, unit_1p)
	local local_player = Managers.player and Managers.player:local_player()

	if not local_player or local_player.player_unit ~= self._unit then
		return
	end

	for _, callback in pairs(mod.wield_callbacks) do
		callback(self, equipment, slot_data, unit_1p)
	end
end)

-- The heat the weapons are given, by the type of overcharge the game is adding (the id of the weapon's own value):
--   mod.overcharge_callbacks[type] = function (overcharge_extension, amount, charge_level)
--       returns the amount to add instead, or nil to add nothing
mod.overcharge_callbacks = {}

mod:hook(PlayerUnitOverchargeExtension, "add_charge", function (func, self, overcharge_amount, charge_level, overcharge_type, ...)
	local callback = mod.overcharge_callbacks[overcharge_type]

	if callback then
		overcharge_amount = callback(self, overcharge_amount, charge_level)

		if not overcharge_amount then
			return
		end
	end

	return func(self, overcharge_amount, charge_level, overcharge_type, ...)
end)

-- The mod framework sends the mod's network messages only to the players on its list of players that have the framework.
-- When a level is loaded the game removes the players and adds them again, and the framework can take a player off its
-- list after it has put them back, so that the messages of the mod (the Shock Rifle's beam for the others, the Bio Rifle's
-- goo of a client) go nowhere until the mod is reloaded. A moment after the players change, after the last change,
-- the framework is asked to ping everyone again, which puts the players back on the list on both sides.
local FRAMEWORK_PING_DELAY = 1 -- seconds

local framework_ping_timer -- seconds until the framework is asked to ping, nothing when it is not waiting

local function ask_framework_to_ping()
	framework_ping_timer = FRAMEWORK_PING_DELAY
end

mod:hook_safe(PlayerManager, "add_remote_player", ask_framework_to_ping)
mod:hook_safe(PlayerManager, "remove_player", ask_framework_to_ping)

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	if not framework_ping_timer then
		return
	end

	framework_ping_timer = framework_ping_timer - dt

	if framework_ping_timer <= 0 then
		framework_ping_timer = nil

		get_mod("VMF").ping_vmf_users()
	end
end

-- (temporary: which caller of the broadphase passes a position that isn't one, the trace is said in the chat)
local last_broadphase_report = 0

mod:hook(AiUtils, "broadphase_query", function (func, ...)
	local ok, result = pcall(func, ...)

	if not ok then
		if Application.time_since_launch() - last_broadphase_report > 5 then
			last_broadphase_report = Application.time_since_launch()

			mod:echo("broadphase_query failed: %s", debug.traceback(tostring(result), 2))
		end

		error(result, 0)
	end

	return result
end)
