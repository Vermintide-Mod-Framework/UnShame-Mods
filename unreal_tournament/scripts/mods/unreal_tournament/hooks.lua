local mod = get_mod("unreal_tournament")

local utils = mod.utils

-- Hooks of game functions that more than one weapon needs. The game lets a function be hooked only once, so the weapons don't hook
-- these functions themselves. Each hook here runs a table of callbacks, and a weapon adds its own function to the table under a name.
-- The callback is found from what the weapon says: the name in the action, or the weapon's template.

-- Projectiles: explosions, creation and hits. The name comes from the action.
--   mod.aoe_callbacks[action.ut_aoe_callback] = function (projectile, aoe_data, position)
--       Runs when a projectile explodes, on the machine of the player who fired it.
--   mod.init_callbacks[action.ut_init_callback] = function (projectile)
--       Runs when a projectile is made, on every machine.
--   mod.hit_enemy_callbacks[action.ut_hit_enemy_callback] = function (func, projectile, is_owner, ...)
--       Wraps the hit on an enemy or on a player. It calls func(projectile, ...) itself. is_owner says if this is the projectile of the player who
--       fired it. The other machines get the hit over the network.
--   mod.init_flow_event_filters[action.ut_init_flow_event_filter] = function (event_name)
--       While a projectile is made, on every machine. Return true to drop a flow event that the game sends to the projectile's unit.
--   mod.skin_init_callbacks[action.ut_skin_init_callback] = function (projectile)
--       The same as init_callbacks, for the weapon's skin.
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

		-- While the projectile is made, the flow events sent to its unit (they start its effects) can be dropped
		Unit.flow_event = function (unit, event_name, ...)
			local action = self._current_action
			local filter = action and action.ut_init_flow_event_filter and mod.init_flow_event_filters[action.ut_init_flow_event_filter]

			if filter and unit == self._projectile_unit and filter(event_name) then
				return
			end

			return flow_event(unit, event_name, ...)
		end

		-- An error must not leave Unit.flow_event replaced
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

	-- Hitting a player or a bot (hit_player) calls the same callbacks as hitting an enemy.
	for _, function_name in ipairs({ "hit_enemy", "hit_player" }) do
		mod:hook(extension_class, function_name, function (func, self, ...)
			local action = self._current_action
			local callback = action and action.ut_hit_enemy_callback and mod.hit_enemy_callbacks[action.ut_hit_enemy_callback]

			if callback then
				return callback(func, self, extension_class == PlayerProjectileUnitExtension, ...)
			end

			return func(self, ...)
		end)
	end
end

-- Projectiles that a weapon's shot spawns. A weapon can change where and how a projectile starts, by its template name.
--   mod.spawn_projectile_callbacks[template name] = function (func, owner_unit, position, rotation, scale, angle, target_vector, speed,
--       item_name, item_template_name, action_name, sub_action_name, ...)
--       Wraps ActionUtils.spawn_player_projectile. It calls func(owner_unit, position, ...) itself, with the arguments it changed.
mod.spawn_projectile_callbacks = {}

mod:hook(ActionUtils, "spawn_player_projectile", function (func, owner_unit, position, rotation, scale, angle, target_vector, speed, item_name, item_template_name, action_name, sub_action_name, ...)
	local callback = mod.spawn_projectile_callbacks[item_template_name]

	if callback then
		return callback(func, owner_unit, position, rotation, scale, angle, target_vector, speed, item_name, item_template_name, action_name, sub_action_name, ...)
	end

	return func(owner_unit, position, rotation, scale, angle, target_vector, speed, item_name, item_template_name, action_name, sub_action_name, ...)
end)

