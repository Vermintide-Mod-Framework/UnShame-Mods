local mod = get_mod("unreal_tournament")

-- Crafting the mod's weapons. The game's crafting is a request to the backend, whose cloud scripts make the weapon (or change it) and tell
-- the game what came of it: the new items, the items used up, the items changed (BackendInterfaceCraftingPlayfab.craft, and craft_request_cb
-- takes the answer into the inventory). The backend has no such weapons, so for a recipe that has one in it the mod makes the answer
-- itself, the way the cloud scripts do, and gives it to craft_request_cb: the crafting pages need nothing else.
--
-- The recipes done here: crafting a weapon from the blueprint, rerolling the properties or the traits of a weapon, upgrading its rarity, and
-- salvaging, which only discards the weapon: the materials a salvage gives would have to be added to the backend's amounts, which it does
-- not know (the page that shows what the salvage gave shows the materials it would give, with 0 of each). Applying and extracting skins
-- are not done.
--
-- What the weapons are made of is in the game's own data: the rarities that crafting gives and their weights (CraftingData), the properties
-- and traits a weapon of a rarity can have (WeaponProperties.combinations, WeaponTraits.combinations: the Chaos Wastes make and upgrade
-- weapons from the same, see DeusWeaponGeneration).
--
-- The weapon the player starts with (a blueprint, of rarity "default") is what the Craft page crafts new ones from. Crafting is paid with
-- the materials of the player's inventory, which are the backend's: the amount spent is kept by the mod (items.saved().spent) and taken
-- from the amounts the backend says, see items.lua.

local items = mod.items

local CONFIG = {
	-- The power level of a crafted weapon (the highest the game has)
	power_level = 300,
}

-- The rarities, from the lowest: what an upgrade goes through
local RARITIES = { "plentiful", "common", "rare", "exotic", "unique" }

local function next_rarity(rarity)
	for i, name in ipairs(RARITIES) do
		if name == rarity then
			return RARITIES[i + 1]
		end
	end
end

-- The combinations of properties and of traits that a weapon of a rarity can have (only exotic and unique weapons have a trait)
local function property_combinations(data, rarity)
	local by_rarity = WeaponProperties.combinations[data.property_table_name]

	return by_rarity and by_rarity[rarity] or {}
end

local function trait_combinations(data, rarity)
	if rarity ~= "exotic" and rarity ~= "unique" then
		return {}
	end

	return WeaponTraits.combinations[data.trait_table_name] or {}
end

local function contains_all(combination, names)
	for _, name in ipairs(names) do
		if not table.contains(combination, name) then
			return false
		end
	end

	return true
end

local function is_same_set(combination, names)
	return #combination == #names and contains_all(combination, names)
end

