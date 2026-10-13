local mod = get_mod("unreal_tournament")

-- The third person of a weapon skin (the Weapon Skins setting): every character on this machine that wields the weapon holds UT2004's
-- pickup mesh of it instead of the game's weapon, as this player sees them: the skin is a setting of each machine, and the game's own
-- units are what the others' machines show. The characters are the player's own (in a third person view), the other players and the
-- bots. Made by weapon_skin.lua for each weapon (mod.weapon_skin.new), with what is the weapon's own in its definition:
--   id: the weapon's setting (always = true if it has none), template: the game's template it is, unit_name: the mesh (tools/asset_conversion/psk2bsi.py, with the
--   DrawScale of the pickup in it), materials: { slot = material } to set on it, hand_node: where the game links the weapon to the
--   character, meters_per_unit: the meters of a UT unit of the mesh, scale: how much of it is held (UT's pickups are far bigger
--   than the weapon in the hand is), grip_*: the point of the mesh that is in the hand (right, forward, up, UT units), yaw, pitch,
--   roll: how the mesh is turned from pointing the way the character faces (degrees), muzzle_*: the end of its barrel, menu_yaw: how far to
--   turn it about the vertical in the item inspection so the barrel points sideways (-90 if its barrel runs along its forward),
--   follow_game_unit: the mesh moves with the game's unit of the weapon, which the game animates with the arms, from how it is turned after
--   follow_calibrate_seconds of being held (follow_game_unit = 2: no calibration, pitch, roll and yaw are from the unit's own axes, for a
--   weapon whose unit is still moving to its place when it would be calibrated: the Repeating Crossbow's)
--
-- The game's unit (the staff, the blunderbuss...) stays, hidden, and the mesh is linked to the same node of the character as it, turned
-- every frame to point the way the character faces, level (a staff is held upright, a rifle is carried pointing ahead: that is not
-- how the hand is turned). Which character wields what is looked at every frame, so that the game's own wielding, which makes a new
-- unit each time, needs no hook.
--
-- A weapon with skins (illusions) can hold a different mesh for one of them: looks = { [skin key] = the definition above, for that mesh }.
-- A character wielding the weapon with that skin holds that mesh.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")

-- Every weapon's third person
local instances = {}

local function new(def, looks)
	local CONFIG = {}

	for key, value in pairs(def) do
		CONFIG[key] = value
	end

	-- The definition for a look (a skin key), or the weapon's own when there is none.
	local function config_of(look)
		return look and looks and looks[look] or CONFIG
	end

	-- The look for the weapon a character wields.
	local function look_of(character)
		local skin_key = utils.wielded_skin(character)

		return skin_key and looks and looks[skin_key] and skin_key or nil
	end

	-- The characters that hold the mesh: [character unit] = { unit = the mesh, staff = the game's unit it stands in for, world, ... }
	local attached = {}

	local third_person = {}

	instances[#instances + 1] = third_person

	third_person.config_of = config_of

	-- How many meters a UT unit of the mesh is as it is held (the flashes are made as big as the mesh is)
	third_person.meters_per_unit = CONFIG.meters_per_unit * CONFIG.scale

	-- The mesh's pose, every frame: the point of it that is in the hand is the node of the hand, and it points the way the
	-- character faces, level, so the rotation in the frame of the hand is the one that makes it so in the world
	local function place(entry)
		local config = entry.config
		local facing = Vector3.flat(Quaternion.forward(Unit.world_rotation(entry.character, 0)))
		local wanted = Quaternion.look(Vector3.normalize(facing), Vector3.up())

		-- follow_game_unit: the mesh moves with the game's own unit of the weapon, which the game animates with the arms. The mesh starts
		-- out pointing the way the character faces (with pitch, roll and yaw), and once the character has stood holding the weapon for
		-- follow_calibrate_seconds, how the game's unit is turned from that is kept, and the mesh is turned from the unit by it from then
		-- on. Without it, or in a menu, where there is no unit, the mesh keeps pointing the way the character faces.
		if config.follow_game_unit and config.follow_game_unit ~= 0 and entry.staff and Unit.alive(entry.staff) then
			local staff_rotation = Unit.world_rotation(entry.staff, 0)
			local t = Managers.time:time("main")

			entry.attached_at = entry.attached_at or t

			if config.follow_game_unit == 2 then
				-- (the mesh is turned from the game's unit by pitch, roll and yaw alone, as they are the unit's own axes: no calibration)
				wanted = staff_rotation
			elseif not entry.follow_offset and t - entry.attached_at >= (config.follow_calibrate_seconds or 1) then
				entry.follow_offset = QuaternionBox(Quaternion.multiply(Quaternion.inverse(staff_rotation), wanted))
			end

			if entry.follow_offset then
				wanted = Quaternion.multiply(staff_rotation, entry.follow_offset:unbox())
			end
		end

		local rotation = Quaternion.multiply(Quaternion.inverse(Unit.world_rotation(entry.character, entry.hand_node)), wanted)

		rotation = Quaternion.multiply(rotation, Quaternion.from_euler_angles_xyz(config.pitch, config.roll, config.yaw))

		local grip = Vector3(config.grip_right, config.grip_forward, config.grip_up) * config.meters_per_unit * config.scale

		Unit.set_local_position(entry.unit, 0, -Quaternion.rotate(rotation, grip))
		Unit.set_local_rotation(entry.unit, 0, rotation)
		Unit.set_local_scale(entry.unit, 0, Vector3(config.scale, config.scale, config.scale))

		-- A material that the engine's fade near the camera does not reach (its shader has no option for it) has a "fade" variable, set from
		-- how far the camera is: nothing of it at fade_near meters, all of it from fade_far
		if config.fade_material and Unit.has_mesh(entry.unit, config.fade_mesh) then
			local camera_manager = Managers.state.camera
			local fade = 1

			if camera_manager then
				local distance = Vector3.length(camera_manager:camera_position("player_1") - Unit.world_position(entry.unit, 0))

				fade = math.clamp((distance - (config.fade_near or 0.3)) / ((config.fade_far or 0.8) - (config.fade_near or 0.3)), 0, 1)
			end

			Material.set_scalar(Mesh.material(Unit.mesh(entry.unit, config.fade_mesh), config.fade_material), "fade", fade)
		end
	end

	local function detach(character)
		local entry = attached[character]

		if not entry then
			return
		end

		attached[character] = nil

		if Unit.alive(entry.unit) then
			World.unlink_unit(entry.world, entry.unit)
			World.destroy_unit(entry.world, entry.unit)
		end

		-- (the weapon that is still wielded is shown as the game would: when the mesh goes because the setting is off. One that is
		-- put away, or the one of an earlier wield, is the game's to show or to have taken down)
		-- (the effects of the units are started again as the game does when it wields: its flow event)
		if Unit.alive(character) and utils.wielded_template_name(character) == CONFIG.template then
			for _, game_unit in ipairs(entry.units) do
				if Unit.alive(game_unit) then
					Unit.flow_event(game_unit, "lua_wield")
					Unit.set_unit_visibility(game_unit, third_person.shows_weapon(character))
				end
			end
		end
	end

	-- A hidden mesh with its materials set
	local function new_mesh(world, look)
		local config = config_of(look)
		local unit = World.spawn_unit(world, config.unit_name, Vector3(0, 0, 0))

		Unit.set_unit_visibility(unit, false)

		for slot, material in pairs(config.materials or {}) do
			Unit.set_material(unit, slot, material)
		end

		return unit
	end

	third_person.new_mesh = new_mesh

	local function attach(character, staff, units)
		local world = Managers.world:world("level_world")
		local look = look_of(character)
		local config = config_of(look)
		local hand_node = Unit.node(character, config.hand_node)
		local unit = new_mesh(world, look)

		-- (kept at once, so that the mesh is found and destroyed whatever happens next, see weapon_skin.lua)
		attached[character] = {
			character = character,
			config = config,
			look = look,
			hand_node = hand_node,
			staff = staff,
			units = units,
			unit = unit,
			world = world,
		}

		-- (the effects of the game's units, the flame of the Beam Staff, are put out as the game does when it unwields: the units are only
		-- hidden, and the effects of a unit are not hidden with it)
		for _, game_unit in ipairs(units) do
			Unit.flow_event(game_unit, "lua_unwield")
		end

		World.link_unit(world, unit, 0, character, hand_node)

		-- The outline of the character (an ally's, for one) is put on the units that are linked to it when it changes, so a unit that is linked
		-- after it was put on is outlined only when it is put on again: the game does this when a weapon is wielded.
		local outline_extension = ScriptUnit.has_extension(character, "outline_system")

		if outline_extension then
			outline_extension:reapply_outline()
		end
	end

	-- The game's unit of a character if the skin is to replace it: the weapon is what it wields and the setting is on
	local function staff_to_replace(character)
		if not (CONFIG.always or utils.is_weapon_skin_enabled(CONFIG.id)) or utils.wielded_template_name(character) ~= CONFIG.template then
			return nil
		end

		local equipment = ScriptUnit.extension(character, "inventory_system"):equipment()
		local staff = equipment.right_hand_wielded_unit_3p or equipment.left_hand_wielded_unit_3p

		if not staff or not Unit.alive(staff) then
			return nil
		end

		-- (and the units of both hands: the Beam Staff's left hand has the flame)
		local units = {}

		-- (a list with a missing hand in it is not walked by ipairs: the Repeating Crossbow is in the left hand only)
		for _, key in ipairs({"right_hand_wielded_unit_3p", "left_hand_wielded_unit_3p"}) do
			local game_unit = equipment[key]

			if game_unit and Unit.alive(game_unit) then
				units[#units + 1] = game_unit
			end
		end

		return staff, units
	end

	-- If the character is shown holding its weapon: the player's own character is not while the view is the first person one
	-- (the game hides the weapon's unit then)
	function third_person.shows_weapon(character)
		if utils.is_local_player_unit(character) then
			local first_person_extension = ScriptUnit.has_extension(character, "first_person_system")

			return first_person_extension ~= nil and not first_person_extension:first_person_mode_active()
		end

		return true
	end

	-- Every frame
	function third_person.update()
		local players = Managers.player and Managers.player:human_and_bot_players()

		if not players then
			return
		end

		local seen = {}

		for _, player in pairs(players) do
			local character = player.player_unit

			if character and Unit.alive(character) and ScriptUnit.has_extension(character, "inventory_system") then
				local staff, units = staff_to_replace(character)
				local entry = attached[character]

				if entry and (entry.staff ~= staff or entry.look ~= look_of(character)) then
					detach(character)

					entry = nil
				end

				if staff then
					if not entry then
						attach(character, staff, units)

						entry = attached[character]
					end

					seen[character] = true
					place(entry)
					Unit.set_unit_visibility(entry.unit, third_person.shows_weapon(character))
					third_person.hide_staffs()
				end
			end
		end

		for character in pairs(attached) do
			if not seen[character] then
				detach(character)
			end
		end
	end

	-- The game's units are hidden again before the frame is drawn: the game shows them at times of its own, after the update
	function third_person.hide_staffs()
		for _, entry in pairs(attached) do
			for _, game_unit in ipairs(entry.units) do
				if Unit.alive(game_unit) then
					Unit.set_unit_visibility(game_unit, false)
				end
			end
		end
	end

	-- The effects of the game's units that are not shown are put out (the game starts them again each time it shows the character's weapons: it
	-- sends the units the flow event of wielding, which lights the flame of the Beam Staff's left hand)
	function third_person.put_out_flames(character)
		local entry = attached[character]

		if not entry then
			return
		end

		for _, game_unit in ipairs(entry.units) do
			if Unit.alive(game_unit) then
				Unit.flow_event(game_unit, "lua_unwield")
			end
		end
	end

	-- Where the barrel ends, for the flashes of a shot (nothing if the character holds the game's weapon)
	function third_person.muzzle_position(character)
		local entry = attached[character]

		if not entry or not Unit.alive(entry.unit) then
			return nil
		end

		local config = entry.config
		local offset = Vector3(config.muzzle_right, config.muzzle_forward, config.muzzle_up) * config.meters_per_unit * config.scale

		return Unit.world_position(entry.unit, 0) + Quaternion.rotate(Unit.world_rotation(entry.unit, 0), offset)
	end

	-- How many meters one UT unit of the mesh is as a character holds it (flashes are sized to match the mesh).
	function third_person.meters_per_unit_of(character)
		local config = attached[character] and attached[character].config or CONFIG

		return config.meters_per_unit * config.scale
	end

	-- All of them are given back (the setting is off, the mod is, the level is gone)
	function third_person.clear()
		for character in pairs(attached) do
			detach(character)
		end
	end

	-- Heroes in menus that hold the mesh. They aren't players, so update doesn't see them.
	-- [character unit] = { character, hand_node, unit, world }
	local in_menu = {}

	-- Makes the hero hold the mesh, placed as in the world, and hides the previewer's own units
	function third_person.hold_in_menu(character, world, game_units, visible, look)
		local entry = in_menu[character]

		look = look and looks and looks[look] and look or nil

		if entry and (entry.world ~= world or entry.look ~= look) then
			third_person.release_from_menu(character)

			entry = nil
		end

		if not entry then
			local config = config_of(look)
			local hand_node = Unit.node(character, config.hand_node)
			local unit = new_mesh(world, look)

			World.link_unit(world, unit, 0, character, hand_node)

			entry = {
				character = character,
				config = config,
				look = look,
				hand_node = hand_node,
				unit = unit,
				world = world,
			}
			in_menu[character] = entry
		end

		-- A mesh that is turned from the game's unit by its axes (follow_game_unit 2) is placed by the previewer's unit, as in the world
		if entry.config.follow_game_unit == 2 then
			entry.staff = nil

			for _, game_unit in ipairs(game_units) do
				if Unit.alive(game_unit) then
					entry.staff = game_unit

					break
				end
			end
		end

		place(entry)
		Unit.set_unit_visibility(entry.unit, visible)

		-- Hidden units still show their effects (the Beam Staff's flame), so they get the unwield event
		for _, game_unit in ipairs(game_units) do
			if Unit.alive(game_unit) then
				Unit.set_unit_visibility(game_unit, false)
				Unit.flow_event(game_unit, "lua_unwield")
			end
		end
	end

	-- Call before the previewer destroys its character: the world must still exist
	function third_person.release_from_menu(character)
		local entry = in_menu[character]

		if not entry then
			return
		end

		in_menu[character] = nil

		if Unit.alive(entry.unit) then
			World.unlink_unit(entry.world, entry.unit)
			World.destroy_unit(entry.world, entry.unit)
		end
	end

	-- Development: what every character holds, told in the chat: the scale of each unit of its weapons (the game's, in the first person and
	-- the third), how far it is from the hand nodes, and the scale of the nodes, to see which one is off when a weapon is seen floating
	function third_person.report()
		local players = Managers.player and Managers.player:human_and_bot_players()

		if not players then
			return
		end

		local function scale_of(unit, node)
			local pose = Unit.world_pose(unit, node or 0)

			return Vector3.length(Matrix4x4.x(pose))
		end

		for _, player in pairs(players) do
			local character = player.player_unit

			if character and Unit.alive(character) and ScriptUnit.has_extension(character, "inventory_system") then
				local equipment = ScriptUnit.extension(character, "inventory_system"):equipment()
				local left_hand = Unit.has_node(character, "j_leftweaponattach") and Unit.node(character, "j_leftweaponattach")
				local right_hand = Unit.has_node(character, "j_rightweaponattach") and Unit.node(character, "j_rightweaponattach")

				mod:echo("%s (%s): wields %s, character scale %.2f, left hand %.2f, right hand %.2f%s", tostring(player:name()), player.bot_player and "bot" or "player", tostring(utils.wielded_template_name(character)), scale_of(character), left_hand and scale_of(character, left_hand) or -1, right_hand and scale_of(character, right_hand) or -1, attached[character] and ", holds the skin's mesh" or "")

				for _, field in ipairs({"right_hand_wielded_unit_3p", "left_hand_wielded_unit_3p", "right_hand_wielded_unit", "left_hand_wielded_unit"}) do
					local unit = equipment[field]

					if unit and Unit.alive(unit) then
						local position = Unit.world_position(unit, 0)
						local to_left = left_hand and Vector3.length(position - Unit.world_position(character, left_hand)) or -1
						local to_right = right_hand and Vector3.length(position - Unit.world_position(character, right_hand)) or -1

						mod:echo("  %s: scale %.2f, %.2f m from the left hand, %.2f m from the right", field, scale_of(unit), to_left, to_right)
					end
				end
			end
		end
	end

	-- Development: sets a number of the definition (how the mesh sits in the hand) while playing
	function third_person.set(key, value)
		-- (follow_recalibrate: the turn of the mesh from the game's unit is taken again, with the characters standing as they should)
		if key == "follow_recalibrate" then
			for _, entry in pairs(attached) do
				entry.follow_offset = nil
				entry.attached_at = nil
			end

			return
		end

		CONFIG[key] = value
		third_person.meters_per_unit = CONFIG.meters_per_unit * CONFIG.scale
	end

	return third_person
end

-- The game shows the character's weapons again (the view is changed to the third person, a ladder is let go of, ...)
-- (the player's own character, and the other characters, which have an inventory of their own)
for _, inventory_class in ipairs({ SimpleInventoryExtension, SimpleHuskInventoryExtension }) do
	mod:hook_safe(inventory_class, "show_third_person_inventory", function (self, show)
		if show then
			for _, third_person in ipairs(instances) do
				third_person.put_out_flames(self._unit)
			end
		end
	end)
end

return {
	new = new,
}
