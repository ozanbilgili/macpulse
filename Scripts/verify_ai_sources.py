#!/usr/bin/env python3
"""Read-only local acceptance: numeric indexes and independent token totals.
Never reads credentials, transcripts or Keychain; never outputs source paths/names.
"""
import calendar
import datetime as dt
import hashlib
import json
import math
import os
import pathlib
import plistlib
import re
import sqlite3

ROOT = pathlib.Path(__file__).resolve().parent.parent
HOME = pathlib.Path.home()
UTC = dt.timezone.utc
NOW = dt.datetime.now(UTC)

def load(path):
    return json.loads(path.read_bytes())

def month(anchor, n):
    number = anchor.year * 12 + anchor.month - 1 + n
    year, m = divmod(number, 12)
    return anchor.replace(year=year, month=m + 1, day=min(anchor.day, calendar.monthrange(year, m + 1)[1]))

def format_tokens(n):
    for divisor, unit in [(10**9, 'milyar'), (10**6, 'milyon'), (10**3, 'bin')]:
        if n >= divisor and (divisor != 1000 or n >= 10000):
            v = n / divisor
            digits = 0 if v >= 100 else 1 if v >= 10 else 2
            return f'{v:.{digits}f}'.replace('.', ',') + ' ' + unit
    return str(n)

private_path = HOME / 'Library/Application Support/MacPulse/ai-token-index.json'
private = load(private_path)
reference = load(HOME / '.cache/claude-hesaplar/tokens-index.json')
common = private.keys() & reference.keys()
same = sum(private[k]['buckets'] == reference[k]['buckets'] for k in common)
# The reference index historically stores zero mtime/size. Actual filesystem
# metadata determines which captured prefixes are still stable.
stable = []
changing = 0
different_offsets = 0
for k in common:
    try:
        stat = pathlib.Path(k).stat()
        frozen = stat.st_size == private[k]['size'] and abs(stat.st_mtime - private[k]['mtime']) < 0.001
    except OSError:
        frozen = False
    same_prefix = private[k]['offset'] == reference[k]['offset']
    if not same_prefix:
        different_offsets += 1
    if frozen and same_prefix:
        stable.append(k)
    elif not frozen:
        changing += 1
stable_same = sum(private[k]['buckets'] == reference[k]['buckets'] for k in stable)

accounts = [(1, HOME / '.claude', HOME / '.claude.json')]
for folder in HOME.iterdir():
    match = re.fullmatch(r'\.claude-hesap([0-9]+)', folder.name)
    if match and folder.is_dir() and int(match[1]) >= 2:
        accounts.append((int(match[1]), folder, folder / '.claude.json'))
periods, owners = {}, {}
for n, folder, config in accounts:
    try:
        raw = load(config)['oauthAccount']['subscriptionCreatedAt']
        anchor = dt.datetime.fromisoformat(raw.replace('Z', '+00:00')).astimezone(UTC)
        offset = max(0, (NOW.year-anchor.year)*12 + NOW.month-anchor.month)
        while offset > 0 and month(anchor, offset) > NOW: offset -= 1
        while month(anchor, offset+1) <= NOW: offset += 1
        periods[n] = (month(anchor, offset).timestamp(), month(anchor, offset+1).timestamp())
    except (OSError, KeyError, TypeError, ValueError):
        pass
    session_dir = folder / 'session-env'
    if session_dir.is_dir():
        for entry in session_dir.iterdir():
            try: owners.setdefault(entry.name, []).append((entry.stat().st_birthtime, n))
            except OSError: pass
for values in owners.values(): values.sort()

