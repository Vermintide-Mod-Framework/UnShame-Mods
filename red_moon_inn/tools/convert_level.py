import argparse, json, math, os, re, sys, uuid, collections

import compiled_level
import sjson
import vt1_bundles
from vt1_bundles import name_hash, name_hash32

# Converts Vermintide 1's Red Moon Inn (levels/inn/world) to a source level for Vermintide 2's editor.
# It keeps what Vermintide 2 has: units, materials and effects are kept when the Modding Tools Content or the SDK's
# core has a resource of the same name, and the rest is left out and listed in the report.
#
# The compiled level only has hashes of names. Names are found by hashing:
#   the files of the Content and of the SDK's core, for resources
#   the strings of Vermintide 1's bundles (made by vt1_strings.py), for what Vermintide 2 doesn't have, and for keys
#   the lights in the units' files, for the names of lights
#   "<unit>_<n>", the editor's names for units
#
# Usage:
#   convert_level.py <Vermintide 1 dir> <Content dir> <SDK dir> <vt1 strings file> <out world.level> <out report>

INN_PACKAGE = 'resource_packages/levels/inn'
INN_LEVEL = 'levels/inn/world'

# The converted level, as the game names it
LEVEL_RESOURCE = 'levels/red_moon_inn/red_moon_inn/world'

# Where the editor's camera starts: in the inn's main room, looking along y and 10 degrees down
EDITOR_CAMERA = {
    'FarRange': 1000,
    'InterestPointDistance': 10,
    'OrthographicPlane': {'W': 1, 'X': 0, 'Y': 0, 'Z': 0},
    'OrthographicZoom': 10,
    'Pos': {'X': 0, 'Y': -8, 'Z': 3},
    'ProjectionType': 1,
    'Rot': {'W': 0.996195, 'X': -0.087156, 'Y': 0, 'Z': 0},
    'RotationSpeed': 0.003,
    'TranslationSpeed': 1,
}

# The navigation mesh's settings: those of Vermintide 2's keep
NAV_GEN_SETTINGS = {
    'altitudeTolerance': 0.5,
    'cellSize': 20,
    'consumeAllPrototypes': True,
    'consumeGwNavGenExclusiveObjectSets': True,
    'consumeGwNavGenObjectSets': True,
    'consumeLevelReferenceSeedPoints': True,
    'consumePhysicsMesh': True,
    'consumeStingrayNavMeshTriangles': False,
    'consumeTerrain': True,
    'consumeUnitsMode': 'All units without gwnavgenexcluded script data',
    'entityHeight': 1.6,
    'entityRadius': 0.38,
    'minNavigableSurface': 0.5,
    'rasterPrecision': 0.2,
    'slopeMax': 60,
    'stepMax': 0.6,
    'terrainSamplingInMeters': 10,
}

# Used for what the inn has and Vermintide 2 doesn't, where the level needs something there
SHADING_ENVIRONMENT = 'environment/honduras_keep_02'

# The keys of level settings that Vermintide 2's levels have. Timpani is Vermintide 1's sound system, which Vermintide 2 doesn't have.
LEVEL_SETTINGS_KEYS = ['num_background_units', 'shading_environment', 'sound_environment', 'timpani_sound_environment']

# Names of the inn's resources that neither game's strings have, found by trying names under the folders the inn uses
FOUND_NAMES = [
    'units/materials/g/generic_door_01',
    'units/architecture/inn/modular_assets/inn_doorframe_3x3m_01',
    'units/architecture/inn/modular_assets/inn_plaster_wall_4x2m_01',
    'units/architecture/inn/modular_assets/inn_stone_floor_2x4m_01',
]

# Units of the inn that Vermintide 2 doesn't have, and the unit of Vermintide 2 that is used instead
SKYDOME = 'units/skydome/skydome_hdr'

# The unit that a light Vermintide 2's unit doesn't have is added as
LIGHT_UNIT = 'units/lights/light'
SUBSTITUTES = {
    'units/skydome/skydome': SKYDOME,
}

# Units Vermintide 2 has under the inn's names but made again in another shape, and the unit of Vermintide 2 that has the inn's
# shape, with the materials to give it. Vermintide 2's 4 m beams are thicker uneven logs of other lengths, so what was put
# against the inn's straight beams doesn't meet them; the wizard tower's beams are the inn's, square and 4 m long, with the
# same origin. They keep their own material: given the inn's beams' material, Vermintide 2's texture of it shows carvings.
REPLACEMENTS = {
    'units/architecture/generic/generic_wood_beam_4m_%02d' % n: ('units/architecture/wizard/wizard_wood_beam_4m_%02d' % n, {})
    for n in (1, 2, 3)
}

