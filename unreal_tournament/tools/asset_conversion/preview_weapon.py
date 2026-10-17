import sys, os, math
from formats import read_png, rgb_at, write_png, read_psk
from quat import qmul, rotate, axis_angle

# A software preview of a first person weapon of the mod, drawn the way weapon_skin.lua places it: the weapon's idle pose, the view offset
# and pivot of UT's weapon class, and optionally the inspect pose (the offsets, the turn, and the point it turns about). It is for checking
# a pose without starting the game: the picture agrees with the game to within a few pixels. The picture is a 16:9 view of 960 by 540.
#
# Usage: preview_weapon.py <weapon> <umodel export dir> out.png [right forward up roll pitch yaw [pivot_right pivot_forward pivot_up]]
#   weapon: one of WEAPONS below. The export dir has the weapon's psk (see README.md). Without the numbers the weapon is in its idle pose;
#   with them they are the inspect_pose_* and inspect_pivot_* of the weapon's skin (UT units, degrees), as if the inspect were fully in.
#
# What it does not do: only the root bone is posed (the other parts of the model are in their reference pose: the hammer of the Flak Cannon,
# for instance, is not where the animation puts it), and the lighting is a simple shading from the way a face points.

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
WIDTH, HEIGHT = 960, 540
# The horizontal field of view of the weapon is that of the class's DisplayFOV times this (see weapon_skin.lua, FIELD_OF_VIEW_FACTOR), unless
# the weapon has one of its own
FIELD_OF_VIEW_FACTOR = 1.345

# psk: the mesh. textures: the png of each material of the mesh (None: not drawn), in the order of the mesh. lua: the animations, of which the
# idle pose of the root is used. display_fov, draw_scale, offset (right, forward, up), pivot (yaw, pitch, roll) are the weapon's skin config.
WEAPONS = {
    'flak': {
        'psk': 'Weapons/SkeletalMesh/Flak_1st.psk',
        'textures': ['units/ut/flak/flak_cannon_flaktex0.png', 'units/ut/flak/flak_cannon_flaktex1.png', 'units/ut/flak/flak_cannon_flaktex0.png'],
        'lua': 'scripts/mods/unreal_tournament/flak/skin_animations.lua',
        'display_fov': 60,
        'draw_scale': 1,
        'offset': (8, -7, 0),
        'pivot': (16884 / 65536 * 360, 0, 200 / 65536 * 360),
    },
    'rocket': {
        'psk': 'Weapons/SkeletalMesh/RocketLauncher_1st.psk',
        'textures': ['units/ut/rocket/rocket_launcher_rockettex0.png'],
        'lua': 'scripts/mods/unreal_tournament/rocket/skin_animations.lua',
        'display_fov': 60,
        'draw_scale': 1,
        'offset': (8, 0, 0),
        'pivot': (500 / 65536 * 360, 0, -1000 / 65536 * 360),
    },
    'bio': {
        'psk': 'Weapons/SkeletalMesh/BioRifle_1st.psk',
        'textures': ['units/ut/bio/bio_rifle_biorifletex0.png', None, 'units/ut/bio/bio_rifle_brinnergoo.png'],
        'lua': 'scripts/mods/unreal_tournament/bio/skin_animations.lua',
        'display_fov': 60,
        'draw_scale': 1,
        'offset': (3, 7, 0),
        'pivot': (0, 0, 0),
    },
    'sniper': {
        'psk': 'Weapons/SkeletalMesh/Sniper_1st.psk',
        'textures': ['units/ut/lightning/lightning_gun_snipertex0.png', 'units/ut/lightning/lightning_gun_sniperscreen1c.png', 'units/ut/lightning/lightning_gun_sniperscreen2.png'],
        'lua': 'scripts/mods/unreal_tournament/lightning/skin_animations.lua',
        'display_fov': 60,
        'draw_scale': 0.4,
        'offset': (2.3, 0, 0),
        'pivot': (0, 0, 0),
    },
    'classic_sniper': {
        'psk': 'SniperAnims/SkeletalMesh/SniperRifle_1st.psk',
        'textures': ['units/ut/sniper/sniper_rifle_newsniper1.png', 'units/ut/sniper/sniper_rifle_sniper2.png'],
        'lua': 'scripts/mods/unreal_tournament/sniper/skin_animations.lua',
        'display_fov': 60,
        'draw_scale': 0.48,
        'offset': (5.3, 27.7, -10.6),
        'pivot': (90, 0, 0),
    },
    'minigun': {
        'psk': 'Weapons/SkeletalMesh/Minigun_1st.psk',
        'textures': ['units/ut/minigun/minigun_miniguntex0.png'],
        'lua': 'scripts/mods/unreal_tournament/minigun/skin_animations.lua',
        'display_fov': 60,
        'draw_scale': 0.4,
        'offset': (-1, 2, 0),
        'pivot': (500 / 65536 * 360, 0, 0),
    },
    'assault': {
        'psk': 'NewWeapons2004/SkeletalMesh/AssaultRifle.psk',
        'textures': ['units/ut/assault/assault_rifle_assaultrifletex0.png'],
        'lua': 'scripts/mods/unreal_tournament/assault/skin_animations.lua',
        'display_fov': 70,
        'draw_scale': 0.8,
        'offset': (5.5, 4, -6),
        'pivot': (0, 400 / 65536 * 360, 0),
    },
    'shield': {
        'psk': 'Weapons/SkeletalMesh/ShieldGun_1st.psk',
        'textures': ['units/ut/shield/shield_gun_shieldtex0.png'],
        'lua': 'scripts/mods/unreal_tournament/shield/skin_animations.lua',
        'display_fov': 60,
        'draw_scale': 0.4,
        'offset': (-0.7, 2, -2.7),
        'pivot': (500 / 65536 * 360, 500 / 65536 * 360, 0),
    },
    'shock2003': {
        'psk': 'Weapons/SkeletalMesh/ShockRifle_1st.psk',
        'textures': ['units/ut/shock2003/shock_rifle_shocktex0.png', 'units/ut/shock2003/shock_rifle_shocktex0.png', None],
        'lua': 'scripts/mods/unreal_tournament/shock/skin_animations_2003.lua',
        'display_fov': 70,
        'field_of_view': 86.5,
        'draw_scale': 1,
        'offset': (0, -15, -5),
        'pivot': (-800 / 65536 * 360, 1000 / 65536 * 360, 500 / 65536 * 360),
    },
}

