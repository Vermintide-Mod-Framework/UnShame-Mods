local mod = get_mod("unreal_tournament")

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")

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
--   mod.init_flow_event_filters[action.ut_init_flow_event_filter] = function (event_name)
--       while a projectile is made, on every peer: true if the flow event the game sends to its unit is to be held back
--   mod.skin_init_callbacks[action.ut_skin_init_callback] = function (projectile)
--       the same, for the weapon's skin (a projectile that has a callback of its own for its gameplay has one for its look as well)
mod.aoe_callbacks = {}
mod.init_callbacks = {}
mod.init_flow_event_filters = {}
mod.skin_init_callbacks = {}
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
	mod:hook(extension_class, "init", function (func, self, ...)
		local flow_event = Unit.flow_event

		-- (the game's flow events of the unit, which start its effects, can be held back: the extension tells the unit when it
		-- makes the projectile, and its action is known by then)
		Unit.flow_event = function (unit, event_name, ...)
			local action = self._current_action
			local filter = action and action.ut_init_flow_event_filter and mod.init_flow_event_filters[action.ut_init_flow_event_filter]

			if filter and unit == self._projectile_unit and filter(event_name) then
				return
			end

			return flow_event(unit, event_name, ...)
		end

		-- (an error mustn't leave the function replaced)
		local ok, error_message = pcall(func, self, ...)

		Unit.flow_event = flow_event

		if not ok then
			error(error_message, 0)
		end

		local action = self._current_action
		local callback = action and action.ut_init_callback and mod.init_callbacks[action.ut_init_callback]

		if callback then
			callback(self)
		end

		callback = action and action.ut_skin_init_callback and mod.skin_init_callbacks[action.ut_skin_init_callback]

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
--   mod.explosion_before_callbacks[template name] = function (world, position, attacker_unit)
--       before an explosion is made, on every peer: what it returns is given to the one after
--   mod.explosion_callbacks[template name] = function (world, position, rotation, before)
--       after an explosion is made, on every peer
-- A template that says ut_penetrates_shields goes through shields: the game asks AiUtils.attack_is_shield_blocked for
-- every enemy in an explosion, which is answered "not blocked" while the explosion of such a template is being made.
mod.explosion_before_callbacks = {}
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

	local before_callback = mod.explosion_before_callbacks[explosion_template.name]
	local before = before_callback and before_callback(world, impact_position, attacker_unit)

	-- (an error mustn't leave the flag set)
	local ok, error_message = pcall(func, world, attacker_unit, impact_position, rotation, explosion_template, ...)

	penetrating_explosion = false

	if not ok then
		error(error_message, 0)
	end

	local callback = mod.explosion_callbacks[explosion_template.name]

	if callback then
		callback(world, impact_position, rotation, before)
	end

	callback = mod.skin_explosion_callbacks[explosion_template.name]

	if callback then
		callback(world, impact_position, rotation)
	end
end)

-- What the skins of the weapons show of an explosion, by the name of the template, on every peer, after the weapon's own
-- (see explosion_callbacks): the weapon's skin draws the explosion that the game's own effect is taken away for
--   mod.skin_explosion_callbacks[template name] = function (world, position, rotation)
mod.skin_explosion_callbacks = {}

-- What the Shock Rifle tells its skin of its beam (the machine of the shooter, and those of the others after the message of
-- it): the one who fired, where the beam starts, where it ends and the way the surface it hits faces (nothing if it hit none)
--   mod.shock_beam_callbacks[name] = function (owner_unit, start_position, end_position, hit_normal)
mod.shock_beam_callbacks = {}

-- A shock combo has gone off (on every peer, as the explosion is made): the one who made it, and the enemies that it killed (a list of
-- units: the combo's damage is applied by the host, and it is the host that tells, the others get an empty list)
--   mod.shock_combo_callbacks[name] = function (attacker_unit, killed_units)
mod.shock_combo_callbacks = {}

-- The sounds a weapon's action plays for its player (the shot's, which the game plays and tells the others of), by the name of
-- the game's event: a weapon's skin takes one over
--   mod.hud_sound_callbacks[event name][name of the skin] = function (first_person_extension, play_on_husk)
--       returns true if the sound is played by it instead (the staffs' events are the ones of more than one weapon: each skin looks at
--       what the player wields)
mod.hud_sound_callbacks = {}

mod:hook(PlayerUnitFirstPerson, "play_hud_sound_event", function (func, self, event, wwise_source_id, play_on_husk)
	local callbacks = mod.hud_sound_callbacks[event]

	if callbacks then
		for _, callback in pairs(callbacks) do
			if callback(self, play_on_husk) then
				return
			end
		end
	end

	return func(self, event, wwise_source_id, play_on_husk)
end)

-- What the Link Gun's skin does with the beam (the game's own look of it is made of effects of the Sister's staff): where the beam starts
-- (the muzzle of the model, or of the mesh in the hand of the character; nothing if it is not the skin's to say) and how it is drawn
--   mod.link_beam_callbacks.start_position = function (owner_unit)
--   mod.link_beam_callbacks.draw = function (state, points, count, is_linked)    (the points are the curve, in the first `count`)
mod.link_beam_callbacks = {}

-- What the Bio Rifle's skin draws of its puddles (the game's own look of them is a fire, which the skin takes away): the puddle of an id
-- is shown at a place, for a time, as big as the radius, and ends
--   mod.puddle_visual_callbacks.show = function (id, position, radius, charged, duration)
--   mod.puddle_visual_callbacks.stop = function (id)
--   mod.puddle_visual_callbacks.burst = function (position, goo_scale)   (a puddle bursts: goo_scale is how much goo, 0 to 1)
mod.puddle_visual_callbacks = {}

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

-- What the weapons do when any charge action starts or ends (the venting of overcharge is one of those, and is the game's own
-- action), by name, for the player or the bot that owns the action:
--   mod.charge_start_callbacks[name] = function (action_charge, new_action)
--   mod.charge_finish_callbacks[name] = function (action_charge, reason)
mod.charge_start_callbacks = {}
mod.charge_finish_callbacks = {}

mod:hook_safe(ActionCharge, "client_owner_start_action", function (self, new_action)
	for _, callback in pairs(mod.charge_start_callbacks) do
		callback(self, new_action)
	end
end)

mod:hook_safe(ActionCharge, "finish", function (self, reason)
	for _, callback in pairs(mod.charge_finish_callbacks) do
		callback(self, reason)
	end
end)

-- What the weapons do when they are wielded (their default stance) and when they are put away. Each is called with what the
-- game gives _wield_slot and looks at the weapon itself. Only for the player's own character: the bots and the other players
-- wield weapons through the same function, and what the weapons do here is with the player's own first person view.
--   mod.unwield_callbacks[name] = function (inventory_extension, equipment, previous_item_data, slot_data)
--       before the swap, with what is wielded still the previous one (nothing, if there was no weapon wielded); slot_data
--       is what is wielded next, nothing if nothing is
--   mod.wield_callbacks[name] = function (inventory_extension, equipment, slot_data, unit_1p)
--       after it
mod.unwield_callbacks = {}
mod.wield_callbacks = {}

mod:hook(SimpleInventoryExtension, "_wield_slot", function (func, self, equipment, slot_data, unit_1p, ...)
	local local_player = Managers.player and Managers.player:local_player()
	local is_local_player = local_player and local_player.player_unit == self._unit

	if is_local_player then
		local previous_item_data = equipment.wielded

		for _, callback in pairs(mod.unwield_callbacks) do
			callback(self, equipment, previous_item_data, slot_data)
		end
	end

	-- (what it returns, whether it wielded a weapon, is what the caller shows the weapon's units by)
	local wielded = func(self, equipment, slot_data, unit_1p, ...)

	if is_local_player then
		for _, callback in pairs(mod.wield_callbacks) do
			callback(self, equipment, slot_data, unit_1p)
		end
	end

	return wielded
end)

-- The shots of the weapons that are patched (the Shock Rifle's), by name:
--   mod.handgun_start_callbacks[name] = function (action_handgun, new_action)
--   mod.handgun_update_callbacks[name] = function (action_handgun)
--   mod.charged_projectile_start_callbacks[name] = function (action_charged_projectile, new_action)
-- They are called on the machine of whoever owns the action: the player who plays, and the host for its bots.
mod.handgun_start_callbacks = {}
mod.handgun_update_callbacks = {}
mod.charged_projectile_start_callbacks = {}

mod:hook_safe(ActionHandgun, "client_owner_start_action", function (self, new_action)
	for _, callback in pairs(mod.handgun_start_callbacks) do
		callback(self, new_action)
	end
end)

mod:hook_safe(ActionHandgun, "client_owner_post_update", function (self)
	for _, callback in pairs(mod.handgun_update_callbacks) do
		callback(self)
	end
end)

mod:hook_safe(ActionChargedProjectile, "client_owner_start_action", function (self, new_action)
	for _, callback in pairs(mod.charged_projectile_start_callbacks) do
		callback(self, new_action)
	end
end)

--   mod.shotgun_start_callbacks[name] = function (action_shotgun, new_action)
--   mod.crossbow_start_callbacks[name] = function (action_crossbow, new_action, t)
--   mod.aim_start_callbacks[name] = function (action_aim, new_action, t)
--   mod.aim_finish_callbacks[name] = function (action_aim, reason)
--   mod.rocket_load_callbacks[name] = function (owner_unit, loaded)
--       the Rocket Launcher has loaded another rocket (how many are loaded now), for the player who loads
--   mod.rocket_lock_callbacks[name] = function (owner_unit, locked)
--       the Rocket Launcher has locked on to an enemy (locked is true), or has lost the lock (false), for the player who aims
mod.rocket_load_callbacks = {}
mod.rocket_lock_callbacks = {}
mod.shotgun_start_callbacks = {}
mod.crossbow_start_callbacks = {}
mod.aim_start_callbacks = {}
mod.aim_finish_callbacks = {}

mod:hook_safe(ActionShotgun, "client_owner_start_action", function (self, new_action)
	for _, callback in pairs(mod.shotgun_start_callbacks) do
		callback(self, new_action)
	end
end)

mod:hook_safe(ActionCrossbow, "client_owner_start_action", function (self, new_action, t)
	for _, callback in pairs(mod.crossbow_start_callbacks) do
		callback(self, new_action, t)
	end
end)

mod:hook_safe(ActionAim, "client_owner_start_action", function (self, new_action, t)
	for _, callback in pairs(mod.aim_start_callbacks) do
		callback(self, new_action, t)
	end
end)

mod:hook_safe(ActionAim, "finish", function (self, reason)
	for _, callback in pairs(mod.aim_finish_callbacks) do
		callback(self, reason)
	end
end)

-- The inspect of a weapon (held with the key, the game's action_inspect_hold): it starts and it ends, with the action
--   mod.inspect_callbacks[name] = function (action_dummy, started)
mod.inspect_callbacks = {}

mod:hook_safe(ActionDummy, "client_owner_start_action", function (self, new_action)
	if new_action.anim_event == "inspect_start" then
		for _, callback in pairs(mod.inspect_callbacks) do
			callback(self, true)
		end
	end
end)

mod:hook_safe(ActionDummy, "finish", function (self)
	if self.current_action and self.current_action.anim_event == "inspect_start" then
		for _, callback in pairs(mod.inspect_callbacks) do
			callback(self, false)
		end
	end
end)

-- The animation events that the game plays on the player's own first person unit for a weapon, by the template of the weapon: some
-- of the sounds of a weapon (the shot of the blunderbuss) are made by its animation, not by an event of Lua that can be taken over
-- (hud_sound_callbacks), and the first person unit and the arms are not shown while a weapon's skin is
--   mod.first_person_animation_filters[template] = function (event_name)
--       true if the event is not to be played (for the player who has it, not the others, who are told by the third person events)
mod.first_person_animation_filters = {}

mod:hook(WeaponUnitExtension, "_play_1p_anim", function (func, self, event_1p, event, ...)
	local owner_unit = self.owner_unit
	local template_name = utils.wielded_template_name(owner_unit)
	local filter = template_name and mod.first_person_animation_filters[template_name]

	if filter and utils.is_local_player_unit(owner_unit) and filter(event) then
		return
	end

	return func(self, event_1p, event, ...)
end)

-- The same for the character's third person unit. Its animation events come over the network from the player holding the weapon, and
-- sounds inside an animation (like reloading) are heard from every player's unit.
--   mod.third_person_animation_filters[template] = function (event_name)
mod.third_person_animation_filters = {}

mod:hook(AnimationSystem, "anim_event", function (func, self, unit, event_name, ...)
	local template_name = utils.wielded_template_name(unit)
	local filter = template_name and mod.third_person_animation_filters[template_name]

	if filter and filter(event_name) then
		return
	end

	return func(self, unit, event_name, ...)
end)

-- (the events that the game plays itself, not as the animation of an action of the weapon: the one of venting the heat is made by its overcharge)
mod:hook(PlayerUnitFirstPerson, "animation_event", function (func, self, event, ...)
	local template_name = utils.wielded_template_name(self.unit)
	local filter = template_name and mod.first_person_animation_filters[template_name]

	if filter and utils.is_local_player_unit(self.unit) and filter(event) then
		return
	end

	return func(self, event, ...)
end)

-- Before the first person view of a character is taken down (the character dies, the level ends): what a weapon has linked to
-- it has to be let go of first
--   mod.first_person_destroy_callbacks[name] = function (first_person_extension)
mod.first_person_destroy_callbacks = {}

mod:hook(PlayerUnitFirstPerson, "destroy", function (func, self, ...)
	for _, callback in pairs(mod.first_person_destroy_callbacks) do
		callback(self)
	end

	return func(self, ...)
end)

-- What is done to what the player sees just before the frame is drawn, after the game has updated everything of it (the game
-- shows the units of its own weapon and arms again at its own times, which a mod's update, that runs first, can't beat)
--   mod.pre_render_callbacks[name] = function ()
mod.pre_render_callbacks = {}

mod:hook_safe(StateIngame, "pre_render", function ()
	for _, callback in pairs(mod.pre_render_callbacks) do
		callback()
	end
end)

-- What the weapons do when the character starts to hang off a ledge (the game plays the animations of hanging, and the stance a
-- weapon keeps the character in with an animation event of its own is still there under them: it is to be ended). Each is called with
-- the unit of the character, for the player's own character only (the state of the other players' characters is theirs).
--   mod.ledge_hang_callbacks[name] = function (unit)
mod.ledge_hang_callbacks = {}

mod:hook_safe(PlayerCharacterStateLedgeHanging, "on_enter", function (self)
	for _, callback in pairs(mod.ledge_hang_callbacks) do
		callback(self.unit)
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

-- Hit effects that do nothing. A weapon that draws its own impact adds an effect name here (mod.silent_hit_effects[name] = true) and uses
-- that name as its action's hit_effect. The game needs a name, and sends it to other players as a number from a lookup table. That table
-- is full and adding a name is an error, so these names can't be sent, and the hooks below skip playing and sending them.
-- Walls and props, and enemies (flesh, armor), each have a local and a remote function, so all four are hooked.
mod.silent_hit_effects = {}

for _, function_name in ipairs({
	"play_surface_material_effects",
	"remote_play_surface_material_effects",
	"play_skinned_surface_material_effects",
	"remote_play_skinned_surface_material_effects",
}) do
	mod:hook(EffectHelper, function_name, function (func, effect_name, ...)
		if mod.silent_hit_effects[effect_name] then
			return
		end

		return func(effect_name, ...)
	end)
end

-- UT's console command: /slomo <number> runs the game at that speed. Below 1 slows it down, above 1 speeds it up, 1 is normal.
mod:command("slomo", "<number> - the speed of the game: below 1 slower, above 1 faster, 1 is normal", function (scale)
	local number = tonumber(scale)

	if not number or number < 0 then
		mod:echo("slomo: a number, 1 is normal")

		return
	end

	Managers.time:set_global_time_scale(number)
	mod:echo("slomo: %g", number)
end)

-- How the bots shoot a weapon of the mod. The game's bot shooting (BTBotShootAction) is hooked once, here (a mod can hook a function once), and
-- runs the callback of the weapon, which is found by a key of the weapon's attack_meta_data that is true:
--   mod.bot_shot_callbacks[key] = function (func, action, shoot_blackboard, action_data, input_extension, t)
--       fires, or calls func(action, shoot_blackboard, action_data, input_extension, t) for the game's own shot. shoot_blackboard.ut_unit is the bot.
mod.bot_shot_callbacks = {}

mod:hook_safe(BTBotShootAction, "enter", function (self, unit, blackboard)
	blackboard.shoot.ut_unit = unit
end)

mod:hook(BTBotShootAction, "_fire_shot", function (func, self, shoot_blackboard, action_data, input_extension, t)
	for key, callback in pairs(mod.bot_shot_callbacks) do
		if shoot_blackboard.attack_meta_data[key] then
			return callback(func, self, shoot_blackboard, action_data, input_extension, t)
		end
	end

	return func(self, shoot_blackboard, action_data, input_extension, t)
end)
