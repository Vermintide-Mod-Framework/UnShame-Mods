import sys, os, math
from formats import read_tga, write_png
from resources import texture_text, gui_material_text

# Makes the inventory icons, ui/ut/<name>_icon: each is the weapon's icon on UT's weapon bar (its class's IconCoords on HudContent's
# HUD texture), turned to point up and to the right as the game's icons do (UT's point left, so it is flipped, then turned 45 degrees),
# on a square with a transparent background, with its .texture and a gui material ut_<name>_icon that items.lua registers in the UI's
# renderers.
# Usage: make_icons.py <export dir> [name ...]      (all of ICONS if none are given)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SIZE = 256
# How much of the square the turned icon's longer side takes up: the game's frame covers the edges of an icon
FILL = 0.72
# Samples a pixel of the icon takes along each side, for its edges
SUPER = 3

# name: the icon's IconCoords (X1, Y1, X2, Y2). The Instagib Shock Rifle is UT's SuperShockRifle, which has the Shock Rifle's icon, and the
# UT2003 Shock Rifle has it too (UT2003's own HUD is not at hand).
SHOCK = (250, 110, 330, 145)
ICONS = {
    'assault_rifle': (245, 39, 329, 79),
    'bio_rifle': (179, 127, 241, 175),
    'flak_cannon': (169, 172, 245, 208),
    'lightning_gun': (246, 182, 331, 210),
    'link_gun': (169, 78, 244, 124),
    'minigun': (246, 80, 332, 106),
    'rocket_launcher': (253, 146, 333, 181),
    'shield_gun': (169, 39, 241, 77),
    'shock_rifle': SHOCK,
    'shock_rifle_2003': SHOCK,
    'shock_rifle_instagib': SHOCK,
    # (ClassicSniperRifle)
    'sniper_rifle': (420, 180, 512, 210),
}

def icon_pixels(rows, coords):
    # The icon's pixels as (r, g, b, a) floats, its colour times its alpha, flipped left to right; and its width and height
    x1, y1, x2, y2 = coords
    width, height = x2 - x1, y2 - y1
    pixels = []

    for y in range(height):
        row = rows[y1 + y]
        line = []

        for x in range(width):
            i = 4 * (x2 - 1 - x)
            alpha = row[i + 3] / 255
            line.append((row[i] * alpha, row[i + 1] * alpha, row[i + 2] * alpha, alpha))

        pixels.append(line)

    return pixels, width, height

def sample(pixels, width, height, x, y):
    # Bilinear, transparent outside the icon
    x, y = x - 0.5, y - 0.5
    x0, y0 = math.floor(x), math.floor(y)
    fx, fy = x - x0, y - y0
    total = [0.0, 0.0, 0.0, 0.0]

    for dx, dy, weight in ((0, 0, (1 - fx) * (1 - fy)), (1, 0, fx * (1 - fy)), (0, 1, (1 - fx) * fy), (1, 1, fx * fy)):
        px, py = x0 + dx, y0 + dy

        if weight > 0 and 0 <= px < width and 0 <= py < height:
            pixel = pixels[py][px]

            for c in range(4):
                total[c] += pixel[c] * weight

    return total

def make(rows, coords):
    pixels, width, height = icon_pixels(rows, coords)
    # The part of the icon that is not transparent, which is centered and fills the square
    seen = [(x, y) for y in range(height) for x in range(width) if pixels[y][x][3] > 0.02]
    left, right = min(x for x, _ in seen), max(x for x, _ in seen) + 1
    top, bottom = min(y for _, y in seen), max(y for _, y in seen) + 1
    center_x, center_y = (left + right) / 2, (top + bottom) / 2
    # A turn of 45 degrees makes a box of w by h about (w + h) / sqrt(2) on each side
    turned = (right - left + bottom - top) / math.sqrt(2)
    scale = FILL * SIZE / turned
    # The picture's y goes down, so turning up to the left (counterclockwise) is turning by -45 degrees in it
    cos, sin = math.cos(math.radians(45)), math.sin(math.radians(45))
    out = []

    for oy in range(SIZE):
        line = bytearray()

        for ox in range(SIZE):
            total = [0.0, 0.0, 0.0, 0.0]

            for sy in range(SUPER):
                for sx in range(SUPER):
                    # The point of the square, from its middle, in the icon's pixels, turned back
                    px = (ox + (sx + 0.5) / SUPER - SIZE / 2) / scale
                    py = (oy + (sy + 0.5) / SUPER - SIZE / 2) / scale
                    ix = px * cos - py * sin + center_x
                    iy = px * sin + py * cos + center_y
                    value = sample(pixels, width, height, ix, iy)

                    for c in range(4):
                        total[c] += value[c]

            alpha = total[3] / (SUPER * SUPER)

            if alpha > 0:
                line += bytes(min(255, round(total[c] / total[3])) for c in range(3)) + bytes([round(alpha * 255)])
            else:
                line += bytes(4)

        out.append(bytes(line))

    return out

def main():
    export = sys.argv[1]
    names = sys.argv[2:] or list(ICONS)
    width, height, rows = read_tga('%s/HudContent/Texture/HUD.tga' % export)

    for name in names:
        path = 'ui/ut/%s_icon' % name

        write_png('%s/%s.png' % (REPO, path), SIZE, SIZE, make(rows, ICONS[name]))
        open('%s/%s.texture' % (REPO, path), 'w', newline='\n').write(texture_text(path))
        open('%s/%s.material' % (REPO, path), 'w', newline='\n').write(gui_material_text('ut_%s_icon' % name, path))
        print('icon', name)

main()
