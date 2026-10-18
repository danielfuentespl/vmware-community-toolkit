# Fictional, reproducible demonstrations

Limited real observations and their constraints are summarized in [the compatibility matrix](../docs/TOOL-VALIDATION-MATRIX.md). Examples and public demo data remain fictional. Use a separately authorized explicit connection and trusted TLS for any future lab run. Native runner Completed/Success means query execution, not complete functional coverage, compliance or health. Empty objects can leave validation PARTIAL; package-wide RealVmwareValidated remains false.

Run from the complete toolkit root with existing PowerShell. Nothing here installs software or connects to VMware. Invented VM/snapshot/ESXi records are **output projections**, not results of a live query. All examples remain simulation/local processing; approved real exports can still contain sensitive metadata and belong outside Git.

## One command for all six demonstrations

```powershell
$demoPath = Join-Path ([IO.Path]::GetTempPath()) ('vmware-toolkit-demo-' + [guid]::NewGuid().ToString('N') + '.html')
$demo = ./examples/Invoke-CommunityOfflineDemo.ps1 -OutputPath $demoPath
```

The script reads bundled fixtures, returns the following collections, and creates one new portable HTML file. It never supplies a fake Server to a live command, loads PowerCLI or attempts authentication. The parent output directory must exist; files are never overwritten. Temporary output is suitable only for these fictional examples.

### VM inventory

```powershell
$demo.Inventory | Select-Object VM, PowerState, NumCpu, MemoryGB, VMHost
```

Expected: one invented VM, two CPUs and 4 GiB. The provider behavior itself is exercised with doubles in Toolkit.Tests.ps1 and PowerCLI.Fixtures.Tests.ps1, not by this DTO display.

### Snapshots

```powershell
$demo.Snapshots | Select-Object VM, Snapshot, Created, SizeGB
```

Expected: one invented snapshot of 2 GiB. The HTML evaluates its age at the fixed fictional capture date, 2026-10-17. No snapshot is created or removed. Get-OldSnapshots filtering has separate mocked regressions.

### ESXi configuration/security observations

```powershell
$demo.EsxiAudit.HostSecurity
$demo.EsxiAudit.HostFirewall
$demo.EsxiAudit.HostSyslog
$demo.EsxiAudit.HostTime
$demo.EsxiAudit.HostAdvancedSettings
```

These are fabricated configuration observations, never vulnerability findings. For a standalone fictional audit HTML, use the existing example with another new filename:

```powershell
$auditPath = Join-Path ([IO.Path]::GetTempPath()) ('vmware-audit-' + [guid]::NewGuid().ToString('N') + '.html')
./examples/Invoke-EsxiAuditOfflineExample.ps1 -OutputPath $auditPath
```

### Inventory comparison

```powershell
$before = Get-Content ./tests/fixtures/inventory-before.json -Raw | ConvertFrom-Json
$after = Get-Content ./tests/fixtures/inventory-after.json -Raw | ConvertFrom-Json
$changes = @(./scripts/Reporting/Compare-vSphereInventory.ps1 -Baseline $before -Current $after)
$changes
```

Expected: five observations for the fictional captures. ScopeId, IdentityKind and SelectionId must be comparable; missing data is not silently treated as a real change. For optional CSV use a new CsvPath in a trusted existing directory. Never match names across unrelated vCenters. See docs/UNIFIED-REPORTING.md.

### HTML report

```powershell
$demo.Report
Get-Content -LiteralPath $demo.Report.Path -TotalCount 1
```

Expected: OfflineRendering receipt, RealVmwareValidated=false and 15 source-specific data sections. Seven original models, five ESXi collections and three VCF collections are supplied. Central-run execution rows are absent because no central VMware run occurred. Open the file locally in a browser; it has no external assets. The checked-in fictional result and actual local-browser PNGs are documented in docs/demo/README.md. A separate existing comparison/HTML example remains available as Invoke-UnifiedOfflineExample.ps1 with OutputDirectory in an existing private directory and unused health.html/changes.csv names.

### VCF analyzers

```powershell
./examples/Invoke-OfflineExamples.ps1
$demo.VCF.Inventory
$demo.VCF.Health
$demo.VCF.Versions
$demo.VCF.Certificates
$demo.VCF.LifecycleStatus
$demo.VCF.OperationsAlerts
$demo.VCF.LicensingReport
```

The existing example runs the four original analyzers; the combined demo runs all seven. To run the new local-file analyzers independently:

```powershell
./scripts/VCF/Get-VCFLifecycleStatus.ps1 -Path ./tests/fixtures/vcf-lifecycle-phase12.json -SourceVersion 'fictional-unverified'
./scripts/VCF/Get-VCFOperationsAlerts.ps1 -Path ./tests/fixtures/vcf-alerts-phase12.json -SourceVersion 'fictional-unverified'
./scripts/VCF/Get-VCFLicensingReport.ps1 -Path ./tests/fixtures/vcf-licensing-phase12.json -SourceVersion 'fictional-unverified'
```

Expected for these three: two domain observations, two alerts and one SYSTEM licensing observation. Assessment stays Unknown, exact VCF 9.x build support is unverified and alert timestamp units are not guessed. Official sources and strict envelope/pagination rules: docs/VCF-API-MATRIX.md.

## Actual tools under provider doubles

With existing Pester, use the relevant suites rather than pretending a fake connection is a live Server:

```powershell
Invoke-Pester -Path ./tests/Toolkit.Tests.ps1,./tests/PowerCLI.Fixtures.Tests.ps1,./tests/EsxiAudit.Tests.ps1,./tests/Runner.Tests.ps1 -Output Detailed
```

For a future authorized real connection, use docs/VCENTER-FIRST-RUN.md and docs/COMMUNITY-TESTING.md. Do not execute real queries merely to reproduce a screenshot. DNS remains WhatIf-only, excluded from the central runner; even its read preview requires separate authorization in a real environment. WhatIf on the central runner suppresses HTML creation only, not read queries. No example demonstrates or permits real infrastructure changes.
