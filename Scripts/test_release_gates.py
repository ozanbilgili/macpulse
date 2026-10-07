#!/usr/bin/env python3
"""Behavioral tests of release fail-closed gates; no credentials, network, or signing."""
import copy
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import package_check as gates
from audit_accessibility import contrast

class ReleaseGates(unittest.TestCase):
    def manifest(self):
        return {'NSPrivacyTracking': False, 'NSPrivacyTrackingDomains': [], 'NSPrivacyCollectedDataTypes': [],
                'NSPrivacyAccessedAPITypes': [{'NSPrivacyAccessedAPIType': key, 'NSPrivacyAccessedAPITypeReasons': value} for key, value in gates.REASONS.items()]}
    def test_reviewed_local_manifest_passes(self):
        gates.privacy(self.manifest())
    def test_unreviewed_tracking_or_collection_is_rejected(self):
        for key, value in [('NSPrivacyTracking', True), ('NSPrivacyTrackingDomains', ['example.invalid']), ('NSPrivacyCollectedDataTypes', [{}])]:
            data = self.manifest(); data[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError): gates.privacy(data)
    def test_missing_or_duplicate_api_reason_is_rejected(self):
        for entries in [[], self.manifest()['NSPrivacyAccessedAPITypes'] * 2]:
            data = self.manifest(); data['NSPrivacyAccessedAPITypes'] = entries
            with self.assertRaises(ValueError): gates.privacy(data)
    def test_reason_for_write_capacity_cannot_substitute_for_display_capacity(self):
        data = self.manifest(); data['NSPrivacyAccessedAPITypes'][-1]['NSPrivacyAccessedAPITypeReasons'] = ['E174.1']
        with self.assertRaises(ValueError): gates.privacy(data)
    def test_ad_hoc_never_satisfies_distribution_signature(self):
        self.assertFalse(gates.signature_ready('Signature=adhoc\nCodeDirectory flags=0x10000(runtime)\nTimestamp=now'))
    def test_distribution_requires_runtime_and_timestamp(self):
        good = 'Authority=Developer ID Application: Test\nCodeDirectory flags=0x10000(runtime)\nTimestamp=Oct 7, 2026\n'
        self.assertTrue(gates.signature_ready(good))
        for bad in [good.replace('(runtime)', '(none)'), good.replace('Timestamp=Oct 7, 2026', 'Timestamp=none'), good.replace('Authority=Developer ID Application:', 'Authority=Apple Development:')]:
            self.assertFalse(gates.signature_ready(bad))
    def test_authority_name_containing_runtime_is_not_hardening(self):
        self.assertFalse(gates.signature_ready('Authority=Developer ID Application: runtime\nTimestamp=now\n'))
    def test_failed_swap_restores_previous_app(self):
        with tempfile.TemporaryDirectory(dir=gates.ROOT / '.build') as directory:
            root = Path(directory); previous = root / 'MacPulse.app'; previous.mkdir(); (previous / 'old').write_text('keep')
            stage = root / 'stage'; stage.mkdir()
            with patch.object(gates, 'preflight'), self.assertRaises(FileNotFoundError): gates.publish(stage / 'missing.app', previous)
            self.assertEqual((previous / 'old').read_text(), 'keep')
    def test_destination_outside_project_is_rejected_before_process_scan(self):
        with self.assertRaises(ValueError): gates.preflight(Path('/Applications'))
    def test_bundle_symlink_is_rejected_before_process_scan(self):
        with tempfile.TemporaryDirectory(dir=gates.ROOT / '.build') as directory:
            root = Path(directory); (root / 'MacPulse.app').symlink_to('/Applications/Other.app')
            with self.assertRaises(ValueError): gates.preflight(root)
    def test_contrast_uses_linear_srgb_known_black_white_ratio(self):
        self.assertAlmostEqual(contrast((0, 0, 0), (1, 1, 1)), 21)
        self.assertEqual(contrast((.5, .5, .5), (.5, .5, .5)), 1)

if __name__ == '__main__': unittest.main(verbosity=2)
