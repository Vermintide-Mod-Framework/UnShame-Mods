# To add later

1. Adrenaline.
2. Chat messages for sprees, like "X is on a Y spree" and "Z ended X's spree". Check the original for what is printed for everyone.

## New weapons

Each is an item of its own (`items.register`), UT2004's look always on, no setting. `WEAPON_CHECKLIST.md` is what to look at for a weapon.
Which careers get which weapon, and from which base, is in `WEAPON_PLAN.md`.

3. **Shield Gun.** For everyone, including the melee-only careers. A melee base for each hero.
4. **Lightning Gun.** From the Deepwood Staff, for Kerillian.
5. **Assault Rifle.** Akimbo. Needs a second model for the other hand.
6. **Minigun.** From the repeater.
7. **Redeemer.** From the Trollhammer Torpedo.
8. **Link Gun for everyone.** Two weapons that share their code (the primary, linking allies, link stacking), each with its own alt
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
9. **Shield Gun for the Warrior Priest.** He can't use the Billhook, so his copy needs a base of his own (his one-handed hammer was
   used before). His third person body is his own (`witch_hunter_warrior_priest`), with only his weapons' animations. Check with
   `Unit.has_animation_event` which poses it has (the Volley Crossbow's `to_repeating_crossbow`, `to_zoom`, `to_unzoom` and
   `attack_shoot`, or one of his own weapons') before choosing his third person pose and grip.
