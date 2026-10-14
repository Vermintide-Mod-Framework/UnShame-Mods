import sys, os

# Makes the texture of a first person muzzle flash: XGameShaders.flak_flash, the texture of the shader (flakflashfinal) that
# FlakMuzFlash1st's mesh is drawn with, or bio_flash, that of BioMuzFlash1st's, which uses the same mesh (the mesh is
# units/ut/fx/flak_flash_mesh, made by make_fx_meshes.py).
# Usage: make_flak_flash.py <scratch dir> [flak_flash | bio_flash]     (the texture is exported with UModel: umodel -export
# XGameShaders.utx, to <scratch>/umodel/out33)

SCRATCH = sys.argv[1]
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FX = REPO + '/units/ut/fx'

# (the helpers of make_fx_assets.py, without running its conversion)
source = open(os.path.join(os.path.dirname(__file__), 'make_fx_assets.py'), encoding='utf8').read()
helpers = source[source.index('def read_tga'):source.index('TEXTURE_TEMPLATE = ')]
material_start = source.index('MATERIAL_TEMPLATE = ')
templates = source[source.index('TEXTURE_TEMPLATE = '):source.index("'''\n", material_start + 25) + 4]
import struct, zlib
exec(helpers)
exec(templates)

name = sys.argv[2] if len(sys.argv) > 2 else 'flak_flash'
w, h, rows = read_tga('%s/umodel/out33/XGameShaders/Texture/%s.tga' % (SCRATCH, name))

write_png('%s/%s.png' % (FX, name), w, h, rows)
open('%s/%s.texture' % (FX, name), 'w', newline='\n').write(TEXTURE_TEMPLATE % {'name': name})
open('%s/fx_%s.material' % (FX, name), 'w', newline='\n').write(MATERIAL_TEMPLATE % {'name': name})
print('texture', name, w, h)
