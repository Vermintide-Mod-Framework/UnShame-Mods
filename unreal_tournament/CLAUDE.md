# Working on the Unreal Tournament mod

Read `README.md` here first (what the mod is, the layout, how it fits together), and `tools/*/README.md` for the assets and the game's files.
`TODO.md` is what is not done.

## Workflow

- Build from the `mods` folder (`E:\Git\vmb\mods`): `../vmb.exe build unreal_tournament -f . --rc ../vmb-rc`. **Read the output for errors before
  committing**: a build with a Lua error still produces files, and a broken commit has been pushed that way. Only report a build to the user if
  it fails.
- Every commit has its build number: in `scripts/mods/unreal_tournament/unreal_tournament.lua`, `(build N)` with N the number of commits
  (`git rev-list --count HEAD`) plus one. Bump it, build, commit, **and push**, for every change, on this branch too. Do not ask whether to commit.
- Edit code with the Edit and Write tools, not with Python or sed scripts through the shell (they have mangled backslashes and line endings). The
  files of the flak and the shock have CRLF line endings: keep them.
- The game can be started and driven from here with the scripts in `tools/` (PowerShell). `run_tests.ps1 -Suite <suite>` does the whole loop: it
  starts the game if it is not running (`start_game.ps1`: the game's program directly, without the launcher, and Enter on Start Game and on
  Adventure in the main menu), runs the in-game suite, and prints its results. It notices a crash (the game's process is gone), prints the
  Lua error and the dump, and exits with 3. `-Reload` reloads the mods first. `screenshot.ps1` and `game_input.ps1`
  give a picture of the game's window, and send it a key or a click.
  **Only ever take pictures of the window of Vermintide 2 or of Unreal Tournament 2004, never of the rest of the screen.** The launcher is not used, and the user has set
  `SendCrashReports = false` in the launcher's config so that a crash leaves no windows. The user still tests by playing and sends
  screenshots, logs and crash text. Do not add "I haven't tested this in game" disclaimers in replies; when something cannot be known from
  the code, say what is guessed and how it can be checked.
- Unreal Tournament 2004, the reference for the weapons, is driven the same way: `start_ut2004.ps1 [-Restart]` starts it in a level (the map
  is the program's argument, so no menus), starts the match, and gives all weapons with the console command `loaded`. Then `screenshot.ps1` and
  `game_input.ps1` with `-Target ut2004` show how the weapons look and play. The game reads the mouse as input, so `game_input.ps1` moves it
  with input events there; Ctrl is Fire and Tilde opens the console. Its window is moved to the top left, or its bottom is under the taskbar.
- To compare a weapon with UT2004's, take the same moment in both (a burst of pictures, `screenshot.ps1 -Burst 30 -Interval 0`, while a
  job presses fire: `game_input.ps1 -Press -Hold 100`) and put two of them together with `tools/compare_images.py` (side by side, blended,
  difference, checkerboard), cropped to the weapon. Compare, change, and compare again.
- The game's own logs and crash dumps: `%APPDATA%\Fatshark\Vermintide 2\console_logs` and `crash_dumps`. Look at them when told about a crash.
- In-game tests are in `scripts/mods/unreal_tournament/tests` (`runner.lua`, and a suite for each weapon). `/ut_test <suite>` runs one (or
  `tools/run_tests.ps1 -Suite <suite>`; several with `-Suite a,b` or `-Suite all`, in one command): it loads its level, sets the career and weapon, and goes back to the Keep. The results are lines that
  start with `[ut_test]` in the console log. The game's engine calls that use the world or physics are made on the main thread
  (`t.on_main_thread`), because a coroutine's references are refused.

## How to work with the user

- They are exact and don't like guessing. Find the root cause (read the game's source for what it does, compare the host and client paths and the
  order of updates) and do not tune numbers hoping. Do not add speculative workarounds.
- For a pose or a placement of a model, render it first (`tools/asset_conversion/preview_weapon.py`) and look, then change it.
- For anything UT does, read UT2004's source (`gh api repos/Deaod/UT2004/contents/<package>/<Class>.uc`) and match it; where this mod departs from
  UT on purpose, say so in the code.
- Replies are short and plain: what was done, what was found, what is open. No recap of the conversation, no build times.
- Do not offer to do what was already decided or decline what was asked. Ask a question only when the answer changes what is done.

## Code

- Comments are plain, short, clear sentences that say what the code does or why. 
- Match the surrounding code's naming and layout; tuning numbers are in each file's `CONFIG` with the units in a comment.
- The framework lets a mod hook a function once: a second `mod:hook` on the same function is refused. Shared hooks are in `hooks.lua`, with tables
  of callbacks that the weapons add to.
- Things that crash the game: a unit of the mod alive when its package is unloaded; playing an effect that is not loaded
  (`effects.is_available`); spawning a projectile unit that is not loaded; a career equipping an item it is not locked to (`can_wield`);
  passing a boxed vector to an engine function (`utils.as_vector`).
- Vectors are userdata (`Vector3.x(v)`, not `v.x`); `Quaternion.from_euler_angles_xyz` takes degrees; `POSITION_LOOKUP[player_unit]` is not a plain
  vector.
