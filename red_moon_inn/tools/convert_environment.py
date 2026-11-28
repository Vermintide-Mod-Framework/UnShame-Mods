import argparse, os, struct

import sjson
import vt1_bundles
from vt1_bundles import name_hash, name_hash32

# Converts Vermintide 1's inn environment (environment/red_moon_inn, a compiled shading environment) to a source
# .shading_environment for Vermintide 2, made from Vermintide 2's outdoor template.
#
# A compiled shading environment is:
#   a version, the template's name (64 bit hash) and the number of variables
#   for each variable: its type, a count, its name (32 bit hash) and where its value is in a setting's values
#   the number of settings, and for each: its name (32 bit hash), the size of its values, the values, and a weight for
#   each variable (0 when the setting leaves that variable to the others)
#   then a table for the shaders, which the source doesn't have
# A resource's value is its name's 64 bit hash and 8 more bytes. An integer's value is stored as a float.
#
# Variables the template doesn't have are left out and listed in the report, unless Vermintide 2 only renamed them.
#
# Usage:
#   convert_environment.py <Vermintide 1 dir> <Content dir> <SDK dir> <vt1 strings file> <out .shading_environment> <out report>

INN_PACKAGE = 'resource_packages/levels/inn'
ENVIRONMENT = 'environment/red_moon_inn'
TEMPLATE = 'core/stingray_renderer/environments/outdoor.shading_environment_template'

# Bytes of a value of each type, and the template's name for the type
TYPES = {0: (4, 'scalar'), 1: (8, 'vector2'), 2: (12, 'vector3'), 3: (16, 'vector4'), 4: (64, 'matrix4x4'),
         6: (32, 'vector2_array'), 10: (16, 'resource'), 11: (4, 'integer')}

# Variables Vermintide 2 renamed
RENAMED = {
    'light_shaft_enabled': 'light_shafts_enabled',
    'light_shaft_settings': 'light_shafts_settings',
    'light_shaft_weigth': 'light_shafts_weigth',
}

# Textures of the inn's that are taken from Vermintide 1's bundle where Vermintide 2 doesn't have them, and the folder of the
# mod they are written to, by their resource name. The global probes give the ambient light and reflections, and the inn's
# ambient_tint is set for the inn's own. They are 8 bit cubemaps encoded as RGBM, as Vermintide 2's default probes, whose
# texture settings they get (and global_probe_rgbm_encoded is left at the template's 1).
PORTED_TEXTURES = {'global_diffuse_map', 'global_specular_map'}
TEXTURE_FOLDER = 'levels/red_moon_inn/environment/textures'
PROBE_TEXTURE = '''common = {
	input = {
		filename = "%s"
	}
	output = {
		apply_processing = false
		category = "texture_categories/cubemap_probes"
		cut_alpha_threshold = 0.5
		enable_cut_alpha_threshold = false
		format = "A8R8G8B8"
		mipmap_filter = "box"
		mipmap_filter_wrap_mode = "mirror"
		mipmap_keep_original = false
		mipmap_num_largest_steps_to_discard = 0
		mipmap_num_smallest_steps_to_discard = 0
		resident_mips = 0
		srgb = true
		streamable = false
	}
}
'''

# Settings Vermintide 2's game looks for that Vermintide 1's inn doesn't have, and the inn's setting that is copied for them.
# An end zone blends the level's environment to waystone_environment_01 when it opens.
ADDED_SETTINGS = {'waystone_environment_01': 'default'}

# The editor's own settings of each setting, which the compiled environment doesn't keep: those of Vermintide 2's keep
EDITOR_VARIABLES = {
    'shadow_slice_depth_ranges': [0, 80, 0.4],
    'sun_shadow_slice_depth_ranges': [0, 15, 0.202],
}

# Variables the editor works out from the editor variables above, which source files have in metres while Vermintide 1's
# compiled environment has them in other units: the keep's values, which go with the editor variables above
WORKED_OUT = {
    'sun_shadow_slice_depth_ranges': [0, 0.956971, 0.956971, 2.41255, 2.41255, 5.61306, 5.61306, 14.9202],
}

