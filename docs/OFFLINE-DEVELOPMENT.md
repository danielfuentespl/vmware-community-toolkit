# Offline development

Offline development uses no VMware infrastructure. Development requires an existing PowerShell installation; tests additionally require existing Pester and PSScriptAnalyzer. Do not install components automatically. Run from the repository root:

```powershell
./tests/Invoke-Validation.ps1
./examples/Invoke-OfflineExamples.ps1
```

The validation runner performs static analysis and simulation only. PowerCLI is neither imported nor required by the command doubles. Do not run the lab runner with -Connect during offline development. DNS remains locked to -WhatIf, including when -Confirm:$false is supplied; even WhatIf queries would need authorized infrastructure outside simulations.

## Local VCF exports

The four original PageOf analyzers accept mutually exclusive -Response (one parsed page), -Pages (complete parsed page collection), or -Path / -LiteralPath (one local UTF-8 JSON file). SourceVersion is mandatory and descriptive only.

```powershell
./scripts/VCF/Get-VCFInventory.ps1 -Path ./tests/fixtures/vcf-domains-pages.json -SourceVersion unverified-fixture
```

The file may contain one PageOf object or an array of all PageOf objects. Arrays are a toolkit export format, not an API response endpoint. No API requests, pagination parameters or export collection are implemented. Retain original per-page metadata. All pages must have equal totals, unique contiguous zero-based page numbers, and aggregate counts matching totalElements. Input order is normalized. A single incomplete page is rejected. pageSize, when present, must be integral and at least the page's element count. These checks do not prove a consistent server snapshot or detect every duplicate entity across pages.

Strict input: 1 byte–16 MiB, JSON depth at most 64, at most 10,000 pages; malformed UTF-8, comments, trailing commas, duplicate/case-colliding keys, API error envelopes, incomplete records and symlink paths are rejected. Local trusted regular files only; network mounts cannot be detected reliably on every OS. Keep directories trusted against concurrent replacement; this is not a filesystem sandbox. Large exports must be reduced securely outside the tool; never truncate page sets and claim completeness.

Export data may contain private infrastructure. Keep actual exports and generated results outside Git in restricted local directories. Projected names/addresses are still sensitive: allowlisted output is not anonymization. Never attach raw exports, tokens, certificates or provider error text to public issues. Tools emit no success records after a projection error; empty successful input emits no rows. Zero rows do not establish sufficient privileges or complete inventory.

## Fixture provenance

See tests/fixtures/CONTRACTS.md and VCF-SOURCES.json. Fixtures are fabricated from documented projection fields, not captured production responses, full schemas or evidence of VMware compatibility. Existing reference reviews are reused without new network access. No credentials, real names, private addresses or original quarantined code are needed.
