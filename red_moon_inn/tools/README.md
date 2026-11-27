# Converting the inn

`levels/red_moon_inn/red_moon_inn/world.level` is made from Vermintide 1's Red Moon Inn (`levels/inn/world`) by `convert_level.py`.
Make it again rather than editing what the conversion wrote, until the level is worked on in the editor.

Vermintide 1 only has the level compiled, in its bundles, and a compiled level keeps names as hashes. The converter reads it, and
names what it can by hashing the names Vermintide 2 has: the files of the Modding Tools Content and of the SDK's `core`. What
Vermintide 2 doesn't have is left out of the level and listed in `missing.txt`, under the names Vermintide 1's own strings give it.

1. Collect the strings of Vermintide 1's bundles (a few minutes; only needed once):

        python vt1_strings.py "<Vermintide 1>" vt1_strings.txt

2. Convert:

        python convert_level.py "<Vermintide 1>" "<Modding Tools Content>/content" "<Vermintide 2 SDK>" vt1_strings.txt ../levels/red_moon_inn/red_moon_inn/world.level ../missing.txt

`compiled_level.py` says how the compiled level was read. Its fields were found by comparing Vermintide 2's keep, which is
compiled in Vermintide 2's bundles and in source in the Content: both games' compiled levels are laid out the same way, with a few
differences.