-- Explosions. The name is the name of the explosion template.
--   mod.explosion_before_callbacks[template name] = function (world, position, attacker_unit)
--       Runs before an explosion is made, on every machine. What it returns is passed to the callback below.
--   mod.explosion_callbacks[template name] = function (world, position, rotation, before, scale)
--       Runs after an explosion is made, on every machine. The scale is the one the explosion was made with.
--   mod.any_explosion_callbacks[name] = function (explosion_template, position, scale)
--       Runs after every explosion of any template, on every machine.
--   mod.explosion_push_speeds[template name] = function (scale)
--       Returns how fast an explosion throws a player (see utils.apply_explosion_push). Runs on every machine, and the player on each
--       machine is thrown, whoever set the explosion off.
-- A template with ut_penetrates_shields goes through shields. The game asks AiUtils.attack_is_shield_blocked for every enemy in an
-- explosion, and while such an explosion is made the answer is always "not blocked".
mod.explosion_before_callbacks = {}
mod.explosion_callbacks = {}
mod.any_explosion_callbacks = {}
mod.explosion_push_speeds = {}

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

	-- An error must not leave the flag set
	local ok, error_message = pcall(func, world, attacker_unit, impact_position, rotation, explosion_template, ...)

	penetrating_explosion = false

	if not ok then
		error(error_message, 0)
	end

	-- The first argument after the template is the explosion's scale.
	local scale = ...
	local callback = mod.explosion_callbacks[explosion_template.name]

	if callback then
		callback(world, impact_position, rotation, before, scale)
	end

	local push_speed = mod.explosion_push_speeds[explosion_template.name]

	if push_speed then
		utils.apply_explosion_push(impact_position, explosion_template.explosion, push_speed(scale))
	end

	for _, any_callback in pairs(mod.any_explosion_callbacks) do
		any_callback(explosion_template, impact_position, scale)
	end

	callback = mod.skin_explosion_callbacks[explosion_template.name]

	if callback then
		callback(world, impact_position, rotation, scale)
	end
end)

-- What a weapon's skin draws for an explosion. It runs on every machine, after the callbacks above. The game's own effect of the
-- explosion is dropped, and the skin draws its own.
--   mod.skin_explosion_callbacks[template name] = function (world, position, rotation, scale)
mod.skin_explosion_callbacks = {}

-- The Shock Rifle tells its skin about its beam. It runs on the shooter's machine, and on the others' after they get the message.
--   mod.shock_beam_callbacks[name] = function (owner_unit, start_position, end_position, hit_normal, reflected)
-- owner_unit fired it. The beam goes from start_position to end_position. hit_normal is the way the surface it hit faces, or nil
-- if it hit nothing. A beam that a shield reflected comes in more than one piece: the ones after the first have reflected, and
-- start where they were reflected.
mod.shock_beam_callbacks = {}

-- The Lightning Gun tells its skin about its bolt. It runs on the shooter's machine, and on the others' after they get the message.
--   mod.lightning_bolt_callbacks[name] = function (owner_unit, end_position, hit_normal, arcs, arcs_start, arc_normals)
-- owner_unit fired it. The bolt goes from the weapon to end_position. hit_normal is the way the surface it hit faces, or the zero
-- vector if it hit nothing. arcs is a list of the ends of the arcs of lightning that jump from arcs_start, and arc_normals the way
-- what each arc hit faces (back along the arc if it hit nothing).
mod.lightning_bolt_callbacks = {}

-- The Minigun tells its skin about each round. It runs on the shooter's machine, and on the others' after they get the message.
--   mod.minigun_shot_callbacks[name] = function (owner_unit, mode, end_position, hit_normal, hit_level, heavy_wall)
-- mode is "primary" or "alt". The round goes from the weapon to end_position. hit_normal is the zero vector if it hit nothing. hit_level
-- is true if it hit the level or a prop, not a character. heavy_wall is true if that is a surface where UT's primary round makes its
-- heavy wall hit (minigun.lua).
mod.minigun_shot_callbacks = {}

-- A shock combo has gone off. It runs on every machine, when the explosion is made.
--   mod.shock_combo_callbacks[name] = function (attacker_unit, killed_units)
-- attacker_unit made the combo. killed_units is a list of the enemies it killed. The host applies the damage and tells the others,
-- so on the other machines the list is empty.
mod.shock_combo_callbacks = {}

