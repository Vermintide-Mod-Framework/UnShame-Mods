local mod = get_mod("unreal_tournament")

-- The third person of a weapon skin. Every character on this machine that wields the weapon holds UT2004's pickup mesh of it
-- instead of the game's weapon. That is how this player sees them. Players without the mod see the game's own units. The characters
-- are the player's own (in a third person view), the other players and the bots. weapon_skin.lua makes one of these for each weapon
-- (mod.weapon_skin.new), from the weapon's definition:
--   id: the weapon's id. template: the game's template of the weapon.
--   unit_name: the mesh (made by tools/asset_conversion/psk2bsi.py, with the pickup's DrawScale in it).
--   materials: { slot = material } to set on the mesh.
--   hand_node: where the game links the weapon to the character.
--   meters_per_unit: the meters per UT unit of the mesh.
--   scale: how much of the mesh is held. UT's pickups are far bigger than the weapon in the hand.
--   grip_*: the point of the mesh that is in the hand (right, forward, up, in UT units).
--   yaw, pitch, roll: how the mesh is turned from pointing the way the character faces, in degrees.
--   muzzle_*: the end of the barrel.
--   menu_scale: how much of the usual size the mesh is in the item inspection (1 if it is not given).
--   menu_yaw: how far to turn the mesh about the vertical in the item inspection, so that the barrel points sideways (-90 if the
--       barrel runs along the mesh's forward).
--   follow_game_unit: the mesh moves with the game's unit of the weapon, which the game animates with the arms. The mesh is turned
--       from the game's unit by the way the unit is turned after follow_calibrate_seconds of being held. With follow_game_unit = 2
--       there is no calibration: pitch, roll and yaw are relative to the unit's own axes. That is for a weapon whose unit is still
--       moving into place when it would be calibrated, such as the Repeating Crossbow. With follow_game_unit = 3 the mesh is turned
--       as the hand's node is, as a unit the game links to that node is. Pitch, roll and yaw are relative to the node's axes. That is
--       for a hero who holds the weapon in the pose of another weapon, whose unit is not in that hand.
--   fade_mesh, fade_material: a material with a "fade" variable, for a material that the engine's near-camera fade doesn't reach.
--
-- The game's unit (the staff, the blunderbuss and so on) stays, hidden. The mesh is linked to the same node of the character, and it
-- is turned every frame to point the way the character faces, level. A staff is held upright and a rifle is carried pointing ahead,
-- which is not how the hand is turned. Every frame the code looks at which character wields what, so the game's own wielding, which
-- makes a new unit each time, needs no hook.
--
-- A weapon with skins (illusions) can hold a different mesh for one of them: looks = { [skin key] = a definition like the one above,
-- for that mesh }. A character wielding the weapon with that skin holds that mesh.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")

-- The third person of every weapon
local instances = {}

local function new(def, looks)
	local CONFIG = {}

	for key, value in pairs(def) do
		CONFIG[key] = value
	end

	-- Returns the definition for a look (a skin key), or the weapon's own definition if there is no look.
	local function config_of(look)
		return look and looks and looks[look] or CONFIG
	end

	-- Returns the look for the weapon a character wields, or nil for the weapon's own look.
	local function look_of(character)
		local skin_key = utils.wielded_skin(character)

		return skin_key and looks and looks[skin_key] and skin_key or nil
	end

	-- The characters that hold the mesh, as [character unit] = { unit = the mesh, staff = the game's unit it replaces, world, ... }
	local attached = {}

	local third_person = {}

	instances[#instances + 1] = third_person

	third_person.config_of = config_of

	-- How many meters a UT unit of the mesh is as it is held. Flashes use it to be as big as the mesh.
	third_person.meters_per_unit = CONFIG.meters_per_unit * CONFIG.scale

	-- Sets the mesh's pose. It runs every frame. The point of the mesh that is in the hand sits on the hand's node, and the mesh points
	-- the way the character faces, level. So the rotation in the hand's frame is the one that gives that result in the world.
	local function place(entry)
		local config = entry.config
		local facing = Vector3.flat(Quaternion.forward(Unit.world_rotation(entry.character, 0)))
		local wanted = Quaternion.look(Vector3.normalize(facing), Vector3.up())

		-- With follow_game_unit the mesh moves with the game's own unit of the weapon, which the game animates with the arms. At first
		-- the mesh points the way the character faces, with the pitch, roll and yaw. Once the character has held the weapon for
		-- follow_calibrate_seconds, the way the game's unit is turned relative to that is stored, and from then on the mesh is turned
		-- from the unit by that amount. Without follow_game_unit, or in a menu where there is no unit, the mesh keeps pointing the way
		-- the character faces.
		if config.follow_game_unit and config.follow_game_unit ~= 0 and entry.staff and Unit.alive(entry.staff) then
			local staff_rotation = Unit.world_rotation(entry.staff, 0)
			local t = Managers.time:time("main")

			entry.attached_at = entry.attached_at or t

			if config.follow_game_unit == 2 then
				-- The mesh is turned from the game's unit by the pitch, roll and yaw alone, which are in the unit's own axes. There is
				-- no calibration.
				wanted = staff_rotation
			elseif not entry.follow_offset and t - entry.attached_at >= (config.follow_calibrate_seconds or 1) then
				entry.follow_offset = QuaternionBox(Quaternion.multiply(Quaternion.inverse(staff_rotation), wanted))
			end

			if entry.follow_offset then
				wanted = Quaternion.multiply(staff_rotation, entry.follow_offset:unbox())
			end
		end

		local rotation = Quaternion.identity()

		if config.follow_game_unit ~= 3 then
			rotation = Quaternion.multiply(Quaternion.inverse(Unit.world_rotation(entry.character, entry.hand_node)), wanted)
		end

		rotation = Quaternion.multiply(rotation, Quaternion.from_euler_angles_xyz(config.pitch, config.roll, config.yaw))

		local grip = Vector3(config.grip_right, config.grip_forward, config.grip_up) * config.meters_per_unit * config.scale

		Unit.set_local_position(entry.unit, 0, -Quaternion.rotate(rotation, grip))
		Unit.set_local_rotation(entry.unit, 0, rotation)
		Unit.set_local_scale(entry.unit, 0, Vector3(config.scale, config.scale, config.scale))

		-- The engine's fade near the camera does not reach some materials, because their shader has no option for it. Such a material
		-- has a "fade" variable, and this sets it the way the engine fades a character (read from the engine's fade update). The
		-- material is invisible up to 0.5 m from the camera, measured sideways. It is fully visible from 0.7 m, and also whenever the
		-- camera is a meter or more above or below the character.
		if config.fade_material and Unit.has_mesh(entry.unit, config.fade_mesh) then
			local camera_manager = Managers.state.camera
			local fade = 1

			if camera_manager then
				local character = entry.character
				local anchor = Unit.has_node(character, "j_hips") and Unit.world_position(character, Unit.node(character, "j_hips")) or Unit.world_position(character, 0)
				local offset = camera_manager:camera_position("player_1") - anchor
				local sideways = math.sqrt(Vector3.x(offset) ^ 2 + Vector3.y(offset) ^ 2)

				if math.abs(Vector3.z(offset)) < 1 and sideways < 0.7 then
					fade = math.clamp((sideways - 0.5) * 5, 0, 1)
				end
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

		-- If the character still wields the weapon, its game units are shown again and their effects are started, with the same flow
		-- event the game sends when it wields. A weapon that was put away, or one from an earlier wield, is left to the game.
		if Unit.alive(character) and utils.wielded_template_name(character) == CONFIG.template then
			for _, game_unit in ipairs(entry.units) do
				if Unit.alive(game_unit) then
					Unit.flow_event(game_unit, "lua_wield")
					Unit.set_unit_visibility(game_unit, third_person.shows_weapon(character))
				end
			end
		end
	end

	-- Makes a mesh, hidden, with its materials set.
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

		-- The entry is stored at once, so the mesh can always be found and destroyed, whatever happens next (see weapon_skin.lua).
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

		-- The game's units are only hidden, and a hidden unit still shows its effects, such as the Beam Staff's flame. So this puts the
		-- effects out with the same flow event the game sends when it unwields.
		for _, game_unit in ipairs(units) do
			Unit.flow_event(game_unit, "lua_unwield")
		end

		World.link_unit(world, unit, 0, character, hand_node)

		-- The game puts a character's outline (an ally's, for example) on the units linked to the character at the moment the outline
		-- changes. A unit linked after that is not outlined until the outline is put on again, which the game does when a weapon is
		-- wielded. So the outline is put on again here.
		local outline_extension = ScriptUnit.has_extension(character, "outline_system")

		if outline_extension then
			outline_extension:reapply_outline()
		end
	end

	-- Returns the game's weapon unit of a character if the skin replaces it, which is when the character wields this weapon. Also
	-- returns the units of both hands.
	local function staff_to_replace(character)
		if utils.wielded_template_name(character) ~= CONFIG.template then
			return nil
		end

		local equipment = ScriptUnit.extension(character, "inventory_system"):equipment()
		local staff = equipment.right_hand_wielded_unit_3p or equipment.left_hand_wielded_unit_3p

		if not staff or not Unit.alive(staff) then
			return nil
		end

		-- Both hands' units are needed, because the Beam Staff's left hand has the flame
		local units = {}

		-- The keys are walked by name, because ipairs stops at a missing hand. The Repeating Crossbow is in the left hand only.
		for _, key in ipairs({"right_hand_wielded_unit_3p", "left_hand_wielded_unit_3p"}) do
			local game_unit = equipment[key]

			if game_unit and Unit.alive(game_unit) then
				units[#units + 1] = game_unit
			end
		end

		return staff, units
	end

	-- Returns whether the character is shown holding its weapon. The player's own character is not, while the view is first person,
	-- because the game hides the weapon's unit then.
	function third_person.shows_weapon(character)
		if utils.is_local_player_unit(character) then
			local first_person_extension = ScriptUnit.has_extension(character, "first_person_system")

			return first_person_extension ~= nil and not first_person_extension:first_person_mode_active()
		end

		return true
	end

	-- Runs every frame. Attaches the mesh to characters that need it, places it, and removes it from the others.
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

	-- Hides the game's units again before the frame is drawn, because the game shows them at times of its own, after the update.
	function third_person.hide_staffs()
		for _, entry in pairs(attached) do
			for _, game_unit in ipairs(entry.units) do
				if Unit.alive(game_unit) then
					Unit.set_unit_visibility(game_unit, false)
				end
			end
		end
	end

	-- Puts out the effects of the game's units that are not shown. Each time the game shows the character's weapons it sends the units
	-- the wield flow event, which lights the flame of the Beam Staff's left hand again.
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

	-- Returns where the barrel ends, for the flash of a shot. Returns nil if the character holds the game's weapon.
	function third_person.muzzle_position(character)
		local entry = attached[character]

		if not entry or not Unit.alive(entry.unit) then
			return nil
		end

		local config = entry.config
		local offset = Vector3(config.muzzle_right, config.muzzle_forward, config.muzzle_up) * config.meters_per_unit * config.scale

		return Unit.world_position(entry.unit, 0) + Quaternion.rotate(Unit.world_rotation(entry.unit, 0), offset)
	end

	-- Returns how the mesh in the character's hand is turned (its forward is the way the barrel points), or nil as muzzle_position does
	function third_person.muzzle_rotation(character)
		local entry = attached[character]

		if not entry or not Unit.alive(entry.unit) then
			return nil
		end

		return Unit.world_rotation(entry.unit, 0)
	end

	-- Returns how many meters one UT unit of the mesh is as a character holds it. Flashes are sized to match the mesh.
	function third_person.meters_per_unit_of(character)
		local config = attached[character] and attached[character].config or CONFIG

		return config.meters_per_unit * config.scale
	end

	-- Removes the mesh from every character. This is used when the mod is switched off or the level ends.
	function third_person.clear()
		for character in pairs(attached) do
			detach(character)
		end
	end

	-- The heroes in menus that hold the mesh, as [character unit] = { character, hand_node, unit, world }. They aren't players, so
	-- update doesn't see them.
	local in_menu = {}

	-- Makes the hero hold the mesh, placed as in the world, and hides the previewer's own units.
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

		-- With follow_game_unit 2, the mesh is placed relative to the previewer's unit, as it is relative to the game's unit in the world.
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

		-- Hidden units still show their effects, such as the Beam Staff's flame, so they get the unwield event.
		for _, game_unit in ipairs(game_units) do
			if Unit.alive(game_unit) then
				Unit.set_unit_visibility(game_unit, false)
				Unit.flow_event(game_unit, "lua_unwield")
			end
		end
	end

	-- Removes the mesh from a hero in a menu. Call this before the previewer destroys its character, while the world still exists.
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

	-- Development command. Prints in the chat what every character holds: the scale of each of its weapon units (the game's, in first
	-- and third person), how far each is from the hand nodes, and the scale of the nodes. This shows which one is off when a weapon
	-- floats.
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

						-- The unit's bounding box in the unit's own axes: how big it is along each axis and where its middle is, which
						-- shows the way its barrel runs.
						local box_pose, box_radius = Unit.box(unit)
						local local_pose = Matrix4x4.multiply(box_pose, Matrix4x4.inverse(Unit.world_pose(unit, 0)))
						local x, y, z = Matrix4x4.x(local_pose), Matrix4x4.y(local_pose), Matrix4x4.z(local_pose)
						local middle = Matrix4x4.translation(local_pose)

						mod:echo("    box: half sizes %.3f %.3f %.3f, along the unit's (%.2f %.2f %.2f) (%.2f %.2f %.2f) (%.2f %.2f %.2f), middle (%.3f %.3f %.3f)", Vector3.x(box_radius), Vector3.y(box_radius), Vector3.z(box_radius), Vector3.x(x), Vector3.y(x), Vector3.z(x), Vector3.x(y), Vector3.y(y), Vector3.z(y), Vector3.x(z), Vector3.y(z), Vector3.z(z), Vector3.x(middle), Vector3.y(middle), Vector3.z(middle))
					end
				end
			end
		end
	end

	-- Development command. Sets a number of the definition, which is how the mesh sits in the hand, while playing.
	function third_person.set(key, value)
		-- follow_recalibrate is not a number: it makes the mesh's turn from the game's unit be measured again. Use it with the
		-- characters standing as they should.
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

-- The game shows the character's weapons again at some moments, for example when the view changes to third person or a ladder is let
-- go. Their effects start again then, so they are put out. This covers the player's own character and the other characters, which
-- have an inventory class of their own.
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
