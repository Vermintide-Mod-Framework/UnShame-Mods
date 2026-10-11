local mod = get_mod("unreal_tournament")

-- Shock Rifle skin, third person (the Weapon Skins setting): every character on this machine that wields the Shock Rifle holds
-- UT2004's pickup mesh (NewWeaponPickups.ShockPickupSM, DrawScale 0.55) instead of the Beam Staff, as this player sees them: the
-- skin is a setting of each machine, and the game's own units are what the others' machines show. The characters are the
-- player's own (in a third person view), the other players and the bots.
--
-- The staff's unit is the game's own, and stays: it is hidden, and the mesh is linked to the same node of the character as it
-- (the right hand weapon attachment node, AttachmentNodeLinking.spear_staff) and turned to point the way the character faces.
-- Which character wields what is looked at every frame, so that the game's own wielding, which makes a new staff unit each
-- time, needs no hook.
--
-- The mesh was converted with the DrawScale in it (tools/asset_conversion/psk2bsi.py, 0.011 meters a UT unit). How it sits in the
-- hand is in CONFIG, and /shockskin 3p tunes it while playing.

local utils = mod:dofile("scripts/mods/unreal_tournament/utils")

local TEMPLATE_NAME = "staff_blast_beam_template_1"
local SETTING_ID = "shock_rifle"

local CONFIG = {
	unit_name = "units/ut/shock_pickup",
	chamber_material = "units/ut/shock_rifle_power_00",
	hand_node = "j_rightweaponattach",
	meters_per_unit = 0.011,
	-- UT2004's pickup models are far bigger than the weapon in the hand is (they are made to be seen on the floor): this much of it
	scale = 0.5,
	-- The point of the mesh that is in the hand, in UT units from its origin (right, forward, up), and how the mesh is turned
	-- from pointing the way the character faces, degrees (yaw, pitch, roll)
	grip_right = 0,
	grip_forward = -12,
	grip_up = -8,
	yaw = 0,
	pitch = 0,
	roll = 0,
	-- The muzzle of the mesh, in the same units (the end of the barrel)
	muzzle_right = 0,
	muzzle_forward = 51.7,
	muzzle_up = 10,
}

-- The characters that hold the mesh: [character unit] = { unit = the mesh, staff = the staff's unit it stands in for, world }
local attached = {}

local module = {}

-- The mesh's pose, every frame: the point of it that is in the hand is the node of the hand, and it points the way the character
-- faces, level (a staff is held upright, a rifle is carried pointing ahead: that is not how the hand is turned), so the
-- rotation in the frame of the hand is the one that makes it so in the world
local function place(entry)
	local facing = Vector3.flat(Quaternion.forward(Unit.world_rotation(entry.character, 0)))
	local wanted = Quaternion.look(Vector3.normalize(facing), Vector3.up())
	local rotation = Quaternion.multiply(Quaternion.inverse(Unit.world_rotation(entry.character, entry.hand_node)), wanted)

	rotation = Quaternion.multiply(rotation, Quaternion.from_euler_angles_xyz(math.rad(CONFIG.pitch), math.rad(CONFIG.roll), math.rad(CONFIG.yaw)))

	local grip = Vector3(CONFIG.grip_right, CONFIG.grip_forward, CONFIG.grip_up) * module.meters_per_unit

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

	-- (the staff that is still wielded is shown as the game would: when the mesh goes because the setting is off. A staff that is put
	-- away, or the one of an earlier wield, is the game's to show or to have taken down)
	if Unit.alive(entry.staff) and Unit.alive(character) and utils.wielded_template_name(character) == TEMPLATE_NAME then
		Unit.set_unit_visibility(entry.staff, module.shows_weapon(character))
	end
end

local function attach(character, staff)
	local world = Managers.world:world("level_world")
	local unit = World.spawn_unit(world, CONFIG.unit_name, Vector3(0, 0, 0))

	Unit.set_unit_visibility(unit, false)
	local hand_node = Unit.node(character, CONFIG.hand_node)

	World.link_unit(world, unit, 0, character, hand_node)
	Unit.set_material(unit, "m_power", CONFIG.chamber_material)

	local entry = {
		character = character,
		hand_node = hand_node,
		staff = staff,
		unit = unit,
		world = world,
	}

	attached[character] = entry

	place(entry)
end

-- The staff of a character if the skin is to replace it: the Shock Rifle is what it wields and the setting is on
local function staff_to_replace(character)
	if not utils.is_weapon_skin_enabled(SETTING_ID) or utils.wielded_template_name(character) ~= TEMPLATE_NAME then
		return nil
	end

	local equipment = ScriptUnit.extension(character, "inventory_system"):equipment()
	local staff = equipment.right_hand_wielded_unit_3p

	return staff and Unit.alive(staff) and staff or nil
end

-- If the character is shown holding its weapon: the player's own character is not while the view is the first person one
-- (the game hides the staff's unit then)
function module.shows_weapon(character)
	if utils.is_local_player_unit(character) then
		local first_person_extension = ScriptUnit.has_extension(character, "first_person_system")

		return first_person_extension ~= nil and not first_person_extension:first_person_mode_active()
	end

	return true
end

-- Every frame (and again before the frame is drawn, the game shows its units at times of its own)
function module.update()
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
				Unit.set_unit_visibility(entry.unit, module.shows_weapon(character))
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

-- The staffs are hidden again before the frame is drawn: the game shows them at times of its own, after the update
function module.hide_staffs()
	for _, entry in pairs(attached) do
		if Unit.alive(entry.staff) then
			Unit.set_unit_visibility(entry.staff, false)
		end
	end
end

-- Where the barrel ends, for the flashes of a shot (nothing if the character holds the staff)
function module.muzzle_position(character)
	local entry = attached[character]

	if not entry or not Unit.alive(entry.unit) then
		return nil
	end

	local offset = Vector3(CONFIG.muzzle_right, CONFIG.muzzle_forward, CONFIG.muzzle_up) * module.meters_per_unit

	return Unit.world_position(entry.unit, 0) + Quaternion.rotate(Unit.world_rotation(entry.unit, 0), offset)
end

-- How many meters a UT unit of the mesh is as it is held (the flashes are made as big as the mesh is)
module.meters_per_unit = CONFIG.meters_per_unit * CONFIG.scale

-- All of them are given back (the setting is off, the mod is, the level is gone)
function module.clear()
	for character in pairs(attached) do
		detach(character)
	end
end

-- Development: sets how the mesh sits in the hand and says it
function module.tune(grip_forward, grip_right, grip_up, yaw, pitch, roll, scale)
	CONFIG.grip_forward = tonumber(grip_forward) or CONFIG.grip_forward
	CONFIG.grip_right = tonumber(grip_right) or CONFIG.grip_right
	CONFIG.grip_up = tonumber(grip_up) or CONFIG.grip_up
	CONFIG.yaw = tonumber(yaw) or CONFIG.yaw
	CONFIG.pitch = tonumber(pitch) or CONFIG.pitch
	CONFIG.roll = tonumber(roll) or CONFIG.roll
	CONFIG.scale = tonumber(scale) or CONFIG.scale
	module.meters_per_unit = CONFIG.meters_per_unit * CONFIG.scale

	for _, entry in pairs(attached) do
		place(entry)
	end

	mod:echo("shock skin 3p: grip forward %.1f right %.1f up %.1f, yaw %.1f pitch %.1f roll %.1f, scale %.2f", CONFIG.grip_forward, CONFIG.grip_right, CONFIG.grip_up, CONFIG.yaw, CONFIG.pitch, CONFIG.roll, CONFIG.scale)
end

return module
