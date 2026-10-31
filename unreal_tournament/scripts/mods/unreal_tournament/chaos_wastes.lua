local mod = get_mod("unreal_tournament")

-- Chaos Wastes. With the reliquary_ut_weapons option, a Reliquary (the chest that swaps a weapon for Pilgrim's Coins) only gives the
-- mod's weapons. The game rolls a Reliquary's weapon from the player's pool of weapons (DeusWeaponGeneration.generate_weapon, which only
-- the Reliquary calls), and this rolls it from the mod's weapons in that pool. A weapon the player already got from a Reliquary is left out
-- of the pool, as the game does. Once all of the mod's weapons for a slot have been left out, they are all in it again, as the game does
-- for its own when a slot runs out. A career that has none of the mod's weapons for the slot gets the game's.

local items = mod.items

-- The mod's weapons of a rarity of a pool, for the slots the Reliquary can give
local function mod_weapons(weapon_groups, slots)
	local found = {}
	local any = false

	for group_name, weapon_key in pairs(weapon_groups or {}) do
		local group = DeusWeaponGroups[group_name]

		if group and slots[group.slot_type] and items.is_registered(group_name) then
			found[group_name] = weapon_key
			any = true
		end
	end

	return any and found or nil
end

-- The game loads the file of the roll with the Reliquary's code, which may not be loaded yet. It is loaded here so that it can be hooked.
-- require keeps it loaded, so the game does not load it again. It needs the Chaos Wastes' weapons (DeusWeapons), which only exist with
-- the DLC.
if rawget(_G, "DeusWeapons") then
	require("scripts/managers/game_mode/mechanisms/deus_weapon_generation")

	mod:hook(DeusWeaponGeneration, "generate_weapon", function (func, difficulty, run_progress, rarity, seed, weapon_pool, slot_chance_melee, slot_chance_ranged)
		local mechanism = Managers.mechanism and Managers.mechanism:game_mechanism()
		local controller = mechanism and mechanism.get_deus_run_controller and mechanism:get_deus_run_controller()

		if not mod.option("reliquary_ut_weapons") or not controller or not weapon_pool[rarity] then
			return func(difficulty, run_progress, rarity, seed, weapon_pool, slot_chance_melee, slot_chance_ranged)
		end

		local slots = {
			melee = slot_chance_melee > 0,
			ranged = slot_chance_ranged > 0,
		}
		local found = mod_weapons(weapon_pool[rarity], slots) or mod_weapons(controller:get_base_weapon_pool()[rarity], slots)

		if found then
			weapon_pool = table.clone(weapon_pool)
			weapon_pool[rarity] = found
		end

		return func(difficulty, run_progress, rarity, seed, weapon_pool, slot_chance_melee, slot_chance_ranged)
	end)
end
