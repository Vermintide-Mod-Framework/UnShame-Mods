import sys, os

# Makes the materials that the converted weapons' materials derive from: copies of the SDK's standard materials with options of their
# output node turned on. Also makes the texture category that every texture of the mod is in (texture_categories/ut).
#   units/ut/weapon_standard   for first person weapons: the game's custom field of view for weapons, as its own weapons have it,
#                              which also keeps the outlines of other players from being drawn over them
#   units/ut/world_standard    for third person weapons and pickups: jitter transparency, so they fade out near the camera as the
#                              game's characters do
# Both are in decal group 3, so that the decals on the ground are not drawn on them. Each has a _transparent copy, of the SDK's
# standard_transparent.
# Usage: make_base_materials.py <SDK dir>

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SDK = sys.argv[1]

# The options of the SDK's standard_base output node (core/stingray_renderer/output_nodes/standard_base.shader_node)
HAS_FOV = '901b44ce-d128-498a-9912-32cd9635c556'
JITTER_TRANSPARENCY = '580cc6eb-3591-4c71-aa50-528af18ba160'
DEFERRED_DECALS_GROUP_3 = 'fe20cc01-4cec-4217-98a0-07220ad3add9'

MATERIALS = {
    'weapon_standard': (HAS_FOV, DEFERRED_DECALS_GROUP_3),
    'world_standard': (JITTER_TRANSPARENCY, DEFERRED_DECALS_GROUP_3),
}

def with_options(text, options):
    # The options are added at the end of the options of the output node
    lines = text.split('\n')
    node_type = lines.index('\t\t\ttype = "core/stingray_renderer/output_nodes/standard_base"')
    start = max(i for i in range(node_type) if lines[i] == '\t\t\toptions = [')
    end = lines.index('\t\t\t]', start)

    return '\n'.join(lines[:end] + ['\t\t\t\t"%s"' % option for option in options] + lines[end:])

for name, options in MATERIALS.items():
    for suffix in ('', '_transparent'):
        source = open('%s/core/stingray_renderer/shader_import/standard%s.material' % (SDK, suffix), newline='').read().replace('\r\n', '\n')
        open('%s/units/ut/%s%s.material' % (REPO, name, suffix), 'w', newline='\n').write(with_options(source, options))
        print('material', name + suffix)

# (a copy of the SDK's example mod's category for effects)
category = open(SDK + '/example_mods/endurance_badges/texture_categories/fx.texture_category', newline='').read().replace('\r\n', '\n')
open(REPO + '/texture_categories/ut.texture_category', 'w', newline='\n').write(category)
