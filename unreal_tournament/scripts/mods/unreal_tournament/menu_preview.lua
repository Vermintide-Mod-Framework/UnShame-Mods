local mod = get_mod("unreal_tournament")

-- The weapon skins in the menus. The hero of the equipment screen holds the weapon's mesh instead of the game's unit (the staff), as the
-- characters of the game do (weapon_skin_third_person.lua), and the inspection of an item (the window the equipment screen opens on an
-- item, LootItemUnitPreviewer) shows the mesh instead of the staff. What the game shows of an item is its own units, which are not changed
-- (the game's weapons are those units): the previewers' units are hidden and the mesh is put where they are.

local CONFIG = {
	-- How long the mesh is shown in the inspection of an item (meters): 1.3 filled more than the window's view, 0.65 was still too big, 0.45
	-- too small
	item_length = 0.55,
}

-- The skin of an item, if the item is a weapon that has one that is shown (the Weapon Skins setting)
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

-- [previewer] = { character, skin }: what holds the mesh
local holding = {}

local function release_hero(previewer)
	local entry = holding[previewer]

	if entry then
		holding[previewer] = nil

		entry.skin.third_person.release_from_menu(entry.character)
	end
end

-- The units of the hero's ranged weapon that the previewer has made (the right hand's and the left hand's)
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

-- (a class gets a copy of its parent's functions when it is made, so the menu's previewer has to be hooked as well as the one it is made from)
for _, previewer_class in ipairs({ HeroPreviewer, MenuWorldPreviewer }) do
	mod:hook_safe(previewer_class, "post_update", function (self)
		local character = self.character_unit
		local skin = character and Unit.alive(character) and skin_of(self:item_name_by_slot_type("ranged")) or nil
		local entry = holding[self]

		if entry and (entry.skin ~= skin or entry.character ~= character) then
			release_hero(self)
		end

		if not skin then
			return
		end

		-- (the mesh is held while the ranged weapon is the one the hero has in hand)
		local visible = self._wielded_slot_type == "ranged" and self.character_unit_visible ~= false

		skin.third_person.hold_in_menu(character, self.world, ranged_units(self), visible)

		holding[self] = {
			character = character,
			skin = skin,
		}
	end)

	-- (before the previewer takes its units and its world's down)
	mod:hook(previewer_class, "clear_units", function (func, self, ...)
		release_hero(self)

		return func(self, ...)
	end)
end

-- The inspection of an item (LootItemUnitPreviewer): the mesh is linked to the unit the item's units are linked to, which the previewer
-- turns, as long as the item is shown, and as big as CONFIG.item_length says

-- (the previewers that have the mesh)
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
		unit = skin.third_person.new_mesh(world)

		-- The mesh turned so that the barrel is to the side, and in the middle of the unit it is linked to, whatever size it is
		local pose, half_extents = Unit.box(unit)
		local length = math.max(Vector3.x(half_extents), Vector3.y(half_extents), Vector3.z(half_extents)) * 2
		local scale = CONFIG.item_length / length
		local rotation = Quaternion.axis_angle(Vector3.up(), -math.pi / 2)

		World.link_unit(world, unit, 0, self._link_unit, 0)
		Unit.set_local_scale(unit, 0, Vector3(scale, scale, scale))
		Unit.set_local_rotation(unit, 0, rotation)
		Unit.set_local_position(unit, 0, -Quaternion.rotate(rotation, Matrix4x4.translation(pose) * scale))

		self._ut_unit = unit
		inspecting[self] = true
	end

	Unit.set_unit_visibility(unit, visible)

	-- (the effects of the game's units, the staff's flame, are put out as the game does when it unwields: hidden units still show them)
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

-- (the mod is unloaded with a menu open: what it has in its worlds goes, the worlds are there)
mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
	for previewer in pairs(holding) do
		release_hero(previewer)
	end

	for previewer in pairs(inspecting) do
		release_item(previewer)
	end
end
