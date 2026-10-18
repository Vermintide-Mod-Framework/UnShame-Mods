import struct, os, sys

# Makes the Wwise sound bank of a weapon's skin by hand (there is no Wwise authoring tool at hand): a .bnk with an event for each
# sound, that plays one sound with the audio of UT2004 in it (exported with UModel with -sounds, see README.md), and what the SDK
# compiles it with: the .wwise_bank (the bank for each platform), the .wwise_metadata (what the engine knows of each event) and the
# .wwise_dep (that they go together). The bank is made like the ones the game has (see "What was found" in README.md), from objects of
# a bank known to work: the sounds are PCM, with no parent and the output bus that the game's sounds use, an event is played by an action.
# Usage: make_bank.py <weapon> <export dir>        (weapons are in WEAPONS below)

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
OUT = REPO + '/wwise/unreal_tournament'

# The sounds of each weapon: event name, wav (relative to the export dir), if it is heard from where it is (3D) or from the
# head, volume in dB, and for those from where they are the distance in meters they are heard from
SOUNDS = 'WeaponSounds/Sound/'
NEW_SOUNDS = 'NewWeaponSounds/Sound/'
# (the male announcer pack of UT2004, the one its reward announcements are by default. The names of the kills are the ones
# MultiKillMessage.KillSoundName has)
ANNOUNCER = 'announcermale2k4/Sound/'
# (the impacts of the Sniper Rifle's bullet)
IMPACTS = 'XEffects/Sound/'
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
        ('ut_shock_fire', SOUNDS + 'BShockRifleFire', False, -22, 0),
        ('ut_shock_alt_fire', SOUNDS + 'BShockRifleAltFire', False, -22, 0),
        ('ut_shock_select', SOUNDS + 'SwitchToShockRifle', False, -24, 0),
        ('ut_shock_fire_3d', SOUNDS + 'BShockRifleFire', True, -22, 40),
        ('ut_shock_alt_fire_3d', SOUNDS + 'BShockRifleAltFire', True, -22, 40),
        ('ut_shock_projectile_3d', SOUNDS + 'ShockRifleProjectile', True, -30, 25),
        ('ut_shock_explosion_3d', SOUNDS + 'ShockRifleExplosion', True, -20, 50),
        # (louder than the other sounds of the rifle: it is played as the beam's shot is, and was lost under it)
        ('ut_shock_combo_3d', SOUNDS + 'ShockComboFire', True, -16, 60),
    ],
    'flak_cannon': [
        ('ut_flak_fire', SOUNDS + 'BFlakCannonFire', False, -22, 0),
        ('ut_flak_alt_fire', SOUNDS + 'BFlakCannonAltFire', False, -22, 0),
        ('ut_flak_select', SOUNDS + 'SwitchToFlakCannon', False, -24, 0),
        # (the end of the shot's sound, after the blast: the next shell sliding in and the hammer, which the shot's animation plays)
        ('ut_flak_load', SOUNDS + 'BFlakCannonFire@0.64', False, -22, 0),
        ('ut_flak_fire_3d', SOUNDS + 'BFlakCannonFire', True, -22, 40),
        ('ut_flak_alt_fire_3d', SOUNDS + 'BFlakCannonAltFire', True, -22, 40),
        ('ut_flak_shell_3d', SOUNDS + 'BFlakCannonProjectile', True, -30, 25),
        ('ut_flak_explosion_3d', SOUNDS + 'BExplosion1', True, -20, 50),
    ],
    'rocket_launcher': [
        ('ut_rocket_fire', SOUNDS + 'BRocketLauncherFire', False, -22, 0),
        ('ut_rocket_alt_fire', SOUNDS + 'BRocketLauncherAltFire', False, -22, 0),
        ('ut_rocket_load', SOUNDS + 'BRocketLauncherLoad', False, -22, 0),
        ('ut_rocket_plunger', SOUNDS + 'RocketLauncherPlunger', False, -22, 0),
        ('ut_rocket_lock', SOUNDS + 'BLockOn1', False, -22, 0),
        ('ut_rocket_seek_lost', SOUNDS + 'BSeekLost1', False, -22, 0),
        ('ut_rocket_select', SOUNDS + 'SwitchToRocketLauncher', False, -24, 0),
        ('ut_rocket_fire_3d', SOUNDS + 'BRocketLauncherFire', True, -22, 40),
        ('ut_rocket_load_3d', SOUNDS + 'BRocketLauncherLoad', True, -26, 25),
        ('ut_rocket_plunger_3d', SOUNDS + 'RocketLauncherPlunger', True, -26, 25),
        ('ut_rocket_projectile_3d', SOUNDS + 'RocketLauncherProjectile', True, -30, 25),
        ('ut_rocket_explosion_3d', SOUNDS + 'BExplosion3', True, -20, 50),
    ],
    'bio_rifle': [
        ('ut_bio_fire', SOUNDS + 'BBioRifleFire', False, -22, 0),
        # (BioChargedFire.Hold plays Biorifle_charge when the charge starts, and BioGoopLoop, a loop, from when it is full)
        ('ut_bio_charge', SOUNDS + 'biorifle_charge', False, -24, 0),
        ('ut_bio_goop_loop', NEW_SOUNDS + 'BioGoopLoop', False, -32, 0),
        # (what others hear: Weapon.PlayOwnedSound for the charge, and the pawn's AmbientSound, radius 50 uu, for the goop loop)
        ('ut_bio_charge_3d', SOUNDS + 'biorifle_charge', True, -26, 25),
        ('ut_bio_goop_loop_3d', NEW_SOUNDS + 'BioGoopLoop', True, -34, 8),
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
    'minigun': [
        ('ut_minigun_fire', NEW_SOUNDS + 'NewMinigunFire', False, -22, 0),
        ('ut_minigun_alt_fire', SOUNDS + 'minialtfireb', False, -22, 0),
        # (the winding of the barrels, which plays while they spin up and down, and the end of it)
        ('ut_minigun_wind', SOUNDS + 'miniempty', False, -26, 0),
        ('ut_minigun_wind_down', SOUNDS + 'BMiniGunWindDown', False, -26, 0),
        ('ut_minigun_select', SOUNDS + 'SwitchToMiniGun', False, -24, 0),
        ('ut_minigun_fire_3d', NEW_SOUNDS + 'NewMinigunFire', True, -22, 40),
        ('ut_minigun_alt_fire_3d', SOUNDS + 'minialtfireb', True, -22, 40),
        ('ut_minigun_shell_3d', SOUNDS + 'BShell1', True, -30, 12),
    ],
    'shield_gun': [
        ('ut_shield_fire', SOUNDS + 'BShieldGunFire', False, -20, 0),
        ('ut_shield_charge', SOUNDS + 'shieldgun_charge', False, -24, 0),
        ('ut_shield_up', SOUNDS + 'BShield1', False, -24, 0),
        ('ut_shield_hit', SOUNDS + 'BShieldReflection', False, -20, 0),
        ('ut_shield_regen', SOUNDS + 'BTranslocatorModuleRegeneration', False, -28, 0),
        ('ut_shield_select', SOUNDS + 'shieldgun_change', False, -24, 0),
        ('ut_shield_fire_3d', SOUNDS + 'BShieldGunFire', True, -20, 40),
        ('ut_shield_up_3d', SOUNDS + 'BShield1', True, -26, 25),
        ('ut_shield_hit_3d', SOUNDS + 'BShieldReflection', True, -22, 30),
        # (the charge on another player: UT's AmbientSound on the pawn while it charges)
        ('ut_shield_charge_3d', SOUNDS + 'shieldgun_charge', True, -26, 25),
        # (another player raising the shield: ShieldAltFire's FireSound, which UT plays for the others and not for the owner)
        ('ut_shield_regen_3d', SOUNDS + 'BTranslocatorModuleRegeneration', True, -30, 25),
    ],
    'redeemer': [
        ('ut_redeemer_fire', SOUNDS + 'redeemer_shoot', False, -18, 0),
        ('ut_redeemer_select', SOUNDS + 'redeemer_change', False, -24, 0),
        ('ut_redeemer_fire_3d', SOUNDS + 'redeemer_shoot', True, -18, 60),
        ('ut_redeemer_flight_3d', SOUNDS + 'redeemer_flight', True, -22, 80),
        ('ut_redeemer_explosion_3d', SOUNDS + 'redeemer_explosionsound', True, -10, 200),
    ],
    'assault_rifle': [
        ('ut_assault_fire', SOUNDS + 'BAssaultRifleFire', False, -22, 0),
        # (AssaultGrenade.FireSound and ReloadSound: the grenade's shot, and the drum turning to the next one)
        ('ut_assault_alt_fire', NEW_SOUNDS + 'NewGrenadeShoot', False, -22, 0),
        ('ut_assault_grenade_load', SOUNDS + 'BReload9', False, -26, 0),
        ('ut_assault_select', SOUNDS + 'SwitchToAssaultRifle', False, -24, 0),
        ('ut_assault_fire_3d', SOUNDS + 'BAssaultRifleFire', True, -22, 40),
        ('ut_assault_alt_fire_3d', NEW_SOUNDS + 'NewGrenadeShoot', True, -22, 40),
        # (Grenade.ImpactSound P1GrenFloor1 and its explosion, BExplosion3)
        ('ut_assault_grenade_bounce_3d', SOUNDS + 'BGrenfloor1', True, -24, 25),
        ('ut_assault_grenade_explosion_3d', SOUNDS + 'BExplosion3', True, -14, 80),
    ],
    'lightning_gun': [
        ('ut_lightning_fire', SOUNDS + 'BLightningGunFire', False, -22, 0),
        # (SniperFire.PlayFiring: the charge up that follows a shot, if there is ammo for the next)
        ('ut_lightning_charge', SOUNDS + 'LightningGunChargeUp', False, -24, 0),
        ('ut_lightning_select', SOUNDS + 'SwitchToLightningGun', False, -24, 0),
        # (SniperRifle.RenderOverlays: LightningZoomIn and LightningZoomOut. Each is a SoundGroup of one ProceduralSound, P1ZoomIn1 and
        # P1ZoomOut1, which play BZoomIn1 and BZoomOut1 as they are: a modifier of 1 and no variance, read from WeaponSounds.uax)
        ('ut_lightning_zoom_in', SOUNDS + 'BZoomIn1', False, -26, 0),
        ('ut_lightning_zoom_out', SOUNDS + 'BZoomOut1', False, -26, 0),
        # (the bolt's hit: LightningBolt.PostBeginPlay)
        ('ut_lightning_impact_3d', SOUNDS + 'BLightningGunImpact', True, -20, 50),
        ('ut_lightning_fire_3d', SOUNDS + 'BLightningGunFire', True, -22, 50),
    ],
    # The Sniper Rifle (UTClassic.ClassicSniperRifle). Its zoom sounds are the Lightning Gun's.
    'sniper_rifle': [
        ('ut_sniper_fire', NEW_SOUNDS + 'NewSniperShot', False, -22, 0),
        ('ut_sniper_select', NEW_SOUNDS + 'NewSniper_load', False, -24, 0),
        ('ut_sniper_fire_3d', NEW_SOUNDS + 'NewSniperShot', True, -22, 50),
        # (SniperWallHitEffect.ImpactSounds: one of the six where the bullet hits, at 2.5 times the volume, heard within 200 units)
        ('ut_sniper_impact_1_3d', IMPACTS + 'Impact1Snd', True, -18, 4),
        ('ut_sniper_impact_2_3d', IMPACTS + 'Impact2Snd', True, -18, 4),
        ('ut_sniper_impact_3_3d', IMPACTS + 'Impact5Snd', True, -18, 4),
        ('ut_sniper_impact_4_3d', IMPACTS + 'Impact3', True, -18, 4),
        ('ut_sniper_impact_5_3d', IMPACTS + 'Impact1', True, -18, 4),
        ('ut_sniper_impact_6_3d', IMPACTS + 'Impact2', True, -18, 4),
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

# The sounds that loop until they are stopped (their event's playing id, WwiseWorld.stop_event): what UT plays as an AmbientSound
LOOPS = {
    # (MinigunFire.PlayAmbientSound: FiringSound while it fires, WindingSound while the barrels wind up and down)
    'ut_minigun_fire', 'ut_minigun_alt_fire', 'ut_minigun_wind', 'ut_minigun_fire_3d', 'ut_minigun_alt_fire_3d',
}

# A sound object's properties start at this offset: their count, their ids, then a value of 4 bytes for each, in the order of the ids.
# The 2D sound has the volume (0x00); the 3D one the volume and its attenuation (0x46). In this version of Wwise (2018.1) 0x3A is Loop,
# the number of times the sound plays, where 0 is for ever.
PROPS_OFFSET = 30
PROP_LOOP = 0x3A

def with_loop(body):
    count = body[PROPS_OFFSET]
    ids = list(body[PROPS_OFFSET + 1:PROPS_OFFSET + 1 + count])
    values_at = PROPS_OFFSET + 1 + count
    values = [body[values_at + 4 * i:values_at + 4 * i + 4] for i in range(count)]
    rest = body[values_at + 4 * count:]
    props = sorted(list(zip(ids, values)) + [(PROP_LOOP, struct.pack('<I', 0))])
    return (body[:PROPS_OFFSET] + bytes([len(props)]) + bytes(prop_id for prop_id, _ in props) + b''.join(value for _, value in props)
            + rest)

def attenuation_object(attenuation_id, distance):
    # The curve of the attenuation is made for 30 meters (the distances of its points, at these offsets of the object): a sound of another
    # reach has the curve made longer or shorter, so that it can be heard as far as the reach of its definition says (the combo, 60, was heard
    # up to 30 only)
    body = bytearray(ATTENUATION)
    body[0:4] = struct.pack('<I', attenuation_id)

    for offset in (40, 52, 64, 76, 88):
        body[offset:offset + 4] = struct.pack('<f', struct.unpack_from('<f', ATTENUATION, offset)[0] * distance / 30.0)

    return bytes(body)

# Sounds that UT plays at a pitch of their own: they are made that much faster (and higher) here, as Unreal plays them
PITCH = {
    # (SniperFire.PlayFiring plays it with a pitch of 1.1)
    'ut_lightning_charge': 1.1,
}

# Plays 16 bit samples faster by a factor, by reading them at that step, between two samples in a line
def faster(pcm, channels, factor):
    count = len(pcm) // (2 * channels)
    samples = struct.unpack('<%dh' % (count * channels), pcm[:count * channels * 2])
    out = []
    for i in range(int((count - 1) / factor)):
        position = i * factor
        first = int(position)
        share = position - first
        for c in range(channels):
            a = samples[first * channels + c]
            b = samples[(first + 1) * channels + c]
            out.append(int(round(a + (b - a) * share)))
    return struct.pack('<%dh' % len(out), *out)

def pcm_wem(path, start=0.0, pitch=1.0):
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
    # (from this many seconds in: the end of a sound is a sound of its own)
    pcm = pcm[int(start * rate) * channels * 2:]
    if pitch != 1.0:
        pcm = faster(pcm, channels, pitch)
    config = {1: b'\x01\x41', 2: b'\x02\x31'}[channels]
    fmt = struct.pack('<HHIIHH', 0xFFFE, channels, rate, rate * channels * 2, channels * 2, 16) + b'\x06\x00\x00\x00' + config + b'\x00\x00'
    body = b'WAVE' + b'fmt ' + struct.pack('<I', len(fmt)) + fmt + b'JUNK' + struct.pack('<I', 4) + b'\0\0\0\0' + b'data' + struct.pack('<I', len(pcm)) + pcm
    return b'RIFF' + struct.pack('<I', len(body)) + body, len(pcm) / (rate * channels * 2)

def main():
    weapon, export = sys.argv[1], sys.argv[2]
    sounds = WEAPONS[weapon]
    bank_name = 'ut_' + weapon
    bank_id = fnv1(bank_name)
    objects = []
    media = {}
    metadata = []
    for event, wav, is_3d, volume, distance in sounds:
        # (a wav can be followed by @ and the second to start from)
        path, _, start = wav.partition('@')
        pitch = PITCH.get(event, 1.0)
        wem, seconds = pcm_wem('%s/%s.wav' % (export, path), float(start or 0), pitch)
        media_id = fnv1('ut_media_' + os.path.basename(wav) + ('' if pitch == 1.0 else '_pitch_%g' % pitch))
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
        if event in LOOPS:
            body = with_loop(bytes(body))
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
        # (a loop plays until it is stopped)
        kind = 'Infinite' if event in LOOPS else 'OneShot'
        lines.append('\t%s = { attenuation_max = %d duration_type = "%s" duration_min = %.3f duration_max = %.3f positioning = "%s" }'
                     % (event, distance, kind, seconds, seconds, '3D' if is_3d else '2D'))
    lines.append('}')
    open('%s/%s.wwise_metadata' % (OUT, weapon), 'w', newline='\n').write('\n'.join(lines) + '\n')
    # The dependency: the resources of the weapon's bank, for each platform
    name = 'wwise/unreal_tournament/' + weapon
    open('%s/%s.wwise_dep' % (OUT, weapon), 'w', newline='\n').write(
        'win32 = {\n\tbanks = [\n\t\t"%s"\n\t]\n\tstreams = [\n\t]\n\tmetadata = "%s"\n}\n' % (name, name))
    print('wrote', OUT + '/' + weapon, len(bank), 'bytes, bank id', hex(bank_id))

main()