# Effects of Vermintide 2 that the mod has its own copy of. The fireplace's copy keeps animating and showing at any distance:
# Vermintide 2's stops animating 5 m from the camera and hides at 35 m.
EFFECT_REPLACEMENTS = {
    'fx/environment_inn_fireplace': 'levels/red_moon_inn/fx/environment_inn_fireplace',
}

# Pieces of the inn that Vermintide 2 doesn't have, and the pieces of Vermintide 2's inn put in their place: for each, its unit,
# its position in the inn piece's own space, its scale along its own axes, and how far it is turned about z, in degrees. The inn pieces of both games have their origin at a corner: x along
# the piece, y through it and z up. The sizes are from Vermintide 1's compiled meshes and Vermintide 2's .bsi files.
STAND_INS = {
    # A 4x4 m stone floor tile (0..4 along x, -4..0 along y). Vermintide 2's inn has a stone floor in its middle, 4.2 m wide.
    '6b9ad3bebc3d3260': [('units/architecture/inn/modular_assets/inn_mud_floor_4x4m_01', [2, -2, 0], [1, 1, 1])],
    # The same floor, 4 m along x and 2 m along y
    'units/architecture/inn/modular_assets/inn_stone_floor_2x4m_01': [
        ('units/architecture/inn/modular_assets/inn_mud_floor_4x4m_01', [2, -1, 0], [1, 0.5, 1])],
    # A plaster wall 2 m high: the 3 m one, lower
    'units/architecture/inn/modular_assets/inn_plaster_wall_4x2m_01': [
        ('units/architecture/inn/modular_assets/inn_plaster_wall_4x3m_01', [0, 0, 0], [1, 1, 2 / 3])],
    # A doorway 3 m wide and high in a 0.47 m wall (y -0.05..0.42): the merchant house's, which is as wide and high, in a wall
    # 0.29 m thick around y 0, moved to the middle of the inn's wall and made as thick. The inn's 4 m doorframe made smaller
    # has a door only 1.9 m high.
    'units/architecture/inn/modular_assets/inn_doorframe_3x3m_01': [
        ('units/architecture/merchant_interior/merchant_int_doorframe_3x3m_01', [0, 0.183, 0], [1, 1.6, 1])],
    # The front door, and inside it the floor (0..4 along x, -4..0 along y) with an opening 2 m wide down to the door (x 1..3,
    # y -2.2..0), where steps go down from the floor to a landing 1 m below it. Vermintide 2 has the door with the same frame for
    # the inn seen from outside: its door is 1 m higher, with steps down outside. Lowered 1.28 m, the door's top step is the
    # landing (z -1.03, to y -0.2) and its steps down are under the floor.
    # The keep's stone stairs, turned to go up away from the door, go from the landing to the floor: made 1.35 times as deep
    # so that their four steps reach y -2.2, as low as the landing is, and as wide as the opening. Their top is under the floor.
    '91f790f86abf8c11': [
        ('units/architecture/inn/modular_assets/inn_red_moon_front_door_outside_01', [0, 0, -1.28], [1, 1, 1]),
        ('units/architecture/hub/hub_stairs_02', [1.98, -0.511, -1.03], [1, 1.351, 0.971], 180),
        ('units/architecture/inn/modular_assets/inn_floor_wood_4x4m_01', [0, -2.2, 0], [1, 0.45, 1]),
        ('units/architecture/inn/modular_assets/inn_floor_wood_4x4m_01', [0, 0, 0], [0.2175, 0.55, 1]),
        ('units/architecture/inn/modular_assets/inn_floor_wood_4x4m_01', [3.13, 0, 0], [0.2175, 0.55, 1])],
}

# The editor names a placed unit after its type, with a number
MAX_UNIT_NUMBER = 3000

# Ids of the converted units, made from the hashes of the inn's ids so that they are the same on every run
ID_NAMESPACE = uuid.UUID('5e6d1c3a-3b8e-4f43-9a51-7a0d5c1f2e60')


def read_resource_names(root, prefix=''):
    """{hash: (name, {extensions})} of the files under a folder of resources."""
    names = {}

    for folder, _, files in os.walk(root):
        for f in files:
            rel = os.path.relpath(os.path.join(folder, f), root).replace(os.sep, '/')
            name, ext = os.path.splitext(prefix + rel)
            entry = names.setdefault(name_hash(name), (name, set()))
            entry[1].add(ext[1:])

    return names


def read_strings(path):
    """{hash64: string} and {hash32: string} of the strings of Vermintide 1's bundles."""
    by64, by32 = {}, {}

    for line in open(path, encoding='utf8'):
        h, s = line.rstrip('\n').split(' ', 1)
        h = int(h, 16)
        by64[h] = s
        by32.setdefault(h >> 32, s)

    return by64, by32


