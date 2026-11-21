import sys, os, re, subprocess

# Makes the mod's title for a 1080p video, with no background: UT2004's logo from its main menu (2K4Menus.MainMenu.2K4Logo, at the size
# of its texture) and WEAPONS & MOVEMENT under it in Impact, as in the Workshop preview (make_item_preview.py). Every step is ffmpeg's,
# which must be on the PATH.
# Usage: make_title.py <export dir> <output.png>      (the export dir is export.py's)

FONT = 'C\\:/Windows/Fonts/impact.ttf'

WIDTH = 1920
HEIGHT = 1080

# The subtitle, its size, and the space between the logo and it, in pixels
SUBTITLE = 'WEAPONS & MOVEMENT'
SUBTITLE_SIZE = 84
GAP = 20

# The shadows, as in the preview three times bigger: their blur and how far down and right they are, in pixels
LOGO_SHADOW_BLUR = 24
LOGO_SHADOW_OFFSET = (9, 15)
TEXT_SHADOW_BLUR = 9
TEXT_SHADOW_OFFSET = (6, 9)
TEXT_BORDER = 3


def visible_box(path):
    # The box around the logo's opaque pixels, so that its transparent border does not count in its size and place.
    log = subprocess.run(['ffmpeg', '-v', 'info', '-i', path, '-vf', 'alphaextract,format=gray,cropdetect=limit=8:round=2:skip=0',
                          '-f', 'null', '-'], capture_output=True, text=True).stderr
    return [int(v) for v in re.findall(r'crop=(\d+):(\d+):(\d+):(\d+)', log)[-1]]


def text_height():
    # The height of the subtitle's letters (Impact's capitals have no descenders), from where drawtext puts them in an empty picture.
    log = subprocess.run(['ffmpeg', '-v', 'info', '-f', 'lavfi', '-i', 'color=black@0:s=%dx%d,format=rgba' % (WIDTH, HEIGHT), '-vf',
                          "drawtext=fontfile='%s':text='%s':fontsize=%d:fontcolor=white:x=0:y=0,alphaextract,format=gray,"
                          "cropdetect=limit=8:round=2:skip=0" % (FONT, SUBTITLE, SUBTITLE_SIZE),
                          '-frames:v', '2', '-f', 'null', '-'], capture_output=True, text=True).stderr
    width, height, x, y = [int(v) for v in re.findall(r'crop=(\d+):(\d+):(\d+):(\d+)', log)[-1]]
    return y + height


export, path = sys.argv[1], os.path.abspath(sys.argv[2])
logo = os.path.join(export, '2K4Menus', 'Texture', '2K4Logo.tga')

w, h, x, y = visible_box(logo)

# The logo and the subtitle are centered in the picture together
top = (HEIGHT - (h + GAP + text_height())) // 2
text_top = top + h + GAP


def drawtext(color, dx, dy, border):
    outline = ':borderw=%d:bordercolor=black@0.8' % border if border else ''
    return ("drawtext=fontfile='%s':text='%s':fontsize=%d:fontcolor=%s%s:x=(w-tw)/2+%d:y=%d"
            % (FONT, SUBTITLE, SUBTITLE_SIZE, color, outline, dx, text_top + dy))


pad = LOGO_SHADOW_BLUR * 3

graph = ';'.join([
    'color=black@0:s=%dx%d,format=rgba[base]' % (WIDTH, HEIGHT),

    # The logo, and its soft shadow down and to the right.
    '[0:v]crop=%d:%d:%d:%d,format=rgba,split[logo][logo_shape]' % (w, h, x, y),
    "[logo_shape]geq=r=0:g=0:b=0:a='alpha(X,Y)',pad=iw+%d:ih+%d:%d:%d:color=black@0,gblur=sigma=%d,colorchannelmixer=aa=0.9[logo_shadow]"
    % (2 * pad, 2 * pad, pad, pad, LOGO_SHADOW_BLUR),

    # The subtitle, over its shadow drawn twice to be darker.
    'color=black@0:s=%dx%d,format=rgba,%s,gblur=sigma=%d,split[ts1][ts2]'
    % (WIDTH, HEIGHT, drawtext('black', TEXT_SHADOW_OFFSET[0], TEXT_SHADOW_OFFSET[1], 0), TEXT_SHADOW_BLUR),
    'color=black@0:s=%dx%d,format=rgba,%s[text]' % (WIDTH, HEIGHT, drawtext('white', 0, 0, TEXT_BORDER)),

    '[base][logo_shadow]overlay=(W-w)/2+%d:%d:format=auto[c1]' % (LOGO_SHADOW_OFFSET[0], top + LOGO_SHADOW_OFFSET[1] - pad),
    '[c1][logo]overlay=(W-w)/2:%d:format=auto[c2]' % top,
    '[c2][ts1]overlay=0:0:format=auto[c3]',
    '[c3][ts2]overlay=0:0:format=auto[c4]',
    '[c4][text]overlay=0:0:format=auto,format=rgba',
])

subprocess.check_call(['ffmpeg', '-v', 'error', '-y', '-i', logo, '-filter_complex', graph, '-frames:v', '1', path])
print('logo', (w, h, x, y), '->', path)
