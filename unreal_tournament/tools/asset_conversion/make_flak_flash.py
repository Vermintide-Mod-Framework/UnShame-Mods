import sys, os
from formats import read_tga, write_png
from resources import texture_text, particle_material_text

# Makes the texture of a first person muzzle flash: XGameShaders.flak_flash, the texture of the shader (flakflashfinal) that
# FlakMuzFlash1st's mesh is drawn with, or bio_flash, that of BioMuzFlash1st's, which uses the same mesh (the mesh is
# units/ut/fx/flak_flash_mesh, made by make_fx_meshes.py).
# Usage: make_flak_flash.py <export dir> [flak_flash | bio_flash]

EXPORT = sys.argv[1]
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
FX = REPO + '/units/ut/fx'

name = sys.argv[2] if len(sys.argv) > 2 else 'flak_flash'
w, h, rows = read_tga('%s/XGameShaders/Texture/%s.tga' % (EXPORT, name))

write_png('%s/%s.png' % (FX, name), w, h, rows)
open('%s/%s.texture' % (FX, name), 'w', newline='\n').write(texture_text('units/ut/fx/' + name))
open('%s/fx_%s.material' % (FX, name), 'w', newline='\n').write(particle_material_text(name))
print('texture', name, w, h)
