import sys, os, struct

# Makes the texture of the Lightning Gun's screen as UT2004 draws it: WeaponSkins.SniperScreen1C is a combiner that blends SniperScreen1
# (the scope's readout) over SniperScreen1Pan (scan lines, which UT pans) with SniperScreen1Pan as the mask (CO_AlphaBlend_With_Mask). The
# panning is left out, so this is one still picture. It is written into the export folder as a tga, where convert_weapon.py reads it.
# Usage: make_sniper_screen.py <umodel export dir>

sys.path.insert(0, os.path.dirname(__file__))
from formats import read_tga

export = sys.argv[1]
width, height, screen = read_tga(export + '/WeaponSkins/Texture/SniperScreen1.tga')
_, _, lines = read_tga(export + '/WeaponSkins/Texture/SniperScreen1Pan.tga')

out = bytearray()

for y in range(height):
    for x in range(width):
        o = x * 4
        mask = lines[y][o] / 255
        pixel = []

        for channel in range(3):
            pixel.append(round(lines[y][o + channel] * (1 - mask) + screen[y][o + channel] * mask))

        # (a tga stores blue, green, red, alpha)
        out += bytes((pixel[2], pixel[1], pixel[0], 255))

header = struct.pack('<BBBHHBHHHHBB', 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 0x28)
open(export + '/WeaponSkins/Texture/SniperScreen1C.tga', 'wb').write(header + bytes(out))
print('wrote', width, height)
