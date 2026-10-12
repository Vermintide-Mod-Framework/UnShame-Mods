import struct, os, sys

# Makes the Wwise sound bank of a weapon's skin by hand (there is no Wwise authoring tool at hand): a .bnk with an event for each
# sound, that plays one sound with the audio of UT2004 in it (exported with UModel with -sounds, see README.md), and what the SDK
# compiles it with: the .wwise_bank (the bank for each platform), the .wwise_metadata (what the engine knows of each event) and the
# .wwise_dep (that they go together). The bank is made like the ones the game has (see "What was found" in README.md), from objects of
# a bank known to work: the sounds are PCM, with no parent and the output bus that the game's sounds use, an event is played by an action.
# Usage: make_bank.py <weapon> <scratch dir>        (weapons are in WEAPONS below, the dir has umodel/out5 and umodel/out8)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = REPO + '/wwise/unreal_tournament'

# The sounds of each weapon: event name, wav (relative to the scratch dir's umodel), if it is heard from where it is (3D) or from the
# head, volume in dB, and for those from where they are the distance in meters they are heard from
SHOCK = 'out5/WeaponSounds/Sound/'
SOUNDS = 'out8/WeaponSounds/Sound/'
NEW_SOUNDS = 'out8/NewWeaponSounds/Sound/'
# (the male announcer pack of UT2004, the one its reward announcements are by default: umodel_64 -game=ut2 -export -sounds -out=out10
# announcermale2k4. The names of the kills are the ones MultiKillMessage.KillSoundName has)
ANNOUNCER = 'out10/announcermale2k4/Sound/'
WEAPONS = {
    'announcer': [
        ('ut_announcer_double_kill', ANNOUNCER + 'Double_Kill', False, -18, 0),
        ('ut_announcer_multi_kill', ANNOUNCER + 'MultiKill', False, -18, 0),
        ('ut_announcer_mega_kill', ANNOUNCER + 'MegaKill', False, -18, 0),
        ('ut_announcer_ultra_kill', ANNOUNCER + 'UltraKill', False, -18, 0),
        ('ut_announcer_monster_kill', ANNOUNCER + 'MonsterKill_F', False, -18, 0),
        ('ut_announcer_ludicrous_kill', ANNOUNCER + 'LudicrousKill_F', False, -18, 0),
        ('ut_announcer_holy_shit', ANNOUNCER + 'HolyShit_F', False, -18, 0),
        # (KillingSpreeMessage.SpreeSoundName, FirstBloodMessage, SpecialKillMessage and DamTypeSniperHeadShot's HeadHunter)
        ('ut_announcer_killing_spree', ANNOUNCER + 'Killing_Spree', False, -18, 0),
        ('ut_announcer_rampage', ANNOUNCER + 'Rampage', False, -18, 0),
        ('ut_announcer_dominating', ANNOUNCER + 'Dominating', False, -18, 0),
        ('ut_announcer_unstoppable', ANNOUNCER + 'Unstoppable', False, -18, 0),
        ('ut_announcer_godlike', ANNOUNCER + 'GodLike', False, -18, 0),
        ('ut_announcer_wicked_sick', ANNOUNCER + 'WhickedSick', False, -18, 0),
        ('ut_announcer_first_blood', ANNOUNCER + 'first_blood', False, -18, 0),
        ('ut_announcer_headshot', ANNOUNCER + 'Headshot', False, -18, 0),
        ('ut_announcer_headhunter', ANNOUNCER + 'Headhunter', False, -18, 0),
        # (DamTypeFlakChunk and DamTypeShockCombo)
        ('ut_announcer_flak_monkey', ANNOUNCER + 'FlackMonkey', False, -18, 0),
        ('ut_announcer_combo_whore', ANNOUNCER + 'Combowhore', False, -18, 0),
    ],
    'shock_rifle': [
        ('ut_shock_fire', SHOCK + 'BShockRifleFire', False, -22, 0),
        ('ut_shock_alt_fire', SHOCK + 'BShockRifleAltFire', False, -22, 0),
        ('ut_shock_select', SHOCK + 'SwitchToShockRifle', False, -24, 0),
        ('ut_shock_fire_3d', SHOCK + 'BShockRifleFire', True, -22, 40),
        ('ut_shock_alt_fire_3d', SHOCK + 'BShockRifleAltFire', True, -22, 40),
        ('ut_shock_projectile_3d', SHOCK + 'ShockRifleProjectile', True, -30, 25),
        ('ut_shock_explosion_3d', SHOCK + 'ShockRifleExplosion', True, -20, 50),
        # (louder than the other sounds of the rifle: it is played as the beam's shot is, and was lost under it)
        ('ut_shock_combo_3d', SHOCK + 'ShockComboFire', True, -16, 60),
    ],
    'flak_cannon': [
        ('ut_flak_fire', SOUNDS + 'BFlakCannonFire', False, -22, 0),
        ('ut_flak_alt_fire', SOUNDS + 'BFlakCannonAltFire', False, -22, 0),
        ('ut_flak_select', SOUNDS + 'SwitchToFlakCannon', False, -24, 0),
        ('ut_flak_fire_3d', SOUNDS + 'BFlakCannonFire', True, -22, 40),
        ('ut_flak_alt_fire_3d', SOUNDS + 'BFlakCannonAltFire', True, -22, 40),
        ('ut_flak_shell_3d', SOUNDS + 'BFlakCannonProjectile', True, -30, 25),
        ('ut_flak_explosion_3d', SOUNDS + 'BExplosion1', True, -20, 50),
    ],
    'rocket_launcher': [
        ('ut_rocket_fire', SOUNDS + 'BRocketLauncherFire', False, -22, 0),
        ('ut_rocket_alt_fire', SOUNDS + 'BRocketLauncherAltFire', False, -22, 0),
        ('ut_rocket_load', SOUNDS + 'BRocketLauncherLoad', False, -22, 0),
        ('ut_rocket_select', SOUNDS + 'SwitchToRocketLauncher', False, -24, 0),
        ('ut_rocket_fire_3d', SOUNDS + 'BRocketLauncherFire', True, -22, 40),
        ('ut_rocket_load_3d', SOUNDS + 'BRocketLauncherLoad', True, -26, 25),
        ('ut_rocket_projectile_3d', SOUNDS + 'RocketLauncherProjectile', True, -30, 25),
        ('ut_rocket_explosion_3d', SOUNDS + 'BExplosion3', True, -20, 50),
    ],
    'bio_rifle': [
        ('ut_bio_fire', SOUNDS + 'BBioRifleFire', False, -22, 0),
        ('ut_bio_charge', SOUNDS + 'BBioRiflePoweUp', False, -24, 0),
        ('ut_bio_select', SOUNDS + 'SwitchToBioRifle', False, -24, 0),
        ('ut_bio_fire_3d', SOUNDS + 'BBioRifleFire', True, -22, 40),
        ('ut_bio_splat_3d', SOUNDS + 'BBioRifleGoo1', True, -22, 30),
        ('ut_bio_splat2_3d', SOUNDS + 'BBioRifleGoo2', True, -22, 30),
    ],
    'link_gun': [
        ('ut_link_fire', SOUNDS + 'BLinkGunFire', False, -22, 0),
        ('ut_link_beam', SOUNDS + 'BLinkGunBeam', False, -26, 0),
        ('ut_link_linked', SOUNDS + 'BLinkedFire', False, -24, 0),
        ('ut_link_select', NEW_SOUNDS + 'NewLinkSelect', False, -24, 0),
        ('ut_link_fire_3d', SOUNDS + 'BLinkGunFire', True, -22, 40),
        ('ut_link_beam_3d', SOUNDS + 'BLinkGunBeam', True, -28, 30),
        ('ut_link_projectile_3d', SOUNDS + 'LinkGunProjectile', True, -30, 25),
    ],
}

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