-- One of the combinations at random, out of the ones that are accepted (all of them when none is)
local function pick(combinations, accepts)
	local accepted = {}

	for _, combination in ipairs(combinations) do
		if accepts(combination) then
			accepted[#accepted + 1] = combination
		end
	end

	if #accepted == 0 then
		accepted = combinations
	end

	-- (none at all: a rarity that has no traits)
	return #accepted > 0 and accepted[math.random(#accepted)] or nil
end

-- The properties of a combination, with the strengths: 1 for a unique weapon, the ones that are kept as they were, any from 0.01 to 1 for the others
local function properties_of(combination, rarity, kept)
	local properties = {}

	for _, name in ipairs(combination or {}) do
		properties[name] = rarity == "unique" and 1 or kept and kept[name] or math.random(1, 100) / 100
	end

	return properties
end

local function copy_of(combination)
	local names = {}

	for _, name in ipairs(combination or {}) do
		names[#names + 1] = name
	end

	return names
end

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

-- The records of the weapons (see items.lua) a recipe makes: from nothing, from a weapon with its properties made again, its traits, its rarity
-- made the next one
local function new_record(key)
	local data = ItemMasterList[key]
	local rarity = roll_rarity()

	return {
		key = key,
		power_level = CONFIG.power_level,
		properties = properties_of(pick(property_combinations(data, rarity), function () return true end), rarity),
		rarity = rarity,
		traits = copy_of(pick(trait_combinations(data, rarity), function () return true end)),
	}
end

local function rerolled_properties(record)
	local data = ItemMasterList[record.key]
	local names = table.keys(record.properties)
	local combination = pick(property_combinations(data, record.rarity), function (candidate)
		return not is_same_set(candidate, names)
	end)

	return {
		key = record.key,
		power_level = record.power_level,
		properties = properties_of(combination, record.rarity),
		rarity = record.rarity,
		traits = record.traits,
	}
end

local function rerolled_traits(record)
	local data = ItemMasterList[record.key]
	local combination = pick(trait_combinations(data, record.rarity), function (candidate)
		return not is_same_set(candidate, record.traits)
	end)

	return {
		key = record.key,
		power_level = record.power_level,
		properties = record.properties,
		rarity = record.rarity,
		traits = copy_of(combination),
	}
end

local function upgraded(record)
	local data = ItemMasterList[record.key]
	local rarity = next_rarity(record.rarity)
	local names = table.keys(record.properties)
	local property_combination = pick(property_combinations(data, rarity), function (candidate)
		return contains_all(candidate, names)
	end)
	local trait_combination = pick(trait_combinations(data, rarity), function (candidate)
		return contains_all(candidate, record.traits)
	end)

	return {
		key = record.key,
		power_level = record.power_level,
		properties = properties_of(property_combination, rarity, record.properties),
		rarity = rarity,
		traits = copy_of(trait_combination),
	}
end

-- What each recipe makes of the record of the weapon in it (nil for the blueprint, which is crafted from and has no record)
local CHANGES = {
	reroll_weapon_properties = rerolled_properties,
	reroll_weapon_traits = rerolled_traits,
	upgrade_item_rarity_common = upgraded,
	upgrade_item_rarity_rare = upgraded,
	upgrade_item_rarity_exotic = upgraded,
	upgrade_item_rarity_unique = upgraded,
}

-- The materials of a recipe are spent (what is left of a material is the answer's, what the backend still has of it is kept by the mod, see
-- items.lua): gives the items used up, the backend id of the weapon in the recipe and what is saved
local function spend_materials(ingredients)
	local inventory = Managers.backend._backend_mirror._inventory_items
	local saved = items.saved()
	local consumed_items = {}
	local weapon_id

	for _, ingredient in ipairs(ingredients) do
		local item = inventory[ingredient.backend_id]

		if item.UtCustom then
			weapon_id = ingredient.backend_id
		else
			saved.spent[item.key] = (saved.spent[item.key] or 0) + ingredient.amount
			consumed_items[#consumed_items + 1] = {
				ItemInstanceId = ingredient.backend_id,
				RemainingUses = item.RemainingUses - ingredient.amount,
			}
		end
	end

	return consumed_items, weapon_id, saved
end

-- The answer to a salvage of crafted weapons: they are gone and give nothing, the page shows the materials they would have given as 0 (the
-- items of the inventory that are the stacks of them, as changed by 0)
local function discard(ingredients)
	local inventory = Managers.backend._backend_mirror._inventory_items
	local saved = items.saved()
	local consumed_items = {}
	local materials = {}
	local modified_items = {}

	for _, ingredient in ipairs(ingredients) do
		local record = saved.crafted[ingredient.backend_id]

		consumed_items[#consumed_items + 1] = {
			ItemInstanceId = ingredient.backend_id,
			RemainingUses = 0,
		}

		for _, material in ipairs(CraftingData.salvage_data.materials_from_rarity[record.rarity] or {}) do
			materials[material.name] = true
		end

		saved.crafted[ingredient.backend_id] = nil
	end

	for _, item in pairs(inventory) do
		if item.data and item.data.item_type == "crafting_material" and materials[item.key] then
			local unchanged = {}

			for field, value in pairs(item) do
				unchanged[field] = value
			end

			unchanged.UsesIncrementedBy = 0
			modified_items[#modified_items + 1] = unchanged
		end
	end

	items.save(saved)

	return {
		consumed_items = consumed_items,
		modified_items = modified_items,
	}
end

-- The answer of the backend to a recipe that has one of the mod's weapons in it
local function answer_to(recipe, ingredients)
	if recipe.name == "salvage" then
		return discard(ingredients)
	end

	local consumed_items, weapon_id, saved = spend_materials(ingredients)
	local change = CHANGES[recipe.name]

	if not change then
		local blueprint_key = Managers.backend._backend_mirror._inventory_items[weapon_id].key
		local _, new_item = items.new_crafted(saved, blueprint_key, new_record(blueprint_key))

		items.save(saved)

		return {
			consumed_items = consumed_items,
			items = { new_item },
		}
	end

	local record = saved.crafted[weapon_id]

	return {
		consumed_items = consumed_items,
		modified_items = { items.change_crafted(saved, weapon_id, change(record)) },
	}
end

-- (set while the mod gives an answer of its own to craft_request_cb)
local answering = false

mod:hook(BackendInterfaceCraftingPlayfab, "craft", function (func, self, career_name, item_backend_ids, recipe_override)
	local recipe, ingredients = self:_get_valid_recipe(item_backend_ids, recipe_override)
	local has_custom_item = false

	for _, ingredient in ipairs(ingredients or {}) do
		has_custom_item = has_custom_item or items.is_custom(ingredient.backend_id)
	end

	if not has_custom_item then
		return func(self, career_name, item_backend_ids, recipe_override)
	end

	if recipe.name == "salvage" then
		local saved = items.saved()

		for _, ingredient in ipairs(ingredients) do
			if not saved.crafted[ingredient.backend_id] then
				mod:echo("The Unreal Tournament weapons you have crafted are salvaged apart from other items, and the blueprint cannot be")

				return nil
			end
		end
	elseif recipe.name ~= "craft_weapon" and not CHANGES[recipe.name] then
		mod:echo("The Unreal Tournament weapons cannot have skins applied or extracted")

		return nil
	end

	local id = self:_new_id()
	local answer = { FunctionResult = answer_to(recipe, ingredients) }

	answering = true

	local ok, error_message = pcall(self.craft_request_cb, self, id, answer)

	answering = false

	if not ok then
		error(error_message, 0)
	end

	return id, recipe
end)

-- A recipe of the backend's own used materials that the mod has taken some of: what is left of them is what the backend says, less what the
-- mod has spent
mod:hook_safe(BackendInterfaceCraftingPlayfab, "craft_request_cb", function (self, id, result)
	if answering then
		return
	end

	local used = {}

	for _, item in ipairs(result.FunctionResult.consumed_items or {}) do
		used[#used + 1] = item.ItemInstanceId
	end

	items.apply_spent(used)
end)
