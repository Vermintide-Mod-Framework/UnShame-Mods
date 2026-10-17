import os
from formats import read_png, write_png
from resources import texture_text, particle_material_text

# Splits UT2004's spark textures (link_spark_green, the Link Gun's, shield_spark, the Shield Gun's, and wall_spark, a bullet's, which
# make_fx_assets.py converts as they are) into the two things each is made of: the top half is the body of a spark, a line that fades in from the tail and ends sharply
# at the head, lying along the texture's x axis, and the bottom half is the head, a round glow. Both textures have them in the same places.
# A spark is drawn as a body along its way with a head at its front. The body is turned so that it lies along the texture's y axis, which
# is the length of a beam's quad (its tail is at the top of the texture, where y is lowest).
# Usage: split_spark.py     (run after make_fx_assets.py)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FX = REPO + '/units/ut/fx'

def pixel(rows, x, y):
    return bytes(rows[y][4 * x:4 * x + 4])


def write(name, width, height, pixels):
    rows = [b''.join(pixels[y]) for y in range(height)]

    write_png('%s/%s.png' % (FX, name), width, height, rows)
    open('%s/%s.texture' % (FX, name), 'w', newline='\n').write(texture_text('units/ut/fx/' + name))
    open('%s/fx_%s.material' % (FX, name), 'w', newline='\n').write(particle_material_text(name))
    print('wrote', name, width, height)


# The body: the rows of the top half that have the line, turned so that the tail is at the top and the head at the bottom.
BODY_ROWS = (16, 48)
# The head: the square of the bottom half that has the glow.
HEAD = (16, 80, 48, 112)

for name in ('link_spark_green', 'shield_spark', 'wall_spark'):
    width, height, _, rows = read_png('%s/%s.png' % (FX, name))

    body_height = BODY_ROWS[1] - BODY_ROWS[0]
    body = [[pixel(rows, x, BODY_ROWS[0] + column) for column in range(body_height)] for x in range(width)]

    write(name + '_body', body_height, width, body)

    head = [[pixel(rows, x, y) for x in range(HEAD[0], HEAD[2])] for y in range(HEAD[1], HEAD[3])]

    write(name + '_head', HEAD[2] - HEAD[0], HEAD[3] - HEAD[1], head)
