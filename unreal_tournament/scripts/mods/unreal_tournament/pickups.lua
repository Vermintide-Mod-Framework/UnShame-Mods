local mod = get_mod("unreal_tournament")

-- More ammo in the level: the game works out how many pickups of each kind a level gets (its settings for the
-- difficulty, with the multipliers of the mutators that are on), and this scales the ammo among them. The
-- pickups are still put where the level has places for them, so a level with few places can't get as many as
-- the setting says. Only the host's game decides what a level gets.

local AMMO_MULTIPLIER = 4

local function scale(amount, multiplier)
	return math.ceil(amount * multiplier)
end

mod:hook(MutatorHandler, "pickup_settings_updated_settings", function (func, self, pickup_settings)
	local updated_settings = func(self, pickup_settings)
	if not updated_settings or not mod:get("more_ammo_pickups") then
		return updated_settings
	end

	local multiplier = AMMO_MULTIPLIER

	-- (what the game gives back is a copy, it is changed in place)
	local ammo = updated_settings.ammo

	if type(ammo) == "table" then
		for pickup_name, amount in pairs(ammo) do
			ammo[pickup_name] = scale(amount, multiplier)
		end
	elseif type(ammo) == "number" then
		updated_settings.ammo = scale(ammo, multiplier)
	end

	return updated_settings
end)
