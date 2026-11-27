import struct

# Reads a compiled level of Vermintide 1 (version 0xa1).
# The fields were found by comparing Vermintide 2's keep, compiled in the game's bundle, with its source level in the
# Modding Tools Content: the two games' compiled levels have the same header and mostly the same sections.
# Names are hashes: 64 bit for resources, unit names and ids, and 32 bit (the top half) for keys, light names and set names.
#
# The header is 42 numbers. The ones read here:
#   1  units: their number. They start at 0xa8, 80 bytes each
#   3  units' script data: an offset for each unit (0 if it has none)
#   4  lights: their number, and the lights
#   14 level settings, as script data
#   15, 16  particle effects: their number and where they start
#   19, 20  volumes: their number and where they start
#   23, 24  object sets: their number, and where each one's name is
#   25, 26  the object sets of each unit and of each particle effect: a number and an offset each

VERSION = 0xa1

HEADER_UNITS = 1
HEADER_UNIT_DATA = 3
HEADER_LIGHTS = 4
HEADER_FLOW = 7
HEADER_TRIGGERS = 9
HEADER_LEVEL_SETTINGS = 14
HEADER_PARTICLES = 15
HEADER_VOLUMES = 19
HEADER_SCATTER = 30
HEADER_OBJECT_SETS = 23
HEADER_UNIT_SETS = 25
HEADER_PARTICLE_SETS = 26
HEADER_STORIES = 28

UNIT_SIZE = 80
LIGHT_SIZE = 64
PARTICLE_SIZE = 56
LIGHT_TYPES = {0: 'omni', 1: 'spot', 2: 'box'}

# Types of script data values
DATA_BOOL = 1
DATA_FLOAT = 2
DATA_STRING = 3


