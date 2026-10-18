#!/usr/bin/env python3
# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
"""Download the two reviewed CI packages; verify bytes before extracting/importing.

These SHA-256 locks were checked against PSGallery's SHA-512 package metadata
on 2026-10-18. They are content locks, not independent publisher signatures.
Update versions and locks together after reviewing the official package/project.
"""
import argparse
import hashlib
import io
from pathlib import Path, PurePosixPath
import urllib.request
import xml.etree.ElementTree as ET
import zipfile


PACKAGES = (
    ('Pester', '6.2.0', 'e6ac7418d4f12500269aaca58ae56cf1caafbbf1afa2cec334e289d1cf50a239'),
    ('PSScriptAnalyzer', '1.25.0', '14e634c828eb98efb9f40b2918ba90f139ed5eccdf663a2a747736d996995d60'),
)
MAX_PACKAGE_BYTES = 32 * 1024 * 1024


def verified_members(data, name, version, expected_hash):
    """Validate content and identity without loading any module code."""
    if hashlib.sha256(data).hexdigest() != expected_hash:
        raise ValueError('CI dependency SHA-256 mismatch; nothing imported')
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        seen = set()
        members = []
        for entry in archive.infolist():
            path = PurePosixPath(entry.filename)
            if (path.is_absolute() or '..' in path.parts or '\\' in entry.filename
                    or ':' in entry.filename or not path.parts
                    or entry.filename.casefold() in seen
                    or (entry.external_attr >> 16) & 0o170000 == 0o120000):
                raise ValueError('Unsafe CI package member')
            seen.add(entry.filename.casefold())
            if not entry.is_dir():
                members.append((path, archive.read(entry)))
        metadata = ET.fromstring(archive.read(name + '.nuspec'))
        values = {node.tag.split('}')[-1]: node.text for node in metadata.iter()}
        if values.get('id') != name or values.get('version') != version:
            raise ValueError('Unexpected CI package identity')
        if any(node.tag.split('}')[-1] == 'dependency' for node in metadata.iter()):
            raise ValueError('Unreviewed transitive CI dependency')
        if PurePosixPath(name + '.psd1') not in {path for path, _ in members}:
            raise ValueError('CI module manifest missing')
        # Keep licenses/catalogs/module files; omit only NuGet transport metadata.
        return [(path, content) for path, content in members
                if path.parts[0] not in ('_rels', 'package', '[Content_Types].xml')
                and path.suffix != '.nuspec']


def install(module_root):
    module_root = Path(module_root)
    # Verify both packages completely before creating the fresh module directory.
    packages = []
    for name, version, digest in PACKAGES:
        url = f'https://www.powershellgallery.com/api/v2/package/{name}/{version}'
        with urllib.request.urlopen(url, timeout=90) as response:
            if not response.url.startswith('https://'):
                raise ValueError('HTTPS required for CI dependencies')
            data = response.read(MAX_PACKAGE_BYTES + 1)
        if len(data) > MAX_PACKAGE_BYTES:
            raise ValueError('CI dependency exceeds size limit')
        packages.append((name, version, verified_members(data, name, version, digest)))
    module_root.mkdir(parents=True, exist_ok=False)
    for name, version, members in packages:
        destination = module_root / name / version
        for path, content in members:
            target = destination.joinpath(*path.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            with target.open('xb') as stream:
                stream.write(content)
        print(f'Verified PSGallery package: {name} {version}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('module_root', type=Path, help='New user-owned CI module directory')
    install(parser.parse_args().module_root)
