# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
"""Regressions for a self-contained public selection, including plain document references."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('public_content', Path(__file__).resolve().parents[1] / 'tools/check_public_content.py')
public_content = importlib.util.module_from_spec(spec)
spec.loader.exec_module(public_content)


class PublicContentTests(unittest.TestCase):
    def test_public_tree_is_self_contained(self):
        root = Path(__file__).resolve().parents[1]
        self.assertEqual(public_content.check(root), [])

    def test_excluded_document_reference_is_rejected_even_if_file_exists(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'docs').mkdir()
            (root / 'hidden.md').write_text('Internal only')
            (root / 'docs/distribution-files.json').write_text(json.dumps({'include': ['README.md', 'docs/distribution-files.json']}))
            readme = root / 'README.md'
            readme.write_text('[internal](hidden.md) and `hidden.md`; [official](https://example.invalid/guide.md)')
            errors = public_content.check(root)
            self.assertTrue(any('unavailable link hidden.md' in e for e in errors))
            self.assertTrue(any('unavailable document hidden.md' in e for e in errors))
            self.assertFalse(any('guide.md' in e for e in errors))
            readme.write_text('[parent](../outside.md)')
            self.assertTrue(public_content.check(root))
            readme.write_text('[self](README.md) and [external](https://example.invalid/guide.md)')
            self.assertEqual(public_content.check(root), [])
            (root / 'tool.ps1').write_text('<# See hidden.md for help #>')
            (root / 'docs/distribution-files.json').write_text(json.dumps({'include': ['README.md', 'tool.ps1', 'docs/distribution-files.json']}))
            self.assertTrue(any('tool.ps1:' in e for e in public_content.check(root)))


if __name__ == '__main__':
    unittest.main()
