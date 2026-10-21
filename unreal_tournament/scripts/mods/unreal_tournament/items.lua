local mod = get_mod("unreal_tournament")

-- The mod's weapons as items of their own. Each is a copy of a game weapon (its template and its item) with a name of its own. The
-- careers that can use the game's weapon can use the copy. The game's weapon itself is left unchanged.
--
--   items.register(setting_id, { key, template, base_item, deus_copy, name, type_name, description, keywords, texts, icon, icon_package,
--       icon_materials })
--     key: the item's name. It is also used for damage sources, loadouts and the network.
--     template: the name of the weapon template, which is a copy of base_item's.
--     base_item: the game item that is copied. Its models are used.
--     deus_copy: the Chaos Wastes weapon (a DeusWeapons key) of base_item. The item's Chaos Wastes weapon is a copy of it.
--     can_wield: the careers that can use the item, if they differ from base_item's.
--     melee_slot: the item goes in the melee slot, though base_item is a ranged weapon. It keeps base_item's properties (critical
--         strikes and power against enemies, which work on any weapon), and takes the traits of a melee weapon (the ranged ones are about
--         ammo), in Chaos Wastes those of deus_melee_tables (a DeusWeapons key of a melee weapon).
--     name, type_name (the line under the name), description: the texts of the item.
--     keywords: localization ids for the line under the power. texts: { id = text } for the ids that are the mod's own.
--     icon: a material in the file icon_materials, which is in the package icon_package.
--     skins: the weapon's illusions, each { key, name, description, icon, icon_materials, default }. The one marked default is how the
--         item looks with no illusion applied. The others are picked on the game's Illusions page. All of them are unlocked for
--         everyone. A skin without an icon or description uses the item's. weapon_skin.lua shows a model for each.
--
-- The backend doesn't have these items, so they are added to the inventory it loaded. The ids are fixed: the item's key for the
-- blueprint, and key#number for crafted weapons (see crafting.lua). That way a loadout finds them again.

local utils = mod.utils

local items = {}
mod.items = items

local definitions = {}

-- The texts of the items' names and descriptions, which the game's localization doesn't have
local texts = {}

mod:hook(LocalizationManager, "_base_lookup", function (func, self, text_id)
	return texts[text_id] or func(self, text_id)
end)

