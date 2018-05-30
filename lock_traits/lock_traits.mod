return {
	run = function()
		local mod_resources = {
			mod_script       = "scripts/mods/lock_traits/lock_traits",
			mod_data         = "scripts/mods/lock_traits/lock_traits_data",
			mod_localization = "scripts/mods/lock_traits/lock_traits_localization"
		}
  	new_mod("lock_traits", mod_resources)
	end,
	packages = {
		"resource_packages/lock_traits/lock_traits"
	},
}