-- The sounds a weapon's action plays for its player, such as the shot sound. The game plays them and tells the others. The name is
-- the game's sound event, and a weapon's skin can take it over.
--   mod.hud_sound_callbacks[event name][name of the skin] = function (first_person_extension, play_on_husk)
--       Return true if the skin plays the sound itself. Several weapons share some staff events, so each skin checks
--       which weapon the player holds.
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

-- How the Link Gun's skin draws the beam.
--   mod.link_beam_callbacks.start_position = function (owner_unit)
--       Where the beam starts: the muzzle of the model, or of the mesh in the character's hand.
--   mod.link_beam_callbacks.draw = function (state, points, count, is_linked)
--       Draws the beam. points is the curve, and the first `count` points are used.
mod.link_beam_callbacks = {}

-- How the Bio Rifle's skin draws the globs that have landed. They run on every machine.
--   mod.goop_visual_callbacks.land = function (id, position, normal, level)
--       A glob with this id lands on a surface. normal is the way the surface faces, and level is how much goop the glob has.
--   mod.goop_visual_callbacks.merge = function (id, level)
--       Another glob lands in the glob with this id, and it now has this level.
--   mod.goop_visual_callbacks.stop = function (id)
--       The glob with this id is gone.
mod.goop_visual_callbacks = {}

-- When a weapon overheats and explodes, by the weapon's template. The game's own explosion still happens and hurts the player.
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

-- Charge actions (the Bio Rifle's charge, the Link Gun's beam) are called every frame they are held. The action names the callback in
-- ut_charge_callback.
--   mod.charge_update_callbacks[action.ut_charge_callback] = function (action_charge, dt, t, world)
mod.charge_update_callbacks = {}

mod:hook_safe(ActionCharge, "client_owner_post_update", function (self, dt, t, world)
	local action = self.current_action
	local callback = action and action.ut_charge_callback and mod.charge_update_callbacks[action.ut_charge_callback]

	if callback then
		callback(self, dt, t, world)
	end
end)

-- Runs when any charge action starts or ends, for the player or bot that owns it. The game's own venting of overcharge is a charge
-- action too.
--   mod.charge_start_callbacks[name] = function (action_charge, new_action)
--   mod.charge_finish_callbacks[name] = function (action_charge, reason, data)
-- data is what the game gives with the reason. For "new_interupting_action" it has new_action, the name of the action that
-- interrupts the charge (a weapon switch is "action_wield").
mod.charge_start_callbacks = {}
mod.charge_finish_callbacks = {}

mod:hook_safe(ActionCharge, "client_owner_start_action", function (self, new_action)
	for _, callback in pairs(mod.charge_start_callbacks) do
		callback(self, new_action)
	end
end)

mod:hook_safe(ActionCharge, "finish", function (self, reason, data)
	for _, callback in pairs(mod.charge_finish_callbacks) do
		callback(self, reason, data)
	end
end)

-- Runs when a weapon is wielded and when it is put away. It gets what the game gives _wield_slot, and each callback checks the
-- weapon itself. It only runs for the player's own character, because bots and other players wield weapons through the same function,
-- and these callbacks work on the player's own first person view.
--   mod.unwield_callbacks[name] = function (inventory_extension, equipment, previous_item_data, slot_data)
--       Runs before the swap, while the previous weapon is still wielded (nothing if there was none). slot_data is the weapon
--       that comes next, or nothing.
--   mod.wield_callbacks[name] = function (inventory_extension, equipment, slot_data, unit_1p)
--       Runs after the swap.
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

	-- It returns whether a weapon was wielded, which the caller uses to show the weapon's units
	local wielded = func(self, equipment, slot_data, unit_1p, ...)

	if is_local_player then
		for _, callback in pairs(mod.wield_callbacks) do
			callback(self, equipment, slot_data, unit_1p)
		end
	end

	return wielded
end)