-- The icons package is listed in the .mod file, and the game loads it through the mod (Managers.package doesn't know it). UI renderers
-- lock its materials, and unloading a package with a locked resource is an error, which a mod reload would cause. So the mod keeps a
-- handle of its own to the package, in a global so that a reload finds it, and never releases it.
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

-- Adds a material set to the UI renderers. UIRenderer.create adds it to every renderer made after this.
local function add_material_set(material_set)
	if not table.contains(UIRenderer._injected_material_sets, material_set) then
		table.insert(UIRenderer._injected_material_sets, material_set)
	end
end

-- A weapon that draws on the screen (the Lightning Gun's scope) adds its materials the same way.
items.add_material_set = add_material_set

-- The in-game UI makes its renderers when a level loads. A renderer made before the mod was loaded or reloaded can't find the icon's
-- material, because the game mounts the mod's resources again on a reload. So in a level, the items show the game's placeholder icon
-- until the next level. Every renderer has it.
local PLACEHOLDER_ICON = "icons_placeholder"
local icons_waiting = {}

mod:hook_safe(IngameUI, "init", function (self)
	for _, set_icon in ipairs(icons_waiting) do
		set_icon()
	end

	table.clear(icons_waiting)

	for _, callback in pairs(mod.ingame_ui_init_callbacks) do
		callback(self)
	end
end)

-- After a reload, the renderers that the game made before it can't find the icon's material, and the game crashes when one draws it.
-- The item tables from before the reload still have the icon, because the tab screen keeps the loadouts it made from them until the
-- player changes theirs. So those tables are given the placeholder.
local function retire_icon(old_table)
	if old_table then
		old_table.inventory_icon = PLACEHOLDER_ICON
	end
end

-- A menu that is open when the mod is unloaded (the hero screen, for example) keeps the icon's name in its widgets and draws it after
-- the reload, which crashes the game. So the menu is closed first. The next time it opens, it is made from the item tables, which have
-- the placeholder then.
mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
	local ingame_ui = Managers.ui and Managers.ui._ingame_ui

	if ingame_ui and ingame_ui.current_view then
		ingame_ui:handle_transition("exit_menu")
	end
end

-- Sets the icon on each table (an item or a skin), now or once the in-game UI has its renderers.
local function set_icons(tables, icon)
	local function set_icon()
		for _, icon_owner in ipairs(tables) do
			icon_owner.inventory_icon = icon
		end
	end

	if Managers.ui and Managers.ui._ingame_ui then
		for _, icon_owner in ipairs(tables) do
			icon_owner.inventory_icon = PLACEHOLDER_ICON
		end

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

	-- Saved data from before this field existed has no started list
	saved.started = saved.started or {}

	return saved
end

function items.save(saved)
	mod:set(SAVED_SETTING, saved)
end

-- The blueprint is always in the inventory, and the Craft page crafts from it. "default" is the rarity that the page accepts for that.
local BLUEPRINT_RECORD = {
	power_level = 5,
	properties = {},
	rarity = "default",
	traits = {},
}

-- The weapon that is given at the start, besides the blueprint
local STARTING_RECORD = {
	power_level = 300,
	properties = {},
	rarity = "plentiful",
	traits = {},
}

-- Makes an inventory item in the shape that the backend uses.
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
		-- This marks the mod's items.
		UtCustom = true,
	}
end

-- Returns the game's local copy of the backend inventory.
local function mirror_of_backend()
	return Managers.backend and Managers.backend._backend_mirror
end

-- Returns whether the inventory item is one of the mod's weapons.
function items.is_custom(backend_id)
	local mirror = mirror_of_backend()
	local item = mirror and mirror._inventory_items and mirror._inventory_items[backend_id]

	return item ~= nil and item.UtCustom == true
end

-- Makes a new crafted weapon and returns its backend id and inventory item. The game's craft adds it to the inventory.
function items.new_crafted(saved, key, record)
	local backend_id = string.format("%s#%d", key, saved.next_id)

	saved.next_id = saved.next_id + 1
	saved.crafted[backend_id] = table.clone(record)
	saved.crafted[backend_id].key = key

	return backend_id, inventory_item(key, backend_id, record)
end

-- Changes a crafted weapon and returns the inventory item that replaces the old one.
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

		-- When the inventory loads, the unlocked skins already include these, so this is only needed when the mod loads later.
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

-- Weapons the mod had and dropped: the Redeemer, which is now the Bounty Hunter's ability (redeemer.lua), and the names the Link Gun's
-- copies had while it was being made (now ut_link_gun and the others, link/link_gun.lua). A loadout that still holds
-- one names an item that is no longer in the inventory, which the game repairs itself when it starts (PlayFabMirrorBase's broken item
-- slots, fixCareerData). After a reload, a character can still hold the item table of a dropped weapon from before it, and the tab
-- screen draws its icon, whose material is gone (see retire_icon).
local DROPPED_KEYS = {
	ut_redeemer = true,
	ut_link_new = true,
	ut_link_new_dr = true,
	ut_link_new_wh = true,
	ut_link_new_bw = true,
	ut_link_new_we = true,
}

for key in pairs(DROPPED_KEYS) do
	retire_icon(rawget(ItemMasterList, key))
end

-- The registered definitions by id, for example items.weapons.shock_rifle.template
items.weapons = {}

-- Each weapon's template as items.register made it: a copy of the base weapon's. With the mod switched off, the template goes back to
-- this, so the item works as its base weapon.
local base_copies = {}

-- The function of each weapon that turns its template into the mod's weapon, by template name
local template_changes = {}

local function reset_template(template_name)
	local template = rawget(Weapons, template_name)

	-- The table is kept, and only its contents are replaced, because the game holds on to it
	table.clear(template)

	for key, value in pairs(table.clone(base_copies[template_name])) do
		template[key] = value
	end

	return template
end

-- Sets the function that turns a weapon's template into the mod's weapon: change(template). It runs on a fresh copy of the base
-- weapon's template each time the mod is switched on.
function items.set_template_changes(template_name, change)
	template_changes[template_name] = change
end

mod.enabled_callbacks[#mod.enabled_callbacks + 1] = function ()
	for template_name, change in pairs(template_changes) do
		change(reset_template(template_name))
	end
end

local function reset_all_templates()
	for template_name in pairs(template_changes) do
		reset_template(template_name)
	end
end

mod.disabled_callbacks[#mod.disabled_callbacks + 1] = reset_all_templates
mod.unload_callbacks[#mod.unload_callbacks + 1] = reset_all_templates

-- Registers the weapon's skins: entries in the game's skin tables and item list, copied from the base weapon's default skin.
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
		skin_item.required_dlc = nil
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

		retire_icon(WeaponSkins.skins[skin.key])
		retire_icon(ItemMasterList[skin.key])

		WeaponSkins.skins[skin.key] = skin_data
		ItemMasterList[skin.key] = skin_item

		utils.register_network_lookup("weapon_skins", skin.key)

		skin_keys[#skin_keys + 1] = skin.key

		if skin.default then
			default_skin_key = skin.key
		end
	end

	-- This is the item that the backend's unlocked skins are turned into. It is named after the weapon.
	local base_skin_item = table.clone(ItemMasterList[base_skin_item_key])

	base_skin_item.matching_item_key = definition.key
	base_skin_item.can_wield = item.can_wield
	base_skin_item.required_dlc = nil
	base_skin_item.key = definition.key .. "_skin"
	base_skin_item.name = base_skin_item.key

	ItemMasterList[base_skin_item.key] = base_skin_item

	WeaponSkins.skin_combinations[definition.key .. "_skins"] = { common = skin_keys }
	WeaponSkins.default_skins[definition.key] = default_skin_key
	-- This is cleared so the game builds it again from these tables the next time it needs it.
	WeaponSkins._matching_weapon_skin_item_keys = nil

	item.skin_combination_table = definition.key .. "_skins"
	definition.skin_keys = skin_keys
end

-- Unlocks every skin of the mod's weapons. The game keeps unlocked skins in the backend's data, which doesn't know about them.
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

	-- Actions name their template, which is how the other machines learn which action a projectile came from.
	utils.set_actions_lookup_data(template.actions, definition.template)

	-- The game sets the name when it loads templates, and the skins use it to identify the weapon.
	template.name = definition.template

	Weapons[definition.template] = template

	item.template = definition.template
	item.display_name = definition.key .. "_name"
	item.description = definition.key .. "_description"
	-- This is the line under the name in the inventory.
	item.item_type = definition.key .. "_type"
	-- The item uses the careers of the weapon it is a copy of. The first person animations, units and attachments are made for those
	-- careers, and another career that equips the item crashes the game.
	item.can_wield = table.clone(definition.can_wield or ItemMasterList[definition.base_item].can_wield)
	-- The game's weapon may need a DLC to own it, but the mod's weapon does not.
	item.required_dlc = nil
	-- The base weapon's skins don't apply to the item. register_skins gives it skins of its own.
	item.skin_combination_table = nil

	if definition.melee_slot then
		item.slot_type = "melee"
		item.trait_table_name = "melee"

		-- An item of the melee slot has no ammo: the game carries each slot's ammo over to the next level, and stops on a template with
		-- ammo whose units have none. Its tooltip shows a melee weapon's stamina and block angles, and stops without them. The base
		-- weapon has no block, so its angles are 0 and its stamina is the least the tooltip shows, one shield. Its bots take it for a
		-- melee weapon, with the game's default data for one (a ranged weapon's in the melee slot stopped them). This holds for the copy
		-- below too, which is the template whenever the mod is off (and while it reloads).
		template.ammo_data = nil
		template.max_fatigue_points = template.max_fatigue_points or 2
		template.block_angle = template.block_angle or 0
		template.outer_block_angle = template.outer_block_angle or 0
		template.buff_type = "MELEE"
		template.attack_meta_data = nil
	end

	-- These are set the way parse_item_master_list sets them for every item.
	item.key = definition.key
	item.name = definition.key
	item.localized_name = definition.name

	texts[item.display_name] = definition.name
	texts[item.description] = definition.description
	texts[item.item_type] = definition.type_name

	-- These are the green words under the power.
	template.tooltip_keywords = definition.keywords

	base_copies[definition.template] = table.clone(template)

	for text_id, text in pairs(definition.texts or {}) do
		texts[text_id] = text
	end

	-- The icon is a standalone texture, drawn by its material's name, so the UI renderers must be given that material.
	UIAtlasHelper.add_standalone_texture_by_name(definition.icon)
	hold_package(definition.icon_package)
	add_material_set(definition.icon_materials)
	set_icons({ item }, definition.icon)

	retire_icon(ItemMasterList[definition.key])

	ItemMasterList[definition.key] = item

	register_skins(definition, item)

	utils.register_network_lookup("item_template_names", definition.template)
	utils.register_network_lookup("item_names", definition.key)
	utils.register_network_lookup("damage_sources", definition.key)

	definitions[definition.key] = definition

	-- Chaos Wastes builds its loadouts and drops from its own tables. They are read-only, so rawset is used. They only exist with the DLC.
	if rawget(_G, "DeusWeapons") then
		local deus_key = "deus_" .. definition.key
		local deus_weapon = table.clone(DeusWeapons[definition.deus_copy])

		deus_weapon.base_item = definition.key

		-- (DeusWeapons filled these in from the base item as it loaded)
		if definition.melee_slot then
			local melee = DeusWeapons[definition.deus_melee_tables]

			deus_weapon.trait_table_name = melee.trait_table_name
			deus_weapon.baked_trait_combinations = melee.baked_trait_combinations
		end

		rawset(DeusWeapons, deus_key, deus_weapon)
		rawset(DeusStartingWeaponTypeMapping, definition.key, deus_key)
		rawset(DeusWeaponGroups, definition.key, {
			can_wield = item.can_wield,
			default = deus_key,
			items_per_rarity = {},
			slot_type = item.slot_type,
		})
	end

	-- If the mod is loaded during a game, the inventory is already loaded, so the items are added to it now.
	local backend = Managers.backend
	local mirror = backend and backend._backend_mirror

	if mirror then
		add_to_inventory(mirror)

		backend:get_interface("items"):make_dirty()
	end
end