local mod = get_mod("unreal_tournament")

-- Rocket Launcher: replaces the Repeating Crossbow's (the witch hunter's) actions in place, like the Flak
-- Cannon does with the Blunderbuss. The numbers are from UT2004 (XWeapons/RocketFire, RocketMultiFire,
-- RocketProj).
--   LMB: a rocket that explodes where it hits.
--   RMB (held): loads rockets, one at first and another every load_interval seconds, up to three.
--               LMB then fires them all in a line.
-- Ammo and reload are the crossbow's own.

local registration = mod:dofile("scripts/mods/unreal_tournament/registration")
local effects = mod:dofile("scripts/mods/unreal_tournament/effects")
local register_damage_profile = registration.register_damage_profile
local register_explosion_template = registration.register_explosion_template
local register_network_lookup = registration.register_network_lookup
local make_flat = registration.make_flat
local attack_power_for = registration.attack_power_for
local impact_power_for = registration.impact_power_for

local TEMPLATE_NAME = "repeating_crossbow_template_1"
local SPIRAL_ACTION = "zoomed_shot_spiral" -- the sub action of the salvo that is a spiral

-- The weapon can be switched off in the settings: the crossbow is then the game's own again (the weapon
-- the player holds changes when it is wielded again)
local function is_rocket_launcher_enabled()
	return mod:get("ut_weapons") ~= false and mod:get("rocket_launcher") ~= false
end

register_network_lookup("sub_actions", SPIRAL_ACTION)

