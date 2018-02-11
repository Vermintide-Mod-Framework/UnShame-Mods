--[[
	You may no longer get copies of trinkets (and hats!) you already own from the loot table at the end of a level, unless you've got them all.
	Author: UnShame
]]--

local mod = get_mod("unique_trinkets_on_loot_table")

-- Awards a replacement item and returns its key and backend id if the given item is a trinket or an exotic hat and is a dupe
function mod.get_missing_item(key, id)

	local item = ItemMasterList[key]
	local slot_type = item.slot_type
	local rarity = item.rarity

	if slot_type == "trinket" or slot_type == "hat" and rarity == "exotic" then 
		local new_key = mod.get_missing_item_key(slot_type, rarity, key)
		if new_key and new_key ~= key then
			--EchoConsole(new_key)
			BackendUtils.remove_item(id)
			ScriptBackendItem.award_item(new_key)
			Managers.backend:commit()
			key = new_key
			id = mod.get_item_id_from_key(key) or id
		end
	end

	return key, id
end

-- Gets backend id of an item by key
-- This will probably fail since backend:commit is seems to be async but it doesn't really matter
function mod.get_item_id_from_key(key)
	local item = ItemMasterList[key]
	local item_id_list = ScriptBackendItem.get_items(item.can_wield[1], item.slot_type)

	for i, backend_id in ipairs(item_id_list) do
		local other_key = ScriptBackendItem.get_key(backend_id)
		local item_data = ItemMasterList[other_key]

		if other_key == key and backend_id ~= 0 then
			return backend_id
		end
	end

	return nil
end

-- Gets key and backend id of a replacement item if the given item is a dupe
function mod.get_missing_item_key(slot, rarity, key)

	-- Get backend ids for all relevant items
	local profiles = {
		"bright_wizard",
		"dwarf_ranger",
		"empire_soldier",
		"witch_hunter",
		"wood_elf"
	}
	local item_id_list = {}
	for _, profile in ipairs(profiles) do
		local item_id_list_profile = ScriptBackendItem.get_items(profile, slot)
		for __, backend_id in ipairs(item_id_list_profile) do
			item_id_list[#item_id_list + 1] = backend_id
		end
	end
	--EchoConsole("item_id_list " .. tostring(#item_id_list))

	-- Get item data for all relevant items
	local items = {}
	for i, backend_id in ipairs(item_id_list) do
		local other_key = ScriptBackendItem.get_key(backend_id)
		local item_data = ItemMasterList[other_key]
		if item_data.rarity == rarity and (not item_data.dlc or Managers.unlock:is_dlc_unlocked(item_data.dlc)) then
			--EchoConsole(tostring(other_key))
			items[other_key] = item_data
		end
	end

	-- Get new key if it's a dupe
	for other_key, item_data in pairs(items) do
		if other_key == key then
			key = mod.get_missing_item_key_from_master_list(other_key, item_data, items)
			break
		end
	end

	return key
end

-- Gets key of a replacement item if player has missing items
function mod.get_missing_item_key_from_master_list(key, item_data, items)

	local slot_type = item_data.slot_type
	local rarity = item_data.rarity

	local missing_items = {}

	for other_key, other_item_data in pairs(ItemMasterList) do
		if other_item_data.slot_type == slot_type and other_item_data.rarity == rarity and not items[other_key] then
			missing_items[#missing_items + 1] = other_key
		end
	end

	if #missing_items > 0 then
		key = missing_items[Math.random(#missing_items)]
	end

	--EchoConsole(key .. " " .. tostring(#missing_items))

	return key
end

--[[
	Hooks
--]] 

-- Replace reward trinkets and exotic hats that the player already owns with ones he doesn't have yet
mod:hook("EndOfLevelUI.update_dice_rolling_results", function(func, self, dt)

	local level_dice_roller = self.level_dice_roller

	level_dice_roller.update(level_dice_roller, dt)

	if not self.successes then
		local num_successes = level_dice_roller.num_successes(level_dice_roller)
		local win_list = level_dice_roller.win_list(level_dice_roller)
		self._num_dice_successes = num_successes
		self.successes = level_dice_roller.successes(level_dice_roller)
		self.dice_types = level_dice_roller.dice(level_dice_roller)
		self.reward_item_key = self.reward_item_key or level_dice_roller.reward_item_key(level_dice_roller)
		self.reward_item_backend_id = self.reward_item_backend_id or level_dice_roller.reward_backend_id(level_dice_roller)

		--self.reward_item_key = "bw_gate_0003"

		-- Try replacing the item with a missing one
		self.reward_item_key, self.reward_item_backend_id = mod.get_missing_item(self.reward_item_key, self.reward_item_backend_id)

		self.views.dice_game:set_reward_values(num_successes, self.dice_types, win_list, self.reward_item_key, self.reward_item_backend_id)
	end

	if not self.dice_simulation_complete then
		self.dice_simulation_complete = level_dice_roller.simulate_dice_rolls(level_dice_roller, self.successes)
	end

	return self.successes and self.dice_simulation_complete
end)

--[[
	Callback
--]] 

mod.suspended = function()
	mod:disable_all_hooks()
end

mod.unsuspended = function()
	mod:enable_all_hooks()
end

--[[
	Execution
--]] 

-- Add option to mod settings menu (args: 1 = widget table, 2 = presence of checkbox in mod settings, 3 = descriptive name, 4 = description)
mod:create_options({}, true, "Loot Table: Unique Trinkets", "You may no longer get copies of trinkets (and hats!) you already own from the loot table at the end of a level, unless you've got them all.")

-- Check for suspend setting
if mod:is_suspended() then
	mod.suspended()
end