# Vermintide 1's fog is fog by distance, from fog_depth_range.x to .y metres, in fog_color. Vermintide 2's is volumetric: the
# fog_color is its albedo, and how thick it is comes from volumetric_extinction (per metre) and two height fogs, all 0 by
# default, which is no fog. The inn's fog is given as volumetric_extinction: Vermintide 2's fog grows exponentially where
# Vermintide 1's grows linearly, so it is made 95% thick (exp(-3)) where Vermintide 1's is all fog, 3 / fog_depth_range.y.
# The inn's height fog starts at z 0, below its floors, and is left out.
FOG_THICKNESS_AT_END = 3

# How much brighter the inn is made than Vermintide 1's exposure gives. With eye adaptation on, exposure is the grey the
# eye adapts to, so a higher one makes the whole level brighter.
EXPOSURE_SCALE = 1.15

# Variables the engine works out while running, which source files don't have
NOT_IN_SOURCE ={'sun_world_to_shadow_slice0', 'sun_world_to_shadow_slice1', 'sun_world_to_shadow_slice2', 'sun_world_to_shadow_slice3'}


def _float(x):
    """A float of the compiled environment, written with the 7 digits a 32 bit float has."""
    return float('%.7g' % x)


def read_names(content_dir, sdk_dir, strings_path):
    """{hash64: name} of textures Vermintide 2 has, and {hash32: word} and {hash64: string} from both games."""
    textures = {}

    for root, prefix in ((content_dir, ''), (os.path.join(sdk_dir, 'sdk', 'core'), 'core/')):
        for folder, _, files in os.walk(root):
            for f in files:
                if f.endswith('.texture'):
                    rel = os.path.relpath(os.path.join(folder, f), root).replace(os.sep, '/')
                    textures[name_hash(prefix + rel[:-len('.texture')])] = prefix + rel[:-len('.texture')]

    words, strings = {}, {}

    for line in open(strings_path, encoding='utf8'):
        h, s = line.rstrip('\n').split(' ', 1)
        strings[int(h, 16)] = s
        words.setdefault(int(h, 16) >> 32, s)

    return textures, words, strings


class Environment:

    def __init__(self, data):
        self.version, self.template, count = struct.unpack_from('<IQI', data, 0)
        self.variables = [struct.unpack_from('<4I', data, 16 + 16 * k) for k in range(count)]
        pos = 16 + 16 * count
        self.settings = []
        setting_count = struct.unpack_from('<I', data, pos)[0]
        pos += 4

        for _ in range(setting_count):
            name, size = struct.unpack_from('<2I', data, pos)
            values = data[pos + 8:pos + 8 + size]
            pos += 8 + size
            weight_count = struct.unpack_from('<I', data, pos)[0]
            weights = struct.unpack_from('<%df' % weight_count, data, pos + 4)
            pos += 4 + 4 * weight_count
            self.settings.append((name, values, weights))


