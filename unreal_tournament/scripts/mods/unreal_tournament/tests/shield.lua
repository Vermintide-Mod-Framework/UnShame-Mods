local mod = get_mod("unreal_tournament")

-- The Shield Gun's in-game tests (see runner.lua). Run them with /ut_test shield (Kruber's), shield_dr, shield_bw, shield_wh, shield_we
-- and shield_priest. They run in the runner's level, Righteous Stand.

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
				local target = t.spawn_target(1.5)

				if not t.expect(target, "the target could not be spawned") then
					return
				end

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
			name = "a punch while moving fast does more damage",
			run = function (t)
				if mod:get("ut_movement") == false or not mod:get("momentum_damage") then
					t.skip("the movement or its momentum damage is turned off")
				end

				-- A punch standing still, and one in a dodge forward at the enemy (about 7 m/s). Each is done four times, and the least
				-- of the ones that hit is taken, as a punch can be a critical hit. The bonus is the movement's (25% at 9 m/s, none up to
				-- 4.5 m/s), most of which has to show.
				local function punch(moving)
					local target = t.spawn_target(moving and 4 or 1.5)

					if not target then
						return nil
					end

					local damage = t.track_damage(target)
					local speed

					if moving then
						t.look(0)
						t.move(0, 1)
						t.tap("dodge")
						t.move()
						t.wait(0.1)
					end

					t.press("action_one", 0.1)
					t.watch(0.8, function ()
						if not speed and damage.total > 0 then
							local vx, vy = t.velocity()

							speed = math.sqrt(vx * vx + vy * vy)
						end
					end)
					t.remove(target)
					t.go_to_start()
					t.wait(0.7)

					return damage.total, speed
				end

				local standing, moving, speed = math.huge, math.huge, math.huge

				for _ = 1, 4 do
					local damage, at = punch(false)

					if damage and damage > 0 then
						standing = math.min(standing, damage)
					end

					damage, at = punch(true)

					if damage and damage > 0 then
						moving = math.min(moving, damage)
						speed = math.min(speed, at)
					end
				end

				local bonus = 0.25 * math.max(speed - 4.5, 0) / 4.5

				t.expect(standing < math.huge and moving < math.huge, "no punch hit")
				t.expect(speed > 4.5, "the punch in a dodge came at %.1f m/s, too slow for a bonus", speed)
				t.expect(moving >= standing * (1 + bonus * 0.7), "a punch at %.1f m/s did %.1f, %.0f%% more than one standing (%.1f), not %.0f%%", speed, moving, (moving / standing - 1) * 100, standing, bonus * 100)
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
