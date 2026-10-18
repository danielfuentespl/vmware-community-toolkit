#!/usr/bin/env python3
# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
"""Build or verify a local review package using only Python's standard library."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

GENERATED = {'BUILD-METADATA.json', 'SHA256SUMS'}


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def safe_source(root, name):
    rel = Path(name)
    if rel.is_absolute() or '..' in rel.parts or not rel.parts or rel.parts[0] == '.git':
        raise ValueError('Unsafe distribution path')
    path = root / rel
    if any(p.is_symlink() for p in [path, *path.parents]):
        raise ValueError('Symlinks are not distributable')
    if not path.is_file():
        raise ValueError('Missing distribution file')
    return path


def verify(target):
    target = Path(target)
    if target.is_symlink():
        raise ValueError('Symlink package root')
    manifest = target / 'SHA256SUMS'
    if manifest.is_symlink():
        raise ValueError('Symlink manifest')
    expected = {}
    for line in manifest.read_text(encoding='utf-8').splitlines():
        sha, name = line.split('  ', 1)
        if name in expected or len(sha) != 64 or any(c not in '0123456789abcdef' for c in sha):
            raise ValueError('Invalid manifest')
        expected[name] = sha
    actual = {p.relative_to(target).as_posix() for p in target.rglob('*') if p.is_file() or p.is_symlink()}
    if actual != set(expected) | {'SHA256SUMS'}:
        raise ValueError('Package file set differs from manifest')
    for name, sha in expected.items():
        if digest(safe_source(target, name)) != sha:
            raise ValueError('Package checksum mismatch')
    return len(expected)


def license_status(root, names, version):
    """Never infer a license from file presence or silently include uncleared files."""
    status = version.get('license_status', 'pending')
    if status != 'MIT':
        return 'pending'
    rights = json.loads((root / 'docs/distribution-rights.json').read_text())
    if (not rights.get('license_applied')
            or not rights.get('confirmed_rightsholder_authority_received')
            or not rights.get('copyright_notice')
            or set(names) != set(rights.get('cleared_for_public_distribution', []))
            or set(names) & set(rights.get('pending_holder_authorization', []))
            or 'LICENSE' not in names):
        raise ValueError('MIT package contains uncleared or inconsistent scope')
    license_text = safe_source(root, 'LICENSE').read_text(encoding='utf-8')
    if rights['copyright_notice'] not in license_text:
        raise ValueError('MIT copyright notice differs from approved scope')
    return 'MIT'


def build(root, target):
    root = root.resolve()
    # Validate the lexical output path before resolve, to reject linked parents.
    target = target.absolute()
    if any(p.is_symlink() for p in [target, *target.parents]):
        raise ValueError('Symlink output path')
    target = target.resolve()
    if target == root or root in target.parents:
        raise ValueError('Staging must be outside the repository')
    if target.exists():
        raise ValueError('Output already exists; use a new empty destination')
    def git(*args):
        return subprocess.check_output(['git', '-C', str(root), *args], text=True).strip()
    if git('status', '--porcelain'):
        raise ValueError('Build requires a clean committed working tree')
    policy = json.loads((root / 'docs/distribution-files.json').read_text())
    names = policy['include']
    tracked = set(git('ls-files').splitlines())
    if len(names) != len(set(names)) or not set(names) <= tracked or set(names) & GENERATED:
        raise ValueError('Invalid distribution allowlist')
    sources = [(name, safe_source(root, name)) for name in sorted(names)]
    version = json.loads((root / 'VERSION.json').read_text())
    approved_license = license_status(root, names, version)
    epoch = int(git('show', '-s', '--format=%ct', 'HEAD'))
    target.mkdir(parents=True, mode=0o700)
    for name, source in sources:
        out = target / name
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(source.read_bytes())
    metadata = {'version': version['version'], 'source_commit': git('rev-parse', 'HEAD'),
                'source_date_epoch': epoch, 'license_status': approved_license,
                'publication_authorized': False, 'real_vmware_validated': False}
    if approved_license == 'MIT':
        rights = json.loads((root / 'docs/distribution-rights.json').read_text())
        metadata['copyright_notice'] = rights['copyright_notice']
        metadata['license_scope'] = sorted(names)
        metadata['validation_note'] = 'No new VMware functional validation; consult retained source reports for limited prior observations.'
    (target / 'BUILD-METADATA.json').write_text(json.dumps(metadata, indent=2, sort_keys=True)+'\n', encoding='utf-8')
    paths = sorted(p for p in target.rglob('*') if p.is_file())
    (target / 'SHA256SUMS').write_text(''.join(f'{digest(p)}  {p.relative_to(target).as_posix()}\n' for p in paths), encoding='utf-8')
    for p in target.rglob('*'):
        os.chmod(p, 0o755 if p.is_dir() else 0o644)
        os.utime(p, (epoch, epoch))
    os.utime(target, (epoch, epoch))
    return verify(target)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--verify', action='store_true')
    args = parser.parse_args()
    count = verify(args.destination) if args.verify else build(Path(__file__).resolve().parents[1], args.destination)
    print(f'Verified {count} SHA-256 entries; local review only.')
