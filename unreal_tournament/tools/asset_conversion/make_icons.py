import sys, os, subprocess, tempfile
from formats import read_png, rgb_at, write_png
from resources import texture_text, gui_material_text

# Makes the inventory icons, ui/ut/<name>_icon: each rendered from its weapon's pickup by render_icon.py, with its .texture, and a gui
# material ut_<name>_icon that items.lua registers in the UI's renderers. Run it after the pickups are converted.
# Usage: make_icons.py [name ...]      (all of ICONS if none are given)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
UNITS = REPO + '/units/ut/'
SIZE = 256

# name: (the pickup, its textures in the order of its geometries, yaw, pitch, roll, fill, mirror). The yaw puts the muzzle at the top
# right. fill is how much of the picture the weapon takes up (None for render_icon.py's own). A texture that is a function is made from
# the texture before it in the list by that function of a pixel's (r, g, b), in place of it.
def instagib_power(r, g, b):
    # the chamber of the Instagib Shock Rifle, red as its ShockControl color (HUD.RedColor) makes it
    level = min(255, (r + g + b) / 3 * 1.4)

    return int(level), int(level * 0.12), int(level * 0.12), 255

ICONS = {
    'assault_rifle': ('assault/pickup.bsi', ['assault/pickup_assaultrifletex0.png'], 20, 0, 35, 0.72, False),
    # (from the side with the orange band, which points up and to the left, so it is mirrored)
    'bio_rifle': ('bio/pickup.bsi', ['bio/pickup_biorifletex0.png', 'bio/pickup_biorifleglass0.png'], -70, 0, -35, 0.74, True),
    'flak_cannon': ('flak/pickup.bsi', ['flak/pickup_flak3rdperson.png'], -70, 0, 35, 0.72, False),
    'lightning_gun': ('lightning/pickup.bsi', ['lightning/pickup_snipertex0.png'], 110, 0, 35, 0.72, False),
    'link_gun': ('link/pickup.bsi', ['link/pickup_linktex0.png'], -70, 0, 35, 0.72, False),
    'minigun': ('minigun/pickup.bsi', ['minigun/pickup_miniguntex0.png'], 110, 0, 35, 0.72, False),
    'rocket_launcher': ('rocket/pickup.bsi', ['rocket/pickup_rockettex0.png'], 110, 0, 35, 0.72, False),
    'shield_gun': ('shield/pickup.bsi', ['shield/pickup_shieldtex0.png'], 110, 0, 35, 0.72, False),
    'shock_rifle': ('shock/pickup.bsi', ['shock/shock_body_df.png', 'shock/shock_power_df.png'], 20, 0, 35, None, False),
    'shock_rifle_2003': ('shock2003/pickup.bsi', ['shock2003/pickup_shocktex0.png'], -70, 0, 35, None, False),
    'shock_rifle_instagib': ('shock/pickup.bsi', ['shock/shock_body_df.png', 'shock/shock_power_df.png', instagib_power], 20, 0, 35, None,
                             False),
    'sniper_rifle': ('sniper/pickup.bsi', ['sniper/pickup_sniper1.png'], 110, 0, 35, 0.72, False),
}

def textures(names, folder):
    # The paths of the textures, with those made by a function written into the folder
    paths = []

    for name in names:
        if callable(name):
            width, height, channels, rows = read_png(paths[-1])
            made = [b''.join(bytes(name(*rgb_at(rows, channels, x, y))) for x in range(width)) for y in range(height)]
            paths[-1] = '%s/%d.png' % (folder, len(paths))
            write_png(paths[-1], width, height, made)
        else:
            paths.append(UNITS + name)

    return paths

def main():
    names = sys.argv[1:] or list(ICONS)
    folder = tempfile.TemporaryDirectory()

    for name in names:
        pickup, texture_names, yaw, pitch, roll, fill, mirror = ICONS[name]
        path = 'ui/ut/%s_icon' % name
        arguments = [UNITS + pickup, '%s/%s.png' % (REPO, path), str(SIZE), str(yaw), str(pitch), str(roll),
                     ','.join(textures(texture_names, folder.name))]

        if fill is not None:
            arguments.append(str(fill))

        if mirror:
            arguments.append('mirror')

        subprocess.check_call([sys.executable, os.path.join(os.path.dirname(__file__), 'render_icon.py')] + arguments)
        open('%s/%s.texture' % (REPO, path), 'w', newline='\n').write(texture_text(path))
        open('%s/%s.material' % (REPO, path), 'w', newline='\n').write(gui_material_text('ut_%s_icon' % name, path))

main()
