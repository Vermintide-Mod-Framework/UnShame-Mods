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

open('%s/units/ut/fx/brighten_base.shader_node' % REPO, 'w', newline='\n').write(source)
print('wrote brighten_base.shader_node')
