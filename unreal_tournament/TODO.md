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
8. **Link Gun for all of Kerillian's careers.** The base and the resource (heat or ammo) are open.
9. **Shield Gun for the Warrior Priest.** He can't use the Billhook, so his copy needs a base of his own (his one-handed hammer was
   used before). His third person body is his own (`witch_hunter_warrior_priest`), with only his weapons' animations. Check with
   `Unit.has_animation_event` which poses it has (the Volley Crossbow's `to_repeating_crossbow`, `to_zoom`, `to_unzoom` and
   `attack_shoot`, or one of his own weapons') before choosing his third person pose and grip.
