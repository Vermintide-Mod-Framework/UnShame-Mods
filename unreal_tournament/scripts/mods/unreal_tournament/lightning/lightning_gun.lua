local mod = get_mod("unreal_tournament")

-- Lightning Gun: Kerillian's, a copy of the Deepwood Staff with its fire modes replaced, the same way the Shock Rifle is a copy of the
-- Beam Staff. The numbers come from UT2004 (XWeapons/SniperRifle, SniperFire and SniperZoom).
--   Left button: fires a lightning bolt that hits at once. After it hits, three short arcs of lightning jump from the place it hit
--       to enemies near it. A hit on the head does double damage.
--   Right button: zooms. Holding it zooms in, until it is let go, and the zoom stays. Pressing it again zooms out.
--   Reload: vents the heat, as the staff does.
-- UT's Lightning Gun has 40 rounds of ammo. Here a bolt adds heat instead, as much as the Beam Staff's charged shot, and overheating
-- is the Deepwood Staff's: the player loses part of their health and the gun is locked out while the heat cools.
-- The staff is the Sister of the Thorn's only, so the copy is given to all four of Kerillian's careers. They have the same third person
-- body (way_watcher), whose animations the staff uses. The skin (skin.lua) draws all of it, and this file only sets what it does to
-- the game.

local utils = mod.utils
local register_damage_profile = utils.register_damage_profile
local make_flat = utils.make_flat
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for
local first_beam_hit = utils.first_beam_hit

local DESCRIPTION = "The Lightning Gun is a high-power energy rifle capable of ablating even the heaviest carapace armor. Acquisition of a target at long range requires a steady hand, but the anti-jitter effect of the optical system reduces the weapon's learning curve significantly."

-- Kerillian's careers. The Sister of the Thorn is the staff's own.
local CAREERS = { "we_shade", "we_maidenguard", "we_waywatcher", "we_thornsister" }

local SETTING_ID = "lightning_gun"
local ITEM_KEY = "ut_lightning_gun"
local TEMPLATE_NAME = "ut_lightning_gun_template"

mod.items.register(SETTING_ID, {
	key = ITEM_KEY,
	template = TEMPLATE_NAME,
	base_item = "we_life_staff",
	deus_copy = "deus_we_life_staff",
	can_wield = CAREERS,
	name = "UT2004 Lightning Gun",
	type_name = "Lightning Gun",
	description = DESCRIPTION,
	keywords = { "weapon_keyword_high_damage", "weapon_keyword_sniper", "weapon_keyword_overheat" },
	icon = "ut_lightning_gun_icon",
	icon_package = "resource_packages/unreal_tournament/icons",
	icon_materials = "ui/ut/lightning_gun_icon",
})

local TEMPLATE_NAMES = {
	[TEMPLATE_NAME] = true,
}

local CONFIG = {
	-- The heat of a bolt: the Beam Staff's charged shot's (8 of the 40 a player can take), so five bolts heat the gun to the top and a
	-- sixth overheats it. UT's gun has 40 rounds instead.
	bolt_overcharge = PlayerUnitStatusSettings.overcharge_values.beam_staff_sniper,
	-- Every career of Kerillian overheats as the Sister of the Thorn does with the staff (her OverchargeData): she loses 40% of her
	-- health, the staff is locked out until the heat is gone, and there is no explosion. The other careers have no data of their own,
	-- which would make them overheat as Sienna does, losing all of their health.
	overheat_like = "we_thornsister",
	-- SniperFire.FireRate. After a shot, the next one can be made once this much time has passed.
	fire_rate = 1.6,
	chain_margin = 0.15, -- seconds
	-- The damage is in UT2004's units, where 45 is the shock rifle's beam. SniperFire.DamageMin and DamageMax are 70.
	damage = 70,
	-- SniperFire.HeadShotDamageMult
	headshot_multiplier = 2,
	-- The multipliers of the damage and the stagger for each armor type: unarmored, armored, monsters, players, berserkers and super
	-- armor. UT has no armor, and the bolt is said to ablate even the heaviest carapace. The game's own multiplier for beams is 0
	-- against super armor, which chaos warriors have.
	armor_attack = {1, 1, 1.2, 1, 1, 0.6},
	armor_impact = {1, 1, 1, 1, 1, 0.6},
	-- How far a bolt that hits nothing goes, in meters. UT's SniperFire.TraceRange is 17000 units.
	bolt_range = 100,
	-- The arcs (SniperFire.NumArcs, SecDamageMult and SecTraceDist: 3 arcs of 300 units that do half the damage). They start a little
	-- off the surface the bolt hit (2 units) and go in random directions.
	arc_count = 3,
	arc_damage_multiplier = 0.5,
	arc_range = 6, -- m
	arc_start_offset = 0.04, -- m
	-- An arc goes for an enemy within this of where the bolt hit, the nearest first and one each, and the arcs left over go in random
	-- directions, as UT's all do. This is the mod's own: UT's arcs only hit what happens to be in their way. A choice, half their range.
	arc_seek_range = 3, -- m
	-- How far a bot shoots from, in meters
	bot_max_range = 60,
	-- The camera shake of a shot is the handgun's recoil, scaled by this.
	recoil_scale = 0.5,
}

