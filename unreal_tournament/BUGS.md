# Bugs found by the tests

What the in-game tests (`scripts/mods/unreal_tournament/tests`) found the mod doing wrong, checked in the game. Each has the suite and scenario
that shows it. The tests run on the difficulty a level loaded by the tests gets, Normal.

## Movement

1. **Fall damage depends on the frame, not on the landing speed.** `movement` / "a fall faster than UT's MaxFallSpeed hurts by UT's rule".
   A fall of 25 m lands at 25.8 m/s every time (UT's MaxFallSpeed is 20.3 m/s here, so UT's rule gives about 27 damage), and five runs of it
   did 0, 0, 0, 6.5 and 20.7 damage. `movement.lua` takes the landing speed from `velocity_current` after the last update in the air
   (`fall_speeds`). The game sets that velocity from how far the mover really moved in the frame
   (`PlayerUnitLocomotionExtension.update_script_driven_movement`: `final_velocity = (final_position - current_position) / dt`). In the frame
   where the mover reaches the floor the move is cut short, and the player is not on the ground yet, so the speed kept is only the part of the
   frame's fall that was left above the floor.

2. **Momentum damage is far less than its numbers say.** `movement` / "a melee hit while moving fast does more damage". A light attack of
   Kruber's sword in a forward dodge at 7.6 m/s did 11.0 against 10.5 standing: 5% more, where `momentum_damage_bonus` and the speeds give
   17% (25% at 9 m/s). The bonus multiplies the power level the hit is sent with (`ActionSweep._send_attack_hit`), and the hook does apply it
   (a call of the hooked function at 7 m/s turns 100 into 114). The game does not turn power into damage in proportion: on Normal the power
   above the difficulty's cap (400) counts at a reduced rate (`ActionUtils.scale_power_levels`), and the power curve flattens it further. How
   much of the bonus is left depends on the difficulty and the player's power.

3. **The Shield Gun's punch gets no momentum damage.** Found by the same scenario while the melee slot held the Shield Gun: the punch at
   7 m/s did the same as standing, and was sent with the power level unchanged (835 both times). The punch sends its hit itself
   (`shield_gun.lua` `melee_hit`: `weapon_system:send_rpc_attack_hit`) and never goes through `ActionSweep._send_attack_hit`, which is what
   the momentum scales. (The Shield Gun is not one of the weapons the tests cover; this is where it meets the movement.)

## Flak Cannon

1. **A shell that hits an enemy procs the buffs on attack twice.** `flak` / "a shell that hits an enemy procs once". A shell fired into
   three rats ran `DamageUtils.buff_on_attack` for the player twice: once for its direct hit (attack type "projectile") and once for its
   explosion ("aoe"). The hook in `flak_cannon.lua` counts the explosion and the chunks as one shot, but the shell's own hit is neither a
   chunk nor an "aoe" attack, so it runs the buffs on its own. A shell that lands among enemies without touching one procs once ("a shell that lands among enemies procs once"). This is the
   double proc of one alt shot (an ammo trait twice) that was fixed for the explosion and the shrapnel, by the other way.