local CONFIG = {
	meters_per_uu = 0.02, -- Unreal unit to meters
	-- Rocket
	rocket_speed = 2200, -- RocketProj.Speed 1350 uu/s is 27 m/s by size and 12 m/s by run speed, this is in between (the action's unit is m/s * 100)
	rocket_lifetime = 8, -- seconds
	rocket_radius = 0.1, -- m, how easily a rocket hits things
	rocket_gravity_settings = "spark", -- the game's gravity setting with the least gravity
	fire_interval = 0.9, -- seconds, RocketFire.FireRate
	-- Ammo (the crossbow's is 15 in a clip and 48 in all). UT's RocketAmmo.MaxAmmo is 30.
	ammo_per_clip = 9,
	max_ammo = 36, -- four clips
	-- The damage and radius of the explosion are the same as the Flak Cannon's shell: UT has 90 and 220 uu for
	-- both, and they were reduced in the same way
	rocket_damage = 60,
	-- The damage multipliers of the explosion per armor type: unarmored, armored, monsters, players,
	-- berserkers, super armor (the explosion hits harder what is big)
	rocket_armor_attack = {
		1,
		1.25,
		2.5,
		1,
		1,
		0.75,
	},
	rocket_explosion_radius_uu = 150,
	rocket_explosion_full_damage_radius = 0.5, -- damage falls off linearly from here to the radius
	-- The explosion hurts the player who fired the rocket: this much at the center, falling off like
	-- the explosion's damage does
	rocket_self_damage = 45,
	-- Loading: RocketMultiFire. One rocket right away, the second after FireRate (0.95 s), the third after
	-- twice that. They are fired in a line, 1000 uu of UT's spread units between them (5.5 degrees).
	max_rockets = 3,
	load_interval = 0.65, -- seconds, UT's is 0.95 which is slower than the 0.9 s of regular fire, this is faster
	-- The loaded rockets are fired by themselves after this long, whatever the ammo. (UT: MaxHoldTime is
	-- 2.3 s, only 0.4 s after the third rocket, which felt too short here. It also fires right away when
	-- the last of the ammo is loaded, that is not done here.)
	max_hold_time = 4, -- seconds
	rocket_line_spread = 0.096, -- radians between two rockets
	-- The spiral: pressing the primary button while loading makes the salvo a spiral instead of a line (UT's
	-- tight spread). The rockets start in a ring around the aim and fly as a flock, RocketProj.Timer: they
	-- are pulled towards each other when they are further apart than twice the flock radius and pushed
	-- away when closer, and curl around each other. (UT's values, in meters.)
	spiral_ring_radius = 0.32, -- 16 uu
	spiral_flock_radius = 0.24, -- FlockRadius 12 uu
	spiral_stiffness = -40, -- FlockStiffness
	spiral_max_force = 12, -- m/s^2, FlockMaxForce 600 uu/s^2
	spiral_curl_force = 9, -- m/s^2, FlockCurlForce 450 uu/s^2
	spiral_pull_interval = 0.1, -- seconds, how often the rockets are pulled back towards their direction
	-- Lock-on, like UT's: keep the crosshair on an enemy for lock_required_time and the rockets fired after that
	-- home in on it, using the game's true flight projectiles (the position of those is synced, so everyone sees
	-- them home in). The lock is lost after unlock_required_time off the enemy, and by firing. (UT: 1.25 s, 0.5 s,
	-- the target has to be within 0.996 of the aim, which is 5 degrees, and 8000 uu away.) The rockets of a spiral
	-- salvo start in their ring and home in too, which takes them out of the flock.
	lock_range = 50, -- m
	lock_aim_dot = 0.995, -- how close to the aim the enemy has to be, 1 is exactly
	lock_keep_dot = 0.95, -- how far from the aim an enemy that is locked can be without it counting as being off it (18 degrees)
	lock_required_time = 0.4, -- seconds (UT's is 1.25)
	unlock_required_time = 1.5, -- seconds the aim has to be off the locked enemy before the lock is lost (UT's is 0.5)
	lock_check_interval = 0.1, -- seconds, UT's is 0.5
	seek_delay = 0.35, -- seconds a rocket flies straight after being fired before it starts to home in
	seek_turn_rate = 3.5, -- radians per second, how fast a rocket can turn towards its target
	lock_outline = true, -- the locked enemy gets the red outline of the game's target marking (like the true flight bow's)
	lock_indicator = false, -- the crosshair gets arrows around it while locked
	lock_arrows_spread = 0.3, -- how far from the center the arrows are
	lock_sound_event = false, -- played when the lock is made, a sound event of the game's HUD (false for none)
	-- When another rocket is loaded the weapon plays an animation (false for none: "attack_shoot" is the
	-- animation of firing while aiming, its sound is the sound of a shot), and a flow event of the weapon's
	-- units (the game triggers these for the sounds of handling a weapon: "sfx_ranged_weapon_foley" is the
	-- rustle of it, "sfx_ranged_weapon_equip" the sound of wielding it)
	load_animation_event = false,
	-- the camera kicks a little when a rocket is loaded
	load_kick = {
		climb_duration = 0.075,
		horizontal_climb = 0,
		restore_duration = 0.3,
		vertical_climb = 0.6,
		climb_function = math.ease_out_quad,
		restore_function = math.ease_out_quad,
	},
	load_flow_event = "sfx_ranged_weapon_equip",
	-- The crosshair shows a pip for each rocket that can be loaded, the loaded ones lit, while loading
	crosshair_pips = true,
	pip_texture = "crosshair_01_center",
	pip_size = 9, -- pixels at 1080p
	pip_spacing = 18,
	pip_offset_y = 7, -- from the center of the crosshair, positive is up
	pip_loaded_color = {
		255,
		255,
		170,
		40,
	}, -- alpha, red, green, blue
	pip_empty_alpha = 70,
	-- When the salvo will be a spiral the pips are in a triangle instead of a row: the second stays where the
	-- middle one of the row is, the first and third are below the lines to the left and right of the crosshair's
	-- center, this far from the center sideways and down (negative is down):
	pip_spiral_side_x = 16,
	pip_spiral_side_y = -15,
	-- and a sound of the game's HUD (false for none)
	load_sound_event = false,
	-- The visual of the explosion: these effects are played together, each that is loaded for the
	-- weapon's character (the others are skipped)
	explosion_effects = {
		{
			name = "fx/wpnfx_frag_grenade_impact",
			scale = 1,
			offset = 0,
		},
		{
			name = "fx/wpnfx_barrel_explosion",
			scale = 0.5,
			offset = 0,
		},
	},
	-- Whatever dies of the explosion is thrown away from it (the game's own push is small)
	ragdoll_speed = 25, -- m/s, a little less for bodies far from the center
	ragdoll_up = 6, -- m/s added upwards
	ragdoll_window = 1.5, -- seconds a body has to start ragdolling after the explosion
}

-- Damage profiles: the direct hit of the rocket only staggers, its damage is the explosion, which is at
-- full strength for whatever the rocket hits (like in UT)
register_damage_profile("ut_rocket", "staff_fireball", function (profile)
	make_flat(profile, 0, impact_power_for(CONFIG.rocket_damage))

	profile.cleave_distribution = {
		attack = 0.01,
		impact = 0.01,
	}
end)

local function modify_explosion_profile(profile)
	make_flat(profile, attack_power_for(CONFIG.rocket_damage), impact_power_for(CONFIG.rocket_damage))

	-- more damage against monsters (and armor)
	profile.armor_modifier.attack = table.clone(CONFIG.rocket_armor_attack)
end

register_damage_profile("ut_rocket_explosion", "fireball_charged_explosion", modify_explosion_profile)
register_damage_profile("ut_rocket_explosion_glance", "fireball_charged_explosion_glance", modify_explosion_profile)

-- The effect of the explosion is played by the code below, only if the game has it loaded
register_explosion_template("ut_rocket_explosion", {
	explosion = {
		alert_enemies = true,
		alert_enemies_radius = 15,
		attacker_power_level_offset = 1,
		damage_profile = "ut_rocket_explosion",
		damage_profile_glance = "ut_rocket_explosion_glance",
		-- the shooter is hurt separately, see rocket_self_damage
		ignore_attacker_unit = true,
		max_damage_radius = CONFIG.rocket_explosion_full_damage_radius,
		radius = CONFIG.rocket_explosion_radius_uu * CONFIG.meters_per_uu,
		sound_event_name = "player_combat_weapon_grenade_explosion",
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
-- The sub actions keep their names (default is the rocket, zoomed_shot the loaded rockets), only what
-- they are made of changes.

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
	action.ut_rocket = true
	action.spread_template_override = nil

	-- grenade: the explosion is set off by the first enemy it hits, like a grenade
	action.impact_data = {
		aoe = ExplosionTemplates.ut_rocket_explosion,
		damage_profile = "ut_rocket",
		grenade = true,
	}

	-- the next shot can be fired as soon as the rocket launcher can
	for _, chain in ipairs(action.allowed_chain_actions) do
		if chain.action == "action_one" then
			chain.start_time = CONFIG.fire_interval
		end
	end

	if is_salvo then
		action.num_projectiles = CONFIG.max_rockets
		action.multi_projectile_spread = CONFIG.rocket_line_spread
		action.ut_rocket_salvo = true

		-- firing the salvo ends the aiming: the weapon goes back to neutral, and aiming again needs
		-- the button to be released first (see needs_release)
		action.hold_input = nil
		action.minimum_hold_time = nil
		action.total_time = CONFIG.fire_interval
		action.ut_init_callback = "rocket"

		-- (no reloading during it either, like in the aiming)
		for i = #action.allowed_chain_actions, 1, -1 do
			local chain = action.allowed_chain_actions[i]

			if chain.sub_action == "zoomed_shot" or chain.action == "weapon_reload" then
				table.remove(action.allowed_chain_actions, i)
			end
		end
	else
		action.total_time = CONFIG.fire_interval
	end

	return action
end

-- After a salvo the player has to release the aiming button before aiming again, per unit
local needs_release = setmetatable({}, {
	__mode = "k",
})

-- The template is shared game state: it is patched in place, what is touched is saved to be put
-- back on disable. The saved values are in a persistent table, so that a mod reload doesn't take
-- the patched template for the original.
local persistent = mod:persistent_table("rocket_launcher")

local function restore_crossbow()
	local original = persistent.original
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not original or not template then
		return
	end

	local actions = template.actions

	actions.action_one.default = original.action_one_default
	actions.action_one.zoomed_shot = original.action_one_zoomed_shot
	actions.action_one[SPIRAL_ACTION] = nil
	actions.action_two.default = original.action_two_default

	-- (a patch from before the ammo was changed has none saved)
	for key, value in pairs(original.ammo_data or {}) do
		template.ammo_data[key] = value
	end

	persistent.original = nil
end

local function apply_rocket_launcher()
	local template = rawget(Weapons, TEMPLATE_NAME)

	if not template then
		return
	end

	-- Already applied by a previous load of this mod, start over from the original
	restore_crossbow()

	local actions = template.actions
	local original = {
		action_one_default = actions.action_one.default,
		action_one_zoomed_shot = actions.action_one.zoomed_shot,
		action_two_default = actions.action_two.default,
		ammo_data = {
			ammo_per_clip = template.ammo_data.ammo_per_clip,
			ammo_per_reload = template.ammo_data.ammo_per_reload,
			max_ammo = template.ammo_data.max_ammo,
		},
	}

	persistent.original = original

	template.ammo_data.ammo_per_clip = CONFIG.ammo_per_clip
	template.ammo_data.ammo_per_reload = CONFIG.ammo_per_clip
	template.ammo_data.max_ammo = CONFIG.max_ammo

	actions.action_one.default = build_rocket_action(original.action_one_default, false)
	actions.action_one.zoomed_shot = build_rocket_action(original.action_one_zoomed_shot, true)

	local spiral = build_rocket_action(original.action_one_zoomed_shot, true)

	spiral.ut_rocket_spiral = true
	spiral.lookup_data.sub_action_name = SPIRAL_ACTION
	actions.action_one[SPIRAL_ACTION] = spiral

	-- the aiming loads the rockets: no zoom (UT has none) and no slowing down while loading
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
	aim.spread_template_override = nil

	-- the salvo is fired by itself after a while (when is set when the aiming starts)
	aim.allowed_chain_actions = table.clone(aim.allowed_chain_actions)

	-- the primary button doesn't fire while loading, it makes the salvo a spiral. Reloading isn't possible
	-- while loading either: the game doesn't allow it while zooming, and there is no zoom here to do that.
	for i = #aim.allowed_chain_actions, 1, -1 do
		local chain = aim.allowed_chain_actions[i]

		if chain.input == "action_one" or chain.action == "weapon_reload" then
			table.remove(aim.allowed_chain_actions, i)
		end
	end

	aim.allowed_chain_actions[#aim.allowed_chain_actions + 1] = {
		action = "action_one",
		auto_chain = true,
		start_time = CONFIG.max_hold_time,
		sub_action = "zoomed_shot",
		ut_salvo_chain = true,
	}

	-- releasing the aiming button fires the loaded rockets (UT's bFireOnRelease)
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

-- Loading: when aiming started, per unit. The number of rockets of a salvo is how long the player
-- has been loading, when it is fired, and a salvo starts the loading again.
local load_start_t = setmetatable({}, {
	__mode = "k",
})

-- The rockets loaded so far while loading (to tell when another one is), per unit
local loading = {}

mod:hook_safe(ActionAim, "client_owner_start_action", function (self, new_action, t)
	if new_action.ut_rocket_aim then
		local ammo = self.ammo_extension and self.ammo_extension:current_ammo() or CONFIG.max_rockets

		-- the salvo is a line until the primary button is pressed (the chains are shared, so they are set every time)
		local salvo_chains = {}

		for _, chain in ipairs(new_action.allowed_chain_actions) do
			if chain.ut_salvo_chain then
				chain.sub_action = "zoomed_shot"
				salvo_chains[#salvo_chains + 1] = chain
			end
		end

		load_start_t[self.owner_unit] = t
		loading[self.owner_unit] = {
			-- a salvo is not bigger than the ammo
			capacity = math.min(CONFIG.max_rockets, ammo),
			first_person_unit = self.first_person_unit,
			loaded = 1,
			salvo_chains = salvo_chains,
			spiral = false,
			start_t = t,
		}
	end
end)

mod:hook_safe(ActionAim, "finish", function (self, reason)
	if self.current_action and self.current_action.ut_rocket_aim then
		loading[self.owner_unit] = nil

		-- leaving the aiming for another action (a reload, the salvo) is not the button being released: it has
		-- to be, before aiming again, or the aiming would start again at the end of the reload
		if reason ~= "hold_input_released" then
			needs_release[self.owner_unit] = true
		end
	end
end)

-- A reload that starts while the aiming button is down needs it released as well, whichever way the
-- aiming was left for it. (For other weapons this does nothing, the flag is only read by the aiming of this one.)
mod:hook_safe(GenericAmmoUserExtension, "start_reload", function (self)
	local unit = self.owner_unit
	local input_extension = unit and Unit.alive(unit) and ScriptUnit.has_extension(unit, "input_system")

	if input_extension and input_extension:get("action_two_hold") then
		needs_release[unit] = true
	end
end)

-- Another rocket loaded: the animation of firing while aiming, and a sound
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
			-- each press of the primary button switches the salvo between a line and a spiral (a press
			-- is the button going down, so holding it doesn't switch back and forth every frame, and a button that
			-- was already down when the aiming started doesn't count)
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

				if CONFIG.load_kick then
					first_person_extension:play_camera_recoil(CONFIG.load_kick, t)
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

-- The spiral salvo: the rockets start in a ring around the aim, all in the same direction
local function fire_spiral(self, action, count)
	local owner_unit = self.owner_unit
	local first_person_extension = ScriptUnit.extension(owner_unit, "first_person_system")
	local position, rotation = first_person_extension:get_projectile_start_position_rotation()
	local right = Quaternion.right(rotation)
	local up = Quaternion.up(rotation)
	local angle = ActionUtils.pitch_from_rotation(rotation)
	local target_vector = Vector3.normalize(Vector3.flat(Quaternion.forward(rotation)))
	local lookup_data = action.lookup_data

	for i = 1, count do
		local offset = Vector3(0, 0, 0)

		if count > 1 then
			local ring_angle = (i - 1) * 2 * math.pi / CONFIG.max_rockets

			offset = right * (math.sin(ring_angle) * CONFIG.spiral_ring_radius) + up * (math.cos(ring_angle) * CONFIG.spiral_ring_radius)
		end

		ActionUtils.spawn_player_projectile(owner_unit, position + offset, rotation, 0, angle, target_vector, action.speed, self.item_name, lookup_data.item_template_name, lookup_data.action_name, lookup_data.sub_action_name, self._is_critical_strike, self.power_level)

		if self.ammo_extension then
			self.ammo_extension:use_ammo(action.ammo_usage)
		end
	end
end

mod:hook_safe(ActionCrossbow, "client_owner_start_action", function (self, new_action, t)
	if not new_action.ut_rocket_salvo then
		return
	end

	local held = t - (load_start_t[self.owner_unit] or t)
	local loaded = math.clamp(1 + math.floor(held / CONFIG.load_interval), 1, CONFIG.max_rockets)

	self.num_projectiles = self.ammo_extension and math.min(loaded, self.ammo_extension:current_ammo()) or loaded
	load_start_t[self.owner_unit] = t
	needs_release[self.owner_unit] = true

	-- the crossbow's own code fires nothing, the rockets are fired here
	if new_action.ut_rocket_spiral then
		fire_spiral(self, new_action, self.num_projectiles)

		self.num_projectiles = 0
	end
end)

-- The flock of a spiral salvo, RocketProj.Timer. The rockets that start together are a flock: every
-- pull_interval seconds each is pulled back towards the direction it was fired in, and gets an acceleration
-- from the neighbor (attraction or repulsion by the distance, and a curl around it, the opposite way for
-- rockets with a different curl). The path of a rocket is re-based on its current position and velocity
-- every frame.
local flocks = {}
local latest_flock = setmetatable({}, {
	__mode = "k",
})

mod.init_callbacks = mod.init_callbacks or {}
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
			pull_t = 0,
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

-- Makes the trajectory of a rocket go on from the position with the velocity
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
	-- the locomotion moves it by the time since its last update
	locomotion_extension.spawn_time = locomotion_extension.t
end

local function update_flocks(dt)
	for i = #flocks, 1, -1 do
		local flock = flocks[i]
		local live = {}

		for _, member in ipairs(flock.members) do
			local locomotion_extension = Unit.alive(member.unit) and ScriptUnit.has_extension(member.unit, "projectile_locomotion_system")

			-- (a rocket that homes in is steered by that, it leaves the flock)
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
								local curl = Vector3.cross(other.velocity:unbox(), offset)
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

-- Lock-on. The game's true flight projectiles: a template (the settings, with an id that goes over the
-- network) and the movement towards the target, a method of the projectile's locomotion extension that is
-- named by the template.
local TRUE_FLIGHT_TEMPLATE = "ut_rocket"

local function register_true_flight_template()
	local template = TrueFlightTemplates[TRUE_FLIGHT_TEMPLATE] or {}

	template.broadphase_radius = 5
	template.dot_threshold = 1
	template.initial_target_node = "c_spine"
	template.target_node = "c_spine"
	template.legitimate_target_func = "legitimate_always"
	template.target_tracking_check_func = "ut_rocket_update_towards_target"
	-- when the target is gone the rocket flies straight on, it doesn't look for another one
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

-- Flies straight for seek_delay seconds after it was fired, then turns towards the target, at most
-- seek_turn_rate radians per second
ProjectileTrueFlightLocomotionExtension.ut_rocket_update_towards_target = function (self, position, t, dt)
	local direction = self.current_direction:unbox()
	local speed = self.speed * self.true_flight_template.speed_multiplier
	local target_unit = self.target_unit

	if self.on_target_time >= CONFIG.seek_delay and target_unit and Unit.alive(target_unit) then
		local to_target = spine_position(target_unit) - position
		local distance = Vector3.length(to_target)

		if distance > 0.01 then
			local wanted_direction = to_target * (1 / distance)
			local angle = math.acos(math.clamp(Vector3.dot(direction, wanted_direction), -1, 1))
			local max_turn = CONFIG.seek_turn_rate * dt
			local fraction = angle <= max_turn and 1 or max_turn / angle
			local rotation = Quaternion.lerp(Quaternion.look(direction), Quaternion.look(wanted_direction), fraction)

			direction = Quaternion.forward(rotation)
		end
	end

	return position + direction * speed * dt, Quaternion.look(direction)
end

-- The lock of the local player: the enemy the crosshair has been on, for how long, and if it is a lock yet
local locks = {}

local function wielding_rocket_launcher(unit)
	local inventory_extension = ScriptUnit.has_extension(unit, "inventory_system")
	local equipment = inventory_extension and inventory_extension:equipment()
	local wielded = equipment and equipment.wielded

	-- (the item data is the entry of the item master list, or has it as data)
	return is_rocket_launcher_enabled() and wielded and (wielded.template or wielded.data and wielded.data.template) == TEMPLATE_NAME
end

-- The enemy closest to the aim that is in front of it, close enough to it and not behind a wall. If there is none
-- on the aim, the enemy that is the target already (current_target) is kept while it is within the wider
-- lock_keep_dot of the aim.
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

	-- An enemy that is on the aim wins, whether it is the target or not: the target is only held on to (kept_unit)
	-- while there isn't one, so the lock moves to another enemy as soon as the aim is on it.
	return best_unit or kept_unit
end

-- The red outline of the game's target marking, what the true flight bow puts on the enemy it is aimed at
local function clear_lock_outline(state)
	local extension = state.outline_extension

	if extension then
		-- the enemy may be gone
		pcall(extension.remove_outline, extension, state.outline_id)

		state.outline_extension = nil
		state.outline_id = nil
	end
end

local function add_lock_outline(state)
	if not CONFIG.lock_outline or state.outline_extension or not ALIVE[state.target] then
		return
	end

	local extension = ScriptUnit.has_extension(state.target, "outline_system")

	if extension then
		state.outline_extension = extension
		state.outline_id = extension:add_outline(OutlineSettings.templates.target_enemy)
	end
end

local function reset_lock(state)
	clear_lock_outline(state)

	state.fired = nil
	state.locked = false
	state.lock_time = 0
	state.target = nil
	state.unlock_time = 0
end

local function update_lock_on(t)
	local player = Managers.player:local_player_safe()
	local unit = player and player.player_unit

	-- the lock of a unit that is gone, or of a weapon that isn't wielded
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
		state = {
			next_check_t = 0,
		}
		reset_lock(state)
		locks[unit] = state
	end

	-- only while loading (holding the secondary button): without it there is no lock, and letting go of it,
	-- or firing, ends it (a salvo has been given its target by then)
	if not loading[unit] then
		if state.target or state.locked then
			reset_lock(state)
		end

		return
	end

	if t < state.next_check_t then
		return
	end

	state.next_check_t = t + CONFIG.lock_check_interval

	-- a lock is used up by firing
	if state.fired then
		reset_lock(state)
	end

	if state.target and not HEALTH_ALIVE[state.target] then
		reset_lock(state)
	end

	local first_person_extension = ScriptUnit.has_extension(unit, "first_person_system")
	local candidate = first_person_extension and pick_lock_candidate(unit, first_person_extension, state.target)
	local interval = CONFIG.lock_check_interval

	if candidate then
		if candidate == state.target then
			state.unlock_time = 0
			state.lock_time = state.lock_time + interval

			if not state.locked and state.lock_time >= CONFIG.lock_required_time then
				state.locked = true

				add_lock_outline(state)

				if CONFIG.lock_sound_event and first_person_extension then
					first_person_extension:play_hud_sound_event(CONFIG.lock_sound_event)
				end
			end
		else
			reset_lock(state)
			state.target = candidate
		end
	elseif state.target then
		state.unlock_time = state.unlock_time + interval

		if state.unlock_time >= CONFIG.unlock_required_time then
			reset_lock(state)
		end
	end
end

-- A rocket fired while there is a lock is a true flight projectile with the locked enemy as its target
mod:hook(ActionUtils, "spawn_player_projectile", function (func, owner_unit, position, rotation, scale, angle, target_vector, speed, item_name, item_template_name, action_name, sub_action_name, ...)
	local state = locks[owner_unit]

	if state and state.locked and item_template_name == TEMPLATE_NAME and HEALTH_ALIVE[state.target] then
		local template = rawget(Weapons, item_template_name)
		local sub_actions = template and template.actions[action_name]
		local action = sub_actions and sub_actions[sub_action_name]

		if action and action.ut_rocket then
			state.fired = true

			-- a true flight projectile is given the direction it is fired in, not the flat part of it
			ActionUtils.spawn_true_flight_projectile(owner_unit, state.target, TrueFlightTemplates[TRUE_FLIGHT_TEMPLATE].lookup_id, position, rotation, angle, Vector3.normalize(Quaternion.forward(rotation)), speed, item_name, item_template_name, action_name, sub_action_name, 1, ...)

			return
		end
	end

	return func(owner_unit, position, rotation, scale, angle, target_vector, speed, item_name, item_template_name, action_name, sub_action_name, ...)
end)

-- The crosshair while loading: a pip for each rocket that can be loaded, the loaded ones lit. It is drawn
-- in the pass of the crosshair, after the rest of it.
local PIPS_TOKEN = {}

-- A texture is drawn from the top left corner of the crosshair's dot (which is 4 pixels and centered) to
-- the right and down, so a pip bigger than that is moved to have its center where it should be
local CROSSHAIR_DOT_SIZE = 4

-- Where a pip is, from the center of the crosshair: in a row, or in a triangle for a spiral
local function pip_position(index, spiral)
	local x, y

	if spiral then
		-- the order is the one of the hands of a clock: bottom left, top, bottom right
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

	-- locked on: the crosshair gets arrows around it
	if CONFIG.lock_indicator and lock and lock.locked then
		self:draw_arrows_style_crosshair(ui_renderer, CONFIG.lock_arrows_spread, CONFIG.lock_arrows_spread)
	end

	local state = player_unit and loading[player_unit]

	if not CONFIG.crosshair_pips or not state then
		return
	end

	-- the pips are kept in the crosshair, which outlives a reload of the mod: made again after one
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

-- The explosion hurts the player: the flak cannon's hook of do_aoe runs the callbacks of the actions
mod.aoe_callbacks = mod.aoe_callbacks or {}
mod.aoe_callbacks.rocket = function (self, aoe_data, position)
	if self._ut_rocket_exploded then
		return
	end

	self._ut_rocket_exploded = true

	registration.apply_explosion_self_damage(self._owner_unit, position, self.item_name, ExplosionTemplates.ut_rocket_explosion.explosion, CONFIG.rocket_self_damage)
end

-- Bodies thrown by the explosion. Runs on every peer, the physics of ragdolls is local. The units
-- near the explosion are collected when it goes off, the ones that die are thrown once their
-- ragdoll has started (before that the actors are driven by animation).
local blasts = {}

local function units_in_radius(world, position, radius)
	local physics_world = World.physics_world(world)
	local actors, num_actors = PhysicsWorld.immediate_overlap(physics_world, "shape", "sphere", "position", position, "size", radius, "collision_filter", "filter_explosion_overlap")
	local units = {}

	for i = 1, num_actors do
		local unit = Actor.unit(actors[i])
		local breed = unit and Unit.alive(unit) and AiUtils.unit_breed(unit)

		if breed and not breed.is_player then
			units[unit] = true
		end
	end

	return units
end

-- Returns true once the body was thrown
local function blast_ragdoll(unit, center, radius)
	local thrown = false

	for i = 0, Unit.num_actors(unit) - 1 do
		local actor = Unit.actor(unit, i)

		if actor and Actor.is_dynamic(actor) then
			local offset = Actor.position(actor) - center
			local distance = Vector3.length(offset)
			local direction = distance > 0.01 and offset * (1 / distance) or Vector3.up()
			local speed = CONFIG.ragdoll_speed * math.lerp(1, 0.5, math.clamp(distance / radius, 0, 1))

			Actor.set_velocity(actor, direction * speed + Vector3(0, 0, CONFIG.ragdoll_up))

			thrown = true
		end
	end

	return thrown
end

local function update_blasts()
	local t = Managers.time:time("game")

	for i = #blasts, 1, -1 do
		local blast = blasts[i]
		local center = blast.position:unbox()

		for unit in pairs(blast.units) do
			if not Unit.alive(unit) then
				blast.units[unit] = nil
			elseif not HEALTH_ALIVE[unit] and blast_ragdoll(unit, center, blast.radius) then
				blast.units[unit] = nil
			end
		end

		if t - blast.t > CONFIG.ragdoll_window or next(blast.units) == nil then
			table.remove(blasts, i)
		end
	end
end

-- The look of the explosion, on every peer: the explosion's callback is run for everyone who sees it
mod.explosion_callbacks = mod.explosion_callbacks or {}
mod.explosion_callbacks.ut_rocket_explosion = function (world, position)
	for _, effect in ipairs(CONFIG.explosion_effects) do
		effects.play(world, effect.name, position + Vector3(0, 0, effect.offset), effect.scale)
	end

	local radius = ExplosionTemplates.ut_rocket_explosion.explosion.radius

	blasts[#blasts + 1] = {
		position = Vector3Box(position),
		radius = radius,
		t = Managers.time:time("game"),
		units = units_in_radius(world, position, radius),
	}
end

-- Enabling and disabling. The files before this one have set these already, they are extended.
local previous_on_enabled = mod.on_enabled
local previous_on_disabled = mod.on_disabled
local previous_update = mod.update
local previous_on_unload = mod.on_unload

mod.on_enabled = function (...)
	if previous_on_enabled then
		previous_on_enabled(...)
	end

	if is_rocket_launcher_enabled() then
		apply_rocket_launcher()
	end
end

mod.on_disabled = function (...)
	if previous_on_disabled then
		previous_on_disabled(...)
	end

	restore_crossbow()
end

local previous_on_setting_changed = mod.on_setting_changed

mod.on_setting_changed = function (setting_id, ...)
	if previous_on_setting_changed then
		previous_on_setting_changed(setting_id, ...)
	end

	if setting_id == "rocket_launcher" or setting_id == "ut_weapons" then
		if is_rocket_launcher_enabled() then
			apply_rocket_launcher()
		else
			restore_crossbow()
		end
	end
end

mod.update = function (dt, ...)
	if previous_update then
		previous_update(dt, ...)
	end

	update_blasts()
	update_flocks(dt)
	update_lock_on(Managers.time:time("game"))
	update_loading(Managers.time:time("game"))
	effects.update(dt)
end

mod.on_unload = function (...)
	if previous_on_unload then
		previous_on_unload(...)
	end

	table.clear(blasts)
	table.clear(flocks)

	for _, locked_state in pairs(locks) do
		clear_lock_outline(locked_state)
	end

	table.clear(locks)
	table.clear(loading)
	effects.clear()
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
	effects.clear()
end
