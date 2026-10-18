# Offline unified reporting and scoped comparison

These tools process local data only. Neither script accepts a connection or invokes PowerCLI, connects to a server, changes TLS policy or installs modules. Existing report outputs are reused as plain data; no new VMware API contract or release compatibility is asserted. PowerShell 7.6.7 Linux x64 is the executed runtime; 7.4+ remains a source target only.

## Portable HTML

`New-vSphereHealthReport.ps1 -Data $data -OutputPath '<new-local-file.html>'` takes one structured object (PSCustomObject or dictionary) with:

| Property | Meaning |
|---|---|
| ScopeId | Required plain text identifying the intended endpoint scope; prefer an opaque fixture/private label |
| CapturedAt | Required timestamp with explicit offset, or typed UTC/local DateTime/DateTimeOffset |
| Completeness | Caller-declared Complete, Partial or Unknown; absent means Unknown |
| VMs | Optional array of Get-VMInventory rows; VMId available with -IncludeIdentity |
| Tools | Optional Get-VMwareToolsStatus rows; last-known guest information |
| Snapshots | Optional Get-SnapshotReport (-IncludeIdentity recommended) or Get-OldSnapshots rows |
| Datastores | Optional Get-DatastoreCapacity rows (GiB property names) |
| Hosts | Optional Get-VMHostHealth alarm-summary rows |
| Ntp | Optional Get-VMHostNtpConfiguration rows |
| Certificates | Optional Get-VMCertificateExpiry machine SSL date rows |

The seven collections must be explicit arrays when supplied. Missing/null collections mean Unknown; `@()` means zero supplied rows. Missing scalar values are Unknown. Row counts are provided counts, not proof of complete visible infrastructure. Duplicate known identities within a section fail; incomplete identity fields remain Unknown and cannot establish uniqueness. Names do not substitute for IDs. The report does not join different identity namespaces between sections or reconcile observations captured at different instants.

VM summary totals use supplied CPU/memory only if every contributing value is known; otherwise the aggregate is Unknown. States outside PoweredOn/PoweredOff/Suspended count as Unknown. Numeric values must be typed, finite and nonnegative; CPU is a positive integer and memory positive when present. Inaccessible/unknown-access datastores have Unknown measurements. Used space and percentage are derived from capacity/free; percentages for zero capacity remain Unknown.

Snapshot age is recomputed from CreatedUtc (old-snapshot model) or Created (snapshot-report model), and optional SizeGiB/SizeGB is validated. Certificate dates use NotBeforeUtc/NotAfterUtc; date status is recomputed, ignoring any supplied trust assertion. Missing dates remain Unknown, and TrustVerified is always false. Host alarm summaries do not evaluate hardware; NTP configuration does not evaluate synchronization. Nothing infers success or health from missing data.

`-AsOf` optionally sets the evaluation instant; default is CapturedAt, making identical inputs reproducible. String timestamps must be ISO 8601 with seconds and Z or an explicit offset. Typed DateTime with unspecified Kind is rejected rather than assuming a time zone. Future snapshots relative to AsOf, reversed certificate intervals and invalid measurements fail before writing. Capture metadata is supplied by the caller and does not prove freshness or collection integrity.

All dynamic HTML is encoded with .NET HtmlEncode. Fixed inline CSS, no JavaScript, CDN, external assets or telemetry; a restrictive CSP provides an additional safeguard. Only allowlisted scalar columns are read. Extra properties such as tokens, credentials and raw provider responses are ignored; credential/secure-string/nested objects in visible scalar columns fail. Never place secrets in names/labels: arbitrary secret strings cannot be reliably recognized as such. Names and IDs remain potentially private; the report is not an anonymizer. Use trusted deserialized data; custom object getters are executable PowerShell behavior, not a sandboxed file format.

The tool writes a new UTF-8 file using CreateNew, refuses overwriting and symlink output parents, and requires an existing local directory. WhatIf creates no file or receipt. Unix files start with mode 0600; Windows requires an appropriate parent ACL. Network mounts are not universally detectable; use a trusted local directory outside Git. All validation/rendering happens before writing. A failed write emits no success receipt and attempts removal of the incomplete new file; process crashes or filesystem failures can still leave a partial artifact. There is no overwrite switch: use a new filename. Receipt means completed local rendering, never a successful VMware health check.

## Scoped inventory comparison

`Compare-vSphereInventory.ps1 -Baseline $before -Current $after` requires both envelopes:

```powershell
$before = [pscustomobject]@{
    ScopeId='fixture-endpoint-01'
    IdentityKind='PowerCliId'
    SelectionId='all-visible-vms-v1'
    CapturedAt=[datetimeoffset]'2026-10-16T00:00:00Z'
    Completeness='Complete'
    VMs=@() # explicit, including an empty capture
}
```

Current has the same schema. Each VM row requires VMId, with optional VM, NumCpu, MemoryGB and PowerState. Get-VMInventory now supports opt-in IncludeIdentity; its default output is preserved. Choose IdentityKind PowerCliId for those IDs, or MoRefValue for SDK-view values. These are different namespaces and are not converted or guessed. ScopeId, IdentityKind and SelectionId must match exactly. IDs are case-sensitive within that declared scope; duplicate IDs fail. Display-name changes do not break matching and are not separately reported as renames.