def aggregate(index):
    counts = {n:[0,0,0,0] for n in periods}
    unattributed = [0,0,0,0]
    latest = max((v[0] for v in periods.values()), default=NOW.timestamp())
    for path, tally in index.items():
        p = pathlib.Path(path)
        parts = p.parts
        sid = parts[parts.index('subagents')-1] if 'subagents' in parts else p.stem
        who = owners.get(sid, [])
        for raw_hour, bucket in tally['buckets'].items():
            hour = int(raw_hour)
            if len(bucket)!=4 or min(bucket)<0: continue
            chosen = [row for row in who if row[0] <= hour+3600]
            n = (chosen[-1] if chosen else who[0])[1] if who else None
            if n in periods:
                start, end = periods[n]
                if math.floor(start/3600)*3600 <= hour < end:
                    counts[n] = [x+y for x,y in zip(counts[n],bucket)]
            elif n is None and hour >= math.floor(latest/3600)*3600:
                unattributed = [x+y for x,y in zip(unattributed,bucket)]
    return counts, unattributed

counts, unattributed = aggregate(private)
reference_counts, _ = aggregate(reference)
source_comparison = {
    'privateFiles': len(private), 'referenceFiles': len(reference), 'commonFiles': len(common),
    'sameTokenBuckets': same, 'stableFiles': len(stable), 'stableFilesWithSameTokenBuckets': stable_same,
    'changingFiles': changing, 'differentOffsetFiles': different_offsets, 'stableSourceParity': len(stable)>0 and stable_same==len(stable),
    'privateIndexMode': oct(private_path.stat().st_mode & 0o777),
    'referenceFullTotalsEqualAtCapture': counts == reference_counts,
    'note': 'Live transcripts and the two independent scan times can change current-hour totals.'
}
expected = {
    'accounts': [{ 'account': n, 'total': sum(v), 'formattedTotal': format_tokens(sum(v)) + ' token',
                   'output': v[1], 'formattedOutput': 'Çıktı ' + format_tokens(v[1]), 'breakdown': v } for n,v in sorted(counts.items())],
    'unattributed': sum(unattributed)
}

baseline = load(ROOT / 'artifacts/phase-9-before-upgrade.json')
db = HOME / 'Library/Application Support/MacPulse/history.sqlite'
connection = sqlite3.connect('file:'+str(db)+'?mode=ro',uri=True)
actual = {str(start):hashlib.sha256(payload.encode() if isinstance(payload,str) else payload).hexdigest() for start,payload in connection.execute('SELECT start,payload FROM minutes')}
preferences = plistlib.loads((HOME/'Library/Preferences/local.macpulse.desktop.plist').read_bytes())
pref = json.loads(preferences['monitor.preferences.v1'])
base_preserved = all(pref.get(k)==v for k,v in baseline['basePreferences'].items())
source_root = HOME / 'Developer/Usage'
ref_preserved = all(hashlib.sha256((source_root/k).read_bytes()).hexdigest()==digest for k,digest in baseline['referenceSources'].items())
upgrade = {
    'completedMinutesChecked':len(baseline['frozenMinutes']),
    'completedMinutesPreserved':sum(actual.get(k)==digest for k,digest in baseline['frozenMinutes'].items()),
    'basePreferencesPreserved':base_preserved, 'referenceSourceFilesPreserved':ref_preserved,
    'quickCheck':connection.execute('PRAGMA quick_check').fetchone()[0],
    'schema':connection.execute('PRAGMA user_version').fetchone()[0],
    'journalMode':connection.execute('PRAGMA journal_mode').fetchone()[0], 'databaseMode':oct(db.stat().st_mode&0o777)
}
connection.close()
report = {'sourceComparison':source_comparison,'expectedUI':expected,'upgrade':upgrade,'capturedAt':NOW.isoformat()}
output = ROOT/'artifacts/phase-9-data-acceptance.json'
fd = os.open(output, os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
with os.fdopen(fd,'w') as file: json.dump(report,file,indent=2)
print(json.dumps(report))
assert source_comparison['stableSourceParity']
assert upgrade['completedMinutesChecked']==upgrade['completedMinutesPreserved']
assert base_preserved and ref_preserved and upgrade['quickCheck']=='ok'