-- Shots of the Shock Rifle:
--   mod.handgun_start_callbacks[name] = function (action_handgun, new_action)
--   mod.handgun_update_callbacks[name] = function (action_handgun)
--   mod.charged_projectile_start_callbacks[name] = function (action_charged_projectile, new_action)
-- They run on the machine that owns the action: the player's, or the host's for its bots.
mod.handgun_start_callbacks = {}
mod.handgun_update_callbacks = {}
mod.charged_projectile_start_callbacks = {}

mod:hook_safe(ActionHandgun, "client_owner_start_action", function (self, new_action)
	for _, callback in pairs(mod.handgun_start_callbacks) do
		callback(self, new_action)
	end
end)

-- The shot sends flow events to the game's weapon unit, which start the game's own effects of the shot (lua_bullet_trail is the tracer).
-- A UT weapon draws its own, so its action can name events to drop: action.ut_dropped_flow_events = { [event_name] = true }.
mod:hook(ActionHandgun, "client_owner_post_update", function (func, self, ...)
	local dropped = self.current_action and self.current_action.ut_dropped_flow_events

	if dropped then
		local flow_event = Unit.flow_event

		Unit.flow_event = function (unit, event_name, ...)
			if dropped[event_name] then
				return
			end

			return flow_event(unit, event_name, ...)
		end

		-- An error must not leave Unit.flow_event replaced
		local ok, error_message = pcall(func, self, ...)

		Unit.flow_event = flow_event

		if not ok then
			error(error_message, 0)
		end
	else
		func(self, ...)
	end

	for _, callback in pairs(mod.handgun_update_callbacks) do
		callback(self)
	end
end)

mod:hook_safe(ActionChargedProjectile, "client_owner_start_action", function (self, new_action)
	for _, callback in pairs(mod.charged_projectile_start_callbacks) do
		callback(self, new_action)
	end
end)

-- Shots and aiming of the Flak Cannon and the Rocket Launcher:
--   mod.shotgun_start_callbacks[name] = function (action_shotgun, new_action)
--   mod.crossbow_start_callbacks[name] = function (action_crossbow, new_action, t)
--   mod.aim_start_callbacks[name] = function (action_aim, new_action, t)
--   mod.aim_finish_callbacks[name] = function (action_aim, reason)
--   mod.rocket_load_callbacks[name] = function (owner_unit, loaded)
--       The Rocket Launcher loaded another rocket. loaded is how many are loaded now. Runs for the player who loads.
--   mod.rocket_lock_callbacks[name] = function (owner_unit, locked)
--       The Rocket Launcher locked on to an enemy (locked is true) or lost the lock (false). Runs for the player who aims.
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

