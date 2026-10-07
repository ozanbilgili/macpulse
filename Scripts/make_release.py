#!/usr/bin/env python3
"""Create a verified local preview or an explicitly notarized DMG/ZIP. Never publish."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
from package_check import ROOT, run, verify

def digest(path):
    with Path(path).open('rb') as source:
        value = hashlib.sha256()
        for block in iter(lambda: source.read(1024 * 1024), b''): value.update(block)
        value = value.hexdigest()
    return value

def notarize(path, profile, evidence, staple_target=None):
    result = run(['xcrun', 'notarytool', 'submit', str(path), '--keychain-profile', profile,
                  '--wait', '--timeout', '20m', '--output-format', 'json'])
    response = json.loads(result.stdout)
    if response.get('status') != 'Accepted':
        raise ValueError('Apple notarization was not Accepted; no release was produced')
    evidence.append({'artifact': path.name, 'id': response.get('id'), 'status': 'Accepted'})
    target = staple_target or path
    run(['xcrun', 'stapler', 'staple', str(target)])
    run(['xcrun', 'stapler', 'validate', str(target)])

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--channel', required=True, choices=['local-preview', 'notarized'])
    parser.add_argument('--notary-profile', help='Existing notarytool Keychain profile name; never a password')
    parser.add_argument('--app', type=Path, default=ROOT / 'MacPulse.app')
    args = parser.parse_args()
    if args.channel == 'notarized' and not args.notary_profile:
        raise ValueError('An existing notarization Keychain profile is required')
    app = args.app.resolve()
    if ROOT not in app.parents: raise ValueError('App must remain inside this project')
    mode = 'developer-id' if args.channel == 'notarized' else 'adhoc'
    report = verify(app, mode, ['arm64', 'x86_64'])
    name = 'MacPulse-' + report['version'] + ('-preview' if mode == 'adhoc' else '') + '-universal'
    output = ROOT / 'dist'; output.mkdir(exist_ok=True)
    if output.is_symlink(): raise ValueError('Release directory must not be a symlink')
    targets = [output / (name + ext) for ext in ['.dmg', '.zip', '.json']]
    if any(p.exists() for p in targets): raise ValueError('Versioned artifacts already exist; increment version/build')
    with tempfile.TemporaryDirectory(prefix='release-', dir=ROOT / '.build') as temporary:
        temporary = Path(temporary)
        source = temporary / 'image'; source.mkdir()
        staged_app = source / 'MacPulse.app'
        run(['ditto', str(app), str(staged_app)])
        notary = []
        if mode == 'developer-id':
            upload = temporary / 'MacPulse-notarize.zip'
            run(['ditto', '--norsrc', '-c', '-k', '--keepParent', str(staged_app), str(upload)])
            notarize(upload, args.notary_profile, notary, staple_target=staged_app)
            # A ZIP cannot be stapled. Its ticket is attached to the app below.
        (source / 'Applications').symlink_to('/Applications')
        (source / 'ÖNCE OKU.txt').write_text((ROOT / 'docs/INSTALL.md').read_text(), encoding='utf8')
        dmg = temporary / (name + '.dmg')
        run(['hdiutil', 'create', '-quiet', '-format', 'UDZO', '-fs', 'HFS+', '-volname',
             'MacPulse ' + report['version'], '-srcfolder', str(source), str(dmg)])
        if mode == 'developer-id':
            # Reuse the bundle's Developer ID certificate; names are not written to the manifest.
            signing = run(['codesign', '-dvv', str(staged_app)], check=False).stderr
            identity = next(s.split('=', 1)[1] for s in signing.splitlines() if s.startswith('Authority=Developer ID Application:'))
            run(['codesign', '--force', '--timestamp', '--sign', identity, str(dmg)])
            notarize(dmg, args.notary_profile, notary)
        run(['hdiutil', 'verify', '-quiet', str(dmg)])
        mount = temporary / 'mounted'; mount.mkdir()
        attachment = subprocess.run(['hdiutil', 'attach', '-readonly', '-nobrowse', '-mountpoint', str(mount), '-plist', str(dmg)], capture_output=True, check=True)
        plistlib.loads(attachment.stdout)
        try:
            mounted = verify(mount / 'MacPulse.app', mode, ['arm64', 'x86_64'])
            same = digest(mount / 'MacPulse.app/Contents/MacOS/MacPulse') == digest(app / 'Contents/MacOS/MacPulse')
            if not same or not (mount / 'Applications').is_symlink() or (mount / 'Applications').readlink() != Path('/Applications'):
                raise ValueError('DMG content verification failed')
        finally: run(['hdiutil', 'detach', '-quiet', str(mount)])
        assessment = run(['spctl', '--assess', '--type', 'execute', '--verbose=2', str(staged_app)], check=False)
        if mode == 'developer-id' and assessment.returncode != 0: raise ValueError('Gatekeeper did not accept the app')
        if mode == 'developer-id':
            run(['spctl', '--assess', '--type', 'open', '--context', 'context:primary-signature', str(dmg)])
        archive = temporary / (name + '.zip')
        run(['ditto', '--norsrc', '-c', '-k', '--keepParent', str(staged_app), str(archive)])
        report.update({'channel': args.channel, 'publicDistributionReady': mode == 'developer-id' and assessment.returncode == 0,
                       'notarization': notary, 'gatekeeperAccepted': assessment.returncode == 0,
                       'dmgContentVerified': same, 'userDataIncluded': False,
                       'files': [{'name': p.name, 'bytes': p.stat().st_size, 'sha256': digest(p)} for p in [dmg, archive]]})
        manifest = temporary / (name + '.json'); manifest.write_text(json.dumps(report, indent=2) + '\n')
        for src, dest in zip([dmg, archive, manifest], targets): src.rename(dest)
    print(json.dumps(report, indent=2))

if __name__ == '__main__':
    try: main()
    except (ValueError, OSError, subprocess.CalledProcessError, StopIteration) as error:
        print('Release gate failed: ' + str(error), file=sys.stderr); sys.exit(1)