local TOTAL_TIME = CONFIG.fire_rate + CONFIG.chain_margin

PlayerUnitStatusSettings.overcharge_values.ut_lightning_bolt = CONFIG.bolt_overcharge

-- The overheating of the Sister of the Thorn for the careers that have none of their own. The game reads it when it spawns a
-- character, so a career has it from its next spawn.
local overheat_given = {}

for _, career_name in ipairs(CAREERS) do
	if not OverchargeData[career_name] then
		OverchargeData[career_name] = table.clone(OverchargeData[CONFIG.overheat_like])
		overheat_given[#overheat_given + 1] = career_name
	end
end

mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
	for _, career_name in ipairs(overheat_given) do
		OverchargeData[career_name] = nil
	end
end

-- Spread: the bolt hits exactly where the crosshair is.
utils.zero_spread_template("ut_lightning_bolt", "handgun")

-- Damage profiles
-- The bolt stops at the first enemy it hits, as UT's trace does. A profile with a cleave that is tiny hurts one enemy.

local function set_armor_modifiers(profile)
	utils.set_armor_modifiers(profile, CONFIG.armor_attack, CONFIG.armor_impact)
end

register_damage_profile("ut_lightning_bolt", "shot_sniper", function (profile)
	make_flat(profile, attack_power_for(CONFIG.damage), impact_power_for(CONFIG.damage), "shot_sniper")

	profile.cleave_distribution = {
		attack = 0.01,
		impact = 0.01,
	}
	set_armor_modifiers(profile)
	utils.set_headshot_multiplier(profile, CONFIG.headshot_multiplier)
end)

-- An arc does half of the bolt's damage. It never hits the head, as in UT, where only the first trace looks for a head shot.
register_damage_profile("ut_lightning_arc", "shot_sniper", function (profile)
	make_flat(profile, attack_power_for(CONFIG.damage * CONFIG.arc_damage_multiplier), impact_power_for(CONFIG.damage * CONFIG.arc_damage_multiplier), "shot_sniper")

	profile.cleave_distribution = {
		attack = 0.01,
		impact = 0.01,
	}
	set_armor_modifiers(profile)
end)

-- The bolt and the arcs have no hit effect of their own. Without this, the game would play the sound, particles and decals of the
-- surface that is hit. The skin draws the impact instead (see mod.silent_hit_effects in hooks.lua).
local NO_HIT_EFFECT = "ut_lightning_impact"

mod.silent_hit_effects[NO_HIT_EFFECT] = true

-- The flow events of the game's handgun shot that start its tracer (ActionHandgun.client_owner_post_update)
local DROPPED_FLOW_EVENTS = {
	lua_bullet_trail = true,
	lua_bullet_trail_set = true,
}

-- What an arc is, to the game's hit processing: an action with the profile of the arc.
local ARC_ACTION = {
	damage_profile = "ut_lightning_arc",
	hit_effect = NO_HIT_EFFECT,
	ignore_shield_hit = true,
}

-- Weapon template

-- The actions that can follow a shot. Holding the button repeats the shot, as in UT, and the heat can be vented. The zoom is not an
-- action.
local function fire_chain_actions()
	local entries = {
		{
			action = "action_wield",
			input = "action_wield",
			start_time = 0.4,
			sub_action = "default",
		},
		{
			action = "weapon_reload",
			input = "weapon_reload",
			start_time = 0.4,
			sub_action = "default",
		},
	}

	for _, input in ipairs({ "action_one", "action_one_hold" }) do
		entries[#entries + 1] = {
			action = "action_one",
			input = input,
			start_time = CONFIG.fire_rate,
			sub_action = "default",
		}
	end

	return entries
end

-- Builds the shot from Kruber's handgun's, which hits at once, with its recoil. It adds heat instead of using ammo, can't be fired while
-- the gun is locked out, and can be repeated after UT's fire time. The animation of the characters is the staff's shot.
local function build_shot(original)
	local action = table.clone(original)

	action.active_reload_time = nil
	action.allowed_chain_actions = fire_chain_actions()
	action.ammo_usage = nil
	action.anim_event = "attack_shoot"
	action.anim_event_last_ammo = nil
	action.anim_event_no_ammo_left = nil
	action.anim_event_secondary = nil
	action.overcharge_type = "ut_lightning_bolt"
	-- (the staff is the left hand's, as its own actions say)
	action.weapon_action_hand = "left"
	action.condition_func = function (action_user)
		local overcharge_extension = ScriptUnit.extension(action_user, "overcharge_system")

		return overcharge_extension:are_you_locked_out() == false
	end
	action.chain_condition_func = action.condition_func
	action.damage_profile = "ut_lightning_bolt"
	action.headshot_multiplier = CONFIG.headshot_multiplier
	action.hit_effect = NO_HIT_EFFECT
	action.ignore_shield_hit = true
	action.reload_when_out_of_ammo = false
	action.spread_template_override = "ut_lightning_bolt"
	-- The shot lasts slightly longer than the time to the next shot. A held button is only read while a shot is still running, so a shot
	-- that ends exactly when the next one may start would miss it.
	action.total_time = TOTAL_TIME
	action.total_time_secondary = nil
	action.ut_lightning_bolt = true
	-- The game's tracer is not drawn: the bolt is the skin's (hooks.lua)
	action.ut_dropped_flow_events = DROPPED_FLOW_EVENTS

	if action.recoil_settings then
		action.recoil_settings.vertical_climb = action.recoil_settings.vertical_climb * CONFIG.recoil_scale
	end

	return action
end

-- The template is shared game state, so it is patched in place. What is changed is saved, and it is put back when the mod is disabled
-- or unloaded.
local saved = {}

local ATTACK_META_DATA_FIELDS = {
	"can_charge_shot",
	"charged_attack_action_name",
	"max_range",
}

-- The template's own fields that are replaced
local TEMPLATE_FIELDS = {
	"crosshair_style",
	"on_wield",
	"synced_states",
	"tooltip_compare",
	"tooltip_detail",
}

local function restore_staff(template_name)
	local original = saved[template_name]
	local template = rawget(Weapons, template_name)

	if not original or not template then
		return
	end

	template.actions.action_one = original.action_one
	template.actions.action_two = original.action_two

	for _, field in ipairs(TEMPLATE_FIELDS) do
		template[field] = original[field]
	end

	for _, field in ipairs(ATTACK_META_DATA_FIELDS) do
		template.attack_meta_data[field] = original.attack_meta_data[field]
	end

	saved[template_name] = nil
end

local function apply_staff(template_name)
	local template = rawget(Weapons, template_name)

	if not template then
		return
	end

	-- The chart of the item's stats, from 0 to 7. The bolt is the normal attack.
	template.weapon_diagram = {
		light_attack = {
			[DamageTypes.ARMOR_PIERCING] = 6,
			[DamageTypes.CLEAVE] = 1,
			[DamageTypes.SPEED] = 2,
			[DamageTypes.STAGGER] = 4,
			[DamageTypes.DAMAGE] = 7,
		},
		heavy_attack = {
			[DamageTypes.ARMOR_PIERCING] = 0,
			[DamageTypes.CLEAVE] = 0,
			[DamageTypes.SPEED] = 0,
			[DamageTypes.STAGGER] = 0,
			[DamageTypes.DAMAGE] = 0,
		},
	}

	local actions = template.actions
	local attack_meta_data = template.attack_meta_data
	local original = {
		action_one = actions.action_one,
		action_two = actions.action_two,
		attack_meta_data = {},
	}

	for _, field in ipairs(TEMPLATE_FIELDS) do
		original[field] = template[field]
	end

	for _, field in ipairs(ATTACK_META_DATA_FIELDS) do
		original.attack_meta_data[field] = attack_meta_data[field]
	end

	saved[template_name] = original

	-- The shot is replaced, and the staff's charged attack is taken away: the zoom is done by this file (see below). Everything else
	-- stays untouched, including the venting, wield, inspect and the career actions.
	actions.action_one = {
		default = build_shot(Weapons.handgun_template_1.actions.action_one.default),
	}
	actions.action_two = nil

	utils.set_actions_lookup_data({
		action_one = actions.action_one,
	}, template_name)

	-- The staff's wield lights trails on the fingers of the first person arms, and its charged attack more. The skin hides the arms,
	-- but not their effects.
	template.on_wield = nil
	template.synced_states = nil
	-- A rifle's crosshair, not the staff's arrows
	template.crosshair_style = "default"

	-- The bot AI and the tooltips refer to the staff's charged attack, which was removed.
	attack_meta_data.can_charge_shot = false
	attack_meta_data.charged_attack_action_name = nil
	attack_meta_data.max_range = CONFIG.bot_max_range

	template.tooltip_compare = {
		light = {
			action_name = "action_one",
			sub_action_name = "default",
		},
		heavy = {
			action_name = "action_one",
			sub_action_name = "default",
		},
	}
	template.tooltip_detail = template.tooltip_compare
end

local function apply_lightning_guns()
	apply_staff(TEMPLATE_NAME)
end

local function restore_lightning_guns()
	restore_staff(TEMPLATE_NAME)
end

-- The bolt and its arcs. The game's own shot damages what the bolt hits. This works out where the bolt ends, jumps the arcs, and tells
-- the skin what to draw. It runs on the machine that owns the shot, which is the player's, or the host's for its bots.

local random_direction = utils.random_direction

local function raycast(physics_world, origin, direction)
	return PhysicsWorld.immediate_raycast_actors(physics_world, origin, direction, "static_collision_filter", "filter_player_ray_projectile_static_only", "dynamic_collision_filter", "filter_player_ray_projectile_ai_only", "dynamic_collision_filter", "filter_player_ray_projectile_hitbox_only")
end

-- Returns the unit that a hit of a ray is on
local function hit_unit_of(hit)
	local actor = hit[4]
	local unit = Actor.unit(actor)

	return (ActionUtils.redirect_shield_hit(unit, actor))
end

-- The living enemies of the shooter within arc_seek_range of where the bolt hit, other than the one it hit, nearest first, each as the
-- point an arc goes for (its spine)
local function arc_targets(shot, origin, main_unit, world)
	local targets = {}

	for unit in pairs(utils.units_in_radius(world, origin, CONFIG.arc_seek_range)) do
		if unit ~= main_unit and HEALTH_ALIVE[unit] and DamageUtils.is_enemy(shot.owner_unit, unit) then
			local point = Unit.has_node(unit, "j_spine") and Unit.world_position(unit, Unit.node(unit, "j_spine")) or Unit.world_position(unit, 0) + Vector3.up()

			targets[#targets + 1] = {
				distance = Vector3.distance(origin, point),
				point = Vector3Box(point),
			}
		end
	end

	table.sort(targets, function (a, b)
		return a.distance < b.distance
	end)

	return targets
end

-- Jumps the arcs from the place the bolt hit. Returns where each one ends, and the normal of what it hit: the surface's, or the way
-- back along the arc if it hit nothing (SniperFire.DoTrace). An arc that hits an enemy that is not the one the bolt hit damages it. The
-- arcs go for the enemies near (arc_targets) before they go in random directions.
local function jump_arcs(shot, origin, main_unit, world)
	local arcs = {}
	local normals = {}
	local targets = arc_targets(shot, origin, main_unit, world)

	for i = 1, CONFIG.arc_count do
		local target = targets[i]
		local direction = target and Vector3.normalize(target.point:unbox() - origin) or random_direction()
		local hits = raycast(shot.physics_world, origin, direction)
		local hit = first_beam_hit(hits, shot.owner_unit)
		local ends = hit and hit[2] <= CONFIG.arc_range
		local end_position = ends and hit[1] or origin + direction * CONFIG.arc_range

		arcs[#arcs + 1] = end_position
		normals[#normals + 1] = ends and hit[3] or -direction

		if ends then
			local unit = hit_unit_of(hit)

			if unit ~= main_unit and Unit.get_data(unit, "breed") then
				DamageUtils.process_projectile_hit(world, shot.item_name, shot.owner_unit, shot.is_server, { hit }, ARC_ACTION, direction, true, nil, nil, shot._is_critical_strike, shot.power_level)
			end
		end
	end

	return arcs, normals
end

mod.handgun_start_callbacks.lightning = function (self, new_action)
	self._ut_lightning_checked = not new_action.ut_lightning_bolt
end

mod.handgun_update_callbacks.lightning = function (self)
	if self._ut_lightning_checked or self.state == "waiting_to_shoot" then
		return
	end

	self._ut_lightning_checked = true

	local owner_unit = self.owner_unit
	local first_person_extension = ScriptUnit.extension(owner_unit, "first_person_system")
	local origin, rotation = first_person_extension:get_projectile_start_position_rotation()
	local direction = Quaternion.forward(rotation)
	local hit = first_beam_hit(raycast(self.physics_world, origin, direction), owner_unit)
	local end_position = hit and hit[1] or origin + direction * CONFIG.bolt_range
	-- The surface normal is the zero-length vector when there is no surface.
	local hit_normal = hit and hit[3] or Vector3.zero()
	-- The arcs start a little off the surface. A bolt that hits nothing has no arcs.
	local arcs_start = hit and hit[1] + hit[3] * CONFIG.arc_start_offset or end_position
	local arcs, arc_normals = {}, {}

	if hit then
		arcs, arc_normals = jump_arcs(self, arcs_start, hit_unit_of(hit), self.world)
	end

	-- The scope's charge bar and the sparks at the tip of the weapon follow the player's shots
	if utils.is_local_player_unit(owner_unit) then
		mod.lightning.last_fire_time = Managers.time:time("game")
	end

	mod.lightning.bolt(owner_unit, end_position, hit_normal, arcs, arcs_start, arc_normals)
end

-- What the skin is told (mod.lightning_bolt_callbacks in hooks.lua), and what is sent to the other players. The skin draws the bolt of
-- the player who fires, from the weapon in their own view, and the others see it come from the weapon of the player's character.
mod.lightning = {
	-- The seconds between shots, and when the player last fired
	fire_rate = CONFIG.fire_rate,
	last_fire_time = nil,
}

-- A vector's three numbers. Vectors are userdata, and a missing one is the zero vector.
local function components(vector)
	if not vector then
		return 0, 0, 0
	end

	return Vector3.x(vector), Vector3.y(vector), Vector3.z(vector)
end

function mod.lightning.bolt(owner_unit, end_position, hit_normal, arcs, arcs_start, arc_normals)
	for _, callback in pairs(mod.lightning_bolt_callbacks) do
		callback(owner_unit, end_position, hit_normal, arcs, arcs_start, arc_normals)
	end

	-- The arcs go as a list of numbers: each arc's end and its normal
	local arc_numbers = {}

	for i = 1, #arcs do
		local end_x, end_y, end_z = components(arcs[i])
		local arc_normal_x, arc_normal_y, arc_normal_z = components(arc_normals[i])

		for _, number in ipairs({ end_x, end_y, end_z, arc_normal_x, arc_normal_y, arc_normal_z }) do
			arc_numbers[#arc_numbers + 1] = number
		end
	end

	local end_x, end_y, end_z = components(end_position)
	local normal_x, normal_y, normal_z = components(hit_normal)
	local start_x, start_y, start_z = components(arcs_start)

	mod:network_send("ut_lightning_bolt", "others", Managers.state.unit_storage:go_id(owner_unit), end_x, end_y, end_z, normal_x, normal_y, normal_z, start_x, start_y, start_z, arc_numbers)
end

mod:network_register("ut_lightning_bolt", function (_, owner_go_id, x, y, z, normal_x, normal_y, normal_z, start_x, start_y, start_z, arc_numbers)
	local unit = Managers.state.unit_storage:unit(owner_go_id)

	if not unit or not Unit.alive(unit) then
		return
	end

	local arcs, arc_normals = {}, {}

	for i = 1, #arc_numbers - 5, 6 do
		local n = arc_numbers

		arcs[#arcs + 1] = Vector3(n[i], n[i + 1], n[i + 2])
		arc_normals[#arc_normals + 1] = Vector3(n[i + 3], n[i + 4], n[i + 5])
	end

	for _, callback in pairs(mod.lightning_bolt_callbacks) do
		callback(unit, Vector3(x, y, z), Vector3(normal_x, normal_y, normal_z), arcs, Vector3(start_x, start_y, start_z), arc_normals)
	end
end)

-- The zoom is UT's (zoom.lua)
mod.zoom.register(TEMPLATE_NAME)

mod.lightning.zoom = mod.zoom

-- The weapon is enabled with the mod. The mod's own copies of the templates are patched, and put back when the mod is switched off
-- or unloaded.
mod.enabled_callbacks[#mod.enabled_callbacks + 1] = apply_lightning_guns
mod.disabled_callbacks[#mod.disabled_callbacks + 1] = restore_lightning_guns
mod.unload_callbacks[#mod.unload_callbacks + 1] = restore_lightning_guns
