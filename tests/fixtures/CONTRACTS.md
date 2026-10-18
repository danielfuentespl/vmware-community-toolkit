# Synthetic contract fixtures

All distributed fixtures are invented; real infrastructure projections and observation-dependent private tests are excluded. example.invalid and 192.0.2.0/24 are documentation identifiers. No VMware capture or legacy code is included.

VCF representative fixtures and their official source references are recorded in VCF-SOURCES.json and ../../docs/VCF-CONTRACT-REVIEW.md. The *-pages.json arrays split the corresponding representative elements across two pages; they model the toolkit's complete offline export container. They do not claim an endpoint returns arrays of pages. Optional response fields are deliberately absent. Negative fixtures/tests cover error markers, missing data, inconsistent totals and ambiguous JSON. The current latest reference is not a pinned product release contract; all product_version_verified values remain false.

powercli-projections.json models only the properties consumed by the reports. It is not a REST contract, full PowerCLI serialization, or real VIServer/VMHost type. Official command references reused from earlier review:

- [Get-VM](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/commands/get-vm)
- [Get-Snapshot](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/commands/get-snapshot)
- [Get-VMHostNetwork](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/commands/get-vmhostnetwork)
- [VIServer](https://developer.broadcom.com/powercli/latest/vmware.vimautomation.core/structures/vmware.vimautomation.vicore.types.v1.viserver)

Expected simulation: two VM records, two zero-size snapshot records (one per VM), two DNS records with empty DNS/search lists. UnauthorizedAccessException doubles represent denied reads without asserting a vendor fault type or verified minimum role. Existing tests cover empty inventories and partial failures. PowerCLI cmdlets abstract API traversal; no REST pagination is added to these reports. VCF pagination alone uses documented PageOf metadata. Dates and counts are deterministic. SourceVersion fixture labels are not release numbers.

## Phase 7 fixtures

phase7-projections.json contains only synthetic selective views and PowerCLI property subsets. Exact references, fields, semantics, expected results and endpoint limitations are in ../../docs/POWERCLI-CONTRACTS.md. No captured responses, certificate PEM, tokens, production IDs or licensed vendor examples are included. Tests mutate copies for numeric/type/permission/duplicate/clock failures. None establishes functional compatibility.

## Phase 8 local processing fixtures

unified-report.json reuses only the documented output fields of existing toolkit models. inventory-before.json and inventory-after.json use the toolkit's new envelope contract, not an invented VMware API. All identifiers and example.invalid labels are fabricated. Dates include explicit offsets to test UTC normalization; the VM with unchanged stable ID is renamed deliberately. Expected five comparison rows: three field changes, one added ID and one removed ID. See ../../docs/UNIFIED-REPORTING.md. No credentials, vendor captures or inherited code are present.

## Phase 9 ESXi configuration observations

esxi-audit-projections.json is a fabricated subset of host/config/service/firewall/advanced-setting properties verified in the official references in ../../docs/ESXI-AUDIT-CONTRACTS.md. It is not a real API capture or PowerCLI CLR serialization. esxi-audit-report.json contains plain invented toolkit output rows for optional HTML sections. Service/rule/protocol fixture labels do not claim installed product identities or enum compatibility. No credentials, private infrastructure, vendor examples or inherited code are included. Tests create suspicious strings only as clearly fictitious negative cases and verify they are withheld.

## Phase 10 runner seam

runner-results.json contains invented, minimal output DTOs of the existing read scripts, not VMware API responses. Runner.Tests supplies them through a private mocked script-invocation seam; production accepts no fixture/script-path parameter. Public selection, status, cache/budget and HTML integration execute locally. The shared snapshot age helper uses the same existing field contract and regression suite as Get-OldSnapshots. Fixture IDs, example.invalid labels and documentation addresses are unrelated to real infrastructure. No credential, real connection object, inherited code or new vendor schema is included.
