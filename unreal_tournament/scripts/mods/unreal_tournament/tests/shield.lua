local mod = get_mod("unreal_tournament")

-- The Shield Gun's in-game tests (see runner.lua). Run them with /ut_test shield (Kruber's), shield_dr, shield_bw, shield_wh, shield_we
-- and shield_priest. They run in the level the player is in, which is the Keep.

local runner = mod.test_runner
local shield = mod.shield

local function scenarios()
	return {
		{
			name = "charge and punch",
			run = function (t)
				local before = shield.last_punch
				local charged = false

				-- Held for a second, the gun charges, and let go it punches
				t.press("action_one", 1, function ()
					if shield.charge_started then
						charged = true
					end
				end)
				t.wait(0.2)

				t.expect(charged, "the gun did not charge while the button was held")
				t.expect(shield.last_punch ~= before, "the gun did not punch when the button was let go")
				t.expect(shield.charge_started == nil, "the charge did not end with the punch")
			end,
		},
		{
			name = "punches by itself near an enemy",
			run = function (t)
				local target = t.spawn("chaos_marauder", 1.5)

				if not t.expect(target, "the target could not be spawned") then
					return
				end

				t.wait(1)

				local before = shield.last_punch
				local punched_while_held = false

				t.press("action_one", 1.5, function ()
					if shield.last_punch ~= before then
						punched_while_held = true
					end
				end)

				t.expect(punched_while_held, "the gun did not punch by itself with an enemy in reach")
			end,
		},
		{
			name = "block",
			run = function (t)
				local blocked = false

				t.press("action_two", 0.6, function ()
					local status_extension = ScriptUnit.has_extension(t.unit(), "status_system")

					if status_extension and status_extension:is_blocking() then
						blocked = true
					end
				end)

				t.expect(blocked, "the right button did not raise the shield (block)")
			end,
		},
	}
end

for _, variant in ipairs({
	{ name = "shield", setting_id = "shield_gun", careers = { "es_mercenary", "es_knight" } },
	{ name = "shield_dr", setting_id = "shield_gun_dr", careers = { "dr_ironbreaker", "dr_slayer" } },
	{ name = "shield_bw", setting_id = "shield_gun_bw", careers = { "bw_adept" } },
	{ name = "shield_wh", setting_id = "shield_gun_wh", careers = { "wh_captain" } },
	{ name = "shield_we", setting_id = "shield_gun_we", careers = { "we_shade" } },
	{ name = "shield_priest", setting_id = "shield_gun_priest", careers = { "wh_priest" } },
}) do
	local definition = mod.items.weapons[variant.setting_id]

	runner.add_suite({
		name = variant.name,
		item = definition.key,
		template = definition.template,
		slot = "slot_melee",
		careers = variant.careers,
		scenarios = scenarios(),
	})
end
