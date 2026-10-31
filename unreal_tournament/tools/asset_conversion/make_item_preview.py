import sys, os, re, subprocess

# Makes the Workshop preview, item_preview.png, of this mod and of the extras mod. It starts from the framework's default preview (the
# template's item_preview.png, 360 by 360), covers its Vermintide logo with burlap copied from the top and bottom of the same picture,
# puts the round UT2004 emblem over it, the largest picture in ut2004_emblem.ico next to this script, and writes the mod's name under it
# in Impact. Every step is ffmpeg's, which must be on the PATH.
# Usage: make_item_preview.py <template item_preview.png>

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
ICON = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'ut2004_emblem.ico')
OUTPUTS = [os.path.join(REPO, 'item_preview.png'), os.path.join(REPO, '..', 'unreal_tournament_extras', 'item_preview.png')]
FONT = 'C\\:/Windows/Fonts/impact.ttf'

LOGO_WIDTH = 240  # pixels
LOGO_Y = 56
LINES = [('UNREAL TOURNAMENT', 39, 256), ('WEAPONS & MOVEMENT', 29, 299)]  # text, size, top

TEMPLATE = sys.argv[1]


def largest_picture(ico):
    sizes = subprocess.check_output(['ffprobe', '-v', 'error', '-show_entries', 'stream=width', '-of', 'csv=p=0', ico], text=True).split()
    return max(range(len(sizes)), key=lambda i: int(sizes[i]))


def visible_box(ico, stream):
    # The box around the emblem's opaque pixels, so that its transparent border does not count in its size and place.
    log = subprocess.run(['ffmpeg', '-v', 'info', '-i', ico, '-map', '0:%d' % stream, '-vf',
                          'loop=4:1:0,alphaextract,format=gray,cropdetect=limit=8:round=2:skip=0', '-f', 'null', '-'],
                         capture_output=True, text=True).stderr
    return re.findall(r'crop=(\d+:\d+:\d+:\d+)', log)[-1]


def drawtext(text, size, top, shadow):
    if shadow:
        return "drawtext=fontfile='%s':text='%s':fontsize=%d:fontcolor=black:x=(w-tw)/2+2:y=%d" % (FONT, text, size, top + 3)

    return ("drawtext=fontfile='%s':text='%s':fontsize=%d:fontcolor=white:borderw=1:bordercolor=black@0.8:x=(w-tw)/2:y=%d"
            % (FONT, text, size, top))


stream = largest_picture(ICON)
box = visible_box(ICON, stream)

graph = ';'.join([
    # The burlap that covers the Vermintide logo: the top 96 rows over the bottom 122, faded into each other and into the picture.
    '[0:v]format=rgba,split=3[bg][top][bottom]',
    '[top]crop=360:96:0:0[a]',
    "[bottom]crop=360:122:0:238,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='255*min(1,Y/24)'[b]",
    'color=black@0:s=360x194,format=rgba[canvas]',
    '[canvas][a]overlay=0:0:format=auto[p1]',
    "[p1][b]overlay=0:72:format=auto,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='alpha(X,Y)*min(1,min(Y/16,(H-1-Y)/16))'[patch]",
    '[bg][patch]overlay=0:62:format=auto[covered]',

    # The emblem, and its soft shadow down and to the right.
    '[1:%d]crop=%s,scale=%d:-1:flags=lanczos,format=rgba,split[logo][logo_shape]' % (stream, box, LOGO_WIDTH),
    "[logo_shape]geq=r=0:g=0:b=0:a='alpha(X,Y)',pad=iw+60:ih+60:30:30:color=black@0,gblur=sigma=8,colorchannelmixer=aa=0.9[logo_shadow]",

    # The text, over its shadow drawn twice to be darker.
    'color=black@0:s=360x360,format=rgba,%s,gblur=sigma=3,split[ts1][ts2]' % ','.join(drawtext(*line, True) for line in LINES),
    'color=black@0:s=360x360,format=rgba,%s[text]' % ','.join(drawtext(*line, False) for line in LINES),

    '[covered][logo_shadow]overlay=(W-w)/2+3:%d:format=auto[c1]' % (LOGO_Y - 25),
    '[c1][logo]overlay=(W-w)/2:%d:format=auto[c2]' % LOGO_Y,
    '[c2][ts1]overlay=0:0:format=auto[c3]',
    '[c3][ts2]overlay=0:0:format=auto[c4]',
    '[c4][text]overlay=0:0:format=auto,format=rgb24,split=%d%s' % (len(OUTPUTS), ''.join('[out%d]' % i for i in range(len(OUTPUTS)))),
])

command = ['ffmpeg', '-v', 'error', '-y', '-i', TEMPLATE, '-i', ICON, '-filter_complex', graph]

for i, path in enumerate(OUTPUTS):
    command += ['-map', '[out%d]' % i, '-frames:v', '1', os.path.abspath(path)]

subprocess.check_call(command)
print('emblem', box, '->', ', '.join(os.path.abspath(path) for path in OUTPUTS))
