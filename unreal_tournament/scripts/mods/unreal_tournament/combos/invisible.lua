local mod = get_mod("unreal_tournament")

-- The Invisible combo (ComboInvis). The character is invisible as the game makes the Shade invisible (set_invisible): enemies lose
-- track of it. It looks as UT draws an invisible pawn (xPawn.SetInvisibility):
--   the body is replaced by UT's invisible material (InvisMaterial): the game's fade hides the body and hats, and a copy of each,
--   in the invisible material, takes their place;
--   the weapons keep their look, with the invisible material drawn over them (Weapon.OverlayMaterial): a copy of each, in the
--   invisible material, is drawn over it. That covers the weapon in the hand, the game's or a UT skin's, and the player's own first
--   person arms and weapon.
-- A copy is the same unit, with each of its nodes linked to the same node of the original, so it moves and bends with it. The engine
-- can replace a unit's materials but not give them back, so the originals are never changed. A copy is shown or hidden whenever its
-- original is.

local utils = mod.utils
local combos = mod.combos

local CONFIG = {
	-- (units/ut/fx/fx_invisible and fx_weapon_invisible, made by tools/asset_conversion/make_combo_materials.py)
	material = "units/ut/fx/fx_invisible",
	first_person_material = "units/ut/fx/fx_weapon_invisible",
	-- The reason the game is given for the invisibility
	reason = "ut_combo_invisible",
	-- How often the units of an invisible character are looked at again, for a weapon that was changed
	refresh_interval = 0.1, -- s
	-- The game's fade of the body: 1 hides it all
	body_fade = 1,
}

-- Whether each unit was last shown or hidden, and its visibility groups. The engine can set these but can't tell them, so the game's
-- calls are watched. A unit that was never set is shown.
local shown = setmetatable({}, {
	__mode = "k",
})
local groups = setmetatable({}, {
	__mode = "k",
})

-- The copy of each original
local copy_of = {}

mod:hook_safe(Unit, "set_unit_visibility", function (unit, visible)
	shown[unit] = visible

	local copy = copy_of[unit]

	if copy and Unit.alive(copy) then
		Unit.set_unit_visibility(copy, visible)
	end
end)

mod:hook_safe(Unit, "set_visibility", function (unit, group, visible)
	groups[unit] = groups[unit] or {}
	groups[unit][group] = visible

	local copy = copy_of[unit]

	if copy and Unit.alive(copy) and Unit.has_visibility_group(copy, group) then
		Unit.set_visibility(copy, group, visible)
	end
end)

-- Each invisible character's: { copies = { [original] = copy }, next_refresh, owner }
local cloaked = {}

local function make_copy(world, original, unit_name, material)
	if not unit_name or not Unit.alive(original) or not Unit.is_a(original, unit_name) then
		return nil
	end

	local copy = World.spawn_unit(world, unit_name, Unit.world_position(original, 0), Unit.world_rotation(original, 0))

	copy_of[original] = copy

	Unit.disable_physics(copy)
	Unit.set_all_materials(copy, material)

	for i = 0, Unit.num_scene_graph_items(copy) - 1 do
		World.link_unit(world, copy, i, original, i)
	end

	-- (the copy's level of detail follows the original's, as the game does for a hat)
	if Unit.num_lod_objects(original) ~= 0 and Unit.num_lod_objects(copy) ~= 0 then
		LODObject.set_bounding_volume(Unit.lod_object(copy, 0), LODObject.bounding_volume(Unit.lod_object(original, 0)))
	end

	for group, visible in pairs(groups[original] or {}) do
		if Unit.has_visibility_group(copy, group) then
			Unit.set_visibility(copy, group, visible)
		end
	end

	Unit.set_unit_visibility(copy, shown[original] ~= false)

	return copy
end

local function remove_copy(world, original, copy)
	if copy_of[original] == copy then
		copy_of[original] = nil
	end

	if Unit.alive(copy) then
		World.unlink_unit(world, copy)
		World.destroy_unit(world, copy)
	end
end

-- The name of the unit a hero's weapon slot has in a hand ("right" or "left"), in third person or first
local function weapon_unit_name(character, slot_data, hand, first_person)
	if not slot_data.item_data then
		return nil
	end

	local player = Managers.player:owner(character)
	local career_name = player and player.career_name and player:career_name()
	local ok, units = pcall(BackendUtils.get_item_units, slot_data.item_data, nil, slot_data.skin, career_name)
	local name = ok and units and units[hand .. "_hand_unit"]

	return name and (first_person and name or name .. "_3p")
end

