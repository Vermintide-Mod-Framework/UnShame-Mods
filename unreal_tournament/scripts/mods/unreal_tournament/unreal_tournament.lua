local mod = get_mod("unreal_tournament")

-- What the weapons have running that belongs to a level (effects, units, worlds) is cleared when the
-- level is left: the game tells the mods before it takes the level's world down, calling something on a world
-- that is gone crashes the game and no pcall catches that. The files add their functions to this.
mod.level_exit_callbacks = {}

mod.on_game_state_changed = function (status, state_name)
	if status == "exit" and state_name == "StateIngame" then
		for _, callback in ipairs(mod.level_exit_callbacks) do
			callback()
		end
	end
end

-- The charge actions of the weapons that are patched (the Bio Rifle's charge, the Link Gun's beam) are told about
-- every frame they are held, by name: a function can be hooked once. The action says which callback in
-- ut_charge_callback.
mod.charge_update_callbacks = {}

mod:hook_safe(ActionCharge, "client_owner_post_update", function (self, dt, t, world)
	local action = self.current_action
	local callback = action and action.ut_charge_callback and mod.charge_update_callbacks[action.ut_charge_callback]

	if callback then
		callback(self, dt, t, world)
	end
end)

-- What the weapons do when they are wielded (their default stance), by name: a function can be hooked once. Each
-- is called with what the game gives _wield_slot and looks at the weapon itself. Only for the player's own
-- character: the bots and the other players wield weapons through the same function, and what the weapons do
-- here is with the player's own first person view.
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

mod:dofile("scripts/mods/unreal_tournament/shock_rifle")
mod:dofile("scripts/mods/unreal_tournament/flak_cannon")
mod:dofile("scripts/mods/unreal_tournament/rocket_launcher")
mod:dofile("scripts/mods/unreal_tournament/bio_rifle")
mod:dofile("scripts/mods/unreal_tournament/link_gun")
mod:dofile("scripts/mods/unreal_tournament/movement")
mod:dofile("scripts/mods/unreal_tournament/pickups")
mod:dofile("scripts/mods/unreal_tournament/gameplay")