def convert(vt1_dir, content_dir, sdk_dir, strings_path):
    data, source = vt1_bundles.newest_resource(os.path.join(vt1_dir, 'bundle'), '%016x' % name_hash(INN_PACKAGE),
                                               ENVIRONMENT, 'shading_environment')
    env = Environment(data)
    template = sjson.loads(open(os.path.join(sdk_dir, 'sdk', TEMPLATE), encoding='utf8').read())['variables']
    textures, words, strings = read_names(content_dir, sdk_dir, strings_path)
    words.update({name_hash32(n): n for n in template})

    report = ['Red Moon Inn environment: what the conversion left out', '',
              'From %s, %s in %s.' % (ENVIRONMENT, os.path.basename(source), INN_PACKAGE), '']
    left_out, missing_textures = set(), set()
    ported = {}
    settings = {}

    for name_h, values, weights in env.settings:
        setting = words.get(name_h, '%08x' % name_h)
        variables, variable_weights = {}, {}

        for (type_id, _, var_h, offset), weight in zip(env.variables, weights):
            vt1_name = words.get(var_h, '%08x' % var_h)
            name = RENAMED.get(vt1_name, vt1_name)

            if name in NOT_IN_SOURCE:
                continue

            if name == 'fog_depth_range':
                start, end = struct.unpack_from('<2f', values, offset)
                variables['volumetric_extinction'] = _float(FOG_THICKNESS_AT_END / end) if end > 0 else 0

                if weight == 0:
                    variable_weights['volumetric_extinction'] = 0

                continue

            if name not in template:
                left_out.add(vt1_name)
                continue

            size, _ = TYPES[type_id]
            raw = values[offset:offset + size]

            if type_id == 10:
                h = struct.unpack_from('<Q', raw)[0]
                value = textures.get(h)

                if value is None and name in PORTED_TEXTURES:
                    value = '%s/%s_%08x' % (TEXTURE_FOLDER, name, h >> 32)
                    ported[value] = h
                elif value is None:
                    missing_textures.add((name, strings.get(h, '%016x' % h)))
                    value = template[name].get('value', '')
            elif type_id == 11:
                value = int(round(struct.unpack('<f', raw)[0]))
            elif name in WORKED_OUT:
                value = list(WORKED_OUT[name])
            else:
                value = [_float(x) for x in struct.unpack('<%df' % (size // 4), raw)]
                value = value[0] if type_id == 0 else value

            if name == 'exposure':
                value = _float(value * EXPOSURE_SCALE)

            variables[name] = value

            if weight == 0:
                variable_weights[name] = 0

        settings[setting] = {
            'editor_variables': dict(EDITOR_VARIABLES),
            'variable_weights': variable_weights,
            'variables': variables,
        }

    for added, copied in ADDED_SETTINGS.items():
        if added not in settings:
            settings[added] = settings[copied]
            report.append('Setting %s, which Vermintide 2 looks for, is a copy of %s.' % (added, copied))

    for old, new in sorted(RENAMED.items()):
        report.append('%s is %s in Vermintide 2.' % (old, new))

    for name in sorted(WORKED_OUT):
        report.append('%s is the keep\'s: Vermintide 1 has it in other units.' % name)

    report.append('%s are left to the engine, which works them out.' % ', '.join(sorted(NOT_IN_SOURCE)))
    report.append('fog_depth_range is volumetric_extinction = %g / its end: Vermintide 2\'s fog is exponential, and is made '
                  '95%% thick where Vermintide 1\'s linear fog is all fog.' % FOG_THICKNESS_AT_END)

    report.append('')
    report.append('Variables Vermintide 2\'s template doesn\'t have (left out):')
    report.extend('  ' + n for n in sorted(left_out))
    report.append('')
    report.append('Textures Vermintide 2 doesn\'t have (the template\'s default is used):')
    report.extend('  %s: %s' % kv for kv in sorted(missing_textures))
    report.append('')
    report.append('Textures taken from Vermintide 1:')
    report.extend('  %s (%016x)' % (resource, h) for resource, h in sorted(ported.items()))

    # The newest version of each ported texture, from the inn's bundle and its patches: a DDS file as it is
    wanted = {h: resource for resource, h in ported.items()}
    dds = {}

    for path in vt1_bundles.bundle_files(os.path.join(vt1_dir, 'bundle'), '%016x' % name_hash(INN_PACKAGE)):
        for type_h, name_h, variants in vt1_bundles.resources(path):
            if type_h == name_hash('texture') and name_h in wanted and variants:
                dds[wanted[name_h]] = variants[0]

    return {'settings': settings, 'template': TEMPLATE}, dds, '\n'.join(report) + '\n'


def main():
    parser = argparse.ArgumentParser(description='Converts Vermintide 1\'s inn environment to a Vermintide 2 source environment.')
    parser.add_argument('vt1_dir')
    parser.add_argument('content_dir')
    parser.add_argument('sdk_dir')
    parser.add_argument('strings')
    parser.add_argument('environment', help='the .shading_environment to write')
    parser.add_argument('report', help='the report of what was left out, to write')
    parser.add_argument('--mod-dir', default='..', help='the mod\'s folder, where textures taken from Vermintide 1 are written')
    args = parser.parse_args()

    environment, dds, report = convert(args.vt1_dir, args.content_dir, args.sdk_dir, args.strings)
    os.makedirs(os.path.dirname(os.path.abspath(args.environment)), exist_ok=True)

    with open(args.environment, 'w', encoding='utf8', newline='\n') as f:
        f.write(sjson.dumps(environment))

    for resource, data in dds.items():
        path = os.path.join(args.mod_dir, resource)
        os.makedirs(os.path.dirname(path), exist_ok=True)

        with open(path + '.dds', 'wb') as f:
            f.write(data)

        with open(path + '.texture', 'w', encoding='utf8', newline='\n') as f:
            f.write(PROBE_TEXTURE % resource)

    with open(args.report, 'w', encoding='utf8', newline='\n') as f:
        f.write(report)

    print(report)


if __name__ == '__main__':
    main()