-- The units of a character to copy now, as [original] = { name, material }
local function originals(character)
	local list = {}
	local cosmetic_extension = ScriptUnit.has_extension(character, "cosmetic_system")
	local skin = cosmetic_extension and cosmetic_extension:get_equipped_skin()
	local profile = cosmetic_extension and cosmetic_extension._profile

	local function add(unit, name, material)
		if unit and name and Unit.alive(unit) then
			list[unit] = { name = name, material = material }
		end
	end

	-- The body and the hats
	if skin and profile then
		local attachment = skin.third_person_attachment or profile.third_person_attachment

		add(cosmetic_extension:get_third_person_mesh_unit(), attachment and attachment.unit, CONFIG.material)
	end

	local attachment_extension = ScriptUnit.has_extension(character, "attachment_system")
	local attachments = attachment_extension and attachment_extension:attachments()

	for _, slot_data in pairs(attachments and attachments.slots or {}) do
		local ok, units = pcall(BackendUtils.get_item_units, slot_data.item_data)

		add(slot_data.unit, ok and units and units.unit, CONFIG.material)
	end

	-- The weapon in the hands, the game's
	local inventory_extension = ScriptUnit.has_extension(character, "inventory_system")
	local equipment = inventory_extension and inventory_extension:equipment()
	local slot_data = equipment and equipment.wielded_slot and equipment.slots[equipment.wielded_slot]
	local own = utils.is_local_player_unit(character)

	if slot_data then
		add(equipment.right_hand_wielded_unit_3p, weapon_unit_name(character, slot_data, "right"), CONFIG.material)
		add(equipment.left_hand_wielded_unit_3p, weapon_unit_name(character, slot_data, "left"), CONFIG.material)

		if own then
			add(equipment.right_hand_wielded_unit, weapon_unit_name(character, slot_data, "right", true), CONFIG.first_person_material)
			add(equipment.left_hand_wielded_unit, weapon_unit_name(character, slot_data, "left", true), CONFIG.first_person_material)
		end
	end

	-- The player's own first person arms
	local first_person_extension = own and ScriptUnit.has_extension(character, "first_person_system")

	if first_person_extension and skin and profile then
		local attachment = skin.first_person_attachment or profile.first_person_attachment

		add(first_person_extension:get_first_person_mesh_unit(), attachment and attachment.unit, CONFIG.first_person_material)
	end

	-- The UT skins' models
	for _, entry in ipairs(mod.weapon_skin.units_of(character)) do
		add(entry.unit, entry.unit_name, entry.first_person and CONFIG.first_person_material or CONFIG.material)
	end

	return list
end

local function set_body_fade(character, fade)
	local fade_system = Managers.state.entity:system("fade_system")

	if fade_system and Unit.alive(character) then
		fade_system:set_min_fade(character, fade)
	end
end

-- Makes copies of the units that have none, and takes away those of units that are gone or no longer the character's
local function refresh(character, entry)
	local world = Managers.world:world("level_world")
	local wanted = originals(character)

	for original, copy in pairs(entry.copies) do
		if not wanted[original] or not Unit.alive(original) or not Unit.alive(copy) then
			remove_copy(world, original, copy)

			entry.copies[original] = nil
		end
	end

	for original, data in pairs(wanted) do
		if not entry.copies[original] then
			entry.copies[original] = make_copy(world, original, data.name, data.material)
		end
	end

	-- (the game sets its own fade as another machine tells it the character is invisible, so it is set again here)
	set_body_fade(character, CONFIG.body_fade)
end

local function uncloak(character)
	local entry = cloaked[character]

	if not entry then
		return
	end

	cloaked[character] = nil

	local world = Managers.world:has_world("level_world") and Managers.world:world("level_world")

	for original, copy in pairs(entry.copies) do
		if world then
			remove_copy(world, original, copy)
		end
	end

	set_body_fade(character, 0)
end

local function set_invisible(character, invisible)
	local status_extension = ScriptUnit.has_extension(character, "status_system")

	if status_extension then
		status_extension:set_invisible(invisible, nil, CONFIG.reason)
	end
end

combos.kinds.invisible = {
	start = function (unit, owner)
		-- (the game's invisibility is set by the machine that runs the character, which tells the others)
		if owner then
			set_invisible(unit, true)
		end

		cloaked[unit] = {
			copies = {},
			next_refresh = 0,
			owner = owner,
		}
	end,
	stop = function (unit, owner)
		if owner and Unit.alive(unit) then
			set_invisible(unit, false)
		end

		uncloak(unit)
	end,
	update = function (unit)
		local entry = cloaked[unit]
		local t = Managers.time:time("game")

		if entry and t >= entry.next_refresh then
			entry.next_refresh = t + CONFIG.refresh_interval

			refresh(unit, entry)
		end
	end,
}

local function uncloak_all()
	for character in pairs(cloaked) do
		uncloak(character)
	end

	table.clear(copy_of)
end

-- The copies are taken away before the level's world goes
mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = uncloak_all

-- and before the mod's package goes (copies of its units). The characters this machine runs are made visible again.
mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
	for character, entry in pairs(cloaked) do
		if entry.owner and Unit.alive(character) then
			set_invisible(character, false)
		end
	end

	uncloak_all()
end
