# Looking into the game's data and engine

Local tools for finding out how Vermintide 2 does something where there is no source for it. They are run by hand, not by the build, and
they only read the game's files.

- `bundles.py` reads the game's resource bundles: which bundle has a resource (`find`, `where`), what a bundle holds (`list`), and a bundle
  unpacked (`unpack`). The names of resources are not in the bundles, only their hashes, so a name has to be known to be found. The game folder is
  in the `VT2_DIR` environment variable. It is how the game's own particle files, which are compiled and
  not text, were found (`fx/wpnfx_frag_grenade_impact` is in one of 15250 bytes).
- `lua_bytecode.py` finds the compiled Lua in an unpacked bundle or a mod's bundle and writes each piece to a file named by its chunk name.
  They can be turned into text with a LuaJIT decompiler (luajit-decompiler-v2).
- `engine.py` looks into the engine's executable: strings, what uses a string, what calls a function, and the code at an address. It is how it
  was seen that the address every crash dump of the game's fatal errors ends at (`vermintide2_dx12.exe`, RVA 0x305826 in the current build)
  is a write to address 0: the engine's own way of stopping.

They need Python with `zstandard` (bundles), `pefile` and `capstone` (engine): `pip install zstandard pefile capstone`.

The game's data are Fatshark's: the tools are for reading them, and nothing from them belongs in a published mod.
