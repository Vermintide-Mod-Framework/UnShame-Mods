import sys, os, re, subprocess

# Makes the Workshop preview, item_preview.png, of this mod and of the extras mod: a square of a screenshot of the mod in the game
# (item_preview_background.jpg next to this script), the round UT2004 emblem over it, the largest picture in ut2004_emblem.ico next to
# this script, and the mod's name under it in Impact. Every step is ffmpeg's, which must be on the PATH.
# Usage: make_item_preview.py

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
OUTPUTS = [os.path.join(REPO, 'item_preview.png'), os.path.join(REPO, '..', 'unreal_tournament_extras', 'item_preview.png')]
BACKGROUND = os.path.join(HERE, 'item_preview_background.jpg')
ICON = os.path.join(HERE, 'ut2004_emblem.ico')
FONT = 'C\\:/Windows/Fonts/impact.ttf'

SIZE = 360  # pixels, as the framework's default preview
CROP_X = 840  # the left edge of the square taken from the screenshot, in its pixels: the right of it, with the weapon
LOGO_WIDTH = 220
LOGO_Y = 14
LINES = [('UNREAL TOURNAMENT', 38, 172), ('WEAPONS & MOVEMENT', 28, 213)]  # text, size, top


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
    '[0:v]crop=ih:ih:%d:0,scale=%d:%d:flags=lanczos,format=rgba[background]' % (CROP_X, SIZE, SIZE),

    # The emblem, and its soft shadow down and to the right.
    '[1:%d]crop=%s,scale=%d:-1:flags=lanczos,format=rgba,split[logo][logo_shape]' % (stream, box, LOGO_WIDTH),
    "[logo_shape]geq=r=0:g=0:b=0:a='alpha(X,Y)',pad=iw+60:ih+60:30:30:color=black@0,gblur=sigma=8,colorchannelmixer=aa=0.9[logo_shadow]",

    # The text, over its shadow drawn twice to be darker.
    'color=black@0:s=%dx%d,format=rgba,%s,gblur=sigma=3,split[ts1][ts2]' % (SIZE, SIZE, ','.join(drawtext(*line, True) for line in LINES)),
    'color=black@0:s=%dx%d,format=rgba,%s[text]' % (SIZE, SIZE, ','.join(drawtext(*line, False) for line in LINES)),

    '[background][logo_shadow]overlay=(W-w)/2+3:%d:format=auto[c1]' % (LOGO_Y - 25),
    '[c1][logo]overlay=(W-w)/2:%d:format=auto[c2]' % LOGO_Y,
    '[c2][ts1]overlay=0:0:format=auto[c3]',
    '[c3][ts2]overlay=0:0:format=auto[c4]',
    '[c4][text]overlay=0:0:format=auto,format=rgb24,split=%d%s' % (len(OUTPUTS), ''.join('[out%d]' % i for i in range(len(OUTPUTS)))),
])

command = ['ffmpeg', '-v', 'error', '-y', '-i', BACKGROUND, '-i', ICON, '-filter_complex', graph]

for i, path in enumerate(OUTPUTS):
    command += ['-map', '[out%d]' % i, '-frames:v', '1', os.path.abspath(path)]

subprocess.check_call(command)
print('emblem', box, '->', ', '.join(os.path.abspath(path) for path in OUTPUTS))
