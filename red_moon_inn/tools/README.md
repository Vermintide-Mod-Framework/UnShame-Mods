# Converting the inn

`levels/red_moon_inn/red_moon_inn/world.level` was made from Vermintide 1's Red Moon Inn (`levels/inn/world`) by `convert_level.py`,
and is now worked on in the editor. `convert_level.py` writes the whole level again, so running it loses what was done in the editor.
`add_stand_ins.py` adds the stand-ins for the inn's missing pieces (`STAND_INS` in `convert_level.py`) to the level as it is.

Vermintide 1 only has the level compiled, in its bundles, and a compiled level keeps names as hashes. The converter reads it, and
names what it can by hashing the names Vermintide 2 has: the files of the Modding Tools Content and of the SDK's `core`. What
Vermintide 2 doesn't have is left out of the level and listed in `missing.txt`, under the names Vermintide 1's own strings give it.

1. Collect the strings of Vermintide 1's bundles (a few minutes; only needed once):

        python vt1_strings.py "<Vermintide 1>" vt1_strings.txt

2. Convert, which starts the level over:

        python convert_level.py "<Vermintide 1>" "<Modding Tools Content>/content" "<Vermintide 2 SDK>" vt1_strings.txt ../levels/red_moon_inn/red_moon_inn/world.level ../missing.txt

   Or add the stand-ins to the level as it is, with the same arguments:

        python add_stand_ins.py "<Vermintide 1>" "<Modding Tools Content>/content" "<Vermintide 2 SDK>" vt1_strings.txt ../levels/red_moon_inn/red_moon_inn/world.level ../missing.txt

   Reload the level in the editor afterwards: saving the copy the editor has open writes over the file.

The heroes' rooms are levels of their own in the inn's bundle, which Vermintide 1 loads behind the doorways upstairs, at the
inn's units with `room_id` script data. `convert_level.py` converts them with the level to read and the name to give it:

    python convert_level.py ... ../levels/red_moon_inn/rooms/<hero>/world.level ../missing_rooms/<hero>.txt --vt1-level levels/inn/rooms/<hero>/world --level-resource levels/red_moon_inn/rooms/<hero>/world

The inn's environment is converted the same way, to `levels/red_moon_inn/environment/red_moon_inn.shading_environment`. What
Vermintide 2's template doesn't have is listed in `environment_missing.txt`:

    python convert_environment.py "<Vermintide 1>" "<Modding Tools Content>/content" "<Vermintide 2 SDK>" vt1_strings.txt ../levels/red_moon_inn/environment/red_moon_inn.shading_environment ../environment_missing.txt

`compiled_level.py` says how the compiled level was read. Its fields were found by comparing Vermintide 2's keep, which is
compiled in Vermintide 2's bundles and in source in the Content: both games' compiled levels are laid out the same way, with a few
differences.
