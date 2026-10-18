# Compatibility and validation

Static analysis, offline simulation/local processing and real VMware observations are distinct. [The per-tool matrix](TOOL-VALIDATION-MATRIX.md) records exact scope for all 25 entry points and the auxiliary lab harness. A passing mock, documented cmdlet or MIT grant is not VMware support certification.

## Executed environment

| Component | Observed version / scope |
|---|---|
| PowerShell | 7.6.7, Linux x64; source target 7.4+, other runtimes/OS not executed |
| PowerCLI Core / Cis.Core / Common / Sdk / OpenAPI / Vcf.Sso | 13.5.1.25718932 each, installed externally in user scope |
| VMware.Vim | 9.1.0.25718932 |
| vCenter | 8.0.3 build 24022515 |
| Managed and direct ESXi 8 | 8.0.3 build 24022510, same host |
| Direct ESXi 9 | 9.0.1 build 24957456; unverified third-party/community media/profile provenance |
| Local automated checks | Pester 6.2.0, PSScriptAnalyzer 1.25.0, Python 3.14.7, Gitleaks 8.30.1 |

The exact observations do not certify Omarchy, HCL, production use, other builds, Windows/macOS or large inventories. Runtime/module versions and vendor support must be checked independently for each authorized environment.

## Real coverage and limits

55 recorded cases: 41 PASS, 12 PARTIAL, two BLOCKED. ESXi 8 VM/Tools/snapshot/configuration readers produced positive observations both through vCenter and directly. Certificate scopes require vCenter; direct ESXi is intentionally unsupported. Snapshot age used actual timestamps and a short threshold, not a genuinely seven-day-old snapshot. Inventory comparison verified Added/PowerState/CPU/RAM and restoration; Removed remains unverified. Central Inventory/Operations worked with a short age threshold; Security/All remain partial for unknown/unsupported evidence. HTML generation preserves those states.

Thirteen direct ESXi 8 readers ran with scoped ReadOnly grants and a real permission denial was observed. This does not establish universal minimum permissions or a vCenter SSO least-privilege role. ESXi 9 has no positive VM/snapshot coverage and its unauthenticated media limits all product-compatibility conclusions. DNS modification and the auxiliary lab connection harness are not functionally validated.

## VCF: offline only

**No analyzer has been functionally validated against a real VCF deployment.** The seven adapters accept local JSON under documented projection profiles. `latest` vendor references and SourceVersion labels do not establish VCF 5.2.x, 9.0.x or 9.1.x build compatibility. Domain health, full BOM, entitlement, certificate trust and global security/compliance cannot be inferred from these subsets. Alert timestamp units remain Unknown when not evidenced. See [API/profile matrix](VCF-API-MATRIX.md) and [strict response handling](VCF-CONTRACT-REVIEW.md).

## Automated checks and community reports

The public suite runs 251 Pester cases on doubles/fictional fixtures and ten standard-library Python tests. Analysis and simulation remain separate from the real observations above. The prepared Ubuntu CI workflow has not run on GitHub; its commands have been exercised locally. No wider runtime certification is implied. [Validation procedure](../VALIDATION.md) and [community testing](COMMUNITY-TESTING.md) explain how to report independently authorized, sanitized results.