def attenuation_object(attenuation_id, distance):
    # The curve of the attenuation is made for 30 meters (the distances of its points, at these offsets of the object): a sound of another
    # reach has the curve made longer or shorter, so that it can be heard as far as the reach of its definition says (the combo, 60, was heard
    # up to 30 only)
    body = bytearray(ATTENUATION)
    body[0:4] = struct.pack('<I', attenuation_id)

    for offset in (40, 52, 64, 76, 88):
        body[offset:offset + 4] = struct.pack('<f', struct.unpack_from('<f', ATTENUATION, offset)[0] * distance / 30.0)

    return bytes(body)

def pcm_wem(path):
    d = open(path, 'rb').read()
    channels, rate = struct.unpack('<HI', d[22:24] + d[24:28])
    bits = struct.unpack('<H', d[34:36])[0]
    assert struct.unpack('<H', d[20:22])[0] == 1 and bits in (8, 16), path
    # (the data chunk)
    q = 12
    while d[q:q + 4] != b'data':
        q += 8 + struct.unpack('<I', d[q + 4:q + 8])[0]
    pcm = d[q + 8:q + 8 + struct.unpack('<I', d[q + 4:q + 8])[0]]
    if bits == 8:
        # (8 bit sounds are unsigned: they are made 16 bit)
        pcm = b''.join(struct.pack('<h', (s - 128) * 256) for s in pcm)
    config = {1: b'\x01\x41', 2: b'\x02\x31'}[channels]
    fmt = struct.pack('<HHIIHH', 0xFFFE, channels, rate, rate * channels * 2, channels * 2, 16) + b'\x06\x00\x00\x00' + config + b'\x00\x00'
    body = b'WAVE' + b'fmt ' + struct.pack('<I', len(fmt)) + fmt + b'JUNK' + struct.pack('<I', 4) + b'\0\0\0\0' + b'data' + struct.pack('<I', len(pcm)) + pcm
    return b'RIFF' + struct.pack('<I', len(body)) + body, len(pcm) / (rate * channels * 2)

