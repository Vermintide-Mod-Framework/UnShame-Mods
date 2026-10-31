import sys, os, re, subprocess

# Makes the Workshop preview, item_preview.png, of this mod and of the extras mod: a square of a screenshot of the mod in the game
# (item_preview_background.jpg next to this script), the round UT2004 emblem over it, the largest picture in ut2004_emblem.ico next to
# this script, and the mod's name under it in Impact. Every step is ffmpeg's, which must be on the PATH.
# Usage: make_item_preview.py

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, '..', '..'))
BACKGROUND = os.path.join(HERE, 'item_preview_background.jpg')
ICON = os.path.join(HERE, 'ut2004_emblem.ico')
FONT = 'C\\:/Windows/Fonts/impact.ttf'

SIZE = 360  # pixels, as the framework's default preview
CROP_X = 840  # the left edge of the square taken from the screenshot, in its pixels: the right of it, with the weapon

# Each mod's preview: the emblem's width and top, and the lines of text (text, size, top), all in pixels. The text stays above the
# gun, which starts about 235 pixels down, so the extras mod's third line moves everything up and makes the emblem smaller.
PREVIEWS = [
    {
        'path': os.path.join(REPO, 'item_preview.png'),
        'logo_width': 180,
        'logo_y': 14,
        'lines': [('UNREAL TOURNAMENT', 38, 152), ('WEAPONS & MOVEMENT', 28, 193)],
    },
    {
        'path': os.path.join(REPO, '..', 'unreal_tournament_extras', 'item_preview.png'),
        'logo_width': 150,
        'logo_y': 8,
        'lines': [('UNREAL TOURNAMENT', 38, 116), ('WEAPONS & MOVEMENT', 28, 157), ('EXTRAS', 28, 190)],
    },
]


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

for preview in PREVIEWS:
    lines = preview['lines']
    graph = ';'.join([
        '[0:v]crop=ih:ih:%d:0,scale=%d:%d:flags=lanczos,format=rgba[background]' % (CROP_X, SIZE, SIZE),

        # The emblem, and its soft shadow down and to the right.
        '[1:%d]crop=%s,scale=%d:-1:flags=lanczos,format=rgba,split[logo][logo_shape]' % (stream, box, preview['logo_width']),
        "[logo_shape]geq=r=0:g=0:b=0:a='alpha(X,Y)',pad=iw+60:ih+60:30:30:color=black@0,gblur=sigma=8,colorchannelmixer=aa=0.9[logo_shadow]",

        # The text, over its shadow drawn twice to be darker.
        'color=black@0:s=%dx%d,format=rgba,%s,gblur=sigma=3,split[ts1][ts2]' % (SIZE, SIZE, ','.join(drawtext(*line, True) for line in lines)),
        'color=black@0:s=%dx%d,format=rgba,%s[text]' % (SIZE, SIZE, ','.join(drawtext(*line, False) for line in lines)),

        '[background][logo_shadow]overlay=(W-w)/2+3:%d:format=auto[c1]' % (preview['logo_y'] - 25),
        '[c1][logo]overlay=(W-w)/2:%d:format=auto[c2]' % preview['logo_y'],
        '[c2][ts1]overlay=0:0:format=auto[c3]',
        '[c3][ts2]overlay=0:0:format=auto[c4]',
        '[c4][text]overlay=0:0:format=auto,format=rgb24',
    ])
    path = os.path.abspath(preview['path'])

    subprocess.check_call(['ffmpeg', '-v', 'error', '-y', '-i', BACKGROUND, '-i', ICON, '-filter_complex', graph, '-frames:v', '1', path])
    print('emblem', box, '->', path)