-- Inspecting a weapon (the game's action_inspect_hold, held with the key). Runs when the inspect starts and when it ends.
--   mod.inspect_callbacks[name] = function (action_dummy, started)
mod.inspect_callbacks = {}

-- Dummy actions (and the melee start, which is one) that a weapon of the mod made. They run on the machine that owns the action.
--   mod.dummy_start_callbacks[name] = function (action_dummy, new_action, t, power_level)
mod.dummy_start_callbacks = {}

mod:hook_safe(ActionDummy, "client_owner_start_action", function (self, new_action, t, chain_action_data, power_level)
	if new_action.anim_event == "inspect_start" then
		for _, callback in pairs(mod.inspect_callbacks) do
			callback(self, true)
		end
	end

	for _, callback in pairs(mod.dummy_start_callbacks) do
		callback(self, new_action, t, power_level)
	end
end)

-- And when they end, with the game's reason ("hold_input_released" when the button they are held with is let go)
--   mod.dummy_finish_callbacks[name] = function (action_dummy, reason)
mod.dummy_finish_callbacks = {}

mod:hook_safe(ActionDummy, "finish", function (self, reason)
	if self.current_action and self.current_action.anim_event == "inspect_start" then
		for _, callback in pairs(mod.inspect_callbacks) do
			callback(self, false)
		end
	end

	for _, callback in pairs(mod.dummy_finish_callbacks) do
		callback(self, reason)
	end
end)

-- A player's block stops an attack (a blow or a shot)
--   mod.block_callbacks[name] = function (status_extension, attacking_unit)
mod.block_callbacks = {}

mod:hook_safe(GenericStatusExtension, "blocked_attack", function (self, fatigue_type, attacking_unit)
	for _, callback in pairs(mod.block_callbacks) do
		callback(self, attacking_unit)
	end
end)

-- Pushes (the push out of a block). They run on the machine that owns the action.
--   mod.push_start_callbacks[name] = function (action_push, new_action, t)
mod.push_start_callbacks = {}

mod:hook_safe(ActionPushStagger, "client_owner_start_action", function (self, new_action, t)
	for _, callback in pairs(mod.push_start_callbacks) do
		callback(self, new_action, t)
	end
end)

-- Animation events that the game plays on the player's own first person unit, by the weapon's template. Some weapon sounds (the
-- blunderbuss's shot) are in the animation, not in a Lua sound event that hud_sound_callbacks could take over. The first person unit
-- and the arms are hidden anyway while a skin is shown, so a skin can drop these events.
--   mod.first_person_animation_filters[template] = function (event_name)
--       Return true to drop the event. It only applies to the player who holds the weapon. The others get the third person events.
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

-- The same for the characters' third person units, the player's own included. The others' animation events come over the network from
-- the player who holds the weapon, and sounds inside an animation (like reloading) are heard from every player's unit.
--   mod.third_person_animation_filters[template] = function (event_name, unit)
-- A filter sees the events of every character that wields the weapon, so it can also play sounds for them.
mod.third_person_animation_filters = {}

mod:hook(AnimationSystem, "anim_event", function (func, self, unit, event_name, ...)
	local template_name = utils.wielded_template_name(unit)
	local filter = template_name and mod.third_person_animation_filters[template_name]

	if filter and filter(event_name, unit) then
		return
	end

	return func(self, unit, event_name, ...)
end)

-- The player's own weapon action plays its third person event on their own character here, and sends it to the others (who play it in
-- the functions around this). A dropped event is neither played nor sent.
mod:hook(WeaponUnitExtension, "_play_3p_anim", function (func, self, event_3p, event, owner_unit, ...)
	local template_name = utils.wielded_template_name(owner_unit)
	local filter = template_name and mod.third_person_animation_filters[template_name]

	if filter and filter(event_3p, owner_unit) then
		return
	end

	return func(self, event_3p, event, owner_unit, ...)
end)

-- The animation of another player's weapon action comes over the network with the speed of the attack, and is played by this function
mod:hook(AnimationSystem, "anim_event_with_variable_float", function (func, self, unit, event_name, ...)
	local template_name = utils.wielded_template_name(unit)
	local filter = template_name and mod.third_person_animation_filters[template_name]

	if filter and filter(event_name, unit) then
		return
	end

	return func(self, unit, event_name, ...)
end)

-- Some weapon sounds are played by the weapon unit's flow, when an animation reaches a point (the crossbow's shot and reload). A weapon
-- can mute them:
--   mod.sound_event_filters[template] = function (event_name, character) return true to mute it
mod.sound_event_filters = {}

-- The character that holds this weapon unit, or the character itself
local function sound_owner(unit)
	local players = Managers.player and Managers.player:human_and_bot_players()

	for _, player in pairs(players or {}) do
		local character = player.player_unit

		if character and Unit.alive(character) then
			local inventory_extension = ScriptUnit.has_extension(character, "inventory_system")
			local equipment = inventory_extension and inventory_extension:equipment()

			if unit == character or equipment and (equipment.left_hand_wielded_unit_3p == unit or equipment.right_hand_wielded_unit_3p == unit) then
				return character
			end
		end
	end

	return nil
end

local function sound_muted(params)
	local event_name = params.name or params.Name
	local unit = params.unit or params.Unit

	if not event_name or not unit then
		return false
	end

	local character = sound_owner(unit)
	local template_name = character and utils.wielded_template_name(character)
	local filter = template_name and mod.sound_event_filters[template_name]

	return filter ~= nil and filter(event_name, character) == true