def main():
    weapon, scratch = sys.argv[1], sys.argv[2]
    sounds = WEAPONS[weapon]
    bank_name = 'ut_' + weapon
    bank_id = fnv1(bank_name)
    objects = []
    media = {}
    metadata = []
    for event, wav, is_3d, volume, distance in sounds:
        wem, seconds = pcm_wem('%s/umodel/%s.wav' % (scratch, wav))
        media_id = fnv1('ut_media_' + os.path.basename(wav))
        media[media_id] = wem
        sound_id, action_id = fnv1('ut_sound_' + event), fnv1('ut_action_' + event)
        body = bytearray(SOUND_3D if is_3d else SOUND_2D)
        body[0:4] = struct.pack('<I', sound_id)
        body[9:13] = struct.pack('<I', media_id)
        body[13:17] = struct.pack('<I', len(wem))
        if is_3d:
            # (an attenuation of its own, of the reach the definition gives it)
            attenuation_id = fnv1('ut_attenuation_' + event)
            objects.append((14, attenuation_object(attenuation_id, distance)))
            body[33:37] = struct.pack('<f', volume)
            body[37:41] = struct.pack('<I', attenuation_id)
        else:
            body[32:36] = struct.pack('<f', volume)
        objects.append((2, bytes(body)))
        # the action that plays the sound (Play = 0x0403), and the event
        objects.append((3, struct.pack('<I', action_id) + b'\x03\x04' + struct.pack('<I', sound_id) + b'\x00\x00\x00\x04' + struct.pack('<I', bank_id)))
        objects.append((4, struct.pack('<I', fnv1(event)) + b'\x01' + struct.pack('<I', action_id)))
        metadata.append((event, is_3d, distance, seconds))
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
    open('%s/%s.bnk' % (OUT, weapon), 'wb').write(bank)
    # The source the SDK compiles into the wwise_bank resource: a version, then a record for each platform (its name in 32 bytes,
    # the length of the bank, the bank)
    open('%s/%s.wwise_bank' % (OUT, weapon), 'wb').write(struct.pack('<I', 1) + b'win32'.ljust(32, b'\0') + struct.pack('<Q', len(bank)) + bank)
    lines = ['events = {']
    for event, is_3d, distance, seconds in metadata:
        lines.append('\t%s = { attenuation_max = %d duration_type = "OneShot" duration_min = %.3f duration_max = %.3f positioning = "%s" }'
                     % (event, distance, seconds, seconds, '3D' if is_3d else '2D'))
    lines.append('}')
    open('%s/%s.wwise_metadata' % (OUT, weapon), 'w', newline='\n').write('\n'.join(lines) + '\n')
    # The dependency: the resources of the weapon's bank, for each platform
    name = 'wwise/unreal_tournament/' + weapon
    open('%s/%s.wwise_dep' % (OUT, weapon), 'w', newline='\n').write(
        'win32 = {\n\tbanks = [\n\t\t"%s"\n\t]\n\tstreams = [\n\t]\n\tmetadata = "%s"\n}\n' % (name, name))
    print('wrote', OUT + '/' + weapon, len(bank), 'bytes, bank id', hex(bank_id))

main()
