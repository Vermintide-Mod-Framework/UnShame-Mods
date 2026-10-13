# To add later

1. Adrenaline.
2. Chat messages for sprees, like "X is on a Y spree" and "Z ended X's spree". Check the original for what is printed for everyone.
3. The Flak Cannon's shell sets off Bio Rifle goo (UT's DamTypeFlakShell has bDetonatesGoop).

## Weapons to convert to the new approach

The Shock Rifle, the Flak Cannon and the Rocket Launcher are items of their own: a copy of the base item and template (`items.register`),
UT2004's look always on, no setting. The Bio Rifle and the Link Gun still change the game's weapon in place, with a setting, and their looks are
the Weapon Skins setting. Each one gets what the first ones got:

- An item of its own with `items.register`: a copy of the base item and template (the base weapon is left as the game has it), named like the
  others ("UT2004 <name>", with UT's own name of the weapon as its type), with UT's flavor text as the description, edited down to the length of the
  Shock Rifle's.
- The careers that can use it are the base weapon's (`can_wield`). A career that equips an item it is not locked to crashes the game.
- An icon of its own (`render_icon.py` with the pickup, fill 0.72), UT's keywords for it checked against how it plays, and a stat chart
  (`weapon_diagram`) set for it.
- No setting and no checkbox: the weapon is enabled with the mod (the enabled and disabled callbacks, not `utils.register_weapon`), and its
  localization strings go.
- The look always on: the first person model, the third person (the grip, the muzzle, whether it follows the arms), the hero and the item screens
  (`menu_yaw`), and the inspect pose, each placed with `preview_weapon.py`.
- What the code was doing to switch the weapon off (the restore, the checks of the setting) is removed.
- Its bots (`<weapon>/bots.lua`), if it needs more than the base weapon's shooting.

For each:

4. **Bio Rifle** (the Drakegun, Bardin's). The puddles and the goo are in `bio_rifle.lua`: they are part of the weapon and go with it.
5. **Link Gun** (the Deepwood Staff, the Thornsister's). It is the largest, with the link beam, the allies, the corpses and the objects it
   can link: its parts in the game's systems (the bot group, the vortex, falling) are hooked in the file and should only act on the new item.

After both are done:

6. Remove the Weapon Skins setting, the weapons checkbox and the settings of the weapons, and `utils.register_weapon` with what only it used. Update
   the README and the localization.

## New weapons

7. **Impact Hammer.** Engineer is the natural fit (the hammer), the Slayer can have it too.
8. **Shield Gun.** For the careers that fight with a sword and a shield.
