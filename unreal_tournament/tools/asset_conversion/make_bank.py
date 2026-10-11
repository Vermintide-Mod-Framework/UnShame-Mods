import struct, os, sys

# Makes the Wwise sound bank of the Shock Rifle's skin by hand (there is no Wwise authoring tool at hand): a .bnk with an event
# for each sound, that plays one sound with the audio of UT2004 in it (exported with UModel to <scratch>/umodel/out5).
# The bank is made like the ones the game has (see "What was found" in README.md), from objects of a bank known to work:
# the sounds are PCM, with no parent and the output bus that the game's sounds use, an event is played by an action.
# Usage: make_bank.py <scratch dir>

SCRATCH = sys.argv[1]
REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
BANK_NAME = 'ut_shock_rifle'
OUT = REPO + '/wwise/unreal_tournament'

# The sounds: event name, wav, if it is heard from where it is (3D) or from the head, volume in dB
SOUNDS = [
    ('ut_shock_fire', 'BShockRifleFire', False, -6),
    ('ut_shock_alt_fire', 'BShockRifleAltFire', False, -6),
    ('ut_shock_select', 'SwitchToShockRifle', False, -6),
    ('ut_shock_fire_3d', 'BShockRifleFire', True, -6),
    ('ut_shock_alt_fire_3d', 'BShockRifleAltFire', True, -6),
    ('ut_shock_projectile_3d', 'ShockRifleProjectile', True, -12),
    ('ut_shock_explosion_3d', 'ShockRifleExplosion', True, -3),
    ('ut_shock_combo_3d', 'ShockComboFire', True, -3),
]

def fnv1(name):
    h = 2166136261
    for c in name.lower().encode():
        h = (h * 16777619) & 0xffffffff
        h ^= c
    return h

# Objects of the bank that is known to work: a sound that is heard from the head (no parent, the bus the game's sounds are
# in, a volume), one that is heard from where it is (the volume and an attenuation), and the attenuation
SOUND_2D = bytes.fromhex('fc326800010001000096eb4b17401a04000000000037bcb7e2000000000001000000e0c00003000000010000000000000000')
SOUND_3D = bytes.fromhex('15a63e0001000100005626e50be44707000000000037bcb7e200000000000200460000e0c0a07e632b0003010000010000000000000000')
ATTENUATION = bytes.fromhex('a07e632b00000000ffffffff010207000000000000000000090000000000004000000000040000000000c0406364ffbe0400000000006041de7952bf040000000000b8419d9074bf040000000000e041a4707dbf040000000000f041000080bf040000000000')

def pcm_wem(path):
    d = open(path, 'rb').read()
    channels, rate = struct.unpack('<HI', d[22:24] + d[24:28])
    assert struct.unpack('<H', d[20:22])[0] == 1 and struct.unpack('<H', d[34:36])[0] == 16, path
    # (the data chunk)
    q = 12
    while d[q:q + 4] != b'data':
        q += 8 + struct.unpack('<I', d[q + 4:q + 8])[0]
    pcm = d[q + 8:q + 8 + struct.unpack('<I', d[q + 4:q + 8])[0]]
    config = {1: b'\x01\x41', 2: b'\x02\x31'}[channels]
    fmt = struct.pack('<HHIIHH', 0xFFFE, channels, rate, rate * channels * 2, channels * 2, 16) + b'\x06\x00\x00\x00' + config + b'\x00\x00'
    body = b'WAVE' + b'fmt ' + struct.pack('<I', len(fmt)) + fmt + b'JUNK' + struct.pack('<I', 4) + b'\0\0\0\0' + b'data' + struct.pack('<I', len(pcm)) + pcm
    return b'RIFF' + struct.pack('<I', len(body)) + body

bank_id = fnv1(BANK_NAME)
attenuation_id = fnv1(BANK_NAME + '_attenuation')
objects = [(14, struct.pack('<I', attenuation_id) + ATTENUATION[4:])]
media = {}
for event, wav, is_3d, volume in SOUNDS:
    wem = pcm_wem('%s/umodel/out5/WeaponSounds/Sound/%s.wav' % (SCRATCH, wav))
    media_id = fnv1('ut_media_' + wav)
    media[media_id] = wem
    sound_id, action_id = fnv1('ut_sound_' + event), fnv1('ut_action_' + event)
    body = bytearray(SOUND_3D if is_3d else SOUND_2D)
    body[0:4] = struct.pack('<I', sound_id)
    body[9:13] = struct.pack('<I', media_id)
    body[13:17] = struct.pack('<I', len(wem))
    if is_3d:
        body[33:37] = struct.pack('<f', volume)
        body[37:41] = struct.pack('<I', attenuation_id)
    else:
        body[32:36] = struct.pack('<f', volume)
    objects.append((2, bytes(body)))
    # the action that plays the sound (Play = 0x0403), and the event
    objects.append((3, struct.pack('<I', action_id) + b'\x03\x04' + struct.pack('<I', sound_id) + b'\x00\x00\x00\x04' + struct.pack('<I', bank_id)))
    objects.append((4, struct.pack('<I', fnv1(event)) + b'\x01' + struct.pack('<I', action_id)))
    print('event', event, hex(fnv1(event)), len(wem), 'bytes')

hirc = struct.pack('<I', len(objects)) + b''.join(struct.pack('<BI', t, len(b)) + b for t, b in objects)
ids = sorted(media)
didx = b''
data = b''
for mid in ids:
    didx += struct.pack('<III', mid, len(data), len(media[mid]))
    data += media[mid]

# (the version and the language are those of the banks of the game)
header = struct.pack('<IIIHHI', 0x9211bc28, bank_id, 0x17705d3e, 0, 0, 0)
bank = b'BKHD' + struct.pack('<I', len(header)) + header + b'DIDX' + struct.pack('<I', len(didx)) + didx + \
    b'DATA' + struct.pack('<I', len(data)) + data + b'HIRC' + struct.pack('<I', len(hirc)) + hirc
os.makedirs(OUT, exist_ok=True)
open(OUT + '/shock_rifle.bnk', 'wb').write(bank)
print('wrote', OUT + '/shock_rifle.bnk', len(bank), 'bytes, bank id', hex(bank_id))
