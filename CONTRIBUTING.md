# Contributing

Thank you for helping improve VMware Community Toolkit. Use the local issue and pull-request templates when the project is made available. Describe the user problem and proposed behavior before broad changes; keep fixes focused and preserve existing public parameters and output contracts.

## Development

Use an existing PowerShell environment with Pester 6.2.0 and PSScriptAnalyzer 1.25.0. Python tests use the standard library; Git is needed for one temporary-repository test. [Development guidance](docs/OFFLINE-DEVELOPMENT.md) explains fictional fixtures and strict VCF export handling.

```powershell
./tests/Invoke-Validation.ps1
```

```bash
python3 -B -m unittest discover -s tests -p 'test_*.py'
python3 -B tools/check_public_content.py
```

Run configured analysis and redacted Gitleaks tree/history scans with approved existing tools. Never enable real VMware connections in automated tests. Add meaningful regression tests for changed behavior, including partial failures and withheld output; avoid tests that merely mirror implementation.

## Reporting bugs and compatibility

Include commit/version, PowerShell/OS/architecture, tool and sanitized syntax, expected/actual behavior and whether the result is static, simulated or a real authorized observation. Provide a minimal fictional fixture, not a production export. Keep passwords, tokens, accounts, hostnames, IP addresses, paths, raw exceptions and original screenshots private. Report suspected secrets using [SECURITY](SECURITY.md), not a public issue.

Use the [community laboratory procedure](docs/COMMUNITY-TESTING.md) and [result template](docs/TEST-RESULT-TEMPLATE.md) for real observations. Record exact product/build/module versions, endpoint type, effective permissions and what was compared in the matching client scope/time. Include failures, Unknown and NotRun. Contributor reports stay unverified until reviewed; one passing combination does not establish general compatibility. VCF remains offline-only until separately reviewed functional evidence exists.

## Safety and provenance

Require explicit Server connections, normal TLS validation and no hidden login or credential storage. Preserve the central fixed read-only allowlist and atomic per-tool result handling. DNS writes remain locked to WhatIf and excluded from central execution. Never add automatic installs, real-infrastructure CI, arbitrary script execution, invented API endpoints or security verdicts without documented criteria.

Contribute only original material you are authorized to distribute under MIT, or separately reviewed third-party material with verifiable compatible rights and all required notices. Identify origin, author, official contract references and any relevant restrictions. Do not submit corporate/quarantined code, real infrastructure data or captures. AI assistance and Git identity do not establish third-party ownership. Retain Copyright (c) 2026 Daniel Fuentes and LICENSE for existing substantial portions; preserve valid contributor/third-party notices without attributing others' work to the maintainer.

## Pull requests

Describe trigger, before/after behavior and any contract impact. Update both READMEs and relevant examples/contracts together; preserve explicit connection, TLS, output, memory-budget and safe-file boundaries. State exact tests run and limits, and distinguish simulation from real VMware testing. Do not put private logs or credentials in commits, artifacts or review comments. [Publication/build mechanics](docs/DISTRIBUTION.md) describe the positive public allowlist; adding a file also requires scope/provenance review.
