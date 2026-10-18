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


class CiDependencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        module_spec = importlib.util.spec_from_file_location(
            'ci_dependencies', Path(__file__).resolve().parents[1] / 'tools/install_ci_dependencies.py')
        cls.ci = importlib.util.module_from_spec(module_spec)
        module_spec.loader.exec_module(cls.ci)

    def package(self, identity='Fixture', extra=None):
        import io
        import zipfile
        output = io.BytesIO()
        with zipfile.ZipFile(output, 'w') as archive:
            archive.writestr('Fixture.nuspec',
                '<package><metadata><id>' + identity + '</id><version>1.0</version>'
                + ('<dependencies><dependency id="unreviewed" /></dependencies>' if extra == 'dependency' else '')
                + '</metadata></package>')
            archive.writestr('Fixture.psd1', '@{}')
            if extra and extra != 'dependency':
                archive.writestr(extra, 'fictional')
        return output.getvalue()

    def test_hash_is_checked_before_parsing_or_import(self):
        with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
            self.ci.verified_members(b'not even a zip', 'Fixture', '1.0', '0' * 64)

    def test_verified_identity_and_module_content(self):
        import hashlib
        data = self.package()
        members = self.ci.verified_members(data, 'Fixture', '1.0', hashlib.sha256(data).hexdigest())
        self.assertEqual([str(path) for path, _ in members], ['Fixture.psd1'])
        for identity, extra in [('other', None), ('Fixture', 'dependency'), ('Fixture', '../escape')]:
            with self.subTest(identity=identity, extra=extra):
                data = self.package(identity, extra)
                with self.assertRaises(ValueError):
                    self.ci.verified_members(data, 'Fixture', '1.0', hashlib.sha256(data).hexdigest())

    def test_tampered_download_creates_no_module_directory(self):
        from unittest.mock import patch
        import io
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / 'modules'
            response = io.BytesIO(b'tampered fixture')
            response.url = 'https://www.powershellgallery.com/fictitious'
            with patch.object(self.ci.urllib.request, 'urlopen', return_value=response):
                with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
                    self.ci.install(destination)
            self.assertFalse(destination.exists())


if __name__ == '__main__':
    unittest.main()
