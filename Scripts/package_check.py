#!/usr/bin/env python3
"""Local package gates. Developer ID and notarization are distinct gates."""
import argparse
import ctypes
import json
from pathlib import Path
import plistlib
import re
import subprocess
import sys
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
LOCALIZATIONS = ['en', 'tr']
LOCALIZED_FILES = {'en': ['Localizable.stringsdict', 'InfoPlist.strings', 'Setup.html'],
                   'tr': ['Localizable.strings', 'InfoPlist.strings', 'Setup.html']}
REASONS = {'NSPrivacyAccessedAPICategoryUserDefaults': ['CA92.1'],
           'NSPrivacyAccessedAPICategorySystemBootTime': ['35F9.1'],
           'NSPrivacyAccessedAPICategoryDiskSpace': ['85F4.1']}

def run(args, check=True):
    return subprocess.run(args, capture_output=True, text=True, check=check)

def versions():
    values = dict(line.split('=', 1) for line in (ROOT / 'version.env').read_text().splitlines() if '=' in line and not line.startswith('#'))
    if values.get('APP_NAME') != 'MacPulse' or values.get('BUNDLE_ID') != 'local.macpulse.desktop':
        raise ValueError('Unexpected application identity')
    if not re.fullmatch(r'\d+\.\d+\.\d+', values.get('MARKETING_VERSION', '')) or not re.fullmatch(r'[1-9]\d*', values.get('BUILD_NUMBER', '')):
        raise ValueError('Invalid version/build')
    return values

def preflight(output):
    output = Path(output)
    if output.is_symlink() or (output / 'MacPulse.app').is_symlink():
        raise ValueError('Package destination must not be a symlink')
    output = output.resolve()
    if output != ROOT and ROOT not in output.parents:
        raise ValueError('Package destination must remain inside this project')
    versions()
    target = output / 'MacPulse.app/Contents/MacOS/MacPulse'
    lib = ctypes.CDLL('/usr/lib/libproc.dylib')
    lib.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    for pid in run(['pgrep', '-x', 'MacPulse'], check=False).stdout.split():
        buffer = ctypes.create_string_buffer(4096)
        if lib.proc_pidpath(int(pid), buffer, len(buffer)) > 0 and Path(buffer.value.decode()).resolve() == target:
            raise ValueError('Quit this MacPulse normally with Cmd+Q before replacing its bundle')

def identity(identity_value):
    text = run(['security', 'find-identity', '-v', '-p', 'codesigning']).stdout
    identities = re.findall(r'([A-Fa-f0-9]{40}) "(Developer ID Application:[^"]+)"', text)
    if not any(identity_value in (fingerprint, name) for fingerprint, name in identities):
        raise ValueError('A valid Developer ID Application identity/private key is required')

def metadata(app, mode, arches):
    value = versions()
    info = {'CFBundleName': value['APP_NAME'], 'CFBundleDisplayName': value['APP_NAME'],
            'CFBundleIdentifier': value['BUNDLE_ID'], 'CFBundleExecutable': value['APP_NAME'],
            'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': value['MARKETING_VERSION'],
            'CFBundleVersion': value['BUILD_NUMBER'], 'LSMinimumSystemVersion': value['MACOS_MIN_VERSION'],
            'LSUIElement': False, 'CFBundleIconFile': 'Icon', 'NSHighResolutionCapable': True,
            'NSHumanReadableCopyright': 'MacPulse',
            'CFBundleDevelopmentRegion': 'en', 'CFBundleLocalizations': LOCALIZATIONS,
            'NSBluetoothAlwaysUsageDescription': 'Battery levels of connected accessories are shown locally.',
            'NSLocalNetworkUsageDescription': 'Batteries of iPhones and iPads already paired with this Mac are read over the local network.',
            'NSBonjourServices': ['_apple-mobdev2._tcp'],
            'DistributionChannel': 'local-preview' if mode == 'adhoc' else 'developer-id',
            'SupportedArchitectures': arches,
            'BuildTimestamp': datetime.now(timezone.utc).isoformat()}
    (Path(app) / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))

def privacy(value):
    if value.get('NSPrivacyTracking') is not False or value.get('NSPrivacyTrackingDomains') != [] or value.get('NSPrivacyCollectedDataTypes') != []:
        raise ValueError('Unexpected tracking/off-device collection declaration')
    entries = value.get('NSPrivacyAccessedAPITypes', [])
    reasons = {e['NSPrivacyAccessedAPIType']: e['NSPrivacyAccessedAPITypeReasons'] for e in entries}
    if reasons != REASONS or len(entries) != len(REASONS):
        raise ValueError('Privacy required-reason declarations do not match the reviewed source')

def localizations(info, resources):
    if info.get('CFBundleDevelopmentRegion') != 'en' or info.get('CFBundleLocalizations') != LOCALIZATIONS:
        raise ValueError('Localization metadata mismatch')
    for lang, names in LOCALIZED_FILES.items():
        for name in names:
            path = resources / f'{lang}.lproj' / name
            if not path.is_file() or path.stat().st_size == 0:
                raise ValueError(f'Missing localized resource: {lang}.lproj/{name}')
    if any(resources.glob('*.xcstrings')) or any(resources.glob('*.html')):
        raise ValueError('Uncompiled catalog or unlocalized help page in bundle')
    strings = plistlib.loads((resources / 'tr.lproj/Localizable.strings').read_bytes())
    if strings.get('Battery') != 'Pil':
        raise ValueError('Turkish string table is incomplete')

