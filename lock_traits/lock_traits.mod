return {
	run = function()
		local mod = new_mod("lock_traits")
		mod:localization("localization/lock_traits")
		mod:initialize("scripts/mods/lock_traits/lock_traits")
	end,
	packages = {
		"resource_packages/lock_traits/lock_traits"
	},
}
