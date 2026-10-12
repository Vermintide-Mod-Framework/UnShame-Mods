local mod = get_mod("unreal_tournament")

-- Weapon skins in the menus. The hero on the equipment screen holds the weapon's mesh instead of the game's unit (weapon_skin_third_person.lua
-- does the same in the world), and the item inspection (LootItemUnitPreviewer) shows the mesh instead of the staff. The previewers keep
-- spawning the game's units; they are hidden and the mesh is shown in their place.

local CONFIG = {
	-- Length of the mesh in the item inspection (meters)
	item_length = 0.62,
}

-- Returns the weapon skin for an item, if it has one and it is shown.
local function skin_of(item_name)
	local item = item_name and rawget(ItemMasterList, item_name)

	if not item then
		return nil
	end

	for _, skin in pairs(mod.weapon_skin.skins) do
		if skin.config.template == item.template and skin.enabled() then
			return skin
		end
	end
end

-- The hero of the equipment screen (HeroPreviewer)

-- [previewer] = { character, skin }: the previewers whose hero holds the mesh
local holding = {}

local function release_hero(previewer)
	local entry = holding[previewer]

	if entry then
		holding[previewer] = nil

		entry.skin.third_person.release_from_menu(entry.character)
	end
end

-- The previewer's units for the ranged weapon (right and left hand)
local function ranged_units(previewer)
	local slot = InventorySettings.slots_by_name.slot_ranged
	local equipment_units = previewer._equipment_units[slot.slot_index]
	local units = {}

	if type(equipment_units) == "table" then
		for _, key in ipairs({ "right", "left" }) do
			if equipment_units[key] then
				units[#units + 1] = equipment_units[key]
			end
		end
	end

	return units
end

-- A class copies its parent's functions when it is made, so MenuWorldPreviewer needs hooking as well as HeroPreviewer
for _, previewer_class in ipairs({ HeroPreviewer, MenuWorldPreviewer }) do
	mod:hook_safe(previewer_class, "post_update", function (self)
		local character = self.character_unit
		local skin = character and Unit.alive(character) and skin_of(self:item_name_by_slot_type("ranged")) or nil
		local item_info = self._item_info_by_slot.ranged
		-- (Most screens give the previewer the item's backend id, not its skin.)
		local skin_key = item_info and (item_info.skin_name or item_info.backend_id and Managers.backend:get_interface("items"):get_skin(item_info.backend_id))
		local entry = holding[self]

		if entry and (entry.skin ~= skin or entry.character ~= character) then
			release_hero(self)
		end

		if not skin then
			return
		end

		-- Shown while the ranged weapon is in hand
		local visible = self._wielded_slot_type == "ranged" and self.character_unit_visible ~= false

		skin.third_person.hold_in_menu(character, self.world, ranged_units(self), visible, skin_key)

		holding[self] = {
			character = character,
			skin = skin,
		}
	end)

	-- Before the previewer destroys its units
	mod:hook(previewer_class, "clear_units", function (func, self, ...)
		release_hero(self)

		return func(self, ...)
	end)
end

-- Item inspection (LootItemUnitPreviewer): the mesh is linked to the unit the previewer turns, which the item's units are linked to

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

		-- Barrel to the side, centred on the unit, scaled to item_length
		local pose, half_extents = Unit.box(unit)
		local length = math.max(Vector3.x(half_extents), Vector3.y(half_extents), Vector3.z(half_extents)) * 2
		local scale = CONFIG.item_length / length
		local rotation = Quaternion.axis_angle(Vector3.up(), math.rad(skin.third_person.config_of(look).menu_yaw or -90))

		World.link_unit(world, unit, 0, self._link_unit, 0)
		Unit.set_local_scale(unit, 0, Vector3(scale, scale, scale))
		Unit.set_local_rotation(unit, 0, rotation)
		Unit.set_local_position(unit, 0, -Quaternion.rotate(rotation, Matrix4x4.translation(pose) * scale))

		self._ut_unit = unit
		inspecting[self] = true
	end

	Unit.set_unit_visibility(unit, visible)

	-- Hidden units still show their effects (the staff's flame), so they get the event the game sends on unwielding
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

-- Unloading with a menu open: the worlds still exist, so the mod's units are destroyed first
mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
	for previewer in pairs(holding) do
		release_hero(previewer)
	end

	for previewer in pairs(inspecting) do
		release_item(previewer)
	end
end
