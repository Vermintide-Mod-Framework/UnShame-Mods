# Bugs found by the tests

What the in-game tests (`scripts/mods/unreal_tournament/tests`) found the mod doing wrong, checked in the game. Each has the suite and scenario
that shows it. The tests run on Legend.

## Movement

1. **The Shield Gun's punch gets no momentum damage.** `movement` / "a melee hit while moving fast does more damage", while the melee slot
   held the Shield Gun: the punch at 7 m/s did the same as standing, and was sent with the power level unchanged (835 both times). The punch
   sends its hit itself (`shield_gun.lua` `melee_hit`: `weapon_system:send_rpc_attack_hit`) and never goes through
   `ActionSweep._send_attack_hit`, which is what the momentum scales. (The Shield Gun is not one of the weapons the tests cover; this is
   where it meets the movement. The scenario now uses the game's sword.)

## Flak Cannon

1. **A shell that hits an enemy procs the buffs on attack twice.** `flak` / "a shell that hits an enemy procs once". A shell fired into
   three rats ran `DamageUtils.buff_on_attack` for the player twice: once for its direct hit (attack type "projectile") and once for its
   explosion ("aoe"). The hook in `flak_cannon.lua` counts the explosion and the chunks as one shot, but the shell's own hit is neither a
   chunk nor an "aoe" attack, so it runs the buffs on its own. A shell that lands among enemies without touching one procs once ("a shell
   that lands among enemies procs once"). This is the double proc of one alt shot (an ammo trait twice) that was fixed for the explosion and
   the shrapnel, by the other way.