class Level:

    def __init__(self, data):
        self.data = data
        self.head = struct.unpack_from('<42I', data, 0)

        if self.head[0] != VERSION:
            raise ValueError('compiled level version %#x, not %#x' % (self.head[0], VERSION))

    def _u32(self, pos):
        return struct.unpack_from('<I', self.data, pos)[0]

    def _string(self, pos):
        end = self.data.index(b'\0', pos)
        return self.data[pos:end].decode()

    def units(self):
        """Each unit's id, name, type and material as hashes, and its position, rotation and scale."""
        out = []

        for k in range(self.head[HEADER_UNITS]):
            pos = 0xa8 + UNIT_SIZE * k
            unit_id, name, unit_type, material = struct.unpack_from('<4Q', self.data, pos)
            values = struct.unpack_from('<10f', self.data, pos + 32)
            out.append({
                'id': unit_id,
                'name': name,
                'type': unit_type,
                'material': material,
                'pos': list(values[0:3]),
                'rot': list(values[3:7]),
                'scl': list(values[7:10]),
            })

        return out

    def script_data(self, pos):
        """Script data: a number of entries, each a key path (32 bit hashes, or indices of arrays), a type and a value.
        Returns [(path, type, value)]; a value of a type that isn't known is returned as None."""
        out = []
        count = self._u32(pos)
        pos += 4

        for _ in range(count):
            parts = self._u32(pos)
            path = list(struct.unpack_from('<%dI' % parts, self.data, pos + 4))
            pos += 4 + 4 * parts
            value_type = self._u32(pos)
            pos += 4

            if value_type == DATA_STRING:
                length = self._u32(pos)
                value = self._string(pos + 4)
                pos += 4 + (length + 3) // 4 * 4
            elif value_type == DATA_FLOAT:
                value = struct.unpack_from('<f', self.data, pos)[0]
                pos += 4
            elif value_type == DATA_BOOL:
                value = self._u32(pos) != 0
                pos += 4
            else:
                raise ValueError('script data value of type %d at %#x' % (value_type, pos))

            out.append((path, value_type, value))

        return out

    def unit_data(self):
        """The script data of each unit that has some, by unit index."""
        table = self.head[HEADER_UNIT_DATA]
        out = {}

        for k in range(self.head[HEADER_UNITS]):
            offset = self._u32(table + 4 * k)

            if offset:
                out[k] = self.script_data(offset)

        return out

    def level_settings(self):
        return self.script_data(self.head[HEADER_LEVEL_SETTINGS])

    def lights(self):
        """The lights the level sets on its units: the unit's index, the light's name (32 bit hash) and its settings.
        Vermintide 2 keeps a box light's box where the others have their falloff and angles. The inn has no box
        lights, so where Vermintide 1 keeps the box is not known."""
        pos = self.head[HEADER_LIGHTS]
        out = []

        for k in range(self._u32(pos)):
            record = pos + 4 + LIGHT_SIZE * k
            unit, name = struct.unpack_from('<2I', self.data, record)
            f = struct.unpack_from('<9f', self.data, record + 8)
            cast_shadows, light_type = struct.unpack_from('<2I', self.data, record + 48)
            material = struct.unpack_from('<Q', self.data, record + 56)[0]

            if LIGHT_TYPES.get(light_type) not in ('omni', 'spot'):
                raise ValueError('light %d has type %d' % (k, light_type))

            out.append((unit, name, {
                'color': list(f[0:3]),
                'intensity': f[3],
                'falloff_start': f[4],
                'falloff_end': f[5],
                'spot_angle_start': f[7],
                'spot_angle_end': f[8],
                'type': LIGHT_TYPES[light_type],
                'cast_shadows': cast_shadows != 0,
                'material': material,
            }))

        return out

    def particle_effects(self):
        count, pos = self.head[HEADER_PARTICLES], self.head[HEADER_PARTICLES + 1]
        out = []

        for k in range(count):
            record = pos + PARTICLE_SIZE * k
            effect = struct.unpack_from('<Q', self.data, record)[0]
            values = struct.unpack_from('<10f', self.data, record + 8)
            spawn = self._u32(record + 48)
            out.append({
                'effect': effect,
                'pos': list(values[0:3]),
                'rot': list(values[3:7]),
                'scl': list(values[7:10]),
                'spawn': spawn != 0,
            })

        return out

    def volumes(self):
        """Each volume: its pose (a 4x4 matrix, rows are the axes and then the position), its box in its own space,
        its name (32 bit hash), its points and the triangles of its caps.
        A volume is 172 bytes, then 8 for each point and 16 for each triangle."""
        count, pos = self.head[HEADER_VOLUMES], self.head[HEADER_VOLUMES + 1]
        out = []

        for _ in range(count):
            matrix = struct.unpack_from('<16f', self.data, pos)
            box = struct.unpack_from('<6f', self.data, pos + 64)
            name, _, triangle_count, triangle_offset, point_count = struct.unpack_from('<IfIII', self.data, pos + 0x98)
            points = [struct.unpack_from('<2f', self.data, pos + 0xac + 8 * k) for k in range(point_count)]
            triangles = []

            for k in range(triangle_count):
                triangles.append(struct.unpack_from('<3I', self.data, pos + triangle_offset + 16 * k + 4))

            out.append({
                'matrix': [matrix[0:4], matrix[4:8], matrix[8:12], matrix[12:16]],
                'box_min': box[0:3],
                'box_max': box[3:6],
                'name': name,
                'points': points,
                'triangles': triangles,
            })
            pos += 0xac + 8 * point_count + 16 * triangle_count

        return out

    def object_sets(self):
        """The object sets' names, and the names (32 bit hashes) of the sets each unit and particle effect is in."""
        count, table = self.head[HEADER_OBJECT_SETS], self.head[HEADER_OBJECT_SETS + 1]
        names = [self._string(self._u32(table + 4 * k)) for k in range(count)]

        def members(header, n):
            out = []

            for k in range(n):
                set_count, offset = struct.unpack_from('<2I', self.data, self.head[header] + 8 * k)
                out.append(list(struct.unpack_from('<%dI' % set_count, self.data, offset)) if set_count else [])

            return out

        return names, members(HEADER_UNIT_SETS, self.head[HEADER_UNITS]), members(HEADER_PARTICLE_SETS, self.head[HEADER_PARTICLES])

    def _count_at(self, offset):
        """The number at the start of a section, or None when it can't be a number of things: in the rooms' levels the
        scatter header points at something else, which this reader doesn't know."""
        if not 0 < offset <= len(self.data) - 4:
            return None

        count = self._u32(offset)
        return count if count <= 100000 else None

    def counts(self):
        """How many of the things this reader leaves out the level has (None: not known)."""
        return {
            'triggers': self.head[HEADER_TRIGGERS],
            'stories': self._count_at(self.head[HEADER_STORIES]),
            'scatter': self._count_at(self.head[HEADER_SCATTER]),
            'flow bytes': self.head[HEADER_FLOW + 1] - self.head[HEADER_FLOW],
        }
