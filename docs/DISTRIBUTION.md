# Public source selection and reproducible packages

The positive list in docs/distribution-files.json defines every original source file included in this candidate. docs/distribution-rights.json records the same MIT scope under Copyright (c) 2026 Daniel Fuentes. The selection contains runtime, public tests and fictional fixtures, practical documentation, examples, demonstration assets, settings and contributor/CI files. No internal phase report, audit/decision plan, source catalog, real infrastructure export, private evidence or vendor dependency is shipped.

## Build from Git source

With existing Git and Python, a clean committed tree and a new destination outside the checkout:

```bash
python3 -B tools/build_offline_candidate.py ../staging/v0.1.0-rc5
python3 -B tools/build_offline_candidate.py ../staging/v0.1.0-rc5 --verify
```

Existing destinations, symlinks, traversal, dirty source, untracked input and an unapproved MIT scope/notice are rejected. New files require provenance/scope review before inclusion. Internal files tracked in a review checkout are not automatically selected; its Git history is not a public distribution. A future public source repository must use the approved positive list, under separately authorized preparation.

## Verify a supplied package

Inside a history-free candidate containing the generated manifest:

```bash
python3 -B tools/build_offline_candidate.py . --verify
```

The exact file set and hashes are checked, including extra files. `sha256sum --check SHA256SUMS` verifies listed hashes only. BUILD-METADATA records the original source commit, epoch, version, exact MIT scope and notice; publication stays false. SHA256SUMS covers all source files and generated metadata except itself; neither is a publisher signature or proof of legal origin. Git source checkouts do not need generated package files to run tests or the fictional demo.

Two builds from the same commit have identical file bytes/manifests and fixed timestamps, with files 0644, nested directories 0755 and restricted root 0700. No archive reproducibility or hosted release is claimed. Keep test output/caches outside the sealed candidate and use Python `-B`; verify again after local checks. Original fixtures/captures remain fictional. [Validation](../VALIDATION.md) describes local and prepared CI checks, and [license scope](LICENSE-SCOPE.md) distinguishes project MIT from external dependencies.
