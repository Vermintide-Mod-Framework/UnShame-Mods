import sys, os

# Makes units/ut/fx/brighten_base.shader_node: a copy of the SDK's unlit output node that blends as UT's FB_Brighten does,
# c + d * (1 - c) in each channel, where the SDK's blends by one alpha for the three channels. The materials of make_combo_materials.py
# that draw what UT draws with FB_Brighten are made with it. Its colour is the base colour times the opacity.
# Usage: make_brighten_node.py <SDK dir>

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SDK = sys.argv[1]

source = open('%s/core/stingray_renderer/output_nodes/unlit_base.shader_node' % SDK, newline='').read().replace('\r\n', '\n')

BLEND = '''				dest_blend = "blend_inv_src_alpha"
				src_blend = "blend_one"'''
assert source.count(BLEND) == 1
source = source.replace(BLEND, BLEND.replace('blend_inv_src_alpha', 'blend_inv_src_color'))

# The SDK's node skins only a mesh with 4 weights for each point; the others are commented out. The Link Gun's beam is a strip whose points
# move with one joint each (units/ut/fx/beam_strip, make_fx_meshes.py), drawn unskinned with only the 4 weights case, so the others are on.
for weights in ('3WEIGHTS', '2WEIGHTS', '1WEIGHT'):
    line = '//{ if: "num_skin_weights() == %s" define: { "macros": ["SKINNED_%s"]' % (weights[0], weights)
    assert source.count(line) == 1
    source = source.replace(line, line[2:])

open('%s/units/ut/fx/brighten_base.shader_node' % REPO, 'w', newline='\n').write(source)
print('wrote brighten_base.shader_node')
