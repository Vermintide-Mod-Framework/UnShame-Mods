# Bugs found by the tests

What the in-game tests (`scripts/mods/unreal_tournament/tests`) found the mod doing wrong, checked in the game. Each has the suite and scenario
that shows it.

## Movement

1. **Fall damage depends on the frame, not on the landing speed.** `movement` / "a fall faster than UT's MaxFallSpeed hurts by UT's rule".
   A fall of 25 m lands at 25.8 m/s every time (UT's MaxFallSpeed is 20.3 m/s here, so UT's rule gives about 27 damage), and five runs of it
   did 0, 0, 0, 6.5 and 20.7 damage. `movement.lua` takes the landing speed from `velocity_current` after the last update in the air
   (`fall_speeds`). The game sets that velocity from how far the mover really moved in the frame
   (`PlayerUnitLocomotionExtension.update_script_driven_movement`: `final_velocity = (final_position - current_position) / dt`). In the frame
   where the mover reaches the floor the move is cut short, and the player is not on the ground yet, so the speed kept is only the part of the
   frame's fall that was left above the floor.
