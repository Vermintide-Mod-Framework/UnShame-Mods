local mod = get_mod("unreal_tournament")

-- Sniper Rifle: UT2004's classic one (UTClassic.ClassicSniperRifle, ClassicSniperFire and XWeapons.SniperZoom), a copy of a handgun with
-- its fire modes replaced.
--   Left button: a bullet that hits at once (the game's own handgun shot). A hit on the head does double damage.
--   Right button: zooms, as the Lightning Gun does (zoom.lua).
-- All of the ammo is in the gun, so there is no reload. Kruber's handgun and Bardin's are separate templates, so the weapon is two items
-- of the mod that share everything but the base. The skin (skin.lua) draws all of it, and this file only sets what it does to the game.

local utils = mod.utils
local register_damage_profile = utils.register_damage_profile
local make_flat = utils.make_flat
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for
local first_beam_hit = utils.first_beam_hit

local DESCRIPTION = "This high muzzle velocity sniper rifle with a 10X scope is a lethal weapon at any range, especially if you can land a head shot."

-- The two items. The careers of each are those of its base.
local VARIANTS = {
	{
		base_item = "es_handgun",
		deus_copy = "deus_es_handgun",
		id = "sniper_rifle",
		key = "ut_sniper_rifle",
		template = "ut_sniper_rifle_template",
	},
	{
		base_item = "dr_handgun",
		deus_copy = "deus_dr_handgun",
		id = "sniper_rifle_dr",
		key = "ut_sniper_rifle_dr",
		template = "ut_sniper_rifle_dr_template",
	},
}

for _, variant in ipairs(VARIANTS) do
	mod.items.register(variant.id, {
		key = variant.key,
		template = variant.template,
		base_item = variant.base_item,
		deus_copy = variant.deus_copy,
		name = "UT2004 Sniper Rifle",
		type_name = "Sniper Rifle",
		description = DESCRIPTION,
		keywords = { "weapon_keyword_high_damage", "weapon_keyword_sniper", "weapon_keyword_headshotting" },
		icon = "ut_sniper_rifle_icon",
		icon_package = "resource_packages/unreal_tournament/icons",
		icon_materials = "ui/ut/sniper_rifle_icon",
	})
end

local TEMPLATE_NAMES = {}

for _, variant in ipairs(VARIANTS) do
	TEMPLATE_NAMES[mod.items.weapons[variant.id].template] = true
end

local CONFIG = {
	-- ClassicSniperAmmo.MaxAmmo. It is all the clip, so there is no reload.
	max_ammo = 35,
	-- ClassicSniperFire.FireRate. After a shot, the next one can be made once this much time has passed.
	fire_rate = 1.33,
	chain_margin = 0.15, -- seconds
	-- ClassicSniperFire.DamageMin and DamageMax, in UT2004's units, where 45 is the shock rifle's beam, and HeadShotDamageMult
	damage = 60,
	headshot_multiplier = 2,
	-- How far the bullet reaches, in meters (TraceRange is 17000 units), for where it hits
	range = 340,
	-- How far a bot shoots from, in meters
	bot_max_range = 60,
	-- ClassicSniperFire.ShakeOffsetMag, ShakeOffsetRate and ShakeOffsetTime: the view jumps back 15 units and up 10 (forward, right, up).
	-- It has no turn (ShakeRotMag is 0), so the game's recoil of the handgun is taken away.
	shake_magnitude = { -15, 0, 10 },
	shake_rate = { -4000, 0, 4000 },
	shake_time = 1.6,
}

local TOTAL_TIME = CONFIG.fire_rate + CONFIG.chain_margin

-- Spread: the bullet hits exactly where the crosshair is.
utils.zero_spread_template("ut_sniper_bullet", "handgun")

-- The bullet stops at the first enemy it hits, as UT's trace does: a profile with a cleave that is tiny hurts one enemy. Its armor
-- modifiers are the handgun's bullet's.
register_damage_profile("ut_sniper_bullet", "shot_sniper", function (profile)
	make_flat(profile, attack_power_for(CONFIG.damage), impact_power_for(CONFIG.damage), "shot_sniper")

	profile.cleave_distribution = {
		attack = 0.01,
		impact = 0.01,
	}
	utils.set_headshot_multiplier(profile, CONFIG.headshot_multiplier)
end)

-- The flow events of the game's handgun shot that start its tracer (ActionHandgun.client_owner_post_update). UT draws no tracer for the
-- player who fires.
local DROPPED_FLOW_EVENTS = {
	lua_bullet_trail = true,
	lua_bullet_trail_set = true,
}

-- Weapon template

-- When each character last fired, on the machine that runs their actions. A shot waits for UT's fire time after the last one whatever
-- action it starts from (the zoom's, which a shot can turn into at once, say).
local last_shots = setmetatable({}, {
	__mode = "k",
})

local function ready_to_fire(unit)
	local last = last_shots[unit]

	return not last or Managers.time:time("game") - last >= CONFIG.fire_rate - 0.01
end

-- The actions that can follow a shot. Holding the button repeats the shot, as in UT, and the zoom can start at any time.
local function fire_chain_actions()
	local entries = {
		{
			action = "action_wield",
			input = "action_wield",
			start_time = 0.4,
			sub_action = "default",
		},
		{
			action = "action_two",
			input = "action_two",
			start_time = 0,
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

-- Builds the handgun's shot, with its ammo and animation. It can be repeated after UT's fire time, and it has no reload. Its hits on
-- the world and on enemies are the game's handgun's (the holes, the dust and the blood).
local function build_shot(original)
	local action = table.clone(original)

	action.active_reload_time = nil
	action.allowed_chain_actions = fire_chain_actions()
	action.condition_func = ready_to_fire
	action.chain_condition_func = ready_to_fire
	action.anim_event_secondary = nil
	action.apply_recoil = false
	action.damage_profile = "ut_sniper_bullet"
	action.headshot_multiplier = CONFIG.headshot_multiplier
	action.recoil_settings = nil
	action.reload_when_out_of_ammo = false
	action.spread_template_override = "ut_sniper_bullet"
	-- The shot lasts slightly longer than the time to the next shot. A held button is only read while a shot is still running, so a shot
	-- that ends exactly when the next one may start would miss it.
	action.total_time = TOTAL_TIME
	action.total_time_secondary = nil
	action.ut_sniper_bullet = true
	action.ut_dropped_flow_events = DROPPED_FLOW_EVENTS

	return action
end

-- The aim animation of each template's base: { zoom_in = event, zoom_out = event }
mod.sniper_zoom_animations = {}

local function apply_handgun(template)
	-- The chart of the item's stats, from 0 to 7. The bullet is the normal attack.
	template.weapon_diagram = {
		light_attack = {
			[DamageTypes.ARMOR_PIERCING] = 5,
			[DamageTypes.CLEAVE] = 1,
			[DamageTypes.SPEED] = 3,
			[DamageTypes.STAGGER] = 3,
			[DamageTypes.DAMAGE] = 6,
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

	-- Only the shot is replaced, and the aim action is replaced by UT's zoom (zoom.lua). Everything else stays untouched, including
	-- wield, inspect and the career actions.
	local hand = actions.action_one.default.weapon_action_hand
	local aim = actions.action_two.default

	-- The base's aim animation, which skin.lua plays on the character while the zoom is in (the zoom is a toggle, not a held action)
	if aim.anim_event then
		mod.sniper_zoom_animations[template.name] = { zoom_in = aim.anim_event, zoom_out = aim.anim_end_event }
	end

	actions.action_one = {
		default = build_shot(actions.action_one.default),
	}
	-- While the zoom is held, a shot can follow at once (it waits for its fire time), and so can wielding
	actions.action_two = {
		default = mod.zoom.action(hand, {
			{
				action = "action_wield",
				input = "action_wield",
				start_time = 0,
				sub_action = "default",
			},
			{
				action = "action_one",
				input = "action_one",
				start_time = 0,
				sub_action = "default",
			},
			{
				action = "action_one",
				input = "action_one_hold",
				start_time = 0,
				sub_action = "default",
			},
		}),
	}

	utils.set_actions_lookup_data({
		action_one = actions.action_one,
		action_two = actions.action_two,
	}, template.name)

	-- All the ammo is the clip, and picked up ammo is added to it, so there is no reload between shots.
	template.ammo_data.max_ammo = CONFIG.max_ammo
	template.ammo_data.ammo_per_clip = CONFIG.max_ammo
	template.ammo_data.ammo_per_reload = CONFIG.max_ammo
	template.ammo_data.ammo_immediately_available = true
	-- Nothing should need a reload, but the game may still start one when the weapon is wielded, so the reload is made short.
	template.ammo_data.reload_time = 0.2

	-- The bot AI and the tooltips refer to the zoomed shot, which was removed.
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

for template_name in pairs(TEMPLATE_NAMES) do
	mod.items.set_template_changes(template_name, apply_handgun)
	mod.zoom.register(template_name)
end

-- The shot. The game's own shot damages what the bullet hits. This works out where it hit, for the skin's sparks and sound
-- (SniperWallHitEffect), and tells the skin and the other players. It runs on the machine that owns the shot, which is the player's,
-- or the host's for its bots.

-- What the skin is told: mod.sniper.shot_callbacks[name] = function (owner_unit, hit_position, hit_normal), with no position or normal
-- if the bullet hit nothing
mod.sniper = {
	shot_callbacks = {},
	-- The seconds between shots, and when the player last fired
	fire_rate = CONFIG.fire_rate,
	last_fire_time = nil,
}

-- The game's time starts again in each level, so a shot of the last level would keep the gun from being ready until the new level's time
-- got as far
mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	mod.sniper.last_fire_time = nil

	table.clear(last_shots)
end

local function raycast(physics_world, origin, direction)
	return PhysicsWorld.immediate_raycast_actors(physics_world, origin, direction, CONFIG.range, "static_collision_filter", "filter_player_ray_projectile_static_only", "dynamic_collision_filter", "filter_player_ray_projectile_ai_only", "dynamic_collision_filter", "filter_player_ray_projectile_hitbox_only")
end

local function tell(owner_unit, hit_position, hit_normal)
	for _, callback in pairs(mod.sniper.shot_callbacks) do
		callback(owner_unit, hit_position, hit_normal)
	end
end

mod.handgun_start_callbacks.sniper = function (self, new_action)
	self._ut_sniper_checked = not new_action.ut_sniper_bullet

	if new_action.ut_sniper_bullet then
		last_shots[self.owner_unit] = Managers.time:time("game")
	end

	-- ClassicSniperFire's view shake, for the player who fires
	if new_action.ut_sniper_bullet and utils.is_local_player_unit(self.owner_unit) then
		mod.view_shake.start(CONFIG.shake_magnitude, CONFIG.shake_rate, CONFIG.shake_time)
		mod.sniper.last_fire_time = Managers.time:time("game")
	end
end

mod.handgun_update_callbacks.sniper = function (self)
	if self._ut_sniper_checked or self.state == "waiting_to_shoot" then
		return
	end

	self._ut_sniper_checked = true

	local owner_unit = self.owner_unit
	local first_person_extension = ScriptUnit.extension(owner_unit, "first_person_system")
	local origin, rotation = first_person_extension:get_projectile_start_position_rotation()
	local hit = first_beam_hit(raycast(self.physics_world, origin, Quaternion.forward(rotation)), owner_unit)
	local hit_position = hit and hit[1]
	local hit_normal = hit and hit[3]

	tell(owner_unit, hit_position, hit_normal)

	-- (a shot that hit nothing is sent with the zero vector as its normal)
	local x, y, z = 0, 0, 0
	local normal_x, normal_y, normal_z = 0, 0, 0

	if hit then
		x, y, z = Vector3.x(hit_position), Vector3.y(hit_position), Vector3.z(hit_position)
		normal_x, normal_y, normal_z = Vector3.x(hit_normal), Vector3.y(hit_normal), Vector3.z(hit_normal)
	end

	mod:network_send("ut_sniper_shot", "others", Managers.state.unit_storage:go_id(owner_unit), x, y, z, normal_x, normal_y, normal_z)
end

mod:network_register("ut_sniper_shot", function (_, owner_go_id, x, y, z, normal_x, normal_y, normal_z)
	local unit = Managers.state.unit_storage:unit(owner_go_id)

	if not unit or not Unit.alive(unit) then
		return
	end

	local normal = Vector3(normal_x, normal_y, normal_z)

	if Vector3.length(normal) > 0.01 then
		tell(unit, Vector3(x, y, z), normal)
	else
		tell(unit, nil, nil)
	end
end)
