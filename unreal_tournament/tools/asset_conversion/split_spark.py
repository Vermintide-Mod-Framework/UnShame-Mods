import os, sys
from formats import read_tga, write_png
from resources import texture_text, particle_material_text

# Cuts the textures of UT2004's line particles (PT_Line) into the two parts that UE2 draws from each, as Engine.dll's line drawing
# (decompiled) maps them:
#   <name>_body: the body, a quad from the tail of the line to its head, shows u 0.05 to 0.95 along it (the tail at 0.05) and v 0.01 to
#       0.49 across it, which is the top half of the texture. It is turned here so that it runs along y, the length of a beam's quad (the
#       tail at the top, where y is lowest), with v across it.
#   <name>_head: the head, a square at the front of the line, shows the whole bottom half (v 0.5 to 1), stretched to the square.
# skin_particles.lua's particles.line draws them. Each gets the material fx_<name>_body and fx_<name>_head.
# The Link Gun's sparks and the Lightning Gun's are read as they are (units/ut/fx/particle_linear, as make_weapon_fx.py's effects), not
# as srgb, which made them faint. The Link Gun's also get fx_<name>_brighten, on fx_particle_brighten_graph: the beam's sparks
# (LinkSparks) are added to the screen, and the bolt's (LinkProjSparks) are STY_Translucent, which is FB_Brighten. The Shield Gun's
# charge sparks are made opaque (an added effect leaves out the alpha, which the particle material multiplies by, as make_weapon_fx.py
# does), and also get fx_weapon_<name>, which draws with the weapon model's field of view, for the first person view.
# Usage: split_spark.py <export dir>

EXPORT = sys.argv[1]
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FX = REPO + '/units/ut/fx'

# name: the tga (its emitters)
TEXTURES = {
    'link_spark_green': 'XEffectMat/Texture/link_spark_green.tga',  # LinkSparks, LinkProjSparks, GoopSparks
    'link_spark_yellow': 'XEffectMat/Texture/link_spark_yellow.tga',  # LinkProjSparksYellow
    'shield_spark': 'XEffectMat/Texture/ShieldSpark.tga',  # ShieldSparks
    'wall_spark': 'XEffects/Texture/pcl_Spark.tga',  # WallSparks
    'blue_spark': 'XEffects/Texture/pcl_BlueSpark.tga',  # ChildBlueSparks
    'shield_charge_spark': 'XEffects/Texture/FlakTrailTex.tga',  # ShieldCharge
}

LINEAR = ('link_spark_green', 'link_spark_yellow', 'blue_spark', 'shield_charge_spark')
BRIGHTEN = ('link_spark_green', 'link_spark_yellow')
OPAQUE = ('shield_charge_spark',)
WEAPON = ('shield_charge_spark',)


def write(name, width, height, rows, source):
    linear = source in LINEAR

    if source in OPAQUE:
        rows = [bytes(255 if i % 4 == 3 else v for i, v in enumerate(row)) for row in rows]

    write_png('%s/%s.png' % (FX, name), width, height, rows)
    open('%s/%s.texture' % (FX, name), 'w', newline='\n').write(texture_text('units/ut/fx/' + name, not linear))
    open('%s/fx_%s.material' % (FX, name), 'w', newline='\n').write(particle_material_text(name, 'particle_linear' if linear else 'particle'))

    if source in BRIGHTEN:
        open('%s/fx_%s_brighten.material' % (FX, name), 'w', newline='\n').write(particle_material_text(name, 'fx_particle_brighten_graph'))

    if source in WEAPON:
        open('%s/fx_weapon_%s.material' % (FX, name), 'w', newline='\n').write(particle_material_text(
            name, 'particle_weapon_linear' if linear else 'particle_weapon'))

    print('wrote', name, width, height)


for name, tga in TEXTURES.items():
    width, height, rows = read_tga('%s/%s' % (EXPORT, tga))

    # (a row is four bytes for each pixel)
    first_x, last_x = round(0.05 * width), round(0.95 * width)
    first_y, last_y = round(0.01 * height), round(0.49 * height)
    body = [b''.join(rows[y][4 * x:4 * x + 4] for y in range(first_y, last_y)) for x in range(first_x, last_x)]

    write(name + '_body', last_y - first_y, last_x - first_x, body, name)

    head = rows[height // 2:]

    write(name + '_head', width, len(head), head, name)
