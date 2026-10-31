local mod = get_mod("unreal_tournament")

-- UT's scorches (mod.scorches): xScorch, a texture that a projector puts onto the surfaces it reaches, drawn here as a decal of the
-- game's decal manager (mod.add_decal in hooks.lua). A scorch lasts its kind's LifeSpan plus -2 to 1 s at random, but at least 0.5 s
-- (xScorch.PostBeginPlay). A pool's decals all last as long, so a kind has a pool for each life one of its scorches can have.
--   scorches.add_kind(name, unit_name, life, pool_size)
--   scorches.put(name, position, normal, size, hit_unit, hit_actor)
--       Puts one on the surface at a position, size meters wide.
--   scorches.project(name, position, direction, size)
--       Puts one where UT's projector would: it starts PushBack back from position, and reaches MaxTraceDistance along direction, the
--       way it points, onto the level. It does nothing if the level isn't there.

local utils = mod.utils

local CONFIG = {
	push_back = 24, -- UT units (xScorch.PushBack)
	reach = 60, -- UT units (xScorch.MaxTraceDistance)
	-- The decal's box reaches as far into the surface as the projector does, but only this far out of it, as the Bio Rifle's splat, so
	-- that it doesn't reach the player's weapon: UT's projector skips actors (bProjectActor false), and the game's decal doesn't.
	reach_out = 0.15, -- meters
}

local scorches = {}
mod.scorches = scorches

local kinds = {}

function scorches.add_kind(name, unit_name, life, pool_size)
	local kind = {
		life = life,
		pools = {},
	}

	for change = -2, 1 do
		local scorch_life = math.max(0.5, life + change)

		if not kind.pools[scorch_life] then
			kind.pools[scorch_life] = name .. "_" .. scorch_life

			mod.add_decal_pool(kind.pools[scorch_life], unit_name, scorch_life, pool_size)
		end
	end

	kinds[name] = kind
end

function scorches.put(name, position, normal, size, hit_unit, hit_actor)
	local kind = kinds[name]
	local life = math.max(0.5, kind.life + math.random(0, 3) - 2)
	local reach_in = (CONFIG.reach - CONFIG.push_back) * utils.UT_UNIT
	local reach_out = CONFIG.reach_out
	local middle = position - normal * ((reach_in - reach_out) / 2)

	mod.add_decal(kind.pools[life], middle, normal, size, reach_in + reach_out, hit_unit, hit_actor)
end

function scorches.project(name, position, direction, size)
	if not Managers.world:has_world("level_world") then
		return
	end

	local physics_world = World.get_data(Managers.world:world("level_world"), "physics_world")
	local start = position - direction * (CONFIG.push_back * utils.UT_UNIT)
	local hit, hit_position, _, normal, actor = PhysicsWorld.immediate_raycast(physics_world, start, direction, CONFIG.reach * utils.UT_UNIT, "closest", "collision_filter", "filter_player_ray_projectile_static_only")

	if hit and normal and Vector3.length(normal) > 0.5 then
		scorches.put(name, hit_position, Vector3.normalize(normal), size, actor and Actor.unit(actor), actor)
	end
end
