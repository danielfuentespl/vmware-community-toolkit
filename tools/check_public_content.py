#!/usr/bin/env python3
# Copyright (c) 2026 Daniel Fuentes
# SPDX-License-Identifier: MIT
"""Check the positive public file set and local Markdown references without network access."""
import argparse
import json
import re
from pathlib import Path


def resolve_reference(root, document, target, names, allow_root=False):
    target = target.strip('<>').split('#', 1)[0]
    if not target or re.match(r'^[a-zA-Z][a-zA-Z0-9+.-]*:', target):
        return True
    if target.startswith('/') or '\\' in target:
        return False
    candidates = [document.parent / target]
    if allow_root:
        candidates.append(root / target)
    for path in candidates:
        try:
            relative = path.resolve().relative_to(root.resolve()).as_posix()
        except ValueError:
            continue
        if relative in names:
            return True
    return False


def check(root):
    root = Path(root).resolve()
    policy = json.loads((root / 'docs/distribution-files.json').read_text(encoding='utf-8'))
    listed = policy['include']
    names = set(listed)
    errors = []
    if len(listed) != len(names):
        errors.append('Duplicate public path')
    for name in sorted(names):
        path = root / name
        try:
            path.resolve().relative_to(root)
        except ValueError:
            errors.append(f'Unsafe public path: {name}')
            continue
        if path.is_symlink() or not path.is_file():
            errors.append(f'Missing/nonregular public path: {name}')
            continue
        if path.suffix == '.md':
            text = path.read_text(encoding='utf-8')
        elif path.suffix in ('.ps1', '.psm1'):
            # Get-Help is part of the user-facing documentation too.
            text = '\n'.join(re.findall(r'(?s)<#(.*?)#>', path.read_text(encoding='utf-8')))
        else:
            continue
        for match in re.finditer(r'\]\(([^)\s]+)\)', text):
            if not resolve_reference(root, path, match.group(1), names):
                errors.append(f'{name}: unavailable link {match.group(1)}')
        # Plain/backticked Markdown paths are also user-facing dependencies.
        without_urls = re.sub(r'https?://[^\s<>`)]+', '', text)
        for match in re.finditer(r'(?<![\w/])(?:\.\./|\./)?[A-Za-z0-9_./-]+\.md\b', without_urls):
            if not resolve_reference(root, path, match.group(), names, allow_root=True):
                errors.append(f'{name}: unavailable document {match.group()}')
    return sorted(set(errors))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', nargs='?', type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    findings = check(args.root)
    if findings:
        print('\n'.join(findings))
        raise SystemExit(1)
    print('Public file set and local Markdown references verified; external URLs not fetched.')
