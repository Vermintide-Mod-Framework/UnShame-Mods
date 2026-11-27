import re

# Reads and writes Stingray's SJSON, the text of .level and .unit files: key = value, { } objects,
# [ ] arrays without commas, and strings quoted or bare.

_TOKEN = re.compile(r'\s*(?:(//[^\n]*)|("(?:[^"\\]|\\.)*")|([{}\[\]=,])|([^\s{}\[\]=,"]+))', re.S)


def _tokens(text):
    pos = 0

    while pos < len(text):
        m = _TOKEN.match(text, pos)

        if not m or m.end() == pos:
            break

        pos = m.end()
        comment, string, punct, bare = m.groups()

        if comment:
            continue
        if string is not None:
            yield ('s', string[1:-1].replace('\\"', '"').replace('\\\\', '\\'))
        elif punct:
            if punct != ',':
                yield ('p', punct)
        elif bare is not None:
            yield ('b', bare)


def _value(token, tokens):
    kind, v = token

    if token == ('p', '{'):
        return _object(tokens, ('p', '}'))

    if token == ('p', '['):
        out = []

        for t in tokens:
            if t == ('p', ']'):
                return out

            out.append(_value(t, tokens))

    if kind == 's':
        return v
    if v in ('true', 'false'):
        return v == 'true'
    if v == 'null':
        return None

    for convert in (int, float):
        try:
            return convert(v)
        except ValueError:
            pass

    return v


def _object(tokens, end):
    out = {}

    for t in tokens:
        if t == end:
            return out

        if next(tokens) != ('p', '='):
            raise ValueError('expected = after %s' % t[1])

        out[t[1]] = _value(next(tokens), tokens)

    return out


def loads(text):
    return _object(_tokens(text), None)


def _number(v):
    if isinstance(v, int) or float(v).is_integer() and abs(v) < 1e15:
        return str(int(v))

    # The shortest text that reads back as the same number, so a level read and written again keeps every number
    return repr(float(v))


def _key(k):
    return k if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', k) else '"%s"' % k


def _string(s):
    return '"%s"' % s.replace('\\', '\\\\').replace('"', '\\"')


def _write(value, indent, out):
    tabs = '\t' * indent

    if isinstance(value, dict):
        out.append('{')

        for k in sorted(value):
            out.append('\n%s\t%s = ' % (tabs, _key(k)))
            _write(value[k], indent + 1, out)

        out.append('\n%s}' % tabs)
    elif isinstance(value, list):
        out.append('[')

        for v in value:
            out.append('\n%s\t' % tabs)
            _write(v, indent + 1, out)

        out.append('\n%s]' % tabs)
    elif isinstance(value, bool):
        out.append('true' if value else 'false')
    elif isinstance(value, (int, float)):
        out.append(_number(value))
    elif value is None:
        out.append('null')
    else:
        out.append(_string(value))


def dumps(obj):
    """Writes the top level object as the editor does: its keys sorted, one value a line, tabs."""
    out = []

    for k in sorted(obj):
        out.append('%s = ' % _key(k))
        _write(obj[k], 0, out)
        out.append('\n')

    return ''.join(out)