# PlayerViewPivot as a turn in this game's axes, as weapon_skin.lua does it: yaw about up, pitch about right, roll about forward
def pivot_rotation(yaw, pitch, roll):
    return qmul(axis_angle((0, 0, 1), -math.radians(yaw)), qmul(axis_angle((1, 0, 0), math.radians(pitch)), axis_angle((0, 1, 0), -math.radians(roll))))

# ---------------------------------------------------------------- files
# Returns a texture as (width, height, pixel), where pixel(x, y) is its colour
def read_texture(path):
    width, height, channels, rows = read_png(path)

    return width, height, lambda x, y: rgb_at(rows, channels, x, y)

def idle_root_pose(lua_path):
    # (the first frame of Idle, its first bone, the root: a rotation (x, y, z, w) and a move (right, forward, up in UT units))
    text = open(lua_path).read()
    start = text.index('Idle = {')
    first = text.index('{ ', text.index('frames', start) + 10)
    values = [float(v) for v in text[first + 1:text.index('}', first)].split(',')]
    return tuple(values[0:4]), values[4:7]

# ---------------------------------------------------------------- the picture
def preview(weapon, export_dir, out_path, inspect=(0, 0, 0, 0, 0, 0), pivot_point=(0, 0, 0)):
    config = WEAPONS[weapon]
    points, wedges, faces = read_psk(os.path.join(export_dir, config['psk']))
    textures = [read_texture(os.path.join(REPO, t)) if t else None for t in config['textures']]
    rotation, move = idle_root_pose(os.path.join(REPO, config['lua']))
    pivot = pivot_rotation(*config['pivot'])
    offset_scale = 90 / config['display_fov']
    right, forward, up, roll, pitch, yaw = inspect

    # The turn of the inspect pose: yaw about up, pitch about right, roll about forward, after everything of the model's own
    turn = qmul(axis_angle((0, 0, 1), math.radians(yaw)), qmul(axis_angle((1, 0, 0), math.radians(pitch)), axis_angle((0, 1, 0), math.radians(roll))))
    total = qmul(turn, qmul(pivot, rotation))
    moved = rotate(pivot, move)
    base = [config['draw_scale'] * moved[i] + config['offset'][i] * offset_scale + (right, forward, up)[i] for i in range(3)]
    # (it turns about the point of the model that the inspect pivot says, not about its origin)
    turned_pivot = rotate(turn, pivot_point)
    base = [base[i] + pivot_point[i] - turned_pivot[i] for i in range(3)]

    # The model's (right, forward, up) is (-y, x, z) of the psk's
    view = [tuple(config['draw_scale'] * rotate(total, (-p[1], p[0], p[2]))[i] + base[i] for i in range(3)) for p in points]

    horizontal_fov = math.radians(config['field_of_view']) if 'field_of_view' in config else 2 * math.atan(math.tan(math.radians(config['display_fov']) / 2) * FIELD_OF_VIEW_FACTOR)
    focal = (WIDTH / 2) / math.tan(horizontal_fov / 2)
    screen = [(WIDTH / 2 + focal * v[0] / v[1], HEIGHT / 2 - focal * v[2] / v[1], v[1]) if v[1] > 1 else None for v in view]

    image = [[(30, 40, 30)] * WIDTH for _ in range(HEIGHT)]
    depth = [[1e9] * WIDTH for _ in range(HEIGHT)]

    for (a, b, c), material in faces:
        texture = textures[material] if material < len(textures) else None

        if not texture:
            continue

        corners = [wedges[w] for w in (a, b, c)]
        projected = [screen[w[0]] for w in corners]

        if any(p is None for p in projected):
            continue

        (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = projected
        denominator = (y1 - y2) * (x0 - x2) + (x2 - x1) * (y0 - y2)

        if abs(denominator) < 1e-9:
            continue

        # Lit by the way the face points (towards the viewer is lit)
        p0, p1, p2 = [view[w[0]] for w in corners]
        e1 = [p1[i] - p0[i] for i in range(3)]
        e2 = [p2[i] - p0[i] for i in range(3)]
        normal = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
        length = math.sqrt(sum(t * t for t in normal)) or 1
        normal = [t / length for t in normal]
        if normal[1] > 0:
            normal = [-t for t in normal]
        shade = 0.55 + 0.6 * max(0, -(normal[0] * -0.3 + normal[1] * 0.5 + normal[2] * 0.8))
        tw, th, pixel = texture

        for y in range(max(0, int(min(y0, y1, y2))), min(HEIGHT - 1, int(max(y0, y1, y2)) + 1) + 1):
            for x in range(max(0, int(min(x0, x1, x2))), min(WIDTH - 1, int(max(x0, x1, x2)) + 1) + 1):
                l0 = ((y1 - y2) * (x - x2) + (x2 - x1) * (y - y2)) / denominator
                l1 = ((y2 - y0) * (x - x2) + (x0 - x2) * (y - y2)) / denominator
                l2 = 1 - l0 - l1

                if l0 < 0 or l1 < 0 or l2 < 0:
                    continue

                z = l0 * z0 + l1 * z1 + l2 * z2

                if z >= depth[y][x]:
                    continue

                depth[y][x] = z
                u = l0 * corners[0][1] + l1 * corners[1][1] + l2 * corners[2][1]
                v = l0 * corners[0][2] + l1 * corners[1][2] + l2 * corners[2][2]
                r, g, bl = pixel(int(u * tw) % tw, int(v * th) % th)
                image[y][x] = (min(255, int(r * shade)), min(255, int(g * shade)), min(255, int(bl * shade)))

    write_png(out_path, WIDTH, HEIGHT, [b''.join(bytes(p) for p in row) for row in image], channels=3)
    print('wrote', out_path)

if __name__ == '__main__':
    weapon, export_dir, out_path = sys.argv[1:4]
    numbers = [float(v) for v in sys.argv[4:]]
    inspect = tuple(numbers[0:6]) if len(numbers) >= 6 else (0, 0, 0, 0, 0, 0)
    pivot_point = tuple(numbers[6:9]) if len(numbers) >= 9 else (0, 0, 0)
    preview(weapon, export_dir, out_path, inspect, pivot_point)