end

local muted_flow_return = {
	playing_id = 0,
	source_id = 0,
	Playing_Id = 0,
	Source_Id = 0,
}

mod:hook(WwiseFlowCallbacks, "wwise_trigger_event", function (func, params, ...)
	if sound_muted(params) then
		return muted_flow_return
	end

	return func(params, ...)
end)

mod:hook(_G, "flow_callback_wwise_trigger_event_with_environment", function (func, params, ...)
	if sound_muted(params) then
		return muted_flow_return
	end

	return func(params, ...)
end)

-- Events that the game plays itself, not as part of a weapon action. Venting the heat is one: the overcharge plays it.
mod:hook(PlayerUnitFirstPerson, "animation_event", function (func, self, event, ...)
	local template_name = utils.wielded_template_name(self.unit)
	local filter = template_name and mod.first_person_animation_filters[template_name]

	if filter and utils.is_local_player_unit(self.unit) and filter(event) then
		return
	end

	return func(self, event, ...)
end)

-- Runs before a character's first person view is taken down, when the character dies or the level ends. A weapon must let go of
-- whatever it linked to the view first.
--   mod.first_person_destroy_callbacks[name] = function (first_person_extension)
mod.first_person_destroy_callbacks = {}

mod:hook(PlayerUnitFirstPerson, "destroy", function (func, self, ...)
	for _, callback in pairs(mod.first_person_destroy_callbacks) do
		callback(self)
	end

	return func(self, ...)
end)

-- Runs just before the frame is drawn, after the game has updated everything. The game shows its own weapon and arm units again at
-- times of its own, and the mod's update runs too early to hide them again.
--   mod.pre_render_callbacks[name] = function ()
mod.pre_render_callbacks = {}

mod:hook_safe(StateIngame, "pre_render", function ()
	for _, callback in pairs(mod.pre_render_callbacks) do
		callback()
	end
end)

-- Drawing on the screen, after the game's own user interface has been updated. The user interface's renderer draws what is added to
-- its gui. The announcer's words and the Lightning Gun's scope are drawn this way.
--   mod.ingame_ui_post_update_callbacks[name] = function (ingame_ui) ... end
-- ingame_ui.ui_renderer.gui is the gui.
--   mod.ingame_ui_init_callbacks[name] = function (ingame_ui)
-- This runs when the in-game user interface is made, which is when a level starts. Its renderer is made then, and only knows the
-- materials that the mod had added to the renderers before that.
mod.ingame_ui_post_update_callbacks = {}
mod.ingame_ui_init_callbacks = {}

mod:hook_safe(IngameUI, "post_update", function (self)
	for _, callback in pairs(mod.ingame_ui_post_update_callbacks) do
		callback(self)
	end
end)

-- Runs when the character starts to hang off a ledge. The game plays the hanging animations, but a weapon's own stance animation is
-- still playing under them, so the weapon ends it. It gets the character's unit, and only runs for the player's own character.
--   mod.ledge_hang_callbacks[name] = function (unit)
mod.ledge_hang_callbacks = {}

mod:hook_safe(PlayerCharacterStateLedgeHanging, "on_enter", function (self)
	for _, callback in pairs(mod.ledge_hang_callbacks) do
		callback(self.unit)
	end
end)

