local mod = get_mod("unreal_tournament")

-- Lightning Gun: a copy of a handgun with its fire modes replaced, the same way the Shock Rifle is a copy of the Beam Staff. The
-- numbers come from UT2004 (XWeapons/SniperRifle, SniperFire and SniperZoom).
--   Left button: fires a lightning bolt that hits at once. After it hits, three short arcs of lightning jump from the place it hit
--       to enemies near it. A hit on the head does double damage.
--   Right button: zooms. Holding it zooms in, until it is let go, and the zoom stays. Pressing it again zooms out.
-- Kruber's handgun and Bardin's are separate templates, so the weapon is two items of the mod that share everything but the base.
-- The skin (skin.lua) draws all of it, and this file only sets what it does to the game.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local register_damage_profile = utils.register_damage_profile
local make_flat = utils.make_flat
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for
local first_beam_hit = utils.first_beam_hit

local DESCRIPTION = "The Lightning Gun is a high-power energy rifle capable of ablating even the heaviest carapace armor. Acquisition of a target at long range requires a steady hand, but the anti-jitter effect of the optical system reduces the weapon's learning curve significantly."

-- The two items. The careers of each are those of its base.
local VARIANTS = {
	{
		base_item = "es_handgun",
		deus_copy = "deus_es_handgun",
		id = "lightning_gun",
		key = "ut_lightning_gun",
		template = "ut_lightning_gun_template",
	},
	{
		base_item = "dr_handgun",
		deus_copy = "deus_dr_handgun",
		id = "lightning_gun_dr",
		key = "ut_lightning_gun_dr",
		template = "ut_lightning_gun_dr_template",
	},
}

for _, variant in ipairs(VARIANTS) do
	mod.items.register(variant.id, {
		key = variant.key,
		template = variant.template,
		base_item = variant.base_item,
		deus_copy = variant.deus_copy,
		name = "UT2004 Lightning Gun",
		type_name = "Lightning Gun",
		description = DESCRIPTION,
		keywords = { "weapon_keyword_high_damage", "weapon_keyword_sniper", "weapon_keyword_headshotting" },
		icon = "ut_lightning_gun_icon",
		icon_package = "resource_packages/unreal_tournament/icons",
		icon_materials = "ui/ut/lightning_gun_icon",
	})
end

local TEMPLATE_NAMES = {}

for _, variant in ipairs(VARIANTS) do
	TEMPLATE_NAMES[mod.items.weapons[variant.id].template] = true
end

