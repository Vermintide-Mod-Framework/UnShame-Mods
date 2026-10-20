# To do

`WEAPON_STATUS.md` is what to look at for a weapon, and which careers get which weapon, from which base.

## Weapons to finish

1. **Link Gun for everyone.** Two weapons that share their code (the primary, linking allies, link stacking), each with its own alt
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

## Adrenaline and sprees

2. **Adrenaline's combos.** The meter, its counter and the Adrenalin line are done (`adrenaline.lua`). The combos, at 100, started by UT's
   taps of the movement keys (xPlayer.CheckCombo), draining it over their time, with UT's effects in first and third person and the
   announcer's names: Speed; Booster, with a very fast dodge and stamina back too (temporary health doesn't go past full health);
   Berserk, with more stagger, push and cleave and a bigger push of the player's own hits, as UT's; and Invisible, in first person
   too if it can be. At least on the UT weapons, on all if it can be. A death in a combo empties the meter (xPawn.Died).
