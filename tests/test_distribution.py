# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
"""Justified package boundaries: checksums, unexpected content, unsafe paths."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('candidate', Path(__file__).resolve().parents[1] / 'tools/build_offline_candidate.py')
candidate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate)


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / 'sample.txt').write_bytes(b'synthetic\n')
        (self.root / 'SHA256SUMS').write_text(candidate.digest(self.root / 'sample.txt')+'  sample.txt\n')

    def tearDown(self):
        self.temp.cleanup()

    def test_mit_requires_exact_approved_scope_and_notice(self):
        import json
        docs = self.root / 'docs'
        docs.mkdir()
        notice = 'Copyright (c) 2026 Fictional Test Holder'
        (self.root / 'LICENSE').write_text(notice)
        rights = dict(license_applied=True, confirmed_rightsholder_authority_received=True,
                      copyright_notice=notice, cleared_for_public_distribution=['LICENSE', 'sample.txt'],
                      pending_holder_authorization=[])
        ledger = docs / 'distribution-rights.json'
        ledger.write_text(json.dumps(rights))
        version = {'license_status': 'MIT'}
        self.assertEqual(candidate.license_status(self.root, ['LICENSE', 'sample.txt'], version), 'MIT')
        with self.assertRaisesRegex(ValueError, 'uncleared'):
            candidate.license_status(self.root, ['LICENSE', 'sample.txt', 'uncleared.txt'], version)
        rights['pending_holder_authorization'] = ['sample.txt']
        ledger.write_text(json.dumps(rights))
        with self.assertRaisesRegex(ValueError, 'uncleared'):
            candidate.license_status(self.root, ['LICENSE', 'sample.txt'], version)
        rights['pending_holder_authorization'] = []
        ledger.write_text(json.dumps(rights))
        (self.root / 'LICENSE').write_text('different notice')
        with self.assertRaisesRegex(ValueError, 'copyright notice'):
            candidate.license_status(self.root, ['LICENSE', 'sample.txt'], version)
        self.assertEqual(candidate.license_status(self.root, ['LICENSE'], {}), 'pending')

    def test_community_scope_keeps_offline_assets_and_excludes_real_observation(self):
        import json
        root = Path(__file__).resolve().parents[1]
        policy = json.loads((root / 'docs/distribution-files.json').read_text())
        included = set(policy['include'])
        excluded = set(policy['excluded_tracked'])
        required = {'LICENSE', 'README.md', 'README.es.md', 'docs/GETTING-STARTED.md',
                    'docs/COMPATIBILITY.md', 'docs/TOOL-VALIDATION-MATRIX.md',
                    'examples/Invoke-CommunityOfflineDemo.ps1', 'tests/CommunityDemo.Tests.ps1',
                    'tests/fixtures/unified-report.json', 'docs/demo/community-report.html',
                    'docs/demo/community-desktop.png', 'docs/demo/community-narrow.png',
                    'tools/build_offline_candidate.py', 'tests/test_distribution.py'}
        observed = {'tests/fixtures/phase14-datastore-observation.json', 'tests/Phase14.Tests.ps1'}
        self.assertTrue(required <= included)
        self.assertFalse(observed & included)
        self.assertTrue(observed <= excluded)
        self.assertFalse(included & excluded)
        version = json.loads((root / 'VERSION.json').read_text())
        self.assertEqual(candidate.license_status(root, policy['include'], version), 'MIT')

    def test_valid_manifest(self):
        self.assertEqual(candidate.verify(self.root), 1)

    def test_tamper_rejected(self):
        (self.root / 'sample.txt').write_bytes(b'changed')
        with self.assertRaises(ValueError):
            candidate.verify(self.root)

    def test_unlisted_file_rejected(self):
        (self.root / 'extra.txt').write_bytes(b'not allowed')
        with self.assertRaises(ValueError):
            candidate.verify(self.root)

    def test_traversal_rejected(self):
        with self.assertRaises(ValueError):
            candidate.safe_source(self.root, '../outside')

    def test_symlink_rejected(self):
        (self.root / 'link').symlink_to(self.root / 'sample.txt')
        with self.assertRaises(ValueError):
            candidate.safe_source(self.root, 'link')

    def test_build_accepts_parent_relative_output(self):
        # The documented ../staging path must normalize before containment checks.
        import subprocess
        repo = self.root / 'repo'
        repo.mkdir()
        subprocess.run(['git', 'init', '-q', str(repo)], check=True)
        (repo / 'uncommitted.txt').write_text('fixture')
        with self.assertRaisesRegex(ValueError, 'clean committed'):
            candidate.build(repo, repo / '..' / 'staging')
        self.assertFalse((self.root / 'staging').exists())


if __name__ == '__main__':
    unittest.main()