local CONFIG = {
	meters_per_uu = 0.02, -- Unreal unit to meters
	-- All of the ammo (UT's Lightning Gun holds up to 40). It is all the clip, so there is no reload.
	max_ammo = 40,
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
	-- How far a bot shoots from, in meters. The handgun's own is the bot's sight.
	bot_max_range = 60,
	-- The camera shake of a shot is the handgun's recoil, scaled by this.
	recoil_scale = 0.5,
	-- The zoom (PlayerController.AdjustView and ToggleZoom). The field of view goes from the normal 90 degrees down by 88 degrees for
	-- each second the button is held, until the zoom level reaches 0.9: 10.8 degrees.
	zoom_normal_fov = 90, -- degrees, horizontal
	zoom_degrees_per_second = 88,
	zoom_max_level = 0.9,
	zoom_min_fov = 1,
}

local TOTAL_TIME = CONFIG.fire_rate + CONFIG.chain_margin

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

-- What an arc is, to the game's hit processing: an action with the profile of the arc.
local ARC_ACTION = {
	damage_profile = "ut_lightning_arc",
	hit_effect = NO_HIT_EFFECT,
	ignore_shield_hit = true,
}

-- Weapon template

-- The actions that can follow a shot. Holding the button repeats the shot, as in UT. The zoom is not an action.
local function fire_chain_actions()
	local entries = {
		{
			action = "action_wield",
			input = "action_wield",
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

-- Builds the handgun's shot, with its ammo, recoil and animation. It can be repeated after UT's fire time, and it has no reload.
local function build_shot(original)
	local action = table.clone(original)

	action.active_reload_time = nil
	action.allowed_chain_actions = fire_chain_actions()
	action.anim_event_secondary = nil
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
	"ut_lightning",
}

local AMMO_DATA_FIELDS = {
	"ammo_per_clip",
	"ammo_per_reload",
	"max_ammo",
	"reload_time",
}

local function restore_handgun(template_name)
	local original = saved[template_name]
	local template = rawget(Weapons, template_name)

	if not original or not template then
		return
	end

	template.actions.action_one = original.action_one
	template.actions.action_two = original.action_two
	template.tooltip_compare = original.tooltip_compare
	template.tooltip_detail = original.tooltip_detail

	for _, field in ipairs(ATTACK_META_DATA_FIELDS) do
		template.attack_meta_data[field] = original.attack_meta_data[field]
	end

	for _, field in ipairs(AMMO_DATA_FIELDS) do
		template.ammo_data[field] = original.ammo_data[field]
	end

	template.ammo_data.ammo_immediately_available = original.ammo_immediately_available
	saved[template_name] = nil
end

local function apply_handgun(template_name)
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
		ammo_data = {},
		ammo_immediately_available = template.ammo_data.ammo_immediately_available,
		attack_meta_data = {},
		tooltip_compare = template.tooltip_compare,
		tooltip_detail = template.tooltip_detail,
	}

	for _, field in ipairs(ATTACK_META_DATA_FIELDS) do
		original.attack_meta_data[field] = attack_meta_data[field]
	end

	for _, field in ipairs(AMMO_DATA_FIELDS) do
		original.ammo_data[field] = template.ammo_data[field]
	end

	saved[template_name] = original

	-- Only the shot is replaced, and the aim action is taken away: the zoom is done by this file (see below). Everything else stays
	-- untouched, including wield, inspect and the career actions.
	actions.action_one = {
		default = build_shot(original.action_one.default),
	}
	actions.action_two = nil

	utils.set_actions_lookup_data({
		action_one = actions.action_one,
	}, template_name)

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
	-- This tells the bot shooting that this is the Lightning Gun (see bots.lua).
	attack_meta_data.ut_lightning = true

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
	for template_name in pairs(TEMPLATE_NAMES) do
		apply_handgun(template_name)
	end
end

local function restore_lightning_guns()
	for template_name in pairs(TEMPLATE_NAMES) do
		restore_handgun(template_name)
	end
end

-- The bolt and its arcs. The game's own shot damages what the bolt hits. This works out where the bolt ends, jumps the arcs, and tells
-- the skin what to draw. It runs on the machine that owns the shot, which is the player's, or the host's for its bots.

local function random_direction()
	local direction = Vector3(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1)

	if Vector3.length(direction) < 0.001 then
		return Vector3.up()
	end

	return Vector3.normalize(direction)
end

local function raycast(physics_world, origin, direction)
	return PhysicsWorld.immediate_raycast_actors(physics_world, origin, direction, "static_collision_filter", "filter_player_ray_projectile_static_only", "dynamic_collision_filter", "filter_player_ray_projectile_ai_only", "dynamic_collision_filter", "filter_player_ray_projectile_hitbox_only")
end

-- Returns the unit that a hit of a ray is on
local function hit_unit_of(hit)
	local actor = hit[4]
	local unit = Actor.unit(actor)

	return (ActionUtils.redirect_shield_hit(unit, actor))
end

-- Jumps the arcs from the place the bolt hit. Returns where each one ends. An arc that hits an enemy that is not the one the bolt
-- hit damages it.
local function jump_arcs(shot, origin, main_unit, world)
	local arcs = {}

	for _ = 1, CONFIG.arc_count do
		local direction = random_direction()
		local hits = raycast(shot.physics_world, origin, direction)
		local hit = first_beam_hit(hits, shot.owner_unit)
		local ends = hit and hit[2] <= CONFIG.arc_range
		local end_position = ends and hit[1] or origin + direction * CONFIG.arc_range

		arcs[#arcs + 1] = end_position

		if ends then
			local unit = hit_unit_of(hit)

			if unit ~= main_unit and Unit.get_data(unit, "breed") then
				DamageUtils.process_projectile_hit(world, shot.item_name, shot.owner_unit, shot.is_server, { hit }, ARC_ACTION, direction, true, nil, nil, shot._is_critical_strike, shot.power_level)
			end
		end
	end

	return arcs
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
	local arcs = hit and jump_arcs(self, arcs_start, hit_unit_of(hit), self.world) or {}

	-- The scope's charge bar and the sparks at the tip of the weapon follow the player's shots
	if utils.is_local_player_unit(owner_unit) then
		mod.lightning.last_fire_time = Managers.time:time("game")
	end

	mod.lightning.bolt(owner_unit, end_position, hit_normal, arcs, arcs_start)
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

function mod.lightning.bolt(owner_unit, end_position, hit_normal, arcs, arcs_start)
	for _, callback in pairs(mod.lightning_bolt_callbacks) do
		callback(owner_unit, end_position, hit_normal, arcs, arcs_start)
	end

	local arc_1x, arc_1y, arc_1z = components(arcs[1])
	local arc_2x, arc_2y, arc_2z = components(arcs[2])
	local arc_3x, arc_3y, arc_3z = components(arcs[3])
	local end_x, end_y, end_z = components(end_position)
	local normal_x, normal_y, normal_z = components(hit_normal)
	local start_x, start_y, start_z = components(arcs_start)

	mod:network_send("ut_lightning_bolt", "others", Managers.state.unit_storage:go_id(owner_unit), end_x, end_y, end_z, normal_x, normal_y, normal_z, start_x, start_y, start_z, arc_1x, arc_1y, arc_1z, arc_2x, arc_2y, arc_2z, arc_3x, arc_3y, arc_3z, #arcs)
end

mod:network_register("ut_lightning_bolt", function (_, owner_go_id, x, y, z, normal_x, normal_y, normal_z, start_x, start_y, start_z, a1x, a1y, a1z, a2x, a2y, a2z, a3x, a3y, a3z, arc_count)
	local unit = Managers.state.unit_storage:unit(owner_go_id)

	if not unit or not Unit.alive(unit) then
		return
	end

	local ends = { Vector3(a1x, a1y, a1z), Vector3(a2x, a2y, a2z), Vector3(a3x, a3y, a3z) }
	local arcs = {}

	for i = 1, arc_count do
		arcs[i] = ends[i]
	end

	for _, callback in pairs(mod.lightning_bolt_callbacks) do
		callback(unit, Vector3(x, y, z), Vector3(normal_x, normal_y, normal_z), arcs, Vector3(start_x, start_y, start_z))
	end
end)

-- The zoom. The game's own aim action zooms to fixed fields of view, and slows the player down. UT's zoom is continuous, and the
-- player moves at the same speed, so this is done here. It works on the camera's field of view, after the game has set it for the
-- frame. The state is of the player on this machine.
local zoom = {
	-- The zoom level (PlayerController.ZoomLevel) and whether the button is held to zoom in (PlayerController.bZooming)
	level = 0,
	zooming = false,
	zoomed = false,
}

mod.lightning.zoom = zoom

local function end_zoom()
	zoom.level = 0
	zoom.zooming = false
	zoom.zoomed = false
end

-- The horizontal field of view that UT's zoom has now, in degrees
local function zoom_fov()
	return math.clamp(CONFIG.zoom_normal_fov - zoom.level * CONFIG.zoom_degrees_per_second, CONFIG.zoom_min_fov, 170)
end

-- How many times larger the view is than it is without zoom
function zoom.magnification()
	if not zoom.zoomed then
		return 1
	end

	return math.tan(math.rad(CONFIG.zoom_normal_fov / 2)) / math.tan(math.rad(zoom_fov() / 2))
end

local function local_wielding_lightning_gun()
	local player = Managers.player and Managers.player:local_player_safe()
	local unit = player and player.player_unit

	if not unit or not Unit.alive(unit) then
		return nil
	end

	local template_name = utils.wielded_template_name(unit)

	return TEMPLATE_NAMES[template_name] and unit or nil
end

-- The game's camera takes a multiplier of its field of view for effects (CameraManager.set_additional_fov_multiplier). The zoom is made
-- with it. The multiplier works on the angle, so it is worked out from the tangent that the zoom is made in.
local zoom_fov_applied = false

local function apply_zoom_fov()
	local camera_manager = Managers.state and Managers.state.camera

	if not camera_manager then
		return
	end

	if zoom.zoomed then
		-- The field of view the camera has without the multiplier: the first person camera's, times the player's setting
		local base = math.rad(65) * camera_manager._fov_multiplier
		local zoomed = 2 * math.atan(math.tan(base / 2) / zoom.magnification())

		camera_manager:set_additional_fov_multiplier(zoomed / base)

		zoom_fov_applied = true
	elseif zoom_fov_applied then
		camera_manager:set_additional_fov_multiplier(1)

		zoom_fov_applied = false
	end
end

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	local unit = local_wielding_lightning_gun()

	if not unit or not HEALTH_ALIVE[unit] then
		if zoom.zoomed then
			end_zoom()
		end

		apply_zoom_fov()

		return
	end

	local input_extension = ScriptUnit.extension(unit, "input_system")

	if input_extension:get("action_two") then
		if zoom.zoomed then
			-- Pressing the button while zoomed zooms out
			end_zoom()
		else
			-- ToggleZoom: StartZoom
			zoom.level = 0
			zoom.zooming = true
			zoom.zoomed = true
		end
	end

	if zoom.zooming then
		if input_extension:get("action_two_hold") then
			zoom.level = math.min(zoom.level + dt, CONFIG.zoom_max_level)
		else
			-- StopZoom: the zoom stays where it is
			zoom.zooming = false
		end
	end

	apply_zoom_fov()
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	end_zoom()
	apply_zoom_fov()
end

local function reset_zoom()
	end_zoom()
	apply_zoom_fov()
end

mod.disabled_callbacks[#mod.disabled_callbacks + 1] = reset_zoom
mod.unload_callbacks[#mod.unload_callbacks + 1] = reset_zoom

-- The weapon is enabled with the mod. The mod's own copies of the templates are patched, and put back when the mod is switched off
-- or unloaded.
mod.enabled_callbacks[#mod.enabled_callbacks + 1] = apply_lightning_guns
mod.disabled_callbacks[#mod.disabled_callbacks + 1] = restore_lightning_guns
mod.unload_callbacks[#mod.unload_callbacks + 1] = restore_lightning_guns
