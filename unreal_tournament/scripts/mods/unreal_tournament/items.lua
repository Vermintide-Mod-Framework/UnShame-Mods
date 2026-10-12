local mod = get_mod("unreal_tournament")

-- The weapons as items of their own: each is a copy of a game weapon (its template and its item), with a name of its own, in every
-- player's inventory and usable by every career. The game's weapon is left as it is.
--
--   items.register(setting_id, { key, template, base_item, name, type_name, description, keywords, texts, icon, icon_package, icon_materials })
--     key: the item's name (damage sources, the loadout and the other peers know the item by it), template: the weapon template's name,
--     base_item: the game's item that is copied (its models and skins are the copy's), name, type_name (the kind of weapon, "Beam Staff"
--     for the game's), description, keywords (the green line: localization ids), texts ({ id = text } for the ids that are the mod's),
--     icon: shown in the inventory, the name of a material of the file icon_materials, which is in the package icon_package (a package
--     of its own, listed in the mod's file, see hold_package)
--
-- The game takes the inventory from the backend (PlayFab), which does not have these items: they are put into the inventory it has loaded,
-- under ids that are the same every time (the item's key for the weapon the player starts with, a blueprint, and key#number for the
-- weapons the player has crafted, see crafting.lua), so that the loadout that has one equipped finds it again.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")

local items = {}

local definitions = {}

-- The text of the names and descriptions: the game's localization has no entry for them
local texts = {}

mod:hook(LocalizationManager, "_base_lookup", function (func, self, text_id)
	return texts[text_id] or func(self, text_id)
end)

-- The package of the icons is one of the packages the mod's file lists, which the game loads through the mod (a mod's packages are not
-- known to Managers.package). The UI's renderers hold the materials of it locked, and the game fails when a package with a locked resource
-- is unloaded, as the mod's packages are when the mod is reloaded: so the mod holds a handle of its own to the package, which is never
-- released (kept in a global, to be found again after a reload).
local function hold_package(package_name)
	UT_HELD_PACKAGES = UT_HELD_PACKAGES or {}

	if UT_HELD_PACKAGES[package_name] then
		return
	end

	local handle = Mod.resource_package(Managers.mod:currently_loading_mod().handle, package_name)

	ResourcePackage.load(handle)
	ResourcePackage.flush(handle)

	UT_HELD_PACKAGES[package_name] = handle
end

-- The materials the UI's renderers are made with, besides the game's own (the game's UIRenderer.create adds these to every renderer made
-- after this: the ones that exist already do not have them)
local function add_material_set(material_set)
	if not table.contains(UIRenderer._injected_material_sets, material_set) then
		table.insert(UIRenderer._injected_material_sets, material_set)
	end
end

-- The items whose icon is not used yet: the renderer of the UI that is there was made without it
local icons_waiting = {}

mod:hook_safe(IngameUI, "init", function ()
	for key in pairs(icons_waiting) do
		ItemMasterList[key].inventory_icon = definitions[key].icon
	end

	table.clear(icons_waiting)
end)

