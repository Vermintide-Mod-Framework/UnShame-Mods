import argparse

import convert_level
import sjson

# Adds the stand-ins for the inn's missing pieces (STAND_INS in convert_level.py) to a level that has been worked on in the
# editor, and changes nothing else in it. A stand-in has the id the conversion gives it, so one already in the level is
# not added again.
#
# Usage:
#   add_stand_ins.py <Vermintide 1 dir> <Content dir> <SDK dir> <vt1 strings file> <world.level> <out report>


def main():
    parser = argparse.ArgumentParser(description='Adds stand-ins for the inn\'s missing pieces to a level worked on in the editor.')
    parser.add_argument('vt1_dir')
    parser.add_argument('content_dir')
    parser.add_argument('sdk_dir')
    parser.add_argument('strings')
    parser.add_argument('level', help='the world.level to add them to')
    parser.add_argument('report', help='the report of what the conversion leaves out, to write')
    args = parser.parse_args()

    converter = convert_level.Converter(args.vt1_dir, args.content_dir, args.sdk_dir, args.strings)
    converted = converter.convert()
    editor_units = {u['Id']: u for u in converted['editor_metadata']['Units']}

    with open(args.level, encoding='utf8') as f:
        level = sjson.loads(f.read())

    present = {u['id'] for u in level['units']}
    added = 0

    for unit in converted['units']:
        if unit['id'] in converter.stand_in_ids and unit['id'] not in present:
            level['units'].append(unit)
            level['editor_metadata']['Units'].append(editor_units[unit['id']])
            added += 1

    with open(args.level, 'w', encoding='utf8', newline='\n') as f:
        f.write(sjson.dumps(level))

    with open(args.report, 'w', encoding='utf8', newline='\n') as f:
        f.write(converter.report(converted))

    print('added %d stand-ins, %d were in the level already' % (added, len(converter.stand_in_ids) - added))


if __name__ == '__main__':
    main()
