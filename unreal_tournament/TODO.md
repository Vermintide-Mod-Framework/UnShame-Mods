# To do

`WEAPON_STATUS.md` is what to look at for a weapon, and which careers get which weapon, from which base.

## Weapons to finish

1. **Assault Rifle.** Go through its column of `WEAPON_STATUS.md`. It now holds UT's third person mesh (NewAssaultRifle_3rd), whose
   grip and turn need setting in the game.
2. **Link Gun for everyone.** Two weapons that share their code (the primary, linking allies, link stacking), each with its own alt
   and resource:
   - The regular Link Gun, UT2004's (`LinkFire`, `LinkAltFire`, `LinkProjectile`), for every career with a ranged slot. It uses
     ammo: 220 at most, 2 for a bolt, 1 for a beam hit, none while linked to a teammate. The alt is the damage beam. A copy for each
     hero, as the Shield Gun has. Sienna has no ammo weapon, so hers is a staff copy given ammo. The Warrior Priest has no ranged slot.
   - The physics Link Gun, the one in `link/link_gun.lua` now: heat, and the beam that holds, throws and pulls. For Sienna and
     Kerillian, as well as the regular one. A copy for Sienna on one of her staffs. Kerillian's could list all four of her careers, as
     the Lightning Gun's copy of the Deepwood Staff does. It needs its own name, so that the two are not both "Link Gun".
   - It can't be an illusion of the regular one, as Instagib is of the Shock Rifle. The ammo comes from the template, so the HUD would
     show the ammo and the heat both.
   - Link stacking, UT's `LinkGun.Links`: a teammate who is linked while linking gets a stronger beam. Both weapons count as Link Guns
     for it. Now a link gives an ally the same boost whatever they hold.
3. **Shield Gun for the Warrior Priest.** He can't use the Billhook, so his copy needs a base of his own (his one-handed hammer was
   used before). His third person body is his own (`witch_hunter_warrior_priest`), with only his weapons' animations. Check with
   `Unit.has_animation_event` which poses it has (the Volley Crossbow's `to_repeating_crossbow`, `to_zoom`, `to_unzoom` and
   `attack_shoot`, or one of his own weapons') before choosing his third person pose and grip.

## Adrenaline and sprees

4. **Adrenaline.**
5. **Chat messages for sprees,** like "X is on a Y spree" and "Z ended X's spree". Check the original for what is printed for everyone.

## Weapons made on the shell of their base

A weapon keeps only what belongs to its base's animations, models and sounds (`utils.template_shell`), and sets everything else itself,
as the Minigun does. What each finished weapon took from its base at build 1282 is in `INHERITED_FIELDS.md`.

6. **The other finished weapons.** Shock Rifle, Bio Rifle, Flak Cannon, Rocket Launcher, Lightning Gun, Shield Gun: write out what
   they take from their base today, on the shell, as the Minigun's are. That changes nothing in the game.
7. **The Shield Gun's copies differ by hero.** Each keeps its base's `dodge_count` (2 or 3), `weapon_type`, `buffs`, push
   (`action_one.push`) and block (`action_two.default`, with `max_fatigue_points` and `outer_block_*`). One set for all five, to
   be decided.
8. **`weapon_type`.** What the game's talents and traits take each weapon for (the Bio Rifle is a BRACE_OF_PISTOLS, the Shock Rifle a
   FIRE_STAFF, the Lightning Gun a LIFE_STAFF). Keep or choose. The Minigun keeps its base's, so that each hero's talents see his
   own repeater.
9. **Bots.** Each weapon's `attack_meta_data`: where bots aim, what they use it against, and whether they shoot past allies and
   enemies in the way. The Minigun's and the Lightning Gun's are written out in full. The Shock Rifle's and the Flak Cannon's change
   a few of their base's values and keep the rest.
10. **Wielding, reloading and inspecting.** These stay the game's: the Minigun takes `ActionTemplates.wield` and `reload` by name, and
   inspecting from its base. The other weapons the same.
