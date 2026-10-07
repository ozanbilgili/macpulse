#!/usr/bin/env python3
"""WCAG contrast calculation of the actual adaptive palette; not a VoiceOver certification."""
import argparse
import json
from pathlib import Path
import re

def luminance(rgb):
    linear = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in rgb]
    return sum(a * b for a, b in zip(linear, [0.2126, 0.7152, 0.0722]))

def contrast(a, b):
    first, second = sorted([luminance(a), luminance(b)])
    return (second + .05) / (first + .05)

def main():
    parser = argparse.ArgumentParser(description=__doc__); parser.add_argument('--output', required=True, type=Path); args = parser.parse_args()
    source = Path(__file__).resolve().parents[1] / 'Sources/MacPulse/Components.swift'
    palette = {name: [tuple(float(n) for n in value.split(',')) for value in [dark, light]]
               for name, dark, light in re.findall(r'static let (\w+) = adaptive\(\(([^)]+)\), \(([^)]+)\)\)', source.read_text())}
    results = []
    for theme, index in [('dark', 0), ('light', 1)]:
        for foreground in ['secondary', 'accent', 'cpu', 'memory', 'disk', 'network', 'battery', 'gpu']:
            for background in ['background', 'card', 'elevated']:
                ratio = contrast(palette[foreground][index], palette[background][index])
                results.append({'theme': theme, 'text': foreground, 'surface': background, 'contrast': ratio, 'AARegularText': ratio >= 4.5})
    report = {'accepted': all(r['AARegularText'] for r in results), 'scope': 'opaque palette text/surfaces; 4.5:1 normal text', 'checks': results}
    args.output.write_text(json.dumps(report, indent=2) + '\n'); args.output.chmod(0o600)
    print(json.dumps({'accepted': report['accepted'], 'checks': len(results), 'failures': [r for r in results if not r['AARegularText']]}))

if __name__ == '__main__': main()