def read_words(root, by32):
    """Adds the words of the Lua files under a folder to {hash32: word}: the keys of script data and level settings are in them."""
    for folder, _, files in os.walk(root):
        for f in files:
            if f.endswith('.lua'):
                text = open(os.path.join(folder, f), encoding='utf8', errors='replace').read()

                for word in set(re.findall(r'[A-Za-z_][A-Za-z0-9_]{2,}', text)):
                    by32.setdefault(name_hash32(word), word)


def numbered_variants(names, exts):
    """{hash: name} of the names of these kinds with their last number changed: Vermintide 1 has units, materials and
    effects that Vermintide 2 has others of the same series of."""
    out = {}

    for name, kinds in names.values():
        if not kinds & exts:
            continue

        m = re.fullmatch(r'(.*?)(\d+)', name)

        if not m:
            continue

        stem, digits = m.groups()

        for n in range(100):
            variant = '%s%0*d' % (stem, len(digits), n)
            out.setdefault(name_hash(variant), variant)

    return out


class Converter:

    def __init__(self, vt1_dir, content_dir, sdk_dir, strings_path, vt1_level=INN_LEVEL, level_resource=LEVEL_RESOURCE):
        """vt1_level is the level of Vermintide 1's inn bundle to convert, level_resource the name of the converted level."""
        self.content_dir = content_dir
        self.vt1_level = vt1_level
        self.level_resource = level_resource
        self.resources = read_resource_names(content_dir)
        self.resources.update(read_resource_names(os.path.join(sdk_dir, 'sdk', 'core'), 'core/'))
        self.vt1_names, self.words = read_strings(strings_path)
        read_words(os.path.join(content_dir, 'scripts'), self.words)
        read_words(os.path.join(sdk_dir, 'sdk', 'core'), self.words)

        for key in LEVEL_SETTINGS_KEYS:
            self.words[name_hash32(key)] = key

        # Names for what Vermintide 2 doesn't have, for the report
        for h, name in numbered_variants(self.resources, {'unit', 'material', 'particles'}).items():
            self.vt1_names.setdefault(h, name)

        for name in FOUND_NAMES:
            self.vt1_names[name_hash(name)] = name

        self.unit_files = {}

        data, self.source = vt1_bundles.newest_resource(os.path.join(vt1_dir, 'bundle'), '%016x' % name_hash(INN_PACKAGE),
                                                        vt1_level, 'level')
        self.level = compiled_level.Level(data)

        # What is left out, for the report: {kind: Counter(name)}
        self.missing = collections.defaultdict(collections.Counter)
        self.substituted = collections.Counter()
        self.where = collections.defaultdict(list)
        self.renamed_lights = collections.Counter()
        self.light_units = collections.Counter()
        self.lights_off = collections.Counter()
        self.stood_in = collections.Counter()
        self.stand_in_ids = set()
        self.notes = []

    # Names

    def resource(self, h, ext):
        """The name of a resource of Vermintide 2 of this hash and kind, or None."""
        entry = self.resources.get(h)
        return entry[0] if entry and ext in entry[1] else None

    def vt1_name(self, h):
        return self.vt1_names.get(h, '%016x' % h)

    def word(self, h):
        return self.words.get(h)

    def unit_file(self, unit_type):
        if unit_type not in self.unit_files:
            path = os.path.join(self.content_dir, unit_type + '.unit')

            if not os.path.exists(path):
                path = None

            self.unit_files[unit_type] = sjson.loads(open(path, encoding='utf8').read()) if path else {}

        return self.unit_files[unit_type]

    def unit_names(self, units, types):
        """The units' names: the editor's "<unit>_<n>", or a name of Vermintide 1's strings, or one made here."""
        wanted = collections.defaultdict(set)

        for k, u in enumerate(units):
            wanted[types[k]].add(u['name'])

        found = {}

        for unit_type, hashes in wanted.items():
            if unit_type is None:
                continue

            base = unit_type.rsplit('/', 1)[-1]

            for n in range(MAX_UNIT_NUMBER):
                guess = base if n == 0 else '%s_%d' % (base, n)
                h = name_hash(guess)

                if h in hashes:
                    found[h] = guess
                    hashes.discard(h)

                    if not hashes:
                        break

        names, used, made = [], set(), 0

        for k, u in enumerate(units):
            name = found.get(u['name']) or self.vt1_names.get(u['name'])

            if name is None or name in used:
                base = (types[k] or 'unit').rsplit('/', 1)[-1]
                name = '%s_vt1_%d' % (base, k)
                made += 1

            used.add(name)
            names.append(name)

        if made:
            self.notes.append('%d units have a name made here: their names in Vermintide 1 are not found from their hashes.' % made)

        return names

    def data_key(self, path):
        """The key of a script data path, as the editor writes it: parts joined with dots, and indices of arrays in [ ]."""
        key = ''

        for part in path:
            word = self.word(part)

            if word is None and part < 0x10000:
                key += '[%d]' % part
            elif word is None:
                return None
            else:
                key += ('.' if key else '') + word

        return key

    # Sections

    def units(self):
        units = self.level.units()
        types = [self.resource(u['type'], 'unit') for u in units]
        extra = []

        for k, u in enumerate(units):
            substitute = SUBSTITUTES.get(self.vt1_name(u['type']))

            if types[k] is None and substitute:
                types[k] = substitute
                self.substituted[(self.vt1_name(u['type']), substitute)] += 1

            stand_ins = STAND_INS.get(self.vt1_name(u['type']))

            if types[k] is None and stand_ins:
                # The first stand-in takes the inn piece's place in the level, the others are added after the inn's units.
                # All of them are placed from where the inn piece is.
                piece = dict(u)

                for n, (unit_type, offset, scale, *turn) in enumerate(stand_ins):
                    placed = {
                        'id': piece['id'] if n == 0 else name_hash('%016x/%d' % (piece['id'], n)),
                        'pos': [p + d for p, d in zip(piece['pos'], rotate(piece['rot'], [o * s for o, s in zip(offset, piece['scl'])]))],
                        'rot': multiply(piece['rot'], z_rotation(turn[0] if turn else 0)),
                        'scl': [a * b for a, b in zip(piece['scl'], scale)],
                    }
                    self.stood_in[(self.vt1_name(u['type']), unit_type)] += 1
                    self.stand_in_ids.add(str(uuid.uuid5(ID_NAMESPACE, '%016x' % placed['id'])))

                    if n == 0:
                        types[k] = unit_type
                        u.update(placed)
                    else:
                        extra.append((placed, unit_type))

        names = self.unit_names(units, types)
        unit_data = self.level.unit_data()
        set_names, unit_sets, _ = self.level.object_sets()
        set_names = {name_hash32(n): n for n in set_names}
        out, index = [], {}

        for k, u in enumerate(units):
            if types[k] is None:
                name = self.vt1_name(u['type'])
                self.missing['unit'][name] += 1
                sets = ', '.join(set_names[s] for s in unit_sets[k])
                self.where[name].append('at %s%s' % (' '.join('%.2f' % v for v in u['pos']), ', in ' + sets if sets else ''))
                continue

            # Vermintide 1 gives most units a material, which is one of the unit's own: in Vermintide 2 a unit's material
            # replaces all of its materials, and only the skydome has one, which the editor sets from its settings
            material = types[k] if types[k] == SKYDOME else ''

            data = {}
            for path, _, value in unit_data.get(k, []):
                key = self.data_key(path)

                if key is None:
                    self.missing['script data key'][' '.join('%08x' % p for p in path)] += 1
                else:
                    data[key] = value

            index[k] = len(out)
            out.append({
                'cameras': {},
                'data': data,
                'id': str(uuid.uuid5(ID_NAMESPACE, '%016x' % u['id'])),
                'lights': {},
                'material': material,
                'materials': {},
                'name': names[k],
                'pos': u['pos'],
                'rot': u['rot'],
                'scl': u['scl'],
                'type': types[k],
            })

        used = {u['name'] for u in out}

        for n, (placed, unit_type) in enumerate(extra):
            name = '%s_stand_in_%d' % (unit_type.rsplit('/', 1)[-1], n + 1)

            while name in used:
                name += '_'

            used.add(name)
            out.append({
                'cameras': {},
                'data': {},
                'id': str(uuid.uuid5(ID_NAMESPACE, '%016x' % placed['id'])),
                'lights': {},
                'material': '',
                'materials': {},
                'name': name,
                'pos': placed['pos'],
                'rot': placed['rot'],
                'scl': placed['scl'],
                'type': unit_type,
            })

        self.add_lights(out, index)
        return self.without_duplicates(out, index)

    def without_duplicates(self, units, index):
        """The units without the inn's exact copies of others: the same unit in the same place with the same settings.
        The editor's level check reports them as duplicate units."""
        kept, first, out_of = [], {}, {}

        for k, u in enumerate(units):
            key = json.dumps([u['type'], [round(v, 4) for v in u['pos'] + u['rot'] + u['scl']], u['data'], u['lights']], sort_keys=True)

            if key in first:
                self.notes.append('%s is a copy of %s, in the same place: it is left out.' % (u['name'], kept[first[key]]['name']))
                out_of[k] = first[key]
                continue

            first[key] = len(kept)
            out_of[k] = len(kept)
            kept.append(u)

        return kept, {vt1: out_of[k] for vt1, k in index.items()}

    def add_lights(self, units, index):
        lights = self.level.lights()
        lights_on = collections.Counter(unit_index for unit_index, _, _ in lights)

        for unit_index, name_h, light in lights:
            if unit_index not in index:
                continue

            unit = units[index[unit_index]]
            defaults = self.unit_file(unit['type']).get('lights', {})
            names = {name_hash32(n): n for n in defaults}
            name = names.get(name_h)
            vt1_name = self.word(name_h) or '%08x' % name_h

            # Vermintide 2 renamed the light of some units. When the unit has one light and the inn sets one light on it,
            # the unit's light gets that light's settings.
            if name is None and len(defaults) == 1 and lights_on[unit_index] == 1:
                name = next(iter(defaults))
                self.renamed_lights[(unit['type'], vt1_name, name)] += 1

            # A light that Vermintide 2's unit doesn't have is added as a light unit, where the unit is. A light the inn
            # turns off (intensity 0) is left out.
            if name is None and light['intensity'] == 0:
                self.lights_off[(unit['type'], vt1_name)] += 1
                continue

            if name is None:
                units.append(self.light_unit(unit, vt1_name, light))
                self.light_units[(unit['type'], vt1_name)] += 1
                continue

            unit['lights'][name] = self.light_settings(defaults[name], light)

    def light_unit(self, owner, vt1_name, light):
        """A light unit with a light the inn sets on a unit that Vermintide 2's unit doesn't have, at the unit's place."""
        unit_id = str(uuid.uuid5(ID_NAMESPACE, 'light %s %s' % (owner['id'], vt1_name)))
        self.stand_in_ids.add(unit_id)
        light_name = next(iter(self.unit_file(LIGHT_UNIT)['lights']))

        return {
            'cameras': {},
            'data': {},
            'id': unit_id,
            'lights': {light_name: self.light_settings(self.unit_file(LIGHT_UNIT)['lights'][light_name], light)},
            'material': '',
            'materials': {},
            'name': '%s_%s' % (owner['name'], vt1_name),
            'pos': list(owner['pos']),
            'rot': list(owner['rot']),
            'scl': [1, 1, 1],
            'type': LIGHT_UNIT,
        }

    def light_settings(self, default, light):
        """A light's settings: the unit file's, with those the inn sets."""
        material = ''

        if light['material']:
            material = self.resource(light['material'], 'material')

            if material is None:
                self.missing['material of a light'][self.vt1_name(light['material'])] += 1
                material = ''

        settings = dict(default)
        settings.pop('node', None)
        settings.update({k: v for k, v in light.items() if k != 'material'})
        settings['material'] = material
        settings.setdefault('box_min', [-10, 0, -10])
        settings.setdefault('box_max', [10, 10, 10])
        settings.setdefault('falloff_exponent', 0)

        # Vermintide 1's lights have no volumetric intensity: it has no volumetric fog
        settings['volumetric_intensity'] = 0
        return settings

    def particle_effects(self):
        out, index = [], {}

        for k, p in enumerate(self.level.particle_effects()):
            effect = self.resource(p['effect'], 'particles')

            if effect is None:
                name = self.vt1_name(p['effect'])
                self.missing['particle effect'][name] += 1
                self.where[name].append('at %s' % ' '.join('%.2f' % v for v in p['pos']))
                continue

            index[k] = len(out)
            out.append({
                'effect': EFFECT_REPLACEMENTS.get(effect, effect),
                'id': str(uuid.uuid5(ID_NAMESPACE, 'particle %d' % k)),
                'pos': p['pos'],
                'rot': p['rot'],
                'scl': p['scl'],
                'spawn': p['spawn'],
            })

        return out, index

    def volumes(self):
        out = []

        for k, v in enumerate(self.level.volumes()):
            name = self.word(v['name'])

            if name is None:
                name = 'volume_vt1_%d' % k
                self.missing['volume name'][('%08x' % v['name'])] += 1

            pos, rot, scl = matrix_pose(v['matrix'])
            out.append({
                'bottom': v['box_min'][2],
                'cap_triangulation': [i + 1 for t in v['triangles'] for i in t],
                'id': str(uuid.uuid5(ID_NAMESPACE, 'volume %d' % k)),
                'name': name,
                'points': [[x, y, 0] for x, y in v['points']],
                'pos': pos,
                'rot': rot,
                'scl': scl,
                'top': v['box_max'][2],
                'type': 'default',
            })

        return out

    def object_sets(self, units, unit_index, effects, effect_index):
        names, unit_sets, effect_sets = self.level.object_sets()
        by_hash = {name_hash32(n): n for n in names}
        out = {n: [] for n in names}

        for k, sets in enumerate(unit_sets):
            for s in sets:
                # A unit left out as a copy is in its sets as the unit it is a copy of
                if k in unit_index and units[unit_index[k]]['id'] not in out[by_hash[s]]:
                    out[by_hash[s]].append(units[unit_index[k]]['id'])

        for k, sets in enumerate(effect_sets):
            for s in sets:
                if k in effect_index:
                    out[by_hash[s]].append(effects[effect_index[k]]['id'])

        return out

    def level_settings(self):
        settings = {}

        for path, _, value in self.level.level_settings():
            key = self.data_key(path)

            if key == 'num_background_units':
                settings[key] = int(value)
            elif key == 'shading_environment':
                if self.resource(name_hash(value), 'shading_environment'):
                    settings[key] = value
                else:
                    self.missing['shading environment'][value] += 1
                    self.notes.append('The shading environment %s is not in Vermintide 2: %s is used.' % (value, SHADING_ENVIRONMENT))
                    settings[key] = SHADING_ENVIRONMENT
            else:
                self.notes.append('Level setting %s = "%s" is left out.' % (key or ' '.join('%08x' % p for p in path), value))

        return settings

    def convert(self):
        units, unit_index = self.units()
        effects, effect_index = self.particle_effects()

        level = {
            'flow': {'nodes': []},
            'level_references': [],
            'level_settings': self.level_settings(),
            'object_sets': self.object_sets(units, unit_index, effects, effect_index),
            'overrides': [],
            'particle_effects': effects,
            'prototypes': [],
            'replays': [],
            'scatter': [],
            'sounds': [],
            'splines': [],
            'stories': [],
            'triggers': [],
            'units': units,
            'volumes': self.volumes(),
        }
        level['editor_metadata'] = editor_metadata(level, self.level_resource)

        for old, (new, _) in sorted(REPLACEMENTS.items()):
            self.notes.append('%s has another shape in Vermintide 2: %s, which has the inn\'s, is used.' % (old, new))

        replace_units(level)
        self.notes.append('Units keep their own materials: the material Vermintide 1 gives %d units is one of their own, '
                          'or the one of their Vermintide 1 version.' % sum(1 for u in self.level.units() if u['material']))

        for what, count in self.level.counts().items():
            if count is None:
                self.notes.append('Not converted: %s (how many is not known).' % what)
            elif count:
                self.notes.append('Not converted: %s (%d).' % (what, count))

        return level

    def report(self, level):
        lines = ['%s: what the conversion left out' % self.level_resource, '',
                 'From %s, %s in %s.' % (self.vt1_level, os.path.basename(self.source), INN_PACKAGE),
                 'Kept: %d of %d units, %d of %d particle effects, %d volumes, %d object sets.' % (
                     len(level['units']), self.level.head[compiled_level.HEADER_UNITS],
                     len(level['particle_effects']), self.level.head[compiled_level.HEADER_PARTICLES],
                     len(level['volumes']), len(level['object_sets'])),
                 '']

        for note in self.notes:
            lines.append(note)

        for (vt1, vt2), count in sorted(self.substituted.items()):
            lines.append('%s is not in Vermintide 2: %s is used%s.' % (vt1, vt2, ' (x%d)' % count if count > 1 else ''))

        for (vt1, vt2), count in sorted(self.stood_in.items()):
            lines.append('%s is not in Vermintide 2: %s stands in for it%s.' % (vt1, vt2, ' (x%d)' % count if count > 1 else ''))

        for (unit_type, vt1, vt2), count in sorted(self.renamed_lights.items()):
            lines.append('%s calls its light %s in Vermintide 2, not %s: the settings are given to %s%s.' % (
                unit_type, vt2, vt1, vt2, ' (x%d)' % count if count > 1 else ''))

        for (unit_type, vt1), count in sorted(self.light_units.items()):
            lines.append('%s has no light %s in Vermintide 2: a %s with its settings is added where the unit is%s.' % (
                unit_type, vt1, LIGHT_UNIT, ' (x%d)' % count if count > 1 else ''))

        for (unit_type, vt1), count in sorted(self.lights_off.items()):
            lines.append('%s has no light %s in Vermintide 2: the inn turns it off, so it is left out%s.' % (
                unit_type, vt1, ' (x%d)' % count if count > 1 else ''))

        for kind in sorted(self.missing):
            lines.append('')
            lines.append('Not in Vermintide 2 (%s):' % kind)

            for name, count in sorted(self.missing[kind].items()):
                lines.append('  %s%s' % (name, ' (x%d)' % count if count > 1 else ''))

                if kind in ('unit', 'particle effect'):
                    lines.extend('    ' + w for w in self.where[name])

        return '\n'.join(lines) + '\n'


