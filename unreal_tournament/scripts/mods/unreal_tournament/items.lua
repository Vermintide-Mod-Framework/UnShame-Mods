local mod = get_mod("unreal_tournament")

-- The mod's weapons as items of their own: each is a copy of a game weapon (template and item) with its own name, usable by the careers of that weapon.
-- The game's weapon is left unchanged.
--
--   items.register(setting_id, { key, template, base_item, deus_copy, name, type_name, description, keywords, texts, icon, icon_package, icon_materials })
--     key: the item's name, also used for damage sources, loadouts and the network
--     template: name of the weapon template (a copy of base_item's)
--     base_item: the game item that is copied; its models are used
--     deus_copy: the Chaos Wastes weapon (DeusWeapons key) of base_item, which the item's Chaos Wastes weapon is a copy of
--     name, type_name (the line under the name), description
--     keywords: localization ids for the line under the power; texts: { id = text } for the ids that are the mod's
--     icon: a material in the file icon_materials, which is in the package icon_package
--     skins: the weapon's illusions, { key, name, description, icon, icon_materials, default }: the one that is default is what the item looks
--         like without one (it has no skin of its own), the others are chosen with the game's Illusions page. They are unlocked for
--         everyone. The icon and description are the item's when a skin has none. weapon_skin.lua shows a model for each.
--
-- The backend doesn't have these items, so they are added to the inventory it loaded. The ids are fixed: the item's key for the blueprint,
-- key#number for crafted weapons (see crafting.lua), so a loadout finds them again.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")

local items = {}

local definitions = {}

-- Texts for the names and descriptions, which the game's localization doesn't have
local texts = {}

mod:hook(LocalizationManager, "_base_lookup", function (func, self, text_id)
	return texts[text_id] or func(self, text_id)
end)

-- The icons package is listed in the .mod file, and the game loads it through the mod (Managers.package doesn't know it). UI renderers
-- lock its materials, and unloading a package with a locked resource is an error, which a mod reload would do. So the mod keeps a handle
-- of its own, in a global so a reload finds it, and never releases it.
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

-- Extra materials for UI renderers. UIRenderer.create adds them to every renderer made after this.
local function add_material_set(material_set)
	if not table.contains(UIRenderer._injected_material_sets, material_set) then
		table.insert(UIRenderer._injected_material_sets, material_set)
	end
end

-- The in-game UI makes its renderers when a level loads. One made before the mod was loaded or reloaded can't find the icon's material (the
-- game mounts the mod's resources again on a reload), so in a level the items keep the base item's icon until the next level.
local icons_waiting = {}

mod:hook_safe(IngameUI, "init", function ()
	for _, set_icon in ipairs(icons_waiting) do
		set_icon()
	end

	table.clear(icons_waiting)
end)

-- Gives each of the tables (an item, a skin) the icon, now or when the in-game UI has its renderers
local function set_icons(tables, icon)
	local function set_icon()
		for _, icon_owner in ipairs(tables) do
			icon_owner.inventory_icon = icon
		end
	end

	if Managers.ui and Managers.ui._ingame_ui then
		icons_waiting[#icons_waiting + 1] = set_icon
	else
		set_icon()
	end
end

-- What the mod saves between games, in its settings file:
--   crafted: { [backend id] = record } the crafted weapons; a record is { key, rarity, power_level, properties, traits, skin }
--   started: { [item key] = true } the weapons given at the start (see add_to_inventory)
--   next_id: number of the next crafted weapon
local SAVED_SETTING = "custom_items"

function items.saved()
	local saved = table.clone(mod:get(SAVED_SETTING) or { crafted = {}, next_id = 1 })

	-- Saved data from before this field existed
	saved.started = saved.started or {}

	return saved
end

function items.save(saved)
	mod:set(SAVED_SETTING, saved)
end

-- The blueprint: always in the inventory, and what the Craft page crafts from. "default" is the rarity the page accepts for that.
local BLUEPRINT_RECORD = {
	power_level = 5,
	properties = {},
	rarity = "default",
	traits = {},
}

-- The weapon given at the start, besides the blueprint
local STARTING_RECORD = {
	power_level = 300,
	properties = {},
	rarity = "plentiful",
	traits = {},
}

-- An inventory item in the shape of the backend's
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

	custom_data.skin = record.skin

	return {
		CustomData = custom_data,
		ItemId = key,
		ItemInstanceId = backend_id,
		-- Marks the mod's items
		UtCustom = true,
	}
end

-- The game's local copy of the backend inventory
local function mirror_of_backend()
	return Managers.backend and Managers.backend._backend_mirror
end

-- If the inventory item is one of the mod's weapons
function items.is_custom(backend_id)
	local mirror = mirror_of_backend()
	local item = mirror and mirror._inventory_items and mirror._inventory_items[backend_id]

	return item ~= nil and item.UtCustom == true
end

-- A new weapon: returns its backend id and inventory item. The game's craft adds it to the inventory.
function items.new_crafted(saved, key, record)
	local backend_id = string.format("%s#%d", key, saved.next_id)

	saved.next_id = saved.next_id + 1
	saved.crafted[backend_id] = table.clone(record)
	saved.crafted[backend_id].key = key

	return backend_id, inventory_item(key, backend_id, record)
end

-- A changed weapon: returns the inventory item that replaces the old one
function items.change_crafted(saved, backend_id, record)
	local key = saved.crafted[backend_id].key

	saved.crafted[backend_id] = table.clone(record)
	saved.crafted[backend_id].key = key

	items.save(saved)

	return inventory_item(key, backend_id, record)
end

-- Adds the mod's weapons to the loaded inventory
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

		-- (the inventory is loaded after the skins that are unlocked, so this only has to make them when the mod is loaded later)
		if mirror._unlocked_weapon_skins then
			for _, skin_key in ipairs(definition.skin_keys or {}) do
				mirror:add_unlocked_weapon_skin(skin_key)
			end
		end

		-- Given once. After that it is an ordinary crafted weapon, which can be changed or salvaged.
		if not saved.started[definition.key] then
			saved.started[definition.key] = true

			items.new_crafted(saved, definition.key, STARTING_RECORD)
			items.save(saved)
		end
	end

	for backend_id, record in pairs(saved.crafted) do
		if definitions[record.key] then
			local item = inventory_item(record.key, backend_id, record)

			mirror:_update_data(item, backend_id)

			inventory[backend_id] = item
		end
	end
end

-- The game uses PlayFabMirrorAdventure. A class copies its parent's functions when it is made, so hooking the base class has no effect.
mod:hook_safe(PlayFabMirrorAdventure, "inventory_request_cb", function (self)
	add_to_inventory(self)
end)

-- The registered definitions by setting id, e.g. items.weapons.shock_rifle.template
items.weapons = {}

-- The weapon's skins: entries of the game's skin tables and of its item list, copies of the base weapon's default skin
local function register_skins(definition, item)
	if not definition.skins then
		return
	end

	local base_skin_key = WeaponSkins.default_skins[definition.base_item]
	local base_skin_item_key = definition.base_item .. "_skin"
	local skin_keys = {}
	local default_skin_key

	for _, skin in ipairs(definition.skins) do
		local skin_data = table.clone(WeaponSkins.skins[base_skin_key])
		local skin_item = table.clone(ItemMasterList[base_skin_key])

		skin_data.template = definition.template
		skin_data.display_name = skin.key .. "_name"
		skin_data.description = skin.key .. "_description"
		skin_data.rarity = skin.default and "plentiful" or "common"

		skin_item.display_name = skin_data.display_name
		skin_item.description = skin_data.description
		skin_item.matching_item_key = definition.key
		skin_item.template = definition.template
		skin_item.rarity = skin_data.rarity
		skin_item.can_wield = item.can_wield
		skin_item.key = skin.key
		skin_item.name = skin.key
		skin_item.localized_name = skin.name

		texts[skin_data.display_name] = skin.name
		texts[skin_data.description] = skin.description or definition.description

		if skin.icon then
			UIAtlasHelper.add_standalone_texture_by_name(skin.icon)
			add_material_set(skin.icon_materials)
		end

		set_icons({ skin_data, skin_item }, skin.icon or definition.icon)

		WeaponSkins.skins[skin.key] = skin_data
		ItemMasterList[skin.key] = skin_item

		utils.register_network_lookup("weapon_skins", skin.key)

		skin_keys[#skin_keys + 1] = skin.key

		if skin.default then
			default_skin_key = skin.key
		end
	end

	-- The skin item the backend's unlocked skins are made into (named after the weapon)
	local base_skin_item = table.clone(ItemMasterList[base_skin_item_key])

	base_skin_item.matching_item_key = definition.key
	base_skin_item.can_wield = item.can_wield
	base_skin_item.key = definition.key .. "_skin"
	base_skin_item.name = base_skin_item.key

	ItemMasterList[base_skin_item.key] = base_skin_item

	WeaponSkins.skin_combinations[definition.key .. "_skins"] = { common = skin_keys }
	WeaponSkins.default_skins[definition.key] = default_skin_key
	-- (made from the tables above the first time it is asked for)
	WeaponSkins._matching_weapon_skin_item_keys = nil

	item.skin_combination_table = definition.key .. "_skins"
	definition.skin_keys = skin_keys
end

-- Every skin of the mod's weapons is unlocked: the game keeps what is unlocked in the backend's data, which doesn't know them
mod:hook(PlayFabMirrorAdventure, "_parse_unlocked_weapon_skins", function (func, self)
	local unlocked = func(self)

	for _, definition in pairs(definitions) do
		for _, skin_key in ipairs(definition.skin_keys or {}) do
			unlocked[skin_key] = unlocked[skin_key] or self._unlocked_weapon_skins and self._unlocked_weapon_skins[skin_key] or true
		end
	end

	return unlocked
end)

function items.register(setting_id, definition)
	items.weapons[setting_id] = definition

	local base_template = rawget(Weapons, ItemMasterList[definition.base_item].template)
	local template = table.clone(base_template)
	local item = table.clone(ItemMasterList[definition.base_item])

	-- Actions name their template; it is how other peers learn which action a projectile came from
	utils.set_actions_lookup_data(template.actions, definition.template)

	-- The game sets this when it loads templates; the skins identify the weapon by it
	template.name = definition.template

	Weapons[definition.template] = template

	item.template = definition.template
	item.display_name = definition.key .. "_name"
	item.description = definition.key .. "_description"
	-- The line under the name in the inventory
	item.item_type = definition.key .. "_type"
	-- The careers of the weapon it is a copy of (the game's first person animations, units and attachments are made for them: another
	-- career equipping it crashes the game)
	item.can_wield = table.clone(definition.can_wield or ItemMasterList[definition.base_item].can_wield)
	-- The base weapon's skins don't apply (register_skins gives the item its own)
	item.skin_combination_table = nil
	-- What parse_item_master_list does for every item
	item.key = definition.key
	item.name = definition.key
	item.localized_name = definition.name

	texts[item.display_name] = definition.name
	texts[item.description] = definition.description
	texts[item.item_type] = definition.type_name

	-- The green line under the power
	template.tooltip_keywords = definition.keywords

	for text_id, text in pairs(definition.texts or {}) do
		texts[text_id] = text
	end

	-- The icon is a standalone texture, drawn by its material's name, which the UI renderers must be given
	UIAtlasHelper.add_standalone_texture_by_name(definition.icon)
	hold_package(definition.icon_package)
	add_material_set(definition.icon_materials)
	set_icons({ item }, definition.icon)

	ItemMasterList[definition.key] = item

	register_skins(definition, item)

	utils.register_network_lookup("item_template_names", definition.template)
	utils.register_network_lookup("item_names", definition.key)
	utils.register_network_lookup("damage_sources", definition.key)

	definitions[definition.key] = definition

	-- Chaos Wastes builds its loadouts and drops from its own tables, which are read-only, so rawset. They only exist with the DLC.
	if rawget(_G, "DeusWeapons") then
		local deus_key = "deus_" .. definition.key
		local deus_weapon = table.clone(DeusWeapons[definition.deus_copy])

		deus_weapon.base_item = definition.key

		rawset(DeusWeapons, deus_key, deus_weapon)
		rawset(DeusStartingWeaponTypeMapping, definition.key, deus_key)
		rawset(DeusWeaponGroups, definition.key, {
			can_wield = item.can_wield,
			default = deus_key,
			items_per_rarity = {},
			slot_type = item.slot_type,
		})
	end

	-- The inventory is already loaded when the mod is loaded during a game
	local backend = Managers.backend
	local mirror = backend and backend._backend_mirror

	if mirror then
		add_to_inventory(mirror)

		backend:get_interface("items"):make_dirty()
	end
end

return items
