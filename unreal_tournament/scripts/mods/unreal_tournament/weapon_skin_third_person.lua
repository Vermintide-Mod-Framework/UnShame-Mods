local mod = get_mod("unreal_tournament")

-- The third person of a weapon skin (the Weapon Skins setting): every character on this machine that wields the weapon holds UT2004's
-- pickup mesh of it instead of the game's weapon, as this player sees them: the skin is a setting of each machine, and the game's own
-- units are what the others' machines show. The characters are the player's own (in a third person view), the other players and the
-- bots. Made by weapon_skin.lua for each weapon (mod.weapon_skin.new), with what is the weapon's own in its definition:
--   id: the weapon's setting, template: the game's template it is, unit_name: the mesh (tools/asset_conversion/psk2bsi.py, with the
--   DrawScale of the pickup in it), materials: { slot = material } to set on it, hand_node: where the game links the weapon to the
--   character, meters_per_unit: the meters of a UT unit of the mesh, scale: how much of it is held (UT's pickups are far bigger
--   than the weapon in the hand is), grip_*: the point of the mesh that is in the hand (right, forward, up, UT units), yaw, pitch,
--   roll: how the mesh is turned from pointing the way the character faces (degrees), muzzle_*: the end of its barrel
--
-- The game's unit (the staff, the blunderbuss...) stays, hidden, and the mesh is linked to the same node of the character as it, turned
-- every frame to point the way the character faces, level (a staff is held upright, a rifle is carried pointing ahead: that is not
-- how the hand is turned). Which character wields what is looked at every frame, so that the game's own wielding, which makes a new
-- unit each time, needs no hook.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")

local function new(def)
	local CONFIG = {}

	for key, value in pairs(def) do
		CONFIG[key] = value
	end

	-- The characters that hold the mesh: [character unit] = { unit = the mesh, staff = the game's unit it stands in for, world, ... }
	local attached = {}

	local third_person = {}

	-- How many meters a UT unit of the mesh is as it is held (the flashes are made as big as the mesh is)
	third_person.meters_per_unit = CONFIG.meters_per_unit * CONFIG.scale

	-- The mesh's pose, every frame: the point of it that is in the hand is the node of the hand, and it points the way the
	-- character faces, level, so the rotation in the frame of the hand is the one that makes it so in the world
	local function place(entry)
		local facing = Vector3.flat(Quaternion.forward(Unit.world_rotation(entry.character, 0)))
		local wanted = Quaternion.look(Vector3.normalize(facing), Vector3.up())
		local rotation = Quaternion.multiply(Quaternion.inverse(Unit.world_rotation(entry.character, entry.hand_node)), wanted)

		rotation = Quaternion.multiply(rotation, Quaternion.from_euler_angles_xyz(math.rad(CONFIG.pitch), math.rad(CONFIG.roll), math.rad(CONFIG.yaw)))

		local grip = Vector3(CONFIG.grip_right, CONFIG.grip_forward, CONFIG.grip_up) * third_person.meters_per_unit

		Unit.set_local_position(entry.unit, 0, -Quaternion.rotate(rotation, grip))
		Unit.set_local_rotation(entry.unit, 0, rotation)
		Unit.set_local_scale(entry.unit, 0, Vector3(CONFIG.scale, CONFIG.scale, CONFIG.scale))
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
		if Unit.alive(entry.staff) and Unit.alive(character) and utils.wielded_template_name(character) == CONFIG.template then
			Unit.set_unit_visibility(entry.staff, third_person.shows_weapon(character))
		end
	end

	local function attach(character, staff)
		local world = Managers.world:world("level_world")
		local unit = World.spawn_unit(world, CONFIG.unit_name, Vector3(0, 0, 0))
		local hand_node = Unit.node(character, CONFIG.hand_node)

		Unit.set_unit_visibility(unit, false)
		World.link_unit(world, unit, 0, character, hand_node)

		for slot, material in pairs(CONFIG.materials or {}) do
			Unit.set_material(unit, slot, material)
		end

		attached[character] = {
			character = character,
			hand_node = hand_node,
			staff = staff,
			unit = unit,
			world = world,
		}
	end

	-- The game's unit of a character if the skin is to replace it: the weapon is what it wields and the setting is on
	local function staff_to_replace(character)
		if not utils.is_weapon_skin_enabled(CONFIG.id) or utils.wielded_template_name(character) ~= CONFIG.template then
			return nil
		end

		local equipment = ScriptUnit.extension(character, "inventory_system"):equipment()
		local staff = equipment.right_hand_wielded_unit_3p or equipment.left_hand_wielded_unit_3p

		return staff and Unit.alive(staff) and staff or nil
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
				local staff = staff_to_replace(character)
				local entry = attached[character]

				if entry and entry.staff ~= staff then
					detach(character)

					entry = nil
				end

				if staff then
					if not entry then
						attach(character, staff)

						entry = attached[character]
					end

					seen[character] = true
					place(entry)
					Unit.set_unit_visibility(entry.unit, third_person.shows_weapon(character))
					Unit.set_unit_visibility(staff, false)
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
			if Unit.alive(entry.staff) then
				Unit.set_unit_visibility(entry.staff, false)
			end
		end
	end

	-- Where the barrel ends, for the flashes of a shot (nothing if the character holds the game's weapon)
	function third_person.muzzle_position(character)
		local entry = attached[character]

		if not entry or not Unit.alive(entry.unit) then
			return nil
		end

		local offset = Vector3(CONFIG.muzzle_right, CONFIG.muzzle_forward, CONFIG.muzzle_up) * third_person.meters_per_unit

		return Unit.world_position(entry.unit, 0) + Quaternion.rotate(Unit.world_rotation(entry.unit, 0), offset)
	end

	-- All of them are given back (the setting is off, the mod is, the level is gone)
	function third_person.clear()
		for character in pairs(attached) do
			detach(character)
		end
	end

	-- Development: sets a number of the definition (how the mesh sits in the hand) while playing
	function third_person.set(key, value)
		CONFIG[key] = value
		third_person.meters_per_unit = CONFIG.meters_per_unit * CONFIG.scale
	end

	return third_person
end

return {
	new = new,
}