def signature_ready(display):
    return ('Authority=Developer ID Application:' in display
            and re.search(r'^.*flags=0x[0-9a-fA-F]+\([^\n]*\bruntime\b[^\n]*\)', display, re.MULTILINE) is not None
            and re.search(r'^Timestamp=(?!none$)\S.*$', display, re.MULTILINE) is not None
            and 'Signature=adhoc' not in display)

def verify(app, mode='adhoc', arches=None):
    app = Path(app)
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    expected = versions()
    for key, value in [('CFBundleIdentifier', expected['BUNDLE_ID']), ('CFBundleExecutable', 'MacPulse'),
                       ('CFBundleShortVersionString', expected['MARKETING_VERSION']), ('CFBundleVersion', expected['BUILD_NUMBER']),
                       ('LSMinimumSystemVersion', '14.0'), ('CFBundlePackageType', 'APPL')]:
        if info.get(key) != value: raise ValueError('Package metadata mismatch: ' + key)
    if info.get('LSUIElement') is not False: raise ValueError('Expected regular desktop app')
    binary = app / 'Contents/MacOS/MacPulse'
    actual = run(['lipo', '-archs', str(binary)]).stdout.split()
    expected_arches = arches or info.get('SupportedArchitectures', [])
    if sorted(actual) != sorted(expected_arches) or len(set(actual)) != len(actual):
        raise ValueError('Binary architecture mismatch')
    build = run(['otool', '-l', str(binary)]).stdout
    minimums = re.findall(r'\bminos ([\d.]+)', build)
    if len(minimums) != len(actual) or any(v != '14.0' for v in minimums):
        raise ValueError('Mach-O deployment target mismatch')
    resources = app / 'Contents/Resources'
    localizations(info, resources)
    privacy(plistlib.loads((resources / 'PrivacyInfo.xcprivacy').read_bytes()))
    if (resources / 'ThirdPartyNotices.md').read_bytes() != (ROOT / 'docs/THIRD-PARTY.md').read_bytes():
        raise ValueError('Missing/changed third-party notice')
    icon = (resources / 'Icon.icns').read_bytes()
    if icon[:4] != b'icns' or int.from_bytes(icon[4:8], 'big') != len(icon): raise ValueError('Invalid app icon')
    if any(p.name.startswith(('history.sqlite', 'preferences.json')) for p in app.rglob('*')):
        raise ValueError('A user store must never be packaged')
    run(['codesign', '--verify', '--deep', '--strict', str(app)])
    signing = run(['codesign', '-dvv', str(app)], check=False).stderr
    ent_result = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)], capture_output=True)
    entitlements = plistlib.loads(ent_result.stdout) if ent_result.stdout else {}
    if entitlements: raise ValueError('Unexpected entitlements or runtime exceptions')
    if mode == 'developer-id' and (not signature_ready(signing) or info.get('DistributionChannel') != 'developer-id'):
        raise ValueError('Developer ID, hardened runtime and timestamp are required; ad-hoc cannot be released')
    if mode == 'adhoc' and ('Signature=adhoc' not in signing or info.get('DistributionChannel') != 'local-preview'):
        raise ValueError('Local preview signature/channel mismatch')
    return {'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
            'architectures': actual, 'minimumMacOS': minimums, 'codesignVerified': True,
            'privacyManifestValidated': True, 'noticesMatch': True, 'entitlementsEmpty': True,
            'developerIDReady': signature_ready(signing), 'channel': info['DistributionChannel']}

def publish(source, destination):
    source, destination = Path(source), Path(destination)
    preflight(destination.parent)
    previous = source.parent / 'previous.app'
    existed = destination.exists()
    if existed: destination.rename(previous)
    try: source.rename(destination)
    except BaseException:
        if existed: previous.rename(destination)
        raise

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='action', required=True)
    p = sub.add_parser('preflight'); p.add_argument('output')
    p = sub.add_parser('identity'); p.add_argument('identity')
    p = sub.add_parser('metadata'); p.add_argument('app'); p.add_argument('mode'); p.add_argument('architectures', nargs='+')
    p = sub.add_parser('verify'); p.add_argument('app'); p.add_argument('--mode', choices=['adhoc', 'developer-id'], default='adhoc'); p.add_argument('--architectures', nargs='+')
    p = sub.add_parser('publish'); p.add_argument('source'); p.add_argument('destination')
    args = parser.parse_args()
    if args.action == 'preflight': preflight(args.output)
    elif args.action == 'identity': identity(args.identity)
    elif args.action == 'metadata': metadata(args.app, args.mode, args.architectures)
    elif args.action == 'publish': publish(args.source, args.destination)
    elif args.action == 'verify': print(json.dumps(verify(args.app, args.mode, args.architectures), indent=2))

if __name__ == '__main__':
    try: main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print('Package gate failed: ' + str(error), file=sys.stderr); sys.exit(1)
