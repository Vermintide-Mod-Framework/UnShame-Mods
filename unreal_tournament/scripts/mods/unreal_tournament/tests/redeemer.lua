local mod = get_mod("unreal_tournament")

-- The Redeemer's in-game tests (see runner.lua). Run them with /ut_test redeemer. They run in the level the player is in, which is the
-- Keep.

local runner = mod.test_runner

-- The blasts that are made while a test runs: each wave's explosion, by its template
local blasts = {}
local recording = false

mod.any_explosion_callbacks.ut_test_redeemer = function (explosion_template)
	if recording and string.find(explosion_template.name, "ut_redeemer_wave_", 1, true) then
		blasts[#blasts + 1] = explosion_template.name
	end
end

local function scenarios()
	return {
		{
			name = "holds one missile",
			run = function (t)
				t.expect(t.ammo() == 1, "the Redeemer holds %s missiles, not 1", tostring(t.ammo()))
			end,
		},
		{
			name = "fire and blast",
			run = function (t)
				table.clear(blasts)

				recording = true

				-- The missile flies until it hits the ground in front of the player, and then the blast's six waves come over 1.3 s
				t.press("action_one", 0.1)
				t.wait(6)

				recording = false

				t.expect(t.ammo() == 0, "the shot did not use the missile: %s left", tostring(t.ammo()))
				t.expect(#blasts == 6, "%d waves of the blast were made, not 6 (%s)", #blasts, table.concat(blasts, ", "))
			end,
		},
	}
end

local definition = mod.items.weapons.redeemer

runner.add_suite({
	name = "redeemer",
	item = definition.key,
	template = definition.template,
	slot = "slot_ranged",
	careers = { "dr_ironbreaker" },
	scenarios = scenarios(),
})
