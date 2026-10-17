# Weapon plan

Which careers get which weapon, and which game weapon each one is copied from (`items.register` with `base_item`).

Each weapon is made for one hero, from the base that reaches the most of that hero's careers. The game does the same: its weapons are
items per hero (`es_`, `dr_`, `wh_`, `we_`, `bw_`), and an item's `can_wield` lists careers of that hero. A career of another hero
needs its own copy from a base of that hero, because the animations, units and attachments are made for the base's careers.

| Weapon | Base | Careers | Base item's DLC | State |
|---|---|---|---|---|
| Shock Rifle | Beam Staff (`bw_skullstaff_beam`) | Pyromancer, Battle Wizard, Unchained, Necromancer | none | done |
| Bio Rifle | Masterwork Pistol (`dr_steam_pistol`) | Engineer, Ranger, Ironbreaker | cog | done |
| Flak Cannon | Blunderbuss (`es_blunderbuss`) | Mercenary, Huntsman, Foot Knight | none | done |
| Rocket Launcher | Repeating Crossbow (`wh_crossbow_repeater`) | Zealot, Bounty Hunter, Captain | none | done |
| Link Gun | Deepwood Staff (`we_life_staff`) now; see below | Sister of the Thorn now; everyone planned | woods | the physics version on the Deepwood Staff; the regular version for everyone is on the TODO list |
| Shield Gun | five melee bases, see below | everyone but the Warrior Priest | see below | done (the Warrior Priest's copy is on the TODO list) |
| Lightning Gun | Deepwood Staff (`we_life_staff`) | all four Kerillian careers | woods | done (heat and the staff's overheat instead of ammo; inspect and bots not yet checked against UT) |
| Sniper Rifle (UT2004's classic one) | Handgun (`es_handgun`, `dr_handgun`) | Mercenary, Huntsman, Foot Knight, Ironbreaker, Ranger | none | in progress |
| Assault Rifle (akimbo) | Brace of Pistols (`wh_brace_of_pistols`) or Repeating Pistols (`wh_repeating_pistols`); Drakefire Pistols (`dr_drake_pistol`) | Zealot, Bounty Hunter, Captain, Ironbreaker | none | in progress (Brace of Pistols only: two rifles, rounds with UT's spread, charged bouncing grenades, UT models and sounds; the Drakefire Pistols, the grenade count, the grenade smoke and NewExplosionB are open) |
| Minigun | Repeater: `es_repeating_handgun`; `wh_repeating_pistols` | Mercenary, Huntsman, Foot Knight, Zealot, Bounty Hunter, Captain | none | done |
| Redeemer | Trollhammer Torpedo (`dr_deus_01`) | Ironbreaker | grass | in progress (missile, six-wave blast, one missile, UT model, sounds; the guided missile and the blast's look are open) |

## Careers without a weapon

- Slayer: the Shield Gun only. He has the game's Throwing Axes.
- Grail Knight: the Shield Gun only. No ranged item of the game lists him.
- Warrior Priest: none yet. No ranged item lists him, and his third person body has only his own weapons' animations. His Shield Gun
  is on the TODO list.
- Engineer: the Bio Rifle and the Shield Gun. His only ranged weapon in the game is the steam pistol.
- Ranger: the Bio Rifle, the Sniper Rifle and the Shield Gun.

## Notes

- Link Gun. The Deepwood Staff reaches only the Sister of the Thorn. The Javelin reaches all four careers, but it is a thrown
  weapon: a melee-style template with 3 javelins as ammo, and ammo pickups blocked. The bows reach Shade, Handmaiden and Waywatcher
  but not the Sister. The base also decides the resource. UT's Link Gun uses ammo (220 at most, 2 for a bolt, 1 for a beam hit, none
  while linked to a teammate), and the staff uses the heat meter that the mod's costs are built on (see `link/link_gun.lua`). The
  plan (TODO) is two weapons: a regular one on ammo for everyone, and the physics one on heat for Sienna and Kerillian.
- Shield Gun. A melee base for each hero, so five registrations: Kruber's Bastard Sword (lake), Bardin's Cog Hammer (cog), Sienna's
  Ghost Scythe (shovel), Victor's Billhook (scorpion) and Kerillian's Spear (none). The Billhook doesn't reach the Warrior Priest,
  who has none. The Thornsister had no melee item in the item list.
- Assault Rifle. UT2004's rifle has a dual mode (`bDualMode`), and this one is always akimbo. The skins place one model in the first
  person view and one on the character, so a pair needs a second model for the other hand, in both. Bardin's only dual-wield
  weapon is the Drakefire Pistols, which only the Ironbreaker has. The Ranger and the Engineer need `can_wield` widened on it.
- Lightning Gun. The Deepwood Staff's item lists only the Sister of the Thorn, but all four of Kerillian's careers share one third
  person body (`way_watcher`), which has the staff's animations, so the copy lists all four. Heat belongs to the career, not the weapon
  (`OverchargeData[career]`): the other three careers have none, which would overheat them as Sienna does, so they get the Sister's.
- Sniper Rifle. Kruber's handgun and Bardin's handgun are separate templates (`handgun_template_1` and `handgun_template_2`), so it
  is two registrations. The Engineer has no handgun.
- Redeemer. The Trollhammer Torpedo is Ironbreaker only. The Engineer has it only in Versus.
- The Necromancer can carry any staff in the game, but the local item list shows only her own staff. So the staff weapons name her
  in `can_wield` themselves (the Shock Rifle does).
- `items.register` copies the whole base item and clears its `required_dlc`, so a weapon of the mod does not need the DLC of its base
  (the "Base item's DLC" column is only where the base comes from). The game loads every DLC's scripts and packages for everyone,
  so cloning a base does not need the DLC either. A career that is itself a DLC career is still locked by its own DLC.
- A career that equips an item it is not listed for crashes the game (see `CLAUDE.md`), so widening `can_wield` needs the first
  person and third person animations of that career to exist for the base.

## Not planned

- Impact Hammer: out of scope.
- Versus: out of scope. The weapons are for the heroes' careers; the Versus careers (the Skaven players, and the heroes' Versus-only
  weapons such as the Engineer's Trollhammer Torpedo) are not given any.
- Not in the plan so far: Translocator, Ion Painter, Mine Layer, AVRiL, Grenade Launcher and the Bombing Run ball launcher.