def replace_units(level):
    """Gives the units of REPLACEMENTS their replacement, in what the game reads and in what the editor reads, and gives
    replacements that are in the level already the materials REPLACEMENTS gives them. Returns how many units were changed."""
    slots_of = {new: slots for new, slots in REPLACEMENTS.values()}
    changed = 0

    for u in level['units']:
        before = (u['type'], u['materials'])

        if u['type'] in REPLACEMENTS:
            u['type'] = REPLACEMENTS[u['type']][0]

        if u['type'] in slots_of:
            u['materials'] = dict(slots_of[u['type']])

        if (u['type'], u['materials']) != before:
            changed += 1

    for u in level['editor_metadata']['Units']:
        if u['Type'] in REPLACEMENTS:
            u['Type'] = REPLACEMENTS[u['Type']][0]
            u['Path'] = u['Type']

        if u['Type'] in slots_of:
            u['MaterialSlots'] = dict(slots_of[u['Type']])

    return changed


def _vector(v):
    return {'X': v[0], 'Y': v[1], 'Z': v[2]}


def _rotation(q):
    return {'X': q[0], 'Y': q[1], 'Z': q[2], 'W': q[3]}


def _placed(item, layer, path):
    """What the editor keeps of anything placed in the level."""
    return {
        'Id': item['id'],
        'Layer': layer,
        'Path': path,
        'Pivot': _vector([0, 0, 0]),
        'Pos': _vector(item['pos']),
        'Rot': _rotation(item['rot']),
        'Scl': _vector(item['scl']),
    }


