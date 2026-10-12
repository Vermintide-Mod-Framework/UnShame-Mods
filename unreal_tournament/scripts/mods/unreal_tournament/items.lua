local mod = get_mod("unreal_tournament")

-- The weapons as items of their own: each is a copy of a game weapon (its template and its item), with a name of its own, in every
-- player's inventory and usable by every career. The game's weapon is left as it is.
--
--   items.register(setting_id, { key, template, base_item, name, description })
--     key: the item's name (damage sources, the loadout and the other peers know the item by it), template: the weapon template's name,
--     base_item: the game's item that is copied (its models, icon, kind and skins are the copy's), name, description: shown in the inventory
--
-- The game takes the inventory from the backend (PlayFab), which does not have these items: they are put into the inventory it has loaded,
-- under an id that is the item's key, the same every time, so that the loadout that has one equipped finds it again.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")

local items = {}

local definitions = {}

-- The text of the names and descriptions: the game's localization has no entry for them
local texts = {}

mod:hook(LocalizationManager, "_base_lookup", function (func, self, text_id)
	return texts[text_id] or func(self, text_id)
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

-- The inventory item of a definition, as the backend's inventory has them
local function inventory_item(definition)
	local item = {
		ItemId = definition.key,
		ItemInstanceId = definition.key,
		CustomData = {
			power_level = "300",
			rarity = "plentiful",
		},
	}

	return item
end

-- Puts the items into the inventory that the mirror of the backend has loaded
local function add_to_inventory(mirror)
	local inventory = mirror._inventory_items

	if not inventory then
		return
	end

	for _, definition in pairs(definitions) do
		local item = inventory_item(definition)

		mirror:_update_data(item, definition.key)

		inventory[definition.key] = item
	end
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
	item.can_wield = all_careers()
	-- (what the game's parse_item_master_list makes of every item)
	item.key = definition.key
	item.name = definition.key
	item.localized_name = definition.name

	texts[item.display_name] = definition.name
	texts[item.description] = definition.description

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