-- The heat a weapon gets, by the overcharge type the game is adding (the id of the weapon's own value):
--   mod.overcharge_callbacks[type] = function (overcharge_extension, amount, charge_level)
--       Return the amount to add instead, or nil to add nothing.
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

-- The color of the overcharge bar, by the template of the weapon in the ranged slot. The game makes the bar orange between its thresholds
-- and red above them. A weapon can use its own color between them, and above them too:
--   mod.overcharge_bar_colors[template] = { color = { red, green, blue }, above_max = true or nil }
-- The game sets the bar's colors every frame after it works out the fraction, so this hook runs after that and changes them. The
-- overcharge is the ranged weapon's, so it is the weapon in the ranged slot that counts, whatever is in the player's hands.
mod.overcharge_bar_colors = {}

mod:hook_safe(OverchargeBarUI, "set_charge_bar_fraction", function (self, player, _, min_threshold_fraction, max_threshold_fraction)
	local unit = player.player_unit
	local inventory_extension = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "inventory_system")
	local slot_data = inventory_extension and inventory_extension:get_slot_data("slot_ranged")
	local item_data = slot_data and slot_data.item_data
	local bar_color = item_data and mod.overcharge_bar_colors[item_data.template]

	if not bar_color then
		return
	end

	local fraction = self.charge_bar.content.internal_gradient_threshold

	if fraction <= min_threshold_fraction or (fraction > max_threshold_fraction and not bar_color.above_max) then
		return
	end

	local style = self.charge_bar.style
	local color = bar_color.color

	for i = 1, 3 do
		style.bar_1.color[i + 1] = color[i]
		style.icon.color[i + 1] = color[i]
	end
end)

-- The mod framework only sends the mod's network messages to the players on its list of players that have the framework. When a
-- level loads, the game removes the players and adds them again, and the framework can take a player off its list after it put them
-- back. Then the mod's messages (the Shock Rifle's beam for the others, the Bio Rifle's goo from a client) go nowhere until the mod is
-- reloaded. So a moment after the last change of players, the framework is asked to ping everyone again. That puts the players back
-- on the list on both sides.
local FRAMEWORK_PING_DELAY = 1 -- seconds

local framework_ping_timer -- seconds until the framework is asked to ping, or nil when it is not waiting

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

-- Hit effects that do nothing. A weapon that draws its own impact adds an effect name here (mod.silent_hit_effects[name] = true) and
-- uses it as its action's hit_effect. The game needs a name there, and sends it to the other players as a number from a lookup table.
-- That table is full, and adding a name is an error, so these names can't be sent. The hooks below skip playing and sending them.
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

-- How bots shoot a weapon of the mod. The game's bot shooting (BTBotShootAction) is hooked once, here, because a function can be hooked
-- only once. The hook runs the callback of the weapon whose key is true in the weapon's attack_meta_data:
--   mod.bot_shot_callbacks[key] = function (func, action, shoot_blackboard, action_data, input_extension, t)
--       Fires the shot itself, or calls func(action, shoot_blackboard, action_data, input_extension, t) for the game's own shot.
--       shoot_blackboard.ut_unit is the bot.
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

-- The Bounty Hunter's talent "power level on clip size" (activate_buff_stacks_based_on_clip_size) adds one buff for each round of the
-- ranged weapon's clip, every frame, until there are as many as the clip holds. Its buff stops at 20 stacks, so with a bigger clip it
-- adds more every frame until the game runs out of buffs and stops. The mod's weapons keep all their ammo in the clip (the Assault
-- Rifle's 200, the Minigun's 300), so the talent is shown a clip of no more than its buff's own limit, which is all it can give.
mod:hook(BuffFunctionTemplates.functions, "activate_buff_stacks_based_on_clip_size", function (func, unit, buff, params, ...)
	local inventory_extension = Unit.alive(unit) and ScriptUnit.has_extension(unit, "inventory_system")
	local slot_data = inventory_extension and inventory_extension:get_slot_data("slot_ranged")
	local item_template = slot_data and BackendUtils.get_item_template(slot_data.item_data)
	local ammo_data = item_template and item_template.ammo_data
	local stack_template = buff.template and BuffUtils.get_buff_template(buff.template.buff_to_add)
	local limit = stack_template and stack_template.buffs and stack_template.buffs[1].max_stacks
	local clip = ammo_data and ammo_data.ammo_per_clip

	if not limit or not clip or clip <= limit then
		return func(unit, buff, params, ...)
	end

	ammo_data.ammo_per_clip = limit

	-- An error must not leave the clip changed
	local ok, error_message = pcall(func, unit, buff, params, ...)

	ammo_data.ammo_per_clip = clip

	if not ok then
		error(error_message, 0)
	end
end)