def _editor_light(light):
    """A light as the editor keeps it: its color in 0 to 255, its angles in degrees and its material as MaterialResource."""
    return {
        'BoxMax': _vector(light['box_max']),
        'BoxMin': _vector(light['box_min']),
        'CastShadows': light['cast_shadows'],
        'Color': {'R': round(light['color'][0] * 255), 'G': round(light['color'][1] * 255), 'B': round(light['color'][2] * 255), 'A': 255},
        'FalloffEnd': light['falloff_end'],
        'FalloffExponent': light['falloff_exponent'],
        'FalloffStart': light['falloff_start'],
        'Intensity': light['intensity'],
        'Material': '',
        'MaterialResource': light['material'],
        'SpotAngleEnd': math.degrees(light['spot_angle_end']),
        'SpotAngleStart': math.degrees(light['spot_angle_start']),
        'Type': light['type'],
        'VolumetricIntensity': light['volumetric_intensity'],
    }


def editor_metadata(level, level_resource=LEVEL_RESOURCE):
    """What the editor reads the level from. The rest of the level is what the game reads, and the editor writes it from this
    when the level is saved. The editor has the skydome in its settings, not with the units."""
    units = []

    for u in level['units']:
        if u['type'] == SKYDOME:
            continue

        item = _placed(u, 'Default', u['type'])
        item.update({
            'Cameras': {},
            'Lights': {name: _editor_light(light) for name, light in u['lights'].items()},
            'MaterialSlots': dict(u['materials']),
            'Name': u['name'],
            'OverridePoses': {},
            'ScriptData': dict(u['data']),
            'StoryOverridePoses': {},
            'Type': u['type'],
        })
        units.append(item)

    effects = []

    for k, p in enumerate(level['particle_effects']):
        item = _placed(p, 'fx', 'particleeffect')
        item.update({'Effect': p['effect'], 'Name': 'particle_effect_%d' % (k + 1), 'Spawn': p['spawn']})
        effects.append(item)

    volumes = []

    for v in level['volumes']:
        item = _placed(v, 'volumes', 'volume')
        item.update({
            'Bottom': v['bottom'],
            'CapTriangulation': v['cap_triangulation'],
            'Name': v['name'],
            'Points': [_vector(p) for p in v['points']],
            'Top': v['top'],
            'Type': v['type'],
        })
        volumes.append(item)

    nav_data = 'navigation\\' + level_resource.replace('/', '\\')

    return {
        'Flow': {'Connections': [], 'Groups': [], 'Nodes': []},
        'Groups': [],
        'GwNavGenSettings': dict(NAV_GEN_SETTINGS, generatedNavDataPath=nav_data),
        'Layers': ['Default', 'fx', 'volumes'],
        'LevelObjectSets': {
            'NestedSetNamesBySetName': {},
            'ObjectIdsBySetName': level['object_sets'],
            'VisibleSetNames': sorted(level['object_sets']),
        },
        'LevelReferences': [],
        'LightBakeSettings': {'ExcludedObjectSets': [], 'Layers': []},
        'LuaPluginObjects': [],
        'Notes': [],
        'Overrides': [],
        'ParticleEffects': effects,
        'PositionMarkers': [],
        'Prototypes': [],
        'Replays': [],
        'Scatter': {'Dirty': False, 'PoolSettings': {}, 'ScatterData': {}},
        'Settings': {
            'FrozenLayers': [],
            'HiddenLayers': [],
            'HiddenObjects': [],
            'LastHiddenObjects': [],
            'ShadingEnvironment': level['level_settings'].get('shading_environment', SHADING_ENVIRONMENT),
            'SkydomeUnit': SKYDOME,
        },
        'Sounds': [],
        'Splines': [],
        'Stories': [],
        'Transients': {'Camera': dict(EDITOR_CAMERA)},
        'Triggers': [],
        'Units': units,
        'Volumes': volumes,
    }


