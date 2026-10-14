local mod = get_mod("unreal_tournament")

-- Rocket Launcher: a copy of the witch hunter's Repeating Crossbow with its fire modes replaced, the same way the Flak Cannon is
-- a copy of the Blunderbuss. The numbers are from UT2004 (XWeapons/RocketFire, RocketMultiFire and RocketProj).
--   LMB: fires a rocket that explodes where it hits.
--   RMB (held): loads rockets, one at first and then another every load_interval seconds, up to three.
--               Releasing RMB fires them all in a line.
-- All the ammo is the clip, so there is no reload.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")
local register_damage_profile = utils.register_damage_profile
local register_explosion_template = utils.register_explosion_template
local register_network_lookup = utils.register_network_lookup
local make_flat = utils.make_flat
local attack_power_for = utils.attack_power_for
local impact_power_for = utils.impact_power_for

mod.items.register("rocket_launcher", {
	key = "ut_rocket_launcher",
	template = "ut_rocket_launcher_template",
	base_item = "wh_crossbow_repeater",
	deus_copy = "deus_wh_crossbow_repeater",
	name = "UT2004 Rocket Launcher",
	type_name = "Rocket Launcher",
	description = "The Trident Tri-barrel Rocket Launcher is extremely popular among competitors who enjoy more bang for their buck. The rotating rear-loading barrel design allows for both single- and multi-warhead launches, letting you place up to three dumbfire rockets on target.",
	keywords = { "weapon_keyword_high_damage", "weapon_keyword_crowd_control", "weapon_keyword_charged_attack", "weapon_keyword_armour_piercing" },
	icon = "ut_rocket_launcher_icon",
	icon_package = "resource_packages/unreal_tournament/icons",
	icon_materials = "ui/ut/rocket_launcher_icon",
})

local TEMPLATE_NAME = mod.items.weapons.rocket_launcher.template

-- A rocket goes where the crosshair is. It has no spread, while the crossbow's default would scatter it a little.
local SPREAD_TEMPLATE = "ut_rocket"

utils.zero_spread_template(SPREAD_TEMPLATE, "brace_of_pistols")
local SPIRAL_ACTION = "zoomed_shot_spiral" -- the sub action for a salvo that is a spiral

register_network_lookup("sub_actions", SPIRAL_ACTION)

