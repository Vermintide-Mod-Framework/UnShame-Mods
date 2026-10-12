local mod = get_mod("unreal_tournament")

-- Crafting the mod's weapons. The game's crafting is a request to the backend, whose cloud scripts make the weapon (or change it) and tell
-- the game what came of it: the new items, the items used up, the items changed (BackendInterfaceCraftingPlayfab.craft, and craft_request_cb
-- takes the answer into the inventory). The backend has no such weapons, so for a recipe that has one in it the mod makes the answer
-- itself, the way the cloud scripts do, and gives it to craft_request_cb: the crafting pages need nothing else.
--
-- What the mod's weapons are made of is in the game's own data: the rarities that crafting gives and their weights (CraftingData), the
-- properties and traits a weapon of a rarity can have (WeaponProperties.combinations, WeaponTraits.combinations: the Chaos Wastes make
-- weapons from the same).
--
-- The weapon the player starts with (a blueprint, of rarity "default") is what the Craft page crafts new ones from. Crafting is paid with
-- the materials of the player's inventory, which are the backend's: the amount spent is kept by the mod (items.saved().spent) and taken
-- from the amounts the backend says, see items.lua.

local items = mod.items

local CONFIG = {
	-- The power level of a crafted weapon (the highest the game has)
	power_level = 300,
}

-- A rarity at random, by the weights of the game's crafting of weapons
local function roll_rarity()
	local weights = CraftingData.craft_weapon_data.rarity_weights
	local total = 0

	for _, weight in pairs(weights) do
		total = total + weight
	end

	local roll = math.random() * total

	-- (sorted: the order of the weights in a table is not fixed)
	local rarities = table.keys(weights)

	table.sort(rarities)

	for _, rarity in ipairs(rarities) do
		roll = roll - weights[rarity]

		if roll <= 0 then
			return rarity
		end
	end

	return rarities[#rarities]
end

-- The record of a weapon of a rarity: properties and traits at random out of the combinations the game has for the rarity of an item of its
-- kind (the strength of a property is anywhere from 0.01 to 1, 1 for a unique weapon)
local function roll_record(key, rarity)
	local data = ItemMasterList[key]
	local record = {
		power_level = CONFIG.power_level,
		properties = {},
		rarity = rarity,
		traits = {},
	}
	local property_combinations = WeaponProperties.combinations[data.property_table_name]
	local combinations = property_combinations and property_combinations[rarity]

	if combinations and #combinations > 0 then
		for _, property in ipairs(combinations[math.random(#combinations)]) do
			record.properties[property] = rarity == "unique" and 1 or math.random(1, 100) / 100
		end
	end

	-- (only exotic and unique weapons have a trait)
	if rarity == "exotic" or rarity == "unique" then
		local trait_combinations = WeaponTraits.combinations[data.trait_table_name]

		if trait_combinations and #trait_combinations > 0 then
			for _, trait in ipairs(trait_combinations[math.random(#trait_combinations)]) do
				record.traits[#record.traits + 1] = trait
			end
		end
	end

	return record
end

-- The answer of the backend to the crafting of a weapon from the blueprint: the new weapon, and the materials used up
local function craft_weapon(ingredients)
	local inventory = Managers.backend._backend_mirror._inventory_items
	local saved = items.saved()
	local consumed_items = {}
	local blueprint_key

	for _, ingredient in ipairs(ingredients) do
		local item = inventory[ingredient.backend_id]

		if item.UtCustom then
			blueprint_key = item.key
		else
			-- (what the backend still has of the material is kept by the mod, see items.lua)
			saved.spent[item.key] = (saved.spent[item.key] or 0) + ingredient.amount
			consumed_items[#consumed_items + 1] = {
				ItemInstanceId = ingredient.backend_id,
				RemainingUses = item.RemainingUses - ingredient.amount,
			}
		end
	end

	local _, new_item = items.new_crafted(saved, blueprint_key, roll_record(blueprint_key, roll_rarity()))

	items.save(saved)

	return {
		consumed_items = consumed_items,
		items = { new_item },
	}
end

mod:hook(BackendInterfaceCraftingPlayfab, "craft", function (func, self, career_name, item_backend_ids, recipe_override)
	local recipe, ingredients = self:_get_valid_recipe(item_backend_ids, recipe_override)
	local has_custom_item = false

	for _, ingredient in ipairs(ingredients or {}) do
		has_custom_item = has_custom_item or items.is_custom(ingredient.backend_id)
	end

	if not has_custom_item then
		return func(self, career_name, item_backend_ids, recipe_override)
	end

	if recipe.name ~= "craft_weapon" then
		mod:echo("The Unreal Tournament weapons can only be crafted so far, not changed or salvaged")

		return nil
	end

	local id = self:_new_id()

	self:craft_request_cb(id, {
		FunctionResult = craft_weapon(ingredients),
	})

	return id, recipe
end)