def rotate(q, v):
    """A vector turned by a rotation (x, y, z, w)."""
    x, y, z, w = q
    # v + 2w (q x v) + 2 q x (q x v)
    cx, cy, cz = y * v[2] - z * v[1], z * v[0] - x * v[2], x * v[1] - y * v[0]
    dx, dy, dz = y * cz - z * cy, z * cx - x * cz, x * cy - y * cx
    return [v[0] + 2 * (w * cx + dx), v[1] + 2 * (w * cy + dy), v[2] + 2 * (w * cz + dz)]


def multiply(a, b):
    """The rotation b, then a (x, y, z, w)."""
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return [aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz]


def z_rotation(degrees):
    half = math.radians(degrees) / 2
    return [0, 0, math.sin(half), math.cos(half)]


def matrix_pose(m):
    """Position, rotation (x, y, z, w) and scale of a matrix whose rows are the axes and then the position."""
    axes = [m[i][0:3] for i in range(3)]
    scl = [math.sqrt(sum(c * c for c in a)) for a in axes]
    r = [[axes[i][j] / scl[i] for j in range(3)] for i in range(3)]

    # The rows are the axes, so the rotation matrix's columns are r's rows
    m00, m01, m02 = r[0][0], r[1][0], r[2][0]
    m10, m11, m12 = r[0][1], r[1][1], r[2][1]
    m20, m21, m22 = r[0][2], r[1][2], r[2][2]
    trace = m00 + m11 + m22

    if trace > 0:
        s = math.sqrt(trace + 1) * 2
        q = [(m21 - m12) / s, (m02 - m20) / s, (m10 - m01) / s, s / 4]
    elif m00 > m11 and m00 > m22:
        s = math.sqrt(1 + m00 - m11 - m22) * 2
        q = [s / 4, (m01 + m10) / s, (m02 + m20) / s, (m21 - m12) / s]
    elif m11 > m22:
        s = math.sqrt(1 + m11 - m00 - m22) * 2
        q = [(m01 + m10) / s, s / 4, (m12 + m21) / s, (m02 - m20) / s]
    else:
        s = math.sqrt(1 + m22 - m00 - m11) * 2
        q = [(m02 + m20) / s, (m12 + m21) / s, s / 4, (m10 - m01) / s]

    return list(m[3][0:3]), q, scl