ScopeId must represent the same persistent endpoint identity namespace, not merely a hostname that might be reused. A vCenter rebuild/restore or migration to another vCenter can invalidate MoRefs. SelectionId must describe the same filter, account visibility and collection policy; reuse only after verifying equivalence. Do not compare direct ESXi IDs with vCenter IDs. Cross-vCenter matching is deliberately blocked; a separate, verified mapping is needed, and VM names alone are insufficient. Incorrect caller labels cannot be independently detected offline.

| Result | Interpretation |
|---|---|
| Added | Current-only ID; baseline is declared Complete for this selection |
| Removed | Baseline-only ID; current is declared Complete for this selection |
| PresenceUnknown | One-sided ID, but the opposite capture is Partial or Unknown |
| Changed | Shared ID with two valid comparable values differing in CPU, memory or power state |
| NotComparable | Shared ID has an absent measure or absent/unrecognized power state on either side |

Unchanged comparable fields produce no rows. Power states are compared case-insensitively among PoweredOn/PoweredOff/Suspended. Missing values are never treated as zero, and invalid typed values fail. Both captures must have valid timestamps; reversed chronology fails, equivalent instants with different offsets compare identically. Times are normalized to UTC in results, not used to infer an inventory change. No changes is not proof of successful complete collection.

Outputs are flat PowerShell objects: ScopeId, VMId, VM, Change, Field, Before, After, BaselineCapturedAt, CurrentCapturedAt. Extra source fields are omitted. All rows validate and buffer before publication. Optional CsvPath creates a new UTF-8 CSV (including headers for no changes), never overwriting. WhatIf suppresses CSV creation but still returns the computed comparison objects. Text starting with spreadsheet formula prefixes, including leading whitespace/control characters, gets an apostrophe in the generated CSV only; raw returned objects are unchanged. If using Export-Csv yourself, apply appropriate spreadsheet protection separately. A CSV write failure produces no comparison rows. This reduces common formula injection, not all spreadsheet-import risks.

## Future explicit collection integration

No live collector was added. After separate authorization, a caller can collect each existing tool with an explicitly supplied single Server, capture timestamps, and place returned plain arrays in the schema above. Every source call must use -Server $connection -ErrorAction Stop -WarningAction Stop. Do not store the connection/credential object in the envelope. Capture each section's provenance privately and label completeness conservatively; suppress failed sections as Unknown, never as successful empty arrays. Do not infer multi-section transactional consistency.

For comparison, collect Get-VMInventory -IncludeIdentity and wrap it with verified persistent ScopeId/IdentityKind/SelectionId. For display, use each script's existing output directly; certificate availability is optional and its current direct-ESXi guard remains in effect. No original lab runner path is changed. Future integration must preserve explicit authorization, normal TLS verification, memory-only credentials, read-only behavior and private output paths.

## Reproduction without infrastructure

Run `examples/Invoke-UnifiedOfflineExample.ps1 -OutputDirectory '<existing-private-local-directory>'` using a new directory or new filenames. It loads only bundled fabricated JSON, creates HTML and CSV, and never imports PowerCLI. Or run `Invoke-Pester ./tests/UnifiedReporting.Tests.ps1`. Fixtures use example.invalid, documentation IPs and fictitious IDs. The comparison fixture yields five rows: Added 1, Removed 1, Changed 3. The HTML fixture has one provided VM, snapshot age 16 elapsed days and one datastore at 75 percent used at its captured reference instant. This is local processing evidence, not functional VMware validation.

## Optional ESXi audit sections

The offline envelope may additionally contain HostSecurity, HostFirewall, HostSyslog, HostTime and HostAdvancedSettings arrays, using the corresponding ESXi observation output rows. A property absent from the envelope adds no section; a present null adds an Unknown section, and an empty array displays zero supplied records. All older inputs retain their seven-section behavior. Assessment and verification flags are forced to NotEvaluated/false, and setting values are rechecked against the bounded profile even if a caller labels them Reported. See ESXI-AUDIT-CONTRACTS.md for the field contracts, withholding limits and absence of vulnerability/compliance claims. No live collection is added.

## Optional central-execution metadata

ToolkitOutcome and ToolkitExecution may accompany the existing envelope. The latter is an array of Check, Requested, Status, RowCount and Reason records; an optional encoded status table displays Completed/Empty/Incomplete/Failed/NotRun and a visible overall outcome. Absent metadata leaves old HTML inputs unchanged. Invoke-VMwareToolkit constructs this envelope from fixed read-only tools, keeping missing/failed datasets null and successful empty datasets as arrays. Rendering a partial run does not turn it into a successful execution. See CENTRAL-RUNNER.md for the runtime contract and separate local-file status.

## Presentation

Executive counts distinguish sections with supplied rows, explicitly empty arrays and missing collections. These counts do not establish field completeness or health. Local section anchors, keyboard-focusable bounded table regions, sticky headings, alternating rows, mobile spacing and print layout improve large-inventory use without JavaScript. Toolkit execution shows both legacy Status and derived State; input State is not trusted. CSP, escaping and exclusive local file creation remain unchanged.

## VCF sections

Optional VCFLifecycle, VCFOperationsAlerts and VCFLicensing arrays render separately with explicit Source/SourceVersion/Endpoint. Sources must match their respective models; raw timestamps and unallowlisted owner/license data are omitted, and Assessment is forced Unknown. Example and schema restrictions: VCF-API-MATRIX.md. No automatic connection, cross-source health score or old-envelope change.
