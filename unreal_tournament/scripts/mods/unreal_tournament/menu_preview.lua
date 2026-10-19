local mod = get_mod("unreal_tournament")

-- Weapon skins in the menus. The hero on the equipment screen holds the weapons' meshes instead of the game's units (weapon_skin_third_person.lua
-- does the same in the world). The item inspection (LootItemUnitPreviewer) shows the mesh instead of the staff. The previewers keep
-- spawning the game's units, so those are hidden and the mesh is shown in their place.

local CONFIG = {
	-- The length of the mesh in the item inspection, in meters
	item_length = 0.62,
}

-- Returns the weapon skin for an item, or nil if it has none. A weapon held two at a time (the Assault Rifle) has a skin for each hand:
-- this is one of them, and skins_of gives all of them.
local function skins_of(item_name)
	local item = item_name and rawget(ItemMasterList, item_name)
	local found = {}

	if not item then
		return found
	end

	for _, skin in pairs(mod.weapon_skin.skins) do
		if skin.config.template == item.template then
			found[#found + 1] = skin
		end
	end

	return found
end

local function skin_of(item_name)
	return skins_of(item_name)[1]
end

-- The hero of the equipment screen (HeroPreviewer)

-- The previewer's slots that can hold a weapon with a skin, by the slot type it uses and the slot's name
local SLOTS = {
	melee = "slot_melee",
	ranged = "slot_ranged",
}

-- The previewers whose hero holds a mesh, as [previewer] = { [slot type] = { character, skins, item_name } }
local holding = {}

local function release_slot(previewer, slot_type)
	local entries = holding[previewer]
	local entry = entries and entries[slot_type]

	if entry then
		entries[slot_type] = nil

		for _, skin in ipairs(entry.skins) do
			skin.third_person.release_from_menu(entry.character)
		end
	end
end

local function release_hero(previewer)
	for slot_type in pairs(SLOTS) do
		release_slot(previewer, slot_type)
	end

	holding[previewer] = nil
end

-- The previewer's units for the weapon in a slot, the one in the skin's hand first (right, then left, or left first for a skin held in
-- the left hand)
local function slot_units(previewer, slot_name, skin)
	local slot = InventorySettings.slots_by_name[slot_name]
	local equipment_units = previewer._equipment_units[slot.slot_index]
	local third_person = skin.config.third_person
	local left_first = third_person and third_person.hand_node == "j_leftweaponattach"
	local units = {}

	if type(equipment_units) == "table" then
		for _, key in ipairs(left_first and { "left", "right" } or { "right", "left" }) do
			if equipment_units[key] then
				units[#units + 1] = equipment_units[key]
			end
		end
	end

	return units
end

-- A class copies its parent's functions when it is made, so MenuWorldPreviewer has to be hooked as well as HeroPreviewer.
for _, previewer_class in ipairs({ HeroPreviewer, MenuWorldPreviewer }) do
	mod:hook_safe(previewer_class, "post_update", function (self)
		local character = self.character_unit

		for slot_type, slot_name in pairs(SLOTS) do
			local item_name = character and Unit.alive(character) and self:item_name_by_slot_type(slot_type) or nil
			local skins = item_name and skins_of(item_name) or {}
			local item_info = self._item_info_by_slot[slot_type]
			-- Most screens give the previewer the item's backend id, not its skin.
			local skin_key = item_info and (item_info.skin_name or item_info.backend_id and Managers.backend:get_interface("items"):get_skin(item_info.backend_id))
			local entry = holding[self] and holding[self][slot_type]

			if entry and (entry.item_name ~= item_name or entry.character ~= character) then
				release_slot(self, slot_type)
			end

			if #skins > 0 then
				-- The mesh is shown while its weapon is in hand. The game's units of the slot stay hidden, in hand or not.
				local visible = self._wielded_slot_type == slot_type and self.character_unit_visible ~= false

				for _, skin in ipairs(skins) do
					skin.third_person.hold_in_menu(character, self.world, slot_units(self, slot_name, skin), visible, skin_key)
				end

				holding[self] = holding[self] or {}
				holding[self][slot_type] = {
					character = character,
					item_name = item_name,
					skins = skins,
				}
			end
		end
	end)

	-- The mesh is released before the previewer destroys its units.
	mod:hook(previewer_class, "clear_units", function (func, self, ...)
		release_hero(self)

		return func(self, ...)
	end)
end

-- Item inspection (LootItemUnitPreviewer). The mesh is linked to the unit that the previewer turns, which is the unit the item's own
-- units are linked to.

-- The previewers that have the mesh
local inspecting = {}

local function release_item(previewer)
	local unit = previewer._ut_unit

	inspecting[previewer] = nil

	if unit then
		previewer._ut_unit = nil

		if Unit.alive(unit) then
			World.unlink_unit(previewer._background_world, unit)
			World.destroy_unit(previewer._background_world, unit)
		end
	end
end

mod:hook_safe(LootItemUnitPreviewer, "_enable_item_units_visibility", function (self, item_key, ignore_spin, visible)
	local skin = skin_of(item_key)

	if not skin or not self._link_unit then
		return
	end

	local world = self._background_world
	local unit = self._ut_unit

	if not unit then
		local look = self._item and skin.look_of(self._item.skin)

		unit = skin.third_person.new_mesh(world, look)

		-- The barrel points to the side, the mesh is centered on the unit, and it is scaled to item_length (times the weapon's menu_scale).
		local pose, half_extents = Unit.box(unit)
		local length = math.max(Vector3.x(half_extents), Vector3.y(half_extents), Vector3.z(half_extents)) * 2
		local config = skin.third_person.config_of(look)
		local scale = CONFIG.item_length / length * (config.menu_scale or 1)
		local rotation = Quaternion.multiply(Quaternion.axis_angle(Vector3.up(), math.rad(config.menu_yaw or -90)), Quaternion.axis_angle(Vector3.right(), math.rad(config.menu_pitch or 0)))

		World.link_unit(world, unit, 0, self._link_unit, 0)
		Unit.set_local_scale(unit, 0, Vector3(scale, scale, scale))
		Unit.set_local_rotation(unit, 0, rotation)
		Unit.set_local_position(unit, 0, -Quaternion.rotate(rotation, Matrix4x4.translation(pose) * scale))

		self._ut_unit = unit
		inspecting[self] = true
	end

	Unit.set_unit_visibility(unit, visible)

	-- Hidden units still show their effects, such as the staff's flame, so they get the event that the game sends on unwielding.
	for _, game_unit in ipairs(self._spawned_units or {}) do
		if Unit.alive(game_unit) then
			Unit.set_unit_visibility(game_unit, false)
			Unit.flow_event(game_unit, "lua_unwield")
		end
	end
end)

mod:hook(LootItemUnitPreviewer, "_destroy_units", function (func, self, ...)
	release_item(self)

	return func(self, ...)
end)

-- When the mod is unloaded with a menu open, the worlds still exist, so the mod's units are destroyed first.
mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
	for previewer in pairs(holding) do
		release_hero(previewer)
	end

	for previewer in pairs(inspecting) do
		release_item(previewer)
	end
end
