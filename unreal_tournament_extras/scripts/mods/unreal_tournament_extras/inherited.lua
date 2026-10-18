local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- /ut_inherited: what each of the mod's finished weapons still takes unchanged from the game weapon it is a copy of. Its template is
-- compared with the base item's template, part by part: a part that is the same in both is printed to the console log, on lines that
-- start with [ut_inherited], once for a whole table that is the same. A part the mod sets to the base's own value is printed too: this
-- can't tell it apart. The actions' lookup_data, which every copy changes, is left out.

-- The weapons that are not finished, by the start of their setting id
local UNFINISHED = {
	"assault_rifle",
	"sniper_rifle",
	"redeemer",
	"link_gun",
}

local function is_finished(setting_id)
	for _, prefix in ipairs(UNFINISHED) do
		if string.sub(setting_id, 1, #prefix) == prefix then
			return false
		end
	end

	return true
end

local IGNORED_KEYS = {
	lookup_data = true,
}

-- (deep enough for any weapon template, and a stop for a table that holds itself)
local MAX_DEPTH = 12

local function same(a, b, depth)
	depth = depth or 0

	if type(a) ~= "table" or type(b) ~= "table" or depth > MAX_DEPTH then
		return a == b
	end

	for key, value in pairs(a) do
		if not IGNORED_KEYS[key] and not same(value, b[key], depth + 1) then
			return false
		end
	end

	for key in pairs(b) do
		if not IGNORED_KEYS[key] and a[key] == nil then
			return false
		end
	end

	return true
end

local function short(value)
	if type(value) == "string" then
		return string.format("%q", value)
	elseif type(value) == "table" then
		return "{...}"
	end

	return tostring(value)
end

local function sorted_keys(tbl)
	local keys = {}

	for key in pairs(tbl) do
		if not IGNORED_KEYS[key] then
			keys[#keys + 1] = key
		end
	end

	table.sort(keys, function (a, b)
		return tostring(a) < tostring(b)
	end)

	return keys
end

-- Adds to lines each part of value that is the same as base's, by its path
local function walk(path, value, base, lines, depth)
	depth = depth or 0

	if type(value) == "table" and type(base) == "table" and depth <= MAX_DEPTH then
		if same(value, base) then
			lines[#lines + 1] = path .. " (all of it)"

			return
		end

		for _, key in ipairs(sorted_keys(value)) do
			walk(path .. "." .. tostring(key), value[key], base[key], lines, depth + 1)
		end
	elseif value ~= nil and value == base then
		lines[#lines + 1] = path .. " = " .. short(value)
	end
end

-- An action of the mod that the base has none of by its name (a new sub-action, made from a copy of one of the base's) is compared with
-- the base's sub-action that it shares the most parts with
local function closest_base_action(sub_action, base_actions)
	local best, best_name, best_count = nil, nil, 0

	for action_name, action in pairs(base_actions) do
		for sub_name, base_sub_action in pairs(action) do
			if type(base_sub_action) == "table" then
				local count = 0

				for key, value in pairs(sub_action) do
					if not IGNORED_KEYS[key] and same(value, base_sub_action[key]) then
						count = count + 1
					end
				end

				if count > best_count then
					best, best_name, best_count = base_sub_action, action_name .. "." .. sub_name, count
				end
			end
		end
	end

	return best, best_name
end

local function walk_actions(actions, base_actions, lines)
	for _, action_name in ipairs(sorted_keys(actions)) do
		local action = actions[action_name]

		for _, sub_name in ipairs(sorted_keys(action)) do
			local sub_action = action[sub_name]
			local base_sub_action = base_actions[action_name] and base_actions[action_name][sub_name]
			local path = ".actions." .. action_name .. "." .. sub_name

			if type(sub_action) == "table" then
				if base_sub_action then
					walk(path, sub_action, base_sub_action, lines)
				else
					local closest, closest_name = closest_base_action(sub_action, base_actions)

					if closest then
						lines[#lines + 1] = path .. " is new; compared with the base's " .. closest_name

						walk(path, sub_action, closest, lines)
					else
						lines[#lines + 1] = path .. " is new, and like none of the base's"
					end
				end
			end
		end
	end
end

mod:command("ut_inherited", "- prints to the console log what the finished weapons still take unchanged from their base weapons", function ()
	local setting_ids = sorted_keys(ut.items.weapons)
	local count = 0

	for _, setting_id in ipairs(setting_ids) do
		local definition = ut.items.weapons[setting_id]

		if is_finished(setting_id) then
			local base_name = ItemMasterList[definition.base_item].template
			local template = rawget(Weapons, definition.template)
			local base = rawget(Weapons, base_name)
			local lines = {}

			-- (everything but the actions, then the actions one by one)
			for _, key in ipairs(sorted_keys(template)) do
				if key ~= "actions" then
					walk("." .. tostring(key), template[key], base[key], lines)
				end
			end

			walk_actions(template.actions or {}, base.actions or {}, lines)

			print(string.format("[ut_inherited] == %s (%s), a copy of %s (%s): %d parts", setting_id, definition.template, definition.base_item, base_name, #lines))

			for _, line in ipairs(lines) do
				print("[ut_inherited] " .. setting_id .. line)
			end

			count = count + 1
		end
	end

	mod:echo("[ut_inherited] %d weapons printed to the console log", count)
end)
