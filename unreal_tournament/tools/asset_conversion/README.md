# Converting UT2004 weapon assets for this mod

Local tools that produced `units/ut/*`, `texture_categories/ut.texture_category` and
`scripts/mods/unreal_tournament/asset_test_animations.lua`. They are run by hand, not by the build.

The assets are Epic's (Unreal Tournament 2004), taken from a legally owned copy. Fatshark's mod rules forbid third
party IP in a published mod: this branch is for local use, and nothing of it should be uploaded or pushed.

## Pipeline

1. Export from the game files with UModel (UE Viewer, gildor.org), `-game=ut2`, to `umodel/out3` next to these tools:

       umodel_64 -path="<UT2004>" -game=ut2 -export -out=out3 NewWeapons2004 ShockRifle SkeletalMesh
       umodel_64 -path="<UT2004>" -game=ut2 -export -out=out3 NewWeapons2004 ShockRifle MeshAnimation

   That gives `NewWeapons2004/SkeletalMesh/ShockRifle.psk`, `NewWeapons2004/MeshAnimation/ShockRifle.psa` and the
   textures `UT2004Weapons/Texture/ShockRifleTex0.tga` and `PowerGel.tga`.
2. `psk2bsi.py in.psk out.bsi g_shock m_body,m_power 0.0125` writes the mesh in the SDK's `.bsi` format, one geometry per
   material (`g_shock_0` the body, `g_shock_1` the energy chamber).
3. `tga2png.py in.tga out.png` converts a texture (the SDK takes png), with an optional tint.
4. `make_anim_assets.py` writes the animation keys as Lua and renders the flipbook of the chamber's gel.
5. `render_psk2.py` and `ut_fit2.py` are checks: a software render of the mesh with outward faces only, and the fit of
   the mesh in UT's projection against pixels of a screenshot of UT2004.

6. `render_icon.py in.bsi out.png size yaw pitch roll body.png,power.png` renders a converted mesh (a pickup's bsi, with the
   textures of its geometries in order) into an icon with a transparent background: the inventory icon of the weapon's item
   (`ui/ut/shock_rifle_icon.png`, made with `pickup.bsi 256 20 0 35`). Its `.texture` and `.material` (a gui material that
   items.lua registers in the UI's renderers) are next to it, in a package of their own (`resource_packages/unreal_tournament/icons`)
   that is listed in `unreal_tournament.mod` (the game only loads the packages that are) and that the mod keeps a handle to, so
   that it stays loaded when the mod is reloaded: the renderers hold the material locked, and the game fails when it is unloaded.

## What was found

- UModel's psk is right handed (x forward, y left, z up): the model's (right, forward, up) is (-y, x, z). The psk's
  front faces are clockwise, the SDK's counter-clockwise: the triangle order is (w0, w2, w1). The bsi's V is up.
- The mesh is single sided, only the side the player sees (the left one) has faces.
- UT never draws the mesh in its reference pose: the root bone of the animation moves all of it. Rotation convention of
  the psa: the rotation of the mesh is `q_animation * conj(q_reference)`, unconjugated (Pickup comes up from below,
  PutDown goes down, Fire kicks back).
- UT draws the weapon at `DrawScale` 0.7, `PlayerViewOffset * 90 / DisplayFOV`, `PlayerViewPivot`, with a horizontal
  field of view of about 86.5 (fitted, with small weapons off). See `asset_test.lua` for how that lands in this game.
- The standard SDK material needs `use_color_map = 1` for its color map to be used, and the key of the texture is
  `color_map`.