-- Every career of the game: the copy is not for the ones the game's weapon is for
local function all_careers()
	local careers = {}

	for career_name, settings in pairs(CareerSettings) do
		if settings.playfab_name then
			careers[#careers + 1] = career_name
		end
	end

	table.sort(careers)

	return careers
end

-- What the mod keeps of its own, between games (the settings file of the mod: the backend is not asked and does not know):
--   crafted: { [backend id] = record } the weapons the player has crafted, a record being { key, rarity, power_level, properties, traits }
--   spent: { [material's key] = amount } the crafting materials spent on them, which the backend still has
--   next_id: the number of the next crafted weapon
local SAVED_SETTING = "custom_items"

function items.saved()
	return table.clone(mod:get(SAVED_SETTING) or { crafted = {}, spent = {}, next_id = 1 })
end

function items.save(saved)
	mod:set(SAVED_SETTING, saved)
end

-- The weapon that is in the inventory from the start, and what the Craft page makes new ones from: its rarity is the one that the page's
-- items to craft with have, "default", and its power level the game's own for them
local BLUEPRINT_RECORD = {
	power_level = 5,
	properties = {},
	rarity = "default",
	traits = {},
}

-- The inventory item of a weapon, as the backend's inventory has them
local function inventory_item(key, backend_id, record)
	local custom_data = {
		power_level = tostring(record.power_level),
		rarity = record.rarity,
	}

	if next(record.properties) then
		custom_data.properties = cjson.encode(record.properties)
	end

	if #record.traits > 0 then
		custom_data.traits = cjson.encode(record.traits)
	end

	return {
		CustomData = custom_data,
		ItemId = key,
		ItemInstanceId = backend_id,
		-- (what tells these from the backend's items)
		UtCustom = true,
	}
end

-- The mirror of the backend (the game's copy of the player's inventory)
local function mirror_of_backend()
	return Managers.backend and Managers.backend._backend_mirror
end

-- If an item of the inventory is one of the mod's weapons
function items.is_custom(backend_id)
	local mirror = mirror_of_backend()
	local item = mirror and mirror._inventory_items and mirror._inventory_items[backend_id]

	return item ~= nil and item.UtCustom == true
end

-- A weapon made new for the player: gives its backend id and the inventory item (it is not in the inventory yet: the game's craft does that)
function items.new_crafted(saved, key, record)
	local backend_id = string.format("%s#%d", key, saved.next_id)

	saved.next_id = saved.next_id + 1
	saved.crafted[backend_id] = table.clone(record)
	saved.crafted[backend_id].key = key

	return backend_id, inventory_item(key, backend_id, record)
end

-- A weapon the player has changed (its properties, traits or rarity): gives the inventory item of it, which is to take the place of the old one
function items.change_crafted(saved, backend_id, record)
	local key = saved.crafted[backend_id].key

	saved.crafted[backend_id] = table.clone(record)
	saved.crafted[backend_id].key = key

	items.save(saved)

	return inventory_item(key, backend_id, record)
end

-- The materials of the inventory have the amounts the backend has, less what the mod has spent of them (the amount the backend has is
-- kept in the item, for when the mod spends more)
local function take_spent_from_materials(inventory, saved)
	for backend_id, item in pairs(inventory) do
		local data = item.data

		if data and data.item_type == "crafting_material" and item.RemainingUses then
			local owned = item.UtOwned or item.RemainingUses
			local spent = saved.spent[data.key] or 0

			-- (the backend has fewer of them than were spent: they were used elsewhere, the rest of the spending is not owed)
			if spent > owned then
				spent = owned
				saved.spent[data.key] = owned
			end

			item.UtOwned = owned
			item.RemainingUses = owned - spent

			if item.RemainingUses <= 0 then
				inventory[backend_id] = nil
			end
		end
	end
end

-- The materials of the inventory after the backend has used some of them (the ids): the amounts are the backend's now, the mod's spending is
-- taken from them again
function items.apply_spent(used_ids)
	local inventory = mirror_of_backend()._inventory_items
	local saved = items.saved()

	for _, backend_id in ipairs(used_ids) do
		if inventory[backend_id] then
			inventory[backend_id].UtOwned = nil
		end
	end

	take_spent_from_materials(inventory, saved)
	items.save(saved)
end

-- Puts the mod's weapons into the inventory that the mirror of the backend has loaded
local function add_to_inventory(mirror)
	local inventory = mirror._inventory_items

	if not inventory then
		return
	end

	local saved = items.saved()

	for _, definition in pairs(definitions) do
		local item = inventory_item(definition.key, definition.key, BLUEPRINT_RECORD)

		mirror:_update_data(item, definition.key)

		inventory[definition.key] = item
	end

	for backend_id, record in pairs(saved.crafted) do
		if definitions[record.key] then
			local item = inventory_item(record.key, backend_id, record)

			mirror:_update_data(item, backend_id)

			inventory[backend_id] = item
		end
	end

	take_spent_from_materials(inventory, saved)
	items.save(saved)
end

-- (the mirror the game uses is PlayFabMirrorAdventure: a class gets a copy of its parent's functions when it is made, so the base class's
-- function is not the one that runs)
mod:hook_safe(PlayFabMirrorAdventure, "inventory_request_cb", function (self)
	add_to_inventory(self)
end)

-- The definitions of the registered weapons, by the weapon's setting (items.weapons.shock_rifle.template is the Shock Rifle's template)
items.weapons = {}

function items.register(setting_id, definition)
	items.weapons[setting_id] = definition

	local base_template = rawget(Weapons, ItemMasterList[definition.base_item].template)
	local template = table.clone(base_template)
	local item = table.clone(ItemMasterList[definition.base_item])

	-- (the actions say which template they are of: the game tells the other peers which action a projectile came from by it)
	utils.set_actions_lookup_data(template.actions, definition.template)

	-- (the game gives every template its name when it loads them: the skins ask the template which weapon it is by it)
	template.name = definition.template

	Weapons[definition.template] = template

	item.template = definition.template
	item.display_name = definition.key .. "_name"
	item.description = definition.key .. "_description"
	-- (the kind of weapon, under the name in the inventory: the game's items say it by their item type)
	item.item_type = definition.key .. "_type"
	item.can_wield = all_careers()
	-- (what the game's parse_item_master_list makes of every item)
	item.key = definition.key
	item.name = definition.key
	item.localized_name = definition.name

	texts[item.display_name] = definition.name
	texts[item.description] = definition.description
	texts[item.item_type] = definition.type_name

	-- (the green line under the power: localization ids, the game's own or ones of texts)
	template.tooltip_keywords = definition.keywords

	for text_id, text in pairs(definition.texts or {}) do
		texts[text_id] = text
	end

	-- (the icon is a texture of its own, not one of the game's atlases: drawn by its material's name, which the UI's renderers have to be given.
	-- The in-game UI's renderer is made when a level is loaded, so when the mod is loaded in a level the item keeps the icon of the game's
	-- item until the next one)
	UIAtlasHelper.add_standalone_texture_by_name(definition.icon)
	hold_package(definition.icon_package)
	add_material_set(definition.icon_materials)

	if Managers.ui and Managers.ui._ingame_ui then
		icons_waiting[definition.key] = true
	else
		item.inventory_icon = definition.icon
	end

	ItemMasterList[definition.key] = item

	utils.register_network_lookup("item_template_names", definition.template)
	utils.register_network_lookup("item_names", definition.key)
	utils.register_network_lookup("damage_sources", definition.key)

	definitions[definition.key] = definition

	-- (the inventory that is already loaded, when the mod is loaded while playing)
	local backend = Managers.backend
	local mirror = backend and backend._backend_mirror

	if mirror then
		add_to_inventory(mirror)

		backend:get_interface("items"):make_dirty()
	end
end

return items
