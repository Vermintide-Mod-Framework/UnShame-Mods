local mod = get_mod("unreal_tournament")

-- Crafting the mod's weapons. The game's crafting is a request to the backend, whose cloud scripts make the weapon (or change it) and tell
-- the game what came of it: the new items, the items used up, the items changed (BackendInterfaceCraftingPlayfab.craft, and craft_request_cb
-- takes the answer into the inventory). The backend has no such weapons (and a request of a game with mods is refused by it, which ends the
-- game), so for a recipe that has one in it the mod makes the answer itself, the way the cloud scripts do, and gives it to craft_request_cb:
-- the crafting pages need nothing else, but what they show of the materials (see the end of this file).
--
-- The recipes done here: crafting a weapon from the blueprint, rerolling the properties or the traits of a weapon, upgrading its rarity, and
-- salvaging. They cost nothing and give nothing (the materials are the backend's, which is not asked): a salvage only discards the weapon,
-- and the page that shows what it gave shows the materials it would give, with 0 of each. Applying and extracting skins are not done.
--
-- What the weapons are made of is in the game's own data: the rarities that crafting gives and their weights (CraftingData), the properties
-- and traits a weapon of a rarity can have (WeaponProperties.combinations, WeaponTraits.combinations: the Chaos Wastes make and upgrade
-- weapons from the same, see DeusWeaponGeneration).
--
-- The weapon the player starts with (a blueprint, of rarity "default") is what the Craft page crafts new ones from.

local items = mod.items

local CONFIG = {
	-- The power level of a crafted weapon (the highest the game has)
	power_level = 300,
	-- Seconds before the game is told that a craft of the mod's is complete: the backend takes a while to answer, and the screens do things
	-- while they wait (the window of an item fades its view out for 0.3 seconds when a craft starts and in when it is complete, both with the
	-- same value: an answer at once has the one fade the other)
	craft_delay = 0.5,
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

-- The answer to a salvage of crafted weapons (their backend ids): they are gone and give nothing, the page shows the materials they would have
-- given as 0 (the items of the inventory that are the stacks of them, as changed by 0)
local function discard(weapon_ids)
	local inventory = Managers.backend._backend_mirror._inventory_items
	local saved = items.saved()
	local consumed_items = {}
	local materials = {}
	local modified_items = {}

	for _, weapon_id in ipairs(weapon_ids) do
		local record = saved.crafted[weapon_id]

		consumed_items[#consumed_items + 1] = {
			ItemInstanceId = weapon_id,
			RemainingUses = 0,
		}

		for _, material in ipairs(CraftingData.salvage_data.materials_from_rarity[record.rarity] or {}) do
			materials[material.name] = true
		end

		saved.crafted[weapon_id] = nil
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

-- The answer to a recipe that has the mod's weapons (their backend ids) in it: nothing is spent
local function answer_to(recipe_name, weapon_ids)
	if recipe_name == "salvage" then
		return discard(weapon_ids)
	end

	local saved = items.saved()
	local weapon_id = weapon_ids[1]
	local change = CHANGES[recipe_name]

	if not change then
		local blueprint_key = Managers.backend._backend_mirror._inventory_items[weapon_id].key
		local _, new_item = items.new_crafted(saved, blueprint_key, new_record(blueprint_key))

		items.save(saved)

		return { items = { new_item } }
	end

	return { modified_items = { items.change_crafted(saved, weapon_id, change(saved.crafted[weapon_id])) } }
end

-- When each craft of the mod's is to be told complete: [craft id] = time
local complete_at = {}

-- (the pages ask again every frame the button is held down: a message is told every few seconds)
local MESSAGE_INTERVAL = 3
local last_message_t = -math.huge

local function tell(message)
	local t = Managers.time:time("main")

	if t - last_message_t >= MESSAGE_INTERVAL then
		last_message_t = t

		mod:echo(message)
	end
end

-- The recipe is the one the page says; the Craft page does not say, it crafts (from a blueprint). The materials the page may have put in are
-- not used: the recipes of the mod's weapons have none.
local function craft(func, self, career_name, item_backend_ids, recipe_override)
	local weapon_ids = {}

	for _, backend_id in ipairs(item_backend_ids) do
		if items.is_custom(backend_id) then
			weapon_ids[#weapon_ids + 1] = backend_id
		end
	end

	if #weapon_ids == 0 then
		return func(self, career_name, item_backend_ids, recipe_override)
	end

	local recipe_name = recipe_override or "craft_weapon"
	local saved = items.saved()

	if recipe_name == "salvage" then
		for _, weapon_id in ipairs(weapon_ids) do
			if not saved.crafted[weapon_id] then
				tell("The Unreal Tournament weapon you start with, the blueprint, cannot be salvaged")

				return nil
			end
		end

		if #weapon_ids ~= #item_backend_ids then
			tell("The Unreal Tournament weapons you have crafted are salvaged apart from other items")

			return nil
		end
	elseif recipe_name == "craft_weapon" then
		if saved.crafted[weapon_ids[1]] then
			tell("An Unreal Tournament weapon is crafted from the weapon you start with, the blueprint")

			return nil
		end
	elseif CHANGES[recipe_name] then
		if not saved.crafted[weapon_ids[1]] then
			tell("The Unreal Tournament weapon you start with, the blueprint, cannot be changed: craft one")

			return nil
		end
	else
		tell("The Unreal Tournament weapons cannot have skins applied or extracted")

		return nil
	end

	local id = self:_new_id()

	self:craft_request_cb(id, { FunctionResult = answer_to(recipe_name, weapon_ids) })

	complete_at[id] = Managers.time:time("main") + CONFIG.craft_delay

	return id, self:get_recipe_by_name(recipe_name)
end

local function is_craft_complete(func, self, id)
	local at = complete_at[id]

	if at then
		if Managers.time:time("main") < at then
			return false
		end

		complete_at[id] = nil
	end

	return func(self, id)
end

-- (hooked when all the mods are loaded: the hook that is made last is the first to be called, and the mod's has to get the crafts of its
-- weapons before another mod's hook of the same function, the Casual mod's, which stops a craft of an item that is not its own)
mod.all_mods_loaded_callbacks[#mod.all_mods_loaded_callbacks + 1] = function ()
	mod:hook(BackendInterfaceCraftingPlayfab, "craft", craft)
	mod:hook(BackendInterfaceCraftingPlayfab, "is_craft_complete", is_craft_complete)
end

-- The crafting pages (the console ones, which is what the game's inventory uses) show what a recipe needs of the materials (what the player
-- has / what it takes), and let the player craft when they have it: for one of the mod's weapons it takes none, so they show what the player
-- has / 0 and the player can craft
local PAGES = {
	"CraftPageCraftItemConsole",
	"CraftPageRollPropertiesConsole",
	"CraftPageRollTraitConsole",
	"CraftPageUpgradeItemConsole",
}

for _, page_name in ipairs(PAGES) do
	mod:hook_safe(_G[page_name], "setup_recipe_requirements", function (self)
		local weapon_id = self._craft_items[1]

		if not weapon_id or not items.is_custom(weapon_id) then
			return
		end

		for i = 1, #UISettings.crafting_material_order do
			local content = self._widgets_by_name["material_text_" .. i].content

			if content.visible then
				content.text = (string.gsub(content.text, "/.*$", "/0"))
				content.warning = false
			end
		end

		table.clear(self._material_items)

		self._has_all_requirements = true

		if (self._num_craft_items or 0) > 0 then
			self:_set_craft_button_disabled(false)
		end
	end)
end

-- The window of an item (HeroWindowItemCustomization: the page of the equipment screen that shows an item and upgrades or rerolls it) does the
-- same from the item. The game turns the crafting off there in the modded realm (GameSettingsDevelopment.read_only_backend, which is set as
-- the backend is not written to): for the mod's weapons, which the backend is not asked about, it is on, as the window sets its button
local function writable_backend(func, self, ...)
	if not items.is_custom(self._item_backend_id) then
		return func(self, ...)
	end

	local read_only_backend = GameSettingsDevelopment.read_only_backend

	GameSettingsDevelopment.read_only_backend = false

	local ok, result = pcall(func, self, ...)

	GameSettingsDevelopment.read_only_backend = read_only_backend

	if not ok then
		error(result, 0)
	end

	return result
end

mod:hook(HeroWindowItemCustomization, "_enable_craft_button", writable_backend)
mod:hook(HeroWindowItemCustomization, "_update_state_craft_button", writable_backend)

-- (and what the window shows of the materials, which the recipe does not need)
mod:hook(HeroWindowItemCustomization, "_create_material_requirement_widgets", function (func, self, recipe_name)
	local has_all_requirements, width = func(self, recipe_name)

	if not items.is_custom(self._item_backend_id) then
		return has_all_requirements, width
	end

	for _, widget in ipairs(self._material_widgets) do
		widget.content.text = (string.gsub(widget.content.text, "/.*$", "/0"))
		widget.content.warning = false
	end

	table.clear(self._material_items)

	return true, width
end)

-- The pages of the rerolls do not set the requirements again when a weapon is put in or taken out (only when they are entered and after a
-- craft), so what they show is of the weapon that was in before: they are set again for every weapon, so that the ones of the mod's weapons
-- do not stay when another is put in
for _, page_name in ipairs({ "CraftPageRollPropertiesConsole", "CraftPageRollTraitConsole" }) do
	for _, function_name in ipairs({ "_add_craft_item", "_remove_craft_item" }) do
		mod:hook_safe(_G[page_name], function_name, function (self)
			self:setup_recipe_requirements()
		end)
	end
end