local CONFIG = {
	meters_per_uu = 0.02, -- Unreal unit to meters
	-- Rocket
	-- RocketProj.Speed is 1350 uu/s. That is 27 m/s by size and 12 m/s by run speed, so this is in between. The action's unit is
	-- m/s * 100.
	rocket_speed = 2200,
	rocket_lifetime = 8, -- seconds
	rocket_radius = 0.1, -- m, how easily a rocket hits things
	-- How close a Flak shell or a Shock ball has to be for the rocket to explode on it. It is the same as the shell's.
	projectile_touch_radius = 0.5, -- m
	-- Where a rocket starts, measured from the camera: forward, to the right and down. UT's RocketFire.ProjSpawnOffset is 25, 6 and
	-- -6 units, which is 0.5, 0.12 and 0.12 m. The launcher is drawn further out here, so the offsets are larger, to start the
	-- rocket at the muzzle.
	start_forward = 1.0, -- m
	start_right = 0.35, -- m
	start_down = 0.18, -- m
	rocket_gravity_settings = "spark", -- the game's gravity setting with the least gravity
	fire_interval = 0.9, -- seconds, RocketFire.FireRate
	salvo_fire_interval = 0.95, -- seconds, RocketMultiFire.FireRate
	-- The crossbow has 15 in a clip and 48 in all, and UT's RocketAmmo.MaxAmmo is 30. All the ammo is the clip, so there is no
	-- reload.
	max_ammo = 27,
	-- The damage and radius of the explosion are the same as the Flak Cannon's shell. UT has 90 damage and a 220 uu radius for
	-- both, and they were reduced in the same way.
	rocket_damage = 60,
	-- The damage multipliers of the explosion for each armor type: unarmored, armored, monsters, players, berserkers and super
	-- armor. They are like the game's armour piercing weapons (at most 0.8 against armor and 1.5 against monsters) and like the Flak
	-- Cannon's shell. Super armor (chaos warriors) takes half damage, while the game's own multiplier for it is 0.
	rocket_armor_attack = {
		1,
		1,
		1.5,
		1,
		1,
		0.5,
	},
	-- The same multipliers for the stagger. The game's own are 0.5 against armor, 0.75 against berserkers and 0 against super armor.
	rocket_armor_impact = {
		1,
		1,
		1,
		1,
		1,
		0.5,
	},
	-- Bots shoot rockets at targets up to this far, in meters. It goes in the weapon's attack_meta_data, which the game's bot shooting reads.
	bot_max_range = 40,
	rocket_explosion_radius_uu = 150,
	rocket_explosion_full_damage_radius = 0.5, -- the damage falls off linearly from here to the radius
	-- The explosion hurts the player who fired the rocket. This is the damage at the center, and it falls off the same way the
	-- explosion's damage does.
	rocket_self_damage = 45,
	-- The explosion throws the player who fired the rocket away from its center at this speed in m/s. The speed is lower further
	-- out, like the damage. RocketProj.MomentumTransfer is 50000, while the Flak Cannon's shell has 75000 and uses 8.5.
	rocket_jump_speed = 5.7,
	-- Loading follows RocketMultiFire. One rocket is loaded right away, the second after FireRate (0.95 s), and the third after
	-- twice that. The rockets are fired in a line, with 1000 uu of UT's spread units (5.5 degrees) between them.
	max_rockets = 3,
	load_interval = 0.95, -- seconds, RocketMultiFire.FireRate
	-- The loaded rockets are fired by themselves after this long, whatever the ammo (RocketMultiFire.MaxHoldTime). UT also fires
	-- right away when the last of the ammo is loaded, but that is not done here.
	max_hold_time = 2.3, -- seconds
	rocket_line_spread = 0.096, -- radians between two rockets
	-- The spiral: pressing the primary button while loading makes the salvo a spiral instead of a line (UT's tight spread). The
	-- rockets start in a ring and fly as a flock (RocketProj.Timer). They are pulled towards each other when they are further apart
	-- than twice the flock radius, pushed away when they are closer, and curl around each other. These are UT's values in meters.
	-- The ring is not around the aim. Its center is to the right of the start of a rocket and below it (see
	-- RocketMultiFire.DoFireEffect), and each rocket starts a little way back, by up to the spiral_start_back distance.
	spiral_ring_radius = 0.32, -- 16 uu
	spiral_ring_right = 0.28, -- 14 uu
	spiral_ring_down = 0.28, -- 14 uu
	spiral_start_back = 0.16, -- 8 uu
	spiral_flock_radius = 0.24, -- FlockRadius 12 uu
	spiral_stiffness = -40, -- FlockStiffness
	spiral_max_force = 12, -- m/s^2, FlockMaxForce 600 uu/s^2
	spiral_curl_force = 9, -- m/s^2, FlockCurlForce 450 uu/s^2
	spiral_pull_interval = 0.1, -- seconds, how often the rockets are pulled back towards their direction
	-- Lock-on works like UT's. When the crosshair stays on an enemy for lock_required_time, the rockets fired after that home in
	-- on it. They use the game's true flight projectiles, whose position is synced, so everyone sees them home in. The lock is lost
	-- when the aim is off the enemy for unlock_required_time, and by firing. UT uses 1.25 s and 0.5 s, requires the target to be
	-- within 0.996 of the aim (5 degrees), and requires it to be within 8000 uu. The rockets of a spiral salvo start in their ring
	-- and home in too, which takes them out of the flock.
	lock_range = 50, -- m
	lock_aim_dot = 0.995, -- how close to the aim the enemy has to be, where 1 is exactly on it
	lock_keep_dot = 0.95, -- how far from the aim a locked enemy can be without counting as off the aim (18 degrees)
	lock_required_time = 0.75, -- seconds (UT's LockRequiredTime is 1.25)
	unlock_required_time = 0.5, -- seconds the aim has to be off the locked enemy before the lock is lost, UnLockRequiredTime
	lock_outline = true, -- the locked enemy gets the red outline of the game's target marking, like the true flight bow's
	lock_indicator = false, -- the crosshair gets arrows around it while locked
	lock_arrows_spread = 0.3, -- how far from the center the arrows are
	-- When another rocket is loaded, the weapon plays an animation (false for none) and sends a flow event to the weapon's units.
	-- "attack_shoot" is the animation of firing while aiming, and its sound is the sound of a shot. The game triggers flow events
	-- for the sounds of handling a weapon. "sfx_ranged_weapon_foley" is the rustle of it, and "sfx_ranged_weapon_equip" is the
	-- sound of wielding it.
	load_animation_event = false,
	load_flow_event = "sfx_ranged_weapon_equip",
	-- While loading, the crosshair shows a pip for each rocket that can be loaded, and the loaded ones are lit.
	crosshair_pips = true,
	pip_texture = "crosshair_01_center",
	pip_size = 9, -- pixels at 1080p
	pip_spacing = 18,
	pip_offset_y = 7, -- from the center of the crosshair, positive is up
	-- The red of the launcher's buttons
	pip_loaded_color = {
		255,
		215,
		25,
		25,
	}, -- alpha, red, green, blue
	pip_empty_alpha = 70,
	-- When the salvo will be a spiral, the pips are in a triangle instead of a row. The second pip stays where the middle one of
	-- the row is. The first and third pips are below the lines to the left and right of the crosshair's center, by this much
	-- sideways and down (negative is down).
	pip_spiral_side_x = 16,
	pip_spiral_side_y = -15,
	-- A sound of the game's HUD played when a rocket is loaded (false for none)
	load_sound_event = false,
	-- Whatever dies of the explosion is thrown away from it as UT does (utils.blast_ragdoll).
	ragdoll_window = 1.5, -- seconds a body has to start ragdolling after the explosion
}

-- Damage profiles. The direct hit of the rocket only staggers (and does 1 damage, so that it is not shown as blocked by armor). Its
-- damage is the explosion, which is at full strength for whatever the rocket hits, like in UT.
register_damage_profile("ut_rocket", "staff_fireball", function (profile)
	make_flat(profile, utils.STAGGER_HIT_ATTACK_POWER, impact_power_for(CONFIG.rocket_damage))

	profile.cleave_distribution = {
		attack = 0.01,
		impact = 0.01,
	}
end)

local function modify_explosion_profile(profile)
	make_flat(profile, attack_power_for(CONFIG.rocket_damage), impact_power_for(CONFIG.rocket_damage))

	-- The explosion does more damage against monsters and armor.
	profile.armor_modifier.attack = table.clone(CONFIG.rocket_armor_attack)
	profile.armor_modifier.impact = table.clone(CONFIG.rocket_armor_impact)
end

register_damage_profile("ut_rocket_explosion", "fireball_charged_explosion", modify_explosion_profile)
register_damage_profile("ut_rocket_explosion_glance", "fireball_charged_explosion_glance", modify_explosion_profile)

-- The look and the sound of the explosion come from the skin.
register_explosion_template("ut_rocket_explosion", {
	explosion = {
		alert_enemies = true,
		alert_enemies_radius = 15,
		attacker_power_level_offset = 1,
		damage_profile = "ut_rocket_explosion",
		damage_profile_glance = "ut_rocket_explosion_glance",
		-- The shooter is hurt separately. See rocket_self_damage.
		ignore_attacker_unit = true,
		max_damage_radius = CONFIG.rocket_explosion_full_damage_radius,
		radius = CONFIG.rocket_explosion_radius_uu * CONFIG.meters_per_uu,
		use_attacker_power_level = true,
		camera_effect = {
			far_distance = 20,
			far_scale = 0.1,
			near_distance = 5,
			near_scale = 0.5,
			shake_name = "frag_grenade_explosion",
		},
	},
})

-- Weapon template
-- The sub actions keep their names: default is the single rocket, and zoomed_shot is the loaded rockets. Only what they are made
-- of changes.

local function build_rocket_action(source, is_salvo)
	local action = table.clone(source)
	local projectile_info = table.clone(Projectiles.repeating_crossbow_bolt)

	projectile_info.gravity_settings = CONFIG.rocket_gravity_settings
	projectile_info.radius = CONFIG.rocket_radius
	projectile_info.unit_life_time = CONFIG.rocket_lifetime
	projectile_info.life_time = CONFIG.rocket_lifetime

	action.projectile_info = projectile_info
	action.speed = CONFIG.rocket_speed
	action.ut_aoe_callback = "rocket"
	action.ut_init_flow_event_filter = "rocket"
	action.ut_skin_init_callback = "rocket"
	action.ut_rocket = true
	action.spread_template_override = SPREAD_TEMPLATE

	-- The rocket is a grenade, so the first enemy it hits sets off the explosion.
	action.impact_data = {
		aoe = ExplosionTemplates.ut_rocket_explosion,
		damage_profile = "ut_rocket",
		grenade = true,
	}

	local interval = is_salvo and CONFIG.salvo_fire_interval or CONFIG.fire_interval

	-- The next shot, or the aiming, can start only once the launcher can fire again. UT does not start either mode while the other
	-- one is waiting for its fire rate.
	for _, chain in ipairs(action.allowed_chain_actions) do
		if chain.action == "action_one" or chain.action == "action_two" then
			chain.start_time = interval
		end
	end

	if is_salvo then
		action.num_projectiles = CONFIG.max_rockets
		action.multi_projectile_spread = CONFIG.rocket_line_spread
		action.ut_rocket_salvo = true

		-- Firing the salvo ends the aiming. The weapon goes back to neutral, and the player has to release the aiming button
		-- before aiming again (see needs_release).
		action.hold_input = nil
		action.minimum_hold_time = nil
		action.total_time = interval
		action.ut_init_callback = "rocket"

		-- There is no reloading during the salvo either, like during the aiming.
		for i = #action.allowed_chain_actions, 1, -1 do
			local chain = action.allowed_chain_actions[i]

			if chain.sub_action == "zoomed_shot" or chain.action == "weapon_reload" then
				table.remove(action.allowed_chain_actions, i)
			end
		end
	else
		action.total_time = interval
	end

	return action
end

-- After a salvo, the player has to release the aiming button before aiming again. This is tracked for each unit.
local needs_release = setmetatable({}, {
	__mode = "k",
})

-- The template is shared game state, so it is patched in place. What is changed is saved, and it is put back when the mod is
-- disabled or unloaded.
local saved = {}

local function restore_crossbow()
	local original = saved.original
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not original or not template then
		return
	end

	local actions = template.actions

	actions.action_one.default = original.action_one_default
	actions.action_one.zoomed_shot = original.action_one_zoomed_shot
	actions.action_one[SPIRAL_ACTION] = nil
	actions.action_two.default = original.action_two_default
	template.attack_meta_data.ut_rocket = nil
	template.attack_meta_data.can_charge_shot = original.can_charge_shot
	template.attack_meta_data.max_range = original.max_range

	for key, value in pairs(original.ammo_data) do
		template.ammo_data[key] = value
	end

	saved.original = nil
end

local function apply_rocket_launcher()
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not template then
		return
	end

	template.default_spread_template = SPREAD_TEMPLATE

	-- The chart of the item's stats, from 0 to 7. The single rocket is the normal attack, and the loaded salvo is the heavy one.
	template.weapon_diagram = {
		light_attack = {
			[DamageTypes.ARMOR_PIERCING] = 4,
			[DamageTypes.CLEAVE] = 6,
			[DamageTypes.SPEED] = 2,
			[DamageTypes.STAGGER] = 6,
			[DamageTypes.DAMAGE] = 6,
		},
		heavy_attack = {
			[DamageTypes.ARMOR_PIERCING] = 5,
			[DamageTypes.CLEAVE] = 7,
			[DamageTypes.SPEED] = 1,
			[DamageTypes.STAGGER] = 6,
			[DamageTypes.DAMAGE] = 7,
		},
	}

	local actions = template.actions
	local original = {
		action_one_default = actions.action_one.default,
		action_one_zoomed_shot = actions.action_one.zoomed_shot,
		action_two_default = actions.action_two.default,
		can_charge_shot = template.attack_meta_data.can_charge_shot,
		max_range = template.attack_meta_data.max_range,
		ammo_data = {
			reload_time = template.ammo_data.reload_time,
			ammo_immediately_available = template.ammo_data.ammo_immediately_available,
			ammo_per_clip = template.ammo_data.ammo_per_clip,
			ammo_per_reload = template.ammo_data.ammo_per_reload,
			max_ammo = template.ammo_data.max_ammo,
		},
	}

	saved.original = original

	-- This tells the bot shooting that this is the Rocket Launcher (see bots.lua). Bots fire single rockets. The crossbow's
	-- charged shot is the aiming, which loads rockets here, so bots must not use it.
	template.attack_meta_data.ut_rocket = true
	template.attack_meta_data.can_charge_shot = false
	template.attack_meta_data.max_range = CONFIG.bot_max_range

	-- All the ammo is the clip, and picked up ammo is added to it, so there is no reload between shots.
	template.ammo_data.max_ammo = CONFIG.max_ammo
	template.ammo_data.ammo_per_clip = CONFIG.max_ammo
	template.ammo_data.ammo_per_reload = CONFIG.max_ammo
	template.ammo_data.ammo_immediately_available = true
	-- Nothing should need a reload, but the game may still start one when the weapon is wielded, so the reload is made short.
	template.ammo_data.reload_time = 0.2

	actions.action_one.default = build_rocket_action(original.action_one_default, false)
	actions.action_one.zoomed_shot = build_rocket_action(original.action_one_zoomed_shot, true)

	local spiral = build_rocket_action(original.action_one_zoomed_shot, true)

	spiral.ut_rocket_spiral = true
	spiral.lookup_data.sub_action_name = SPIRAL_ACTION
	actions.action_one[SPIRAL_ACTION] = spiral

	-- The aiming loads the rockets. It has no zoom, because UT has none, and it does not slow the player down while loading.
	local aim = table.clone(original.action_two_default)
	local original_condition = aim.condition_func

	aim.ut_rocket_aim = true
	aim.condition_func = function (unit, input_extension, ammo_extension)
		if needs_release[unit] then
			return false
		end

		return not original_condition or original_condition(unit, input_extension, ammo_extension)
	end
	aim.zoom_condition_function = function ()
		return false
	end
	aim.buff_data = nil
	aim.spread_template_override = SPREAD_TEMPLATE

	aim.allowed_chain_actions = table.clone(aim.allowed_chain_actions)

	-- The primary button does not fire while loading. It makes the salvo a spiral. Reloading is not possible while loading
	-- either. The game does not allow it while zooming, and there is no zoom here to stop it.
	for i = #aim.allowed_chain_actions, 1, -1 do
		local chain = aim.allowed_chain_actions[i]

		if chain.input == "action_one" or chain.action == "weapon_reload" then
			table.remove(aim.allowed_chain_actions, i)
		end
	end

	-- The salvo is fired by itself after max_hold_time.
	aim.allowed_chain_actions[#aim.allowed_chain_actions + 1] = {
		action = "action_one",
		auto_chain = true,
		start_time = CONFIG.max_hold_time,
		sub_action = "zoomed_shot",
		ut_salvo_chain = true,
	}

	-- Releasing the aiming button fires the loaded rockets, like UT's bFireOnRelease.
	aim.allowed_chain_actions[#aim.allowed_chain_actions + 1] = {
		action = "action_one",
		auto_chain = true,
		release_required = "action_two_hold",
		start_time = 0.12,
		sub_action = "zoomed_shot",
		ut_salvo_chain = true,
	}
	actions.action_two.default = aim
end

-- Loading: the time the aiming started, for each unit. The number of rockets in a salvo depends on how long the player has been
-- loading when the salvo is fired. Firing a salvo starts the loading again.
local load_start_t = setmetatable({}, {
	__mode = "k",
})

-- The number of rockets loaded so far while loading, for each unit. It is used to tell when another rocket gets loaded.
local loading = {}

mod.aim_start_callbacks.rocket = function (self, new_action, t)
	if new_action.ut_rocket_aim then
		local ammo = self.ammo_extension and self.ammo_extension:current_ammo() or CONFIG.max_rockets

		-- The salvo is a line until the primary button is pressed. The chains are shared, so they are reset every time.
		local salvo_chains = {}

		for _, chain in ipairs(new_action.allowed_chain_actions) do
			if chain.ut_salvo_chain then
				chain.sub_action = "zoomed_shot"
				salvo_chains[#salvo_chains + 1] = chain
			end
		end

		load_start_t[self.owner_unit] = t
		loading[self.owner_unit] = {
			-- A salvo is not bigger than the ammo.
			capacity = math.min(CONFIG.max_rockets, ammo),
			first_person_unit = self.first_person_unit,
			loaded = 1,
			salvo_chains = salvo_chains,
			spiral = false,
			start_t = t,
		}
	end
end

mod.aim_finish_callbacks.rocket = function (self, reason)
	if self.current_action and self.current_action.ut_rocket_aim then
		loading[self.owner_unit] = nil

		-- Leaving the aiming for another action, such as a reload or the salvo, does not mean the button was released. The
		-- button has to be released before aiming again, or the aiming would start again at the end of the reload.
		if reason ~= "hold_input_released" then
			needs_release[self.owner_unit] = true
		end
	end
end

-- A reload that starts while the aiming button is down also needs the button released, whichever way the aiming was left for it.
-- This does nothing for other weapons, because only this weapon's aiming reads the flag.
mod:hook_safe(GenericAmmoUserExtension, "start_reload", function (self)
	local unit = self.owner_unit
	local input_extension = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "input_system")

	if input_extension and input_extension:get("action_two_hold") then
		needs_release[unit] = true
	end
end)

-- Every frame, this switches the salvo between a line and a spiral when the primary button is pressed. When another rocket gets
-- loaded, it plays the load animation and sound.
local function update_loading(t)
	for unit in pairs(needs_release) do
		local input_extension = Unit.alive(unit) and ScriptUnit.has_extension(unit, "input_system")

		if not input_extension or not input_extension:get("action_two_hold") then
			needs_release[unit] = nil
		end
	end

	for unit, state in pairs(loading) do
		local first_person_extension = Unit.alive(unit) and ScriptUnit.has_extension(unit, "first_person_system")

		if not first_person_extension then
			loading[unit] = nil
		else
			-- Each press of the primary button switches the salvo between a line and a spiral. A press is the button going
			-- down, so holding it does not switch back and forth every frame. A button that was already down when the aiming
			-- started does not count.
			local input_extension = ScriptUnit.has_extension(unit, "input_system")

			if input_extension then
				local primary_down = not not (input_extension:get("action_one") or input_extension:get("action_one_hold"))

				if state.primary_down == false and primary_down then
					state.spiral = not state.spiral

					for _, chain in ipairs(state.salvo_chains) do
						chain.sub_action = state.spiral and SPIRAL_ACTION or "zoomed_shot"
					end
				end

				state.primary_down = primary_down
			end

			local loaded = math.clamp(1 + math.floor((t - state.start_t) / CONFIG.load_interval), 1, math.max(state.capacity, 1))

			if loaded > state.loaded then
				state.loaded = loaded

				for _, callback in pairs(mod.rocket_load_callbacks) do
					callback(unit, loaded)
				end

				if CONFIG.load_animation_event then
					CharacterStateHelper.play_animation_event(unit, CONFIG.load_animation_event)
					CharacterStateHelper.play_animation_event_first_person(first_person_extension, CONFIG.load_animation_event)
				end

				if CONFIG.load_flow_event and Unit.alive(state.first_person_unit) then
					Unit.flow_event(state.first_person_unit, CONFIG.load_flow_event)
				end

				if CONFIG.load_sound_event then
					first_person_extension:play_hud_sound_event(CONFIG.load_sound_event)
				end
			end
		end
	end
end

-- Fires the spiral salvo. The rockets start in a ring around the aim, all in the same direction.
local function fire_spiral(self, action, count)
	local owner_unit = self.owner_unit
	local first_person_extension = ScriptUnit.extension(owner_unit, "first_person_system")
	local position, rotation = first_person_extension:get_projectile_start_position_rotation()
	local right = Quaternion.right(rotation)
	local up = Quaternion.up(rotation)
	local forward = Quaternion.forward(rotation)
	local angle = ActionUtils.pitch_from_rotation(rotation)
	local target_vector = Vector3.normalize(Vector3.flat(Quaternion.forward(rotation)))
	local lookup_data = action.lookup_data

	for i = 1, count do
		local offset = Vector3(0, 0, 0)

		if count > 1 then
			local ring_angle = (i - 1) * 2 * math.pi / CONFIG.max_rockets

			-- In UT, a point of the ring turns to the left as the angle grows, and the first one is at the top.
			offset = right * (CONFIG.spiral_ring_right - math.sin(ring_angle) * CONFIG.spiral_ring_radius)
				+ up * (math.cos(ring_angle) * CONFIG.spiral_ring_radius - CONFIG.spiral_ring_down)
				- forward * (CONFIG.spiral_start_back * math.random())
		end

		ActionUtils.spawn_player_projectile(owner_unit, position + offset, rotation, 0, angle, target_vector, action.speed, self.item_name, lookup_data.item_template_name, lookup_data.action_name, lookup_data.sub_action_name, self._is_critical_strike, self.power_level)

		if self.ammo_extension then
			self.ammo_extension:use_ammo(action.ammo_usage)
		end
	end
end

mod.crossbow_start_callbacks.rocket = function (self, new_action, t)
	if not new_action.ut_rocket_salvo then
		return
	end

	local held = t - (load_start_t[self.owner_unit] or t)
	local loaded = math.clamp(1 + math.floor(held / CONFIG.load_interval), 1, CONFIG.max_rockets)

	self.num_projectiles = self.ammo_extension and math.min(loaded, self.ammo_extension:current_ammo()) or loaded
	load_start_t[self.owner_unit] = t
	needs_release[self.owner_unit] = true

	-- The crossbow's own code fires nothing for a spiral. The rockets are fired here.
	if new_action.ut_rocket_spiral then
		fire_spiral(self, new_action, self.num_projectiles)

		self.num_projectiles = 0
	end
end

-- The flock of a spiral salvo, from RocketProj.Timer. The rockets that start together are a flock. Every pull_interval seconds,
-- each rocket is pulled back towards the direction it was fired in, and it gets an acceleration from its neighbor. The neighbor
-- attracts or repels it depending on the distance, and makes it curl around the neighbor, the opposite way for rockets with a
-- different curl. Every frame, the path of a rocket is re-based on its current position and velocity.
local flocks = {}
local latest_flock = setmetatable({}, {
	__mode = "k",
})

mod.init_callbacks.rocket = function (extension)
	local action = extension._current_action

	if not action or not action.ut_rocket_spiral then
		return
	end

	local t = Managers.time:time("game")
	local owner_unit = extension._owner_unit
	local flock = latest_flock[owner_unit]

	if not flock or t - flock.t > 0.25 or #flock.members >= CONFIG.max_rockets then
		flock = {
			members = {},
			next_curl = false,
			pull_t = CONFIG.spiral_pull_interval,
			t = t,
		}
		flocks[#flocks + 1] = flock
		latest_flock[owner_unit] = flock
	end

	flock.members[#flock.members + 1] = {
		curl = flock.next_curl,
		unit = extension._projectile_unit,
	}
	flock.next_curl = not flock.next_curl
end

-- Makes the trajectory of a rocket continue from the given position with the given velocity.
local function steer(locomotion_extension, position, velocity)
	local speed = Vector3.length(velocity)

	if speed < 0.01 then
		return
	end

	local direction = velocity * (1 / speed)
	local flat = Vector3.flat(direction)
	local flat_length = Vector3.length(flat)

	locomotion_extension.initial_position_boxed:store(position)

	if flat_length > 0.001 then
		locomotion_extension.target_vector_boxed:store(flat * (1 / flat_length))
	end

	locomotion_extension.radians = math.asin(math.clamp(direction.z, -1, 1))
	locomotion_extension.speed = speed * 100
	-- The locomotion moves the rocket by the time since its last update.
	locomotion_extension.spawn_time = locomotion_extension.t
end

local function update_flocks(dt)
	for i = #flocks, 1, -1 do
		local flock = flocks[i]
		local live = {}

		for _, member in ipairs(flock.members) do
			local locomotion_extension = Unit.alive(member.unit) and ScriptUnit.has_extension(member.unit, "projectile_locomotion_system")

			-- A rocket that homes in is steered by that instead, so it leaves the flock.
			if locomotion_extension and not locomotion_extension.stopped and not locomotion_extension.true_flight_template then
				if not member.velocity then
					local direction = Vector3.normalize(Vector3.flat(locomotion_extension.target_vector_boxed:unbox())) * math.cos(locomotion_extension.radians) + Vector3(0, 0, math.sin(locomotion_extension.radians))
					local speed = locomotion_extension.speed / 100

					member.acceleration = Vector3Box(0, 0, 0)
					member.forward = Vector3Box(direction)
					member.speed = speed
					member.velocity = Vector3Box(direction * speed)
				end

				member.locomotion_extension = locomotion_extension
				live[#live + 1] = member
			end
		end

		if #live == 0 then
			table.remove(flocks, i)
		else
			flock.pull_t = flock.pull_t - dt

			local timer_tick = flock.pull_t <= 0

			if timer_tick then
				flock.pull_t = CONFIG.spiral_pull_interval
			end

			for _, member in ipairs(live) do
				local position = member.locomotion_extension:current_position()
				local velocity = member.velocity:unbox()

				if timer_tick then
					velocity = member.speed * Vector3.normalize(member.forward:unbox() * 0.5 * member.speed + velocity)

					local acceleration = Vector3(0, 0, 0)

					for _, other in ipairs(live) do
						if other ~= member then
							local offset = other.locomotion_extension:current_position() - position
							local distance = Vector3.length(offset)

							if distance > 0.001 then
								local magnitude = CONFIG.spiral_stiffness * (2 * CONFIG.spiral_flock_radius - distance)
								-- UT's axes are left handed, so its cross product points the other way. The factors are swapped to match.
								local curl = Vector3.cross(offset, other.velocity:unbox())
								local curl_length = Vector3.length(curl)

								acceleration = offset * (1 / distance) * math.min(magnitude, CONFIG.spiral_max_force)

								if curl_length > 0.001 then
									acceleration = acceleration + curl * (1 / curl_length) * (other.curl == member.curl and CONFIG.spiral_curl_force or -CONFIG.spiral_curl_force)
								end
							end
						end
					end

					member.acceleration:store(acceleration)
				end

				velocity = velocity + member.acceleration:unbox() * dt

				member.velocity:store(velocity)
				steer(member.locomotion_extension, position, velocity)
			end
		end
	end
end

-- Lock-on uses the game's true flight projectiles. A true flight template holds the settings, with an id that is sent over the
-- network. The movement towards the target is a method of the projectile's locomotion extension, and the template names it.
local TRUE_FLIGHT_TEMPLATE = "ut_rocket"

local function register_true_flight_template()
	local template = TrueFlightTemplates[TRUE_FLIGHT_TEMPLATE] or {}

	template.broadphase_radius = 5
	template.dot_threshold = 1
	template.initial_target_node = "c_spine"
	template.target_node = "c_spine"
	template.legitimate_target_func = "legitimate_always"
	-- This is the game's own steering of its true flight projectiles.
	template.target_tracking_check_func = "update_towards_target"
	-- When the target is gone, the rocket flies straight on and does not look for another one.
	template.max_on_target_time = 0
	template.speed_multiplier = 0.01
	template.time_between_raycasts = 0.1
	template.lerp_constant = 50
	template.lerp_squared_distance_threshold = 2000

	if not template.lookup_id then
		local lookup_id = #TrueFlightTemplatesLookup + 1

		template.lookup_id = lookup_id
		TrueFlightTemplatesLookup[lookup_id] = TRUE_FLIGHT_TEMPLATE
	end

	TrueFlightTemplates[TRUE_FLIGHT_TEMPLATE] = template
end

register_true_flight_template()

local function spine_position(unit)
	local node = Unit.has_node(unit, "c_spine") and Unit.node(unit, "c_spine") or 0

	return Unit.world_position(unit, node)
end

-- The lock of the local player. It holds the enemy the crosshair has been on, for how long, and whether it is a lock yet.
local locks = {}

local function wielding_rocket_launcher(unit)
	return utils.wielded_template_name(unit) == TEMPLATE_NAME
end

-- Returns the enemy closest to the aim that is in front of the player, close enough to the aim and not behind a wall. If no
-- enemy is on the aim, the current target stays the candidate while it is within the wider lock_keep_dot of the aim.
local function pick_lock_candidate(unit, first_person_extension, current_target)
	local side = Managers.state.side.side_by_unit[unit]
	local origin = first_person_extension:current_position()
	local forward = Quaternion.forward(first_person_extension:current_rotation())
	local ai_units = {}
	local count = AiUtils.broadphase_query(origin + forward * (CONFIG.lock_range / 2), CONFIG.lock_range / 2 + 2, ai_units, side and side.enemy_broadphase_categories)
	local physics_world = World.get_data(Managers.world:world("level_world"), "physics_world")
	local best_unit
	local best_dot = CONFIG.lock_aim_dot
	local kept_unit

	for i = 1, count do
		local candidate = ai_units[i]
		local breed = HEALTH_ALIVE[candidate] and AiUtils.unit_breed(candidate)

		if breed and not breed.no_autoaim and not breed.is_player then
			local offset = spine_position(candidate) - origin
			local distance = Vector3.length(offset)

			if distance > 0.1 and distance <= CONFIG.lock_range then
				local direction = offset * (1 / distance)
				local dot = Vector3.dot(forward, direction)
				local is_kept = candidate == current_target and dot > CONFIG.lock_keep_dot

				if is_kept or dot > best_dot then
					local hit, _, hit_distance = PhysicsWorld.immediate_raycast(physics_world, origin, direction, distance, "closest", "collision_filter", "filter_ai_line_of_sight_check")

					if not hit or hit_distance > distance - 0.5 then
						if is_kept then
							kept_unit = candidate
						end

						if dot > best_dot then
							best_unit = candidate
							best_dot = dot
						end
					end
				end
			end
		end
	end

	-- An enemy on the aim wins, whether or not it is the target. The target is only held on to (kept_unit) while no other enemy
	-- is on the aim, so the lock moves to another enemy as soon as the aim is on it.
	return best_unit or kept_unit
end

-- The red outline of the game's target marking. The true flight bow puts it on the enemy it is aimed at.
local clear_lock_outline = utils.clear_outline

local function add_lock_outline(state)
	if CONFIG.lock_outline then
		utils.add_outline(state, state.target, OutlineSettings.templates.target_enemy)
	end
end

local function reset_lock(state)
	clear_lock_outline(state)

	state.candidate = nil
	state.candidate_time = 0
	state.fired = nil
	state.locked = false
	state.lock_time = 0
	state.target = nil
	state.unlock_time = 0
end

local function update_lock_on(dt)
	local player = Managers.player:local_player_safe()
	local unit = player and player.player_unit

	-- Remove the lock of a unit that is gone, or of a weapon that is not wielded.
	for locked_unit, locked_state in pairs(locks) do
		if locked_unit ~= unit or not Unit.alive(unit) or not HEALTH_ALIVE[unit] or not wielding_rocket_launcher(unit) then
			clear_lock_outline(locked_state)

			locks[locked_unit] = nil
		end
	end

	if not unit or not HEALTH_ALIVE[unit] or not wielding_rocket_launcher(unit) then
		return
	end

	local state = locks[unit]

	if not state then
		state = {}
		reset_lock(state)
		locks[unit] = state
	end

	-- The lock is kept while a rocket that was fired with it is still on its way to the enemy, which can be after the aiming has
	-- ended. Those rockets belong to the lock, so they are as locked on as it is. The lock is used up when they are gone.
	local rockets_on_their_way = state.fired and (Managers.time:time("game") - state.fired_t < 0.5 or mod.rocket_homing_on(state.target))

	-- A lock exists only while loading, which means holding the secondary button. Without it there is no lock, and letting go of
	-- it ends the lock.
	if not loading[unit] then
		if (state.target or state.locked) and not rockets_on_their_way then
			reset_lock(state)
		end

		return
	end

	if state.fired and not rockets_on_their_way then
		reset_lock(state)
	end

	if state.target and not HEALTH_ALIVE[state.target] then
		reset_lock(state)
	end

	local first_person_extension = ScriptUnit.has_extension(unit, "first_person_system")
	local candidate = first_person_extension and pick_lock_candidate(unit, first_person_extension, state.candidate or state.target)
	local interval = dt

	if state.locked then
		-- Moving the aim off the locked enemy does not unlock it. Only locking on to another enemy does, which takes the aim on
		-- that enemy for lock_required_time.
		if candidate and candidate ~= state.target then
			if candidate == state.candidate then
				state.candidate_time = state.candidate_time + interval

				if state.candidate_time >= CONFIG.lock_required_time then
					clear_lock_outline(state)

					state.target = candidate
					state.candidate = nil
					-- The rockets that were fired belong to the lock that is gone, so they must not use up the new lock.
					state.fired = nil

					add_lock_outline(state)

					for _, callback in pairs(mod.rocket_lock_callbacks) do
						callback(unit, true)
					end
				end
			else
				state.candidate = candidate
				state.candidate_time = 0
			end
		else
			state.candidate = nil
		end
	elseif candidate then
		if candidate == state.target then
			state.unlock_time = 0
			state.lock_time = state.lock_time + interval

			if not state.locked and state.lock_time >= CONFIG.lock_required_time then
				state.locked = true

				add_lock_outline(state)

				for _, callback in pairs(mod.rocket_lock_callbacks) do
					callback(unit, true)
				end
			end
		else
			reset_lock(state)
			state.target = candidate
		end
	elseif state.target then
		state.unlock_time = state.unlock_time + interval

		if state.unlock_time >= CONFIG.unlock_required_time then
			if state.locked then
				for _, callback in pairs(mod.rocket_lock_callbacks) do
					callback(unit, false)
				end
			end

			reset_lock(state)
		end
	end
end

-- Returns where a rocket starts: in front of the camera, to its right and below it, like RocketFire.ProjSpawnOffset (25, 6 and -6
-- units). A rocket that would start behind a wall starts at the wall instead, because RocketFire.DoFireEffect traces to it.
local function start_position(position, rotation)
	position = utils.as_vector(position)

	-- The game's spread rolls the rotation of a shot by a random angle about the way it points, whatever the spread numbers are.
	-- So right and up are taken from the way it points alone. Otherwise the offset would turn about the aim from shot to shot.
	local level = Quaternion.look(Quaternion.forward(rotation), Vector3.up())
	local offset = Quaternion.forward(level) * CONFIG.start_forward + Quaternion.right(level) * CONFIG.start_right - Quaternion.up(level) * CONFIG.start_down
	local distance = Vector3.length(offset)
	local direction = offset * (1 / distance)
	local physics_world = World.get_data(Managers.world:world("level_world"), "physics_world")
	local hit, _, hit_distance = PhysicsWorld.immediate_raycast(physics_world, position, direction, distance, "closest", "collision_filter", "filter_ai_line_of_sight_check")

	if hit then
		return position + direction * math.max(hit_distance - 0.05, 0)
	end

	return position + offset
end

-- The rockets start where UT's do. A rocket fired while there is a lock is a true flight projectile with the locked enemy as its
-- target.
mod.spawn_projectile_callbacks[TEMPLATE_NAME] = function (func, owner_unit, position, rotation, scale, angle, target_vector, speed, item_name, item_template_name, action_name, sub_action_name, ...)
	local template = rawget(Weapons, item_template_name)
	local sub_actions = template and template.actions[action_name]
	local action = sub_actions and sub_actions[sub_action_name]

	if action and action.ut_rocket then
		position = start_position(position, rotation)

		local state = locks[owner_unit]

		if state and state.locked and HEALTH_ALIVE[state.target] then
			state.fired = true
			state.fired_t = Managers.time:time("game")

			-- A true flight projectile is given the direction it is fired in, not just the flat part of it.
			ActionUtils.spawn_true_flight_projectile(owner_unit, state.target, TrueFlightTemplates[TRUE_FLIGHT_TEMPLATE].lookup_id, position, rotation, angle, Vector3.normalize(Quaternion.forward(rotation)), speed, item_name, item_template_name, action_name, sub_action_name, 1, ...)

			return
		end
	end

	return func(owner_unit, position, rotation, scale, angle, target_vector, speed, item_name, item_template_name, action_name, sub_action_name, ...)
end

-- The crosshair while loading shows a pip for each rocket that can be loaded, and the loaded ones are lit. The pips are drawn in
-- the crosshair's pass, after the rest of the crosshair.
local PIPS_TOKEN = {}

-- A texture is drawn from the top left corner of the crosshair's dot, which is 4 pixels and centered, to the right and down. So a
-- pip bigger than the dot is moved to put its center where it should be.
local CROSSHAIR_DOT_SIZE = 4

-- Returns where a pip is, measured from the center of the crosshair. The pips are in a row, or in a triangle for a spiral.
local function pip_position(index, spiral)
	local x, y

	if spiral then
		-- The pips go in the order of a clock's hands: bottom left, top, bottom right.
		if index == 2 then
			x, y = 0, CONFIG.pip_offset_y
		else
			x, y = (index == 1 and -1 or 1) * CONFIG.pip_spiral_side_x, CONFIG.pip_spiral_side_y
		end
	else
		x, y = (index - (CONFIG.max_rockets + 1) / 2) * CONFIG.pip_spacing, CONFIG.pip_offset_y
	end

	local correction = (CONFIG.pip_size - CROSSHAIR_DOT_SIZE) / 2

	return x - correction, y + correction
end

local function create_pips()
	local pips = {}

	for i = 1, CONFIG.max_rockets do
		local color = table.clone(CONFIG.pip_loaded_color)
		local offset_x = pip_position(i, false)

		pips[i] = UIWidget.init({
			element = UIElements.SimpleTexture,
			scenegraph_id = "crosshair_dot",
			content = {
				texture_id = CONFIG.pip_texture,
			},
			style = {
				color = color,
				offset = {
					offset_x,
					CONFIG.pip_offset_y,
					2,
				},
				texture_size = {
					CONFIG.pip_size,
					CONFIG.pip_size,
				},
			},
		})
	end

	return pips
end

mod:hook_safe(CrosshairUI, "_draw_kill_confirm", function (self, dt, t, ui_renderer)
	local player = Managers.player:local_player_safe()
	local player_unit = player and player.player_unit
	local lock = player_unit and locks[player_unit]

	-- When locked on, the crosshair gets arrows around it.
	if CONFIG.lock_indicator and lock and lock.locked then
		self:draw_arrows_style_crosshair(ui_renderer, CONFIG.lock_arrows_spread, CONFIG.lock_arrows_spread)
	end

	local state = player_unit and loading[player_unit]

	if not CONFIG.crosshair_pips or not state then
		return
	end

	-- The pips are kept in the crosshair, which outlives a reload of the mod. So they are made again after a reload.
	if self._ut_rocket_pips_token ~= PIPS_TOKEN then
		self._ut_rocket_pips = create_pips()
		self._ut_rocket_pips_token = PIPS_TOKEN
	end

	for i, pip in ipairs(self._ut_rocket_pips) do
		if i <= state.capacity then
			local offset_x, offset_y = pip_position(i, state.spiral)

			pip.style.offset[1] = offset_x
			pip.style.offset[2] = offset_y
			pip.style.color[1] = i <= state.loaded and CONFIG.pip_loaded_color[1] or CONFIG.pip_empty_alpha

			UIRenderer.draw_widget(ui_renderer, pip)
		end
	end
end)

-- The explosion hurts the player who fired it. The hook of do_aoe in hooks.lua runs the callbacks of the actions.
mod.aoe_callbacks.rocket = function (self, aoe_data, position)
	if self._ut_rocket_exploded then
		return
	end

	self._ut_rocket_exploded = true

	utils.apply_explosion_self_damage(self._owner_unit, position, self.item_name, ExplosionTemplates.ut_rocket_explosion.explosion, CONFIG.rocket_self_damage)
end

-- It throws every player near it.
mod.explosion_push_speeds.ut_rocket_explosion = function ()
	return CONFIG.rocket_jump_speed
end

-- Bodies thrown by the explosion. This runs on every peer, because the physics of ragdolls is local. The units near the
-- explosion are collected when it goes off. The ones that die are thrown once their ragdoll has started, because before that
-- the actors are driven by animation.
local blasts = {}

local function update_blasts()
	local t = Managers.time:time("game")

	for i = #blasts, 1, -1 do
		local blast = blasts[i]
		local center = blast.position:unbox()

		for unit in pairs(blast.units) do
			if not Unit.alive(unit) then
				blast.units[unit] = nil
			elseif not HEALTH_ALIVE[unit] and utils.blast_ragdoll(unit, center) then
				blast.units[unit] = nil
			end
		end

		if t - blast.t > CONFIG.ragdoll_window or next(blast.units) == nil then
			table.remove(blasts, i)
		end
	end
end

-- The look of the explosion on every peer. The explosion's callback runs for everyone who sees it.
mod.explosion_callbacks.ut_rocket_explosion = function (world, position)
	-- The look itself comes from the skin (see skin_explosion_callbacks). This only collects the bodies to throw.
	local radius = ExplosionTemplates.ut_rocket_explosion.explosion.radius

	blasts[#blasts + 1] = {
		position = Vector3Box(position),
		radius = radius,
		t = Managers.time:time("game"),
		units = utils.units_in_radius(world, position, radius),
	}
end

mod.enabled_callbacks[#mod.enabled_callbacks + 1] = apply_rocket_launcher
mod.disabled_callbacks[#mod.disabled_callbacks + 1] = restore_crossbow
mod.unload_callbacks[#mod.unload_callbacks + 1] = restore_crossbow

-- A rocket explodes when it touches a Flak shell or a Shock ball (RocketProj.ProcessTouch and their bProjTarget). The shell also
-- explodes when a rocket gets near it. See flak_cannon.lua.
local function detonate_on_projectiles()
	local projectiles = utils.flying_projectiles()

	if not projectiles or #projectiles == 0 then
		return
	end

	for _, rocket in ipairs(projectiles) do
		local extension = rocket.extension

		if rocket.own and extension._current_action.ut_rocket and not extension._stop_impacts and not extension._ut_rocket_exploded then
			local position = Unit.world_position(rocket.unit, 0)

			for _, other in ipairs(projectiles) do
				local action = other.extension._current_action
				local other_position = Unit.world_position(other.unit, 0)

				if other ~= rocket and (action.ut_flak_shell or action.ut_shock_ball) and not other.extension._stop_impacts and other_position and Vector3.distance(position, other_position) < CONFIG.projectile_touch_radius then
					extension:do_aoe(ExplosionTemplates.ut_rocket_explosion, position, true)
					extension:stop()

					break
				end
			end
		end
	end
end

mod.update_callbacks[#mod.update_callbacks + 1] = function (dt)
	detonate_on_projectiles()
	update_blasts()
	update_flocks(dt)
	update_lock_on(dt)
	update_loading(Managers.time:time("game"))
end

mod.unload_callbacks[#mod.unload_callbacks + 1] = function ()
	table.clear(blasts)
	table.clear(flocks)

	for _, locked_state in pairs(locks) do
		clear_lock_outline(locked_state)
	end

	table.clear(locks)
	table.clear(loading)
end

mod.level_exit_callbacks[#mod.level_exit_callbacks + 1] = function ()
	table.clear(blasts)
	table.clear(flocks)

	for _, locked_state in pairs(locks) do
		clear_lock_outline(locked_state)
	end

	table.clear(locks)
	table.clear(loading)
	table.clear(needs_release)
end
