local mod = get_mod("unreal_tournament_extras")
local ut = get_mod("unreal_tournament")

-- Checks that the game's effects the mod plays are loaded (see runner.lua). Run it with /ut_test effects. The mod plays them without
-- checking, and playing an effect that isn't loaded crashes the game, so each must be in a package the game always loads. The career is
-- one that none of the effects belongs to, so an effect that only comes with a career or a weapon fails here.

local runner = mod.test_runner

local function scenarios()
	return {
		{
			name = "the game's effects are loaded",
			run = function (t)
				local names = table.keys(ut.effects.game_effects)

				table.sort(names)
				t.expect(#names > 0, "the mod names no game effects")

				for _, name in ipairs(names) do
					local loaded = t.on_main_thread(function ()
						return Application.can_get("particles", name)
					end)

					t.expect(loaded, "%s is not loaded", name)
				end
			end,
		},
	}
end

-- (Bardin's copy, on the Grudge-raker: Kruber's is on the Blunderbuss, whose wield animation Bardin doesn't have)
local definition = ut.items.weapons.flak_cannon_dr

runner.add_suite({
	name = "effects",
	item = definition.key,
	template = definition.template,
	slot = "slot_ranged",
	careers = { "dr_ironbreaker" },
	scenarios = scenarios(),
})
