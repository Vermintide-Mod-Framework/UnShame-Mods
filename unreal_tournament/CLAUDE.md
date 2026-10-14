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
- The game cannot be run from here. The user tests in game and sends screenshots, logs and crash text. Do not add "I haven't tested this in
  game" disclaimers in replies; when something cannot be known from the code, say what is guessed and how the user can check it.
- The game's own logs and crash dumps: `%APPDATA%\Fatshark\Vermintide 2\console_logs` and `crash_dumps`. Look at them when told about a crash.
- In-game tests are in `scripts/mods/unreal_tournament/tests` (`runner.lua`, and a suite for each weapon). The user runs `/ut_test <suite>` in a
  mission, and the results are lines that start with `[ut_test]` in the console log. A suite has to be tried in game before it is relied on:
  it sets the loadout and career and respawns the player, which the code only guesses will work.

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