def main():
    parser = argparse.ArgumentParser(description='Converts Vermintide 1\'s Red Moon Inn to a Vermintide 2 source level.')
    parser.add_argument('vt1_dir', help='Vermintide 1\'s folder (the one with the bundle folder)')
    parser.add_argument('content_dir', help='the Modding Tools Content\'s content folder')
    parser.add_argument('sdk_dir', help='the Vermintide 2 SDK\'s folder')
    parser.add_argument('strings', help='the strings of Vermintide 1\'s bundles, made by vt1_strings.py')
    parser.add_argument('level', help='the world.level to write')
    parser.add_argument('report', help='the report of what was left out, to write')
    parser.add_argument('--vt1-level', default=INN_LEVEL, help='the level of Vermintide 1\'s inn bundle to convert')
    parser.add_argument('--level-resource', default=LEVEL_RESOURCE, help='the name of the converted level')
    args = parser.parse_args()

    converter = Converter(args.vt1_dir, args.content_dir, args.sdk_dir, args.strings, args.vt1_level, args.level_resource)
    level = converter.convert()

    with open(args.level, 'w', encoding='utf8', newline='\n') as f:
        f.write(sjson.dumps(level))

    report = converter.report(level)

    with open(args.report, 'w', encoding='utf8', newline='\n') as f:
        f.write(report)

    print(report)


if __name__ == '__main__':
    main()
